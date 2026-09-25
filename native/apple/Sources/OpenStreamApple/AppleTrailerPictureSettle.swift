import CoreGraphics
import Foundation

/// The iPhone and iPad hero's reveal gate (N46b): its trailer is cropped to
/// the picture band measured inside YouTube's 16:9 raster, and that crop is
/// final before the art fades. A band first measured after the fade (a dark
/// opening frame) grew Project Hail Mary 1.30→1.73× 1.1 s into the video.
/// The art now stays up until the same band — at the same hero size — has
/// been measured for `stableInterval`, and reveals at whatever was last
/// measured after `timeout` rather than never. Nothing is measured again
/// once the video shows, so the crop never changes while it is seen.
struct AppleTrailerPictureSettle {
    /// The band must hold this long before the art fades (the Mac gate's).
    static let stableInterval: TimeInterval = 0.3
    /// Reveals anyway after this, rather than never show the trailer.
    static let timeout: TimeInterval = 3
    /// How often a frame is measured while the art is up.
    static let pollInterval: TimeInterval = 0.1
    /// Raster fraction two measurements may differ by and still be the same
    /// band: two rows of the 256 × 144 snapshot a band is read from.
    static let tolerance: CGFloat = 0.015

    enum Verdict: Equatable {
        case wait
        /// `window` is nil when no frame measured at all: the whole raster.
        case reveal(window: ClosedRange<CGFloat>?, settled: Bool)
    }

    private var start: Date?
    private var candidate: (window: ClosedRange<CGFloat>, size: CGSize, since: Date)?
    private var lastMeasured: ClosedRange<CGFloat>?

    /// One measurement of the current frame: `window` is nil for a frame
    /// that measures as nothing (a fade-in, a title card), which breaks the
    /// run. `size` is the hero's size when it was taken.
    mutating func record(_ window: ClosedRange<CGFloat>?, size: CGSize, at now: Date) -> Verdict {
        let start = start ?? now
        self.start = start
        if let window {
            lastMeasured = window
            if let candidate, candidate.size == size, Self.isSame(candidate.window, window) {
                self.candidate = (window, size, candidate.since)
            } else {
                candidate = (window, size, now)
            }
        } else {
            candidate = nil
        }
        if let candidate, now.timeIntervalSince(candidate.since) >= Self.stableInterval {
            return .reveal(window: candidate.window, settled: true)
        }
        if now.timeIntervalSince(start) >= Self.timeout {
            return .reveal(window: lastMeasured, settled: false)
        }
        return .wait
    }

    static func isSame(_ a: ClosedRange<CGFloat>, _ b: ClosedRange<CGFloat>) -> Bool {
        abs(a.lowerBound - b.lowerBound) <= tolerance && abs(a.upperBound - b.upperBound) <= tolerance
    }
}
