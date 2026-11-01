using System;
using System.Security.Cryptography;
using System.Text;

namespace FlacPlayer.Remote
{
    public static class AlbumIdHelper
    {
        public static string From(string artist, string title)
        {
            string a = (artist ?? string.Empty).Trim();
            string t = (title ?? string.Empty).Trim();
            string key = a + "\n" + t;
            using (var sha = SHA256.Create())
            {
                byte[] hash = sha.ComputeHash(Encoding.UTF8.GetBytes(key));
                var sb = new StringBuilder(16);
                for (int i = 0; i < 8; i++)
                {
                    sb.Append(hash[i].ToString("x2"));
                }
                return sb.ToString();
            }
        }
    }
}