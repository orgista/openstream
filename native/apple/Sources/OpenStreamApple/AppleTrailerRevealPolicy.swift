import Foundation

/// When the shared trailer page (`AppleYouTubePreviewHTML`) may reveal its
/// player once YouTube has said PLAYING — one rule for the iPhone, iPad,
/// Vision Pro and Mac pages; the host's own art-first gate (picture band,
/// geometry settle) still runs after it.
///
/// Nothing of YouTube's player is hidden or cropped (its terms; owner round 3, 2026-10-10). Where the
/// mobile embed draws its start-up title strip, link and "More videos" (iPhone, iPad, Vision Pro), the
/// art stays up until that chrome has faded on its own — 3.9–4.2 s of media time when filmed (N75) — and
/// the trailer is shown from then on, attribution and all, whenever YouTube draws it again.
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

    /// Whether YouTube's start-up title strip and link can reach the screen
    /// on this platform's trailer page: the mobile embed draws them, the
    /// Mac's desktop embed does not (N70).
    static var startupChromeCanShow: Bool {
        #if os(macOS)
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
