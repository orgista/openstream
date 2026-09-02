import AVFoundation
import Foundation

/// Shared AVPlayer setup used by every platform host. Spatial rendering and
/// external playback remain system-controlled; OpenStream only declares the
/// layouts it can supply and leaves AirPods/AirPlay choices to the user.
@MainActor
public final class ApplePlayerSession {
    public let playerItem: AVPlayerItem
    public let player: AVPlayer
    public let progressCoordinator: ApplePlaybackProgressCoordinator
    public let mediaIdentity: String

    public init(
        url: URL,
        resumeAt seconds: Double = 0,
        mediaID: String? = nil,
        progressStore: ApplePlaybackStore? = nil,
        requestHeaders: [String: String] = [:]
    ) {
        let store = progressStore ?? ApplePlaybackStore()
        let identity = mediaID.flatMap(ApplePlaybackIdentity.storageKey(for:))
            ?? ApplePlaybackIdentity.storageKey(for: url)
        mediaIdentity = identity

        // IPTV providers often 403 unless the playlist's User-Agent/Referer are
        // sent on the media request; carry them onto the asset when present.
        let item: AVPlayerItem
        if requestHeaders.isEmpty {
            item = AVPlayerItem(url: url)
        } else {
            let asset = AVURLAsset(url: url, options: ["AVURLAssetHTTPHeaderFieldsKey": requestHeaders])
            item = AVPlayerItem(asset: asset)
        }
        item.allowedAudioSpatializationFormats = .monoStereoAndMultichannel
        playerItem = item

        let player = AVPlayer(playerItem: item)
        #if !os(visionOS)
        player.allowsExternalPlayback = true
        #endif
        #if os(iOS) || os(tvOS)
        player.usesExternalPlaybackWhileExternalScreenIsActive = true
        #endif
        self.player = player

        let savedPosition = store.progress(for: identity)?.resumePosition ?? 0
        let requestedPosition = seconds.isFinite && seconds > 0 ? seconds : savedPosition
        if requestedPosition > 0 {
            player.seek(to: CMTime(seconds: requestedPosition, preferredTimescale: 600))
        }

        let coordinator = ApplePlaybackProgressCoordinator(
            store: store,
            mediaIdentity: identity
        )
        progressCoordinator = coordinator
        coordinator.startObserving(player)
    }

    /// Consumes the result of `ApplePlaybackPreparer` directly. Gateway
    /// preparation returns a scoped bearer URL, never global auth headers.
    public convenience init(
        preparedPlayback: ApplePreparedPlayback,
        resumeAt seconds: Double = 0,
        mediaID: String? = nil,
        progressStore: ApplePlaybackStore? = nil
    ) {
        self.init(
            url: preparedPlayback.url,
            resumeAt: seconds,
            mediaID: mediaID,
            progressStore: progressStore
        )
    }

    public func savePlaybackProgress() {
        progressCoordinator.saveCurrentProgress()
    }

    public func stop(saveProgress: Bool = true) {
        progressCoordinator.stopObserving(saveCurrentProgress: saveProgress)
        player.pause()
    }
}
