import SwiftUI

/// Host discovery + manual IP live here (replaces the old full-screen picker / Hosts toolbar button).
struct SettingsView: View {
    @EnvironmentObject private var session: LydSession
    @State private var manualHost = ""
    @State private var manualPort = "8080"
    @State private var didLoadDefaults = false

    var body: some View {
        List {
            ScrollablePageTitle(title: "Settings")
                .scrollableListTitleRow()

            Section {
                switch session.phase {
                case .connected:
                    VStack(alignment: .leading, spacing: 4) {
                        Text(session.selectedDisplayName)
                            .font(.headline)
                        Text(session.selectedEndpoint)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        if !session.isHostReachable {
                            Text(session.offlineMessage ?? "Host unreachable")
                                .font(.footnote)
                                .foregroundStyle(.red)
                            TVContrastButton("Retry connection") {
                                Task { await session.retryHostConnection() }
                            }
                        }
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
                        .font(.footnote)
                    if let last = HostPreferences.lastSelection {
                        TVContrastButton("Retry \(HostAddress.endpointLabel(host: last.host, port: last.port))") {
                            session.reconnectLastIfPossible()
                        }
                    }
                }
            } header: {
                Text("Current host")
            }

            rememberedHostsSection

            Section {
                if session.browser.hosts.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(session.browser.isBrowsing ? "Looking for Lyd on the LAN…" : "Not browsing")
                            .foregroundStyle(.secondary)
                        Text("Service type `_lyd._tcp`. If nothing appears (AP isolation / firewall), use manual IP below.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                } else {
                    ForEach(session.browser.hosts) { host in
                        DiscoveredHostButton(host: host)
                    }
                }
            } header: {
                Text("Discovered hosts")
            }

            #if os(tvOS)
            Section {
                TVContrastButton("Refresh discovery") {
                    session.startDiscovery()
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

                switch session.manualValidateResult {
                case .idle:
                    EmptyView()
                case .checking:
                    HStack {
                        ProgressView()
                        Text("Checking /health…")
                    }
                case .ok(let name, let endpoint):
                    Text("OK — \(name) at \(endpoint)")
                        .foregroundStyle(.green)
                        .font(.footnote)
                case .failed(let message, _):
                    Text(message)
                        .foregroundStyle(.red)
                        .font(.footnote)
                }

                TVContrastButton("Validate") {
                    validateManual(connectAfter: false)
                }
                .disabled(!canConnectManual || session.manualValidateResult == .checking)

                TVContrastButton("Validate & Connect") {
                    validateManual(connectAfter: true)
                }
                .disabled(!canConnectManual || session.manualValidateResult == .checking)
            } header: {
                Text("Manual connection")
            } footer: {
                Text("Validates `GET /api/v1/health` before saving. IPv4 or IPv6 (brackets optional), e.g. 192.168.44.154 or fe80::1 — default port 8080. Last manual and Bonjour hosts are remembered separately.")
            }
        }
        .scrollableNavigationTitle()
        #if os(iOS)
        .toolbarBackground(.visible, for: .navigationBar)
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
                if let manual = HostPreferences.lastManual {
                    manualHost = manual.host
                    manualPort = String(manual.port)
                } else if let last = HostPreferences.lastSelection {
                    manualHost = last.host
                    manualPort = String(last.port)
                } else {
                    manualHost = "192.168.44.154"
                    manualPort = "8080"
                }
            }
        }
    }

    @ViewBuilder
    private var rememberedHostsSection: some View {
        let bonjour = HostPreferences.lastBonjour
        let manual = HostPreferences.lastManual
        if bonjour != nil || manual != nil {
            Section {
                if let bonjour {
                    TVContrastButton("Bonjour: \(bonjour.displayName ?? bonjour.host) — \(HostAddress.endpointLabel(host: bonjour.host, port: bonjour.port))") {
                        session.connect(
                            to: DiscoveredHost(
                                id: "remembered-bonjour",
                                name: bonjour.displayName ?? bonjour.host,
                                host: bonjour.host,
                                port: bonjour.port,
                                txtName: bonjour.displayName
                            )
                        )
                    }
                }
                if let manual {
                    TVContrastButton("Manual: \(manual.endpointLabel)") {
                        session.connect(manual: manual)
                    }
                }
            } header: {
                Text("Remembered")
            }
        }
    }

    private var canConnectManual: Bool {
        !manualHost.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && Int(manualPort).map { (1...65535).contains($0) } == true
    }

    private func validateManual(connectAfter: Bool) {
        guard let port = Int(manualPort) else { return }
        let host = HostAddress.normalize(manualHost)
        Task {
            await session.validateManualHost(ManualHost(host: host, port: port), connectAfter: connectAfter)
        }
    }
}

// MARK: - tvOS focus-safe controls

private struct DiscoveredHostButton: View {
    @EnvironmentObject private var session: LydSession
    let host: DiscoveredHost
    #if os(tvOS)
    @FocusState private var isFocused: Bool
    #endif

    var body: some View {
        Button {
            session.connect(to: host)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(host.displayTitle)
                        .font(.headline)
                        .foregroundStyle(titleColor)
                    Text(host.endpointLabel)
                        .font(.subheadline)
                        .foregroundStyle(subtitleColor)
                }
                Spacer()
                if session.phase == .connected,
                   session.selectedEndpoint == host.endpointLabel {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(checkmarkColor)
                }
            }
            #if os(tvOS)
            .frame(maxWidth: .infinity, alignment: .leading)
            #endif
        }
        #if os(tvOS)
        .focused($isFocused)
        #endif
    }

    private var titleColor: Color {
        #if os(tvOS)
        isFocused ? Color.black : Color.primary
        #else
        Color.primary
        #endif
    }

    private var subtitleColor: Color {
        #if os(tvOS)
        isFocused ? Color.black.opacity(0.65) : Color.secondary
        #else
        Color.secondary
        #endif
    }

    private var checkmarkColor: Color {
        #if os(tvOS)
        isFocused ? Color.black : LydTheme.primary
        #else
        LydTheme.primary
        #endif
    }
}

/// Plain-title button that flips to dark text on the tvOS light focus plate.
private struct TVContrastButton: View {
    let title: String
    let action: () -> Void
    #if os(tvOS)
    @FocusState private var isFocused: Bool
    #endif

    init(_ title: String, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .frame(maxWidth: .infinity, alignment: .leading)
                #if os(tvOS)
                .foregroundStyle(isFocused ? Color.black : Color.primary)
                #endif
        }
        #if os(tvOS)
        .focused($isFocused)
        #endif
    }
}
