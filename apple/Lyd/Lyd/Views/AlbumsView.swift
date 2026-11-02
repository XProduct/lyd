import SwiftUI

struct AlbumsView: View {
    @EnvironmentObject private var session: LydSession

    private var columns: [GridItem] {
        #if os(tvOS)
        // ~6 albums per row; leave room for CardButtonStyle focus scale.
        Array(repeating: GridItem(.flexible(), spacing: 40, alignment: .top), count: 6)
        #else
        [GridItem(.adaptive(minimum: 140), spacing: 16, alignment: .top)]
        #endif
    }

    private var gridSpacing: CGFloat {
        #if os(tvOS)
        36
        #else
        16
        #endif
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: gridSpacing) {
                ScrollablePageTitle(title: "Albums")
                    .padding(.horizontal, gridPadding)
                    .padding(.top, titleTopPadding)

                LazyVGrid(columns: columns, alignment: .leading, spacing: gridSpacing) {
                    ForEach(session.library.albums) { album in
                        #if os(tvOS)
                        TVAlbumPosterCell(album: album, coverURL: session.coverURL(for: album))
                        #else
                        NavigationLink(value: album) {
                            AlbumCell(album: album, coverURL: session.coverURL(for: album))
                        }
                        .buttonStyle(.plain)
                        #endif
                    }
                }
                .padding(.horizontal, gridPadding)
                .padding(.bottom, gridPadding)
            }
        }
        .scrollableNavigationTitle()
        #if os(iOS)
        .toolbarBackground(.visible, for: .navigationBar)
        .refreshable {
            await session.refreshLibrary(force: true)
        }
        #endif
        .navigationDestination(for: AlbumDto.self) { album in
            AlbumDetailView(album: album)
        }
        .overlay {
            if session.library.albums.isEmpty {
                ContentUnavailableView(
                    session.phase == .connected ? "No albums yet" : "Not connected",
                    systemImage: "square.stack",
                    description: Text(
                        session.phase == .connected
                            ? "Library revision \(max(session.library.revision, 0)). Waiting for the Windows host to finish scanning."
                            : "Choose a Lyd host in Settings."
                    )
                )
            }
        }
    }

    private var gridPadding: CGFloat {
        #if os(tvOS)
        48
        #else
        16
        #endif
    }

    private var titleTopPadding: CGFloat {
        #if os(tvOS)
        24
        #else
        8
        #endif
    }
}

#if os(tvOS)
/// tvOS album tile: NavigationLink + `.buttonStyle(.card)` so Siri Remote focus
/// gets Apple’s native lift/parallax (home-screen-style). Labels sit outside the card.
private struct TVAlbumPosterCell: View {
    let album: AlbumDto
    let coverURL: URL?

    private let titleLineHeight: CGFloat = 28
    private let artistLineHeight: CGFloat = 24

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            NavigationLink(value: album) {
                CoverImage(url: coverURL)
                    .aspectRatio(1, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .frame(maxWidth: .infinity)
            }
            // Critical: `.card` (not `.plain`) — plain suppressed focus motion before.
            .buttonStyle(.card)

            VStack(alignment: .leading, spacing: 2) {
                Text(album.displayTitle)
                    .font(.headline)
                    .foregroundStyle(Color.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                Text(album.displayArtist)
                    .font(.subheadline)
                    .foregroundStyle(Color.secondary)
                    .lineLimit(1)
            }
            .frame(
                maxWidth: .infinity,
                minHeight: titleLineHeight * 2 + 2 + artistLineHeight,
                alignment: .topLeading
            )
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}
#endif

struct AlbumCell: View {
    let album: AlbumDto
    let coverURL: URL?

    private var titleLineHeight: CGFloat {
        #if os(tvOS)
        28
        #else
        20
        #endif
    }

    private var artistLineHeight: CGFloat {
        #if os(tvOS)
        24
        #else
        18
        #endif
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            CoverImage(url: coverURL)
                .aspectRatio(1, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(album.displayTitle)
                    .font(.headline)
                    .foregroundStyle(Color.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                Text(album.displayArtist)
                    .font(.subheadline)
                    .foregroundStyle(Color.secondary)
                    .lineLimit(1)
            }
            .frame(
                maxWidth: .infinity,
                minHeight: titleLineHeight * 2 + 2 + artistLineHeight,
                alignment: .topLeading
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .tint(Color.primary)
    }
}

struct CoverImage: View {
    let url: URL?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.quaternary)
            if let url {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        placeholder
                    case .empty:
                        ProgressView()
                    @unknown default:
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .clipped()
    }

    private var placeholder: some View {
        Image(systemName: "music.note")
            .font(.largeTitle)
            .foregroundStyle(Color.secondary)
    }
}
