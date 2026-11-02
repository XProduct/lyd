import SwiftUI

struct AlbumsView: View {
    @EnvironmentObject private var session: LydSession
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    #if os(tvOS)
    @FocusState private var focusedAlbumID: String?
    /// Staggered entrance runs once per Albums tab appearance — not on every library poll.
    @State private var playsEntranceAnimation = true
    #endif

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
                        TVAlbumPosterCell(
                            album: album,
                            coverURL: session.coverURL(for: album),
                            focusDepthScale: focusDepthScale(for: album.id),
                            staggerIndex: albumIndex(album.id),
                            playsEntrance: playsEntranceAnimation,
                            reduceMotion: reduceMotion
                        )
                        .focused($focusedAlbumID, equals: album.id)
                        .id(album.id)
                        #else
                        NavigationLink(value: album) {
                            AlbumCell(album: album, coverURL: session.coverURL(for: album))
                        }
                        .buttonStyle(.plain)
                        .id(album.id)
                        #endif
                    }
                }
                .padding(.horizontal, gridPadding)
                .padding(.bottom, gridPadding)
                #if os(tvOS)
                .animation(
                    reduceMotion ? nil : .easeOut(duration: 0.28),
                    value: focusedAlbumID
                )
                .onAppear {
                    // After the first layout pass, library polls must not re-trigger fades.
                    guard playsEntranceAnimation else { return }
                    DispatchQueue.main.async {
                        playsEntranceAnimation = false
                    }
                }
                #endif
            }
        }
        .scrollableNavigationTitle(hideBar: true)
        #if os(iOS)
        .refreshable {
            await session.refreshLibrary(force: true)
        }
        #endif
        .navigationDestination(for: AlbumDto.self) { album in
            AlbumDetailView(album: album)
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            HostOfflineBanner()
        }
        .overlay {
            // Sticky latch: once albums loaded, never cover the grid with hydrating empty UI.
            if session.shouldShowAlbumsEmptyState {
                LibraryEmptyState(libraryKind: .albums)
            }
        }
    }

    private func albumIndex(_ id: String) -> Int {
        session.library.albums.firstIndex(where: { $0.id == id }) ?? 0
    }

    #if os(tvOS)
    private func focusDepthScale(for albumID: String) -> CGFloat {
        guard LydMotion.allowsMotion(reduceMotion), let focusedAlbumID else { return 1 }
        if focusedAlbumID == albumID { return 1 }
        return 0.94
    }
    #endif

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
        0
        #endif
    }
}

#if os(tvOS)
/// tvOS album tile: NavigationLink + `.buttonStyle(.card)` so Siri Remote focus
/// gets Apple’s native lift/parallax (home-screen-style). Labels sit outside the card.
private struct TVAlbumPosterCell: View {
    let album: AlbumDto
    let coverURL: URL?
    var focusDepthScale: CGFloat = 1
    var staggerIndex: Int = 0
    /// False after the first Albums grid entrance — prevents poll-driven clear/fade.
    var playsEntrance: Bool = false
    var reduceMotion: Bool = false

    @State private var appeared = false

    private let titleLineHeight: CGFloat = 28
    private let artistLineHeight: CGFloat = 24

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            NavigationLink(value: album) {
                CoverImage(url: coverURL, morphID: album.id)
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
        .scaleEffect(focusDepthScale)
        .opacity(appeared || !playsEntrance || reduceMotion ? 1 : 0)
        .offset(y: appeared || !playsEntrance || reduceMotion ? 0 : 18)
        .onAppear {
            if !playsEntrance || reduceMotion {
                appeared = true
                return
            }
            guard !appeared else { return }
            let delay = min(Double(staggerIndex) * LydMotion.staggerStep, 0.6)
            withAnimation(.easeOut(duration: 0.4).delay(delay)) {
                appeared = true
            }
        }
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
    /// Stable id for Phase D matched-geometry morph (album id).
    var morphID: String? = nil
    @Environment(\.coverMorphNamespace) private var coverMorphNamespace

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
        .modifier(CoverMorphModifier(morphID: morphID, namespace: coverMorphNamespace))
    }

    private var placeholder: some View {
        Image(systemName: "music.note")
            .font(.largeTitle)
            .foregroundStyle(Color.secondary)
    }
}

private struct CoverMorphModifier: ViewModifier {
    let morphID: String?
    let namespace: Namespace.ID?

    func body(content: Content) -> some View {
        if let morphID, let namespace {
            content.matchedGeometryEffect(id: morphID, in: namespace)
        } else {
            content
        }
    }
}
