using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Linq;
using System.Text;
using System.Windows.Media.Imaging;

namespace FlacPlayer.Model
{
    public interface IDataService
    {
        ObservableCollection<Song> GetSongs(string path);
        void GetID3Tags(Song path);
        BitmapImage GetAlbumImage(string path);

        ObservableCollection<string> GetSavedSearchFolders();
        void SetSavedSearchFolders(ObservableCollection<string> folders);

        string OpenFolderBrowser();
        string GetLocalIPAddress();
    }
}
