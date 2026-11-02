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
            // Strong wildcard: HTTP.sys dual-stack when URL ACL allows it.
            list.Add("http://+:" + port + "/");
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
                        && !ip.IsIPv6LinkLocal)
                    {
                        list.Add("http://[" + ip + "]:" + port + "/");
                    }
                }
            }
            catch { }
            list.Add("http://127.0.0.1:" + port + "/");
            list.Add("http://localhost:" + port + "/");
            return list.ToArray();
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

                if (method == "GET" && path == "/api/v1/library/revision")
                {
                    int rev = _control.GetLibraryRevision();
                    WriteJsonWithEtag(context, 200, new { revision = rev }, rev);
                    return;
                }

                if (method == "GET" && (path == "/api/v1/library" || path == "/api/v1/songs" || path == "/api/v1/albums"))
                {
                    int rev = _control.GetLibraryRevision();
                    if (ClientHasCurrentRevision(context, rev))
                    {
                        WriteNotModified(context, rev);
                        return;
                    }

                    LibraryDto library = _control.GetLibrary();
                    rev = library.Revision;
                    if (path == "/api/v1/songs")
                    {
                        WriteJsonWithEtag(context, 200, new { songs = library.Songs, revision = rev }, rev);
                    }
                    else if (path == "/api/v1/albums")
                    {
                        WriteJsonWithEtag(context, 200, new { albums = library.Albums, revision = rev }, rev);
                    }
                    else
                    {
                        WriteJsonWithEtag(context, 200, library, rev);
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

                // Phase E: original-file stream with HTTP Range (Apple AVPlayer).
                if (method == "GET" && path.StartsWith("/api/v1/stream/songs/", StringComparison.OrdinalIgnoreCase))
                {
                    string songId = path.Substring("/api/v1/stream/songs/".Length);
                    if (songId.EndsWith("/")) songId = songId.TrimEnd('/');
                    string filePath;
                    string contentType;
                    if (!_control.TryGetSongFilePath(songId, out filePath, out contentType) || string.IsNullOrEmpty(filePath))
                    {
                        WriteJson(context, 404, new { error = "song_not_found" });
                        return;
                    }
                    WriteFileWithRange(context, filePath, contentType);
                    return;
                }

                if (method == "POST" && path == "/api/v1/playback/output")
                {
                    var body = ReadJson<PlaybackOutputRequest>(context) ?? new PlaybackOutputRequest();
                    if (body.Targets != null && body.Targets.Count > 0)
                    {
                        InvokeOnUi(() => _control.SetAudioOutputs(body.Targets));
                        WriteJson(context, 200, new { ok = true, targets = body.Targets });
                    }
                    else
                    {
                        string target = string.IsNullOrWhiteSpace(body.Target) ? "host" : body.Target.Trim();
                        InvokeOnUi(() => _control.SetAudioOutput(target, body.DeviceId, body.DeviceName));
                        WriteJson(context, 200, new { ok = true, target = target, deviceId = body.DeviceId });
                    }
                    return;
                }

                if (method == "POST" && path == "/api/v1/playback/heartbeat")
                {
                    var body = ReadJson<PlaybackHeartbeatRequest>(context);
                    if (body == null || string.IsNullOrEmpty(body.DeviceId))
                    {
                        WriteJson(context, 400, new { error = "deviceId_required" });
                        return;
                    }
                    InvokeOnUi(() => _control.ApplyPlaybackHeartbeat(body.DeviceId, body.PositionMs, body.DurationMs, body.SongId));
                    WriteJson(context, 200, new { ok = true });
                    return;
                }

                if (method == "GET" && path == "/api/v1/players")
                {
                    WriteJson(context, 200, new { players = _control.GetPlayers() });
                    return;
                }

                if (method == "POST" && path == "/api/v1/players/register")
                {
                    var body = ReadJson<PlayerRegisterRequest>(context);
                    if (body == null || string.IsNullOrEmpty(body.DeviceId))
                    {
                        WriteJson(context, 400, new { error = "deviceId_required" });
                        return;
                    }
                    InvokeOnUi(() => _control.RegisterPlayer(body.DeviceId, body.Name, body.Platform, body.Capabilities));
                    WriteJson(context, 200, new { ok = true, deviceId = body.DeviceId });
                    return;
                }

                if (method == "DELETE" && path.StartsWith("/api/v1/players/", StringComparison.OrdinalIgnoreCase))
                {
                    string deviceId = path.Substring("/api/v1/players/".Length);
                    if (deviceId.EndsWith("/")) deviceId = deviceId.TrimEnd('/');
                    if (string.IsNullOrEmpty(deviceId))
                    {
                        WriteJson(context, 400, new { error = "deviceId_required" });
                        return;
                    }
                    InvokeOnUi(() => _control.UnregisterPlayer(deviceId));
                    WriteJson(context, 200, new { ok = true });
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

        private static bool ClientHasCurrentRevision(HttpListenerContext context, int currentRevision)
        {
            string ifNoneMatch = context.Request.Headers["If-None-Match"];
            if (!string.IsNullOrEmpty(ifNoneMatch))
            {
                string etag = FormatEtag(currentRevision);
                string[] parts = ifNoneMatch.Split(',');
                for (int i = 0; i < parts.Length; i++)
                {
                    string token = parts[i].Trim();
                    if (token == "*" || string.Equals(token, etag, StringComparison.Ordinal) ||
                        string.Equals(token, "W/" + etag, StringComparison.OrdinalIgnoreCase))
                    {
                        return true;
                    }
                }
            }

            string queryRev = context.Request.QueryString["revision"];
            int clientRevision;
            if (!string.IsNullOrEmpty(queryRev) && int.TryParse(queryRev, out clientRevision) &&
                clientRevision == currentRevision)
            {
                return true;
            }

            return false;
        }

        private static string FormatEtag(int revision)
        {
            return "\"" + revision.ToString(System.Globalization.CultureInfo.InvariantCulture) + "\"";
        }

        private static void WriteNotModified(HttpListenerContext context, int revision)
        {
            context.Response.StatusCode = 304;
            context.Response.Headers["ETag"] = FormatEtag(revision);
            context.Response.Headers["Cache-Control"] = "no-cache";
            context.Response.ContentLength64 = 0;
            context.Response.OutputStream.Close();
        }

        private static void WriteJsonWithEtag(HttpListenerContext context, int status, object body, int revision)
        {
            byte[] bytes = Encoding.UTF8.GetBytes(JsonConvert.SerializeObject(body));
            context.Response.StatusCode = status;
            context.Response.ContentType = "application/json; charset=utf-8";
            context.Response.Headers["ETag"] = FormatEtag(revision);
            context.Response.Headers["Cache-Control"] = "no-cache";
            context.Response.ContentLength64 = bytes.LongLength;
            context.Response.OutputStream.Write(bytes, 0, bytes.Length);
            context.Response.OutputStream.Close();
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

        /// <summary>Serve a media file with Accept-Ranges / Range support for AVPlayer.</summary>
        private static void WriteFileWithRange(HttpListenerContext context, string filePath, string contentType)
        {
            var info = new System.IO.FileInfo(filePath);
            long length = info.Length;
            context.Response.Headers["Accept-Ranges"] = "bytes";
            context.Response.ContentType = contentType;
            context.Response.Headers["Cache-Control"] = "no-cache";

            string rangeHeader = context.Request.Headers["Range"];
            long start = 0;
            long end = length - 1;
            if (!string.IsNullOrEmpty(rangeHeader) && rangeHeader.StartsWith("bytes=", StringComparison.OrdinalIgnoreCase))
            {
                string spec = rangeHeader.Substring("bytes=".Length).Trim();
                int dash = spec.IndexOf('-');
                if (dash >= 0)
                {
                    string startText = spec.Substring(0, dash);
                    string endText = spec.Substring(dash + 1);
                    long parsedStart;
                    long parsedEnd;
                    if (long.TryParse(startText, out parsedStart)) start = parsedStart;
                    if (long.TryParse(endText, out parsedEnd)) end = parsedEnd;
                    if (end >= length) end = length - 1;
                    if (start < 0) start = 0;
                    if (start > end || start >= length)
                    {
                        context.Response.StatusCode = 416;
                        context.Response.Headers["Content-Range"] = "bytes */" + length;
                        context.Response.ContentLength64 = 0;
                        context.Response.OutputStream.Close();
                        return;
                    }
                    context.Response.StatusCode = 206;
                    context.Response.Headers["Content-Range"] = "bytes " + start + "-" + end + "/" + length;
                }
                else
                {
                    context.Response.StatusCode = 200;
                }
            }
            else
            {
                context.Response.StatusCode = 200;
            }

            long count = end - start + 1;
            context.Response.ContentLength64 = count;
            using (var fs = new System.IO.FileStream(filePath, System.IO.FileMode.Open, System.IO.FileAccess.Read, System.IO.FileShare.Read))
            {
                fs.Seek(start, System.IO.SeekOrigin.Begin);
                var buffer = new byte[81920];
                long remaining = count;
                while (remaining > 0)
                {
                    int toRead = remaining > buffer.Length ? buffer.Length : (int)remaining;
                    int read = fs.Read(buffer, 0, toRead);
                    if (read <= 0) break;
                    context.Response.OutputStream.Write(buffer, 0, read);
                    remaining -= read;
                }
            }
            context.Response.OutputStream.Close();
        }

        public void Dispose()
        {
            Stop();
        }
    }
}