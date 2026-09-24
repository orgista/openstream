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

/// N22c: a title page with nothing to play has no Play, so the opening
/// focus goes to My List.
@Suite("Apple TV title page opening focus without Play")
struct AppleTVDetailOpeningFocusWithoutPlayTests {
    @Test func theTargetIsMyListWithoutPlay() {
        #expect(AppleTVDetailOpeningFocus.target(showsPlay: true) == .play)
        #expect(AppleTVDetailOpeningFocus.target(showsPlay: false) == .myList)
    }

    @Test func myListSettlesTheOpening() {
        #expect(AppleTVDetailOpeningFocus.settles(on: .myList, target: .myList))
        #expect(!AppleTVDetailOpeningFocus.settles(on: .rate, target: .myList))
    }

    @Test(arguments: [AppleTVDetailFocus.play, .rate, .rateChoice(0)])
    func otherTitleRowFocusGoesToMyList(_ focus: AppleTVDetailFocus) {
        #expect(AppleTVDetailOpeningFocus.correction(for: focus, hasHadAnyFocus: true, target: .myList) == .myList)
    }

    @Test func nothingFocusedAsksForMyList() {
        #expect(AppleTVDetailOpeningFocus.correction(for: nil, hasHadAnyFocus: false, target: .myList) == .myList)
        #expect(AppleTVDetailOpeningFocus.correction(for: .myList, hasHadAnyFocus: true, target: .myList) == nil)
    }
}
