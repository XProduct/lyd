import Foundation
import Network

/// Helpers for IPv4/IPv6 host strings used in Bonjour resolution, Settings, and URLSession.
enum HostAddress {
    /// Strip brackets, whitespace, and interface/zone suffixes (`%en1`, `%25en1`, `%0`).
    static func normalize(_ raw: String) -> String {
        var host = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if host.hasPrefix("["), let close = host.lastIndex(of: "]") {
            host = String(host[host.index(after: host.startIndex)..<close])
        }
        // Decode a single `%25` zone separator if present, then drop the zone id.
        if let range = host.range(of: "%25", options: [.caseInsensitive, .backwards]),
           range.upperBound < host.endIndex {
            // Only treat as zone encoding when it looks like `%25en0` / `%250`.
            let after = host[range.upperBound...]
            if after.first?.isLetter == true || after.first?.isNumber == true {
                host = String(host[..<range.lowerBound])
            }
        }
        if let idx = host.firstIndex(of: "%") {
            host = String(host[..<idx])
        }
        return host
    }

    /// True when `host` looks like an IPv6 literal (with or without brackets / zone id).
    static func isIPv6Literal(_ raw: String) -> Bool {
        let host = normalize(raw)
        if host.contains(":"), IPv6Address(host) != nil {
            return true
        }
        return host.contains(":") && !host.contains(".")
    }

    /// Display / compare form: `192.168.1.1:8080` or `[fe80::1]:8080` (never includes zone id).
    static func endpointLabel(host raw: String, port: Int) -> String {
        let host = normalize(raw)
        if isIPv6Literal(host) {
            return "[\(host)]:\(port)"
        }
        return "\(host):\(port)"
    }

    /// Build `http://host:port/` with correct IPv6 bracketing; never embeds zone/interface ids.
    static func httpBaseURL(host raw: String, port: Int) -> URL? {
        let host = normalize(raw)
        guard !host.isEmpty, (1...65535).contains(port) else { return nil }

        var components = URLComponents()
        components.scheme = "http"
        // URLComponents.host must be unbracketed; it emits brackets in `.url` for IPv6.
        components.host = host
        components.port = port
        components.path = "/"
        return components.url
    }
}
