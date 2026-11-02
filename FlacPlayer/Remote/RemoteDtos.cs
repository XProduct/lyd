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
    }

    public sealed class PlayRequest
    {
        public string SongId { get; set; }
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
}