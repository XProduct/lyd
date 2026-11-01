using System;
using System.Linq;
using Makaretu.Dns;

namespace FlacPlayer.Remote
{
    public sealed class MdnsAdvertiser : IDisposable
    {
        private MulticastService _mdns;
        private ServiceDiscovery _discovery;
        private ServiceProfile _profile;
        private bool _started;

        public void Start(string instanceName, int port, string displayName)
        {
            Stop();
            _mdns = new MulticastService();
            _discovery = new ServiceDiscovery(_mdns);
            _profile = new ServiceProfile(instanceName, "_lyd._tcp", (ushort)port);
            _profile.AddProperty("path", "/api/v1");
            _profile.AddProperty("ver", "1");
            _profile.AddProperty("name", displayName ?? instanceName);
            _discovery.Advertise(_profile);
            _mdns.Start();
            _started = true;
        }

        public void Stop()
        {
            if (!_started)
            {
                return;
            }
            try
            {
                if (_discovery != null && _profile != null)
                {
                    _discovery.Unadvertise(_profile);
                }
            }
            catch
            {
            }
            try
            {
                if (_mdns != null)
                {
                    _mdns.Stop();
                    _mdns.Dispose();
                }
            }
            catch
            {
            }
            _discovery = null;
            _mdns = null;
            _profile = null;
            _started = false;
        }

        public void Dispose()
        {
            Stop();
        }
    }
}