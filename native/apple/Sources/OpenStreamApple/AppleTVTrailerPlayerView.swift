#if os(tvOS)
import AVFoundation
import SwiftUI
import UIKit

/// Full-bleed native trailer preview for the Apple TV title page. tvOS has no
/// WebKit, so the YouTube embed the other platforms use cannot exist here; the
/// page resolves the trailer with `AppleYouTubeStreamResolver` and this layer
/// plays it with AVPlayer, filling the hero the way the backdrop does. Ends are
/// observed by the page through `AVPlayerItemDidPlayToEndTime`; the layer draws
/// no controls.
///
/// A resolved trailer arrives one of two ways. An HLS manifest plays directly.
/// Adaptive formats do not: YouTube hands back video-only and audio-only
/// streams, so they are stitched into an `AVMutableComposition` — one video
/// track and one audio track over the same time range — which AVPlayer plays
/// as a single item.
struct AppleTVTrailerPlayerView: UIViewRepresentable {
    let source: AppleYouTubeStreamResolver.Source
    var isMuted = true
    /// Called on the main actor when the trailer cannot play. The caller takes
    /// the layer away again; without it a dead player sits over the billboard
    /// as an opaque black rectangle until the hero rotates (owner, 2026-09-20:
    /// "Apple TV regressed ... it looks smaller and off", hero fully black).
    var onFailure: () -> Void = {}

    func makeUIView(context: Context) -> PlayerLayerView {
        let view = PlayerLayerView()
        view.onFailure = onFailure
        view.isMuted = isMuted
        view.load(source: source)
        return view
    }

    func updateUIView(_ uiView: PlayerLayerView, context: Context) {
        uiView.onFailure = onFailure
        uiView.isMuted = isMuted
        if uiView.currentSource != source { uiView.load(source: source) }
    }

    static func dismantleUIView(_ uiView: PlayerLayerView, coordinator: ()) {
        uiView.stop()
    }

