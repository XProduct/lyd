using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

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
    }
}
