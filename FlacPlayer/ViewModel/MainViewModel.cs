using GalaSoft.MvvmLight;
using FlacPlayer.Model;
using FlacPlayer.Remote;
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
using System.Windows;
using System.IO;

namespace FlacPlayer.ViewModel
{
    public sealed class MainViewModel : ViewModelBase
    {
        #region Constructor

        private readonly IDataService DataService;
        private readonly IPlayer Player;
        private readonly IWebSocketService WebSocketService;
        private int _libraryRevision;
        /// <summary>Phase E: true when an Apple (or other) client is the audio renderer.</summary>
        private bool _remoteAudioOutput;
        private string _remoteAudioOutputDeviceId;
        /// <summary>Authoritative play/pause while audio renders on a remote player (irrKlang stays paused).</summary>
        private bool _sessionDesiredPlaying;
        private long _sessionPositionMs;
        private long _sessionSeekGeneration;
        private long _sessionRemoteDurationMs;
        private readonly System.Collections.Concurrent.ConcurrentDictionary<string, PlayerDto> _registeredPlayers =
            new System.Collections.Concurrent.ConcurrentDictionary<string, PlayerDto>();

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

            // Playback Precentage Update
            StopPrecentageUpdateCommand = new RelayCommand(() => IsPrecentageUpdateActive = false);
            StartPrecentageUpdateCommand = new RelayCommand(() => { SetPlayTime(); IsPrecentageUpdateActive = true; });

            // Music Folders Commands
            AddMusicFolderCommand = new RelayCommand(AddMusicFolder);
            RemoveMusicFolderCommand = new RelayCommand(RemoveMusicFolder, () => !string.IsNullOrEmpty(MusicSearchPath));

            // Event Listeners
            StartSongPositionListener();

            // LAN remote API + mDNS
            RemotePort = WebSocketService.Port > 0 ? WebSocketService.Port : 8080;
            LydRemoteInstructions = "Lyd Remote is starting...";
            WebSocketService.SetControl(new MainRemoteControl(this));
            try
            {
                WebSocketService.Start();
                RefreshRemoteDiscoverability();
            }
            catch (Exception ex)
            {
                LydRemoteInstructions = "Remote API failed to start: " + ex.Message;
                RemoteDiscoverableAs = "(offline)";
                RemoteBoundUrls = string.Empty;
            }
        }

        #endregion

        #region Properties

        /// <summary>
        /// The <see cref="LydRemoteInstructions" /> property's name.
        /// </summary>
        public const string LydRemoteInstructionsPropertyName = "LydRemoteInstructions";

        private string _lydRemoteInstructions = "Lyd Remote Is Not Available";

        /// <summary>
        /// Sets and gets the LydRemoteInstructions property.
        /// Changes to that property's value raise the PropertyChanged event. 
        /// </summary>
        public string LydRemoteInstructions
        {
            get
            {
                return _lydRemoteInstructions;
            }

            set
            {
                if (_lydRemoteInstructions == value)
                {
                    return;
                }

                _lydRemoteInstructions = value;
                RaisePropertyChanged(LydRemoteInstructionsPropertyName);
            }
        }

        /// <summary>
        /// The <see cref="IsPrecentageUpdateActive" /> property's name.
        /// </summary>
        public const string IsPrecentageUpdateActivePropertyName = "IsPrecentageUpdateActive";

        private bool _IsPrecentageUpdateActive = true;

        /// <summary>
        /// Sets and gets the IsPrecentageUpdateActive property.
        /// Changes to that property's value raise the PropertyChanged event. 
        /// </summary>
        public bool IsPrecentageUpdateActive
        {
            get
            {
                return _IsPrecentageUpdateActive;
            }

            set
            {
                if (_IsPrecentageUpdateActive == value)
                {
                    return;
                }

                _IsPrecentageUpdateActive = value;
                RaisePropertyChanged(IsPrecentageUpdateActivePropertyName);
            }
        }

