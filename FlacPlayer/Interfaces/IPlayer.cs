namespace FlacPlayer.Model
{
    public interface IPlayer
    {
        void Play(string filepath = null);
        void Pause();
        long GetCurrentSongDuration();
        long GetCurrentSongPlayTime();
        bool IsPlaying();
        bool IsFinished();
        void SetPlayPosition(int seconds);
        double GetVolume();
        void SetVolume(double level);
    }
}