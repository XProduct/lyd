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

struct SongDto: Codable, Hashable, Identifiable {
    var id: String
    var title: String?
    var artist: String?
    var album: String?
    var albumId: String?
    var track: Int?
    var disc: Int?
    var durationMs: Int64?

    var displayTitle: String { title?.nilIfEmpty ?? "Unknown Title" }
    var displayArtist: String { artist?.nilIfEmpty ?? "Unknown Artist" }
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
}

struct PlayRequest: Encodable {
    var songId: String
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
