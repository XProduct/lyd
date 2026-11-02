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
    /// Phase E: multi-select Playing on device ids (`LydOutputIds.host` and/or player ids).
    @Published private(set) var outputTargetIds: Set<String> = [LydOutputIds.host]
    /// Other registered Apple players on this host (excludes this device in the UI list).
    @Published private(set) var registeredPlayers: [PlayerDto] = []

    let browser = BonjourBrowser()
    let localPlayer = LocalStreamPlayer()

    private var client: LydAPIClient?
    private var libraryPollTask: Task<Void, Never>?
    private var playbackPollTask: Task<Void, Never>?
    private var playerHeartbeatTask: Task<Void, Never>?
    private var connectSource: ConnectSource = .unknown
    private var localPlayerConfigured = false
    private var localPlayerCancellables = Set<AnyCancellable>()
    /// Last seek generation applied to AVPlayer (host bumps on seek / track start).
    private var lastAppliedSeekGeneration: Int64 = -1
    /// Suppress host→local play/pause echo for a moment after local transport.
    private var ignoreHostTransportUntil: Date?
    private var lastPlayerRegisterAt: Date?
    /// Optimistic Playing on selection — polls must not clobber until host matches or grace ends.
    private var pendingOutputTargetIds: Set<String>?
    private var pendingOutputUntil: Date?

    /// This device is checked in Playing on → AVPlayer renders; unchecked = remote-only UI.
    var isLocalAudioOutput: Bool { outputTargetIds.contains(DeviceIdentity.deviceId) }

    var isHostAudioOutput: Bool { outputTargetIds.contains(LydOutputIds.host) }

    /// Volume UI should drive the device AVPlayer only when this device is an output.
    var usesDeviceVolume: Bool { isLocalAudioOutput }

    var effectiveIsPlaying: Bool {
        isLocalAudioOutput ? localPlayer.isPlaying : playback.isPlaying
    }

    var effectivePositionMs: Int64 {
        isLocalAudioOutput ? localPlayer.positionMs : playback.positionMs
    }

    var effectiveDurationMs: Int64 {
        if isLocalAudioOutput, localPlayer.durationMs > 0 {
            return localPlayer.durationMs
        }
        return playback.durationMs
    }

    var playingOnSummary: String {
        var parts: [String] = []
        if isHostAudioOutput {
            parts.append(selectedDisplayName.isEmpty ? "Host" : selectedDisplayName)
        }
        if isLocalAudioOutput {
            parts.append("This device")
        }
        for player in registeredPlayers where outputTargetIds.contains(player.deviceId)
            && player.deviceId != DeviceIdentity.deviceId {
            parts.append(player.displayName)
        }
        return parts.isEmpty ? "None" : parts.joined(separator: ", ")
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
        playerHeartbeatTask?.cancel()
        libraryPollTask = nil
        playbackPollTask = nil
        playerHeartbeatTask = nil
        let outgoing = client
        Task {
            try? await outgoing?.unregisterPlayer(deviceId: DeviceIdentity.deviceId)
        }
        localPlayer.stop()
        outputTargetIds = [LydOutputIds.host]
        pendingOutputTargetIds = nil
        pendingOutputUntil = nil
        registeredPlayers = []
        lastAppliedSeekGeneration = -1
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
                applyLibraryUpdate(next, force: force)
                markReachable()
            }
        } catch {
            markUnreachable(error)
        }
    }

    /// Avoid blanking tvOS/iOS grids: skip no-op publishes and keep stable album/song identities.
    private func applyLibraryUpdate(_ next: LibraryDto, force: Bool) {
        if !force,
           library.revision >= 0,
           next.revision == library.revision {
            return
        }

        let sameAlbumIDs = library.albums.map(\.id) == next.albums.map(\.id)
        let sameSongIDs = library.songs.map(\.id) == next.songs.map(\.id)
        if !force, sameAlbumIDs, sameSongIDs {
            let albumsEqual = zip(library.albums, next.albums).allSatisfy { $0 == $1 }
            let songsEqual = zip(library.songs, next.songs).allSatisfy { $0 == $1 }
            if albumsEqual, songsEqual {
                // Equivalent catalog — bump revision only, keep the same album/song arrays.
                if next.revision != library.revision {
                    library = LibraryDto(
                        songs: library.songs,
                        albums: library.albums,
                        revision: next.revision
                    )
                }
                return
            }
        }

        library = Self.mergingLibrary(current: library, next: next)
    }

    /// Reuse equal album/song values by id so SwiftUI ForEach identity stays calm across polls.
    private static func mergingLibrary(current: LibraryDto, next: LibraryDto) -> LibraryDto {
        let oldAlbums = Dictionary(uniqueKeysWithValues: current.albums.map { ($0.id, $0) })
        let oldSongs = Dictionary(uniqueKeysWithValues: current.songs.map { ($0.id, $0) })
        let albums = next.albums.map { album -> AlbumDto in
            if let old = oldAlbums[album.id], old == album { return old }
            return album
        }
        let songs = next.songs.map { song -> SongDto in
            if let old = oldSongs[song.id], old == song { return old }
            return song
        }
        return LibraryDto(songs: songs, albums: albums, revision: next.revision)
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

    /// Phase E: toggle one Playing on target (host / this device / other registered player).
    func setOutputTarget(deviceId: String, enabled: Bool) async {
        guard client != nil else { return }
        var next = outputTargetIds
        if enabled {
            next.insert(deviceId)
        } else {
            next.remove(deviceId)
        }
        // Empty is allowed (silence everywhere / remote-only with no local renderer).
        await applyOutputTargets(next)
    }

    func applyOutputTargets(_ ids: Set<String>) async {
        guard client != nil else { return }
        let previousLocal = isLocalAudioOutput
        let wasPlaying = effectiveIsPlaying
        let position = effectivePositionMs
        let songId = playback.currentSongId

        // Optimistic UI first — hold off host poll overwrites until confirmed.
        outputTargetIds = ids
        pendingOutputTargetIds = ids
        pendingOutputUntil = Date().addingTimeInterval(3.0)
        let nowLocal = isLocalAudioOutput

        configureLocalPlayerIfNeeded()
        async let registered: Void = registerThisPlayer()
        async let pushed: Void = pushOutputTargetsToHost()

        if nowLocal, !previousLocal {
            lastAppliedSeekGeneration = playback.seekGeneration ?? lastAppliedSeekGeneration
            if let songId {
                await startLocalStream(songId: songId, atMs: position, autoplay: wasPlaying)
            }
        } else if !nowLocal, previousLocal {
            localPlayer.stop()
        }

        await registered
        await pushed
        if nowLocal {
            await reportPlaybackHeartbeat()
        }
        await refreshPlayers()
        // Refresh song/transport only; syncOutputTargets respects pending until host matches.
        await refreshPlayback()
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
        if isLocalAudioOutput {
            // Optimistic stream start — host mutate catches up; same songId avoids restart.
            ignoreHostTransportUntil = Date().addingTimeInterval(1.0)
            await startLocalStream(songId: songId, atMs: 0, autoplay: true)
        }
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
        if isLocalAudioOutput {
            localPlayer.playPause()
            ignoreHostTransportUntil = Date().addingTimeInterval(0.8)
            // Toggle shared session desired playing (host keeps irrKlang silent).
            try? await client?.playPause()
            await reportPlaybackHeartbeat()
            return
        }
        await mutate { try await $0.playPause() }
    }

    func pause() async {
        if isLocalAudioOutput {
            localPlayer.pause()
            ignoreHostTransportUntil = Date().addingTimeInterval(0.8)
            try? await client?.pause()
            await reportPlaybackHeartbeat()
            return
        }
        await mutate { try await $0.pause() }
    }

    func next() async {
        if isLocalAudioOutput,
           let peek = predictedNextSong(after: playback.currentSong) {
            ignoreHostTransportUntil = Date().addingTimeInterval(1.0)
            await startLocalStream(songId: peek.id, atMs: 0, autoplay: true)
        }
        await mutate { try await $0.next() }
    }

    func previous() async {
        await mutate { try await $0.previous() }
    }

    func toggleShuffle() async {
        await mutate { try await $0.shuffle(enabled: nil) }
    }

    func seek(positionMs: Int64) async {
        if isLocalAudioOutput {
            await localPlayer.seek(positionMs: positionMs)
            ignoreHostTransportUntil = Date().addingTimeInterval(0.8)
            try? await client?.seek(positionMs: positionMs)
            await reportPlaybackHeartbeat()
            return
        }
        await mutate { try await $0.seek(positionMs: positionMs) }
    }

    func setVolume(_ level: Double) async {
        let clamped = min(max(level, 0), 1)
        if isLocalAudioOutput {
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
                await registerThisPlayer()
                lastAppliedSeekGeneration = playback.seekGeneration ?? -1
                syncOutputTargets(from: playback)
                if isLocalAudioOutput, let songId = playback.currentSongId {
                    await startLocalStream(
                        songId: songId,
                        atMs: playback.positionMs,
                        autoplay: playback.isPlaying
                    )
                }
                await refreshPlayers()
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
        playerHeartbeatTask?.cancel()

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

        playerHeartbeatTask = Task { [weak self] in
            var ticks = 0
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                ticks += 1
                await self?.registerThisPlayer(force: false)
                await self?.reportPlaybackHeartbeat()
                if ticks % 5 == 0 {
                    await self?.refreshPlayers()
                }
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
                guard let self, self.isLocalAudioOutput else { return }
                await self.next()
            }
        }
    }

    private func pushOutputTargetsToHost() async {
        guard let client else { return }
        let targets = outputTargetIds.map { id -> PlaybackOutputTargetDto in
            if id == LydOutputIds.host {
                return PlaybackOutputTargetDto(deviceId: LydOutputIds.host, deviceName: selectedDisplayName)
            }
            if id == DeviceIdentity.deviceId {
                return PlaybackOutputTargetDto(deviceId: id, deviceName: DeviceIdentity.displayName)
            }
            let name = registeredPlayers.first(where: { $0.deviceId == id })?.displayName
            return PlaybackOutputTargetDto(deviceId: id, deviceName: name ?? id)
        }
        do {
            try await client.setPlaybackOutputs(targets)
        } catch {
            // Older hosts: fall back to legacy single-target API.
            if isLocalAudioOutput && !isHostAudioOutput {
                try? await client.setPlaybackOutput(
                    target: "remote",
                    deviceId: DeviceIdentity.deviceId,
                    deviceName: DeviceIdentity.displayName
                )
            } else if isHostAudioOutput && outputTargetIds.count == 1 {
                try? await client.setPlaybackOutput(target: "host", deviceId: nil, deviceName: nil)
            }
        }
    }

    private func refreshPlayers() async {
        guard let client else { return }
        do {
            let players = try await client.listPlayers()
            registeredPlayers = players
                .filter { $0.deviceId != DeviceIdentity.deviceId }
                .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        } catch {
            // Older hosts without /players — keep empty list.
        }
    }

    private func syncOutputTargets(from remote: PlaybackStateDto) {
        let remoteIds = resolvedOutputTargetIds(from: remote)

        if let pending = pendingOutputTargetIds {
            if let remoteIds, remoteIds == pending {
                pendingOutputTargetIds = nil
                pendingOutputUntil = nil
                outputTargetIds = remoteIds
                return
            }
            // Stale poll / in-flight POST — keep optimistic selection.
            if let until = pendingOutputUntil, Date() < until {
                return
            }
            // Grace expired: accept host if we can resolve it; otherwise keep local.
            pendingOutputTargetIds = nil
            pendingOutputUntil = nil
            if let remoteIds {
                outputTargetIds = remoteIds
            }
            return
        }

        guard let remoteIds else {
            // Missing output fields — don't invent [host] and wipe a valid local selection.
            return
        }
        outputTargetIds = remoteIds
    }

    /// `nil` = host omitted output info (don't clobber). Empty set = intentionally no outputs.
    private func resolvedOutputTargetIds(from remote: PlaybackStateDto) -> Set<String>? {
        if let targets = remote.outputTargets {
            return Set(targets.map(\.deviceId))
        }
        // Legacy single-target fields only when OutputTargets is absent.
        switch remote.outputTarget {
        case "remote":
            if let id = remote.outputDeviceId, !id.isEmpty {
                return [id]
            }
            return nil
        case "multi":
            var ids: Set<String> = [LydOutputIds.host]
            if let id = remote.outputDeviceId, !id.isEmpty {
                ids.insert(id)
            }
            return ids
        case "host":
            return [LydOutputIds.host]
        default:
            return nil
        }
    }

    private func startLocalStream(songId: String, atMs: Int64, autoplay: Bool) async {
        guard let client, let url = client.streamURL(songId: songId) else {
            statusMessage = "Stream URL unavailable"
            return
        }
        configureLocalPlayerIfNeeded()
        // Same URL already rendering — just seek / resume instead of replacing the item.
        if localPlayer.currentSongId == songId {
            if atMs > 0 {
                await localPlayer.seek(positionMs: atMs)
            }
            if autoplay {
                localPlayer.resume()
            } else {
                localPlayer.pause()
            }
            return
        }
        localPlayer.play(url: url, songId: songId, startAtMs: max(0, atMs), autoplay: autoplay)
        // Do NOT POST pause here — that clears shared session desired-playing.
    }

    private func registerThisPlayer(force: Bool = true) async {
        guard let client, phase == .connected || phase == .connecting else { return }
        if !force, let last = lastPlayerRegisterAt, Date().timeIntervalSince(last) < 15 {
            return
        }
        try? await client.registerPlayer(
            deviceId: DeviceIdentity.deviceId,
            name: DeviceIdentity.displayName,
            platform: DeviceIdentity.platform
        )
        lastPlayerRegisterAt = Date()
    }

    private func reportPlaybackHeartbeat() async {
        guard isLocalAudioOutput, let client else { return }
        try? await client.playbackHeartbeat(
            deviceId: DeviceIdentity.deviceId,
            positionMs: localPlayer.positionMs,
            durationMs: localPlayer.durationMs > 0 ? localPlayer.durationMs : nil,
            songId: localPlayer.currentSongId ?? playback.currentSongId
        )
    }

    private func applyHostPlaybackState(_ remote: PlaybackStateDto) async {
        let previouslyLocal = isLocalAudioOutput
        syncOutputTargets(from: remote)
        let nowLocal = isLocalAudioOutput

        if nowLocal {
            var merged = remote
            merged.positionMs = localPlayer.positionMs
            if localPlayer.durationMs > 0 {
                merged.durationMs = localPlayer.durationMs
            }
            merged.volume = Double(localPlayer.volume)
            let suppressTransport = ignoreHostTransportUntil.map { Date() < $0 } ?? false
            if !suppressTransport {
                merged.isPlaying = remote.isPlaying
            } else {
                merged.isPlaying = localPlayer.isPlaying
            }
            playback = merged

            if !previouslyLocal, let songId = remote.currentSongId {
                lastAppliedSeekGeneration = remote.seekGeneration ?? -1
                await startLocalStream(
                    songId: songId,
                    atMs: remote.positionMs,
                    autoplay: remote.isPlaying
                )
                return
            }

            let songId = remote.currentSongId
            if let songId, songId != localPlayer.currentSongId {
                lastAppliedSeekGeneration = remote.seekGeneration ?? lastAppliedSeekGeneration
                await startLocalStream(
                    songId: songId,
                    atMs: remote.positionMs,
                    autoplay: remote.isPlaying
                )
                return
            }

            if songId == nil, localPlayer.currentSongId != nil {
                localPlayer.stop()
                return
            }

            let generation = remote.seekGeneration ?? 0
            if generation != lastAppliedSeekGeneration {
                lastAppliedSeekGeneration = generation
                if abs(remote.positionMs - localPlayer.positionMs) > 1500 {
                    await localPlayer.seek(positionMs: remote.positionMs)
                }
            }

            if !suppressTransport {
                if remote.isPlaying, !localPlayer.isPlaying {
                    localPlayer.resume()
                } else if !remote.isPlaying, localPlayer.isPlaying {
                    localPlayer.pause()
                }
            }
        } else {
            if previouslyLocal {
                localPlayer.stop()
            }
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
