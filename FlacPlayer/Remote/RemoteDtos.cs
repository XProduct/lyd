using System.Collections.Generic;

namespace FlacPlayer.Remote
{
    public sealed class HealthDto
    {
        public string Name { get; set; }
        public string Version { get; set; }
        public int Api { get; set; }
        public int Port { get; set; }
    }

    public sealed class LibraryDto
    {
        public List<SongDto> Songs { get; set; }
        public List<AlbumDto> Albums { get; set; }
        public int Revision { get; set; }
    }

    public sealed class SongDto
    {
        public string Id { get; set; }
        public string Title { get; set; }
        public string Artist { get; set; }
        public string Album { get; set; }
        public string AlbumId { get; set; }
        public int Track { get; set; }
        public int Disc { get; set; }
        public long? DurationMs { get; set; }
        /// <summary>Audio bitrate in kbps (TagLib).</summary>
        public double? Bitrate { get; set; }
        /// <summary>Sample rate in kHz (desktop stores AudioSampleRate / 1000).</summary>
        public double? SampleRate { get; set; }
        /// <summary>Bits per sample.</summary>
        public double? Depth { get; set; }
    }

    public sealed class AlbumDto
    {
        public string Id { get; set; }
        public string Title { get; set; }
        public string Artist { get; set; }
        public List<string> SongIds { get; set; }
        public string CoverUrl { get; set; }
    }

    public sealed class PlaybackStateDto
    {
        public bool IsPlaying { get; set; }
        public bool Shuffle { get; set; }
        public long PositionMs { get; set; }
        public long DurationMs { get; set; }
        public string CurrentSongId { get; set; }
        public SongDto CurrentSong { get; set; }
        public double Volume { get; set; }

        /// <summary>Stable session id for this host process (one session per host in v1).</summary>
        public string SessionId { get; set; }

        /// <summary>
        /// Legacy single output id. When remotes are selected, prefer a remote id so Apple
        /// ``outputDeviceId == myDeviceId`` checks succeed; use <see cref="OutputDeviceIds"/> for multi.
        /// </summary>
        public string OutputDeviceId { get; set; }

        /// <summary>Legacy single output display name.</summary>
        public string OutputDeviceName { get; set; }

        /// <summary>
        /// Phase E Apple contract: "host" | "remote" | "multi"
        /// (remote = Apple-only; multi = host + at least one Apple device).
        /// </summary>
        public string OutputTarget { get; set; }

        /// <summary>
        /// Apple multi-select Playing on set (<c>deviceId</c> + <c>deviceName</c>).
        /// Preferred over legacy single fields; never empty on the wire.
        /// </summary>
        public OutputTargetDto[] OutputTargets { get; set; }

        /// <summary>All devices currently selected to render audio (host + Apple players). Never empty.</summary>
        public string[] OutputDeviceIds { get; set; }

        /// <summary>Selected outputs with display names — who is (allowed to be) playing.</summary>
        public OutputDeviceDto[] OutputDevices { get; set; }

        /// <summary>Relative stream URL for the current song, when available.</summary>
        public string StreamUrl { get; set; }

        /// <summary>
        /// Monotonic transport command sequence. Apple players apply host play/pause/next/seek/shuffle
        /// when this value changes (command fan-out via shared session poll).
        /// </summary>
        public long TransportSeq { get; set; }

        /// <summary>Bumped on seek / track start so Apple AVPlayer re-seeks (Phase E Apple field).</summary>
        public long SeekGeneration { get; set; }

        /// <summary>
        /// Phase F1 host timeline: UTC unix ms when <see cref="PositionAtAnchorMs"/> was sampled.
        /// Clients derive desired position = PositionAtAnchorMs + (now − AnchorUnixMs) while playing.
        /// </summary>
        public long AnchorUnixMs { get; set; }

        /// <summary>Song position (ms) at <see cref="AnchorUnixMs"/>.</summary>
        public long PositionAtAnchorMs { get; set; }

        /// <summary>
        /// Host’s current timeline estimate at serialize time (same as PositionAtAnchorMs when
        /// the anchor is refreshed on each state build).
        /// </summary>
        public long TimelineMs { get; set; }
    }

    public sealed class OutputDeviceDto
    {
        public string DeviceId { get; set; }
        public string Name { get; set; }
        public bool IsHost { get; set; }
    }

    /// <summary>Apple multi Playing on entry — property names match Swift <c>PlaybackOutputTargetDto</c>.</summary>
    public sealed class OutputTargetDto
    {
        public string DeviceId { get; set; }
        public string DeviceName { get; set; }
    }

    public sealed class RegisteredPlayerDto
    {
        public string DeviceId { get; set; }
        public string Name { get; set; }
        public string Platform { get; set; }
        public string[] Capabilities { get; set; }
        public bool IsOutput { get; set; }
        public long LastSeenUnixMs { get; set; }
    }

    public sealed class PlayerRegisterRequest
    {
        public string DeviceId { get; set; }
        public string Name { get; set; }
        public string Platform { get; set; }
        public string[] Capabilities { get; set; }
    }

    public sealed class PlayerHeartbeatRequest
    {
        public string DeviceId { get; set; }
        /// <summary>Optional position report from the rendering Apple player.</summary>
        public long? PositionMs { get; set; }
        public long? DurationMs { get; set; }
        public string SongId { get; set; }
        public bool? IsPlaying { get; set; }
    }

    public sealed class PlayRequest
    {
        public string SongId { get; set; }
    }

    public sealed class PlayAlbumRequest
    {
        public string AlbumId { get; set; }
    }

    public sealed class SeekRequest
    {
        public long PositionMs { get; set; }
    }

    public sealed class VolumeRequest
    {
        public double Level { get; set; }
    }

    public sealed class ShuffleRequest
    {
        public bool? Enabled { get; set; }
    }

    /// <summary>POST /api/v1/playback/output — explicit multi-select of who renders audio.</summary>
    public sealed class OutputRequest
    {
        /// <summary>Apple E1 field: "host" | "remote".</summary>
        public string Target { get; set; }

        /// <summary>Legacy / Apple single id ("host" or a client device id).</summary>
        public string DeviceId { get; set; }
        public string DeviceName { get; set; }

        /// <summary>
        /// Apple multi-select body (preferred): <c>{ "targets": [{ "deviceId", "deviceName" }] }</c>.
        /// When present (even empty), wins over legacy single-target fields.
        /// </summary>
        public OutputTargetDto[] Targets { get; set; }

        /// <summary>Multi-select device ids. Example: ["host","ipad-1"].</summary>
        public string[] DeviceIds { get; set; }

        /// <summary>Optional multi-select with display names.</summary>
        public OutputDeviceDto[] Devices { get; set; }
    }
}
