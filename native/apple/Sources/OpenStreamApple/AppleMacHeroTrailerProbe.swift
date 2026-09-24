#if DEBUG && os(macOS)
import AppKit
import WebKit

/// `-OpenStreamHeroTrailerProbe </absolute/dir>`: a frame sequence of the Mac
/// hero's trailer around the crossfade, for proving it never changes size
/// once it can be seen (N31). From the first `playing` until 4 s after the
/// cover starts to fade, every 100 ms it writes one line — the web view's
/// frame, the cover's on-screen opacity, and the player page's own size and
/// `<video>` box — plus a PNG of the part of the web view the hero shows.
/// `-OpenStreamHeroTrailerProbeStill <seconds>` also writes `still.png`, the
/// hero's part of the web view at full resolution that long after `playing`,
/// so two builds can be compared on the same trailer frame.
@MainActor
final class AppleMacHeroTrailerProbe {
    weak var container: AppleMacYouTubeHeroPreview.PlayerContainer?
    private let directory: URL
    private var started: Date?
    private var fadeAt: Date?
    private var tick = 0
    private var timer: Timer?
    private var lines = [String]()

    private init(directory: URL) {
        self.directory = directory
    }

    static func fromArguments(_ arguments: [String] = ProcessInfo.processInfo.arguments) -> AppleMacHeroTrailerProbe? {
        guard let marker = arguments.firstIndex(of: "-OpenStreamHeroTrailerProbe"),
              arguments.indices.contains(marker + 1), arguments[marker + 1].hasPrefix("/") else { return nil }
        let directory = URL(fileURLWithPath: arguments[marker + 1], isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return AppleMacHeroTrailerProbe(directory: directory)
    }

    func begin() {
        guard started == nil else { return }
        started = Date()
        let still = UserDefaults.standard.double(forKey: "OpenStreamHeroTrailerProbeStill")
        if still > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + still) { [weak self] in self?.writeStill() }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.sample() }
        }
    }

    func markFade() {
        guard fadeAt == nil else { return }
        fadeAt = Date()
        lines.append("FADE at \(milliseconds(since: started))ms")
    }

    private func milliseconds(since date: Date?) -> Int {
        Int(Date().timeIntervalSince(date ?? Date()) * 1000)
    }

    private func sample() {
        guard let container, let started else { return finish() }
        let elapsed = Date().timeIntervalSince(started)
        if let fadeAt, Date().timeIntervalSince(fadeAt) > 4 { return finish() }
        if fadeAt == nil, elapsed > 15 { return finish() }
        tick += 1
        let web = container.webView.frame
        let scale = CGFloat(container.layoutScale)
        let geometry = container.geometry()
        // The video's box in the hero, in points, if the page were drawn at
        // the web view's current frame.
        let onScreen = geometry?.video.map {
            CGRect(x: web.minX + $0.minX / scale, y: web.minY + $0.minY / scale,
                   width: $0.width / scale, height: $0.height / scale)
        }
        let relative = fadeAt.map { "\(milliseconds(since: $0))" } ?? "-"
        let line = String(format: "tick=%03d t=%dms sinceFade=%@ cover=%.2f web=%@ page=%@ videoInHero=%@",
                          tick, Int(elapsed * 1000), relative, container.coverOpacity,
                          NSStringFromRect(web), geometry?.description ?? "none",
                          onScreen.map(NSStringFromRect) ?? "none")
        lines.append(line)
        appleTrace("probe \(line)")
        let name = String(format: "%03d.png", tick)
        let visible = container.bounds.offsetBy(dx: -web.minX, dy: -web.minY)
        let configuration = WKSnapshotConfiguration()
        configuration.afterScreenUpdates = false
        configuration.snapshotWidth = NSNumber(value: 480)
        container.webView.takeSnapshot(with: configuration) { [directory] image, _ in
            guard let image, let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil), web.width > 0 else { return }
            let factor = CGFloat(cg.width) / web.width
            let crop = CGRect(x: visible.minX * factor, y: visible.minY * factor,
                              width: visible.width * factor, height: visible.height * factor).integral
            guard let cropped = cg.cropping(to: crop) else { return }
            let rep = NSBitmapImageRep(cgImage: cropped)
            try? rep.representation(using: .png, properties: [:])?.write(to: directory.appending(path: name))
        }
    }

    private func writeStill() {
        guard let container else { return }
        let web = container.webView.frame
        let visible = container.bounds.offsetBy(dx: -web.minX, dy: -web.minY)
        let directory = directory
        container.webView.evaluateJavaScript("player && player.getCurrentTime ? player.getCurrentTime() : -1") { time, _ in
            appleTrace("probe still at mediaTime=\(time ?? "?")")
        }
        container.webView.takeSnapshot(with: nil) { image, _ in
            guard let image, let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil), web.width > 0 else { return }
            let factor = CGFloat(cg.width) / web.width
            let crop = CGRect(x: visible.minX * factor, y: visible.minY * factor,
                              width: visible.width * factor, height: visible.height * factor).integral
            guard let cropped = cg.cropping(to: crop) else { return }
            try? NSBitmapImageRep(cgImage: cropped).representation(using: .png, properties: [:])?
                .write(to: directory.appending(path: "still.png"))
        }
    }

    private func finish() {
        timer?.invalidate()
        timer = nil
        guard !lines.isEmpty else { return }
        try? (lines.joined(separator: "\n") + "\n").write(to: directory.appending(path: "probe.log"),
                                                          atomically: true, encoding: .utf8)
        lines.removeAll()
    }
}
#endif
