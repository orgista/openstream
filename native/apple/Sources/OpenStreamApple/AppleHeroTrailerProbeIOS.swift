#if DEBUG && os(iOS)
import UIKit
import WebKit

/// `-OpenStreamHeroTrailerProbe YES`: the iPhone and iPad hero's trailer
/// around the crossfade, with the same metrics as the Mac's probe (N44, N46).
/// From the first `playing` until `-OpenStreamHeroTrailerProbeSeconds`
/// (default 4) after the cover starts to fade, every 16 ms it writes one
/// line, in WINDOW points: the window, its safe-area insets, the hero (the
/// frame the still fills), the still as SwiftUI draws it, the cover's copy of
/// it, the web view, the trailer's measured picture band, the cover's
/// on-screen opacity, the part of the still and of the video the hero shows
/// (`crop=`, as fractions of each) and the video's width over the still's
/// (`zoom=`). It writes `N-before-still.png` (the window's hero without the
/// trailer: the SwiftUI still with its fade and copy), `N-before-art.png` (the
/// cover), and `N-before-trailer.png` / `N-after-trailer.png` (the hero's part
/// of the web view at the fade and 0.7 s after), all at the hero's size, 1x.
/// Everything goes to `Library/Caches/hero-probe/` in the app's container.
@MainActor
final class AppleHeroTrailerProbeIOS {
    weak var container: AppleYouTubeAutoPreview.PlayerContainer?
    private let directory: URL
    private var started: Date?
    private var fadeAt: Date?
    private var tick = 0
    private var timer: Timer?
    private var lines = [String]()
    private let number: Int
    private static var count = 0

    private init(directory: URL) {
        self.directory = directory
        Self.count += 1
        number = Self.count
    }

    static func fromDefaults() -> AppleHeroTrailerProbeIOS? {
        guard UserDefaults.standard.bool(forKey: "OpenStreamHeroTrailerProbe"),
              let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return nil }
        let directory = caches.appending(path: "hero-probe", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return AppleHeroTrailerProbeIOS(directory: directory)
    }

