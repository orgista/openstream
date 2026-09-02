@preconcurrency import AVFoundation
import Foundation

/// Coordinates bounded periodic progress writes for one player. The observer
/// uses a weak capture, so the player/session can still be released normally.
@MainActor
public final class ApplePlaybackProgressCoordinator {
    public let mediaIdentity: String

    private let store: ApplePlaybackStore
    private let saveInterval: Double
    private weak var player: AVPlayer?
    private var periodicTimeObserver: Any?

    public init(
        store: ApplePlaybackStore,
        mediaIdentity: String,
        saveInterval: Double = 15
    ) {
        self.store = store
        self.mediaIdentity = mediaIdentity
        self.saveInterval = max(1, saveInterval)
    }

    public func startObserving(_ player: AVPlayer) {
        stopObserving(saveCurrentProgress: false)
        self.player = player
        let interval = CMTime(seconds: saveInterval, preferredTimescale: 600)
        periodicTimeObserver = player.addPeriodicTimeObserver(
            forInterval: interval,
            queue: .main
        ) { [weak self, weak player] time in
            MainActor.assumeIsolated {
                guard let self, let player else { return }
                self.record(position: time.seconds, duration: player.currentItem?.duration.seconds ?? 0)
            }
        }
    }

    public func saveCurrentProgress() {
        guard let player else { return }
        record(
            position: player.currentTime().seconds,
            duration: player.currentItem?.duration.seconds ?? 0
        )
    }

    public func record(position: Double, duration: Double) {
        store.save(mediaID: mediaIdentity, position: position, duration: duration)
    }

    public func markComplete() {
        store.clear(mediaID: mediaIdentity)
    }

    public func stopObserving(saveCurrentProgress: Bool = true) {
        if saveCurrentProgress { self.saveCurrentProgress() }
        if let periodicTimeObserver, let player {
            player.removeTimeObserver(periodicTimeObserver)
        }
        periodicTimeObserver = nil
        player = nil
    }
}
