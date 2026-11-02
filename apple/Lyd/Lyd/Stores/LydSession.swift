import Foundation
import Combine
import SwiftUI

enum AppTab: Hashable {
    case albums
    case songs
    case nowPlaying
    case settings
}

@MainActor
final class LydSession: ObservableObject {
    enum Phase: Equatable {
        case pickingHost
        case connecting
        case connected
        case error(String)
    }

    enum ManualValidateResult: Equatable {
        case idle
        case checking
        case ok(name: String, endpoint: String)
        case failed(message: String, endpoint: String)
    }

    @Published var phase: Phase = .pickingHost
    @Published var selectedTab: AppTab = .albums
    @Published var selectedDisplayName: String = "Lyd"
    @Published var selectedEndpoint: String = ""
    @Published private(set) var library = LibraryDto(songs: [], albums: [], revision: -1)
    @Published private(set) var playback = PlaybackStateDto(
        isPlaying: false,
        shuffle: false,
        positionMs: 0,
        durationMs: 0,
        currentSongId: nil,
        currentSong: nil,
        volume: 0.5
    )
    @Published var statusMessage: String?
    @Published var isBusy = false
    /// True once connected; flipped false when health/playback/library polls fail until recovery.
    @Published private(set) var isHostReachable = false
    @Published private(set) var offlineMessage: String?
    @Published var manualValidateResult: ManualValidateResult = .idle

    let browser = BonjourBrowser()

    private var client: LydAPIClient?
    private var libraryPollTask: Task<Void, Never>?
    private var playbackPollTask: Task<Void, Never>?
    private var connectSource: ConnectSource = .unknown

    private enum ConnectSource {
        case bonjour
        case manual
        case unknown
    }

    var songsByID: [String: SongDto] {
        Dictionary(uniqueKeysWithValues: library.songs.map { ($0.id, $0) })
    }

    /// Connected to a healthy host but catalog not populated yet (Dropbox / scan).
    var isLibraryStillLoading: Bool {
        phase == .connected && isHostReachable && library.songs.isEmpty && library.albums.isEmpty
    }

    func songs(for album: AlbumDto) -> [SongDto] {
        let ids = album.songIds ?? []
        let lookup = songsByID
        let mapped = ids.compactMap { lookup[$0] }
        if !mapped.isEmpty { return mapped.sorted(by: Self.trackSort) }
        return library.songs
            .filter { $0.albumId == album.id }
            .sorted(by: Self.trackSort)
    }

    func coverURL(for album: AlbumDto) -> URL? {
        client?.coverURL(for: album.coverUrl)
    }

    func startDiscovery() {
        browser.start()
    }

    func stopDiscovery() {
        browser.stop()
    }

    func connect(to host: DiscoveredHost) {
        connectSource = .bonjour
        connect(host: host.host, port: host.port, displayName: host.displayTitle)
    }

    func connect(manual: ManualHost, displayName: String? = nil) {
        connectSource = .manual
        connect(host: manual.host, port: manual.port, displayName: displayName ?? manual.endpointLabel)
    }

    func reconnectLastIfPossible() {
        guard let last = HostPreferences.lastSelection else { return }
        connectSource = .unknown
        connect(host: last.host, port: last.port, displayName: last.displayName ?? last.host)
    }

    func disconnect(returnToPicker: Bool = true) {
        libraryPollTask?.cancel()
        playbackPollTask?.cancel()
        libraryPollTask = nil
        playbackPollTask = nil
        client = nil
        isHostReachable = false
        offlineMessage = nil
        library = LibraryDto(songs: [], albums: [], revision: -1)
        playback = PlaybackStateDto(
            isPlaying: false,
            shuffle: false,
            positionMs: 0,
            durationMs: 0,
            currentSongId: nil,
            currentSong: nil,
            volume: 0.5
        )
        if returnToPicker {
            phase = .pickingHost
            startDiscovery()
        }
    }

    /// Validate manual host with `/health` before saving. Does not change the active session unless `connectAfter` is true.
    func validateManualHost(_ manual: ManualHost, connectAfter: Bool) async {
        let host = HostAddress.normalize(manual.host)
        let endpoint = HostAddress.endpointLabel(host: host, port: manual.port)
        guard let url = LydAPIClient.baseURL(host: host, port: manual.port) else {
            manualValidateResult = .failed(message: "Invalid host or port", endpoint: endpoint)
            return
        }

        manualValidateResult = .checking
        let probe = LydAPIClient(baseURL: url)
        do {
            let health = try await probe.health()
            let name = health.name.isEmpty ? endpoint : health.name
            HostPreferences.lastManual = ManualHost(host: host, port: manual.port)
            manualValidateResult = .ok(name: name, endpoint: endpoint)
            if connectAfter {
                connect(manual: ManualHost(host: host, port: manual.port), displayName: name)
            }
        } catch {
            let detail = "\(error.localizedDescription) — tried \(url.absoluteString)"
            manualValidateResult = .failed(message: detail, endpoint: endpoint)
        }
    }

    func refreshLibrary(force: Bool = false) async {
        guard let client else { return }
        do {
            let result = try await client.syncLibrary(knownRevision: library.revision, force: force)
            switch result {
            case .unchanged:
                markReachable()
            case .updated(let next):
                library = next
                markReachable()
            }
        } catch {
            markUnreachable(error)
        }
    }

