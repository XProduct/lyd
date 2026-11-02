import Foundation
import Combine

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

    let browser = BonjourBrowser()

    private var client: LydAPIClient?
    private var libraryPollTask: Task<Void, Never>?
    private var playbackPollTask: Task<Void, Never>?

    var songsByID: [String: SongDto] {
        Dictionary(uniqueKeysWithValues: library.songs.map { ($0.id, $0) })
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
        connect(host: host.host, port: host.port, displayName: host.displayTitle)
    }

    func connect(manual: ManualHost, displayName: String? = nil) {
        connect(host: manual.host, port: manual.port, displayName: displayName ?? manual.endpointLabel)
    }

    func reconnectLastIfPossible() {
        guard let last = HostPreferences.lastSelection else { return }
        connect(host: last.host, port: last.port, displayName: last.displayName ?? last.host)
    }

    func disconnect(returnToPicker: Bool = true) {
        libraryPollTask?.cancel()
        playbackPollTask?.cancel()
        libraryPollTask = nil
        playbackPollTask = nil
        client = nil
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

    func refreshLibrary(force: Bool = false) async {
        guard let client else { return }
        do {
            let next = try await client.library()
            if force || next.revision != library.revision {
                library = next
            }
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func refreshPlayback() async {
        guard let client else { return }
        do {
            playback = try await client.playbackState()
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func play(songId: String) async {
        selectedTab = .nowPlaying
        await mutate { try await $0.play(songId: songId) }
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

        Task {
            do {
                let health = try await api.health()
                HostPreferences.lastSelection = (normalizedHost, port, health.name.isEmpty ? displayName : health.name)
                selectedDisplayName = health.name.isEmpty ? displayName : health.name
                let lib = try await api.library()
                library = lib
                playback = try await api.playbackState()
                phase = .connected
                startPolling()
                // Connected — browsing optional; leave it running for Settings host list.
                startDiscovery()
            } catch {
                phase = .error(error.localizedDescription)
                client = nil
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
                await self?.refreshLibrary()
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
        } catch {
            statusMessage = error.localizedDescription
        }
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
