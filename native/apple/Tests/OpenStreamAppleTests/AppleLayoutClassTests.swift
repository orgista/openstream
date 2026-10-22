import CoreGraphics
import Testing
@testable import OpenStreamApple

struct AppleLayoutClassTests {
    @Test(arguments: [
        ("Duo folded, 27.2 outer window", 466.0, 678.0, false, false),
        ("Duo folded, regular width", 466.0, 678.0, true, false),
        ("Duo unfolded upright, 27.2 inner panel", 669.0, 951.0, true, true),
        ("Duo unfolded on its side", 951.0, 669.0, true, true),
        ("iPhone SE", 320.0, 568.0, false, false),
        ("iPhone Pro Max portrait", 440.0, 956.0, false, false),
        ("iPhone Pro Max landscape", 956.0, 440.0, true, false),
        ("iPad Pro 13 portrait", 1024.0, 1366.0, true, true),
        ("iPad Pro 13 landscape", 1366.0, 1024.0, true, true),
        ("M5 iPad Pro 13 portrait", 1032.0, 1376.0, true, true),
        ("iPad regular split", 686.0, 1366.0, true, true),
        ("iPad compact split", 507.0, 1366.0, false, false),
        ("Regular narrow split", 599.0, 1366.0, true, false),
        ("Minimum large short side", 600.0, 1000.0, true, true),
        ("Minimum large square", 600.0, 600.0, true, true),
        ("Compact large window", 744.0, 1133.0, false, false),
        ("Unmeasured", 0.0, 0.0, true, false),
    ])
    func classifiesWindow(_ sample: (String, Double, Double, Bool, Bool)) {
        let (name, width, height, regular, expected) = sample
        #expect(AppleLayoutClass.isLarge(size: CGSize(width: width, height: height),
                                        isRegularWidth: regular) == expected, "\(name)")
    }

    @Test func foldingReevaluatesThePhoneOrientationMask() {
        let sizes = [CGSize(width: 466, height: 678), CGSize(width: 951, height: 669),
                     CGSize(width: 669, height: 951), CGSize(width: 466, height: 678)]
        let masks = sizes.map { size in
            AppleOrientationPolicy.supportedOrientations(isPhone: true, allowsLandscape: false,
                isLargeLayout: AppleLayoutClass.isLarge(size: size, isRegularWidth: size.width >= 600))
        }
        #expect(masks == [.portrait, .allButUpsideDown, .allButUpsideDown, .portrait])
    }

    @Test func playersAndCompactIPadsKeepTheirOrientationMasks() {
        #expect(AppleOrientationPolicy.supportedOrientations(isPhone: true, allowsLandscape: true,
                                                             isLargeLayout: false) == .allButUpsideDown)
        #expect(AppleOrientationPolicy.supportedOrientations(isPhone: false, allowsLandscape: false,
                                                             isLargeLayout: false) == .all)
        #expect(AppleOrientationPolicy.supportedOrientations(isPhone: true, allowsLandscape: true,
                                                             isLargeLayout: true) == .allButUpsideDown)
    }

    @Test func largePhoneWindowsChooseThePadHeroAndChannelStrip() {
        for size in [CGSize(width: 744, height: 1133), CGSize(width: 900, height: 740)] {
            let large = AppleLayoutClass.isLarge(size: size, isRegularWidth: true)
            #expect(AppleHomePresentationPolicy.hero(platform: .iOS, compact: false,
                landscape: size.width > size.height, isLargeLayout: large) == .pad)
            #expect(AppleHomePresentationPolicy.hero(platform: .iOS, compact: false,
                accessibility: true, isLargeLayout: large) == .rotating)
            #expect(AppleLiveChannelPickerPresentation.choose(isLargeLayout: large) == .bottomStrip)
        }
        let phone = AppleLayoutClass.isLarge(size: CGSize(width: 956, height: 440), isRegularWidth: true)
        #expect(AppleLiveChannelPickerPresentation.choose(isLargeLayout: phone) == .panel)
    }

    @Test(arguments: [CGSize(width: 744, height: 1133), CGSize(width: 900, height: 740),
                      CGSize(width: 740, height: 900), CGSize(width: 600, height: 600)])
    func expandedPhonesSplitSettings(_ size: CGSize) {
        #expect(AppleLayoutClass.settingsUseSplitView(size: size, isRegularWidth: true,
                                                      preservesPortraitStack: false))
    }

    /// Upright, the stage spans the width and the list fills the height under
    /// it; on its side, the stage and its schedule sit beside the list.
    @Test(arguments: [
        (CGSize(width: 900, height: 740), true),
        (CGSize(width: 951, height: 669), true),
        (CGSize(width: 740, height: 900), false),
        (CGSize(width: 669, height: 951), false),
        (CGSize(width: 600, height: 600), false),
    ])
    func expandedPhoneLiveSplitsOnItsSide(_ sample: (CGSize, Bool)) {
        let (size, expected) = sample
        let sideBySide = AppleLiveStagePolicy.sideBySide(isRegularWidth: true, size: size, expandsPhoneLayout: true)
        #expect(sideBySide == expected)
        #expect(AppleLiveStagePolicy.showsSchedule(sideBySide: sideBySide, expandsPhoneLayout: true) == expected)
    }

    @Test func onlyIPadsShowTheStageWithoutASchedule() {
        let landscape = CGSize(width: 1376, height: 1032)
        let sideBySide = AppleLiveStagePolicy.sideBySide(isRegularWidth: true, size: landscape)
        #expect(sideBySide)
        #expect(AppleLiveStagePolicy.showsSchedule(sideBySide: sideBySide, expandsPhoneLayout: false) == false)
    }

    /// Owner 2026-10-20: no bar over the hero on a phone. The unfolded Duo is a phone.
    @Test func onlyLargeIPadWindowsUseTheBarOverTheLandingHero() {
        #expect(AppleLayoutClass.usesPadLandingChrome(isLarge: true, isPhone: false))
        #expect(AppleLayoutClass.usesPadLandingChrome(isLarge: true, isPhone: true) == false)
        #expect(AppleLayoutClass.usesPadLandingChrome(isLarge: false, isPhone: true) == false)
        #expect(AppleLayoutClass.usesPadLandingChrome(isLarge: false, isPhone: false) == false)
    }

    @Test func currentIPadAndSmallPhonePaneChoicesStayTheSame() {
        let portrait = CGSize(width: 1032, height: 1376)
        let landscape = CGSize(width: 1376, height: 1032)
        #expect(AppleLayoutClass.settingsUseSplitView(size: portrait, isRegularWidth: true,
                                                      preservesPortraitStack: true) == false)
        #expect(AppleLayoutClass.settingsUseSplitView(size: landscape, isRegularWidth: true,
                                                      preservesPortraitStack: true))
        #expect(AppleLiveStagePolicy.sideBySide(isRegularWidth: true, size: portrait) == false)
        #expect(AppleLiveStagePolicy.sideBySide(isRegularWidth: true, size: landscape))
        #expect(AppleLayoutClass.settingsUseSplitView(size: CGSize(width: 430, height: 932),
            isRegularWidth: false, preservesPortraitStack: false) == false)
        #expect(AppleLiveStagePolicy.sideBySide(isRegularWidth: true, size: CGSize(width: 430, height: 932),
                                                expandsPhoneLayout: true) == false)
    }

    @Test func resizingWithZeroTopInsetBypassesBarSettling() {
        let expanded = AppleHomePhoneHeroLayout(containerHeight: 740, topInset: 0, bottomInset: 34,
                                                containerWidth: 900)
        let outer = AppleHomePhoneHeroLayout(containerHeight: 678, topInset: 0, bottomInset: 34,
                                             containerWidth: 382)
        for held in [false, true] {
            #expect(AppleHomePhoneHeroLayout.next(drawn: expanded, measured: outer, held: held) == outer)
            #expect(AppleHomePhoneHeroLayout.next(drawn: outer, measured: expanded, held: held) == expanded)
        }
    }

    @Test func changingWidthDrawsTheNewHeroWithoutTheBarSettleDelay() {
        let wide = AppleHomePhoneHeroLayout(containerHeight: 1133, topInset: 97, bottomInset: 83,
                                            containerWidth: 744)
        let folded = AppleHomePhoneHeroLayout(containerHeight: 852, topInset: 115, bottomInset: 83,
                                              containerWidth: 393)
        #expect(AppleHomePhoneHeroLayout.next(drawn: wide, measured: folded, held: true) == folded)
        #expect(AppleHomePhoneHeroLayout.next(drawn: folded, measured: wide, held: true) == wide)
        let barChange = AppleHomePhoneHeroLayout(containerHeight: 870, topInset: 97, bottomInset: 83,
                                                 containerWidth: 393)
        #expect(AppleHomePhoneHeroLayout.next(drawn: folded, measured: barChange, held: true) == folded)
    }
}
