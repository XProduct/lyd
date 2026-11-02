using System;
using System.Collections.Generic;
using System.Net;
using System.Net.Sockets;
using System.Text;
using FlacPlayer.Remote;

namespace FlacPlayer
{
    /// <summary>
    /// Hosts the Lyd LAN remote HTTP API and mDNS advertisement.
    /// Kept name for DI compatibility with existing ViewModelLocator registration.
    /// </summary>
    public class WebSocketService : IWebSocketService
    {
        private LydApiServer _api;
        private MdnsAdvertiser _mdns;
        private RemoteHostSettings _settings;
        private IRemoteControl _control;

        public int Port
        {
            get
            {
                if (_settings == null)
                {
                    _settings = RemoteHostSettings.Load();
                }
                return _settings.Port > 0 ? _settings.Port : 8080;
            }
        }

        public bool IsRunning
        {
            get { return _api != null && _api.IsRunning; }
        }

        public string DiscoverabilityHint { get; private set; }

        /// <summary>mDNS instance name, e.g. "Lyd on HOST".</summary>
        public string DiscoverableAs { get; private set; }

        /// <summary>Bound API base URLs (IPv4 / IPv6), one per line.</summary>
        public string BoundUrls { get; private set; }

        public void SetControl(IRemoteControl control)
        {
            _control = control;
        }

        public void Start()
        {
            if (_control == null)
            {
                throw new InvalidOperationException("Remote control facade was not set before Start().");
            }

            _settings = RemoteHostSettings.Load();
            if (_settings.Port <= 0 || _settings.Port > 65535)
            {
                _settings.Port = 8080;
            }

            // First-run (or port change): one prompt for inbound TCP API + UDP 5353 mDNS.
            // Persist FirewallPrompted even on decline so we do not spam every launch.
            // Legacy: older builds only set FirewallConfigured — treat that as already prompted.
            if (_settings.FirewallConfigured && !_settings.FirewallPrompted)
            {
                _settings.FirewallPrompted = true;
                _settings.FirewallPromptedPort = _settings.Port;
                _settings.Save();
            }

            bool needsFirewallPrompt = !_settings.FirewallPrompted
                || _settings.FirewallPromptedPort != _settings.Port;

            if (needsFirewallPrompt)
            {
                bool userAccepted;
                bool configured = FirewallHelper.EnsureAccess(_settings.Port, out userAccepted);
                _settings.FirewallPrompted = true;
                _settings.FirewallPromptedPort = _settings.Port;
                if (configured)
                {
                    _settings.FirewallConfigured = true;
                }
                _settings.Save();
            }

            _api = new LydApiServer(_control);
            _api.Start(_settings.Port);

            bool lanBound = _api.BoundPrefix != null && _api.BoundPrefix.Contains("://+:");
            // If the user accepted elevation but bind is still localhost-only, retry start once
            // without showing another MessageBox (rules may have landed after first Start).
            if (!lanBound && _settings.FirewallConfigured)
            {
                _api.Stop();
                _api.Start(_settings.Port);
                lanBound = _api.BoundPrefix != null && _api.BoundPrefix.Contains("://+:");
            }

            string host = Environment.MachineName;
            string instance = "Lyd on " + host;
            DiscoverableAs = instance;
            BoundUrls = BuildBoundUrlsText(_settings.Port, lanBound);

            string firewallNote = "Requires inbound TCP " + _settings.Port + " (API) and UDP 5353 (mDNS). First-run firewall prompt covers this.";
            string bindNote = lanBound ? "" : " (localhost only until firewall/URL ACL is granted)";

            _mdns = new MdnsAdvertiser();
            try
            {
                _mdns.Start(instance, _settings.Port, _control.DisplayName ?? instance);
                DiscoverabilityHint =
                    "Discoverable as \"" + instance + "\" (_lyd._tcp)" + Environment.NewLine +
                    BoundUrls + Environment.NewLine +
                    firewallNote + bindNote;
            }
            catch (Exception ex)
            {
                MdnsAdvertiser.WriteErrorLog(ex);
                DiscoverableAs = "(mDNS failed)";
                DiscoverabilityHint =
                    "Discoverable as: mDNS failed — " + MdnsAdvertiser.FlattenException(ex) + Environment.NewLine +
                    BoundUrls + Environment.NewLine +
                    firewallNote +
                    " Use a bound URL below for manual IP entry on the Apple remote.";
            }
        }

        public void Stop()
        {
            if (_mdns != null)
            {
                _mdns.Dispose();
                _mdns = null;
            }
            if (_api != null)
            {
                _api.Dispose();
                _api = null;
            }
        }

        public void ApplyPort(int port)
        {
            if (port <= 0 || port > 65535)
            {
                return;
            }
            _settings = RemoteHostSettings.Load();
            if (_settings.Port == port && IsRunning)
            {
                return;
            }
            Stop();
            _settings.Port = port;
            // New port needs its own URL ACL + firewall rule; allow one fresh prompt.
            _settings.FirewallConfigured = false;
            _settings.FirewallPrompted = false;
            _settings.FirewallPromptedPort = 0;
            _settings.Save();
            Start();
        }

        private static string BuildBoundUrlsText(int port, bool lanBound)
        {
            var lines = new List<string>();
            if (!lanBound)
            {
                lines.Add("http://127.0.0.1:" + port + "/api/v1");
                return string.Join(Environment.NewLine, lines);
            }

            foreach (IPAddress ip in GetLocalAddresses())
            {
                lines.Add("http://" + FormatHostForUrl(ip) + ":" + port + "/api/v1");
            }

            if (lines.Count == 0)
            {
                lines.Add("http://" + GetLanIp() + ":" + port + "/api/v1");
            }

            return string.Join(Environment.NewLine, lines);
        }

        private static IEnumerable<IPAddress> GetLocalAddresses()
        {
            var list = new List<IPAddress>();
            try
            {
                foreach (IPAddress ip in Dns.GetHostAddresses(Dns.GetHostName()))
                {
                    if (ip.AddressFamily == AddressFamily.InterNetwork)
                    {
                        if (!IPAddress.IsLoopback(ip))
                        {
                            list.Add(ip);
                        }
                    }
                    else if (ip.AddressFamily == AddressFamily.InterNetworkV6)
                    {
                        if (!IPAddress.IsLoopback(ip) && !ip.IsIPv6LinkLocal && !ip.IsIPv6SiteLocal)
                        {
                            list.Add(ip);
                        }
                    }
                }
            }
            catch
            {
            }
            return list;
        }

        private static string FormatHostForUrl(IPAddress ip)
        {
            if (ip.AddressFamily == AddressFamily.InterNetworkV6)
            {
                return "[" + ip + "]";
            }
            return ip.ToString();
        }

        private static string GetLanIp()
        {
            try
            {
                using (var socket = new Socket(AddressFamily.InterNetwork, SocketType.Dgram, 0))
                {
                    socket.Connect("8.8.8.8", 65530);
                    var endPoint = socket.LocalEndPoint as IPEndPoint;
                    if (endPoint != null)
                    {
                        return endPoint.Address.ToString();
                    }
                }
            }
            catch
            {
            }
            return "127.0.0.1";
        }
    }
}
