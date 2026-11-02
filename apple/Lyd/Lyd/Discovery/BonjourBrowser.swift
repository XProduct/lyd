import Foundation
import Network

struct DiscoveredHost: Identifiable, Hashable {
    let id: String
    let name: String
    /// Unbracketed host: IPv4, IPv6, or `.local` name.
    let host: String
    let port: Int
    let txtName: String?

    var endpointLabel: String { HostAddress.endpointLabel(host: host, port: port) }

    var displayTitle: String {
        if let txtName, !txtName.isEmpty { return txtName }
        return name
    }
}

@MainActor
final class BonjourBrowser: ObservableObject {
    @Published private(set) var hosts: [DiscoveredHost] = []
    @Published private(set) var isBrowsing = false
    @Published var lastError: String?

    private var browser: NWBrowser?
    private var resolvers: [String: NWConnection] = [:]

    func start() {
        stop()
        lastError = nil
        isBrowsing = true

        let descriptor = NWBrowser.Descriptor.bonjour(type: "_lyd._tcp", domain: "local.")
        let params = NWParameters()
        params.includePeerToPeer = true
        let browser = NWBrowser(for: descriptor, using: params)
        self.browser = browser

        browser.stateUpdateHandler = { [weak self] newState in
            Task { @MainActor in
                guard let self else { return }
                switch newState {
                case .failed(let error):
                    self.lastError = error.localizedDescription
                    self.isBrowsing = false
                case .ready:
                    self.isBrowsing = true
                case .cancelled:
                    self.isBrowsing = false
                default:
                    break
                }
            }
        }

        browser.browseResultsChangedHandler = { [weak self] results, _ in
            Task { @MainActor in
                self?.handle(results: results)
            }
        }

        browser.start(queue: .main)
    }

    func stop() {
        browser?.cancel()
        browser = nil
        resolvers.values.forEach { $0.cancel() }
        resolvers.removeAll()
        isBrowsing = false
    }

    private func handle(results: Set<NWBrowser.Result>) {
        let currentIDs = Set(results.map { resultID($0) })
        hosts.removeAll { !currentIDs.contains($0.id) }

        for result in results {
            let id = resultID(result)
            if hosts.contains(where: { $0.id == id }) { continue }
            // Prefer IPv4 (Windows Phase A advertises/binds IPv4); fall back to any.
            resolve(result, preferIPv4: true)
        }
    }

    private func resultID(_ result: NWBrowser.Result) -> String {
        switch result.endpoint {
        case .service(let name, let type, let domain, _):
            return "\(name).\(type).\(domain)"
        default:
            return String(describing: result.endpoint)
        }
    }