        /// <summary>
        /// The <see cref="StopPrecentageUpdateCommand" /> property's name.
        /// </summary>
        public const string StopPrecentageUpdateCommandPropertyName = "StopPrecentageUpdateCommand";

        private ICommand _StopPrecentageUpdateCommand;

        /// <summary>
        /// Sets and gets the StopPrecentageUpdateCommand property.
        /// Changes to that property's value raise the PropertyChanged event. 
        /// </summary>
        public ICommand StopPrecentageUpdateCommand
        {
            get
            {
                return _StopPrecentageUpdateCommand;
            }

            set
            {
                if (_StopPrecentageUpdateCommand == value)
                {
                    return;
                }

                _StopPrecentageUpdateCommand = value;
                RaisePropertyChanged(StopPrecentageUpdateCommandPropertyName);
            }
        }

        /// <summary>
        /// The <see cref="StartPrecentageUpdateCommand" /> property's name.
        /// </summary>
        public const string StartPrecentageUpdateCommandPropertyName = "StartPrecentageUpdateCommand";

        private ICommand _StartPrecentageUpdateCommand;

        /// <summary>
        /// Sets and gets the StartPrecentageUpdateCommand property.
        /// Changes to that property's value raise the PropertyChanged event. 
        /// </summary>
        public ICommand StartPrecentageUpdateCommand
        {
            get
            {
                return _StartPrecentageUpdateCommand;
            }

            set
            {
                if (_StartPrecentageUpdateCommand == value)
                {
                    return;
                }

                _StartPrecentageUpdateCommand = value;
                RaisePropertyChanged(StartPrecentageUpdateCommandPropertyName);
            }
        }

        /// <summary>
        /// The <see cref="IsErrorVisible" /> property's name.
        /// </summary>
        public const string IsErrorVisiblePropertyName = "IsErrorVisible";

        /// <summary>
        /// Sets and gets the IsErrorVisible property.
        /// Changes to that property's value raise the PropertyChanged event. 
        /// </summary>
        public bool IsErrorVisible
        {
            get
            {
                return ErrorString.Length != 0;
            }
        }

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
                if (_remoteAudioOutput)
                {
                    return _sessionDesiredPlaying;
                }
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
                RaisePropertyChanged(IsErrorVisiblePropertyName);
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
                BumpLibraryRevision();
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

