using FlacPlayer.Model;

namespace FlacPlayer.Design
{
    public class DesignPlayer : IPlayer
    {
        public long GetCurrentSongDuration() { return 0; }
        public long GetCurrentSongPlayTime() { return 0; }
        public bool IsFinished() { return false; }
        public bool IsPlaying() { return true; }
        public void Pause() { }
        public void Stop() { }
        public void Play(string filepath = null) { }
        public void SetPlayPosition(int seconds) { }
        public void SetPlayPositionMs(long positionMs) { }
        public double GetVolume() { return 1.0; }
        public void SetVolume(double level) { }
    }
}