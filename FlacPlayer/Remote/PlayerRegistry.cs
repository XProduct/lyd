using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.Linq;

namespace FlacPlayer.Remote
{
    /// <summary>
    /// In-memory registry of Apple (and other) players that can render the shared host session.
    /// </summary>
    public sealed class PlayerRegistry
    {
        public static readonly PlayerRegistry Instance = new PlayerRegistry();

        private readonly ConcurrentDictionary<string, RegisteredPlayer> _players =
            new ConcurrentDictionary<string, RegisteredPlayer>(StringComparer.OrdinalIgnoreCase);

        /// <summary>Players silently expire if they miss heartbeats this long.</summary>
        public static readonly TimeSpan StaleAfter = TimeSpan.FromSeconds(45);

        public RegisteredPlayer Register(string deviceId, string name, string platform, string[] capabilities)
        {
            if (string.IsNullOrWhiteSpace(deviceId))
            {
                throw new ArgumentException("deviceId required", "deviceId");
            }

            string id = deviceId.Trim();
            var player = new RegisteredPlayer
            {
                DeviceId = id,
                Name = string.IsNullOrWhiteSpace(name) ? id : name.Trim(),
                Platform = platform ?? string.Empty,
                Capabilities = capabilities ?? new string[0],
                LastSeenUtc = DateTime.UtcNow
            };
            _players[id] = player;
            return player;
        }

        public bool Heartbeat(string deviceId, out RegisteredPlayer player)
        {
            player = null;
            if (string.IsNullOrWhiteSpace(deviceId))
            {
                return false;
            }
            RegisteredPlayer existing;
            if (!_players.TryGetValue(deviceId.Trim(), out existing))
            {
                return false;
            }
            existing.LastSeenUtc = DateTime.UtcNow;
            player = existing;
            return true;
        }

        public bool Unregister(string deviceId)
        {
            if (string.IsNullOrWhiteSpace(deviceId))
            {
                return false;
            }
            RegisteredPlayer removed;
            return _players.TryRemove(deviceId.Trim(), out removed);
        }

        public IList<RegisteredPlayer> ListActive()
        {
            PruneStale();
            return _players.Values
                .OrderBy(p => p.Name, StringComparer.OrdinalIgnoreCase)
                .ToList();
        }

        public void PruneStale()
        {
            DateTime cutoff = DateTime.UtcNow - StaleAfter;
            foreach (var kv in _players)
            {
                if (kv.Value.LastSeenUtc < cutoff)
                {
                    RegisteredPlayer ignored;
                    _players.TryRemove(kv.Key, out ignored);
                }
            }
        }
    }

    public sealed class RegisteredPlayer
    {
        public string DeviceId { get; set; }
        public string Name { get; set; }
        public string Platform { get; set; }
        public string[] Capabilities { get; set; }
        public DateTime LastSeenUtc { get; set; }
    }
}