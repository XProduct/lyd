using GalaSoft.MvvmLight;
using FlacPlayer.Model;
using System.Windows.Input;
using GalaSoft.MvvmLight.Command;
using System.Drawing;
using System.Collections.Generic;
using System.Threading.Tasks;
using System;
using System.Collections.ObjectModel;
using System.Timers;
using System.Linq;
using System.Windows.Media.Imaging;
using System.Threading;

namespace FlacPlayer.ViewModel
{
    /// <summary>
    /// This class contains properties that the main View can data bind to.
    /// <para>
    /// See http://www.galasoft.ch/mvvm
    /// </para>
    /// </summary>
    public sealed class MainViewModel : ViewModelBase
    {
        #region Constructor

        private readonly IDataService DataService;
        private readonly IPlayer Player;
        private readonly IWebSocketService WebSocketService;

        /// <summary>
        /// Initializes a new instance of the MainViewModel class.
        /// </summary>
        public MainViewModel(IDataService dataService, IPlayer player, IWebSocketService webSocketService)
        {
            DataService = dataService;
            Player = player;
            WebSocketService = webSocketService;

            GetDesignData();
            RefreshSongs();

            OpenSettingsCommand = new RelayCommand(() => IsSettingsVisible = true);
            PauseCommand = new RelayCommand(Pause);
            PlayCommand = new RelayCommand(Play);
            TogglePlayPauseCommand = new RelayCommand(TogglePlayPause);
            PlayOnDemandCommand = new RelayCommand(PlayOnDemand);
            SaveSettingsCommand = new RelayCommand(SaveSettings);
            ToggleShuffleCommand = new RelayCommand(ToggleShuffle);
            OpenAlbumCommand = new RelayCommand(OpenSelectedAlbum);
            CloseSelectedAlbumCommand = new RelayCommand(CloseSelectedAlbum);

            // Music Folders Commands
            AddMusicFolderCommand = new RelayCommand(AddMusicFolder);
            RemoveMusicFolderCommand = new RelayCommand(RemoveMusicFolder, () => !string.IsNullOrEmpty(MusicSearchPath));

            // Event Listeners
            StartSongPositionListener();

            // Start Web Socket
            WebSocketService.Start();
        }

        #endregion

        #region Properties

        /// <summary>
        /// The <see cref="CloseSelectedAlbumCommand" /> property's name.
        /// </summary>
        public const string CloseSelectedAlbumCommandPropertyName = "CloseSelectedAlbumCommand";

        private ICommand _CloseSelectedAlbumCommand;

        /// <summary>
        /// Sets and gets the CloseSelectedAlbumCommand property.
        /// Changes to that property's value raise the PropertyChanged event. 
        /// </summary>
        public ICommand CloseSelectedAlbumCommand
        {
            get
            {
                return _CloseSelectedAlbumCommand;
            }

            set
            {
                if (_CloseSelectedAlbumCommand == value)
                {
                    return;
                }

                _CloseSelectedAlbumCommand = value;
                RaisePropertyChanged(CloseSelectedAlbumCommandPropertyName);
            }
        }

        /// <summary>
        /// The <see cref="SelectedAlbumSongs" /> property's name.
        /// </summary>
        public const string SelectedAlbumSongsPropertyName = "SelectedAlbumSongs";

        private ObservableCollection<Song> _SelectedAlbumSongs = new ObservableCollection<Song>();

        /// <summary>
        /// Sets and gets the SelectedAlbumSongs property.
        /// Changes to that property's value raise the PropertyChanged event. 
        /// </summary>
        public ObservableCollection<Song> SelectedAlbumSongs
        {
            get
            {
                return _SelectedAlbumSongs;
            }

            set
            {
                if (_SelectedAlbumSongs == value)
                {
                    return;
                }

                _SelectedAlbumSongs = value;
                RaisePropertyChanged(SelectedAlbumSongsPropertyName);
            }
        }

        /// <summary>
        /// The <see cref="IsAlbumsVisible" /> property's name.
        /// </summary>
        public const string IsAlbumsVisiblePropertyName = "IsAlbumsVisible";

        private bool _IsAlbumsVisible = false;

        /// <summary>
        /// Sets and gets the IsAlbumsVisible property.
        /// Changes to that property's value raise the PropertyChanged event. 
        /// </summary>
        public bool IsAlbumsVisible
        {
            get
            {
                return _IsAlbumsVisible;
            }

            set
            {
                if (_IsAlbumsVisible == value)
                {
                    return;
                }

                _IsAlbumsVisible = value;
                RaisePropertyChanged(IsAlbumsVisiblePropertyName);
            }
        }