    final class PlayerLayerView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }

        private var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
        private var player: AVPlayer?
        var isMuted = true { didSet { player?.isMuted = isMuted } }
        private var loadTask: Task<Void, Never>?
        /// Set by the representable before `load(source:)`.
        var onFailure: () -> Void = {}
        /// A source that already failed. Reported failure clears
        /// `currentSource`, and without this the next `updateUIView` would see
        /// a mismatch and start the same dead stream over again.
        private var failedSource: AppleYouTubeStreamResolver.Source?
        /// `AVURLAsset` does not retain its resource-loader delegate, so the
        /// loaders have to be held here for as long as the item plays.
        private var loaders: [AppleRangedAssetLoader] = []
        private var statusObservation: NSKeyValueObservation?
        private(set) var currentSource: AppleYouTubeStreamResolver.Source?

        func load(source: AppleYouTubeStreamResolver.Source) {
            guard source != failedSource else { return }
            stop()
            currentSource = source
            // Clear, not black: the billboard's artwork is behind this layer
            // and has to stay visible until there are video frames to cover it.
            backgroundColor = .clear

            switch source {
            case .hls(let url):
                start(item: AVPlayerItem(url: url))
            case .adaptive(let video, let audio):
                // Building the composition needs the two moov atoms, so it is
                // a network round trip. A trailer that never resolves simply
                // never fades in; the page treats silence as no trailer.
                loadTask = Task { [weak self] in
                    var composed: (AVPlayerItem, [AppleRangedAssetLoader])
                    do {
                        composed = try await Self.composedItem(video: video, audio: audio)
                    } catch {
                        // The streams are DASH-fragmented MP4, which AVPlayer
                        // plays but `AVMutableComposition` cannot cut tracks
                        // from (`AVFoundationErrorDomain -11849`). A hero
                        // preview is better silent than absent, so the video
                        // half plays on its own rather than nothing at all.
                        let ns = error as NSError
                        appleTrace("trailer composition unavailable (\(ns.domain) \(ns.code)); playing video only")
                        guard let (asset, loader) = AppleRangedAssetLoader.asset(
                            for: video, contentType: AVFileType.mp4.rawValue
                        ) else {
                            appleTraceFailure("trailer: could not build a video-only asset either")
                            await MainActor.run { self?.reportFailure() }
                            return
                        }
                        composed = (AVPlayerItem(asset: asset), [loader])
                    }
                    guard let self, !Task.isCancelled, self.currentSource == source else { return }
                    appleTrace("trailer composition ready, playing")
                    self.loaders = composed.1
                    self.start(item: composed.0)
                }
            }
        }

        private func start(item: AVPlayerItem) {
            guard ApplePlaybackSessionPolicy.prepareTrailerAudio() else {
                reportFailure()
                return
            }
            let player = AVPlayer(playerItem: item)
            player.audiovisualBackgroundPlaybackPolicy = .pauses
            player.isMuted = isMuted
            player.allowsExternalPlayback = false
            player.actionAtItemEnd = .pause
            player.preventsDisplaySleepDuringVideoPlayback = false
            playerLayer.player = player
            playerLayer.videoGravity = .resizeAspectFill
            player.play()
            self.player = player
            // A player that never becomes ready draws nothing, so the caller
            // has to hear about it and put the still back. This observation is
            // not DEBUG-only: the release build has the same dead layer.
            statusObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
                switch item.status {
                case .readyToPlay: appleTrace("trailer item ready")
                case .failed:
                    let ns = (item.error ?? NSError(domain: "none", code: 0)) as NSError
                    appleTraceFailure("trailer item failed: \(ns.domain) \(ns.code) \(ns.localizedDescription)")
                    Task { @MainActor in self?.reportFailure() }
                default: break
                }
            }
        }

        /// Tears the dead player down and tells the page once.
        private func reportFailure() {
            guard let source = currentSource else { return }
            stop()
            failedSource = source
            onFailure()
        }

        /// One item carrying both halves of an adaptive pair, plus the loaders
        /// that must stay alive for as long as it plays.
        static func composedItem(video: URL, audio: URL) async throws -> (AVPlayerItem, [AppleRangedAssetLoader]) {
            let composition = AVMutableComposition()
            // Both halves are served by a host that refuses unranged requests,
            // so neither can be opened as a plain `AVURLAsset`.
            guard let (videoAsset, videoLoader) = AppleRangedAssetLoader.asset(for: video, contentType: AVFileType.mp4.rawValue),
                  let (audioAsset, audioLoader) = AppleRangedAssetLoader.asset(for: audio, contentType: AVFileType.mp4.rawValue) else {
                throw AppleYouTubeStreamResolver.Failure.noHLS
            }

            async let videoTracks = videoAsset.loadTracks(withMediaType: .video)
            async let audioTracks = audioAsset.loadTracks(withMediaType: .audio)
            async let videoDuration = videoAsset.load(.duration)
            async let audioDuration = audioAsset.load(.duration)

            guard let videoTrack = try await videoTracks.first,
                  let audioTrack = try await audioTracks.first else {
                throw AppleYouTubeStreamResolver.Failure.noHLS
            }
            // The two streams are muxed separately and their durations differ
            // by a frame or so; inserting past the shorter one throws.
            let duration = min(try await videoDuration, try await audioDuration)
            let range = CMTimeRange(start: .zero, duration: duration)

            if let track = composition.addMutableTrack(
                withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid
            ) {
                try track.insertTimeRange(range, of: videoTrack, at: .zero)
            }
            if let track = composition.addMutableTrack(
                withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid
            ) {
                try track.insertTimeRange(range, of: audioTrack, at: .zero)
            }
            return (AVPlayerItem(asset: composition), [videoLoader, audioLoader])
        }

        func stop() {
            loadTask?.cancel()
            loadTask = nil
            statusObservation = nil
            player?.pause()
            playerLayer.player = nil
            player = nil
            loaders = []
            currentSource = nil
        }
    }
}
#endif
