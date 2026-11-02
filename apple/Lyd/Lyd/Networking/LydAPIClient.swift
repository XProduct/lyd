import Foundation

enum LydAPIError: LocalizedError {
    case invalidURL
    case badStatus(Int, String?)
    case decoding(Error)
    case transport(Error)
    case notModified

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid server URL"
        case .badStatus(let code, let body):
            return "HTTP \(code)" + (body.map { ": \($0)" } ?? "")
        case .decoding(let error):
            return "Decode failed: \(error.localizedDescription)"
        case .transport(let error):
            return error.localizedDescription
        case .notModified:
            return "Not modified"
        }
    }
}

/// Outcome of a revision-efficient library poll.
enum LibrarySyncResult: Equatable {
    case unchanged(revision: Int)
    case updated(LibraryDto)
}

final class LydAPIClient: @unchecked Sendable {
    private let session: URLSession
    private let lock = NSLock()
    private var _baseURL: URL
    /// Cached: nil = unknown, true/false after first revision-endpoint probe.
    private var _thinRevisionSupported: Bool?

    var baseURL: URL {
        lock.lock(); defer { lock.unlock() }
        return _baseURL
    }

    init(baseURL: URL, session: URLSession = .shared) {
        self._baseURL = baseURL
        self.session = session
    }

    func updateBaseURL(_ url: URL) {
        lock.lock(); _baseURL = url; lock.unlock()
    }

    func health() async throws -> HealthDto {
        try await get("api/v1/health")
    }

    func library() async throws -> LibraryDto {
        try await get("api/v1/library")
    }

    /// Cheap revision check via `GET /api/v1/library/revision`. Throws `badStatus(404)` when unsupported.
    func libraryRevisionThin() async throws -> Int {
        let dto: LibraryRevisionDto = try await get("api/v1/library/revision")
        lock.lock(); _thinRevisionSupported = true; lock.unlock()
        return dto.revision
    }

    /// Poll: return `.unchanged` when remote revision matches `knownRevision`; otherwise full library.
    /// Prefers thin `/library/revision` or conditional `?revision=` / `If-None-Match`. Until Windows
    /// ships those, falls back to one full `/library` fetch and compares the `revision` field locally.
    func syncLibrary(knownRevision: Int, force: Bool) async throws -> LibrarySyncResult {
        if force {
            return .updated(try await library())
        }

        if knownRevision >= 0 {
            // Planned conditional fetch — ignore unsupported responses.
            do {
                if let conditional = try await libraryIfUnchanged(knownRevision: knownRevision) {
                    return conditional
                }
            } catch {
                // Host may not support ?revision= / If-None-Match yet.
            }

            let thinKnown: Bool?
            lock.lock(); thinKnown = _thinRevisionSupported; lock.unlock()
            if thinKnown != false {
                do {
                    let remoteRevision = try await libraryRevisionThin()
                    if remoteRevision == knownRevision {
                        return .unchanged(revision: remoteRevision)
                    }
                    return .updated(try await library())
                } catch let LydAPIError.badStatus(code, _) where code == 404 {
                    lock.lock(); _thinRevisionSupported = false; lock.unlock()
                }
            }
        }

        // Stub against today's contract: full /library, replace only when revision changes.
        let lib = try await library()
        if knownRevision >= 0, lib.revision == knownRevision {
            return .unchanged(revision: lib.revision)
        }
        return .updated(lib)
    }

    func playbackState() async throws -> PlaybackStateDto {
        try await get("api/v1/playback/state")
    }

    func play(songId: String) async throws {
        try await post("api/v1/playback/play", body: PlayRequest(songId: songId))
    }

    func playAlbum(albumId: String) async throws {
        try await post("api/v1/playback/play-album", body: PlayAlbumRequest(albumId: albumId))
    }

    func pause() async throws {
        try await postEmpty("api/v1/playback/pause")
    }

    func playPause() async throws {
        try await postEmpty("api/v1/playback/playpause")
    }

    func next() async throws {
        try await postEmpty("api/v1/playback/next")
    }

    func previous() async throws {
        try await postEmpty("api/v1/playback/previous")
    }

    func shuffle(enabled: Bool? = nil) async throws {
        try await post("api/v1/playback/shuffle", body: ShuffleRequest(enabled: enabled))
    }

    func seek(positionMs: Int64) async throws {
        try await post("api/v1/playback/seek", body: SeekRequest(positionMs: positionMs))
    }

    func setVolume(level: Double) async throws {
        let clamped = min(max(level, 0), 1)
        try await post("api/v1/playback/volume", body: VolumeRequest(level: clamped))
    }

    /// Phase E: Playing on targets. Returns authoritative host state (may collapse when multi off).
    @discardableResult
    func setPlaybackOutputs(_ targets: [PlaybackOutputTargetDto]) async throws -> PlaybackStateDto {
        try await post(
            "api/v1/playback/output",
            body: PlaybackOutputRequest(target: nil, deviceId: nil, deviceName: nil, targets: targets),
            as: PlaybackStateDto.self
        )
    }

