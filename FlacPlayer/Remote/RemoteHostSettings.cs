using System;
using System.IO;
using Newtonsoft.Json;

namespace FlacPlayer.Remote
{
    public sealed class RemoteHostSettings
    {
        public int Port { get; set; } = 8080;

        /// <summary>True after the one-time firewall/URL ACL dialog was shown (Yes or No).</summary>
        public bool FirewallPrompted { get; set; }

        /// <summary>Port for which <see cref="FirewallPrompted"/> applies; changing Port re-prompts.</summary>
        public int FirewallPromptedPort { get; set; }

        /// <summary>True when elevated rules were applied successfully.</summary>
        public bool FirewallConfigured { get; set; }

        private static string SettingsPath
        {
            get
            {
                string dir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "XProduct", "Lyd");
                Directory.CreateDirectory(dir);
                return Path.Combine(dir, "remote-settings.json");
            }
        }

        public static RemoteHostSettings Load()
        {
            try
            {
                if (File.Exists(SettingsPath))
                {
                    return JsonConvert.DeserializeObject<RemoteHostSettings>(File.ReadAllText(SettingsPath)) ?? new RemoteHostSettings();
                }
            }
            catch
            {
            }
            return new RemoteHostSettings();
        }

        public void Save()
        {
            File.WriteAllText(SettingsPath, JsonConvert.SerializeObject(this, Formatting.Indented));
        }
    }
}
