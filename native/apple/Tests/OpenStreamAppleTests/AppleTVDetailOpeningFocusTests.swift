import Testing
@testable import OpenStreamApple

@Suite("Apple TV title page opening focus")
struct AppleTVDetailOpeningFocusTests {
    @Test func onlyPlaySettlesTheOpening() {
        #expect(AppleTVDetailOpeningFocus.settles(on: .play))
        #expect(!AppleTVDetailOpeningFocus.settles(on: .rate))
        #expect(!AppleTVDetailOpeningFocus.settles(on: nil))
    }

    @Test(arguments: [AppleTVDetailFocus.myList, .rate, .rateChoice(0)])
    func focusCarriedOntoTheTitleRowGoesBackToPlay(_ focus: AppleTVDetailFocus) {
        #expect(AppleTVDetailOpeningFocus.correction(for: focus, hasHadAnyFocus: true) == .play)
        #expect(AppleTVDetailOpeningFocus.correction(for: focus, hasHadAnyFocus: false) == .play)
    }

    @Test func aPageWithNothingFocusedAsksForPlay() {
        #expect(AppleTVDetailOpeningFocus.correction(for: nil, hasHadAnyFocus: false) == .play)
    }

    @Test func focusBelowTheTitleRowIsLeftAlone() {
        #expect(AppleTVDetailOpeningFocus.correction(for: nil, hasHadAnyFocus: true) == nil)
        #expect(AppleTVDetailOpeningFocus.correction(for: .play, hasHadAnyFocus: true) == nil)
    }
}