    /// Legacy single-target output (older hosts without Targets).
    @discardableResult
    func setPlaybackOutput(target: String, deviceId: String?, deviceName: String?) async throws -> PlaybackStateDto {
        try await post(
            "api/v1/playback/output",
            body: PlaybackOutputRequest(target: target, deviceId: deviceId, deviceName: deviceName, targets: nil),
            as: PlaybackStateDto.self
        )
    }

    func listPlayers() async throws -> [PlayerDto] {
        let response = try await getPlayers()
        return response.players ?? []
    }

    func getPlayers() async throws -> PlayersResponse {
        try await get("api/v1/players")
    }

    /// Phase E: report playhead while this device is the audio renderer.
    func playbackHeartbeat(deviceId: String, positionMs: Int64, durationMs: Int64?, songId: String?) async throws {
        try await post(
            "api/v1/playback/heartbeat",
            body: PlaybackHeartbeatRequest(
                deviceId: deviceId,
                positionMs: positionMs,
                durationMs: durationMs,
                songId: songId
            )
        )
    }

    func registerPlayer(deviceId: String, name: String, platform: String) async throws {
        try await post(
            "api/v1/players/register",
            body: PlayerRegisterRequest(
                deviceId: deviceId,
                name: name,
                platform: platform,
                capabilities: ["play"]
            )
        )
    }

    func unregisterPlayer(deviceId: String) async throws {
        let encoded = deviceId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? deviceId
        try await delete("api/v1/players/\(encoded)")
    }

    func coverURL(for relativeOrAbsolute: String?) -> URL? {
        guard let value = relativeOrAbsolute, !value.isEmpty else { return nil }
        if let absolute = URL(string: value), absolute.scheme != nil {
            return absolute
        }
        return URL(string: value, relativeTo: baseURL)?.absoluteURL
    }

    /// Phase E: original-file stream URL for AVPlayer (`Range`-capable on the host).
    func streamURL(songId: String) -> URL? {
        let encoded = songId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? songId
        return URL(string: "api/v1/stream/songs/\(encoded)", relativeTo: baseURL)?.absoluteURL
    }

    // MARK: - HTTP

    /// Returns `.unchanged` on 304, `.updated` on 200 with body, or `nil` if the host rejects the query.
    private func libraryIfUnchanged(knownRevision: Int) async throws -> LibrarySyncResult? {
        var request = try makeRequest(path: "api/v1/library", method: "GET")
        guard var components = URLComponents(url: request.url!, resolvingAgainstBaseURL: false) else {
            return nil
        }
        components.queryItems = [URLQueryItem(name: "revision", value: String(knownRevision))]
        request.url = components.url
        request.setValue(String(knownRevision), forHTTPHeaderField: "If-None-Match")

        let (data, response) = try await perform(request)
        guard let http = response as? HTTPURLResponse else { return nil }

        if http.statusCode == 304 {
            return .unchanged(revision: knownRevision)
        }
        if http.statusCode == 400 || http.statusCode == 404 {
            return nil
        }
        try validate(response, data: data)
        do {
            let library = try LydJSON.decoder.decode(LibraryDto.self, from: data)
            if library.revision == knownRevision {
                return .unchanged(revision: library.revision)
            }
            return .updated(library)
        } catch {
            throw LydAPIError.decoding(error)
        }
    }

    private func get<T: Decodable>(_ path: String) async throws -> T {
        let request = try makeRequest(path: path, method: "GET")
        let (data, response) = try await perform(request)
        try validate(response, data: data)
        do {
            return try LydJSON.decoder.decode(T.self, from: data)
        } catch {
            throw LydAPIError.decoding(error)
        }
    }

    private func post<Body: Encodable>(_ path: String, body: Body) async throws {
        var request = try makeRequest(path: path, method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try LydJSON.encoder.encode(body)
        let (data, response) = try await perform(request)
        try validate(response, data: data)
    }

    private func post<Body: Encodable, T: Decodable>(_ path: String, body: Body, as: T.Type) async throws -> T {
        var request = try makeRequest(path: path, method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try LydJSON.encoder.encode(body)
        let (data, response) = try await perform(request)
        try validate(response, data: data)
        do {
            return try LydJSON.decoder.decode(T.self, from: data)
        } catch {
            throw LydAPIError.decoding(error)
        }
    }

    private func postEmpty(_ path: String) async throws {
        let request = try makeRequest(path: path, method: "POST")
        let (data, response) = try await perform(request)
        try validate(response, data: data)
    }

    private func delete(_ path: String) async throws {
        let request = try makeRequest(path: path, method: "DELETE")
        let (data, response) = try await perform(request)
        try validate(response, data: data)
    }

    private func makeRequest(path: String, method: String) throws -> URLRequest {
        guard let url = URL(string: path, relativeTo: baseURL)?.absoluteURL else {
            throw LydAPIError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    private func perform(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: request)
        } catch {
            throw LydAPIError.transport(error)
        }
    }

    private func validate(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8)
            throw LydAPIError.badStatus(http.statusCode, body)
        }
    }
}

extension LydAPIClient {
    static func baseURL(host: String, port: Int) -> URL? {
        HostAddress.httpBaseURL(host: host, port: port)
    }
}