        /// <summary>
        /// The <see cref="IsSongsVisible" /> property's name.
        /// </summary>
        public const string IsSongsVisiblePropertyName = "IsSongsVisible";

        private bool _IsSongsVisible = true;

        /// <summary>
        /// Sets and gets the IsSongsVisible property.
        /// Changes to that property's value raise the PropertyChanged event. 
        /// </summary>
        public bool IsSongsVisible
        {
            get
            {
                return _IsSongsVisible;
            }

            set
            {
                if (_IsSongsVisible == value)
                {
                    return;
                }

                _IsSongsVisible = value;
                RaisePropertyChanged(IsSongsVisiblePropertyName);
            }
        }

        /// <summary>
        /// The <see cref="SelectedMenuItem" /> property's name.
        /// </summary>
        public const string SelectedMenuItemPropertyName = "SelectedMenuItem";

        private string _SelectedMenuItem = "Songs";

        /// <summary>
        /// Sets and gets the SelectedMenuItem property.
        /// Changes to that property's value raise the PropertyChanged event. 
        /// </summary>
        public string SelectedMenuItem
        {
            get
            {
                return _SelectedMenuItem;
            }

            set
            {
                if (_SelectedMenuItem == value)
                {
                    return;
                }

                _SelectedMenuItem = value;
                RaisePropertyChanged(SelectedMenuItemPropertyName);
                ChangeView();
            }
        }

        /// <summary>
        /// The <see cref="MenuItems" /> property's name.
        /// </summary>
        public const string MenuItemsPropertyName = "MenuItems";

        private ObservableCollection<string> _MenuItems = new ObservableCollection<string>() { "Songs", "Albums", "Settings" };

        /// <summary>
        /// Sets and gets the MenuItems property.
        /// Changes to that property's value raise the PropertyChanged event. 
        /// </summary>
        public ObservableCollection<string> MenuItems
        {
            get
            {
                return _MenuItems;
            }

            set
            {
                if (_MenuItems == value)
                {
                    return;
                }

                _MenuItems = value;
                RaisePropertyChanged(MenuItemsPropertyName);
            }
        }

        /// <summary>
        /// The <see cref="OpenAlbumCommand" /> property's name.
        /// </summary>
        public const string OpenAlbumCommandPropertyName = "OpenAlbumCommand";

        private ICommand _OpenAlbumCommand;

        /// <summary>
        /// Sets and gets the OpenAlbumCommand property.
        /// Changes to that property's value raise the PropertyChanged event. 
        /// </summary>
        public ICommand OpenAlbumCommand
        {
            get
            {
                return _OpenAlbumCommand;
            }

            set
            {
                if (_OpenAlbumCommand == value)
                {
                    return;
                }

                _OpenAlbumCommand = value;
                RaisePropertyChanged(OpenAlbumCommandPropertyName);
            }
        }

        /// <summary>
        /// The <see cref="IsSelectedAlbumVisible" /> property's name.
        /// </summary>
        public const string IsSelectedAlbumVisiblePropertyName = "IsSelectedAlbumVisible";

        private bool _IsSelectedAlbumVisible = false;

        /// <summary>
        /// Sets and gets the IsSelectedAlbumVisible property.
        /// Changes to that property's value raise the PropertyChanged event. 
        /// </summary>
        public bool IsSelectedAlbumVisible
        {
            get
            {
                return _IsSelectedAlbumVisible;
            }

            set
            {
                if (_IsSelectedAlbumVisible == value)
                {
                    return;
                }

                _IsSelectedAlbumVisible = value;
                RaisePropertyChanged(IsSelectedAlbumVisiblePropertyName);
            }
        }

        /// <summary>
        /// The <see cref="SelectedAlbum" /> property's name.
        /// </summary>
        public const string SelectedAlbumPropertyName = "SelectedAlbum";

        private Album _SelectedAlbum;

        /// <summary>
        /// Sets and gets the SelectedAlbum property.
        /// Changes to that property's value raise the PropertyChanged event. 
        /// </summary>
        public Album SelectedAlbum
        {
            get
            {
                return _SelectedAlbum;
            }

            set
            {
                if (_SelectedAlbum == value)
                {
                    return;
                }

                _SelectedAlbum = value;
                RaisePropertyChanged(SelectedAlbumPropertyName);
            }
        }

