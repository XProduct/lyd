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
    /// Sticky: once we have seen albums this connection, never flash the hydrating empty overlay.
    @Published private(set) var hasLoadedAlbumCatalog = false
    /// Sticky: once we have seen songs this connection, never flash the songs hydrating empty overlay.
    @Published private(set) var hasLoadedSongCatalog = false
    /// Phase E: multi-select Playing on device ids (`LydOutputIds.host` and/or player ids).
    @Published private(set) var outputTargetIds: Set<String> = [LydOutputIds.host]
    /// Host `allowMultiOutput` (Windows #32). Default false = single Playing on (desktop default).
    @Published private(set) var allowMultiOutput = false
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
    /// Phase F: at most one corrective hard seek per song (join catch-up counts).
    private var didCorrectiveTimelineSeekThisItem = false
    /// Live host playhead sampled at poll receive — clock-safe fallback when sticky+offset unavailable.
    private var timelineSamplePositionMs: Int64 = 0
    private var timelineSampleAt: Date?
    private var timelineSamplePlaying = false
    /// Host−client wall offset: `serverUnixMs − clientReceiveUnixMs` (positive ⇒ client clock behind).
    /// Matches Windows #27 / f1-clock-skew-contract: correctedNow = clientNow + offsetMs.
    private var serverMinusClientMs: Int64 = 0
    private var hasHostClockOffset = false
    /// Last sticky pin from the host (transport / one-shot glue — not rewritten every poll).
    private var stickyAnchorUnixMs: Int64?
    private var stickyPositionAtAnchorMs: Int64?
    /// Phase F: join catch-up once, then rate=1.0 and no mid-track sync seeks/rate (skips).
    private enum TimelineSync {
        /// Join/ready: one catch-up seek if |skew| at least this; then leave AVPlayer alone.
        static let joinSeekSkewMs: Int64 = 750
        /// EMA for serverMinusClientMs (poll RTT noise → stable desired at join).
        static let clockOffsetEmaAlpha: Double = 0.25
    }

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
    /// Once either catalog has loaded this session, stop treating empty polls as “still loading”.
    var isLibraryStillLoading: Bool {
        phase == .connected
            && isHostReachable
            && !hasLoadedAlbumCatalog
            && !hasLoadedSongCatalog
            && library.songs.isEmpty
            && library.albums.isEmpty
    }

    /// Albums tab empty overlay — never cover a previously loaded grid during poll churn.
    var shouldShowAlbumsEmptyState: Bool {
        library.albums.isEmpty && !hasLoadedAlbumCatalog
    }

    /// Songs tab empty overlay — same latch as albums.
    var shouldShowSongsEmptyState: Bool {
        library.songs.isEmpty && !hasLoadedSongCatalog
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
        allowMultiOutput = false
        pendingOutputTargetIds = nil
        pendingOutputUntil = nil
        didCorrectiveTimelineSeekThisItem = false
        timelineSampleAt = nil
        timelineSamplePositionMs = 0
        timelineSamplePlaying = false
        serverMinusClientMs = 0
        hasHostClockOffset = false
        stickyAnchorUnixMs = nil
        stickyPositionAtAnchorMs = nil
        registeredPlayers = []
        lastAppliedSeekGeneration = -1
        client = nil
        isHostReachable = false
        offlineMessage = nil
        library = LibraryDto(songs: [], albums: [], revision: -1)
        hasLoadedAlbumCatalog = false
        hasLoadedSongCatalog = false
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
    /// Shared by iOS and tvOS — no platform split.
    private func applyLibraryUpdate(_ next: LibraryDto, force: Bool) {
        if !force,
           library.revision >= 0,
           next.revision == library.revision {
            noteLibraryContentLoaded(library)
            return
        }

        // Host scan/hydration can briefly return an empty catalog with a bumped revision.
        // Never wipe a populated grid unless this is an explicit force refresh.
        if !force {
            let nextFullyEmpty = next.albums.isEmpty && next.songs.isEmpty
            let currentPopulated = !library.albums.isEmpty || !library.songs.isEmpty
            if nextFullyEmpty, currentPopulated {
                if next.revision != library.revision {
                    library = LibraryDto(
                        songs: library.songs,
                        albums: library.albums,
                        revision: next.revision
                    )
                }
                noteLibraryContentLoaded(library)
                return
            }
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
                noteLibraryContentLoaded(library)
                return
            }
        }

        let merged = Self.mergingLibrary(current: library, next: next, force: force)
        library = merged
        noteLibraryContentLoaded(merged)
    }

    private func noteLibraryContentLoaded(_ dto: LibraryDto) {
        if !dto.albums.isEmpty { hasLoadedAlbumCatalog = true }
        if !dto.songs.isEmpty { hasLoadedSongCatalog = true }
    }

    /// Reuse equal album/song values by id so SwiftUI ForEach identity stays calm across polls.
    /// When `force` is false, keep prior albums/songs if the incoming side is empty.
    private static func mergingLibrary(current: LibraryDto, next: LibraryDto, force: Bool) -> LibraryDto {
        let oldAlbums = Dictionary(uniqueKeysWithValues: current.albums.map { ($0.id, $0) })
        let oldSongs = Dictionary(uniqueKeysWithValues: current.songs.map { ($0.id, $0) })

        let incomingAlbums: [AlbumDto]
        if !force, next.albums.isEmpty, !current.albums.isEmpty {
            incomingAlbums = current.albums
        } else {
            incomingAlbums = next.albums.map { album -> AlbumDto in
                if let old = oldAlbums[album.id], old == album { return old }
                return album
            }
        }

        let incomingSongs: [SongDto]
        if !force, next.songs.isEmpty, !current.songs.isEmpty {
            incomingSongs = current.songs
        } else {
            incomingSongs = next.songs.map { song -> SongDto in
                if let old = oldSongs[song.id], old == song { return old }
                return song
            }
        }

        return LibraryDto(songs: incomingSongs, albums: incomingAlbums, revision: next.revision)
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
    /// When `allowMultiOutput` is false, tapping a row **replaces** the selection (single-select).
    func setOutputTarget(deviceId: String, enabled: Bool) async {
        guard client != nil else { return }
        if !allowMultiOutput {
            await applyOutputTargets([deviceId])
            return
        }
        var next = outputTargetIds
        if enabled {
            next.insert(deviceId)
        } else {
            next.remove(deviceId)
        }
        // Never allow an empty set — that silences every renderer and looks like “play does nothing”.
        if next.isEmpty {
            next.insert(LydOutputIds.host)
        }
        await applyOutputTargets(next)
    }

    func applyOutputTargets(_ ids: Set<String>) async {
        guard client != nil else { return }
        var normalized = Self.nonEmptyOutputTargets(ids)
        if !allowMultiOutput, normalized.count > 1 {
            normalized = Self.collapseToSingleOutput(normalized)
        }
        let previousLocal = isLocalAudioOutput
        let wasPlaying = effectiveIsPlaying
        let position = effectivePositionMs
        let songId = playback.currentSongId

        // Optimistic UI; host response is authoritative (may collapse when multi is off).
        outputTargetIds = normalized
        pendingOutputTargetIds = normalized
        pendingOutputUntil = Date().addingTimeInterval(3.0)

        // Stop immediately when leaving the output set — don't wait for the next poll.
        if previousLocal, !normalized.contains(DeviceIdentity.deviceId) {
            localPlayer.stop()
        }

        configureLocalPlayerIfNeeded()
        await registerThisPlayer()
        let hostState = await pushOutputTargetsToHost()
        if let hostState {
            // Clear pending so sync trusts the POST response (contract: host is source of truth).
            pendingOutputTargetIds = nil
            pendingOutputUntil = nil
            await applyHostPlaybackState(hostState)
        } else {
            await refreshPlayback()
        }

        let nowLocal = isLocalAudioOutput
        if nowLocal, !previousLocal {
            lastAppliedSeekGeneration = playback.seekGeneration ?? lastAppliedSeekGeneration
            if let songId {
                await startLocalStream(songId: songId, atMs: position, autoplay: wasPlaying)
            }
        } else if !nowLocal, previousLocal, localPlayer.currentSongId != nil {
            localPlayer.stop()
        }

        if nowLocal {
            await reportPlaybackHeartbeat()
        }
        await refreshPlayers()
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
        await ensurePlaybackOutputsReady()
        if isLocalAudioOutput {
            // Optimistic stream start — host mutate catches up; same songId avoids restart.
            ignoreHostTransportUntil = Date().addingTimeInterval(1.0)
            await startLocalStream(songId: songId, atMs: 0, autoplay: true)
        }
        await mutate { try await $0.play(songId: songId) }
        // If host ack left us local but AVPlayer never started (race / failed first start), retry.
        if isLocalAudioOutput, localPlayer.currentSongId != songId || (!localPlayer.isPlaying && playback.isPlaying) {
            await startLocalStream(songId: songId, atMs: 0, autoplay: true)
        } else if isLocalAudioOutput, !localPlayer.isPlaying, localPlayer.currentSongId == songId {
            localPlayer.resume()
        }
    }

    /// Shuffle off + play album in disc/track order (Windows `play-album`).
    func playAlbum(albumId: String) async {
        selectedTab = .nowPlaying
        await ensurePlaybackOutputsReady()
        await mutate { client in
            try? await client.shuffle(enabled: false)
            try await client.playAlbum(albumId: albumId)
        }
        if isLocalAudioOutput, let songId = playback.currentSongId {
            ignoreHostTransportUntil = Date().addingTimeInterval(1.0)
            await startLocalStream(songId: songId, atMs: 0, autoplay: true)
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
                noteLibraryContentLoaded(lib)
                playback = try await api.playbackState()
                noteHostTimelineSample(playback)
                configureLocalPlayerIfNeeded()
                await registerThisPlayer()
                lastAppliedSeekGeneration = playback.seekGeneration ?? -1
                syncOutputTargets(from: playback)
                // Heal empty Playing on from host and push a real renderer before first play.
                await ensurePlaybackOutputsReady()
                if isLocalAudioOutput, let songId = playback.currentSongId {
                    // Late join / restart: start on the clock-corrected host timeline.
                    await startLocalStream(
                        songId: songId,
                        atMs: hostTimelineDesiredMs(),
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
        // After buffer/start, host may have advanced — one join catch-up, then calm follow.
        localPlayer.onBecameReady = { [weak self] in
            Task { @MainActor in
                guard let self, self.isLocalAudioOutput, self.playback.isPlaying else { return }
                await self.followHostTimeline(self.playback, allowJoinSeek: true)
            }
        }
    }

    /// Guarantees at least one renderer before play/seek transport hits the host.
    private func ensurePlaybackOutputsReady() async {
        let normalized = Self.nonEmptyOutputTargets(outputTargetIds)
        if normalized != outputTargetIds {
            outputTargetIds = normalized
        }
        pendingOutputTargetIds = normalized
        pendingOutputUntil = Date().addingTimeInterval(3.0)
        await pushOutputTargetsToHost()
    }

    private static func nonEmptyOutputTargets(_ ids: Set<String>) -> Set<String> {
        ids.isEmpty ? [LydOutputIds.host] : ids
    }

    @discardableResult
    private func pushOutputTargetsToHost() async -> PlaybackStateDto? {
        guard let client else { return nil }
        let ids = Self.nonEmptyOutputTargets(outputTargetIds)
        if ids != outputTargetIds {
            outputTargetIds = ids
        }
        let targets = ids.map { id -> PlaybackOutputTargetDto in
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
            return try await client.setPlaybackOutputs(targets)
        } catch {
            // Legacy single-target recovery must match the user's selection.
            // Never POST host-only when This device (or any non-host target) is selected —
            // that was wiping multi / This-device picks and stopping AVPlayer.
            if ids == [LydOutputIds.host] {
                return try? await client.setPlaybackOutput(target: "host", deviceId: nil, deviceName: nil)
            } else if ids.contains(DeviceIdentity.deviceId) {
                return try? await client.setPlaybackOutput(
                    target: "remote",
                    deviceId: DeviceIdentity.deviceId,
                    deviceName: DeviceIdentity.displayName
                )
            }
            // Other remotes-only / unknown: leave host state alone rather than force host.
            return nil
        }
    }

    private func refreshPlayers() async {
        guard let client else { return }
        do {
            let response: PlayersResponse = try await client.getPlayers()
            if let flag = response.allowMultiOutput {
                allowMultiOutput = flag
            }
            registeredPlayers = (response.players ?? [])
                .filter { $0.deviceId != DeviceIdentity.deviceId }
                .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        } catch {
            // Older hosts without /players — keep empty list.
        }
    }

    private func syncOutputTargets(from remote: PlaybackStateDto) {
        // Missing field → false (matches desktop default off / f1-allow-multi-output-contract).
        allowMultiOutput = remote.allowMultiOutput ?? false
        let remoteIds = resolvedOutputTargetIds(from: remote)

        // Single-output mode: host collapse is authoritative — never sticky-repush This device.
        if !allowMultiOutput {
            if let remoteIds {
                var next = Self.nonEmptyOutputTargets(remoteIds)
                if next.count > 1 {
                    next = Self.collapseToSingleOutput(next)
                }
                if let pending = pendingOutputTargetIds {
                    let pendingSingle = {
                        let p = Self.nonEmptyOutputTargets(pending)
                        return p.count > 1 ? Self.collapseToSingleOutput(p) : p
                    }()
                    if next == pendingSingle {
                        pendingOutputTargetIds = nil
                        pendingOutputUntil = nil
                        outputTargetIds = next
                        return
                    }
                    if let until = pendingOutputUntil, Date() < until {
                        outputTargetIds = pendingSingle
                        return
                    }
                    pendingOutputTargetIds = nil
                    pendingOutputUntil = nil
                }
                outputTargetIds = next
            } else if outputTargetIds.isEmpty {
                outputTargetIds = [LydOutputIds.host]
            }
            return
        }

        if let pending = pendingOutputTargetIds {
            let pendingNormalized = Self.nonEmptyOutputTargets(pending)
            if let remoteIds, remoteIds == pendingNormalized {
                pendingOutputTargetIds = nil
                pendingOutputUntil = nil
                outputTargetIds = remoteIds
                return
            }
            // Stale poll / in-flight POST — keep optimistic selection.
            if let until = pendingOutputUntil, Date() < until {
                outputTargetIds = pendingNormalized
                return
            }
            // Grace expired but host still disagrees. Never let a lagging host-only
            // (or missing) poll clobber a user pick that includes This device / remotes —
            // that stopped AVPlayer after a brief play. Stay sticky and re-push.
            let remoteIsHostOnly = remoteIds == nil || remoteIds == [LydOutputIds.host]
            let pendingWantsMoreThanHost = pendingNormalized != [LydOutputIds.host]
            if pendingWantsMoreThanHost, remoteIsHostOnly || !(remoteIds?.isSuperset(of: pendingNormalized) ?? false) {
                outputTargetIds = pendingNormalized
                pendingOutputUntil = Date().addingTimeInterval(3.0)
                Task { await self.pushOutputTargetsToHost() }
                return
            }
            // Grace expired: accept host if we can resolve it; otherwise keep local non-empty.
            pendingOutputTargetIds = nil
            pendingOutputUntil = nil
            if let remoteIds {
                outputTargetIds = Self.nonEmptyOutputTargets(remoteIds)
            } else if outputTargetIds.isEmpty {
                outputTargetIds = [LydOutputIds.host]
            }
            return
        }

        guard let remoteIds else {
            // Missing output fields — heal empty local selection only.
            if outputTargetIds.isEmpty {
                outputTargetIds = [LydOutputIds.host]
            }
            return
        }
        // Don't let steady-state polls drop This device to host-only while AVPlayer
        // is actively rendering that selection (host lag / partial apply).
        if outputTargetIds.contains(DeviceIdentity.deviceId),
           !remoteIds.contains(DeviceIdentity.deviceId),
           remoteIds == [LydOutputIds.host],
           localPlayer.currentSongId != nil {
            pendingOutputTargetIds = outputTargetIds
            pendingOutputUntil = Date().addingTimeInterval(3.0)
            Task { await self.pushOutputTargetsToHost() }
            return
        }
        outputTargetIds = Self.nonEmptyOutputTargets(remoteIds)
    }

    /// Single-output mode: prefer host if selected, else keep one stable id.
    private static func collapseToSingleOutput(_ ids: Set<String>) -> Set<String> {
        if ids.contains(LydOutputIds.host) {
            return [LydOutputIds.host]
        }
        if ids.contains(DeviceIdentity.deviceId) {
            return [DeviceIdentity.deviceId]
        }
        if let first = ids.sorted().first {
            return [first]
        }
        return [LydOutputIds.host]
    }

    /// `nil` = host omitted output info (don't clobber). Empty list is treated as host.
    private func resolvedOutputTargetIds(from remote: PlaybackStateDto) -> Set<String>? {
        if let targets = remote.outputTargets {
            let ids = Set(targets.map(\.deviceId))
            // Empty OutputTargets from host previously silenced every renderer.
            return ids.isEmpty ? [LydOutputIds.host] : ids
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
        // Wait until the join seek has landed. Pre-ready heartbeats repeated the same
        // pendingStart and restarted the host Stopwatch every second (bar flicker).
        // Host keeps time from the handoff Stopwatch until we are ready.
        guard localPlayer.isReadyForHeartbeat else { return }
        try? await client.playbackHeartbeat(
            deviceId: DeviceIdentity.deviceId,
            positionMs: localPlayer.heartbeatPositionMs,
            durationMs: localPlayer.durationMs > 0 ? localPlayer.durationMs : nil,
            songId: localPlayer.currentSongId ?? playback.currentSongId,
            isPlaying: localPlayer.isPlaying
        )
    }

    private func applyHostPlaybackState(_ remote: PlaybackStateDto) async {
        let previouslyLocal = isLocalAudioOutput
        syncOutputTargets(from: remote)
        let nowLocal = isLocalAudioOutput
        // Always refresh the local timeline sample — even when not rendering — so a later
        // join uses a clock-skew-safe base instead of raw AnchorUnixMs vs iOS wall clock.
        noteHostTimelineSample(remote)

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

            // Late join / output enable: catch up alone to host timeline (don’t resync peers).
            if !previouslyLocal, let songId = remote.currentSongId {
                lastAppliedSeekGeneration = remote.seekGeneration ?? -1
                didCorrectiveTimelineSeekThisItem = false
                let target = hostTimelineDesiredMs()
                await startLocalStream(
                    songId: songId,
                    atMs: target,
                    autoplay: remote.isPlaying
                )
                return
            }

            let songId = remote.currentSongId
            if let songId, songId != localPlayer.currentSongId {
                lastAppliedSeekGeneration = remote.seekGeneration ?? lastAppliedSeekGeneration
                didCorrectiveTimelineSeekThisItem = false
                let target = hostTimelineDesiredMs()
                await startLocalStream(
                    songId: songId,
                    atMs: target,
                    autoplay: remote.isPlaying
                )
                return
            }

            if songId == nil, localPlayer.currentSongId != nil {
                localPlayer.stop()
                return
            }

            // Host-initiated seek / transport bump — not drift chatter; apply once per generation.
            let generation = remote.seekGeneration ?? 0
            if generation != lastAppliedSeekGeneration {
                lastAppliedSeekGeneration = generation
                let target = hostTimelineDesiredMs()
                // Generous seek tolerance — precise mid-stream seeks rebuffer and click.
                if abs(target - localPlayer.positionMs) > 400 {
                    await localPlayer.seek(positionMs: target, precise: false)
                    localPlayer.setPlaybackRate(1.0)
                }
            }

            if !suppressTransport {
                if remote.isPlaying, !localPlayer.isPlaying {
                    localPlayer.resume()
                } else if !remote.isPlaying, localPlayer.isPlaying {
                    localPlayer.pause()
                }
            }

            // After join: keep rate at 1.0 only — no mid-track rate/seek follow (audible skips).
            if !suppressTransport, remote.isPlaying, localPlayer.currentSongId != nil {
                await followHostTimeline(remote, allowJoinSeek: false)
            }
        } else {
            if previouslyLocal {
                localPlayer.stop()
            }
            playback = remote
        }
    }

    /// Capture sticky anchors + clock offset (or live-position fallback) at poll receive.
    private func noteHostTimelineSample(_ remote: PlaybackStateDto) {
        let receiveMs = Int64(Date().timeIntervalSince1970 * 1000)

        var rawOffset: Int64?
        if let server = remote.serverUnixMs, server > 0 {
            // Windows #27: offsetMs ≈ serverUnixMs − clientLocalUnixMsAtReceive
            rawOffset = server - receiveMs
        } else if let anchor = remote.anchorUnixMs,
                  let atAnchor = remote.positionAtAnchorMs,
                  remote.isPlaying {
            // Pre-#27 hosts: infer host−client from sticky derive vs live playhead.
            let derivedOnClientClock = atAnchor + (receiveMs - anchor)
            rawOffset = remote.positionMs - derivedOnClientClock
        }
        if let rawOffset {
            applyClockOffsetSample(rawOffset)
        }

        stickyAnchorUnixMs = remote.anchorUnixMs
        stickyPositionAtAnchorMs = remote.positionAtAnchorMs

        // Live playhead sample — fallback when sticky+offset path is unavailable.
        timelineSamplePositionMs = remote.liveHostPositionMs
        timelineSampleAt = Date()
        timelineSamplePlaying = remote.isPlaying
    }

    /// EMA-smooth clock offset so poll RTT noise does not flutter rate/desired.
    private func applyClockOffsetSample(_ rawOffsetMs: Int64) {
        if !hasHostClockOffset {
            serverMinusClientMs = rawOffsetMs
            hasHostClockOffset = true
            return
        }
        let alpha = TimelineSync.clockOffsetEmaAlpha
        let blended = Double(serverMinusClientMs) * (1 - alpha) + Double(rawOffsetMs) * alpha
        serverMinusClientMs = Int64(blended.rounded())
    }

    /// Desired playhead on the host timeline, corrected for wall-clock skew.
    private func hostTimelineDesiredMs(at date: Date = Date()) -> Int64 {
        if let anchor = stickyAnchorUnixMs ?? playback.anchorUnixMs,
           let atAnchor = stickyPositionAtAnchorMs ?? playback.positionAtAnchorMs {
            let playing = timelineSamplePlaying || playback.isPlaying
            if !playing {
                return max(0, atAnchor)
            }
            if hasHostClockOffset {
                // Contract: correctedNow = clientNow + (serverUnixMs − clientReceive)
                // desired = positionAtAnchorMs + (correctedNow − anchorUnixMs)
                let nowMs = Int64(date.timeIntervalSince1970 * 1000)
                let correctedNowMs = nowMs + serverMinusClientMs
                return max(0, atAnchor + (correctedNowMs - anchor))
            }
            // Sticky without an offset estimate: never raw client wall vs AnchorUnixMs
            // (~3s ahead / ~6s behind). Fall through to live positionMs sample.
        }

        guard let sampleAt = timelineSampleAt else {
            return max(0, playback.positionMs)
        }
        if !timelineSamplePlaying {
            return timelineSamplePositionMs
        }
        let elapsedMs = Int64(date.timeIntervalSince(sampleAt) * 1000)
        return max(0, timelineSamplePositionMs + max(0, elapsedMs))
    }

    /// Align AVPlayer to host timeline. Corrections apply to **this device only**.
    /// - Parameter allowJoinSeek: true only from ready — one catch-up if badly off, then never again.
    private func followHostTimeline(_ remote: PlaybackStateDto, allowJoinSeek: Bool = false) async {
        let playing = remote.isPlaying || timelineSamplePlaying
        guard playing else {
            ensureUnityRate()
            return
        }

        // Join/ready only: one seek if badly off. No mid-track drift seeks (they rebuffer/skip).
        if allowJoinSeek, !didCorrectiveTimelineSeekThisItem {
            let desired = hostTimelineDesiredMs()
            let skew = desired - localPlayer.positionMs
            if abs(skew) >= TimelineSync.joinSeekSkewMs {
                didCorrectiveTimelineSeekThisItem = true
                // Non-precise: avoid tight reseek clicks on LAN streams.
                await localPlayer.seek(positionMs: desired, precise: false)
                localPlayer.resume()
            } else {
                // Close enough at join — consume the once-per-track seek budget anyway
                // so polls never hard-seek for ordinary drift.
                didCorrectiveTimelineSeekThisItem = true
            }
        }

        ensureUnityRate()
    }

    /// Keep AVPlayer at 1.0× after lock — rate tweaks (even ±3%) click/skip on stream items.
    private func ensureUnityRate() {
        if abs(localPlayer.playbackRate - 1.0) > 0.001 {
            localPlayer.setPlaybackRate(1.0)
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
