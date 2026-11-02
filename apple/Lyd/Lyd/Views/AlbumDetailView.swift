import SwiftUI

struct AlbumDetailView: View {
    @EnvironmentObject private var session: LydSession
    let album: AlbumDto

    private var tracks: [SongDto] { session.songs(for: album) }

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
                            .foregroundStyle(Color.primary)
                        Text(album.displayArtist)
                            .foregroundStyle(Color.secondary)
                        Text("\(tracks.count) tracks")
                            .font(.footnote)
                            .foregroundStyle(Color.secondary)

                        Button {
                            Task { await session.playAlbum(albumId: album.id) }
                        } label: {
                            Label("Play Album", systemImage: "play.fill")
                                .font(.body.weight(.semibold))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(LydTheme.primary)
                        .disabled(tracks.isEmpty)
                        .padding(.top, 6)
                    }
                }
                .padding(.vertical, 4)
            }

            Section("Tracks") {
                ForEach(tracks) { song in
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