        /// <summary>
        /// The <see cref="IsPlaying" /> property's name.
        /// </summary>
        public const string IsPlayingPropertyName = "IsPlaying";

        /// <summary>
        /// Sets and gets the IsPlaying property.
        /// Changes to that property's value raise the PropertyChanged event. 
        /// </summary>
        public bool IsPlaying
        {
            get
            {
                return Player.IsPlaying();
            }
        }

        /// <summary>
        /// The <see cref="TogglePlayPauseCommand" /> property's name.
        /// </summary>
        public const string TogglePlayPauseCommandPropertyName = "TogglePlayPauseCommand";

        private ICommand _TogglePlayPauseCommand;

        /// <summary>
        /// Sets and gets the TogglePlayPauseCommand property.
        /// Changes to that property's value raise the PropertyChanged event. 
        /// </summary>
        public ICommand TogglePlayPauseCommand
        {
            get
            {
                return _TogglePlayPauseCommand;
            }

            set
            {
                if (_TogglePlayPauseCommand == value)
                {
                    return;
                }

                _TogglePlayPauseCommand = value;
                RaisePropertyChanged(TogglePlayPauseCommandPropertyName);
            }
        }

        /// <summary>
        /// The <see cref="Albums" /> property's name.
        /// </summary>
        public const string AlbumsPropertyName = "Albums";

        private ObservableCollection<Album> _albums = new ObservableCollection<Album>();

        /// <summary>
        /// Sets and gets the Albums property.
        /// Changes to that property's value raise the PropertyChanged event. 
        /// </summary>
        public ObservableCollection<Album> Albums
        {
            get
            {
                return _albums;
            }

            set
            {
                if (_albums == value)
                {
                    return;
                }

                _albums = value;
                RaisePropertyChanged(AlbumsPropertyName);
            }
        }

        /// <summary>
        /// The <see cref="AddMusicFolderCommand" /> property's name.
        /// </summary>
        public const string AddMusicFolderCommandPropertyName = "AddMusicFolderCommand";

        private ICommand _AddMusicFolderCommand;

        /// <summary>
        /// Sets and gets the AddMusicFolderCommand property.
        /// Changes to that property's value raise the PropertyChanged event. 
        /// </summary>
        public ICommand AddMusicFolderCommand
        {
            get
            {
                return _AddMusicFolderCommand;
            }

            set
            {
                if (_AddMusicFolderCommand == value)
                {
                    return;
                }

                _AddMusicFolderCommand = value;
                RaisePropertyChanged(AddMusicFolderCommandPropertyName);
            }
        }

        /// <summary>
        /// The <see cref="RemoveMusicFolderCommand" /> property's name.
        /// </summary>
        public const string RemoveMusicFolderCommandPropertyName = "RemoveMusicFolderCommand";

        private ICommand _RemoveMusicFolderCommand;

        /// <summary>
        /// Sets and gets the RemoveMusicFolderCommand property.
        /// Changes to that property's value raise the PropertyChanged event. 
        /// </summary>
        public ICommand RemoveMusicFolderCommand
        {
            get
            {
                return _RemoveMusicFolderCommand;
            }

            set
            {
                if (_RemoveMusicFolderCommand == value)
                {
                    return;
                }

                _RemoveMusicFolderCommand = value;
                RaisePropertyChanged(RemoveMusicFolderCommandPropertyName);
            }
        }

        /// <summary>
        /// The <see cref="MusicFolders" /> property's name.
        /// </summary>
        public const string MusicFoldersPropertyName = "MusicFolders";

        private ObservableCollection<string> _MusicFolders = new ObservableCollection<string>();

        /// <summary>
        /// Sets and gets the MusicFolders property.
        /// Changes to that property's value raise the PropertyChanged event. 
        /// </summary>
        public ObservableCollection<string> MusicFolders
        {
            get
            {
                return _MusicFolders;
            }

            set
            {
                if (_MusicFolders == value)
                {
                    return;
                }

                _MusicFolders = value;
                RaisePropertyChanged(MusicFoldersPropertyName);
            }
        }

        /// <summary>
        /// The <see cref="MusicSearchPath" /> property's name.
        /// </summary>
        public const string MusicSearchPathPropertyName = "MusicSearchPath";

        private string _MusicSearchPath;

