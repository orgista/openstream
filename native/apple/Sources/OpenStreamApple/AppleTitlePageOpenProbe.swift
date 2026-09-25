#if DEBUG
import Foundation

/// Review builds only: how long the main thread is busy after a title page is
/// pushed (N47), measured in the app rather than by attaching a profiler.
///
/// `-OpenStreamTitlePageProbe YES` with the `OpenStreamVisionScreen` hook:
/// each push prints `[OpenStream] title-open <label> busy <ms>/600 ms …`.
/// Busy is the time the main run loop spends outside its wait — the same
/// thing a profiler's main-thread samples count — over the 600 ms after the
/// push (N45's window) and over 2 s, the longest busy streak (gaps ≤ 2 ms
/// merged), when the page first appeared, and the busy spans themselves.
/// With `-OpenStreamMainThreadSamples` the push is also sampled
/// (`AppleMainThreadSampler`).
@MainActor
enum AppleTitlePageOpenProbe {
    static let isEnabled = UserDefaults.standard.bool(forKey: "OpenStreamTitlePageProbe")

    private static var observer: CFRunLoopObserver?
    private static var busySince: CFAbsoluteTime?
    private static var intervals: [(start: CFAbsoluteTime, end: CFAbsoluteTime)] = []
    private static var windowStart: CFAbsoluteTime?
    private static var firstAppear: CFAbsoluteTime?

    /// Call where the push is requested.
    static func pushed(_ label: String) {
        guard isEnabled else { return }
        install()
        #if (os(macOS) || targetEnvironment(simulator)) && arch(arm64)
        AppleMainThreadSampler.captureMainThread()
        AppleMainThreadSampler.sample(label: label)
        #endif
        let now = CFAbsoluteTimeGetCurrent()
        windowStart = now
        busySince = now
        intervals = []
        firstAppear = nil
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(2100))
            report(label, start: now)
        }
    }

    /// The page's first `onAppear` after the push.
    static func appeared() {
        guard isEnabled, windowStart != nil, firstAppear == nil else { return }
        firstAppear = CFAbsoluteTimeGetCurrent()
    }

    private static func install() {
        guard observer == nil else { return }
        let activities = CFRunLoopActivity.afterWaiting.rawValue | CFRunLoopActivity.beforeWaiting.rawValue
        let observer = CFRunLoopObserverCreateWithHandler(nil, activities, true, 0) { _, activity in
            MainActor.assumeIsolated { AppleTitlePageOpenProbe.runLoop(activity) }
        }
        CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
        self.observer = observer
    }

    private static func runLoop(_ activity: CFRunLoopActivity) {
        guard windowStart != nil else { return }
        let now = CFAbsoluteTimeGetCurrent()
        if activity == .afterWaiting {
            busySince = now
        } else if let since = busySince {
            intervals.append((since, now))
            busySince = nil
        }
    }

    private static func busy(from start: CFAbsoluteTime, to end: CFAbsoluteTime,
                             in spans: [(start: CFAbsoluteTime, end: CFAbsoluteTime)]) -> (total: Double, longest: Double) {
        var total = 0.0
        var longest = 0.0
        var streak: (start: CFAbsoluteTime, end: CFAbsoluteTime)?
        for span in spans {
            let s = max(span.start, start), e = min(span.end, end)
            guard e > s else { continue }
            total += e - s
            if let current = streak, s - current.end <= 0.002 {
                streak = (current.start, e)
            } else {
                streak = (s, e)
            }
            if let current = streak { longest = max(longest, current.end - current.start) }
        }
        return (total * 1000, longest * 1000)
    }

    private static func report(_ label: String, start: CFAbsoluteTime) {
        guard windowStart == start else { return }
        var spans = intervals
        if let since = busySince { spans.append((since, CFAbsoluteTimeGetCurrent())) }
        let short = busy(from: start, to: start + 0.6, in: spans)
        let long = busy(from: start, to: start + 2.0, in: spans)
        let appear = firstAppear.map { String(Int((($0 - start) * 1000).rounded())) } ?? "-"
        let loops = spans.filter { $0.end - $0.start > 0.002 && $0.start < start + 0.6 }
            .map { "\(Int((($0.start - start) * 1000).rounded()))-\(Int((($0.end - start) * 1000).rounded()))" }
        print("[OpenStream] title-open \(label) loops [\(loops.joined(separator: " "))]")
        print("[OpenStream] title-open \(label) busy \(Int(short.total.rounded()))/600 ms longest \(Int(short.longest.rounded())) ms; busy \(Int(long.total.rounded()))/2000 ms; appear +\(appear) ms)")
        fflush(stdout)
        windowStart = nil
        intervals = []
    }
}
#endif
