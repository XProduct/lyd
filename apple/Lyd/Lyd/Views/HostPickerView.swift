import SwiftUI

struct HostPickerView: View {
    @EnvironmentObject private var session: LydSession
    @State private var manualHost = "192.168.44.154"
    @State private var manualPort = "8080"
    @State private var didTryLast = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if session.browser.hosts.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(session.browser.isBrowsing ? "Looking for Lyd on the LAN…" : "Not browsing")
                                .foregroundStyle(.secondary)
                            Text("Service type `_lyd._tcp`. If nothing appears (common on some Windows mDNS setups), use manual IP below.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    } else {
                        ForEach(session.browser.hosts) { host in
                            Button {
                                session.connect(to: host)
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(host.displayTitle)
                                        .font(.headline)
                                    Text(host.endpointLabel)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                } header: {
                    Text("Discovered hosts")
                }

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
                    Text("Example Windows host: 192.168.44.154 port 8080 → http://192.168.44.154:8080/api/v1")
                }

                if case .connecting = session.phase {
                    Section {
                        HStack {
                            ProgressView()
                            Text("Connecting to \(session.selectedEndpoint)…")
                        }
                    }
                }

                if case .error(let message) = session.phase {
                    Section {
                        Text(message)
                            .foregroundStyle(.red)
                        if let last = HostPreferences.lastSelection {
                            Button("Retry \(last.host):\(last.port)") {
                                session.reconnectLastIfPossible()
                            }
                        }
                    } header: {
                        Text("Connection error")
                    }
                }
            }
            .navigationTitle("Lyd Remote")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.large)
            #endif
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        session.browser.start()
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                }
            }
            .onAppear {
                if !didTryLast {
                    didTryLast = true
                    if let last = HostPreferences.lastSelection {
                        manualHost = last.host
                        manualPort = String(last.port)
                    }
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
        let host = manualHost.trimmingCharacters(in: .whitespacesAndNewlines)
        session.connect(manual: ManualHost(host: host, port: port))
    }
}
