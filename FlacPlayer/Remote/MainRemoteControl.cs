using System;
using FlacPlayer.ViewModel;

namespace FlacPlayer.Remote
{
    /// <summary>
    /// Thin adapter so the HTTP host depends on IRemoteControl, not the WPF view-model type.
    /// </summary>
    public sealed class MainRemoteControl : IRemoteControl
    {
        private readonly MainViewModel _vm;

        public MainRemoteControl(MainViewModel vm)
        {
            _vm = vm;
        }

        public string DisplayName
        {
            get { return _vm.RemoteDisplayName; }
        }

        public LibraryDto GetLibrary()
        {
            return _vm.BuildRemoteLibrary();
        }

        public int GetLibraryRevision()
        {
            return _vm.GetLibraryRevision();
        }

        public PlaybackStateDto GetPlaybackState()
        {
            return _vm.BuildRemotePlaybackState();
        }

        public void PlaySong(string songId)
        {
            _vm.RemotePlaySong(songId);
        }

        public void PlayAlbum(string albumId)
        {
            _vm.RemotePlayAlbum(albumId);
        }

        public void Pause()
        {
            _vm.RemotePause();
        }

        public void PlayPause()
        {
            _vm.RemotePlayPause();
        }

        public void Next()
        {
            _vm.RemoteNext();
        }

        public void Previous()
        {
            _vm.RemotePrevious();
        }

        public void SetShuffle(bool? enabled)
        {
            _vm.RemoteSetShuffle(enabled);
        }

        public void Seek(long positionMs)
        {
            _vm.RemoteSeek(positionMs);
        }

        public void SetVolume(double level)
        {
            _vm.RemoteSetVolume(level);
        }

        public bool TryGetAlbumCover(string albumId, out byte[] bytes, out string contentType)
        {
            return _vm.TryGetRemoteAlbumCover(albumId, out bytes, out contentType);
        }
    }
}