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
                    AlbumNavigationCell(album: album, coverURL: session.coverURL(for: album))
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

/// Navigation wrapper so tvOS can apply a home-screen-style focus lift without purple label tint.
private struct AlbumNavigationCell: View {
    let album: AlbumDto
    let coverURL: URL?
    #if os(tvOS)
    @FocusState private var isFocused: Bool
    #endif

    var body: some View {
        NavigationLink(value: album) {
            #if os(tvOS)
            AlbumCell(album: album, coverURL: coverURL, isFocused: isFocused)
            #else
            AlbumCell(album: album, coverURL: coverURL, isFocused: false)
            #endif
        }
        .buttonStyle(.plain)
        #if os(tvOS)
        .focused($isFocused)
        .scaleEffect(isFocused ? 1.06 : 1.0, anchor: .center)
        .offset(y: isFocused ? -8 : 0)
        .shadow(color: .black.opacity(isFocused ? 0.45 : 0), radius: isFocused ? 18 : 0, y: isFocused ? 12 : 0)
        .zIndex(isFocused ? 1 : 0)
        .animation(.easeOut(duration: 0.18), value: isFocused)
        #endif
    }
}

struct AlbumCell: View {
    let album: AlbumDto
    let coverURL: URL?
    var isFocused: Bool = false

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
                #if os(tvOS)
                .scaleEffect(isFocused ? 1.03 : 1.0)
                .shadow(color: .black.opacity(isFocused ? 0.35 : 0.12), radius: isFocused ? 14 : 4, y: isFocused ? 10 : 2)
                #endif

            // Pack title + artist tightly; reserve caption height so covers stay
            // top-aligned across the row without a gap between a 1-line title and artist.
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