        /// <summary>
        /// Sets and gets the MusicSearchPath property.
        /// Changes to that property's value raise the PropertyChanged event. 
        /// </summary>
        public string MusicSearchPath
        {
            get
            {
                return _MusicSearchPath;
            }

            set
            {
                if (_MusicSearchPath == value)
                {
                    return;
                }

                _MusicSearchPath = value;
                RaisePropertyChanged(MusicSearchPathPropertyName);
            }
        }

        /// <summary>
        /// The <see cref="SaveSettingsCommand" /> property's name.
        /// </summary>
        public const string SaveSettingsCommandPropertyName = "SaveSettingsCommand";

        private ICommand _saveSettingsCommand;

        /// <summary>
        /// Sets and gets the SaveSettingsCommand property.
        /// Changes to that property's value raise the PropertyChanged event. 
        /// </summary>
        public ICommand SaveSettingsCommand
        {
            get
            {
                return _saveSettingsCommand;
            }

            set
            {
                if (_saveSettingsCommand == value)
                {
                    return;
                }

                _saveSettingsCommand = value;
                RaisePropertyChanged(SaveSettingsCommandPropertyName);
            }
        }

        /// <summary>
        /// The <see cref="OpenSettingsCommand" /> property's name.
        /// </summary>
        public const string OpenSettingsCommandPropertyName = "OpenSettingsCommand";

        private ICommand _openSettingsCommand;

        /// <summary>
        /// Sets and gets the OpenSettingsCommand property.
        /// Changes to that property's value raise the PropertyChanged event. 
        /// </summary>
        public ICommand OpenSettingsCommand
        {
            get
            {
                return _openSettingsCommand;
            }

            set
            {
                if (_openSettingsCommand == value)
                {
                    return;
                }

                _openSettingsCommand = value;
                RaisePropertyChanged(OpenSettingsCommandPropertyName);
            }
        }

        /// <summary>
        /// The <see cref="IsSettingsVisible" /> property's name.
        /// </summary>
        public const string IsSettingsVisiblePropertyName = "IsSettingsVisible";

        private bool _isSettingsVisible = false;

        /// <summary>
        /// Sets and gets the IsSettingsVisible property.
        /// Changes to that property's value raise the PropertyChanged event. 
        /// </summary>
        public bool IsSettingsVisible
        {
            get
            {
                return _isSettingsVisible;
            }

            set
            {
                if (_isSettingsVisible == value)
                {
                    return;
                }

                _isSettingsVisible = value;
                RaisePropertyChanged(IsSettingsVisiblePropertyName);
            }
        }

        public const string CurrentTrackDurationPropertyName = "CurrentTrackDuration";

        private long _currentTrackDuration;

        public long CurrentTrackDuration
        {
            get
            {
                return _currentTrackDuration;
            }

            set
            {
                if (_currentTrackDuration == value)
                {
                    return;
                }

                RaisePropertyChanging(CurrentTrackDurationPropertyName);
                _currentTrackDuration = value;
                RaisePropertyChanged(CurrentTrackDurationPropertyName);
            }
        }

        /// <summary>
        /// The <see cref="ToggleShuffleCommand" /> property's name.
        /// </summary>
        public const string ToggleShuffleCommandPropertyName = "ToggleShuffleCommand";

        private ICommand _toggleShuffleCommand;

        /// <summary>
        /// Sets and gets the ToggleShuffleCommand property.
        /// Changes to that property's value raise the PropertyChanged event. 
        /// </summary>
        public ICommand ToggleShuffleCommand
        {
            get
            {
                return _toggleShuffleCommand;
            }

            set
            {
                if (_toggleShuffleCommand == value)
                {
                    return;
                }

                RaisePropertyChanging(ToggleShuffleCommandPropertyName);
                _toggleShuffleCommand = value;
                RaisePropertyChanged(ToggleShuffleCommandPropertyName);
            }
        }

        /// <summary>
        /// The <see cref="IsShuffleMode" /> property's name.
        /// </summary>
        public const string IsShuffleModePropertyName = "IsShuffleMode";

        private bool _isShuffleMode = false;

        /// <summary>
        /// Sets and gets the IsShuffleMode property.
        /// Changes to that property's value raise the PropertyChanged event. 
        /// </summary>
        public bool IsShuffleMode
        {
            get
            {
                return _isShuffleMode;
            }

            set
            {
                if (_isShuffleMode == value)
                {
                    return;
                }

                RaisePropertyChanging(IsShuffleModePropertyName);
                _isShuffleMode = value;
                RaisePropertyChanged(IsShuffleModePropertyName);
            }
        }

