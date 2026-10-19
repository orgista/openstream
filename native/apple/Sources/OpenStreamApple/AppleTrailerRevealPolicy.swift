import Foundation

/// When the shared trailer page may reveal its player after PLAYING.
/// The host's art-first gate (picture band, geometry settle) still runs after it.
///
/// iOS hides the centre play glyph and reveals without waiting for start-up
/// chrome; YouTube's title strip and attribution remain untouched.
struct AppleTrailerRevealRule: Equatable, Sendable {
    /// Never earlier than this after PLAYING.
    var minimumWait: TimeInterval
    /// Media time that must have played since PLAYING: frames are flowing,
    /// not a stalled first buffer.
    var minimumMediaAdvance: TimeInterval
    /// Reveals at this regardless (the old fixed wait).
    var cap: TimeInterval

    func allowsReveal(sincePlaying: TimeInterval, mediaAdvance: TimeInterval) -> Bool {
        if sincePlaying >= cap { return true }
        return sincePlaying >= minimumWait && mediaAdvance >= minimumMediaAdvance
    }
}

enum AppleTrailerRevealPolicy {
    static let landscapeCap: TimeInterval = 3.2
    static let portraitCap: TimeInterval = 0.9
    static let minimumWait: TimeInterval = 0.5
    static let minimumMediaAdvance: TimeInterval = 0.3
    /// Media time the mobile embed's start-up chrome stays up, plus a margin.
    static let startupChromeMediaTime: TimeInterval = 4.5
    /// A video that stalls under its chrome is shown anyway after this.
    static let startupChromeCap: TimeInterval = 12

    /// Whether the page waits for YouTube's start-up chrome to fade.
    static var startupChromeCanShow: Bool {
        #if os(macOS) || os(iOS)
        false
        #else
        true
        #endif
    }

    static func rule(isLandscape: Bool, startupChromeCanShow: Bool) -> AppleTrailerRevealRule {
        guard !startupChromeCanShow else {
            return AppleTrailerRevealRule(minimumWait: minimumWait, minimumMediaAdvance: startupChromeMediaTime,
                                          cap: startupChromeCap)
        }
        let cap = isLandscape ? landscapeCap : portraitCap
        return AppleTrailerRevealRule(minimumWait: min(minimumWait, cap), minimumMediaAdvance: minimumMediaAdvance, cap: cap)
    }

    /// The same rules for the page's script: `[minimum wait ms, media
    /// advance s, cap ms]` per orientation.
    static func javascriptRules(startupChromeCanShow: Bool) -> String {
        func entry(_ rule: AppleTrailerRevealRule) -> String {
            "[\(Int((rule.minimumWait * 1000).rounded())), \(rule.minimumMediaAdvance), \(Int((rule.cap * 1000).rounded()))]"
        }
        let landscape = rule(isLandscape: true, startupChromeCanShow: startupChromeCanShow)
        let portrait = rule(isLandscape: false, startupChromeCanShow: startupChromeCanShow)
        return "{landscape: \(entry(landscape)), portrait: \(entry(portrait))}"
    }
}
