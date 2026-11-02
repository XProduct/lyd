import Foundation
import AVFoundation
import Combine

/// Phase E: AVPlayer that pulls original files from `GET /api/v1/stream/songs/{id}`.
@MainActor
final class LocalStreamPlayer: ObservableObject {
    @Published private(set) var isPlaying = false
    @Published private(set) var positionMs: Int64 = 0
    @Published private(set) var durationMs: Int64 = 0
    @Published private(set) var currentSongId: String?
    @Published var volume: Float = 1.0 {
        didSet { player?.volume = volume }
    }

    private var player: AVPlayer?
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var statusObserver: NSKeyValueObservation?
    private var pendingStartMs: Int64 = 0
    private var pendingAutoplay = true
    private var sessionArmed = false

    var onFinished: (() -> Void)?

    /// Non-blocking: category + activate run off the main thread (avoids UI hitch).
    func configureAudioSession() {
        armAudioSession(active: true)
    }

    func play(url: URL, songId: String, startAtMs: Int64, autoplay: Bool = true) {
        armAudioSession(active: true)

        pendingStartMs = max(0, startAtMs)
        pendingAutoplay = autoplay
        currentSongId = songId
        positionMs = pendingStartMs
        durationMs = 0
        isPlaying = false

        // Prefer approximate timing — precise duration stalls LAN stream open.
        let asset = AVURLAsset(
            url: url,
            options: [AVURLAssetPreferPreciseDurationAndTimingKey: false]
        )
        let item = AVPlayerItem(asset: asset)
        // Small forward buffer; don't wait for a long warm-up before first frames.
        item.preferredForwardBufferDuration = 1.0

        let av = ensurePlayer()
        av.volume = volume
        av.automaticallyWaitsToMinimizeStalling = false

        detachItemObservers()
        av.replaceCurrentItem(with: item)
        attachItemObservers(item: item, player: av)
    }

    func playPause() {
        guard let player else { return }
        if player.rate > 0.01 {
            player.pause()
            isPlaying = false
        } else {
            armAudioSession(active: true)
            player.play()
            isPlaying = true
        }
    }

    func resume() {
        guard let player else { return }
        armAudioSession(active: true)
        player.play()
        isPlaying = true
    }

    func pause() {
        player?.pause()
        isPlaying = false
    }

    func seek(positionMs: Int64) async {
        guard let player else { return }
        let t = CMTime(value: max(0, positionMs), timescale: 1000)
        // Generous tolerance = faster seeks on network streams.
        await player.seek(to: t, toleranceBefore: .positiveInfinity, toleranceAfter: .positiveInfinity)
        self.positionMs = max(0, positionMs)
    }

    func stop() {
        detachItemObservers()
        if let timeObserver, let player {
            player.removeTimeObserver(timeObserver)
        }
        timeObserver = nil
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        isPlaying = false
        positionMs = 0
        durationMs = 0
        currentSongId = nil
        pendingStartMs = 0
        pendingAutoplay = true
        armAudioSession(active: false)
    }

    // MARK: - Audio session (background queue)

    private static let audioSessionQueue = DispatchQueue(
        label: "com.xproduct.lyd.audio-session",
        qos: .userInitiated
    )

    private func armAudioSession(active: Bool) {
        #if os(iOS) || os(tvOS)
        if active, sessionArmed { return }
        if !active, !sessionArmed {
            // Still enqueue deactivate in case a prior activate is in flight.
        }
        sessionArmed = active
        Self.audioSessionQueue.async {
            let session = AVAudioSession.sharedInstance()
            do {
                if active {
                    try session.setCategory(.playback, mode: .default)
                    try session.setActive(true)
                } else {
                    try session.setActive(false, options: [.notifyOthersOnDeactivation])
                }
            } catch {
                // Best-effort; playback may still work with the existing session.
            }
        }
        #endif
    }

    // MARK: - Player plumbing

    private func ensurePlayer() -> AVPlayer {
        if let player { return player }
        let av = AVPlayer()
        av.automaticallyWaitsToMinimizeStalling = false
        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        timeObserver = av.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            Task { @MainActor in
                guard let self else { return }
                if time.isNumeric {
                    self.positionMs = Int64(time.seconds * 1000)
                }
                self.isPlaying = (self.player?.rate ?? 0) > 0.01
            }
        }
        player = av
        return av
    }

    private func attachItemObservers(item: AVPlayerItem, player av: AVPlayer) {
        let startMs = pendingStartMs
        let shouldPlay = pendingAutoplay

        statusObserver = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            Task { @MainActor in
                guard let self, self.player === av, av.currentItem === item else { return }
                guard item.status == .readyToPlay else { return }

                let duration = item.duration
                if duration.isNumeric && !duration.seconds.isNaN {
                    self.durationMs = Int64(duration.seconds * 1000)
                }

                if startMs > 0 {
                    let t = CMTime(value: startMs, timescale: 1000)
                    await av.seek(
                        to: t,
                        toleranceBefore: .positiveInfinity,
                        toleranceAfter: .positiveInfinity
                    )
                    self.positionMs = startMs
                }

                if shouldPlay {
                    av.play()
                    self.isPlaying = true
                } else {
                    av.pause()
                    self.isPlaying = false
                }
            }
        }

        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.isPlaying = false
                self?.onFinished?()
            }
        }
    }

    private func detachItemObservers() {
        statusObserver?.invalidate()
        statusObserver = nil
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
        endObserver = nil
    }
}