        /// <summary>
        /// The <see cref="Duration" /> property's name.
        /// </summary>
        public const string DurationPropertyName = "Duration";

        private string _duration = "0:00";

        /// <summary>
        /// Sets and gets the Duration property.
        /// Changes to that property's value raise the PropertyChanged event. 
        /// </summary>
        public string Duration
        {
            get
            {
                return _duration;
            }

            set
            {
                if (_duration == value)
                {
                    return;
                }

                RaisePropertyChanging(DurationPropertyName);
                _duration = value;
                RaisePropertyChanged(DurationPropertyName);
            }
        }

        /// <summary>
        /// The <see cref="PercentageComplete" /> property's name.
        /// </summary>
        public const string PercentageCompletePropertyName = "PercentageComplete";

        private double _PercentageComplete = 0;

        /// <summary>
        /// Sets and gets the PercentageComplete property.
        /// Changes to that property's value raise the PropertyChanged event. 
        /// </summary>
        public double PercentageComplete
        {
            get
            {
                return _PercentageComplete;
            }

            set
            {
                if (_PercentageComplete == value)
                {
                    return;
                }

                RaisePropertyChanging(PercentageCompletePropertyName);
                _PercentageComplete = value;
                RaisePropertyChanged(PercentageCompletePropertyName);
            }
        }

        /// <summary>
        /// The <see cref="ErrorString" /> property's name.
        /// </summary>
        public const string ErrorStringPropertyName = "ErrorString";

        private string _ErrorString;

        /// <summary>
        /// Sets and gets the ErrorString property.
        /// Changes to that property's value raise the PropertyChanged event. 
        /// </summary>
        public string ErrorString
        {
            get
            {
                return _ErrorString;
            }

            set
            {
                if (_ErrorString == value)
                {
                    return;
                }

                RaisePropertyChanging(ErrorStringPropertyName);
                _ErrorString = value;
                RaisePropertyChanged(ErrorStringPropertyName);
            }
        }

        /// <summary>
        /// The <see cref="CurrentSongIndex" /> property's name.
        /// </summary>
        public const string CurrentSongIndexPropertyName = "CurrentSongIndex";

        private int _CurrentSongIndex;

        /// <summary>
        /// Sets and gets the CurrentSongIndex property.
        /// Changes to that property's value raise the PropertyChanged event. 
        /// </summary>
        public int CurrentSongIndex
        {
            get
            {
                return _CurrentSongIndex;
            }

            set
            {
                if (_CurrentSongIndex == value)
                {
                    return;
                }

                RaisePropertyChanging(CurrentSongIndexPropertyName);
                _CurrentSongIndex = value;
                RaisePropertyChanged(CurrentSongIndexPropertyName);
            }
        }

        /// <summary>
        /// The <see cref="PlayOnDemandCommand" /> property's name.
        /// </summary>
        public const string PlayOnDemandCommandPropertyName = "PlayOnDemandCommand";

        private ICommand _PlayOnDemandCommand;

        /// <summary>
        /// Sets and gets the PlayOnDemandCommand property.
        /// Changes to that property's value raise the PropertyChanged event. 
        /// </summary>
        public ICommand PlayOnDemandCommand
        {
            get
            {
                return _PlayOnDemandCommand;
            }

            set
            {
                if (_PlayOnDemandCommand == value)
                {
                    return;
                }

                RaisePropertyChanging(PlayOnDemandCommandPropertyName);
                _PlayOnDemandCommand = value;
                RaisePropertyChanged(PlayOnDemandCommandPropertyName);
            }
        }

        /// <summary>
        /// The <see cref="PauseCommand" /> property's name.
        /// </summary>
        public const string PauseCommandPropertyName = "PauseCommand";

        private ICommand _PauseCommand;

        /// <summary>
        /// Sets and gets the PauseCommand property.
        /// Changes to that property's value raise the PropertyChanged event. 
        /// </summary>
        public ICommand PauseCommand
        {
            get
            {
                return _PauseCommand;
            }

            set
            {
                if (_PauseCommand == value)
                {
                    return;
                }

                RaisePropertyChanging(PauseCommandPropertyName);
                _PauseCommand = value;
                RaisePropertyChanged(PauseCommandPropertyName);
            }
        }

        /// <summary>
        /// The <see cref="SelectedSong" /> property's name.
        /// </summary>
        public const string SelectedSongPropertyName = "SelectedSong";

