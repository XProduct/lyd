import Foundation

struct ManualHost: Hashable, Codable {
    /// Unbracketed host / IP (IPv6 literals allowed).
    var host: String
    var port: Int

    var endpointLabel: String { HostAddress.endpointLabel(host: host, port: port) }
}

/// Persisted host picks — last successful reconnect target plus separate Bonjour / manual memories.
enum HostPreferences {
    private static let lastHostKey = "lyd.lastHost"
    private static let lastPortKey = "lyd.lastPort"
    private static let lastDisplayNameKey = "lyd.lastDisplayName"

    private static let lastManualHostKey = "lyd.lastManualHost"
    private static let lastManualPortKey = "lyd.lastManualPort"

    private static let lastBonjourHostKey = "lyd.lastBonjourHost"
    private static let lastBonjourPortKey = "lyd.lastBonjourPort"
    private static let lastBonjourNameKey = "lyd.lastBonjourDisplayName"

    /// Last host that answered `/health` successfully (auto-reconnect target).
    static var lastSelection: (host: String, port: Int, displayName: String?)? {
        get {
            let defaults = UserDefaults.standard
            guard let host = defaults.string(forKey: lastHostKey), !host.isEmpty else { return nil }
            let port = defaults.object(forKey: lastPortKey) as? Int ?? 8080
            let name = defaults.string(forKey: lastDisplayNameKey)
            return (host, port, name)
        }
        set {
            let defaults = UserDefaults.standard
            if let value = newValue {
                defaults.set(value.host, forKey: lastHostKey)
                defaults.set(value.port, forKey: lastPortKey)
                defaults.set(value.displayName, forKey: lastDisplayNameKey)
            } else {
                defaults.removeObject(forKey: lastHostKey)
                defaults.removeObject(forKey: lastPortKey)
                defaults.removeObject(forKey: lastDisplayNameKey)
            }
        }
    }

    static var lastManual: ManualHost? {
        get {
            let defaults = UserDefaults.standard
            guard let host = defaults.string(forKey: lastManualHostKey), !host.isEmpty else { return nil }
            let port = defaults.object(forKey: lastManualPortKey) as? Int ?? 8080
            return ManualHost(host: host, port: port)
        }
        set {
            let defaults = UserDefaults.standard
            if let value = newValue {
                defaults.set(value.host, forKey: lastManualHostKey)
                defaults.set(value.port, forKey: lastManualPortKey)
            } else {
                defaults.removeObject(forKey: lastManualHostKey)
                defaults.removeObject(forKey: lastManualPortKey)
            }
        }
    }

    static var lastBonjour: (host: String, port: Int, displayName: String?)? {
        get {
            let defaults = UserDefaults.standard
            guard let host = defaults.string(forKey: lastBonjourHostKey), !host.isEmpty else { return nil }
            let port = defaults.object(forKey: lastBonjourPortKey) as? Int ?? 8080
            let name = defaults.string(forKey: lastBonjourNameKey)
            return (host, port, name)
        }
        set {
            let defaults = UserDefaults.standard
            if let value = newValue {
                defaults.set(value.host, forKey: lastBonjourHostKey)
                defaults.set(value.port, forKey: lastBonjourPortKey)
                defaults.set(value.displayName, forKey: lastBonjourNameKey)
            } else {
                defaults.removeObject(forKey: lastBonjourHostKey)
                defaults.removeObject(forKey: lastBonjourPortKey)
                defaults.removeObject(forKey: lastBonjourNameKey)
            }
        }
    }
}
