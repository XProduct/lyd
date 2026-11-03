import Foundation
import AVFoundation
import Combine

/// Phase E: AVPlayer that pulls original files from `GET /api/v1/stream/songs/{id}`.
@MainActor
final class LocalStreamPlayer: ObservableObject {
    /// Digital attenuator applied only on tvOS stream output. Full-res FLAC over AVPlayer
    /// is much hotter than typical Apple TV apps; keep Siri Remote / soundbar system volume.
    #if os(tvOS)
    private static let outputGain: Float = 0.15
    #else
    private static let outputGain: Float = 1.0
    #endif

    @Published private(set) var isPlaying = false
    @Published private(set) var positionMs: Int64 = 0
    @Published private(set) var durationMs: Int64 = 0
    @Published private(set) var currentSongId: String?
    /// User-facing level 0…1 (Device volume UI). Actual AVPlayer volume is `volume * outputGain`.
    @Published var volume: Float = 1.0 {
        didSet { applyOutputVolume() }
    }

    private var player: AVPlayer?
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var statusObserver: NSKeyValueObservation?
    private var pendingStartMs: Int64 = 0
    private var pendingAutoplay = true
    private var sessionArmed = false
    /// Once true for the current item, ready-to-play must not re-seek to a stale start
    /// (that was clobbering Phase F catch-up seeks and leaving iOS seconds behind).
    private var didApplyInitialStart = false

    /// Playhead safe to report to the host. Before the join seek lands, AVPlayer often
    /// samples ~0 — that must not rewind the desktop remote session clock.
    var heartbeatPositionMs: Int64 {
        if !didApplyInitialStart {
            return max(positionMs, pendingStartMs)
        }
        return positionMs
    }

    /// True after the initial start seek/play has been applied for the current item.
    var isReadyForHeartbeat: Bool { didApplyInitialStart }

    var onFinished: (() -> Void)?
    /// Fired once when the current item is ready and initial start/play has been applied.
    var onBecameReady: (() -> Void)?

    /// Non-blocking: category + activate run off the main thread (avoids UI hitch).
    func configureAudioSession() {
        armAudioSession(active: true)
    }

    func play(url: URL, songId: String, startAtMs: Int64, autoplay: Bool = true) {
        armAudioSession(active: true)

        pendingStartMs = max(0, startAtMs)
        pendingAutoplay = autoplay
        didApplyInitialStart = false
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
        // Deeper buffer + stall-wait: short buffer + no-wait was causing audible mid-track skips.
        item.preferredForwardBufferDuration = 4.0

        let av = ensurePlayer()
        applyOutputVolume(to: av)
        av.automaticallyWaitsToMinimizeStalling = true

        detachItemObservers()
        av.replaceCurrentItem(with: item)
        attachItemObservers(item: item, player: av)
    }

    private func applyOutputVolume(to av: AVPlayer? = nil) {
        let target = (av ?? player)
        target?.volume = min(max(volume, 0), 1) * Self.outputGain
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

    func seek(positionMs: Int64, precise: Bool = false) async {
        guard let player else { return }
        // Mark initial start consumed so a late ready-to-play cannot rewind to pendingStartMs.
        didApplyInitialStart = true
        pendingStartMs = max(0, positionMs)
        let t = CMTime(value: max(0, positionMs), timescale: 1000)
        if precise {
            // Phase F sync correction — tighter than transport scrub seeks.
            let slack = CMTime(value: 40, timescale: 1000)
            await player.seek(to: t, toleranceBefore: slack, toleranceAfter: slack)
        } else {
            // Generous tolerance = faster seeks on network streams.
            await player.seek(to: t, toleranceBefore: .positiveInfinity, toleranceAfter: .positiveInfinity)
        }
        self.positionMs = max(0, positionMs)
    }

    /// Force a playback rate (session keeps 1.0 after join — mid-track tweaks skip).
    /// No-ops while paused so a rate reset cannot accidentally resume.
    func setPlaybackRate(_ rate: Float) {
        guard let player else { return }
        let clamped = min(max(rate, 0.5), 1.5)
        if clamped <= 0.01 {
            player.pause()
            isPlaying = false
            return
        }
        guard isPlaying || player.rate > 0.01 else { return }
        if abs(player.rate - clamped) < 0.001 { return }
        armAudioSession(active: true)
        player.rate = clamped
        isPlaying = true
    }

    var playbackRate: Float { player?.rate ?? 0 }

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
        didApplyInitialStart = false
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
        if let player {
            // stop() removes the observer but keeps the AVPlayer — reattach on reuse or
            // the UI/heartbeats freeze on the join second while audio still plays.
            ensureTimeObserver(on: player)
            return player
        }
        let av = AVPlayer()
        av.automaticallyWaitsToMinimizeStalling = true
        ensureTimeObserver(on: av)
        player = av
        return av
    }

    private func ensureTimeObserver(on av: AVPlayer) {
        guard timeObserver == nil else { return }
        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        timeObserver = av.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            Task { @MainActor in
                guard let self else { return }
                // Ignore pre-seek samples — they read near 0 and poison host timekeeping.
                if self.didApplyInitialStart, time.isNumeric {
                    self.positionMs = Int64(time.seconds * 1000)
                }
                self.isPlaying = (self.player?.rate ?? 0) > 0.01
            }
        }
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

                // Only the first ready pass applies the join start — a Phase F catch-up
                // seek sets didApplyInitialStart so we must not rewind to stale startMs.
                if !self.didApplyInitialStart {
                    self.didApplyInitialStart = true
                    let applyStartMs = self.pendingStartMs > 0 ? self.pendingStartMs : startMs
                    if applyStartMs > 0 {
                        let t = CMTime(value: applyStartMs, timescale: 1000)
                        await av.seek(
                            to: t,
                            toleranceBefore: .positiveInfinity,
                            toleranceAfter: .positiveInfinity
                        )
                        self.positionMs = applyStartMs
                    }
                    if shouldPlay {
                        av.play()
                        self.isPlaying = true
                    } else {
                        av.pause()
                        self.isPlaying = false
                    }
                    self.onBecameReady?()
                } else if shouldPlay, !self.isPlaying {
                    av.play()
                    self.isPlaying = true
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
