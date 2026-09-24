import Foundation
import Testing
@testable import OpenStreamApple

/// The Mac hero asks for the best trailer stream it can show pixel for pixel
/// (owner, 2026-09-24: the playing trailer looked muddy next to the Apple TV
/// app's), and a narrow fade while the video is up.
@Suite("Trailer quality and fade")
struct AppleTrailerQualityTests {
    @Test("Highest quality no taller than the frame", arguments: [
        (2_400.0, "hd2160"), (2_160.0, "hd2160"), (1_935.0, "hd1440"), (1_360.0, "hd1080"),
        (1_080.0, "hd1080"), (877.0, "hd720"), (600.0, "large"), (200.0, "medium"),
    ])
    func qualityFitsTheFrame(pixelHeight: Double, expected: String) {
        #expect(AppleTrailerPreviewPolicy.quality(forPixelHeight: pixelHeight) == expected)
    }

    @Test func embedURLCarriesTheChosenQuality() throws {
        let url = try #require(AppleTrailerPreviewPolicy.embedURL(for: "abcdefghijk", quality: "hd1080"))
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        #expect(items.first { $0.name == "vq" }?.value == "hd1080")
    }

    @Test func videoFadeLeavesTheCentreAndRightUntouched() {
        let leading = AppleMacHeroFade.leading(videoIsShowing: true)
        let bottom = AppleMacHeroFade.bottom(videoIsShowing: true)
        #expect(leading.last?.opacity == 0)
        #expect((leading.last?.location ?? 1) <= 0.4)
        #expect(bottom.last?.opacity == 0)
        #expect((bottom.last?.location ?? 1) <= 0.3)
        // Narrower than the still's fade, never darker.
        #expect((leading.last?.location ?? 1) < (AppleMacHeroFade.leading.last?.location ?? 0))
        #expect((leading.first?.opacity ?? 1) <= (AppleMacHeroFade.leading.first?.opacity ?? 0))
        #expect(AppleMacHeroFade.leading(videoIsShowing: false) == AppleMacHeroFade.leading)
    }
}
