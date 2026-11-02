import SwiftUI

/// Inline banner when the session has a host but polls are failing.
struct HostOfflineBanner: View {
    @EnvironmentObject private var session: LydSession

    private var shouldShow: Bool {
        !session.isHostReachable
            && !session.selectedEndpoint.isEmpty
            && session.phase != .pickingHost
            && session.phase != .connecting
    }

    var body: some View {
        if shouldShow, let message = session.offlineMessage {
            VStack(alignment: .leading, spacing: 10) {
                Label("Host offline", systemImage: "wifi.slash")
                    .font(.headline)
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Retry") {
                    Task { await session.retryHostConnection() }
                }
                .buttonStyle(.borderedProminent)
                .tint(LydTheme.primary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(.red.opacity(0.12))
        }
    }
}

/// Shared empty-library / not-connected messaging for Albums & Songs.
struct LibraryEmptyState: View {
    @EnvironmentObject private var session: LydSession
    let libraryKind: LibraryKind

    enum LibraryKind {
        case albums
        case songs

        var symbol: String {
            switch self {
            case .albums: return "square.stack"
            case .songs: return "music.note.list"
            }
        }
    }

    var body: some View {
        switch session.phase {
        case .pickingHost:
            ContentUnavailableView(
                "Not connected",
                systemImage: libraryKind.symbol,
                description: Text("Choose a Lyd host in Settings, or enter a manual IP and port.")
            )
        case .connecting:
            ContentUnavailableView {
                ProgressView()
            } description: {
                Text("Connecting to \(session.selectedEndpoint)…")
            }
        case .error:
            ContentUnavailableView(
                "Can't reach host",
                systemImage: "wifi.exclamationmark",
                description: Text(session.offlineMessage ?? "Open Settings to pick a host or retry.")
            )
        case .connected where !session.isHostReachable:
            ContentUnavailableView(
                "Host offline",
                systemImage: "wifi.slash",
                description: Text(session.offlineMessage ?? "The library may be stale until the host returns.")
            )
        case .connected where session.isLibraryStillLoading:
            ContentUnavailableView(
                "Library is empty or still loading…",
                systemImage: libraryKind.symbol,
                description: Text(
                    "Connected to \(session.selectedDisplayName). Revision \(max(session.library.revision, 0)) — waiting for the Windows host to finish scanning or Dropbox hydration."
                )
            )
        case .connected:
            // Only reached when the sticky latch says this tab never loaded content.
            ContentUnavailableView(
                libraryKind == .albums ? "No albums yet" : "No songs yet",
                systemImage: libraryKind.symbol,
                description: Text(connectedEmptyDescription)
            )
        }
    }

    private var connectedEmptyDescription: String {
        let revision = max(session.library.revision, 0)
        #if os(tvOS)
        return "Revision \(revision). Open Settings and refresh when the host finishes scanning."
        #else
        return "Revision \(revision). Pull to refresh when the host finishes scanning."
        #endif
    }
}
