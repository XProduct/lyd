import Foundation
import Network

struct DiscoveredHost: Identifiable, Hashable {
    let id: String
    let name: String
    let host: String
    let port: Int
    let txtName: String?

    var endpointLabel: String { "\(host):\(port)" }

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
            resolve(result)
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

    private func resolve(_ result: NWBrowser.Result) {
        let id = resultID(result)
        guard resolvers[id] == nil else { return }

        let connection = NWConnection(to: result.endpoint, using: .tcp)
        resolvers[id] = connection

        connection.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                guard let self else { return }
                switch state {
                case .ready:
                    if let host = self.extractHost(from: connection),
                       let port = connection.currentPath?.remoteEndpoint.flatMap({ self.extractPort($0) })
                        ?? self.extractPort(result.endpoint) {
                        let name: String
                        let txtName: String?
                        if case .service(let serviceName, _, _, _) = result.endpoint {
                            name = serviceName
                        } else {
                            name = id
                        }
                        txtName = Self.txtDisplayName(from: result.metadata)
                        let discovered = DiscoveredHost(
                            id: id,
                            name: name,
                            host: host,
                            port: port,
                            txtName: txtName
                        )
                        if let index = self.hosts.firstIndex(where: { $0.id == id }) {
                            self.hosts[index] = discovered
                        } else {
                            self.hosts.append(discovered)
                            self.hosts.sort { $0.displayTitle.localizedCaseInsensitiveCompare($1.displayTitle) == .orderedAscending }
                        }
                    }
                    connection.cancel()
                    self.resolvers[id] = nil
                case .failed, .cancelled:
                    self.resolvers[id] = nil
                default:
                    break
                }
            }
        }

        connection.start(queue: .main)
    }

    private func extractHost(from connection: NWConnection) -> String? {
        guard let endpoint = connection.currentPath?.remoteEndpoint else { return nil }
        switch endpoint {
        case .hostPort(let host, _):
            switch host {
            case .ipv4(let v4):
                return "\(v4)"
            case .ipv6(let v6):
                return "\(v6)"
            case .name(let name, _):
                return name
            @unknown default:
                return nil
            }
        case .service(let name, let type, let domain, _):
            return "\(name).\(type)\(domain)"
        default:
            return nil
        }
    }

    private func extractPort(_ endpoint: NWEndpoint) -> Int? {
        switch endpoint {
        case .hostPort(_, let port):
            return Int(port.rawValue)
        default:
            return nil
        }
    }

    private static func txtDisplayName(from metadata: NWBrowser.Result.Metadata) -> String? {
        guard case .bonjour(let txt) = metadata else { return nil }
        let value = txt.dictionary["name"] ?? txt.dictionary["Name"]
        guard let value, !value.isEmpty else { return nil }
        return value
    }
}
