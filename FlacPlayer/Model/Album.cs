using GalaSoft.MvvmLight;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;
using System.Windows.Media.Imaging;

namespace FlacPlayer.Model
{
    public class Album : ViewModelBase
    {
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
    }
}
