import Foundation

struct ManualHost: Hashable, Codable {
    var host: String
    var port: Int

    var endpointLabel: String { "\(host):\(port)" }
}

enum HostPreferences {
    private static let lastHostKey = "lyd.lastHost"
    private static let lastPortKey = "lyd.lastPort"
    private static let lastDisplayNameKey = "lyd.lastDisplayName"

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
}
