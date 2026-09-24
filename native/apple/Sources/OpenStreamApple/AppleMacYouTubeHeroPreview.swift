#if os(macOS)
import AppKit
import SwiftUI
import WebKit

/// The Mac hero's inline trailer: the same muted YouTube preview page the
/// iPhone and iPad draw (`AppleYouTubePreviewHTML`), in a web view that never
/// takes a click, under a cover of the hero's own still that fades away only
/// once the video has frames — so the hero shows its art, never a black
/// iframe, until the trailer is really playing.
///
/// The web view is laid out over the frame it is offered and cropped to it
/// (`AppleTrailerPreviewLayout`), and reports only that frame to SwiftUI: a
/// window resize moves it in place and never reloads the page.
@MainActor
struct AppleMacYouTubeHeroPreview: NSViewRepresentable {
    let url: URL
    /// The hero's decoded still, shown until the first frame.
    var artworkImage: CGImage?
    let isPlaying: Bool
    let isMuted: Bool
    let onStateChange: (String, Bool, Int?) -> Void

    final class Coordinator: NSObject, WKScriptMessageHandler {
        var loadedURL: URL?
        var lastMuted = true
        var lastPlaying = true
        /// What the loaded document was told to start with. A change that
        /// arrives before the page has loaded is evaluated against the old
        /// document and lost, so `ready` sends whatever differs again.
        var documentPlaying = true
        var documentMuted = true
        var onStateChange: ((String, Bool, Int?) -> Void)?
        weak var container: PlayerContainer?
        private var revealGeneration = 0

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "trailerState",
                  let payload = message.body as? [String: Any],
                  let state = payload["state"] as? String else { return }
            if state == "ready" {
                // The title page starts its trailer a moment after the view
                // is made; without this the page stayed on `ready` with the
                // still up (Mac trace, 2026-09-24).
                if lastPlaying != documentPlaying {
                    documentPlaying = lastPlaying
                    container?.webView.evaluateJavaScript(
                        "window.setTrailerPlaying(\(lastPlaying ? "true" : "false"));", completionHandler: nil)
                }
                if lastMuted != documentMuted {
                    documentMuted = lastMuted
                    container?.webView.evaluateJavaScript(
                        AppleTrailerSoundBridge.javascriptCommand(isMuted: lastMuted), completionHandler: nil)
                    appleTrace("mac hero trailer state=ready muted=\(lastMuted) error=none (re-sent)")
                    onStateChange?(state, lastMuted, nil)
                    return
                }
            }
            let muted = payload["muted"] as? Bool ?? lastMuted
            lastMuted = muted
            let errorCode = payload["errorCode"] as? Int
            appleTrace("mac hero trailer state=\(state) muted=\(muted) error=\(errorCode.map(String.init) ?? "none")")
            switch state {
            case "revealed":
                reveal()
            case "ended":
                // The page pauses only once the art has crossfaded back up,
                // so the fade runs over live frames.
                conceal(animated: true) { [weak self] in
                    self?.container?.webView.evaluateJavaScript("window.completeTrailerEnd();", completionHandler: nil)
                }
            case "error":
                conceal(animated: true)
            case "paused", "concealed":
                conceal()
            default:
                break
            }
            onStateChange?(state, muted, errorCode)
        }

        func conceal(animated: Bool = false, completion: (@MainActor @Sendable () -> Void)? = nil) {
            revealGeneration += 1
            container?.setPreviewVisible(false, animated: animated, completion: completion)
        }

        /// Measures the picture band first, so a letterboxed trailer is
        /// cropped to its picture before the cover fades.
        private func reveal() {
            guard let container else { return }
            revealGeneration += 1
            let generation = revealGeneration
            measure(container, generation: generation, remaining: 3) { container in
                container.setPreviewVisible(true)
            }
        }

