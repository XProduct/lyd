using System;
using System.Diagnostics;
using System.Security.Principal;
using System.Windows;

namespace FlacPlayer.Remote
{
    public static class FirewallHelper
    {
        public static bool EnsureAccess(int port, ref bool alreadyConfigured)
        {
            if (alreadyConfigured)
            {
                return true;
            }

            MessageBoxResult answer = MessageBox.Show(
                "Lyd needs a one-time Windows permission to accept remote connections on TCP port " + port +
                " (IPv4 + IPv6 HTTP URL reservation and firewall). Allow now? An elevation prompt may appear.",
                "Lyd Remote",
                MessageBoxButton.YesNo,
                MessageBoxImage.Information);

            if (answer != MessageBoxResult.Yes)
            {
                return false;
            }

            string user = WindowsIdentity.GetCurrent().Name;
            // '+' strong wildcard covers dual-stack; also reserve [::] explicitly for builds that need it.
            string script =
                "netsh http add urlacl url=http://+:" + port + "/ user=\"" + user + "\"\r\n" +
                "netsh http add urlacl url=http://[::]:" + port + "/ user=\"" + user + "\"\r\n" +
                "netsh advfirewall firewall delete rule name=\"Lyd Remote API\"\r\n" +
                "netsh advfirewall firewall delete rule name=\"Lyd Remote API IPv6\"\r\n" +
                "netsh advfirewall firewall add rule name=\"Lyd Remote API\" dir=in action=allow protocol=TCP localport=" + port + " profile=private,domain\r\n" +
                "netsh advfirewall firewall add rule name=\"Lyd Remote API IPv6\" dir=in action=allow protocol=TCP localport=" + port + " profile=private,domain interfacetype=any\r\n" +
                "netsh advfirewall firewall delete rule name=\"Lyd Remote mDNS\"\r\n" +
                "netsh advfirewall firewall add rule name=\"Lyd Remote mDNS\" dir=in action=allow protocol=UDP localport=5353 profile=private,domain\r\n";

            string temp = System.IO.Path.Combine(System.IO.Path.GetTempPath(), "lyd-remote-firewall.cmd");
            System.IO.File.WriteAllText(temp, script);

            try
            {
                var psi = new ProcessStartInfo
                {
                    FileName = temp,
                    UseShellExecute = true,
                    Verb = "runas",
                    WindowStyle = ProcessWindowStyle.Hidden
                };
                Process p = Process.Start(psi);
                if (p == null)
                {
                    return false;
                }
                p.WaitForExit(60000);
                alreadyConfigured = p.ExitCode == 0;
                return alreadyConfigured;
            }
            catch (Exception)
            {
                return false;
            }
        }
    }
}
