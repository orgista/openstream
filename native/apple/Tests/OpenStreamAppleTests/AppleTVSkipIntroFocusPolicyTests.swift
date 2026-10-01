import Foundation
import Testing
@testable import OpenStreamApple

/// Full test 2026-10-01: Skip Intro showed, but Down from the video went to
/// the scrubber row and never reached it.
@Suite("Apple TV Skip Intro focus")
struct AppleTVSkipIntroFocusPolicyTests {
    @Test func downFromThePictureStopsAtSkipIntro() {
        #expect(AppleTVSkipIntroFocusPolicy.redirects(fromSurface: true, toBottomBar: true, showsSkipIntro: true))
    }

    @Test func otherMovesAreLeftAlone() {
        #expect(!AppleTVSkipIntroFocusPolicy.redirects(fromSurface: true, toBottomBar: true, showsSkipIntro: false))
        #expect(!AppleTVSkipIntroFocusPolicy.redirects(fromSurface: false, toBottomBar: true, showsSkipIntro: true))
        #expect(!AppleTVSkipIntroFocusPolicy.redirects(fromSurface: true, toBottomBar: false, showsSkipIntro: true))
    }
}
