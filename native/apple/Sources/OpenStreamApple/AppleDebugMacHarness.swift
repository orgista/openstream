#if DEBUG && os(macOS)
import AppKit
import QuartzCore

/// Headless measuring aids for the Mac (N34), DEBUG only.
///
/// `-OpenStreamMacWindowOrigin x,y` moves the window's top-left corner to
/// that screen point (from the top-left of the main screen) once it opens —
/// never ordering it forward — so a test copy can sit where the owner's own
/// windows do not cover it. `-OpenStreamMacWindowSize w,h` also sets its
/// size, so every run lays out the same page.
///
/// `-OpenStreamMacFrameMeter start,seconds` counts display frames on the
/// main thread over that window of the launch and logs how many arrived
/// more than 33 ms after the one before (a visible hitch) and the longest
/// gap. The sweep below meters itself.
///
/// `-OpenStreamMacScrollSweep <points>` scrolls the window's main scroll view
/// that far down and back up in 40 pt steps, one per frame, eight seconds
/// after launch — a headless stand-in for a trackpad scroll, so a hitch trace
/// measures real scrolling. It moves the AppKit scroll view directly: moving
/// a SwiftUI `ScrollPosition` instead writes state on the screen being
/// measured and re-renders all of it at every step.
@MainActor
enum AppleDebugMacHarness {
    static func startIfRequested() {
        placeWindowIfRequested()
        meterIfRequested()
        let distance = UserDefaults.standard.double(forKey: "OpenStreamMacScrollSweep")
        guard distance > 0 else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(8))
            guard let scrollView = mainScrollView() else {
                appleTrace("mac sweep: no scroll view")
                return
            }
            appleTrace("mac sweep start")
            let meter = AppleDebugFrameMeter(view: scrollView)
            let clip = scrollView.contentView
            let bottom = max(0, (scrollView.documentView?.frame.height ?? 0) - clip.bounds.height)
            let target = min(distance, bottom)
            let down = Array(stride(from: 0.0, through: target, by: 40))
            for y in down + down.reversed() {
                clip.scroll(to: NSPoint(x: clip.bounds.origin.x, y: y))
                scrollView.reflectScrolledClipView(clip)
                try? await Task.sleep(for: .milliseconds(16))
            }
            appleTrace("mac sweep end \(Int(target)) pt; \(meter.finish())")
        }
    }

    private static func meterIfRequested() {
        let parts = (UserDefaults.standard.string(forKey: "OpenStreamMacFrameMeter") ?? "")
            .split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        guard parts.count == 2 else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(parts[0]))
            guard let view = NSApp.windows.first(where: { $0.isVisible && $0.frame.width > 400 })?.contentView else { return }
            let meter = AppleDebugFrameMeter(view: view)
            try? await Task.sleep(for: .seconds(parts[1]))
            appleTrace("mac frames \(Int(parts[0]))-\(Int(parts[0] + parts[1]))s: \(meter.finish())")
        }
    }

    private static func placeWindowIfRequested() {
        let parts = (UserDefaults.standard.string(forKey: "OpenStreamMacWindowOrigin") ?? "")
            .split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        guard parts.count == 2 else { return }
        Task { @MainActor in
            for _ in 0 ..< 50 {
                if let window = NSApp.windows.first(where: { $0.isVisible && $0.contentView != nil && $0.frame.width > 400 }),
                   let screen = NSScreen.screens.first {
                    let size = (UserDefaults.standard.string(forKey: "OpenStreamMacWindowSize") ?? "")
                        .split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
                    if size.count == 2 {
                        window.setContentSize(NSSize(width: size[0], height: size[1]))
                    }
                    window.setFrameTopLeftPoint(NSPoint(x: parts[0], y: screen.frame.maxY - parts[1]))
                    appleTrace("mac window placed \(Int(window.frame.minX)),\(Int(parts[1])) \(Int(window.frame.width))x\(Int(window.frame.height))")
                    return
                }
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }

    /// The tallest vertically scrolling view in a visible window: Discover's
    /// page, not a horizontal row inside it.
    private static func mainScrollView() -> NSScrollView? {
        var best: NSScrollView?
        func visit(_ view: NSView) {
            if let scroll = view as? NSScrollView, scroll.hasVerticalScroller || scroll.verticalScrollElasticity != .none,
               (scroll.documentView?.frame.height ?? 0) > scroll.frame.height,
               scroll.frame.height > (best?.frame.height ?? 0) {
                best = scroll
            }
            view.subviews.forEach(visit)
        }
        for window in NSApp.windows where window.isVisible {
            if let content = window.contentView { visit(content) }
        }
        return best
    }
}

/// Main-thread frame arrival, from the view's display link.
@MainActor
final class AppleDebugFrameMeter: NSObject {
    private var link: CADisplayLink?
    private var last: CFTimeInterval?
    private var frames = 0
    private var late = 0
    private var longest: CFTimeInterval = 0

    init(view: NSView) {
        super.init()
        link = view.displayLink(target: self, selector: #selector(tick(_:)))
        link?.add(to: .main, forMode: .common)
    }

    @objc private func tick(_ link: CADisplayLink) {
        let now = link.timestamp
        if let last {
            let gap = now - last
            longest = max(longest, gap)
            if gap > 0.033 { late += 1 }
        }
        last = now
        frames += 1
    }

    func finish() -> String {
        link?.invalidate()
        link = nil
        return "frames=\(frames) late>33ms=\(late) longest=\(Int((longest * 1000).rounded()))ms"
    }
}
#endif