    func refreshPlayback() async {
        guard let client else { return }
        do {
            playback = try await client.playbackState()
            markReachable()
        } catch {
            markUnreachable(error)
        }
    }

    /// Foreground / Retry: ping health then resume polls if the host is back.
    func retryHostConnection() async {
        if client == nil {
            reconnectLastIfPossible()
            return
        }
        guard let client else { return }
        do {
            let health = try await client.health()
            if !health.name.isEmpty {
                selectedDisplayName = health.name
            }
            markReachable()
            if phase != .connected {
                phase = .connected
            }
            await refreshLibrary(force: false)
            await refreshPlayback()
            startPolling()
        } catch {
            markUnreachable(error)
        }
    }

    func handleScenePhase(_ scenePhase: ScenePhase) {
        guard scenePhase == .active else { return }
        startDiscovery()
        if client != nil || HostPreferences.lastSelection != nil {
            Task { await retryHostConnection() }
        }
    }

    func play(songId: String) async {
        selectedTab = .nowPlaying
        await mutate { try await $0.play(songId: songId) }
    }

    /// Shuffle off + play album in disc/track order (Windows `play-album`).
    func playAlbum(albumId: String) async {
        selectedTab = .nowPlaying
        await mutate { client in
            try? await client.shuffle(enabled: false)
            try await client.playAlbum(albumId: albumId)
        }
    }

    func playPause() async {
        await mutate { try await $0.playPause() }
    }

    func pause() async {
        await mutate { try await $0.pause() }
    }

    func next() async {
        await mutate { try await $0.next() }
    }

    func previous() async {
        await mutate { try await $0.previous() }
    }

    func toggleShuffle() async {
        await mutate { try await $0.shuffle(enabled: nil) }
    }

    func seek(positionMs: Int64) async {
        await mutate { try await $0.seek(positionMs: positionMs) }
    }

    func setVolume(_ level: Double) async {
        playback.volume = level
        await mutate { try await $0.setVolume(level: level) }
    }

    // MARK: - Private

    private func connect(host: String, port: Int, displayName: String) {
        let normalizedHost = HostAddress.normalize(host)
        guard let url = LydAPIClient.baseURL(host: normalizedHost, port: port) else {
            phase = .error("Invalid host")
            return
        }

        disconnect(returnToPicker: false)
        // Keep Bonjour browsing while connecting so iOS Local Network permission /
        // browse results are not torn down if auto-reconnect fails.
        phase = .connecting
        selectedDisplayName = displayName
        selectedEndpoint = HostAddress.endpointLabel(host: normalizedHost, port: port)
        let api = LydAPIClient(baseURL: url)
        client = api
        isBusy = true
        statusMessage = nil
        offlineMessage = nil

        Task {
            do {
                let health = try await api.health()
                let resolvedName = health.name.isEmpty ? displayName : health.name
                HostPreferences.lastSelection = (normalizedHost, port, resolvedName)
                switch connectSource {
                case .bonjour:
                    HostPreferences.lastBonjour = (normalizedHost, port, resolvedName)
                case .manual:
                    HostPreferences.lastManual = ManualHost(host: normalizedHost, port: port)
                case .unknown:
                    break
                }
                selectedDisplayName = resolvedName
                let lib = try await api.library()
                library = lib
                playback = try await api.playbackState()
                phase = .connected
                markReachable()
                startPolling()
                startDiscovery()
            } catch {
                let detail = "\(error.localizedDescription) — tried \(url.absoluteString)"
                phase = .error(detail)
                client = nil
                isHostReachable = false
                offlineMessage = detail
                startDiscovery()
            }
            isBusy = false
        }
    }

    private func startPolling() {
        libraryPollTask?.cancel()
        playbackPollTask?.cancel()

        libraryPollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                await self?.refreshLibrary(force: false)
            }
        }

        playbackPollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                await self?.refreshPlayback()
            }
        }
    }

    private func mutate(_ work: (LydAPIClient) async throws -> Void) async {
        guard let client else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            try await work(client)
            playback = try await client.playbackState()
            statusMessage = nil
            markReachable()
        } catch {
            statusMessage = error.localizedDescription
            markUnreachable(error)
        }
    }

    private func markReachable() {
        isHostReachable = true
        offlineMessage = nil
        if case .error = phase {
            phase = .connected
        }
    }

    private func markUnreachable(_ error: Error) {
        isHostReachable = false
        let message = error.localizedDescription
        offlineMessage = selectedEndpoint.isEmpty
            ? message
            : "Can't reach \(selectedEndpoint) — \(message)"
        statusMessage = offlineMessage
    }

    private static func trackSort(_ lhs: SongDto, _ rhs: SongDto) -> Bool {
        let ld = lhs.disc ?? 0
        let rd = rhs.disc ?? 0
        if ld != rd { return ld < rd }
        let lt = lhs.track ?? 0
        let rt = rhs.track ?? 0
        if lt != rt { return lt < rt }
        return (lhs.title ?? "") < (rhs.title ?? "")
    }
}
