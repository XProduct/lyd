using FlacPlayer.Model;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;
using System.Timers;

namespace FlacPlayer.Design
{
    public class DesignPlayer : IPlayer
    {
        public long GetCurrentSongDuration()
        {
            throw new NotImplementedException();
        }

        public long GetCurrentSongPlayTime()
        {
            throw new NotImplementedException();
        }

        public bool IsFinished()
        {
            return false;
        }

        public bool IsPlaying()
        {
            return true;
        }

        public void Pause()
        {
            throw new NotImplementedException();
        }

        public void Play(string filepath = null)
        {
            throw new NotImplementedException();
        }

        public void SetPlayPosition(int seconds)
        {
            throw new NotImplementedException();
        }
    }
}