        private Song _SelectedSong;

        /// <summary>
        /// Sets and gets the SelectedSong property.
        /// Changes to that property's value raise the PropertyChanged event. 
        /// </summary>
        public Song SelectedSong
        {
            get
            {
                return _SelectedSong;
            }

            set
            {
                if (_SelectedSong == value)
                {
                    return;
                }

                RaisePropertyChanging(SelectedSongPropertyName);
                _SelectedSong = value;
                RaisePropertyChanged(SelectedSongPropertyName);
            }
        }

        /// <summary>
        /// The <see cref="Songs" /> property's name.
        /// </summary>
        public const string SongsPropertyName = "Songs";

        private ObservableCollection<Model.Song> _Songs = new ObservableCollection<Song>();

        /// <summary>
        /// Sets and gets the Songs property.
        /// Changes to that property's value raise the PropertyChanged event. 
        /// </summary>
        public ObservableCollection<Model.Song> Songs
        {
            get
            {
                return _Songs;
            }

            set
            {
                if (_Songs == value)
                {
                    return;
                }

                RaisePropertyChanging(SongsPropertyName);
                _Songs = value;
                RaisePropertyChanged(SongsPropertyName);
            }
        }

        /// <summary>
        /// The <see cref="PlayCommand" /> property's name.
        /// </summary>
        public const string PlayCommandPropertyName = "PlayCommand";

        private ICommand _playCommand;

        /// <summary>
        /// Sets and gets the PlayCommand property.
        /// Changes to that property's value raise the PropertyChanged event. 
        /// </summary>
        public ICommand PlayCommand
        {
            get
            {
                return _playCommand;
            }

            set
            {
                if (_playCommand == value)
                {
                    return;
                }

                RaisePropertyChanging(PlayCommandPropertyName);
                _playCommand = value;
                RaisePropertyChanged(PlayCommandPropertyName);
            }
        }

        /// <summary>
        /// The <see cref="CurrentPositionText" /> property's name.
        /// </summary>
        public const string CurrentPositionTextPropertyName = "CurrentPositionText";

        private string _CurrentPositionText;

        /// <summary>
        /// Sets and gets the CurrentPositionText property.
        /// Changes to that property's value raise the PropertyChanged event. 
        /// </summary>
        public string CurrentPositionText
        {
            get
            {
                return _CurrentPositionText;
            }

            set
            {
                if (_CurrentPositionText == value)
                {
                    return;
                }

                RaisePropertyChanging(CurrentPositionTextPropertyName);
                _CurrentPositionText = value;
                RaisePropertyChanged(CurrentPositionTextPropertyName);
            }
        }

        /// <summary>
        /// The <see cref="CurrentPlayingSongCoverArt" /> property's name.
        /// </summary>
        public const string CurrentPlayingSongCoverArtPropertyName = "CurrentPlayingSongCoverArt";

        private BitmapSource _currentPlayingSongCoverArt;

        /// <summary>
        /// Sets and gets the CurrentPlayingSongCoverArt property.
        /// Changes to that property's value raise the PropertyChanged event. 
        /// </summary>
        public BitmapSource CurrentPlayingSongCoverArt
        {
            get
            {
                return _currentPlayingSongCoverArt;
            }

            set
            {
                if (_currentPlayingSongCoverArt == value)
                {
                    return;
                }

                RaisePropertyChanging(CurrentPlayingSongCoverArtPropertyName);
                _currentPlayingSongCoverArt = value;
                RaisePropertyChanged(CurrentPlayingSongCoverArtPropertyName);
            }
        }

        /// <summary>
        /// The <see cref="CurrentPlayQueue" /> property's name.
        /// </summary>
        public const string CurrentPlayQueuePropertyName = "CurrentPlayQueue";

        private ObservableCollection<Song> _currentPlayQueue = new ObservableCollection<Song>();

        /// <summary>
        /// Sets and gets the CurrentPlayQueue property.
        /// Changes to that property's value raise the PropertyChanged event. 
        /// </summary>
        public ObservableCollection<Song> CurrentPlayQueue
        {
            get
            {
                return _currentPlayQueue;
            }

            set
            {
                if (_currentPlayQueue == value)
                {
                    return;
                }

                RaisePropertyChanging(CurrentPlayQueuePropertyName);
                _currentPlayQueue = value;
                RaisePropertyChanged(CurrentPlayQueuePropertyName);
            }
        }

