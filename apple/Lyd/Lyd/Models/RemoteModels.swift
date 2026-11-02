import Foundation

/// Phase A Windows API DTOs (Newtonsoft default = PascalCase).
struct HealthDto: Codable, Hashable {
    var name: String
    var version: String
    var api: Int
    var port: Int?
}

struct LibraryDto: Codable, Hashable {
    var songs: [SongDto]
    var albums: [AlbumDto]
    var revision: Int
}

/// Thin `GET /api/v1/library/revision` payload (Phase C). Older hosts may 404.
struct LibraryRevisionDto: Codable, Hashable {
    var revision: Int
}

struct SongDto: Codable, Hashable, Identifiable {
    var id: String
    var title: String?
    var artist: String?
    var album: String?
    var albumId: String?
    var track: Int?
    var disc: Int?
    var durationMs: Int64?
    /// kbps
    var bitrate: Double?
    /// kHz (Windows host stores sample rate / 1000)
    var sampleRate: Double?
    /// bits per sample
    var depth: Double?

    var displayTitle: String { title?.nilIfEmpty ?? "Unknown Title" }
    var displayArtist: String { artist?.nilIfEmpty ?? "Unknown Artist" }

    /// e.g. "24-bit · 96 kHz · 2,048 kbps"
    var technicalSummary: String? {
        var parts: [String] = []
        if let depth, depth > 0 {
            parts.append("\(Int(depth.rounded()))-bit")
        }
        if let sampleRate, sampleRate > 0 {
            let formatted = sampleRate == floor(sampleRate)
                ? String(Int(sampleRate))
                : String(format: "%g", sampleRate)
            parts.append("\(formatted) kHz")
        }
        if let bitrate, bitrate > 0 {
            let kbps = Int(bitrate.rounded())
            parts.append("\(kbps) kbps")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

struct AlbumDto: Codable, Hashable, Identifiable {
    var id: String
    var title: String?
    var artist: String?
    var songIds: [String]?
    var coverUrl: String?

    var displayTitle: String { title?.nilIfEmpty ?? "Unknown Album" }
    var displayArtist: String { artist?.nilIfEmpty ?? "Unknown Artist" }
}

struct PlaybackStateDto: Codable, Hashable {
    var isPlaying: Bool
    var shuffle: Bool
    var positionMs: Int64
    var durationMs: Int64
    var currentSongId: String?
    var currentSong: SongDto?
    var volume: Double
    /// Phase E: "host" | "remote" (optional on older hosts).
    var outputTarget: String?
    var outputDeviceId: String?
}

struct PlaybackOutputRequest: Encodable {
    var target: String
    var deviceId: String?
    var deviceName: String?
}

enum PlaybackOutputMode: String, CaseIterable, Identifiable, Hashable {
    case host
    case thisDevice

    var id: String { rawValue }

    func title(hostName: String) -> String {
        switch self {
        case .host:
            return hostName.isEmpty ? "Host" : hostName
        case .thisDevice:
            return "This device"
        }
    }
}

struct PlayRequest: Encodable {
    var songId: String
}

struct PlayAlbumRequest: Encodable {
    var albumId: String
}

struct SeekRequest: Encodable {
    var positionMs: Int64
}

struct VolumeRequest: Encodable {
    /// irrKlang scale: 0.0 … 1.0
    var level: Double
}

struct ShuffleRequest: Encodable {
    var enabled: Bool?
}

struct OkResponse: Codable {
    var ok: Bool?
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
