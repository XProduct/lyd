import SwiftUI

struct AlbumDetailView: View {
    @EnvironmentObject private var session: LydSession
    let album: AlbumDto

    private var tracks: [SongDto] { session.songs(for: album) }

    private var artworkMaxSide: CGFloat {
        #if os(tvOS)
        420
        #else
        320
        #endif
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 16) {
                    CoverImage(url: session.coverURL(for: album))
                        .aspectRatio(1, contentMode: .fit)
                        .frame(maxWidth: artworkMaxSide)
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                    Button {
                        Task { await session.playAlbum(albumId: album.id) }
                    } label: {
                        Label("Play Album", systemImage: "play.fill")
                            .font(.body.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            #if os(tvOS)
                            .padding(.vertical, 8)
                            #endif
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(LydTheme.primary)
                    .disabled(tracks.isEmpty)
                    .frame(maxWidth: .infinity)

                    VStack(alignment: .leading, spacing: 6) {
                        ScrollablePageTitle(title: album.displayTitle)
                        Text(album.displayArtist)
                            .foregroundStyle(Color.secondary)
                        Text("\(tracks.count) tracks")
                            .font(.footnote)
                            .foregroundStyle(Color.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
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
        .scrollableNavigationTitle()
    }
}
