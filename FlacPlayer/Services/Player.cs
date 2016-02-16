using IrrKlang;
using System;
using System.Diagnostics;
using System.Timers;

namespace FlacPlayer.Model
{
    public sealed class Player : IPlayer, IDisposable
    {
        ISoundEngine engine;
        //Timer playTimer = new Timer();
        Stopwatch playerStopWatch = new Stopwatch();
        ISound currentSound;
        bool IsPlaying = false;

        public Player()
        {
            engine = new ISoundEngine();
        }

        public void Play(string filename = null)
        {
            if (filename == null)
            {
                playerStopWatch.Start();
                engine.SetAllSoundsPaused(false);
            }
            else {
                playerStopWatch.Restart();
                engine.StopAllSounds();
                currentSound = engine.Play2D(filename);
            }
            IsPlaying = true;
        }

        public void Pause()
        {
            playerStopWatch.Stop();
            engine.SetAllSoundsPaused(true);
            IsPlaying = false;
        }

        public long GetCurrentSongDuration()
        {
            return currentSound.PlayLength;
        }

        public long GetCurrentSongPlayTime()
        {
            return playerStopWatch.ElapsedMilliseconds;
        }

        public void SetPlayPosition(int seconds)
        {
            if (currentSound != null)
            {
                currentSound.PlayPosition = (uint)(seconds * 1000);
            }
        }

        bool IPlayer.IsPlaying()
        {
            return IsPlaying;
        }

        public void Dispose()
        {
            Dispose(true);
        }

        private void Dispose(bool isCleanAll)
        {
            if (isCleanAll)
            {
                engine.Dispose();
                GC.SuppressFinalize(this);
            }
            else
            {
                // Clean Managed Resources
            }
        }
    }
}
