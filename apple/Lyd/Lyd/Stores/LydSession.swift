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
    /// Phase E: where audio renders for the shared host session.
    @Published var playingOn: PlaybackOutputMode = .host

    let browser = BonjourBrowser()
    let localPlayer = LocalStreamPlayer()

    private var client: LydAPIClient?
    private var libraryPollTask: Task<Void, Never>?
    private var playbackPollTask: Task<Void, Never>?
    private var connectSource: ConnectSource = .unknown
    private var localPlayerConfigured = false
    private var localPlayerCancellables = Set<AnyCancellable>()

    /// Volume UI should drive the device AVPlayer only when Playing on this device.
    var usesDeviceVolume: Bool { playingOn == .thisDevice }

    var effectiveIsPlaying: Bool {
        playingOn == .thisDevice ? localPlayer.isPlaying : playback.isPlaying
    }

    var effectivePositionMs: Int64 {
        playingOn == .thisDevice ? localPlayer.positionMs : playback.positionMs
    }

    var effectiveDurationMs: Int64 {
        if playingOn == .thisDevice, localPlayer.durationMs > 0 {
            return localPlayer.durationMs
        }
        return playback.durationMs
    }

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

    /// Best-effort next track for “next up” peek (album order, then library order).
    func predictedNextSong(after current: SongDto?) -> SongDto? {
        guard let current else { return nil }
        if let albumId = current.albumId,
           let album = library.albums.first(where: { $0.id == albumId }) {
            let tracks = songs(for: album)
            if let idx = tracks.firstIndex(where: { $0.id == current.id }),
               idx + 1 < tracks.count {
                return tracks[idx + 1]
            }
        }
        let all = library.songs
        if let idx = all.firstIndex(where: { $0.id == current.id }),
           idx + 1 < all.count {
            return all[idx + 1]
        }
        return nil
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
        localPlayer.stop()
        playingOn = .host
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
            let remote = try await client.playbackState()
            markReachable()
            await applyHostPlaybackState(remote)
        } catch {
            markUnreachable(error)
        }
    }

    /// Phase E: transfer audio renderer between host irrKlang and this device’s AVPlayer.
    func setPlayingOn(_ mode: PlaybackOutputMode) async {
        guard client != nil else { return }
        let previous = playingOn
        guard previous != mode else { return }

        let wasPlaying = effectiveIsPlaying
        let position = effectivePositionMs
        let songId = playback.currentSongId

        if mode == .thisDevice {
            playingOn = .thisDevice
            await notifyHostOutput(remote: true)
            // Silence host if output API missing on older builds.
            try? await client?.pause()
            if let songId {
                await startLocalStream(songId: songId, atMs: position, autoplay: wasPlaying)
            }
        } else {
            let handoffMs = localPlayer.positionMs > 0 ? localPlayer.positionMs : position
            localPlayer.stop()
            playingOn = .host
            await notifyHostOutput(remote: false)
            if let songId {
                try? await client?.seek(positionMs: handoffMs)
                if wasPlaying {
                    // Host was paused for remote output; nudge play.
                    try? await client?.play(songId: songId)
                    try? await client?.seek(positionMs: handoffMs)
                }
            }
            await refreshPlayback()
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
        if playingOn == .thisDevice {
            await startLocalStream(songId: songId, atMs: 0, autoplay: true)
        }
    }

    /// Shuffle off + play album in disc/track order (Windows `play-album`).
    func playAlbum(albumId: String) async {
        selectedTab = .nowPlaying
        await mutate { client in
            try? await client.shuffle(enabled: false)
            try await client.playAlbum(albumId: albumId)
        }
        if playingOn == .thisDevice, let songId = playback.currentSongId {
            await startLocalStream(songId: songId, atMs: 0, autoplay: true)
        }
    }

    func playPause() async {
        if playingOn == .thisDevice {
            localPlayer.playPause()
            // Keep shared session roughly aligned without starting host audio.
            if localPlayer.isPlaying {
                try? await client?.seek(positionMs: localPlayer.positionMs)
            } else {
                try? await client?.pause()
            }
            return
        }
        await mutate { try await $0.playPause() }
    }

    func pause() async {
        if playingOn == .thisDevice {
            localPlayer.pause()
            try? await client?.pause()
            return
        }
        await mutate { try await $0.pause() }
    }

    func next() async {
        await mutate { try await $0.next() }
        if playingOn == .thisDevice, let songId = playback.currentSongId {
            await startLocalStream(songId: songId, atMs: 0, autoplay: true)
        }
    }

    func previous() async {
        await mutate { try await $0.previous() }
        if playingOn == .thisDevice, let songId = playback.currentSongId {
            await startLocalStream(songId: songId, atMs: 0, autoplay: true)
        }
    }

    func toggleShuffle() async {
        await mutate { try await $0.shuffle(enabled: nil) }
    }

    func seek(positionMs: Int64) async {
        if playingOn == .thisDevice {
            await localPlayer.seek(positionMs: positionMs)
            try? await client?.seek(positionMs: positionMs)
            return
        }
        await mutate { try await $0.seek(positionMs: positionMs) }
    }

    func setVolume(_ level: Double) async {
        let clamped = min(max(level, 0), 1)
        if playingOn == .thisDevice {
            localPlayer.volume = Float(clamped)
            playback.volume = clamped
            return
        }
        playback.volume = clamped
        await mutate { try await $0.setVolume(level: clamped) }
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
                configureLocalPlayerIfNeeded()
                if playback.outputTarget == "remote",
                   playback.outputDeviceId == DeviceIdentity.deviceId {
                    playingOn = .thisDevice
                    if let songId = playback.currentSongId {
                        await startLocalStream(
                            songId: songId,
                            atMs: playback.positionMs,
                            autoplay: true
                        )
                    }
                } else {
                    playingOn = .host
                }
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
            let remote = try await client.playbackState()
            await applyHostPlaybackState(remote)
            statusMessage = nil
            markReachable()
        } catch {
            statusMessage = error.localizedDescription
            markUnreachable(error)
        }
    }

    private func configureLocalPlayerIfNeeded() {
        guard !localPlayerConfigured else { return }
        localPlayerConfigured = true
        localPlayer.configureAudioSession()
        localPlayer.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &localPlayerCancellables)
        localPlayer.onFinished = { [weak self] in
            Task { @MainActor in
                guard let self, self.playingOn == .thisDevice else { return }
                await self.next()
            }
        }
    }

    private func notifyHostOutput(remote: Bool) async {
        guard let client else { return }
        do {
            try await client.setPlaybackOutput(
                target: remote ? "remote" : "host",
                deviceId: remote ? DeviceIdentity.deviceId : nil,
                deviceName: remote ? DeviceIdentity.displayName : nil
            )
        } catch {
            // Older hosts without /playback/output — Apple still pauses host explicitly.
            statusMessage = nil
        }
    }

    private func startLocalStream(songId: String, atMs: Int64, autoplay: Bool) async {
        guard let client, let url = client.streamURL(songId: songId) else {
            statusMessage = "Stream URL unavailable"
            return
        }
        configureLocalPlayerIfNeeded()
        localPlayer.play(url: url, songId: songId, startAtMs: max(0, atMs))
        if !autoplay {
            localPlayer.pause()
        }
        // Ensure host stays silent while we render.
        try? await client.pause()
    }

    private func applyHostPlaybackState(_ remote: PlaybackStateDto) async {
        if playingOn == .thisDevice {
            // Shared session: take song/shuffle from host; position/playing from AVPlayer.
            var merged = remote
            merged.isPlaying = localPlayer.isPlaying
            merged.positionMs = localPlayer.positionMs
            if localPlayer.durationMs > 0 {
                merged.durationMs = localPlayer.durationMs
            }
            merged.volume = Double(localPlayer.volume)
            playback = merged

            if let songId = remote.currentSongId, songId != localPlayer.currentSongId {
                // Shared session song changed (another remote, or host). Keep local play/pause.
                let shouldPlay = localPlayer.isPlaying
                await startLocalStream(songId: songId, atMs: 0, autoplay: shouldPlay)
            }
        } else {
            playback = remote
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
