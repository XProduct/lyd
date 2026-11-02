using System;
using System.Diagnostics;
using System.Security.Principal;
using System.Windows;

namespace FlacPlayer.Remote
{
    public static class FirewallHelper
    {
        /// <summary>
        /// Shows the one-time elevation prompt and, if accepted, adds URL ACL + inbound
        /// firewall rules for the API TCP port and mDNS UDP 5353.
        /// </summary>
        /// <param name="port">HTTP API listen port.</param>
        /// <param name="userAccepted">True when the user clicked Yes (UAC may still be cancelled).</param>
        /// <returns>True when the elevated script completed successfully.</returns>
        public static bool EnsureAccess(int port, out bool userAccepted)
        {
            userAccepted = false;

            MessageBoxResult answer = MessageBox.Show(
                "Lyd needs a one-time Windows permission so phones on your LAN can connect:" + Environment.NewLine + Environment.NewLine +
                "• Inbound TCP " + port + " — HTTP remote API (IPv4 + IPv6 URL reservation)" + Environment.NewLine +
                "• Inbound UDP 5353 — mDNS / Bonjour discovery (_lyd._tcp)" + Environment.NewLine + Environment.NewLine +
                "Allow now? A Windows elevation (UAC) prompt may appear. You will not be asked again for this port.",
                "Lyd Remote",
                MessageBoxButton.YesNo,
                MessageBoxImage.Information);

            if (answer != MessageBoxResult.Yes)
            {
                return false;
            }

            userAccepted = true;

            string user = WindowsIdentity.GetCurrent().Name;
            // Delete-then-add so re-runs succeed when the ACL/rule already exists (exit code 0).
            string script =
                "@echo off" + Environment.NewLine +
                "netsh http delete urlacl url=http://+:" + port + "/ >nul 2>&1" + Environment.NewLine +
                "netsh http delete urlacl url=http://[::]:" + port + "/ >nul 2>&1" + Environment.NewLine +
                "netsh http add urlacl url=http://+:" + port + "/ user=\"" + user + "\"" + Environment.NewLine +
                "netsh http add urlacl url=http://[::]:" + port + "/ user=\"" + user + "\"" + Environment.NewLine +
                "netsh advfirewall firewall delete rule name=\"Lyd Remote API\" >nul 2>&1" + Environment.NewLine +
                "netsh advfirewall firewall delete rule name=\"Lyd Remote API IPv6\" >nul 2>&1" + Environment.NewLine +
                "netsh advfirewall firewall add rule name=\"Lyd Remote API\" dir=in action=allow protocol=TCP localport=" + port + " profile=private,domain" + Environment.NewLine +
                "netsh advfirewall firewall add rule name=\"Lyd Remote API IPv6\" dir=in action=allow protocol=TCP localport=" + port + " profile=private,domain interfacetype=any" + Environment.NewLine +
                "netsh advfirewall firewall delete rule name=\"Lyd Remote mDNS\" >nul 2>&1" + Environment.NewLine +
                "netsh advfirewall firewall add rule name=\"Lyd Remote mDNS\" dir=in action=allow protocol=UDP localport=5353 profile=private,domain" + Environment.NewLine +
                "exit /b 0" + Environment.NewLine;

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
                return p.ExitCode == 0;
            }
            catch (Exception)
            {
                // UAC cancelled or elevation unavailable.
                return false;
            }
        }
    }
}
