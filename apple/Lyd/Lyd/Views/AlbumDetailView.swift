import SwiftUI

struct AlbumDetailView: View {
    @EnvironmentObject private var session: LydSession
    let album: AlbumDto

    var body: some View {
        List {
            Section {
                HStack(spacing: 16) {
                    CoverImage(url: session.coverURL(for: album))
                        .frame(width: 120, height: 120)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    VStack(alignment: .leading, spacing: 6) {
                        Text(album.displayTitle)
                            .font(.title2.bold())
                        Text(album.displayArtist)
                            .foregroundStyle(.secondary)
                        Text("\(session.songs(for: album).count) tracks")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }

            Section("Tracks") {
                ForEach(session.songs(for: album)) { song in
                    SongRow(song: song) {
                        Task { await session.play(songId: song.id) }
                    }
                }
            }
        }
        .navigationTitle(album.displayTitle)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}
