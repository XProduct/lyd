using System;
using System.IO;
using System.Net;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using Newtonsoft.Json;

namespace FlacPlayer.Remote
{
    public sealed class LydApiServer : IDisposable
    {
        private readonly IRemoteControl _control;
        private HttpListener _listener;
        private CancellationTokenSource _cts;
        private Task _loop;
        public int Port { get; private set; }
        public bool IsRunning { get; private set; }

        public LydApiServer(IRemoteControl control)
        {
            _control = control;
        }

        public string BoundPrefix { get; private set; }

        public void Start(int port)
        {
            Stop();
            Port = port;

            Exception lastError = null;
            string[] candidates = BuildPrefixCandidates(port);
            foreach (string prefix in candidates)
            {
                try
                {
                    _listener = new HttpListener();
                    _listener.Prefixes.Add(prefix);
                    _listener.Start();
                    BoundPrefix = prefix;
                    lastError = null;
                    break;
                }
                catch (Exception ex)
                {
                    lastError = ex;
                    try { if (_listener != null) { _listener.Close(); } } catch { }
                    _listener = null;
                }
            }

            if (_listener == null || !_listener.IsListening)
            {
                throw lastError ?? new InvalidOperationException("HttpListener failed to start.");
            }

            _cts = new CancellationTokenSource();
            _loop = Task.Run(() => ListenLoop(_cts.Token));
            IsRunning = true;
        }

        private static string[] BuildPrefixCandidates(int port)
        {
            var list = new System.Collections.Generic.List<string>();
            // Strong wildcard: HTTP.sys dual-stack (IPv4 + IPv6) when URL ACL allows it.
            list.Add("http://+:" + port + "/");
            // Explicit IPv6 any (separate ACL on some Windows builds).
            list.Add("http://[::]:" + port + "/");
            try
            {
                foreach (var ip in Dns.GetHostAddresses(Dns.GetHostName()))
                {
                    if (ip.AddressFamily == System.Net.Sockets.AddressFamily.InterNetwork)
                    {
                        list.Add("http://" + ip + ":" + port + "/");
                    }
                    else if (ip.AddressFamily == System.Net.Sockets.AddressFamily.InterNetworkV6
                        && !ip.IsIPv6LinkLocal
                        && !IPAddress.IsLoopback(ip))
                    {
                        list.Add("http://[" + ip + "]:" + port + "/");
                    }
                }
            }
            catch { }
            list.Add("http://127.0.0.1:" + port + "/");
            list.Add("http://[::1]:" + port + "/");
            list.Add("http://localhost:" + port + "/");
            return list.ToArray();
        }

        /// <summary>Build an absolute URL using the request authority (IPv6 hosts already bracketed by Uri).</summary>
        internal static string AbsoluteApiUrl(HttpListenerRequest request, string absolutePath)
        {
            if (request == null || request.Url == null)
            {
                return absolutePath;
            }
            string authority = request.Url.GetLeftPart(UriPartial.Authority).TrimEnd('/');
            if (!absolutePath.StartsWith("/"))
            {
                absolutePath = "/" + absolutePath;
            }
            return authority + absolutePath;
        }

        private static void AbsolutizeCoverUrls(HttpListenerRequest request, LibraryDto library)
        {
            if (library == null || library.Albums == null)
            {
                return;
            }
            foreach (AlbumDto album in library.Albums)
            {
                if (album == null || string.IsNullOrEmpty(album.CoverUrl))
                {
                    continue;
                }
                if (album.CoverUrl.StartsWith("http://", StringComparison.OrdinalIgnoreCase)
                    || album.CoverUrl.StartsWith("https://", StringComparison.OrdinalIgnoreCase))
                {
                    continue;
                }
                album.CoverUrl = AbsoluteApiUrl(request, album.CoverUrl);
            }
        }

