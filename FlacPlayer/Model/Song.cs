using GalaSoft.MvvmLight;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Windows.Media.Imaging;

namespace FlacPlayer.Model
{
    public sealed class Song : ViewModelBase
    {
        public Song(string path, string title, string artist = null, string album = null)
        {
            ID = Guid.NewGuid().ToString();
            Path = path;
            Title = title;
            Artist = artist;
            Album = album;
        }

        public string ID { get; private set; }

        /// <summary>
        /// The <see cref="Disc" /> property's name.
        /// </summary>
        public const string DiscPropertyName = "Disc";

        private int _disc = 1;

        /// <summary>
        /// Sets and gets the Disc property.
        /// Changes to that property's value raise the PropertyChanged event. 
        /// </summary>
        public int Disc
        {
            get
            {
                return _disc;
            }

            set
            {
                if (_disc == value)
                {
                    return;
                }

                _disc = value;
                RaisePropertyChanged(DiscPropertyName);
            }
        }

        /// <summary>
        /// The <see cref="Track" /> property's name.
        /// </summary>
        public const string TrackPropertyName = "Track";

        private int _track = 0;

        /// <summary>
        /// Sets and gets the Track property.
        /// Changes to that property's value raise the PropertyChanged event. 
        /// </summary>
        public int Track
        {
            get
            {
                return _track;
            }

            set
            {
                if (_track == value)
                {
                    return;
                }

                _track = value;
                RaisePropertyChanged(TrackPropertyName);
            }
        }

        /// <summary>
        /// The <see cref="Title" /> property's name.
        /// </summary>
        public const string TitlePropertyName = "Title";

        private string _title;

        /// <summary>
        /// Sets and gets the Title property.
        /// Changes to that property's value raise the PropertyChanged event. 
        /// </summary>
        public string Title
        {
            get
            {
                return _title;
            }

            set
            {
                if (_title == value)
                {
                    return;
                }

                RaisePropertyChanging(TitlePropertyName);
                _title = value;
                RaisePropertyChanged(TitlePropertyName);
            }
        }

        /// <summary>
        /// The <see cref="Artist" /> property's name.
        /// </summary>
        public const string ArtistPropertyName = "Artist";

        private string _artist;

        /// <summary>
        /// Sets and gets the Artist property.
        /// Changes to that property's value raise the PropertyChanged event. 
        /// </summary>
        public string Artist
        {
            get
            {
                return _artist;
            }

            set
            {
                if (_artist == value)
                {
                    return;
                }

                RaisePropertyChanging(ArtistPropertyName);
                _artist = value;
                RaisePropertyChanged(ArtistPropertyName);
            }
        }

        /// <summary>
        /// The <see cref="Album" /> property's name.
        /// </summary>
        public const string AlbumPropertyName = "Album";

        private string _album;

        /// <summary>
        /// Sets and gets the Album property.
        /// Changes to that property's value raise the PropertyChanged event. 
        /// </summary>
        public string Album
        {
            get
            {
                return _album;
            }

            set
            {
                if (_album == value)
                {
                    return;
                }

                RaisePropertyChanging(AlbumPropertyName);
                _album = value;
                RaisePropertyChanged(AlbumPropertyName);
            }
        }

        /// <summary>
        /// The <see cref="Depth" /> property's name.
        /// </summary>
        public const string DepthPropertyName = "Depth";

        private double _Depth = 0;

        /// <summary>
        /// Sets and gets the Depth property.
        /// Changes to that property's value raise the PropertyChanged event. 
        /// </summary>
        public double Depth
        {
            get
            {
                return _Depth;
            }

            set
            {
                if (_Depth == value)
                {
                    return;
                }

                _Depth = value;
                RaisePropertyChanged(DepthPropertyName);
            }
        }

        /// <summary>
        /// The <see cref="Bitrate" /> property's name.
        /// </summary>
        public const string BitratePropertyName = "Bitrate";

        private double _Bitrate = 0;

        /// <summary>
        /// Sets and gets the Bitrate property.
        /// Changes to that property's value raise the PropertyChanged event. 
        /// </summary>
        public double Bitrate
        {
            get
            {
                return _Bitrate;
            }

            set
            {
                if (_Bitrate == value)
                {
                    return;
                }

                _Bitrate = value;
                RaisePropertyChanged(BitratePropertyName);
            }
        }

        /// <summary>
        /// The <see cref="SampleRate" /> property's name.
        /// </summary>
        public const string SampleRatePropertyName = "SampleRate";

        private double _SampleRate;

        /// <summary>
        /// Sets and gets the SampleRate property.
        /// Changes to that property's value raise the PropertyChanged event. 
        /// </summary>
        public double SampleRate
        {
            get
            {
                return _SampleRate;
            }

            set
            {
                if (_SampleRate == value)
                {
                    return;
                }

                _SampleRate = value;
                RaisePropertyChanged(SampleRatePropertyName);
            }
        }

        /// <summary>
        /// The <see cref="CoverArt" /> property's name.
        /// </summary>
        public const string CoverArtPropertyName = "CoverArt";

        private BitmapImage _CoverArt;

        /// <summary>
        /// Sets and gets the CoverArt property.
        /// Changes to that property's value raise the PropertyChanged event. 
        /// </summary>
        public BitmapImage CoverArt
        {
            get
            {
                return _CoverArt;
            }

            set
            {
                if (_CoverArt == value)
                {
                    return;
                }

                RaisePropertyChanging(CoverArtPropertyName);
                _CoverArt = value;
                RaisePropertyChanged(CoverArtPropertyName);
            }
        }

        /// <summary>
        /// The <see cref="IsCurrentlyPlaying" /> property's name.
        /// </summary>
        public const string IsCurrentlyPlayingPropertyName = "IsCurrentlyPlaying";

        private bool _IsCurrentlyPlaying = false;

        /// <summary>
        /// Sets and gets the IsCurrentlyPlaying property.
        /// Changes to that property's value raise the PropertyChanged event. 
        /// </summary>
        public bool IsCurrentlyPlaying
        {
            get
            {
                return _IsCurrentlyPlaying;
            }

            set
            {
                if (_IsCurrentlyPlaying == value)
                {
                    return;
                }

                _IsCurrentlyPlaying = value;
                RaisePropertyChanged(IsCurrentlyPlayingPropertyName);
            }
        }

        public string Path
        {
            get;
            private set;
        }
    }
}
