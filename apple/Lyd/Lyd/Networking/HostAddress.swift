import Foundation
import Network

/// Helpers for IPv4/IPv6 host strings used in Bonjour resolution, Settings, and URLSession.
enum HostAddress {
    /// Strip surrounding `[…]` and whitespace from a typed or stored host.
    static func normalize(_ raw: String) -> String {
        var host = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if host.hasPrefix("["), let close = host.lastIndex(of: "]") {
            host = String(host[host.index(after: host.startIndex)..<close])
        }
        return host
    }

    /// True when `host` looks like an IPv6 literal (with or without brackets / zone id).
    static func isIPv6Literal(_ raw: String) -> Bool {
        let host = normalize(raw)
        if host.contains(":"), IPv6Address(host.split(separator: "%").first.map(String.init) ?? host) != nil {
            return true
        }
        // Zone-scoped link-local often still parses via NWEndpoint / URLComponents.
        if host.contains(":"), !host.contains("."), host.first?.isHexDigit == true || host.hasPrefix("::") || host.lowercased().hasPrefix("fe80:") {
            return true
        }
        return host.contains(":") && !host.contains(".")
    }

    /// Display / compare form: `192.168.1.1:8080` or `[fe80::1]:8080`.
    static func endpointLabel(host raw: String, port: Int) -> String {
        let host = normalize(raw)
        if isIPv6Literal(host) {
            return "[\(host)]:\(port)"
        }
        return "\(host):\(port)"
    }

    /// Build `http://host:port/` with correct IPv6 bracketing via URLComponents.
    static func httpBaseURL(host raw: String, port: Int) -> URL? {
        let host = normalize(raw)
        guard !host.isEmpty, (1...65535).contains(port) else { return nil }

        var components = URLComponents()
        components.scheme = "http"
        // URLComponents.host must be unbracketed; it emits brackets in `.url` for IPv6.
        components.host = host
        components.port = port
        components.path = "/"

        if let url = components.url {
            return url
        }

        // Link-local zone ids (`%en0`) sometimes need percent-encoding in the authority.
        if host.contains("%") {
            let encodedHost = host.replacingOccurrences(of: "%", with: "%25")
            let authority: String
            if isIPv6Literal(host) {
                authority = "[\(encodedHost)]:\(port)"
            } else {
                authority = "\(encodedHost):\(port)"
            }
            return URL(string: "http://\(authority)/")
        }
        return nil
    }
}
