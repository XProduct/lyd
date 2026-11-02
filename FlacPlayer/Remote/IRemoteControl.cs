namespace FlacPlayer.Remote
{
    public interface IRemoteControl
    {
        string DisplayName { get; }
        LibraryDto GetLibrary();
        /// <summary>Current monotonic library revision (cheap; no catalog build).</summary>
        int GetLibraryRevision();
        PlaybackStateDto GetPlaybackState();
        void PlaySong(string songId);
        void PlayAlbum(string albumId);
        void Pause();
        void PlayPause();
        void Next();
        void Previous();
        void SetShuffle(bool? enabled);
        void Seek(long positionMs);
        void SetVolume(double level);
        /// <summary>Set where audio renders: "host" or a remote device id (E1).</summary>
        void SetOutput(string deviceId, string deviceName);
        bool TryGetAlbumCover(string albumId, out byte[] bytes, out string contentType);
        /// <summary>Resolve a song id to its on-disk path for streaming.</summary>
        bool TryGetSongPath(string songId, out string path);
    }
}