        /// <summary>
        /// The <see cref="CurrentPlayingSong" /> property's name.
        /// </summary>
        public const string CurrentPlayingSongPropertyName = "CurrentPlayingSong";

        private Song _currentPlayingSong;

        /// <summary>
        /// Sets and gets the CurrentPlayingSong property.
        /// Changes to that property's value raise the PropertyChanged event. 
        /// </summary>
        public Song CurrentPlayingSong
        {
            get
            {
                return _currentPlayingSong;
            }

            set
            {
                if (_currentPlayingSong == value)
                {
                    return;
                }

                RaisePropertyChanging(CurrentPlayingSongPropertyName);
                _currentPlayingSong = value;
                RaisePropertyChanged(CurrentPlayingSongPropertyName);
            }
        }

        #endregion

        #region Methods

        private void AddMusicFolder()
        {
            MusicSearchPath = DataService.OpenFolderBrowser();
            MusicFolders.Add(MusicSearchPath);
            DataService.SetSavedSearchFolders(MusicFolders);
        }

        private void ChangeView()
        {
            switch (SelectedMenuItem)
            {
                case "Songs":
                    IsSongsVisible = true;
                    IsAlbumsVisible = false;
                    IsSelectedAlbumVisible = false;
                    IsSettingsVisible = false;
                    break;
                case "Albums":
                    IsAlbumsVisible = true;
                    IsSongsVisible = false;
                    IsSelectedAlbumVisible = false;
                    IsSettingsVisible = false;
                    break;
                case "Settings":
                    IsSettingsVisible = true;
                    IsAlbumsVisible = false;
                    IsSongsVisible = false;
                    IsSelectedAlbumVisible = false;
                    break;
            }
        }

        private void RemoveMusicFolder()
        {
            MusicFolders.Remove(MusicSearchPath);
            DataService.SetSavedSearchFolders(MusicFolders);
        }

        private void Play()
        {
            Player.Play();
        }

        private void PlayOnDemand()
        {
            Player.Play(SelectedSong.Path);
            CurrentSongIndex = 0;
            GetSongDuration();
            UpdateCurrentSong(SelectedSong);
            AddSongsToQueue();
            RaisePropertyChanged(nameof(IsPlaying));
        }

        private int PlayNextSong()
        {
            PercentageComplete = 0;
            CurrentSongIndex = CurrentSongIndex + 1;
            if (CurrentSongIndex < CurrentPlayQueue.Count)
            {
                Player.Play(CurrentPlayQueue[CurrentSongIndex].Path);
                UpdateCurrentSong(CurrentPlayQueue[CurrentSongIndex]);
                GetSongDuration();
            }
            else
            {
                UpdateCurrentSong(new Song("", "", "", ""));
                CurrentPositionText = "0:00";
                CurrentTrackDuration = 0;
                PercentageComplete = 0;
            }
            return 0;
        }

        private void Pause()
        {
            Player.Pause();
        }

        private void TogglePlayPause()
        {
            if (Player.IsPlaying())
            {
                Pause();
            }
            else
            {
                Play();
            }

            RaisePropertyChanged(nameof(IsPlaying));
        }

        private void UpdateCurrentSong(Song song)
        {
            CurrentPlayingSong = song;
            CurrentPlayingSongCoverArt = Albums.Where(x => x.Title == CurrentPlayingSong.Album).FirstOrDefault().CoverArt;
        }

        private void GetSongDuration()
        {
            CurrentTrackDuration = Player.GetCurrentSongDuration() / 1000;
            int currentSeconds = (int)CurrentTrackDuration;
            Duration = currentSeconds / 60 + ":" + (currentSeconds % 60 < 10 ? "0" + currentSeconds % 60 : (currentSeconds % 60).ToString());
        }

        private void LoadSongID3Tags()
        {
            foreach (Song song in Songs)
            {
                DataService.GetID3Tags(song);
            }
        }

