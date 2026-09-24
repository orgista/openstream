import CoreGraphics
import Testing
@testable import OpenStreamApple

@Suite("Mac title page layout")
struct AppleTitlePageMacLayoutTests {
    @Test("The art is two thirds of the window tall", arguments: [
        (CGSize(width: 1440, height: 900), 594.0),
        (CGSize(width: 1000, height: 800), 528.0),
        (CGSize(width: 1700, height: 1000), 660.0),
    ])
    func heroFollowsTheWindowHeight(window: CGSize, expected: CGFloat) {
        let layout = AppleTitlePageMacLayout(contentWidth: window.width, windowHeight: window.height)
        #expect(layout.heroHeight == expected)
    }

    @Test func aTallNarrowWindowDoesNotGetAPortraitHero() {
        let layout = AppleTitlePageMacLayout(contentWidth: 700, windowHeight: 1400)
        #expect(layout.heroHeight == 525)
    }

    @Test func theHeroNeverDropsBelowItsFloor() {
        #expect(AppleTitlePageMacLayout(contentWidth: 800, windowHeight: 500).heroHeight == 420)
        // Before the window has been measured.
        #expect(AppleTitlePageMacLayout(contentWidth: 0, windowHeight: 0).heroHeight == 420)
    }

    @Test func theCopyColumnGrowsWithTheWindowWithinItsBounds() {
        #expect(AppleTitlePageMacLayout(contentWidth: 1000, windowHeight: 800).copyWidth == 420)
        #expect(AppleTitlePageMacLayout(contentWidth: 700, windowHeight: 800).copyWidth == 360)
        #expect(AppleTitlePageMacLayout(contentWidth: 1700, windowHeight: 1000).copyWidth == 560)
        // Never wider than the window leaves between its insets.
        let narrow = AppleTitlePageMacLayout(contentWidth: 380, windowHeight: 800)
        #expect(narrow.copyWidth == 380 - 2 * narrow.horizontalInset)
    }

    @Test func theInsetIsTheDiscoverRailsInset() {
        for width in [800.0, 1200, 1440, 1900] {
            let layout = AppleTitlePageMacLayout(contentWidth: width, windowHeight: 900)
            #expect(layout.horizontalInset == AppleMacHeroLayout(contentWidth: width).horizontalPadding)
        }
    }

    @Test func referenceBlocksStackBelowTheBreakpointAndSitSideBySideAboveIt() {
        let narrow = AppleTitlePageMacLayout(contentWidth: 899, windowHeight: 800)
        #expect(narrow.referenceColumns(count: 3) == 1)
        let wide = AppleTitlePageMacLayout(contentWidth: 900, windowHeight: 800)
        #expect(wide.referenceColumns(count: 3) == 3)
        #expect(wide.referenceColumns(count: 2) == 2)
        #expect(wide.referenceColumns(count: 1) == 1)
        #expect(wide.referenceColumns(count: 0) == 1)
        #expect(wide.referenceColumns(count: 5) == 3)
    }
}
