import CoreGraphics
import Testing
@testable import OpenStreamApple

@Suite("Catalog card progress bar inset")
struct AppleCatalogCardMetricsTests {
    /// N58: on Apple TV a bar on the art's bottom edge vanished from the
    /// focused card, so it sits inside the art, clear of every edge.
    @Test func appleTVBarSitsInsideTheArtwork() {
        let inset = AppleCatalogCardMetrics.progressBarInset(isTV: true)
        #expect(inset.horizontal > 0)
        #expect(inset.bottom > 0)
        #expect(inset.bottom < 20)
    }

    @Test func otherPlatformsKeepTheEdgeBar() {
        let inset = AppleCatalogCardMetrics.progressBarInset(isTV: false)
        #expect(inset.horizontal == 0)
        #expect(inset.bottom == 0)
    }
}
