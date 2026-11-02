import SwiftUI

struct SongsView: View {
    @EnvironmentObject private var session: LydSession
    @State private var query = ""

    private var filtered: [SongDto] {
        let songs = session.library.songs
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return songs }
        return songs.filter {
            ($0.title ?? "").localizedCaseInsensitiveContains(q)
                || ($0.artist ?? "").localizedCaseInsensitiveContains(q)
                || ($0.album ?? "").localizedCaseInsensitiveContains(q)
        }
    }

    var body: some View {
        List(filtered) { song in
            SongRow(song: song) {
                Task { await session.play(songId: song.id) }
            }
        }
        .navigationTitle("Songs")
        #if os(iOS)
        .searchable(text: $query, prompt: "Title, artist, album")
        #endif
        .toolbar { HostToolbar() }
        .overlay {
            if session.library.songs.isEmpty {
                ContentUnavailableView(
                    "No songs yet",
                    systemImage: "music.note.list",
                    description: Text("Connect to a Lyd host that has finished scanning.")
                )
            }
        }
    }
}

struct SongRow: View {
    let song: SongDto
    let onPlay: () -> Void

    var body: some View {
        Button(action: onPlay) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(song.displayTitle)
                        .font(.body.weight(.medium))
                    Text("\(song.displayArtist) · \(song.album ?? "Unknown Album")")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "play.fill")
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
