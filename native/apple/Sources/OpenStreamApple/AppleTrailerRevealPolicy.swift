import Foundation

/// When the shared trailer page (`AppleYouTubePreviewHTML`) may reveal its
/// player once YouTube has said PLAYING — one rule for the iPhone, iPad,
/// Vision Pro and Mac pages; the host's own art-first gate (picture band,
/// geometry settle) still runs after it.
///
/// The fixed waits (3.2 s landscape, 0.9 s portrait, 2026-09-12) hid the
/// title strip and link that YouTube's MOBILE embed draws over the first
/// 3.5–4 s of playback (N46 film, iPhone). The Mac's desktop embed draws no
/// such chrome: filmed every 250 ms from PLAYING, three trailers showed a
/// clean, full-quality picture from the first sample (N70). So a host whose
/// embed draws no start-up chrome reveals as soon as the video is really
/// advancing — at least `minimumWait` after PLAYING and `minimumMediaAdvance`
/// of media time past where PLAYING found it — and never later than the old
/// wait. A host whose embed does draw it keeps the old wait exactly.
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

    /// Whether this platform's web view gets YouTube's mobile embed, which
    /// draws a title strip and link over the first seconds of playback.
    static var embedDrawsStartupChrome: Bool {
        #if os(macOS)
        false
        #else
        true
        #endif
    }

    static func rule(isLandscape: Bool, embedDrawsStartupChrome: Bool) -> AppleTrailerRevealRule {
        let cap = isLandscape ? landscapeCap : portraitCap
        guard !embedDrawsStartupChrome else {
            return AppleTrailerRevealRule(minimumWait: cap, minimumMediaAdvance: 0, cap: cap)
        }
        return AppleTrailerRevealRule(minimumWait: min(minimumWait, cap), minimumMediaAdvance: minimumMediaAdvance, cap: cap)
    }

    /// The same rules for the page's script: `[minimum wait ms, media
    /// advance s, cap ms]` per orientation.
    static func javascriptRules(embedDrawsStartupChrome: Bool) -> String {
        func entry(_ rule: AppleTrailerRevealRule) -> String {
            "[\(Int((rule.minimumWait * 1000).rounded())), \(rule.minimumMediaAdvance), \(Int((rule.cap * 1000).rounded()))]"
        }
        let landscape = rule(isLandscape: true, embedDrawsStartupChrome: embedDrawsStartupChrome)
        let portrait = rule(isLandscape: false, embedDrawsStartupChrome: embedDrawsStartupChrome)
        return "{landscape: \(entry(landscape)), portrait: \(entry(portrait))}"
    }
}
