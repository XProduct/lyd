import SwiftUI

struct AlbumsView: View {
    @EnvironmentObject private var session: LydSession

    private var columns: [GridItem] {
        #if os(tvOS)
        // ~6 albums per row on typical Apple TV widths; generous gutters.
        Array(repeating: GridItem(.flexible(), spacing: 32, alignment: .top), count: 6)
        #else
        [GridItem(.adaptive(minimum: 140), spacing: 16, alignment: .top)]
        #endif
    }

    private var gridSpacing: CGFloat {
        #if os(tvOS)
        32
        #else
        16
        #endif
    }

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, alignment: .leading, spacing: gridSpacing) {
                ForEach(session.library.albums) { album in
                    NavigationLink(value: album) {
                        AlbumCell(album: album, coverURL: session.coverURL(for: album))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(gridPadding)
        }
        .navigationTitle("Albums")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
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
        40
        #else
        16
        #endif
    }
}

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

            // Fixed two-line title slot so shorter titles don't shift neighbors.
            Text(album.displayTitle)
                .font(.headline)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, minHeight: titleLineHeight * 2, alignment: .topLeading)

            Text(album.displayArtist)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, minHeight: artistLineHeight, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
            .foregroundStyle(.secondary)
    }
}
