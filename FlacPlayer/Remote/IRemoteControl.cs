namespace FlacPlayer.Remote
{
    public interface IRemoteControl
    {
        string DisplayName { get; }
        LibraryDto GetLibrary();
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
        bool TryGetAlbumCover(string albumId, out byte[] bytes, out string contentType);
    }
}