    /// `-OpenStreamDebugOrientation portrait|landscape` turns an iPad's
    /// interface that way, for a headless sim that has no rotate command.
    static func applyDebugOrientation() {
        let mask: UIInterfaceOrientationMask
        switch UserDefaults.standard.string(forKey: "OpenStreamDebugOrientation") {
        case "portrait": mask = .portrait
        case "landscape": mask = .landscapeRight
        default: return
        }
        for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask)) { error in
                appleTrace("debug orientation failed: \(error.localizedDescription)")
            }
        }
    }

    func begin() {
        guard started == nil else { return }
        started = Date()
        let screen = container?.window?.windowScene?.screen
        lines.append("SCREEN bounds=\(NSCoder.string(for: screen?.bounds ?? .zero)) scale=\(screen?.scale ?? 0) idiom=\(UIDevice.current.userInterfaceIdiom.rawValue) orientation=\(container?.window?.windowScene?.effectiveGeometry.interfaceOrientation.rawValue ?? 0)")
        writeStill(named: "\(number)-before-still.png")
        writeCover(named: "\(number)-before-art.png")
        // The web view under the cover from its first frame (`-OpenStreamHeroTrailerProbeFilm YES`),
        // every half second: when YouTube's title strip and link come and go.
        if UserDefaults.standard.bool(forKey: "OpenStreamHeroTrailerProbeFilm") {
            for step in 1...20 {
                DispatchQueue.main.asyncAfter(deadline: .now() + Double(step) * 0.5) { [weak self] in
                    guard let self else { return }
                    self.writeTrailer(named: "\(self.number)-film-\(String(format: "%03d", step * 5))ds.png")
                }
            }
        }
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.sample() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func markFade() {
        guard fadeAt == nil, started != nil else { return }
        sample()
        fadeAt = Date()
        lines.append("FADE at \(milliseconds(since: started))ms")
        writeTrailer(named: "\(number)-before-trailer.png")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self] in
            guard let self else { return }
            self.writeTrailer(named: "\(self.number)-after-trailer.png")
        }
        // How long YouTube's own title strip and link stay over the video.
        for delay in [1.5, 2.5, 3.5, 5.0, 7.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self else { return }
                self.writeTrailer(named: "\(self.number)-trailer-\(Int(delay * 10))ds.png")
            }
        }
    }

    private func milliseconds(since date: Date?) -> Int {
        Int(Date().timeIntervalSince(date ?? Date()) * 1000)
    }

    private var seconds: TimeInterval {
        let value = UserDefaults.standard.double(forKey: "OpenStreamHeroTrailerProbeSeconds")
        return value > 0 ? value : 4
    }

    private func sample() {
        guard let container, container.window != nil, let started else { return finish() }
        let elapsed = Date().timeIntervalSince(started)
        if let fadeAt, Date().timeIntervalSince(fadeAt) > seconds { return finish() }
        if fadeAt == nil, elapsed > 25 { return finish() }
        tick += 1
        lines.append(Self.line(container, tick: tick, elapsed: elapsed, sinceFade: fadeAt.map { milliseconds(since: $0) }))
    }

    /// One tick's geometry, in window points.
    static func line(_ container: AppleYouTubeAutoPreview.PlayerContainer, tick: Int, elapsed: TimeInterval,
                     sinceFade: Int?) -> String {
        func text(_ r: CGRect?) -> String {
            guard let r else { return "none" }
            return String(format: "%.1f,%.1f %.1fx%.1f", r.minX, r.minY, r.width, r.height)
        }
        func fraction(_ r: CGRect?) -> String {
            guard let r else { return "none" }
            return String(format: "%.3f,%.3f %.3fx%.3f", r.minX, r.minY, r.width, r.height)
        }
        let probe = container.probeGeometry
        let insets = container.window?.safeAreaInsets ?? .zero
        let offset = probe.still.map { still in
            probe.coverArt.map { String(format: "%.1f,%.1f", $0.minX - still.minX, $0.minY - still.minY) } ?? "none"
        } ?? "none"
        return String(
            format: "tick=%04d t=%dms sinceFade=%@ cover=%.2f urlArt=%@ win=%@ safe=%.0f,%.0f,%.0f,%.0f hero=%@ still=%@ coverArt=%@ web=%@ pic=%@ crop.still=%@ crop.pic=%@ zoom=%@ coverVsStill=%@",
            tick, Int(elapsed * 1000), sinceFade.map(String.init) ?? "-", probe.coverOpacity,
            probe.urlArtworkShows ? "shown" : "hidden",
            text(container.window?.bounds), insets.top, insets.left, insets.bottom, insets.right,
            text(probe.hero), text(probe.still), text(probe.coverArt), text(probe.web), text(probe.picture),
            fraction(probe.still.map { AppleMacHeroCrop.visibleFraction(of: $0, through: probe.hero) }),
            fraction(AppleMacHeroCrop.visibleFraction(of: probe.picture, through: probe.hero)),
            probe.still.map { String(format: "%.3f", probe.picture.width / max($0.width, 1)) } ?? "none",
            offset)
    }

    private func renderer(size: CGSize) -> UIGraphicsImageRenderer {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format)
    }

    /// The window's hero with the trailer's container hidden: the SwiftUI
    /// still under it, with the hero's fade and copy.
    private func writeStill(named name: String) {
        guard let container, let window = container.window else { return }
        let hero = container.probeGeometry.hero
        container.isHidden = true
        defer { container.isHidden = false }
        let image = renderer(size: hero.size).image { _ in
            window.drawHierarchy(in: window.bounds.offsetBy(dx: -hero.minX, dy: -hero.minY), afterScreenUpdates: true)
        }
        try? image.pngData()?.write(to: directory.appending(path: name))
    }

    /// The cover, as it stands over the still until the video shows.
    private func writeCover(named name: String) {
        guard let cover = container?.probeCover else { return }
        let image = renderer(size: cover.bounds.size).image { _ in
            cover.drawHierarchy(in: cover.bounds, afterScreenUpdates: true)
        }
        try? image.pngData()?.write(to: directory.appending(path: name))
    }

    /// The hero's part of the web view, at the hero's size.
    private func writeTrailer(named name: String) {
        guard let container, let cover = container.probeCover else { return }
        let webView = container.webView
        // In the web view's own (untransformed) points.
        let visible = cover.convert(cover.bounds, to: webView)
        let size = cover.bounds.size
        let configuration = WKSnapshotConfiguration()
        configuration.afterScreenUpdates = false
        let directory = directory
        webView.takeSnapshot(with: configuration) { [weak self] image, _ in
            guard let self, let image, let cg = image.cgImage, webView.bounds.width > 0 else { return }
            let factor = CGFloat(cg.width) / webView.bounds.width
            let crop = CGRect(x: visible.minX * factor, y: visible.minY * factor,
                              width: visible.width * factor, height: visible.height * factor)
            // Draws the whole snapshot shifted, so a hero that reaches past
            // the web view keeps its size and shows black there.
            let output = self.renderer(size: size).image { context in
                UIColor.black.setFill()
                context.fill(CGRect(origin: .zero, size: size))
                let sx = size.width / max(crop.width, 1), sy = size.height / max(crop.height, 1)
                UIImage(cgImage: cg).draw(in: CGRect(x: -crop.minX * sx, y: -crop.minY * sy,
                                                     width: CGFloat(cg.width) * sx, height: CGFloat(cg.height) * sy))
            }
            try? output.pngData()?.write(to: directory.appending(path: name))
        }
    }

    private func finish() {
        timer?.invalidate()
        timer = nil
        guard !lines.isEmpty else { return }
        try? (lines.joined(separator: "\n") + "\n").write(to: directory.appending(path: "probe-\(number).log"),
                                                          atomically: true, encoding: .utf8)
        lines.removeAll()
    }
}
#endif

#if DEBUG && os(iOS)
/// What the probe reads off the trailer's container each tick, in window points.
struct AppleHeroTrailerProbeGeometry {
    var hero: CGRect
    /// The still as the SwiftUI hero draws it under the container, when known.
    var still: CGRect?
    /// The cover's copy of the still, as UIKit lays it out.
    var coverArt: CGRect?
    var urlArtworkShows: Bool
    var web: CGRect
    var picture: CGRect
    var coverOpacity: Float
}
#endif
