import CoreGraphics
import Testing
@testable import OpenStreamApple

@Test func detailActionButtonsShareOneFixedFrame() {
    let layouts: [(AppleDetailLayout, CGFloat, CGFloat)] = [
        (.portraitPhone, 390, 174),
        (.portraitIPad, 834, 150),
        (.landscapeIPad, 1_192, 140),
    ]

    #expect(AppleDetailMetrics.actionButtonHeight == 36)
    #expect(AppleDetailMetrics.actionButtonCornerRadius == 18)
    #expect(AppleDetailMetrics.actionButtonLabelFontSize == 15)
    #expect(AppleDetailMetrics.actionButtonGlyphSize == 13)
    #expect(AppleDetailMetrics.actionButtonHorizontalPadding == 16)
    #expect(AppleDetailMetrics.actionButtonGap == 10)
    #expect(AppleDetailMetrics.iconGlyphSize == 20)
    #expect(AppleDetailMetrics.iconLabelFontSize == 11)
    #expect(AppleDetailMetrics.iconRowHeight == 44)

    for (layout, screenWidth, expectedWidth) in layouts {
        let frames = AppleDetailMetrics.actionButtonFrames(for: layout, screenWidth: screenWidth)
        #expect(frames.play.size == frames.download.size)
        #expect(frames.play.width == expectedWidth)
        #expect(frames.play.height == AppleDetailMetrics.actionButtonHeight)
        #expect(frames.download.minX - frames.play.maxX == AppleDetailMetrics.actionButtonGap)
        #expect(AppleDetailMetrics.iconRowWidth(for: layout, screenWidth: screenWidth) == frames.download.maxX)
    }
}

@Test func detailFormatBadgesNeverRepresentDolbyAsText() {
    #expect(AppleFormatBadgeKind.resolve("4K") == .text("4K"))
    #expect(AppleFormatBadgeKind.resolve("HDR10+") == .text("HDR10+"))
    #expect(AppleFormatBadgeKind.resolve("dolby vision") == .image("dolby-vision"))
    #expect(AppleFormatBadgeKind.resolve("DV") == .image("dolby-vision"))
    #expect(AppleFormatBadgeKind.resolve("DOLBY ATMOS") == .image("dolby-atmos"))
    #expect(AppleFormatBadgeKind.resolve("DOLBY AUDIO") == .image("dolby-audio"))
    #expect(AppleFormatBadgeKind.resolve("unknown") == nil)
}

@Test func detailMetadataMatchesAppleTVOrderAndFormatting() {
    #expect(AppleTitleMetadataPresentation.textValues(
        genres: ["Sci-Fi", "Drama"],
        releaseInfo: "2026-09-04",
        runtimeMinutes: 103
    ) == ["Sci-Fi", "Sep 4, 2026", "1 hr 43 min"])
    #expect(AppleTitleMetadataPresentation.formattedRuntime(60) == "1 hr")
    #expect(AppleTitleMetadataPresentation.formattedRuntime(43) == "43 min")

    #expect(AppleTitleMetadataPresentation.orderedBadges(
        contentRating: "TV-MA",
        formatBadges: ["AD", "DOLBY ATMOS", "4K", "CC", "HDR", "SDH", "HD"],
        limit: 6
    ) == ["TV-MA", "4K", "HDR", "CC", "SDH", "AD"])
}
