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

    var onFinished: (() -> Void)?

    func configureAudioSession() {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default)
        try? session.setActive(true)
        #endif
    }

    func play(url: URL, songId: String, startAtMs: Int64, autoplay: Bool = true) {
        configureAudioSession()
        tearDownPlayer(keepCallbacks: true)

        let item = AVPlayerItem(url: url)
        let av = AVPlayer(playerItem: item)
        av.volume = volume
        player = av
        currentSongId = songId
        isPlaying = false

        statusObserver = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            Task { @MainActor in
                guard let self else { return }
                if item.status == .readyToPlay {
                    let duration = item.duration
                    if duration.isNumeric && !duration.seconds.isNaN {
                        self.durationMs = Int64(duration.seconds * 1000)
                    }
                    if startAtMs > 0 {
                        let t = CMTime(value: startAtMs, timescale: 1000)
                        await av.seek(to: t)
                        self.positionMs = max(0, startAtMs)
                    }
                    if autoplay {
                        av.play()
                        self.isPlaying = true
                    } else {
                        av.pause()
                        self.isPlaying = false
                    }
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

        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        timeObserver = av.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            Task { @MainActor in
                guard let self else { return }
                if time.isNumeric {
                    self.positionMs = Int64(time.seconds * 1000)
                }
                self.isPlaying = av.rate > 0.01
            }
        }
    }

    func playPause() {
        guard let player else { return }
        if player.rate > 0.01 {
            player.pause()
            isPlaying = false
        } else {
            player.play()
            isPlaying = true
        }
    }

    func resume() {
        guard let player else { return }
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
        await player.seek(to: t)
        self.positionMs = max(0, positionMs)
    }

    func stop() {
        tearDownPlayer(keepCallbacks: false)
        isPlaying = false
        positionMs = 0
        durationMs = 0
        currentSongId = nil
    }

    private func tearDownPlayer(keepCallbacks: Bool) {
        if let timeObserver, let player {
            player.removeTimeObserver(timeObserver)
        }
        timeObserver = nil
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
        endObserver = nil
        statusObserver = nil
        player?.pause()
        player = nil
        if !keepCallbacks {
            onFinished = nil
        }
    }
}