    private func resolve(_ result: NWBrowser.Result, preferIPv4: Bool) {
        let id = resultID(result)
        let resolverKey = preferIPv4 ? "\(id)#v4" : "\(id)#any"
        guard resolvers[resolverKey] == nil else { return }

        let connection = NWConnection(to: result.endpoint, using: Self.tcpParameters(preferIPv4: preferIPv4))
        resolvers[resolverKey] = connection

        connection.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                guard let self else { return }
                switch state {
                case .ready:
                    if let resolved = self.makeDiscoveredHost(id: id, result: result, connection: connection) {
                        self.upsert(resolved)
                        connection.cancel()
                        self.resolvers[resolverKey] = nil
                        // Cancel the alternate attempt if still pending.
                        let otherKey = preferIPv4 ? "\(id)#any" : "\(id)#v4"
                        self.resolvers[otherKey]?.cancel()
                        self.resolvers[otherKey] = nil
                    } else {
                        connection.cancel()
                        self.resolvers[resolverKey] = nil
                        if preferIPv4 {
                            self.resolve(result, preferIPv4: false)
                        }
                    }
                case .failed:
                    self.resolvers[resolverKey] = nil
                    if preferIPv4 {
                        self.resolve(result, preferIPv4: false)
                    }
                case .cancelled:
                    self.resolvers[resolverKey] = nil
                default:
                    break
                }
            }
        }

        connection.start(queue: .main)
    }

    private func upsert(_ discovered: DiscoveredHost) {
        if let index = hosts.firstIndex(where: { $0.id == discovered.id }) {
            let existing = hosts[index]
            // Prefer keeping an IPv4 endpoint over replacing it with IPv6.
            if HostAddress.isIPv6Literal(discovered.host), !HostAddress.isIPv6Literal(existing.host) {
                return
            }
            hosts[index] = discovered
        } else {
            hosts.append(discovered)
            hosts.sort { $0.displayTitle.localizedCaseInsensitiveCompare($1.displayTitle) == .orderedAscending }
        }
    }

    private func makeDiscoveredHost(id: String, result: NWBrowser.Result, connection: NWConnection) -> DiscoveredHost? {
        let name: String
        if case .service(let serviceName, _, _, _) = result.endpoint {
            name = serviceName
        } else {
            name = id
        }
        let txtName = Self.txtDisplayName(from: result.metadata)

        guard let endpoint = connection.currentPath?.remoteEndpoint else {
            // Fall back to Bonjour service name — URLSession can resolve .local Happy-Eyeballs style.
            if case .service(let serviceName, _, let domain, _) = result.endpoint {
                let hostName = Self.localHostName(serviceName: serviceName, domain: domain)
                let port = Self.portFromTXTOrDefault(result: result) ?? 8080
                return DiscoveredHost(id: id, name: name, host: hostName, port: port, txtName: txtName)
            }
            return nil
        }

        guard let host = Self.hostString(from: endpoint),
              let port = Self.port(from: endpoint) ?? Self.portFromTXTOrDefault(result: result) else {
            return nil
        }

        return DiscoveredHost(id: id, name: name, host: host, port: port, txtName: txtName)
    }

    private static func tcpParameters(preferIPv4: Bool) -> NWParameters {
        let parameters = NWParameters.tcp
        parameters.includePeerToPeer = true
        if preferIPv4, let ipOptions = parameters.defaultProtocolStack.internetProtocol as? NWProtocolIP.Options {
            ipOptions.version = .v4
        }
        return parameters
    }

    private static func hostString(from endpoint: NWEndpoint) -> String? {
        switch endpoint {
        case .hostPort(let host, _):
            switch host {
            case .ipv4(let v4):
                return "\(v4)"
            case .ipv6(let v6):
                // NWProtocolIP may include zone; keep as reported for URLComponents.
                return "\(v6)"
            case .name(let name, _):
                return name
            @unknown default:
                return nil
            }
        case .service(let name, _, let domain, _):
            return localHostName(serviceName: name, domain: domain)
        default:
            return nil
        }
    }

    private static func port(from endpoint: NWEndpoint) -> Int? {
        switch endpoint {
        case .hostPort(_, let port):
            return Int(port.rawValue)
        default:
            return nil
        }
    }

    private static func localHostName(serviceName: String, domain: String) -> String {
        var d = domain
        if !d.hasSuffix(".") { d += "." }
        // Prefer short .local form when possible.
        if d.lowercased().hasPrefix("local") {
            return "\(serviceName).local"
        }
        return "\(serviceName).\(d)".trimmingCharacters(in: CharacterSet(charactersIn: "."))
    }

    private static func portFromTXTOrDefault(result: NWBrowser.Result) -> Int? {
        // Port comes from the service SRV record via NWConnection path; default for Lyd.
        if case .hostPort(_, let port) = result.endpoint {
            return Int(port.rawValue)
        }
        return 8080
    }

    private static func txtDisplayName(from metadata: NWBrowser.Result.Metadata) -> String? {
        guard case .bonjour(let txt) = metadata else { return nil }
        let value = txt.dictionary["name"] ?? txt.dictionary["Name"]
        guard let value, !value.isEmpty else { return nil }
        return value
    }
}
