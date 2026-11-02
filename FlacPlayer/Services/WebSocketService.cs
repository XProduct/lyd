using System;
using System.Net;
using System.Net.Sockets;
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
            string baseUrl = "http://" + GetLanIp() + ":" + _settings.Port + "/api/v1";
            if (!lanBound)
            {
                baseUrl = "http://127.0.0.1:" + _settings.Port + "/api/v1";
            }

            _mdns = new MdnsAdvertiser();
            try
            {
                _mdns.Start(instance, _settings.Port, _control.DisplayName ?? instance);
                DiscoverabilityHint = "Discoverable as \"" + instance + "\" (_lyd._tcp). API: " + baseUrl +
                    (lanBound ? "" : " (localhost only until firewall/URL ACL is granted)");
            }
            catch (Exception ex)
            {
                MdnsAdvertiser.WriteErrorLog(ex);
                DiscoverabilityHint = "API: " + baseUrl + " (mDNS failed: " + MdnsAdvertiser.FlattenException(ex) + ")";
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