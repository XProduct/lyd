import Foundation

enum LydAPIError: LocalizedError {
    case invalidURL
    case badStatus(Int, String?)
    case decoding(Error)
    case transport(Error)

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
        }
    }
}

final class LydAPIClient: @unchecked Sendable {
    private let session: URLSession
    private let lock = NSLock()
    private var _baseURL: URL

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

    func playbackState() async throws -> PlaybackStateDto {
        try await get("api/v1/playback/state")
    }

    func play(songId: String) async throws {
        try await post("api/v1/playback/play", body: PlayRequest(songId: songId))
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

    func coverURL(for relativeOrAbsolute: String?) -> URL? {
        guard let value = relativeOrAbsolute, !value.isEmpty else { return nil }
        if let absolute = URL(string: value), absolute.scheme != nil {
            return absolute
        }
        return URL(string: value, relativeTo: baseURL)?.absoluteURL
    }

    // MARK: - HTTP

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

    private func postEmpty(_ path: String) async throws {
        let request = try makeRequest(path: path, method: "POST")
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
        var components = URLComponents()
        components.scheme = "http"
        let trimmed = host.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.contains(":") && !trimmed.contains(".") {
            // Likely IPv6 — leave for later; Phase A is IPv4 LAN.
        }
        components.host = trimmed
        components.port = port
        components.path = "/"
        return components.url
    }
}