        private func measure(_ container: PlayerContainer, generation: Int, remaining: Int,
                             then: ((PlayerContainer) -> Void)? = nil) {
            let configuration = WKSnapshotConfiguration()
            configuration.afterScreenUpdates = false
            configuration.snapshotWidth = NSNumber(value: 256)
            container.webView.takeSnapshot(with: configuration) { [weak self, weak container] image, _ in
                guard let self, let container, self.revealGeneration == generation else { return }
                let window = image?.cgImage(forProposedRect: nil, context: nil, hints: nil)
                    .flatMap(AppleTrailerPreviewLayout.pictureWindow(in:))
                if let window {
                    container.pictureWindow = window
                    container.hasMeasuredPicture = true
                }
                then?(container)
                // A fade-in or a title card measures as nothing; look again
                // while it plays so a wide trailer settles into its band.
                guard !container.hasMeasuredPicture, remaining > 0 else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self, weak container] in
                    guard let self, let container else { return }
                    self.measure(container, generation: generation, remaining: remaining - 1)
                }
            }
        }
    }

    final class PlayerContainer: NSView {
        let webView: WKWebView
        private let cover = CoverView()
        var pictureWindow: ClosedRange<CGFloat> = 0...1 { didSet { needsLayout = true } }
        var hasMeasuredPicture = false
        private var previewVisible = false

        init(messageHandler: WKScriptMessageHandler) {
            let configuration = WKWebViewConfiguration()
            configuration.mediaTypesRequiringUserActionForPlayback = []
            configuration.websiteDataStore = .nonPersistent()
            configuration.userContentController.addUserScript(WKUserScript(
                source: ApplePlaybackSessionPolicy.trailer.webMediaSessionSuppressionScript,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: false
            ))
            configuration.userContentController.add(messageHandler, name: "trailerState")
            webView = WKWebView(frame: .zero, configuration: configuration)
            super.init(frame: .zero)
            wantsLayer = true
            layer?.masksToBounds = true
            webView.setAccessibilityElement(false)
            addSubview(webView)
            addSubview(cover)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { nil }

        override var isFlipped: Bool { true }

        /// The hero's own buttons, hover and swipe handle every event; the
        /// iframe never gets a click it could act on.
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func layout() {
            super.layout()
            webView.frame = AppleTrailerPreviewLayout.playerFrame(
                in: bounds.size, isLandscape: true, pictureWindow: pictureWindow
            )
            cover.frame = bounds
        }

        func updateStill(_ image: CGImage?) {
            cover.image = image
        }

        /// Reveal cross-fades the cover away over the live frames. Hiding
        /// crossfades it back when `animated` (a trailer that ends or fails)
        /// and puts it back at once otherwise; `completion` runs once the
        /// art is fully up. Reduce Motion swaps instantly both ways.
        func setPreviewVisible(_ visible: Bool, animated: Bool = true,
                               completion: (@MainActor @Sendable () -> Void)? = nil) {
            let wasVisible = previewVisible
            previewVisible = visible
            if visible != wasVisible { appleTrace("mac hero trailer cover \(visible ? "fading out" : "up")") }
            let duration = AppleTrailerArtFirstPolicy.crossfadeDuration(
                reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
            let animates = visible != wasVisible && animated && duration > 0
            NSAnimationContext.runAnimationGroup { context in
                context.duration = animates ? duration : 0
                context.allowsImplicitAnimation = animates
                cover.animator().alphaValue = visible ? 0 : 1
            } completionHandler: {
                // AppKit runs it on the main thread.
                MainActor.assumeIsolated { completion?() }
            }
        }
    }

    /// The still, drawn aspect-fill as the hero draws it.
    final class CoverView: NSView {
        var image: CGImage? {
            didSet { if image !== oldValue { needsDisplay = true } }
        }

        override init(frame: NSRect) {
            super.init(frame: frame)
            wantsLayer = true
            layerContentsRedrawPolicy = .onSetNeedsDisplay
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { nil }

        override var wantsUpdateLayer: Bool { true }

        override func updateLayer() {
            layer?.contents = image
            layer?.contentsGravity = .resizeAspectFill
            layer?.backgroundColor = image == nil ? NSColor.black.cgColor : nil
        }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> PlayerContainer {
        let coordinator = context.coordinator
        coordinator.onStateChange = onStateChange
        coordinator.lastMuted = isMuted
        coordinator.lastPlaying = isPlaying
        let container = PlayerContainer(messageHandler: coordinator)
        coordinator.container = container
        container.updateStill(artworkImage)
        load(url, in: container, context: context)
        return container
    }

    func updateNSView(_ view: PlayerContainer, context: Context) {
        let coordinator = context.coordinator
        coordinator.onStateChange = onStateChange
        view.updateStill(artworkImage)
        if coordinator.loadedURL != url {
            view.pictureWindow = 0...1
            view.hasMeasuredPicture = false
            coordinator.conceal()
            load(url, in: view, context: context)
        }
        if coordinator.lastPlaying != isPlaying {
            coordinator.lastPlaying = isPlaying
            if !isPlaying { coordinator.conceal() }
            view.webView.evaluateJavaScript("window.setTrailerPlaying(\(isPlaying ? "true" : "false"));", completionHandler: nil)
        }
        if coordinator.lastMuted != isMuted {
            coordinator.lastMuted = isMuted
            view.webView.evaluateJavaScript(AppleTrailerSoundBridge.javascriptCommand(isMuted: isMuted), completionHandler: nil)
        }
    }

    static func dismantleNSView(_ view: PlayerContainer, coordinator: Coordinator) {
        coordinator.conceal()
        view.webView.evaluateJavaScript("window.setTrailerPlaying(false);", completionHandler: nil)
        view.webView.stopLoading()
        view.webView.loadHTMLString("", baseURL: nil)
        view.webView.configuration.userContentController.removeScriptMessageHandler(forName: "trailerState")
        coordinator.loadedURL = nil
        coordinator.onStateChange = nil
    }

    private func load(_ url: URL, in view: PlayerContainer, context: Context) {
        context.coordinator.loadedURL = url
        context.coordinator.documentPlaying = isPlaying
        context.coordinator.documentMuted = isMuted
        appleTrace("mac hero trailer load playing=\(isPlaying) muted=\(isMuted)")
        let html = AppleYouTubePreviewHTML.document(
            embedURL: url, startsPlaying: isPlaying, isLandscape: true, startsMuted: isMuted, allowsSound: true
        )
        view.webView.loadHTMLString(html, baseURL: URL(string: "https://openstream.app"))
    }
}
#endif
