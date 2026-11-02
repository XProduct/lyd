import SwiftUI

struct NowPlayingView: View {
    @EnvironmentObject private var session: LydSession
    @State private var scrubPosition: Double = 0
    @State private var isScrubbing = false
    @State private var volumeDraft: Double = 0.5

    private var song: SongDto? { session.playback.currentSong }
    private var duration: Double { Double(max(session.playback.durationMs, 0)) }
    private var position: Double {
        isScrubbing ? scrubPosition : Double(max(session.playback.positionMs, 0))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                CoverImage(url: coverURL)
                    .frame(maxWidth: 360)
                    .aspectRatio(1, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .padding(.top, 4)

                VStack(spacing: 6) {
                    Text(song?.displayTitle ?? "Nothing playing")
                        .font(.title2.bold())
                        .foregroundStyle(Color.primary)
                        .multilineTextAlignment(.center)
                    Text(song?.displayArtist ?? session.selectedDisplayName)
                        .font(.title3)
                        .foregroundStyle(Color.secondary)
                        .multilineTextAlignment(.center)
                    if let album = song?.album?.nilIfEmpty {
                        Text(album)
                            .font(.subheadline)
                            .foregroundStyle(Color.secondary)
                            .multilineTextAlignment(.center)
                    }
                    if let tech = song?.technicalSummary {
                        Text(tech)
                            .font(.footnote.monospacedDigit())
                            .foregroundStyle(Color.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.top, 2)
                    }
                }

                VStack(spacing: 8) {
                    #if os(tvOS)
                    HStack {
                        Text(format(ms: Int64(position)))
                        Spacer()
                        Text(format(ms: Int64(duration)))
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    #else
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
                    #endif
                }
                .padding(.horizontal)

                HStack(spacing: 28) {
                    Button {
                        Task { await session.previous() }
                    } label: {
                        Image(systemName: "backward.fill")
                            .font(.title)
                            .foregroundStyle(Color.primary)
                    }

                    Button {
                        Task { await session.playPause() }
                    } label: {
                        Image(systemName: session.playback.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 64))
                            .foregroundStyle(LydTheme.primary)
                    }

                    Button {
                        Task { await session.next() }
                    } label: {
                        Image(systemName: "forward.fill")
                            .font(.title)
                            .foregroundStyle(Color.primary)
                    }
                }
                .buttonStyle(.plain)

                HStack(spacing: 20) {
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

                    #if os(tvOS)
                    HStack {
                        Button {
                            Task { await session.setVolume(max(0, session.playback.volume - 0.05)) }
                        } label: {
                            Image(systemName: "speaker.wave.1.fill")
                        }
                        Text("\(Int((session.playback.volume * 100).rounded()))%")
                            .monospacedDigit()
                        Button {
                            Task { await session.setVolume(min(1, session.playback.volume + 0.05)) }
                        } label: {
                            Image(systemName: "speaker.wave.3.fill")
                        }
                    }
                    #endif
                }

                #if os(iOS)
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
                #endif

                if let status = session.statusMessage {
                    Text(status)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .padding(.horizontal)
                }

                Text("Controlling \(session.selectedDisplayName) · \(session.selectedEndpoint)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
            .padding()
            // Clear the tab bar so shuffle / volume stay reachable.
            .padding(.bottom, 48)
        }
        .scrollBounceBehavior(.basedOnSize)
        .navigationTitle("Now Playing")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.visible, for: .navigationBar)
        #endif
        .onAppear { volumeDraft = session.playback.volume }
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

private extension LydSession {
    func clientCoverFallback(albumId: String) -> URL? {
        // Relative cover path used by Phase A when album list is incomplete.
        coverURL(for: AlbumDto(id: albumId, title: nil, artist: nil, songIds: nil, coverUrl: "/api/v1/albums/\(albumId)/cover"))
    }
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

