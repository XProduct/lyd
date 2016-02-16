using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Linq;
using System.Text;

namespace FlacPlayer.Model
{
    public interface IDataService
    {
        ObservableCollection<Song> GetSongs(string path);
        void GetID3Tags(Song path);

        ObservableCollection<string> GetSavedSearchFolders();
        void SetSavedSearchFolders(ObservableCollection<string> folders);

        string OpenFolderBrowser();
    }
}
