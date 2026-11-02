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
        bool TryGetAlbumCover(string albumId, out byte[] bytes, out string contentType);
        /// <summary>Phase E: absolute path for streaming original file bytes.</summary>
        bool TryGetSongFilePath(string songId, out string path, out string contentType);
        /// <summary>Phase E legacy: "host" keeps irrKlang; "remote" silences host while session continues.</summary>
        void SetAudioOutput(string target, string deviceId, string deviceName);
        /// <summary>Phase E: multi-select Playing on targets (deviceId "host" and/or player ids).</summary>
        void SetAudioOutputs(System.Collections.Generic.IList<PlaybackOutputTargetDto> targets);
        /// <summary>Phase E: output device reports playhead for host UI / other remotes.</summary>
        void ApplyPlaybackHeartbeat(string deviceId, long positionMs, long? durationMs, string songId);
        void RegisterPlayer(string deviceId, string name, string platform, string[] capabilities);
        void UnregisterPlayer(string deviceId);
        System.Collections.Generic.IList<PlayerDto> GetPlayers();
    }
}