                Songs.ToList().ForEach(song => { song.IsCurrentlyPlaying = false; });
                _currentPlayingSong.IsCurrentlyPlaying = true;
            }
        }

        /// <summary>Remote API port (Settings override).</summary>
        public int RemotePort
        {
            get { return _remotePort; }
            set
            {
                if (_remotePort == value) return;
                _remotePort = value;
                RaisePropertyChanged(nameof(RemotePort));
            }
        }
        private int _remotePort = 8080;

        /// <summary>Settings: mDNS instance name ("Discoverable as …").</summary>
        public string RemoteDiscoverableAs
        {
            get { return _remoteDiscoverableAs; }
            private set
            {
                if (_remoteDiscoverableAs == value) return;
                _remoteDiscoverableAs = value;
                RaisePropertyChanged(nameof(RemoteDiscoverableAs));
            }
        }
        private string _remoteDiscoverableAs = string.Empty;

        /// <summary>Settings: bound API base URLs (IPv4/IPv6), one per line.</summary>
        public string RemoteBoundUrls
        {
            get { return _remoteBoundUrls; }
            private set
            {
                if (_remoteBoundUrls == value) return;
                _remoteBoundUrls = value;
                RaisePropertyChanged(nameof(RemoteBoundUrls));
            }
        }
        private string _remoteBoundUrls = string.Empty;

        public string RemoteDisplayName
        {
            get { return "Lyd on " + Environment.MachineName; }
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
                    RefreshRemoteDiscoverability();
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

        private void PlayOnDemand(Song song)
        {
            if (song == null || String.IsNullOrEmpty(song.Path))
            {
                return;
            }

            Player.Play(song.Path);
            CurrentSongIndex = 0;
            GetSongDuration();
            UpdateCurrentSong(song);
            AddSongsToQueue();
            // Phase E: session updates on host, but audio may render on an Apple client.
            if (_remoteAudioOutput)
            {
                _sessionDesiredPlaying = true;
                _sessionPositionMs = 0;
                _sessionSeekGeneration++;
                Pause();
            }
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
                if (_remoteAudioOutput)
                {
                    _sessionPositionMs = 0;
                    _sessionSeekGeneration++;
                    // Keep desired playing so the Apple renderer advances with the shared session.
                    Pause();
                }
            }
            else
            {
                UpdateCurrentSong(new Song("", "", "", ""));
                CurrentPositionText = "0:00";
                CurrentTrackDuration = 0;
                PercentageComplete = 0;
                if (_remoteAudioOutput)
                {
                    _sessionDesiredPlaying = false;
                    _sessionPositionMs = 0;
                    _sessionSeekGeneration++;
                }
            }
            RaisePropertyChanged(nameof(IsPlaying));
            return 0;
        }

        private void Pause()
        {
            Player.Pause();
        }

        private void TogglePlayPause()
        {
            if (_remoteAudioOutput)
            {
                _sessionDesiredPlaying = !_sessionDesiredPlaying;
                Pause();
                RaisePropertyChanged(nameof(IsPlaying));
                return;
            }

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
            if (song == null || String.IsNullOrEmpty(song.Path))
            {
                return;
            }

            CurrentPlayingSong = song;

            // Albums may still be empty while files hydrate (e.g. Dropbox) or ID3/album refresh is in progress.
            Album album = Albums.FirstOrDefault(x => x.Title == CurrentPlayingSong.Album);
            CurrentPlayingSongCoverArt = album != null ? album.CoverArt : null;
        }

        private void GetSongDuration()
        {
            try {
                CurrentTrackDuration = Player.GetCurrentSongDuration() / 1000;
                int currentSeconds = (int)CurrentTrackDuration;
                Duration = currentSeconds / 60 + ":" + (currentSeconds % 60 < 10 ? "0" + currentSeconds % 60 : (currentSeconds % 60).ToString());
                ErrorString = string.Empty;
            }
            catch
            {
                ErrorString = "Song Failed To Play";
                Pause();
            }
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
                string albumId = AlbumIdHelper.From(song.Artist, song.Album);
                song.AlbumId = albumId;

                Album existingAlbum = Albums.FirstOrDefault(x => x.Id == albumId || x.Title == song.Album);

                if (existingAlbum == null)
                {
                    App.Current.Dispatcher.Invoke((Action)delegate
                    {
                        Albums.Add(new Album()
                        {
                            Id = albumId,
                            Title = song.Album,
                            Artist = song.Artist,
                            CoverSourcePath = song.Path,
                            CoverArt = DataService.GetAlbumImage(song.Path)
                        });
                    });
                }
                else if (string.IsNullOrEmpty(existingAlbum.Id))
                {
                    existingAlbum.Id = albumId;
                    if (string.IsNullOrEmpty(existingAlbum.CoverSourcePath))
                    {
                        existingAlbum.CoverSourcePath = song.Path;
                    }
                }
            }

            Albums.OrderBy(s => s.Title.StartsWith("A ", StringComparison.OrdinalIgnoreCase) || s.Title.StartsWith("The ", StringComparison.OrdinalIgnoreCase) ? s.Title.Substring(s.Title.IndexOf(" ") + 1) : s.Title);
            BumpLibraryRevision();
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
            else
            {
                ErrorString = string.Empty;
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
            try
            {
                if (RemotePort > 0 && RemotePort <= 65535 && RemotePort != WebSocketService.Port)
                {
                    WebSocketService.ApplyPort(RemotePort);
                }
                RefreshRemoteDiscoverability();
            }
            catch (Exception ex)
            {
                LydRemoteInstructions = "Failed to apply remote port: " + ex.Message;
            }

            RefreshSongs();
            SelectedMenuItem = "Songs";
        }

        private void RefreshRemoteDiscoverability()
        {
            RemoteDiscoverableAs = WebSocketService.DiscoverableAs ?? string.Empty;
            RemoteBoundUrls = WebSocketService.BoundUrls ?? string.Empty;
            LydRemoteInstructions = WebSocketService.DiscoverabilityHint ?? string.Empty;
        }

        private void SetPlayTime()
        {
            int seconds = (int)(CurrentTrackDuration * PercentageComplete / 100);
            Player.SetPlayPosition(seconds);
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
            // Phase E: when Apple renders audio, host UI follows session position from heartbeats —
            // never advance the queue from a paused irrKlang "finished" state.
            if (_remoteAudioOutput)
            {
                int currentSeconds = (int)(_sessionPositionMs / 1000);
                if (currentSeconds < 0) currentSeconds = 0;
                CurrentPositionText = currentSeconds / 60 + ":" + (currentSeconds % 60 < 10 ? "0" + currentSeconds % 60 : (currentSeconds % 60).ToString());
                double durationSec = CurrentTrackDuration;
                if (_sessionRemoteDurationMs > 0)
                {
                    durationSec = _sessionRemoteDurationMs / 1000.0;
                }
                if (durationSec > 0)
                {
                    PercentageComplete = (((double)currentSeconds / durationSec) * 100);
                }
                return;
            }

            if (IsPrecentageUpdateActive)
            {
                long time = Player.GetCurrentSongPlayTime();
                int currentSeconds = (int)time / 1000;

                if (Player.IsFinished())
                {
                    PlayNextSong();
                }
                else
                {
                    CurrentPositionText = currentSeconds / 60 + ":" + (currentSeconds % 60 < 10 ? "0" + currentSeconds % 60 : (currentSeconds % 60).ToString());

                    if (CurrentTrackDuration != 0)
                    {

                        PercentageComplete = (((double)currentSeconds / CurrentTrackDuration) * 100);
                    }
                }
            }
            else
            {
                int currentSeconds = (int)(CurrentTrackDuration * PercentageComplete / 100);
                CurrentPositionText = currentSeconds / 60 + ":" + (currentSeconds % 60 < 10 ? "0" + currentSeconds % 60 : (currentSeconds % 60).ToString());
            }
        }

        private void ToggleShuffle()
        {
            IsShuffleMode = !IsShuffleMode;
            AddSongsToQueue();
        }

        private void Shuffle()
        {
            IsShuffleMode = true;
            AddSongsToQueue();
            PlayNextSong();
        }

        private void PlayPreviousSong()
        {
            PercentageComplete = 0;
            if (CurrentSongIndex > 0 && CurrentPlayQueue != null && CurrentPlayQueue.Count > 0)
            {
                CurrentSongIndex = CurrentSongIndex - 1;
                Player.Play(CurrentPlayQueue[CurrentSongIndex].Path);
                UpdateCurrentSong(CurrentPlayQueue[CurrentSongIndex]);
                GetSongDuration();
                if (_remoteAudioOutput)
                {
                    _sessionPositionMs = 0;
                    _sessionSeekGeneration++;
                    Pause();
                }
            }
            RaisePropertyChanged(nameof(IsPlaying));
        }

        private void BumpLibraryRevision()
        {
            Interlocked.Increment(ref _libraryRevision);
        }

        /// <summary>Monotonic library revision for cheap remote polls (C1).</summary>
        public int GetLibraryRevision()
        {
            return _libraryRevision;
        }

        public LibraryDto BuildRemoteLibrary()
        {
            var songs = Songs.Select(MapSongDto).ToList();
            var albums = Albums.Select(a =>
            {
                string id = a.Id ?? AlbumIdHelper.From(a.Artist, a.Title);
                return new AlbumDto
                {
                    Id = id,
                    Title = a.Title,
                    Artist = a.Artist,
                    SongIds = Songs.Where(s => (s.AlbumId ?? AlbumIdHelper.From(s.Artist, s.Album)) == id).Select(s => s.ID).ToList(),
                    CoverUrl = "/api/v1/albums/" + id + "/cover"
                };
            }).ToList();

            return new LibraryDto
            {
                Songs = songs,
                Albums = albums,
                Revision = _libraryRevision
            };
        }

        public PlaybackStateDto BuildRemotePlaybackState()
        {
            long position;
            long duration = 0;
            bool playing;
            if (_remoteAudioOutput)
            {
                position = _sessionPositionMs;
                if (position < 0) position = 0;
                playing = _sessionDesiredPlaying;
                if (_sessionRemoteDurationMs > 0)
                {
                    duration = _sessionRemoteDurationMs;
                }
                else
                {
                    try { duration = Player.GetCurrentSongDuration(); } catch { }
                }
            }
            else
            {
                position = Player.GetCurrentSongPlayTime();
                if (position < 0) position = 0;
                playing = Player.IsPlaying();
                try { duration = Player.GetCurrentSongDuration(); } catch { }
            }

            return new PlaybackStateDto
            {
                IsPlaying = playing,
                Shuffle = IsShuffleMode,
                PositionMs = position,
                DurationMs = duration,
                CurrentSongId = CurrentPlayingSong != null ? CurrentPlayingSong.ID : null,
                CurrentSong = CurrentPlayingSong != null && !string.IsNullOrEmpty(CurrentPlayingSong.Path) ? MapSongDto(CurrentPlayingSong) : null,
                Volume = Player.GetVolume(),
                OutputTarget = _remoteAudioOutput ? "remote" : "host",
                OutputDeviceId = _remoteAudioOutputDeviceId,
                SeekGeneration = _sessionSeekGeneration
            };
        }

        public void RemotePlaySong(string songId)
        {
            Song song = Songs.FirstOrDefault(s => s.ID == songId);
            PlayOnDemand(song);
        }

        /// <summary>Phase E: when Apple (or another remote) renders audio, silence irrKlang but keep session/queue.</summary>
        public void RemoteSetAudioOutput(string target, string deviceId, string deviceName)
        {
            bool remote = string.Equals(target, "remote", StringComparison.OrdinalIgnoreCase);
            if (remote)
            {
                long pos = Player.GetCurrentSongPlayTime();
                if (pos < 0) pos = 0;
                _sessionPositionMs = pos;
                _sessionDesiredPlaying = Player.IsPlaying();
                _remoteAudioOutput = true;
                _remoteAudioOutputDeviceId = deviceId;
                Pause();
            }
            else
            {
                bool resume = _sessionDesiredPlaying;
                long handoff = _sessionPositionMs;
                _remoteAudioOutput = false;
                _remoteAudioOutputDeviceId = null;
                if (handoff > 0)
                {
                    Player.SetPlayPosition((int)(handoff / 1000));
                }
                if (resume)
                {
                    Play();
                }
                else
                {
                    Pause();
                }
            }
            RaisePropertyChanged(nameof(IsPlaying));
        }

        public void RemoteApplyPlaybackHeartbeat(string deviceId, long positionMs, long? durationMs, string songId)
        {
            if (!_remoteAudioOutput)
            {
                return;
            }
            if (string.IsNullOrEmpty(deviceId) ||
                !string.Equals(deviceId, _remoteAudioOutputDeviceId, StringComparison.OrdinalIgnoreCase))
            {
                return;
            }
            if (positionMs < 0) positionMs = 0;
            _sessionPositionMs = positionMs;
            if (durationMs.HasValue && durationMs.Value > 0)
            {
                _sessionRemoteDurationMs = durationMs.Value;
            }
            TouchRegisteredPlayer(deviceId);
        }

        public void RemoteRegisterPlayer(string deviceId, string name, string platform, string[] capabilities)
        {
            if (string.IsNullOrEmpty(deviceId))
            {
                return;
            }
            var dto = new PlayerDto
            {
                DeviceId = deviceId,
                Name = string.IsNullOrWhiteSpace(name) ? deviceId : name,
                Platform = platform ?? "",
                Capabilities = capabilities ?? new string[0],
                LastSeenUnixMs = DateTimeOffset.UtcNow.ToUnixTimeMilliseconds()
            };
            _registeredPlayers[deviceId] = dto;
        }

        public void RemoteUnregisterPlayer(string deviceId)
        {
            if (string.IsNullOrEmpty(deviceId))
            {
                return;
            }
            PlayerDto removed;
            _registeredPlayers.TryRemove(deviceId, out removed);
            if (_remoteAudioOutput &&
                string.Equals(deviceId, _remoteAudioOutputDeviceId, StringComparison.OrdinalIgnoreCase))
            {
                // Output device left — fall back to host audio at last known position.
                RemoteSetAudioOutput("host", null, null);
            }
        }

        public System.Collections.Generic.IList<PlayerDto> RemoteGetPlayers()
        {
            long cutoff = DateTimeOffset.UtcNow.ToUnixTimeMilliseconds() - 45000;
            var list = new System.Collections.Generic.List<PlayerDto>();
            foreach (var pair in _registeredPlayers)
            {
                if (pair.Value.LastSeenUnixMs >= cutoff)
                {
                    list.Add(pair.Value);
                }
            }
            return list;
        }

        private void TouchRegisteredPlayer(string deviceId)
        {
            PlayerDto existing;
            if (_registeredPlayers.TryGetValue(deviceId, out existing) && existing != null)
            {
                existing.LastSeenUnixMs = DateTimeOffset.UtcNow.ToUnixTimeMilliseconds();
            }
        }

        public bool TryGetRemoteSongFilePath(string songId, out string path, out string contentType)
        {
            path = null;
            contentType = "application/octet-stream";
            Song song = Songs.FirstOrDefault(s => s.ID == songId);
            if (song == null || string.IsNullOrEmpty(song.Path) || !System.IO.File.Exists(song.Path))
            {
                return false;
            }
            path = song.Path;
            string ext = System.IO.Path.GetExtension(song.Path) ?? string.Empty;
            if (ext.Equals(".flac", StringComparison.OrdinalIgnoreCase)) contentType = "audio/flac";
            else if (ext.Equals(".mp3", StringComparison.OrdinalIgnoreCase)) contentType = "audio/mpeg";
            else if (ext.Equals(".m4a", StringComparison.OrdinalIgnoreCase) || ext.Equals(".aac", StringComparison.OrdinalIgnoreCase)) contentType = "audio/mp4";
            else if (ext.Equals(".wav", StringComparison.OrdinalIgnoreCase)) contentType = "audio/wav";
            else if (ext.Equals(".ogg", StringComparison.OrdinalIgnoreCase)) contentType = "audio/ogg";
            return true;
        }

        /// <summary>
        /// Match desktop album view: open album context, shuffle off, play from first track in disc/track order.
        /// </summary>
        public void RemotePlayAlbum(string albumId)
        {
            if (string.IsNullOrEmpty(albumId))
            {
                return;
            }

            Album album = Albums.FirstOrDefault(a => a.Id == albumId);
            var albumSongs = new ObservableCollection<Song>(
                Songs
                    .Where(s => (s.AlbumId ?? AlbumIdHelper.From(s.Artist, s.Album)) == albumId)
                    .OrderBy(s => s.Disc)
                    .ThenBy(s => s.Track)
                    .ThenBy(s => s.Title)
                    .ToList());

            if (albumSongs.Count == 0)
            {
                return;
            }

            if (album != null)
            {
                SelectedAlbum = album;
            }
            SelectedAlbumSongs = albumSongs;
            IsSelectedAlbumVisible = true;
            IsShuffleMode = false;
            PlayOnDemand(albumSongs[0]);
            RaisePropertyChanged(nameof(IsShuffleMode));
        }

        public void RemotePause()
        {
            if (_remoteAudioOutput)
            {
                _sessionDesiredPlaying = false;
            }
            Pause();
            RaisePropertyChanged(nameof(IsPlaying));
        }

        public void RemotePlayPause() { TogglePlayPause(); }
        public void RemoteNext() { PlayNextSong(); }
        public void RemotePrevious() { PlayPreviousSong(); }

        public void RemoteSetShuffle(bool? enabled)
        {
            if (enabled.HasValue)
            {
                IsShuffleMode = enabled.Value;
                AddSongsToQueue();
            }
            else
            {
                ToggleShuffle();
            }
        }

        public void RemoteSeek(long positionMs)
        {
            if (positionMs < 0) positionMs = 0;
            if (_remoteAudioOutput)
            {
                _sessionPositionMs = positionMs;
                _sessionSeekGeneration++;
                // Keep irrKlang parked near the same offset for a clean handoff later.
                try { Player.SetPlayPosition((int)(positionMs / 1000)); } catch { }
                return;
            }
            Player.SetPlayPosition((int)(positionMs / 1000));
        }

        public void RemoteSetVolume(double level)
        {
            Player.SetVolume(level);
        }

        public bool TryGetRemoteAlbumCover(string albumId, out byte[] bytes, out string contentType)
        {
            bytes = null;
            contentType = "image/jpeg";
            Album album = Albums.FirstOrDefault(a => a.Id == albumId);
            string path = album != null ? album.CoverSourcePath : null;
            if (string.IsNullOrEmpty(path))
            {
                Song song = Songs.FirstOrDefault(s => (s.AlbumId ?? AlbumIdHelper.From(s.Artist, s.Album)) == albumId);
                path = song != null ? song.Path : null;
            }
            if (string.IsNullOrEmpty(path) || !File.Exists(path))
            {
                return false;
            }

            try
            {
                using (TagLib.File file = TagLib.File.Create(path))
                {
                    if (file != null && file.Tag.Pictures != null && file.Tag.Pictures.Length > 0)
                    {
                        var pic = file.Tag.Pictures[0];
                        bytes = pic.Data.Data;
                        if (!string.IsNullOrEmpty(pic.MimeType))
                        {
                            contentType = pic.MimeType;
                        }
                        return bytes != null && bytes.Length > 0;
                    }
                }
            }
            catch
            {
            }
            return false;
        }

        private static SongDto MapSongDto(Song song)
        {
            return new SongDto
            {
                Id = song.ID,
                Title = song.Title,
                Artist = song.Artist,
                Album = song.Album,
                AlbumId = song.AlbumId ?? AlbumIdHelper.From(song.Artist, song.Album),
                Track = song.Track,
                Disc = song.Disc,
                DurationMs = null,
                Bitrate = song.Bitrate > 0 ? song.Bitrate : (double?)null,
                SampleRate = song.SampleRate > 0 ? song.SampleRate : (double?)null,
                Depth = song.Depth > 0 ? song.Depth : (double?)null
            };
        }

        public override void Cleanup()
        {
            WebSocketService.Stop();
            base.Cleanup();
        }

        private void GetDesignData()
        {
            if (IsInDesignMode)
            {
                IsSettingsVisible = false;
                PercentageComplete = 35;
                
                ErrorString = "Whoa buddy.";
            }
        }

        #endregion
    }
}