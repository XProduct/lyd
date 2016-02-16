using System;
using FlacPlayer.Model;
using System.Collections.Generic;
using System.Collections.ObjectModel;

namespace FlacPlayer.Design
{
    public class DesignDataService : IDataService
    {
        public void GetID3Tags(Song path)
        {
            //throw new NotImplementedException();
        }

        public ObservableCollection<string> GetSavedSearchFolders()
        {
            return new ObservableCollection<string>() { "C:\\Music" };
        }

        public ObservableCollection<Song> GetSongs(string path)
        {
            return new ObservableCollection<Song>() {
                new Song("", "") {
                    Title = "My Bum",
                    Album = "The Body",
                    Artist = "Rockers"
                },
                new Song("", "") {
                    Title = "My Toof",
                    Album = "The Body",
                    Artist = "Rockers"
                },
                new Song("", "") {
                    Title = "My Bum",
                    Album = "The Body",
                    Artist = "Rockers"
                }
            };
        }

        public string OpenFolderBrowser()
        {
            throw new NotImplementedException();
        }

        public void SetSavedSearchFolders(ObservableCollection<string> folders)
        {
           
        }
    }
}