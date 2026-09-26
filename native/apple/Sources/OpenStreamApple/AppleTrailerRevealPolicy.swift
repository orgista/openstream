import Foundation

/// When the shared trailer page (`AppleYouTubePreviewHTML`) may reveal its
/// player once YouTube has said PLAYING — one rule for the iPhone, iPad,
/// Vision Pro and Mac pages; the host's own art-first gate (picture band,
/// geometry settle) still runs after it.
///
/// The fixed waits (3.2 s landscape, 0.9 s portrait, 2026-09-12) hid the
/// title strip and link that YouTube's MOBILE embed draws over the first
/// 3.5–4 s of playback (N46 film, iPhone). A host where that chrome cannot
/// reach the screen reveals as soon as the video is really advancing — at
/// least `minimumWait` after PLAYING and `minimumMediaAdvance` of media time
/// past where PLAYING found it — and never later than the old wait:
/// - the Mac's desktop embed draws none: filmed every 250 ms from PLAYING,
///   three trailers were clean from the first sample (N70);
/// - on iPhone and iPad the strip and link live inside YouTube's
///   `.player-controls-top`, which the frame script every trailer web view
///   injects has hidden since N49 (`AppleYouTubePreviewHTML.playerChromeScript`,
///   `[class^="player-controls"]`). Filmed every 250 ms from PLAYING (N75):
///   without that CSS the strip is up from load until 3.9–4.2 s of media
///   time; with it, it is `display: none` from the first frame and never
///   painted, on the Discover hero and the title page.
/// Vision Pro keeps the old wait: its frame script is the same, but no one
/// has filmed it there.
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

    /// Whether YouTube's start-up title strip and link can reach the screen
    /// on this platform's trailer page (see the type's notes).
    static var startupChromeCanShow: Bool {
        #if os(visionOS)
        true
        #else
        false
        #endif
    }

    static func rule(isLandscape: Bool, startupChromeCanShow: Bool) -> AppleTrailerRevealRule {
        let cap = isLandscape ? landscapeCap : portraitCap
        guard !startupChromeCanShow else {
            return AppleTrailerRevealRule(minimumWait: cap, minimumMediaAdvance: 0, cap: cap)
        }
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
