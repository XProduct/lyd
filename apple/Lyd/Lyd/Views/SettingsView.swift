import SwiftUI

/// Host discovery + manual IP live here (replaces the old full-screen picker / Hosts toolbar button).
struct SettingsView: View {
    @EnvironmentObject private var session: LydSession
    @State private var manualHost = "192.168.44.154"
    @State private var manualPort = "8080"
    @State private var didLoadDefaults = false

    var body: some View {
        List {
            Section {
                switch session.phase {
                case .connected:
                    VStack(alignment: .leading, spacing: 4) {
                        Text(session.selectedDisplayName)
                            .font(.headline)
                        Text(session.selectedEndpoint)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Button("Disconnect", role: .destructive) {
                        session.disconnect()
                    }
                case .connecting:
                    HStack {
                        ProgressView()
                        Text("Connecting to \(session.selectedEndpoint)…")
                    }
                case .pickingHost:
                    Text("Not connected")
                        .foregroundStyle(.secondary)
                case .error(let message):
                    Text(message)
                        .foregroundStyle(.red)
                    if let last = HostPreferences.lastSelection {
                        Button("Retry \(last.host):\(last.port)") {
                            session.reconnectLastIfPossible()
                        }
                    }
                }
            } header: {
                Text("Current host")
            }

            Section {
                if session.browser.hosts.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(session.browser.isBrowsing ? "Looking for Lyd on the LAN…" : "Not browsing")
                            .foregroundStyle(.secondary)
                        Text("Service type `_lyd._tcp`. If nothing appears, use manual IP below.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                } else {
                    ForEach(session.browser.hosts) { host in
                        Button {
                            session.connect(to: host)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(host.displayTitle)
                                        .font(.headline)
                                        .foregroundStyle(Color.primary)
                                    Text(host.endpointLabel)
                                        .font(.subheadline)
                                        .foregroundStyle(Color.secondary)
                                }
                                Spacer()
                                if session.phase == .connected,
                                   session.selectedEndpoint == host.endpointLabel {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(LydTheme.primary)
                                }
                            }
                        }
                    }
                }
            } header: {
                Text("Discovered hosts")
            }

            #if os(tvOS)
            Section {
                Button {
                    session.startDiscovery()
                } label: {
                    Text("Refresh discovery")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            #endif

            Section {
                TextField("Host / IP", text: $manualHost)
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.asciiCapable)
                    .autocorrectionDisabled()
                    #endif
                TextField("Port", text: $manualPort)
                    #if os(iOS)
                    .keyboardType(.numberPad)
                    #endif
                Button("Connect") {
                    connectManual()
                }
                .disabled(!canConnectManual)
            } header: {
                Text("Manual connection")
            } footer: {
                Text("IPv4 or IPv6 (brackets optional), e.g. 192.168.44.154 or fe80::1 — port 8080. Last successful host is remembered.")
            }
        }
        .navigationTitle("Settings")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.visible, for: .navigationBar)
        #endif
        #if os(iOS)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    session.startDiscovery()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            }
        }
        #endif
        // tvOS: refresh lives in the list (toolbar labels clip on the Siri Remote UI).
        .onAppear {
            session.startDiscovery()
            if !didLoadDefaults {
                didLoadDefaults = true
                if let last = HostPreferences.lastSelection {
                    manualHost = last.host
                    manualPort = String(last.port)
                }
            }
        }
    }

    private var canConnectManual: Bool {
        !manualHost.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && Int(manualPort).map { (1...65535).contains($0) } == true
    }

    private func connectManual() {
        guard let port = Int(manualPort) else { return }
        let host = HostAddress.normalize(manualHost)
        session.connect(manual: ManualHost(host: host, port: port))
    }
}
