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
        List {
            ScrollablePageTitle(title: "Songs")
                .scrollableListTitleRow()

            #if os(iOS)
            TextField("Title, artist, album", text: $query)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 8, trailing: 16))
            #endif

            ForEach(filtered) { song in
                SongRow(song: song) {
                    Task { await session.play(songId: song.id) }
                }
            }
        }
        .scrollableNavigationTitle(hideBar: true)
        #if os(iOS)
        .refreshable {
            await session.refreshLibrary(force: true)
        }
        #endif
        .overlay {
            if session.library.songs.isEmpty {
                ContentUnavailableView(
                    session.phase == .connected ? "No songs yet" : "Not connected",
                    systemImage: "music.note.list",
                    description: Text(
                        session.phase == .connected
                            ? "Connect to a Lyd host that has finished scanning."
                            : "Choose a Lyd host in Settings."
                    )
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
                        .foregroundStyle(Color.primary)
                    Text("\(song.displayArtist) · \(song.album ?? "Unknown Album")")
                        .font(.footnote)
                        .foregroundStyle(Color.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "play.fill")
                    .foregroundStyle(Color.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .tint(Color.primary)
    }
}
