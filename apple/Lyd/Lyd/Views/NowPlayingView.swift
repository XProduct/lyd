import SwiftUI
#if os(tvOS)
import UIKit
#endif

struct NowPlayingView: View {
    @EnvironmentObject private var session: LydSession
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var scrubPosition: Double = 0
    @State private var isScrubbing = false
    @State private var volumeDraft: Double = 0.5
    #if os(tvOS)
    @State private var cinemaMode = false
    @State private var idleReset = UUID()
    @FocusState private var cinemaSurfaceFocused: Bool
    #endif

    private var song: SongDto? { session.playback.currentSong }
    private var duration: Double { Double(max(session.effectiveDurationMs, 0)) }
    private var position: Double {
        isScrubbing ? scrubPosition : Double(max(session.effectivePositionMs, 0))
    }
    private var progressFraction: Double {
        guard duration > 0 else { return 0 }
        return min(max(position / duration, 0), 1)
    }
    private var washColor: Color {
        LydMotion.washColor(for: song?.albumId ?? song?.id)
    }
    /// Play/pause accent — wash-matched on tvOS, brand purple on iPad.
    private var playAccentColor: Color {
        #if os(tvOS)
        washColor
        #else
        LydTheme.primary
        #endif
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
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 24) {
                    Color.clear.frame(height: 0).id("nowPlayingTop")

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
                                    scrubPosition = Double(session.effectivePositionMs)
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

                    playingOnPicker

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
                        Text(session.usesDeviceVolume ? "Device volume" : "Host volume")
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
            .onChange(of: session.nowPlayingScrollToken) { _, _ in
                DispatchQueue.main.async {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo("nowPlayingTop", anchor: .top)
                    }
                }
            }
        }
    }
    #endif

    // MARK: - tvOS: primary playback page + scroll-down secondary

    #if os(tvOS)
    private var tvOSBody: some View {
        GeometryReader { geo in
            ZStack {
                LydTheme.nowPlayingBackground
                    .ignoresSafeArea()

                ambientWash
                    .ignoresSafeArea()

                if cinemaMode {
                    // Outside ScrollView — avoids light scroll chrome / white focus sheets.
                    tvOSCinemaPage
                        .frame(width: geo.size.width, height: geo.size.height)
                } else {
                    ScrollViewReader { proxy in
                        ScrollView(.vertical, showsIndicators: false) {
                            VStack(alignment: .leading, spacing: 0) {
                                Color.clear.frame(height: 0).id("nowPlayingTop")

                                // Primary fills one viewport so More sits just below the fold.
                                // Do NOT insert a large empty spacer — tvOS focus cannot travel
                                // back up across a non-focusable gap (got stuck in More).
                                tvOSPrimaryPage
                                    .frame(minHeight: max(geo.size.height - 24, 680))
                                    .padding(.horizontal, 48)
                                    .padding(.top, 12)
                                    .padding(.bottom, 24)
                                    .id("nowPlayingPrimary")

                                tvOSSecondarySection
                                    .padding(.horizontal, 48)
                                    .padding(.top, 8)
                                    .padding(.bottom, 80)
                                    .id("nowPlayingMore")
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        // Keep ScrollView dark; `.scrollContentBackground` is iOS-only.
                        .background(LydTheme.nowPlayingBackground)
                        .onChange(of: session.nowPlayingScrollToken) { _, _ in
                            DispatchQueue.main.async {
                                withAnimation(.easeOut(duration: 0.2)) {
                                    proxy.scrollTo("nowPlayingTop", anchor: .top)
                                }
                            }
                        }
                    }
                }
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
            UIApplication.shared.isIdleTimerDisabled = true
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
        }
        // Do not defaultFocus play/pause — let tvOS keep natural / last-control focus
        // (reverses Phase D “always land on play”).
        // Track / play-state changes must NOT exit cinema — art/metadata update in place.
        // Only remote interaction (below) calls bumpIdleTimer().
        .onChange(of: idleReset) { _, token in
            guard !reduceMotion else {
                cinemaMode = false
                return
            }
            // bumpIdleTimer() already left cinema; schedule re-entry after idle.
            let captured = token
            Task {
                try? await Task.sleep(nanoseconds: UInt64(LydMotion.cinemaIdleSeconds * 1_000_000_000))
                guard !Task.isCancelled, captured == idleReset else { return }
                guard session.effectiveIsPlaying else { return }
                withAnimation(.easeInOut(duration: 0.6)) {
                    cinemaMode = true
                }
                cinemaSurfaceFocused = true
            }
        }
        .onChange(of: cinemaMode) { _, enabled in
            if enabled {
                cinemaSurfaceFocused = true
            }
        }
        // Any Siri Remote interaction exits idle cinema and resets the timer.
        .onMoveCommand { _ in
            bumpIdleTimer()
        }
        .onPlayPauseCommand {
            bumpIdleTimer()
            Task { await session.playPause() }
        }
        .onExitCommand {
            bumpIdleTimer()
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
    /// No full-screen Button — tvOS paints a white focus plate on focused buttons.
    private var tvOSCinemaPage: some View {
        VStack(spacing: 28) {
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
        .padding(.horizontal, 48)
        .background {
            LydTheme.nowPlayingBackground
                .overlay(ambientWash.opacity(0.85))
                .ignoresSafeArea()
        }
        .contentShape(Rectangle())
        .focusable()
        .focused($cinemaSurfaceFocused)
        .focusEffectDisabled()
        .accessibilityLabel("Now Playing cinema mode")
        .onTapGesture { bumpIdleTimer() }
        .onMoveCommand { _ in bumpIdleTimer() }
        .onPlayPauseCommand {
            bumpIdleTimer()
            Task { await session.playPause() }
        }
    }

    private func coverArtBlock(maxWidth: CGFloat) -> some View {
        CrossfadeValue(value: song?.id ?? "none", reduceMotion: reduceMotion) { _ in
            CoverImage(url: coverURL, morphID: song?.albumId)
                .aspectRatio(1, contentMode: .fit)
                .frame(maxWidth: maxWidth)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .shadow(color: washColor.opacity(0.55), radius: 28, y: 16)
                .lydBreathing(isPlaying: session.effectiveIsPlaying, reduceMotion: reduceMotion)
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

    /// Shuffle, volume, and host status — reached by scrolling / focus moving down.
    /// One focusSection for the whole More block so up from its first control can
    /// leave to the primary transport section (nested sections trapped focus before).
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

            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Playing on")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Color.primary)
                        .accessibilityAddTraits(.isHeader)
                    Text(session.allowMultiOutput
                         ? "Devices that should play audio"
                         : "One device plays audio")
                        .font(.callout)
                        .foregroundStyle(Color.secondary)
                }

                VStack(spacing: 12) {
                    TVPlayingOnRow(
                        title: session.selectedDisplayName.isEmpty ? "Host" : session.selectedDisplayName,
                        subtitle: "Windows Lyd",
                        systemImage: "desktopcomputer",
                        selected: session.isHostAudioOutput,
                        singleSelect: !session.allowMultiOutput
                    ) {
                        bumpIdleTimer()
                        Task {
                            await session.setOutputTarget(
                                deviceId: LydOutputIds.host,
                                enabled: !session.isHostAudioOutput
                            )
                        }
                    }
                    TVPlayingOnRow(
                        title: "This Apple TV",
                        subtitle: DeviceIdentity.displayName,
                        systemImage: "appletv",
                        selected: session.isLocalAudioOutput,
                        singleSelect: !session.allowMultiOutput
                    ) {
                        bumpIdleTimer()
                        Task {
                            await session.setOutputTarget(
                                deviceId: DeviceIdentity.deviceId,
                                enabled: !session.isLocalAudioOutput
                            )
                        }
                    }
                    ForEach(session.registeredPlayers) { player in
                        TVPlayingOnRow(
                            title: player.displayName,
                            subtitle: player.platformLabel,
                            systemImage: "hifispeaker",
                            selected: session.outputTargetIds.contains(player.deviceId),
                            singleSelect: !session.allowMultiOutput
                        ) {
                            bumpIdleTimer()
                            Task {
                                await session.setOutputTarget(
                                    deviceId: player.deviceId,
                                    enabled: !session.outputTargetIds.contains(player.deviceId)
                                )
                            }
                        }
                    }
                }
            }

            HStack(spacing: 20) {
                Text(session.usesDeviceVolume ? "Device volume" : "Host volume")
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
        .focusSection()
    }

    private func bumpIdleTimer() {
        cinemaMode = false
        idleReset = UUID()
        // Leave transport focus alone — do not yank the Siri Remote back to play/pause.
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
        // Slightly tighter than largeTitle stack so artist/album aren't clipped at the bottom.
        let titleFont: Font = .title.bold()
        let artistFont: Font = .title3
        let albumFont: Font = .body
        let techFont: Font = .callout.monospacedDigit()
        let spacing: CGFloat = 6
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
                .lineLimit(2)

            Text(song?.displayArtist ?? session.selectedDisplayName)
                .font(artistFont)
                .foregroundStyle(Color.secondary)
                .multilineTextAlignment(textAlignment)
                .lineLimit(1)

            if let album = song?.album?.nilIfEmpty {
                Text(album)
                    .font(albumFont)
                    .foregroundStyle(Color.secondary)
                    .multilineTextAlignment(textAlignment)
                    .lineLimit(1)
            }

            if let tech = song?.technicalSummary {
                Text(tech)
                    .font(techFont)
                    .foregroundStyle(Color.secondary)
                    .multilineTextAlignment(textAlignment)
                    .lineLimit(1)
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
                Image(systemName: session.effectiveIsPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 84))
                    .foregroundStyle(playAccentColor)
                    .animation(
                        reduceMotion ? nil : .easeInOut(duration: LydMotion.washDuration),
                        value: song?.albumId ?? song?.id
                    )
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
        #if os(tvOS)
        .focusSection()
        #endif
    }

    private func noteUserActivity() {
        #if os(tvOS)
        bumpIdleTimer()
        #endif
    }

    #if os(iOS)
    private var playingOnPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Playing on")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Text(session.allowMultiOutput
                 ? "Choose where audio plays. Uncheck This device to control without streaming here."
                 : "Choose one device for audio. Enable Allow multi-room output on the host to select several.")
                .font(.caption2)
                .foregroundStyle(.secondary)

            outputToggleRow(
                title: session.selectedDisplayName.isEmpty ? "Host" : session.selectedDisplayName,
                systemImage: "desktopcomputer",
                selected: session.isHostAudioOutput,
                singleSelect: !session.allowMultiOutput
            ) {
                Task {
                    await session.setOutputTarget(
                        deviceId: LydOutputIds.host,
                        enabled: !session.isHostAudioOutput
                    )
                }
            }

            outputToggleRow(
                title: "This device",
                systemImage: "iphone",
                selected: session.isLocalAudioOutput,
                singleSelect: !session.allowMultiOutput
            ) {
                Task {
                    await session.setOutputTarget(
                        deviceId: DeviceIdentity.deviceId,
                        enabled: !session.isLocalAudioOutput
                    )
                }
            }

            ForEach(session.registeredPlayers) { player in
                outputToggleRow(
                    title: player.displayName,
                    systemImage: "hifispeaker",
                    selected: session.outputTargetIds.contains(player.deviceId),
                    singleSelect: !session.allowMultiOutput
                ) {
                    Task {
                        await session.setOutputTarget(
                            deviceId: player.deviceId,
                            enabled: !session.outputTargetIds.contains(player.deviceId)
                        )
                    }
                }
            }
        }
        .padding(.horizontal)
    }

    private func outputToggleRow(
        title: String,
        systemImage: String,
        selected: Bool,
        singleSelect: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                // Multi: checkbox. Single: radio (one Playing on device).
                Image(systemName: selected
                      ? (singleSelect ? "circle.inset.filled" : "checkmark.circle.fill")
                      : "circle")
                    .foregroundStyle(selected ? LydTheme.primary : Color.secondary)
                Label(title, systemImage: systemImage)
                    .foregroundStyle(Color.primary)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
        .accessibilityHint(singleSelect ? "Selects this device only" : "Toggles this device in Playing on")
    }
    #endif

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
        Text("Playing on \(session.playingOnSummary)")
            .font(.caption)
            .foregroundStyle(.secondary)
        if !session.isLocalAudioOutput {
            Text("Remote only — no audio on this device")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
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
/// Focus-safe labeled control for the tvOS Now Playing sidebar (shuffle / volume).
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

/// Native-feeling Playing on row — list layout + trailing check, not a chunky card stack.
private struct TVPlayingOnRow: View {
    let title: String
    var subtitle: String?
    let systemImage: String
    let selected: Bool
    var singleSelect: Bool = false
    let action: () -> Void
    @FocusState private var isFocused: Bool

    var body: some View {
        Button(action: action) {
            HStack(spacing: 20) {
                Image(systemName: systemImage)
                    .font(.title2)
                    .frame(width: 36, alignment: .center)
                    .foregroundStyle(isFocused ? Color.black : Color.secondary)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(isFocused ? Color.black : Color.primary)
                        .lineLimit(1)
                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.callout)
                            .foregroundStyle(isFocused ? Color.black.opacity(0.65) : Color.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 12)

                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(
                        isFocused
                            ? Color.black
                            : (selected ? Color.primary : Color.secondary.opacity(0.45))
                    )
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 22)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focused($isFocused)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(isFocused ? Color.white : Color.primary.opacity(selected ? 0.12 : 0.06))
        )
        .accessibilityAddTraits(selected ? [.isSelected] : [])
        .accessibilityHint(singleSelect ? "Selects this device only" : "Toggles this device in Playing on")
    }
}

private extension PlayerDto {
    var platformLabel: String? {
        guard let platform, !platform.isEmpty else { return nil }
        switch platform.lowercased() {
        case "ios": return "iPhone or iPad"
        case "tvos": return "Apple TV"
        case "unknown": return nil
        default: return platform
        }
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