        public void Stop()
        {
            IsRunning = false;
            try
            {
                if (_cts != null)
                {
                    _cts.Cancel();
                }
            }
            catch { }
            try
            {
                if (_listener != null && _listener.IsListening)
                {
                    _listener.Stop();
                }
            }
            catch { }
            try
            {
                if (_listener != null)
                {
                    _listener.Close();
                }
            }
            catch { }
            _listener = null;
            _cts = null;
            _loop = null;
        }

        private async Task ListenLoop(CancellationToken token)
        {
            while (!token.IsCancellationRequested && _listener != null && _listener.IsListening)
            {
                HttpListenerContext context;
                try
                {
                    context = await _listener.GetContextAsync().ConfigureAwait(false);
                }
                catch (ObjectDisposedException)
                {
                    break;
                }
                catch (HttpListenerException)
                {
                    break;
                }
                catch (Exception)
                {
                    continue;
                }

                ThreadPool.QueueUserWorkItem(_ => HandleRequest(context));
            }
        }

        private void HandleRequest(HttpListenerContext context)
        {
            try
            {
                string method = context.Request.HttpMethod.ToUpperInvariant();
                string path = context.Request.Url.AbsolutePath.TrimEnd('/');
                if (string.IsNullOrEmpty(path))
                {
                    path = "/";
                }

                if (method == "GET" && path == "/api/v1/health")
                {
                    WriteJson(context, 200, new HealthDto
                    {
                        Name = _control.DisplayName,
                        Version = typeof(LydApiServer).Assembly.GetName().Version.ToString(),
                        Api = 1,
                        Port = Port
                    });
                    return;
                }

                if (method == "GET" && (path == "/api/v1/library" || path == "/api/v1/songs" || path == "/api/v1/albums"))
                {
                    LibraryDto library = _control.GetLibrary();
                    AbsolutizeCoverUrls(context.Request, library);
                    if (path == "/api/v1/songs")
                    {
                        WriteJson(context, 200, new { songs = library.Songs, revision = library.Revision });
                    }
                    else if (path == "/api/v1/albums")
                    {
                        WriteJson(context, 200, new { albums = library.Albums, revision = library.Revision });
                    }
                    else
                    {
                        WriteJson(context, 200, library);
                    }
                    return;
                }

                if (method == "GET" && path.StartsWith("/api/v1/albums/", StringComparison.OrdinalIgnoreCase) && path.EndsWith("/cover", StringComparison.OrdinalIgnoreCase))
                {
                    string albumId = path.Substring("/api/v1/albums/".Length);
                    albumId = albumId.Substring(0, albumId.Length - "/cover".Length);
                    byte[] bytes;
                    string contentType;
                    if (_control.TryGetAlbumCover(albumId, out bytes, out contentType) && bytes != null)
                    {
                        WriteBytes(context, 200, contentType, bytes);
                    }
                    else
                    {
                        WriteJson(context, 404, new { error = "cover_not_found" });
                    }
                    return;
                }

                if (method == "GET" && path == "/api/v1/playback/state")
                {
                    WriteJson(context, 200, _control.GetPlaybackState());
                    return;
                }

                if (method == "POST" && path == "/api/v1/playback/play")
                {
                    var body = ReadJson<PlayRequest>(context);
                    if (body == null || string.IsNullOrEmpty(body.SongId))
                    {
                        WriteJson(context, 400, new { error = "songId_required" });
                        return;
                    }
                    InvokeOnUi(() => _control.PlaySong(body.SongId));
                    WriteJson(context, 200, new { ok = true });
                    return;
                }

                if (method == "POST" && path == "/api/v1/playback/play-album")
                {
                    var body = ReadJson<PlayAlbumRequest>(context);
                    if (body == null || string.IsNullOrEmpty(body.AlbumId))
                    {
                        WriteJson(context, 400, new { error = "albumId_required" });
                        return;
                    }
                    InvokeOnUi(() => _control.PlayAlbum(body.AlbumId));
                    WriteJson(context, 200, new { ok = true });
                    return;
                }

                if (method == "POST" && path == "/api/v1/playback/pause")
                {
                    InvokeOnUi(() => _control.Pause());
                    WriteJson(context, 200, new { ok = true });
                    return;
                }

                if (method == "POST" && path == "/api/v1/playback/playpause")
                {
                    InvokeOnUi(() => _control.PlayPause());
                    WriteJson(context, 200, new { ok = true });
                    return;
                }

                if (method == "POST" && path == "/api/v1/playback/next")
                {
                    InvokeOnUi(() => _control.Next());
                    WriteJson(context, 200, new { ok = true });
                    return;
                }

                if (method == "POST" && path == "/api/v1/playback/previous")
                {
                    InvokeOnUi(() => _control.Previous());
                    WriteJson(context, 200, new { ok = true });
                    return;
                }

                if (method == "POST" && path == "/api/v1/playback/shuffle")
                {
                    var body = ReadJson<ShuffleRequest>(context) ?? new ShuffleRequest();
                    InvokeOnUi(() => _control.SetShuffle(body.Enabled));
                    WriteJson(context, 200, new { ok = true });
                    return;
                }

                if (method == "POST" && path == "/api/v1/playback/seek")
                {
                    var body = ReadJson<SeekRequest>(context);
                    if (body == null)
                    {
                        WriteJson(context, 400, new { error = "positionMs_required" });
                        return;
                    }
                    InvokeOnUi(() => _control.Seek(body.PositionMs));
                    WriteJson(context, 200, new { ok = true });
                    return;
                }

                if (method == "POST" && path == "/api/v1/playback/volume")
                {
                    var body = ReadJson<VolumeRequest>(context);
                    if (body == null)
                    {
                        WriteJson(context, 400, new { error = "level_required" });
                        return;
                    }
                    InvokeOnUi(() => _control.SetVolume(body.Level));
                    WriteJson(context, 200, new { ok = true });
                    return;
                }

                if (path == "/" || path == "/api" || path == "/api/v1")
                {
                    WriteJson(context, 200, new
                    {
                        name = "Lyd Remote API",
                        api = "/api/v1",
                        health = "/api/v1/health"
                    });
                    return;
                }

                WriteJson(context, 404, new { error = "not_found", path = path });
            }
            catch (Exception ex)
            {
                try
                {
                    WriteJson(context, 500, new { error = "server_error", message = ex.Message });
                }
                catch
                {
                }
            }
        }

