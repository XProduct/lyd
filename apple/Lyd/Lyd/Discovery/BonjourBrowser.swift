import Foundation
import Network

struct DiscoveredHost: Identifiable, Hashable {
    let id: String
    let name: String
    /// Unbracketed host: IPv4, IPv6 (no zone), or `.local` name.
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
        // Empty NWParameters is the documented browse configuration (do not force TCP/IP version here).
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
                    self.lastError = nil
                case .waiting(let error):
                    // Common on iOS until Local Network permission is granted — keep browsing.
                    self.lastError = error.localizedDescription
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
            // Publish a usable `.local` host immediately so iPad/tvOS both show rows
            // even before TCP resolve completes (resolve can hang on some interfaces).
            if !hosts.contains(where: { $0.id == id }) {
                if let placeholder = placeholderHost(id: id, result: result) {
                    upsert(placeholder)
                }
            }
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

    private func placeholderHost(id: String, result: NWBrowser.Result) -> DiscoveredHost? {
        guard case .service(let serviceName, _, let domain, _) = result.endpoint else { return nil }
        return DiscoveredHost(
            id: id,
            name: serviceName,
            host: Self.localHostName(serviceName: serviceName, domain: domain),
            port: 8080,
            txtName: Self.txtDisplayName(from: result.metadata)
        )
    }

    private func resolve(_ result: NWBrowser.Result, preferIPv4: Bool) {
        let id = resultID(result)
        let resolverKey = preferIPv4 ? "\(id)#v4" : "\(id)#any"
        guard resolvers[resolverKey] == nil else { return }

        let connection = NWConnection(to: result.endpoint, using: Self.tcpParameters(preferIPv4: preferIPv4))
        resolvers[resolverKey] = connection

        // Don't leave iPad waiting forever on a stuck IPv4-only resolve.
        let timeout = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            guard self.resolvers[resolverKey] != nil else { return }
            connection.cancel()
            self.resolvers[resolverKey] = nil
            if preferIPv4 {
                self.resolve(result, preferIPv4: false)
            }
        }

        connection.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                guard let self else { return }
                switch state {
                case .ready:
                    timeout.cancel()
                    if let resolved = self.makeDiscoveredHost(id: id, result: result, connection: connection) {
                        self.upsert(resolved)
                        let otherKey = preferIPv4 ? "\(id)#any" : "\(id)#v4"
                        self.resolvers[otherKey]?.cancel()
                        self.resolvers[otherKey] = nil
                    } else if preferIPv4 {
                        self.resolve(result, preferIPv4: false)
                    }
                    connection.cancel()
                    self.resolvers[resolverKey] = nil
                case .failed:
                    timeout.cancel()
                    self.resolvers[resolverKey] = nil
                    if preferIPv4 {
                        self.resolve(result, preferIPv4: false)
                    }
                case .cancelled:
                    timeout.cancel()
                    self.resolvers[resolverKey] = nil
                default:
                    break
                }
            }
        }

        connection.start(queue: .main)
    }

    private func upsert(_ discovered: DiscoveredHost) {
        let cleaned = DiscoveredHost(
            id: discovered.id,
            name: discovered.name,
            host: HostAddress.normalize(discovered.host),
            port: discovered.port,
            txtName: discovered.txtName
        )
        if let index = hosts.firstIndex(where: { $0.id == cleaned.id }) {
            let existing = hosts[index]
            let existingIsName = existing.host.contains(".") && existing.host.lowercased().hasSuffix("local")
                || (!HostAddress.isIPv6Literal(existing.host) && existing.host.contains(where: { $0.isLetter }))
            let newIsIP = IPv4Address(cleaned.host) != nil || HostAddress.isIPv6Literal(cleaned.host)
            // Prefer concrete IPs over `.local` placeholders; prefer IPv4 over IPv6.
            if HostAddress.isIPv6Literal(cleaned.host), IPv4Address(existing.host) != nil {
                return
            }
            if existingIsName, newIsIP {
                hosts[index] = cleaned
                return
            }
            if IPv4Address(cleaned.host) != nil {
                hosts[index] = cleaned
                return
            }
            if HostAddress.isIPv6Literal(existing.host), IPv4Address(cleaned.host) != nil {
                hosts[index] = cleaned
                return
            }
            // Keep existing usable entry unless we have nothing better.
            if existing.host.isEmpty {
                hosts[index] = cleaned
            }
        } else {
            hosts.append(cleaned)
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
            if case .service(let serviceName, _, let domain, _) = result.endpoint {
                return DiscoveredHost(
                    id: id,
                    name: name,
                    host: Self.localHostName(serviceName: serviceName, domain: domain),
                    port: 8080,
                    txtName: txtName
                )
            }
            return nil
        }

        guard let host = Self.hostString(from: endpoint).map(HostAddress.normalize),
              !host.isEmpty,
              let port = Self.port(from: endpoint) else {
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
                // Avoid String(describing:) picking up unexpected interface decorations.
                let bytes = v4.rawValue
                return "\(bytes[0]).\(bytes[1]).\(bytes[2]).\(bytes[3])"
            case .ipv6(let v6):
                return HostAddress.normalize("\(v6)")
            case .name(let name, _):
                return HostAddress.normalize(name)
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
        if d.lowercased().hasPrefix("local") {
            return "\(serviceName).local"
        }
        return "\(serviceName).\(d)".trimmingCharacters(in: CharacterSet(charactersIn: "."))
    }

    private static func txtDisplayName(from metadata: NWBrowser.Result.Metadata) -> String? {
        guard case .bonjour(let txt) = metadata else { return nil }
        let value = txt.dictionary["name"] ?? txt.dictionary["Name"]
        guard let value, !value.isEmpty else { return nil }
        return value
    }
}
