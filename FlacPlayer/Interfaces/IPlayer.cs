namespace FlacPlayer.Model
{
    public interface IPlayer
    {
        void Play(string filepath = null);
        void Pause();
        /// <summary>Stop all sounds and clear the current stream (used when output leaves the host).</summary>
        void Stop();
        long GetCurrentSongDuration();
        long GetCurrentSongPlayTime();
        bool IsPlaying();
        bool IsFinished();
        void SetPlayPosition(int seconds);
        /// <summary>Seek to an absolute playhead in milliseconds (seamless output handoff).</summary>
        void SetPlayPositionMs(long positionMs);
        double GetVolume();
        void SetVolume(double level);
    }
}