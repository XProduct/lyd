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

                if (method == "GET" && (path == "/api/v1/playback/state" || path == "/api/v1/playback/session"))
                {
                    WriteJson(context, 200, _control.GetPlaybackState());
                    return;
                }

                if ((method == "GET" || method == "HEAD") && path.StartsWith("/api/v1/stream/songs/", StringComparison.OrdinalIgnoreCase))
                {
                    string songId = Uri.UnescapeDataString(path.Substring("/api/v1/stream/songs/".Length));
                    HandleSongStream(context, songId, headOnly: method == "HEAD");
                    return;
                }

                if (method == "POST" && path == "/api/v1/playback/output")
                {
                    var body = ReadJson<OutputRequest>(context) ?? new OutputRequest();
                    InvokeOnUi(() => _control.SetOutput(body));
                    WriteJson(context, 200, _control.GetPlaybackState());
                    return;
                }

                if (method == "GET" && path == "/api/v1/players")
                {
                    PlaybackStateDto state = _control.GetPlaybackState();
                    WriteJson(context, 200, new
                    {
                        players = _control.ListPlayers(),
                        AllowMultiOutput = state != null && state.AllowMultiOutput
                    });
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
                    RegisteredPlayerDto registered = null;
                    InvokeOnUi(() => registered = _control.RegisterPlayer(body));
                    WriteJson(context, 200, registered);
                    return;
                }

                // Apple posts /playback/heartbeat; also accept /players/heartbeat.
                if (method == "POST" && (path == "/api/v1/players/heartbeat" || path == "/api/v1/playback/heartbeat"))
                {
                    var body = ReadJson<PlayerHeartbeatRequest>(context) ?? new PlayerHeartbeatRequest();
                    if (string.IsNullOrEmpty(body.DeviceId))
                    {
                        WriteJson(context, 400, new { error = "deviceId_required" });
                        return;
                    }
                    InvokeOnUi(() => _control.ReportPlayerHeartbeat(body.DeviceId, body.PositionMs, body.IsPlaying));
                    WriteJson(context, 200, _control.GetPlaybackState());
                    return;
                }

                if (method == "DELETE" && path.StartsWith("/api/v1/players/", StringComparison.OrdinalIgnoreCase))
                {
                    string deviceId = Uri.UnescapeDataString(path.Substring("/api/v1/players/".Length));
                    bool removed = false;
                    InvokeOnUi(() => removed = _control.UnregisterPlayer(deviceId));
                    WriteJson(context, removed ? 200 : 404, removed ? (object)new { ok = true } : new { error = "player_not_found" });
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

        private void HandleSongStream(HttpListenerContext context, string songId, bool headOnly = false)
        {
            string filePath;
            if (string.IsNullOrEmpty(songId) || !_control.TryGetSongPath(songId, out filePath) || !File.Exists(filePath))
            {
                WriteJson(context, 404, new { error = "song_not_found" });
                return;
            }

            string contentType = ContentTypeForAudioPath(filePath);
            long fileLength = new FileInfo(filePath).Length;
            long start = 0;
            long end = fileLength - 1;
            bool isPartial = false;

            string rangeHeader = context.Request.Headers["Range"];
            if (!string.IsNullOrEmpty(rangeHeader) && rangeHeader.StartsWith("bytes=", StringComparison.OrdinalIgnoreCase))
            {
                string spec = rangeHeader.Substring("bytes=".Length).Trim();
                int dash = spec.IndexOf('-');
                if (dash >= 0)
                {
                    string startText = spec.Substring(0, dash).Trim();
                    string endText = spec.Substring(dash + 1).Trim();
                    long parsedStart;
                    long parsedEnd;
                    if (startText.Length == 0 && long.TryParse(endText, out parsedEnd))
                    {
                        // suffix: bytes=-500
                        start = Math.Max(0, fileLength - parsedEnd);
                        end = fileLength - 1;
                        isPartial = true;
                    }
                    else if (long.TryParse(startText, out parsedStart))
                    {
                        start = parsedStart;
                        if (endText.Length > 0 && long.TryParse(endText, out parsedEnd))
                        {
                            end = parsedEnd;
                        }
                        isPartial = true;
                    }
                }
            }

            if (start < 0) start = 0;
            if (end >= fileLength) end = fileLength - 1;
            if (start > end || start >= fileLength)
            {
                context.Response.StatusCode = 416;
                context.Response.Headers["Content-Range"] = "bytes */" + fileLength;
                context.Response.ContentLength64 = 0;
                context.Response.OutputStream.Close();
                return;
            }

            long contentLength = end - start + 1;
            context.Response.StatusCode = isPartial ? 206 : 200;
            context.Response.ContentType = contentType;
            context.Response.Headers["Accept-Ranges"] = "bytes";
            if (isPartial)
            {
                context.Response.Headers["Content-Range"] = "bytes " + start + "-" + end + "/" + fileLength;
            }
            context.Response.ContentLength64 = contentLength;

            // HttpListener hangs if a body is written for HEAD — headers only.
            if (headOnly)
            {
                context.Response.OutputStream.Close();
                return;
            }

            const int bufferSize = 81920;
            byte[] buffer = new byte[bufferSize];
            using (var fs = new FileStream(filePath, FileMode.Open, FileAccess.Read, FileShare.ReadWrite))
            {
                fs.Seek(start, SeekOrigin.Begin);
                long remaining = contentLength;
                while (remaining > 0)
                {
                    int toRead = remaining > bufferSize ? bufferSize : (int)remaining;
                    int read = fs.Read(buffer, 0, toRead);
                    if (read <= 0)
                    {
                        break;
                    }
                    context.Response.OutputStream.Write(buffer, 0, read);
                    remaining -= read;
                }
            }
            context.Response.OutputStream.Close();
        }

        private static string ContentTypeForAudioPath(string path)
        {
            string ext = Path.GetExtension(path);
            if (string.IsNullOrEmpty(ext))
            {
                return "application/octet-stream";
            }
            switch (ext.ToLowerInvariant())
            {
                case ".flac": return "audio/flac";
                case ".mp3": return "audio/mpeg";
                case ".m4a":
                case ".mp4":
                case ".aac": return "audio/mp4";
                case ".wav": return "audio/wav";
                case ".ogg":
                case ".oga": return "audio/ogg";
                case ".wma": return "audio/x-ms-wma";
                case ".aiff":
                case ".aif": return "audio/aiff";
                case ".alac": return "audio/alac";
                default: return "application/octet-stream";
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
            bool headOnly = string.Equals(context.Request.HttpMethod, "HEAD", StringComparison.OrdinalIgnoreCase);
            if (!headOnly)
            {
                context.Response.OutputStream.Write(bytes, 0, bytes.Length);
            }
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
            // Writing a body on HEAD makes HttpListener hang (client expects headers only).
            bool headOnly = string.Equals(context.Request.HttpMethod, "HEAD", StringComparison.OrdinalIgnoreCase);
            if (!headOnly && bytes != null && bytes.Length > 0)
            {
                context.Response.OutputStream.Write(bytes, 0, bytes.Length);
            }
            context.Response.OutputStream.Close();
        }

        public void Dispose()
        {
            Stop();
        }
    }
}