        private static void InvokeOnUi(Action action)
        {
            var app = System.Windows.Application.Current;
            if (app != null && !app.Dispatcher.CheckAccess())
            {
                app.Dispatcher.Invoke(action);
            }
            else
            {
                action();
            }
        }

        private static T ReadJson<T>(HttpListenerContext context)
        {
            using (var reader = new StreamReader(context.Request.InputStream, context.Request.ContentEncoding ?? Encoding.UTF8))
            {
                string json = reader.ReadToEnd();
                if (string.IsNullOrWhiteSpace(json))
                {
                    return default(T);
                }
                return JsonConvert.DeserializeObject<T>(json);
            }
        }

        private static void WriteJson(HttpListenerContext context, int status, object body)
        {
            byte[] bytes = Encoding.UTF8.GetBytes(JsonConvert.SerializeObject(body));
            WriteBytes(context, status, "application/json; charset=utf-8", bytes);
        }

        private static void WriteBytes(HttpListenerContext context, int status, string contentType, byte[] bytes)
        {
            context.Response.StatusCode = status;
            context.Response.ContentType = contentType;
            context.Response.ContentLength64 = bytes.LongLength;
            context.Response.OutputStream.Write(bytes, 0, bytes.Length);
            context.Response.OutputStream.Close();
        }

        public void Dispose()
        {
            Stop();
        }
    }
}