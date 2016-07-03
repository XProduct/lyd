using FlacPlayer.Model;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace FlacPlayer
{
    public static class HtmlData
    {
        public static List<Song> Songs = null;
        public static Song CurrentSong = null;
        public static event EventHandler<string> PlaySong;
        public static event EventHandler ShufflePlay;
        public static event EventHandler PlayPause;

        public static void OnPlaySong(string id)
        {
            PlaySong?.Invoke(null, id);
        }

        public static void OnShufflePlay()
        {
            ShufflePlay?.Invoke(null, null);
        }

        public static void OnPlayPause()
        {
            PlayPause?.Invoke(null, null);
        }
    }
}