        private void AddSongsToQueue()
        {
            CurrentPlayQueue.Clear();

            if (IsSelectedAlbumVisible)
            {
                if (IsShuffleMode)
                {
                    CurrentPlayQueue = new ObservableCollection<Song>(SelectedAlbumSongs.Shuffle());
                    CurrentPlayQueue.Remove(CurrentPlayingSong);
                    CurrentPlayQueue.Insert(0, CurrentPlayingSong);
                }
                else
                {
                    for (var i = (SelectedAlbumSongs.IndexOf(CurrentPlayingSong)); i < SelectedAlbumSongs.Count; i++)
                    {
                        CurrentPlayQueue.Add(SelectedAlbumSongs[i]);
                    }
                }
            }
            else {
                if (IsShuffleMode)
                {
                    CurrentPlayQueue = new ObservableCollection<Song>(Songs.Shuffle());
                    CurrentPlayQueue.Insert(0, CurrentPlayingSong);
                }
                else
                {
                    if (CurrentPlayingSong != null)
                    {
                        for (var i = (Songs.IndexOf(CurrentPlayingSong)); i < Songs.Count; i++)
                        {
                            CurrentPlayQueue.Add(Songs[i]);
                        }
                    }
                }
            }
        }

        private void OpenSelectedAlbum()
        {
            IsSelectedAlbumVisible = true;
            SelectedAlbumSongs = new ObservableCollection<Song>(Songs.Where(x => x.Album == SelectedAlbum.Title).OrderBy(x => x.Disc).ThenBy(y => y.Track).ToList());
        }

        private void CloseSelectedAlbum()
        {
            IsSelectedAlbumVisible = false;
            SelectedAlbumSongs = null;
        }

        private void RefreshAlbums()
        {
            foreach (Song song in Songs)
            {
                Album existingAlbum = Albums.Where(x => x.Title == song.Album).FirstOrDefault();

                if (existingAlbum == null)
                {
                    App.Current.Dispatcher.Invoke((Action)delegate // <--- HERE
                    {
                        Albums.Add(new Album()
                        {
                            Title = song.Album,
                            Artist = song.Artist,
                            CoverArt = DataService.GetAlbumImage(song.Path)
                        });
                    });
                }
            }

            Albums.OrderBy(s => s.Title.StartsWith("A ", StringComparison.OrdinalIgnoreCase) || s.Title.StartsWith("The ", StringComparison.OrdinalIgnoreCase) ? s.Title.Substring(s.Title.IndexOf(" ") + 1) : s.Title);
        }

        private void RefreshSongs()
        {
            Songs.Clear();
            MusicFolders = DataService.GetSavedSearchFolders();

            if (MusicFolders.Count == 0)
            {
                ErrorString = "Add Folders Where You Store Your Music To Get Started!";
                SelectedMenuItem = "Settings";
            }

            foreach (string folder in MusicFolders)
            {
                Songs = DataService.GetSongs(folder);
            }

            // Load ID3 Tags And Fill Albums
            Task.Run(() =>
            {
                LoadSongID3Tags();
                Songs.OrderBy(s => s.Artist.StartsWith("A ", StringComparison.OrdinalIgnoreCase) || s.Artist.StartsWith("The ", StringComparison.OrdinalIgnoreCase) ? s.Artist.Substring(s.Artist.IndexOf(" ") + 1) : s.Artist);

                RefreshAlbums();
            });
        }

        private void SaveSettings()
        {
            //DataService.SetSavedSearchFolders(new ObservableCollection<string> { MusicSearchPath });
            RefreshSongs();
            SelectedMenuItem = "Songs";
        }

        private void StartSongPositionListener()
        {
            System.Timers.Timer timer = new System.Timers.Timer();
            timer.Interval = 100;
            timer.Elapsed += timer_Elapsed;
            timer.Enabled = true;
        }

        void timer_Elapsed(object sender, ElapsedEventArgs e)
        {
            long time = Player.GetCurrentSongPlayTime();
            int currentSeconds = (int)time / 1000;

            if (time > 1000 && currentSeconds > CurrentTrackDuration)
            {
                PlayNextSong();
            }
            else {
                CurrentPositionText = currentSeconds / 60 + ":" + (currentSeconds % 60 < 10 ? "0" + currentSeconds % 60 : (currentSeconds % 60).ToString());

                if (CurrentTrackDuration != 0)
                {

                    PercentageComplete = (((double)currentSeconds / CurrentTrackDuration) * 100);
                }
            }
        }

        private void ToggleShuffle()
        {
            IsShuffleMode = !IsShuffleMode;
            AddSongsToQueue();
        }

        ////public override void Cleanup()
        ////{
        ////    // Clean up if needed

        ////    base.Cleanup();
        ////}

        private void GetDesignData()
        {
            if (IsInDesignMode)
            {
                IsSettingsVisible = false;
                PercentageComplete = 35;
            }
        }

        #endregion
    }
}