import Foundation
import Testing
@testable import OpenStreamApple

/// N70/N75: the shared trailer page reveals as soon as the video is really
/// advancing where YouTube's start-up chrome cannot reach the screen (the
/// Mac's desktop embed draws none), and after that chrome has faded where the
/// mobile embed draws it (iPhone, iPad, Vision Pro).
@Suite("Trailer page: reveal once the video advances and YouTube's start-up chrome is gone")
struct AppleTrailerRevealPolicyTests {
    private let fast = AppleTrailerRevealPolicy.rule(isLandscape: true, startupChromeCanShow: false)

    @Test("Without start-up chrome: revealed at 0.5 s once 0.3 s of media has played")
    func revealsOnceTheVideoAdvances() {
        #expect(fast.allowsReveal(sincePlaying: 0.5, mediaAdvance: 0.3))
        #expect(fast.allowsReveal(sincePlaying: 0.8, mediaAdvance: 0.7))
    }

    @Test("Never before the minimum wait, however far the media has moved")
    func neverBeforeTheMinimumWait() {
        #expect(!fast.allowsReveal(sincePlaying: 0.49, mediaAdvance: 2))
        #expect(!fast.allowsReveal(sincePlaying: 0, mediaAdvance: 0.3))
    }

    @Test("A stalled first buffer waits for the old 3.2 s cap")
    func stalledVideoWaitsForTheCap() {
        #expect(!fast.allowsReveal(sincePlaying: 1.5, mediaAdvance: 0.05))
        #expect(!fast.allowsReveal(sincePlaying: 3.19, mediaAdvance: 0))
        #expect(fast.allowsReveal(sincePlaying: 3.2, mediaAdvance: 0))
        // A seek back to the start reads as negative advance: the cap still reveals.
        #expect(!fast.allowsReveal(sincePlaying: 2, mediaAdvance: -40))
        #expect(fast.allowsReveal(sincePlaying: 3.2, mediaAdvance: -40))
    }

    @Test("The mobile embed waits for its start-up chrome to fade", arguments: [true, false])
    func mobileEmbedWaitsForItsChrome(isLandscape: Bool) {
        let rule = AppleTrailerRevealPolicy.rule(isLandscape: isLandscape, startupChromeCanShow: true)
        // N75: the title strip, link and "More videos" are up until 3.9–4.2 s of media time.
        #expect(!rule.allowsReveal(sincePlaying: 4.3, mediaAdvance: 4.2))
        #expect(rule.allowsReveal(sincePlaying: 4.6, mediaAdvance: 4.5))
        #expect(!rule.allowsReveal(sincePlaying: 11.9, mediaAdvance: 1))
        #expect(rule.allowsReveal(sincePlaying: 12, mediaAdvance: 1))
    }

    @Test("Portrait without start-up chrome: still capped at 0.9 s")
    func portraitCap() {
        let rule = AppleTrailerRevealPolicy.rule(isLandscape: false, startupChromeCanShow: false)
        #expect(rule.cap == 0.9)
        #expect(rule.allowsReveal(sincePlaying: 0.5, mediaAdvance: 0.3))
        #expect(rule.allowsReveal(sincePlaying: 0.9, mediaAdvance: 0))
    }

    @Test("Only the Mac's desktop embed has no start-up chrome")
    func platformDefault() {
        #if os(macOS)
        #expect(AppleTrailerRevealPolicy.startupChromeCanShow == false)
        #else
        #expect(AppleTrailerRevealPolicy.startupChromeCanShow == true)
        #endif
    }

    @Test("Trailer scripts preserve YouTube attribution")
    func frameScriptsPreserveAttribution() {
        for script in [AppleYouTubePreviewHTML.playerChromeScript, AppleYouTubePreviewHTML.macPlayerFrameScript] {
            #expect(script.contains(#"[class^="player-controls"]"#) == false)
            #expect(script.contains("player-controls-top") == false)
            #expect(script.contains(".ytp-chrome-top") == false)
            #expect(script.contains(".ytp-bezel"))
        }
    }

    @Test("The page carries the same numbers as the Swift rule")
    func pageCarriesTheRule() throws {
        let embed = try #require(AppleTrailerPreviewPolicy.embedURL(for: "trailer_456"))
        let mac = AppleYouTubePreviewHTML.document(embedURL: embed, startsPlaying: true, isLandscape: true,
                                                   startupChromeCanShow: false)
        #expect(mac.contains("var revealRules = {landscape: [500, 0.3, 3200], portrait: [500, 0.3, 900]};"))
        let mobile = AppleYouTubePreviewHTML.document(embedURL: embed, startsPlaying: true, isLandscape: true,
                                                      startupChromeCanShow: true)
        #expect(mobile.contains("var revealRules = {landscape: [500, 4.5, 12000], portrait: [500, 4.5, 12000]};"))
        for html in [mac, mobile] {
            #expect(html.contains("if (waited >= rule[2]) return true;"))
            #expect(html.contains("return currentMediaTime() - playingMediaTime >= rule[1];"))
            #expect(!html.contains("3200 : 900"))
        }
    }
    @Test("Known trailer offsets survive initial play and replay", arguments: ["12", "0", "-1", "nan"])
    func suppliedOffsetIsHonored(_ value: String) throws {
        let embed = try #require(URL(string: "https://www.youtube-nocookie.com/embed/trailer_456?start=\(value)"))
        let html = AppleYouTubePreviewHTML.document(embedURL: embed, startsPlaying: true)
        let expected = value == "12" ? 12 : 0
        #expect(html.contains("start: \(expected),"))
        #expect(html.contains("player.seekTo(\(expected), true)"))
    }

}
