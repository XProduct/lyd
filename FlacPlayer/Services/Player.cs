using IrrKlang;
using System;
using System.Diagnostics;

namespace FlacPlayer.Model
{
    public sealed class Player : IPlayer, IDisposable
    {
        ISoundEngine engine;
        Stopwatch playerStopWatch = new Stopwatch();
        ISound currentSound;
        bool IsPlaying = false;
        double _volume = 1.0;

        public Player()
        {
            engine = new ISoundEngine();
            engine.SoundVolume = 1.0f;
        }

        public void Play(string filename = null)
        {
            if (filename == null)
            {
                playerStopWatch.Start();
                engine.SetAllSoundsPaused(false);
            }
            else
            {
                playerStopWatch.Restart();
                engine.StopAllSounds();
                currentSound = engine.Play2D(filename);
                if (currentSound != null)
                {
                    currentSound.Volume = (float)_volume;
                }
            }
            IsPlaying = true;
        }

        public void Pause()
        {
            playerStopWatch.Stop();
            engine.SetAllSoundsPaused(true);
            IsPlaying = false;
        }

        public void Stop()
        {
            playerStopWatch.Reset();
            engine.StopAllSounds();
            currentSound = null;
            IsPlaying = false;
        }

        public long GetCurrentSongDuration()
        {
            return currentSound != null ? currentSound.PlayLength : 0;
        }

        public long GetCurrentSongPlayTime()
        {
            // irrKlang PlayPosition is milliseconds. Do not gate on the stopwatch —
            // that returned -1 at the start of play and made the F1 timeline lie.
            if (currentSound != null)
            {
                return currentSound.PlayPosition;
            }
            return -1;
        }

        public void SetPlayPosition(int seconds)
        {
            SetPlayPositionMs(seconds * 1000L);
        }

        public void SetPlayPositionMs(long positionMs)
        {
            if (currentSound == null)
            {
                return;
            }
            if (positionMs < 0)
            {
                positionMs = 0;
            }
            currentSound.PlayPosition = (uint)positionMs;
        }

        public double GetVolume()
        {
            return _volume;
        }

        public void SetVolume(double level)
        {
            if (level < 0) level = 0;
            if (level > 1) level = 1;
            _volume = level;
            engine.SoundVolume = (float)_volume;
            if (currentSound != null)
            {
                currentSound.Volume = (float)_volume;
            }
        }

        bool IPlayer.IsPlaying()
        {
            return IsPlaying;
        }

        public bool IsFinished()
        {
            return currentSound == null ? false : currentSound.Finished;
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
        }
    }
}