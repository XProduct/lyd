import SwiftUI

struct AlbumsView: View {
    @EnvironmentObject private var session: LydSession

    private let columns: [GridItem] = [
        GridItem(.adaptive(minimum: albumMinimum), spacing: 16)
    ]

    private static var albumMinimum: CGFloat {
        #if os(tvOS)
        220
        #else
        140
        #endif
    }

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(session.library.albums) { album in
                    NavigationLink(value: album) {
                        AlbumCell(album: album, coverURL: session.coverURL(for: album))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
        }
        .navigationTitle("Albums")
        .navigationDestination(for: AlbumDto.self) { album in
            AlbumDetailView(album: album)
        }
        .toolbar { HostToolbar() }
        .overlay {
            if session.library.albums.isEmpty {
                ContentUnavailableView(
                    "No albums yet",
                    systemImage: "square.stack",
                    description: Text("Library revision \(max(session.library.revision, 0)). Waiting for the Windows host to finish scanning.")
                )
            }
        }
    }
}

struct AlbumCell: View {
    let album: AlbumDto
    let coverURL: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            CoverImage(url: coverURL)
                .aspectRatio(1, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            Text(album.displayTitle)
                .font(.headline)
                .lineLimit(2)
            Text(album.displayArtist)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
