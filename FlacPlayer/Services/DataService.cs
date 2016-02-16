using System;
using System.IO;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Windows.Media.Imaging;

namespace FlacPlayer.Model
{
    public class DataService : IDataService
    {
        private ObservableCollection<Song> SongList = new ObservableCollection<Song>();

        public void GetID3Tags(Song song)
        {
            TagLib.File file = TagLib.File.Create(song.Path);

            if (file == null)
            {
                return;
            }

            song.Title = file.Tag.Title;

            song.Artist = file.Tag.FirstAlbumArtist ?? file.Tag.FirstPerformer ?? "Unknown";
            song.Album = file.Tag.Album;
            song.Track = (int)file.Tag.Track;

            if (file.Tag.Pictures.Length > 0)
            {
                // Load you image data in MemoryStream
                TagLib.IPicture pic = file.Tag.Pictures[0];
                MemoryStream ms = new MemoryStream(pic.Data.Data);
                ms.Seek(0, SeekOrigin.Begin);

                // ImageSource for System.Windows.Controls.Image
                BitmapImage bitmap = new BitmapImage();
                bitmap.BeginInit();
                bitmap.StreamSource = ms;
                bitmap.EndInit();
                bitmap.Freeze();

                song.CoverArt = bitmap;
            }
            else
            {
                BitmapImage defaultAlbumArt = new BitmapImage(new Uri("Images/default-album-artwork.png", UriKind.Relative));
                defaultAlbumArt.Freeze();
                song.CoverArt = defaultAlbumArt;
            }
        }

        public ObservableCollection<Song> GetSongs(string path)
        {
            ObservableCollection<Song> tempSongList = new ObservableCollection<Song>();

            if (Directory.Exists(path))
            {
                ProcessDirectory(path);
            }

            return SongList;
        }

        public string OpenFolderBrowser()
        {
            string selectedPath = string.Empty;
            var dialog = new System.Windows.Forms.FolderBrowserDialog();
            System.Windows.Forms.DialogResult result = dialog.ShowDialog();
            if (result == System.Windows.Forms.DialogResult.OK)
            {
                selectedPath = dialog.SelectedPath;
            }

            return selectedPath;
        }

        public ObservableCollection<string> GetSavedSearchFolders()
        {
            ObservableCollection<string> folders = new ObservableCollection<string>();

            if (File.Exists("folders.bin"))
            {
                using (StreamReader reader = new StreamReader("folders.bin"))
                {
                    while (!reader.EndOfStream)
                    {
                        folders.Add(reader.ReadLine());
                    }
                }
            }

            return folders;
        }

        public void SetSavedSearchFolders(ObservableCollection<string> folders)
        {
            using (StreamWriter writer = new StreamWriter("folders.bin"))
            {
                foreach (string folder in folders)
                {
                    writer.WriteLine(folder);
                }
            }
        }

        #region Helper Functions

        // Process all files in the directory passed in, recurse on any directories  
        // that are found, and process the files they contain. 
        private void ProcessDirectory(string targetDirectory)
        {
            DirectoryInfo dirInfo = new DirectoryInfo(targetDirectory);
            if (dirInfo.Name.Substring(0, 1) != ".")
            {
                // Process the list of files found in the directory. 
                string[] fileEntries = Directory.GetFiles(targetDirectory);
                foreach (string fileName in fileEntries)
                {
                    ProcessFile(fileName);
                }

                // Recurse into subdirectories of this directory. 
                string[] subdirectoryEntries = Directory.GetDirectories(targetDirectory);
                foreach (string subdirectory in subdirectoryEntries)
                {
                    ProcessDirectory(subdirectory);
                }
            }
        }

        // Insert logic for processing found files here. 
        private void ProcessFile(string path)
        {
            FileInfo fileInfo = new FileInfo(path);
            if (fileInfo.Name.Substring(0, 1) != "." && (fileInfo.Extension == ".flac" || fileInfo.Extension == ".mp3"))
            {
                SongList.Add(new Song(path, fileInfo.Name));
            }
        }

        #endregion
    }
}