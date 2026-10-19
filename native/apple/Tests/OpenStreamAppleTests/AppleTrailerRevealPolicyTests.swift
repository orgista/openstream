import Foundation
import Testing
@testable import OpenStreamApple

@Suite("Trailer page: reveal once the video advances, preserving attribution")
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

    @Test("Platforms retaining the chrome wait keep their existing rule", arguments: [true, false])
    func startupChromeWaitIsUnchanged(isLandscape: Bool) {
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

    @Test("iOS and Mac reveal without waiting for start-up chrome")
    func platformDefault() {
        #if os(macOS) || os(iOS)
        #expect(AppleTrailerRevealPolicy.startupChromeCanShow == false)
        #else
        #expect(AppleTrailerRevealPolicy.startupChromeCanShow == true)
        #endif
    }

    @Test("Owner: \"only the centre play glyph is hidden\"; YouTube attribution stays")
    func frameScriptsPreserveAttribution() {
        for script in [AppleYouTubePreviewHTML.playerChromeScript, AppleYouTubePreviewHTML.macPlayerFrameScript] {
            #expect(script.contains(#"[class^="player-controls"]"#) == false)
            #expect(script.contains("player-controls-top") == false)
            #expect(script.contains(".ytp-chrome-top") == false)
            #expect(script.contains(".player-controls-middle,"))
            #expect(script.contains(".ytp-bezel"))
        }
    }

    @Test("The iOS and Mac page defaults reveal at 0.5 s with 0.3 s of media")
    func pageDefaultsToFastReveal() throws {
        let embed = try #require(AppleTrailerPreviewPolicy.embedURL(for: "trailer_456"))
        let html = AppleYouTubePreviewHTML.document(embedURL: embed, startsPlaying: true)
        #if os(macOS) || os(iOS)
        #expect(html.contains("var revealRules = {landscape: [500, 0.3, 3200], portrait: [500, 0.3, 900]};"))
        #else
        #expect(html.contains("var revealRules = {landscape: [500, 4.5, 12000], portrait: [500, 4.5, 12000]};"))
        #endif
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
