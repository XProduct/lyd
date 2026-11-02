using System;
using System.IO;
using System.Linq;
using System.Net.NetworkInformation;
using System.Text;
using Makaretu.Dns;

namespace FlacPlayer.Remote
{
    public sealed class MdnsAdvertiser : IDisposable
    {
        private MulticastService _mdns;
        private ServiceDiscovery _discovery;
        private ServiceProfile _profile;
        private bool _started;

        /// <summary>True when AAAA / IPv6 multicast advertising is active.</summary>
        public bool Ipv6Enabled { get; private set; }

        public void Start(string instanceName, int port, string displayName)
        {
            Stop();

            _mdns = new MulticastService(FilterNics);
            _mdns.UseIpv4 = true;
            // Advertise AAAA when possible so Apple Bonjour clients that prefer IPv6 can resolve the service.
            try
            {
                _mdns.UseIpv6 = true;
                Ipv6Enabled = true;
            }
            catch
            {
                _mdns.UseIpv6 = false;
                Ipv6Enabled = false;
            }

            _discovery = new ServiceDiscovery(_mdns);

            // DNS-SD instance labels should be conservative; put friendly text in TXT "name".
            string dnsInstance = SanitizeInstanceName(instanceName);
            _profile = new ServiceProfile(dnsInstance, "_lyd._tcp", (ushort)port);
            _profile.AddProperty("path", "/api/v1");
            _profile.AddProperty("ver", "1");
            _profile.AddProperty("name", displayName ?? instanceName);

            try
            {
                _discovery.Advertise(_profile);
                _mdns.Start();
                _started = true;
            }
            catch (Exception)
            {
                // Fall back to IPv4-only if dual-stack mDNS init fails (seen on some Windows NIC stacks).
                if (Ipv6Enabled)
                {
                    try
                    {
                        try { _mdns.Stop(); } catch { }
                        try { _mdns.Dispose(); } catch { }
                        _mdns = new MulticastService(FilterNics);
                        _mdns.UseIpv4 = true;
                        _mdns.UseIpv6 = false;
                        Ipv6Enabled = false;
                        _discovery = new ServiceDiscovery(_mdns);
                        _discovery.Advertise(_profile);
                        _mdns.Start();
                        _started = true;
                        return;
                    }
                    catch
                    {
                        Ipv6Enabled = false;
                        throw;
                    }
                }
                throw;
            }
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
            Ipv6Enabled = false;
        }

        public void Dispose()
        {
            Stop();
        }

        public static string FlattenException(Exception ex)
        {
            var sb = new StringBuilder();
            for (Exception cur = ex; cur != null; cur = cur.InnerException)
            {
                if (sb.Length > 0) sb.Append(" | ");
                sb.Append(cur.GetType().Name).Append(": ").Append(cur.Message);
            }
            return sb.ToString();
        }

        public static void WriteErrorLog(Exception ex)
        {
            try
            {
                string dir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "XProduct", "Lyd");
                Directory.CreateDirectory(dir);
                File.WriteAllText(Path.Combine(dir, "mdns-error.log"), DateTime.Now + Environment.NewLine + FlattenException(ex) + Environment.NewLine + ex);
            }
            catch
            {
            }
        }

        private static string SanitizeInstanceName(string name)
        {
            if (string.IsNullOrWhiteSpace(name))
            {
                return "Lyd";
            }
            var sb = new StringBuilder(name.Length);
            foreach (char c in name.Trim())
            {
                if (char.IsLetterOrDigit(c) || c == '-' || c == '_')
                {
                    sb.Append(c);
                }
                else if (char.IsWhiteSpace(c))
                {
                    sb.Append('-');
                }
            }
            string cleaned = sb.ToString().Trim('-');
            if (cleaned.Length == 0) return "Lyd";
            if (cleaned.Length > 63) cleaned = cleaned.Substring(0, 63);
            return cleaned;
        }

        private static System.Collections.Generic.IEnumerable<NetworkInterface> FilterNics(
            System.Collections.Generic.IEnumerable<NetworkInterface> nics)
        {
            return nics.Where(n =>
                n.OperationalStatus == OperationalStatus.Up &&
                n.SupportsMulticast &&
                n.NetworkInterfaceType != NetworkInterfaceType.Loopback &&
                n.NetworkInterfaceType != NetworkInterfaceType.Tunnel);
        }
    }
}
