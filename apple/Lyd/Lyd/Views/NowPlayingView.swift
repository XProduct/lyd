import SwiftUI

struct NowPlayingView: View {
    @EnvironmentObject private var session: LydSession
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var scrubPosition: Double = 0
    @State private var isScrubbing = false
    @State private var volumeDraft: Double = 0.5
    #if os(tvOS)
    @State private var cinemaMode = false
    @State private var idleReset = UUID()
    #endif

    private var song: SongDto? { session.playback.currentSong }
    private var duration: Double { Double(max(session.playback.durationMs, 0)) }
    private var position: Double {
        isScrubbing ? scrubPosition : Double(max(session.playback.positionMs, 0))
    }
    private var progressFraction: Double {
        guard duration > 0 else { return 0 }
        return min(max(position / duration, 0), 1)
    }
    private var washColor: Color {
        LydMotion.washColor(for: song?.albumId ?? song?.id)
    }

    var body: some View {
        #if os(tvOS)
        tvOSBody
        #else
        iOSBody
        #endif
    }

    // MARK: - iPad / iPhone (unchanged stacked layout)

    #if os(iOS)
    private var iOSBody: some View {
        ScrollView {
            VStack(spacing: 24) {
                ScrollablePageTitle(title: "Now Playing")

                CoverImage(url: coverURL)
                    .frame(maxWidth: 360)
                    .aspectRatio(1, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                metadataBlock(centered: true)

                VStack(spacing: 8) {
                    Slider(
                        value: Binding(
                            get: { position },
                            set: { scrubPosition = $0 }
                        ),
                        in: 0...max(duration, 1),
                        onEditingChanged: { editing in
                            if editing {
                                isScrubbing = true
                                scrubPosition = Double(session.playback.positionMs)
                            } else {
                                isScrubbing = false
                                Task { await session.seek(positionMs: Int64(scrubPosition)) }
                            }
                        }
                    )
                    HStack {
                        Text(format(ms: Int64(position)))
                        Spacer()
                        Text(format(ms: Int64(duration)))
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .padding(.horizontal)

                transportRow

                Button {
                    Task { await session.toggleShuffle() }
                } label: {
                    Label(
                        session.playback.shuffle ? "Shuffle On" : "Shuffle Off",
                        systemImage: "shuffle"
                    )
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(session.playback.shuffle ? LydTheme.primary : Color.secondary)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Volume")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    HStack {
                        Image(systemName: "speaker.fill")
                        Slider(
                            value: Binding(
                                get: { volumeDraft },
                                set: { volumeDraft = $0 }
                            ),
                            in: 0...1,
                            onEditingChanged: { editing in
                                if !editing {
                                    Task { await session.setVolume(volumeDraft) }
                                }
                            }
                        )
                        Image(systemName: "speaker.wave.3.fill")
                    }
                }
                .padding(.horizontal)
                .onChange(of: session.playback.volume) { _, newValue in
                    if abs(newValue - volumeDraft) > 0.02 {
                        volumeDraft = newValue
                    }
                }

                statusFooter
            }
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
            .padding(.horizontal)
            .padding(.top, 8)
            .padding(.bottom, 48)
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollableNavigationTitle(hideBar: true)
        .safeAreaInset(edge: .top, spacing: 0) {
            HostOfflineBanner()
        }
        .onAppear { volumeDraft = session.playback.volume }
    }
    #endif

    // MARK: - tvOS: primary playback page + scroll-down secondary

    #if os(tvOS)
    private var tvOSBody: some View {
        GeometryReader { geo in
            let secondaryOffset = max(geo.size.height * 0.9, 700)

            ZStack {
                ambientWash
                    .ignoresSafeArea()

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        Group {
                            if cinemaMode {
                                tvOSCinemaPage
                            } else {
                                tvOSPrimaryPage
                            }
                        }
                        .frame(minHeight: max(geo.size.height, 720))
                        .padding(.horizontal, 48)
                        .padding(.top, 12)
                        .padding(.bottom, 12)

                        if !cinemaMode {
                            Color.clear
                                .frame(height: secondaryOffset)
                                .accessibilityHidden(true)

                            tvOSSecondarySection
                                .padding(.horizontal, 48)
                                .padding(.bottom, 80)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollDisabled(cinemaMode)
            }
        }
        .background(LydTheme.nowPlayingBackground.ignoresSafeArea())
        .scrollableNavigationTitle()
        .safeAreaInset(edge: .top, spacing: 0) {
            if !cinemaMode {
                HostOfflineBanner()
            }
        }
        .onAppear {
            volumeDraft = session.playback.volume
            bumpIdleTimer()
        }
        .onChange(of: session.playback.currentSongId) { _, _ in
            bumpIdleTimer()
        }
        .onChange(of: session.playback.isPlaying) { _, _ in
            bumpIdleTimer()
        }
        .onChange(of: idleReset) { _, token in
            guard !reduceMotion else {
                cinemaMode = false
                return
            }
            cinemaMode = false
            let captured = token
            Task {
                try? await Task.sleep(nanoseconds: UInt64(LydMotion.cinemaIdleSeconds * 1_000_000_000))
                guard !Task.isCancelled, captured == idleReset else { return }
                guard session.playback.isPlaying else { return }
                withAnimation(.easeInOut(duration: 0.6)) {
                    cinemaMode = true
                }
            }
        }
        .onExitCommand {
            if cinemaMode {
                bumpIdleTimer()
            }
        }
        .simultaneousGesture(
            TapGesture().onEnded { bumpIdleTimer() }
        )
    }

    private var ambientWash: some View {
        RadialGradient(
            colors: [
                washColor.opacity(cinemaMode ? 0.55 : 0.38),
                washColor.opacity(0.12),
                LydTheme.nowPlayingBackground
            ],
            center: .center,
            startRadius: 40,
            endRadius: cinemaMode ? 900 : 700
        )
        .animation(
            reduceMotion ? nil : .easeInOut(duration: LydMotion.washDuration),
            value: song?.albumId ?? song?.id
        )
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.6), value: cinemaMode)
    }

    /// Art + metadata + main transport — first screen; no seek / shuffle / volume.
    private var tvOSPrimaryPage: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollablePageTitle(title: "Now Playing")
                .padding(.bottom, 8)
                .opacity(cinemaMode ? 0 : 1)

            HStack(alignment: .center, spacing: 48) {
                coverArtBlock(maxWidth: 520)

                VStack(alignment: .leading, spacing: 28) {
                    metadataBlock(centered: false)
                        .id(song?.id ?? "none")
                        .transition(reduceMotion ? .identity : .opacity)
                        .animation(
                            reduceMotion ? nil : .easeInOut(duration: LydMotion.crossfadeDuration),
                            value: song?.id
                        )

                    progressReadout

                    transportRow
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if let next = nextUpSong, progressFraction >= 0.82 {
                        nextUpPeek(next)
                            .transition(reduceMotion ? .identity : .move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.35), value: progressFraction >= 0.82)
        }
    }

    /// Idle cinema: large art + metadata; chrome faded (Phase D #9).
    private var tvOSCinemaPage: some View {
        VStack(spacing: 36) {
            Spacer(minLength: 0)
            coverArtBlock(maxWidth: 640)
                .frame(maxWidth: 640)
            metadataBlock(centered: true)
                .id(song?.id ?? "none")
            progressReadout
                .frame(maxWidth: 640)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { bumpIdleTimer() }
    }

    private func coverArtBlock(maxWidth: CGFloat) -> some View {
        CrossfadeValue(value: song?.id ?? "none", reduceMotion: reduceMotion) { _ in
            CoverImage(url: coverURL, morphID: song?.albumId)
                .aspectRatio(1, contentMode: .fit)
                .frame(maxWidth: maxWidth)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .shadow(color: washColor.opacity(0.55), radius: 28, y: 16)
                .lydBreathing(isPlaying: session.playback.isPlaying, reduceMotion: reduceMotion)
                .accessibilityHidden(true)
        }
    }

    /// Elapsed / duration + eased progress — display only (not seekable).
    private var progressReadout: some View {
        VStack(alignment: .leading, spacing: 10) {
            EasedProgressBar(progress: progressFraction, reduceMotion: reduceMotion, tint: washColor)
                .accessibilityLabel("Playback progress")
                .accessibilityValue("\(format(ms: Int64(position))) of \(format(ms: Int64(duration)))")

            HStack {
                CrossfadeTimeLabel(milliseconds: Int64(position), reduceMotion: reduceMotion)
                Spacer()
                CrossfadeTimeLabel(milliseconds: Int64(duration), reduceMotion: reduceMotion)
            }
        }
        .allowsHitTesting(false)
    }

    private var nextUpSong: SongDto? {
        session.predictedNextSong(after: song)
    }

    private func nextUpPeek(_ next: SongDto) -> some View {
        HStack(spacing: 16) {
            CoverImage(url: nextCoverURL(for: next))
                .frame(width: 72, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text("Next")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.secondary)
                Text(next.displayTitle)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color.primary)
                    .lineLimit(1)
                Text(next.displayArtist)
                    .font(.body)
                    .foregroundStyle(Color.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    /// Shuffle, volume, and host status — reached by scrolling down.
    private var tvOSSecondarySection: some View {
        VStack(alignment: .leading, spacing: 28) {
            Text("More")
                .font(.title.bold())
                .foregroundStyle(Color.primary)
                .accessibilityAddTraits(.isHeader)

            TVNowPlayingButton(
                title: session.playback.shuffle ? "Shuffle On" : "Shuffle Off",
                systemImage: "shuffle",
                emphasized: session.playback.shuffle
            ) {
                bumpIdleTimer()
                Task { await session.toggleShuffle() }
            }

            HStack(spacing: 20) {
                Text("Volume")
                    .font(.title3)
                    .foregroundStyle(Color.secondary)
                TVNowPlayingButton(title: "Down", systemImage: "speaker.wave.1.fill") {
                    bumpIdleTimer()
                    Task { await session.setVolume(max(0, session.playback.volume - 0.05)) }
                }
                Text("\(Int((session.playback.volume * 100).rounded()))%")
                    .font(.title3.monospacedDigit())
                    .foregroundStyle(Color.primary)
                    .frame(minWidth: 72, alignment: .center)
                TVNowPlayingButton(title: "Up", systemImage: "speaker.wave.3.fill") {
                    bumpIdleTimer()
                    Task { await session.setVolume(min(1, session.playback.volume + 0.05)) }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                if !session.isHostReachable, let offline = session.offlineMessage {
                    Text(offline)
                        .font(.body)
                        .foregroundStyle(.red)
                } else if let status = session.statusMessage {
                    Text(status)
                        .font(.body)
                        .foregroundStyle(.red)
                }
                Text("Controlling \(session.selectedDisplayName)")
                    .font(.body)
                    .foregroundStyle(Color.secondary)
                Text(session.selectedEndpoint)
                    .font(.body)
                    .foregroundStyle(Color.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func bumpIdleTimer() {
        cinemaMode = false
        idleReset = UUID()
    }

    private func nextCoverURL(for song: SongDto) -> URL? {
        guard let albumId = song.albumId else { return nil }
        if let album = session.library.albums.first(where: { $0.id == albumId }) {
            return session.coverURL(for: album)
        }
        return session.clientCoverFallback(albumId: albumId)
    }
    #endif

    // MARK: - Shared pieces

    private func metadataBlock(centered: Bool) -> some View {
        let textAlignment: TextAlignment = centered ? .center : .leading
        #if os(tvOS)
        let titleFont: Font = .largeTitle.bold()
        let artistFont: Font = .title2
        let albumFont: Font = .title3
        let techFont: Font = .body.monospacedDigit()
        let spacing: CGFloat = 8
        #else
        let titleFont: Font = .title2.bold()
        let artistFont: Font = .title3
        let albumFont: Font = .subheadline
        let techFont: Font = .footnote.monospacedDigit()
        let spacing: CGFloat = 6
        #endif
        return VStack(alignment: centered ? .center : .leading, spacing: spacing) {
            Text(song?.displayTitle ?? "Nothing playing")
                .font(titleFont)
                .foregroundStyle(Color.primary)
                .multilineTextAlignment(textAlignment)
                .lineLimit(3)

            Text(song?.displayArtist ?? session.selectedDisplayName)
                .font(artistFont)
                .foregroundStyle(Color.secondary)
                .multilineTextAlignment(textAlignment)

            if let album = song?.album?.nilIfEmpty {
                Text(album)
                    .font(albumFont)
                    .foregroundStyle(Color.secondary)
                    .multilineTextAlignment(textAlignment)
            }

            if let tech = song?.technicalSummary {
                Text(tech)
                    .font(techFont)
                    .foregroundStyle(Color.secondary)
                    .multilineTextAlignment(textAlignment)
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: centered ? .center : .leading)
    }

    private var transportRow: some View {
        HStack(spacing: 36) {
            Button {
                noteUserActivity()
                Task { await session.previous() }
            } label: {
                Image(systemName: "backward.fill")
                    .font(.largeTitle)
                    .foregroundStyle(Color.primary)
                    .frame(width: 72, height: 72)
            }

            Button {
                noteUserActivity()
                Task { await session.playPause() }
            } label: {
                Image(systemName: session.playback.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 84))
                    .foregroundStyle(LydTheme.primary)
            }

            Button {
                noteUserActivity()
                Task { await session.next() }
            } label: {
                Image(systemName: "forward.fill")
                    .font(.largeTitle)
                    .foregroundStyle(Color.primary)
                    .frame(width: 72, height: 72)
            }
        }
        .buttonStyle(.plain)
    }

    private func noteUserActivity() {
        #if os(tvOS)
        bumpIdleTimer()
        #endif
    }

    @ViewBuilder
    private var statusFooter: some View {
        if let status = session.statusMessage {
            Text(status)
                .font(.footnote)
                .foregroundStyle(.red)
        }

        Text("Controlling \(session.selectedDisplayName) · \(session.selectedEndpoint)")
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    private var coverURL: URL? {
        guard let albumId = song?.albumId else { return nil }
        if let album = session.library.albums.first(where: { $0.id == albumId }) {
            return session.coverURL(for: album)
        }
        return session.clientCoverFallback(albumId: albumId)
    }

    private func format(ms: Int64) -> String {
        let total = max(ms, 0) / 1000
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
    }
}

#if os(tvOS)
/// Focus-safe labeled control for the tvOS Now Playing sidebar.
private struct TVNowPlayingButton: View {
    let title: String
    let systemImage: String
    var emphasized: Bool = false
    let action: () -> Void
    @FocusState private var isFocused: Bool

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.title3.weight(.semibold))
                .labelStyle(.titleAndIcon)
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
                .foregroundStyle(isFocused ? Color.black : (emphasized ? LydTheme.primary : Color.primary))
        }
        .buttonStyle(.card)
        .focused($isFocused)
    }
}
#endif

private extension LydSession {
    func clientCoverFallback(albumId: String) -> URL? {
        coverURL(for: AlbumDto(id: albumId, title: nil, artist: nil, songIds: nil, coverUrl: "/api/v1/albums/\(albumId)/cover"))
    }
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
