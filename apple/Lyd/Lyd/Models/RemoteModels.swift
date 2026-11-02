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

struct PlaybackOutputTargetDto: Codable, Hashable, Identifiable {
    var deviceId: String
    var deviceName: String?

    var id: String { deviceId }

    var displayName: String {
        let name = deviceName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? deviceId : name
    }
}

struct PlaybackStateDto: Codable, Hashable {
    var isPlaying: Bool
    var shuffle: Bool
    var positionMs: Int64
    var durationMs: Int64
    var currentSongId: String?
    var currentSong: SongDto?
    var volume: Double
    /// Legacy: "host" | "remote" | "multi" (optional on older hosts).
    var outputTarget: String?
    var outputDeviceId: String?
    /// Multi-select Playing on targets (`deviceId` "host" = Windows).
    var outputTargets: [PlaybackOutputTargetDto]?
    /// Bumped on host seek / track start so the Apple renderer re-seeks.
    var seekGeneration: Int64?
    /// Phase F1 host timeline (optional on older hosts).
    var anchorUnixMs: Int64?
    var positionAtAnchorMs: Int64?
    /// Host’s timeline estimate at serialize time (optional).
    var timelineMs: Int64?

    /// Host-reported position at the timeline anchor (no client-clock math).
    var hostAnchoredPositionMs: Int64 {
        if let positionAtAnchorMs {
            return max(0, positionAtAnchorMs)
        }
        if let timelineMs {
            return max(0, timelineMs)
        }
        return max(0, positionMs)
    }

    /// Raw wall-clock extrapolation. **Unsafe across devices** unless `hostClockSkewMs`
    /// corrects for (clientUnixNow − hostUnixNow). Prefer session receive-time rebasing.
    /// - Parameter hostClockSkewMs: estimate of clientNow − hostNow (positive ⇒ client clock ahead).
    func desiredPositionMs(at date: Date = Date(), hostClockSkewMs: Int64 = 0) -> Int64 {
        if let anchor = anchorUnixMs, let atAnchor = positionAtAnchorMs {
            if !isPlaying {
                return max(0, atAnchor)
            }
            let nowMs = Int64(date.timeIntervalSince1970 * 1000)
            return max(0, atAnchor + (nowMs - anchor - hostClockSkewMs))
        }
        return hostAnchoredPositionMs
    }
}

struct PlaybackOutputRequest: Encodable {
    var target: String?
    var deviceId: String?
    var deviceName: String?
    var targets: [PlaybackOutputTargetDto]?
}

struct PlaybackHeartbeatRequest: Encodable {
    var deviceId: String
    var positionMs: Int64
    var durationMs: Int64?
    var songId: String?
}

struct PlayerRegisterRequest: Encodable {
    var deviceId: String
    var name: String
    var platform: String
    var capabilities: [String]
}

struct PlayerDto: Codable, Hashable, Identifiable {
    var deviceId: String
    var name: String?
    var platform: String?
    var capabilities: [String]?
    var lastSeenUnixMs: Int64?
    var isOutput: Bool?

    var id: String { deviceId }

    var displayName: String {
        let n = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return n.isEmpty ? deviceId : n
    }
}

struct PlayersResponse: Codable {
    var players: [PlayerDto]?
}

enum LydOutputIds {
    static let host = "host"
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
