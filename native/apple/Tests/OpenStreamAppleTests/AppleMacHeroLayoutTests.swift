import CoreGraphics
import Foundation
import Testing
@testable import OpenStreamApple

@Suite("Mac Discover hero")
struct AppleMacHeroLayoutTests {
    @Test("Height is min(680, 75 % of the width), capped at 75 % of the window",
          arguments: [
              (CGFloat(1200), CGFloat(800), CGFloat(600)),   // the window caps it: 75 % of 800
              (CGFloat(1200), CGFloat(1200), CGFloat(680)),  // 75 % of 1200 is 900; the ceiling wins
              (CGFloat(1600), CGFloat(1000), CGFloat(680)),
              (CGFloat(800), CGFloat(1400), CGFloat(600)),   // 75 % of the width
              (CGFloat(700), CGFloat(420), CGFloat(360)),    // never shorter than the floor
          ])
    func heightFollowsWidthAndWindow(width: CGFloat, window: CGFloat, expected: CGFloat) {
        let layout = AppleMacHeroLayout(contentWidth: width, windowHeight: window, topInset: 52)
        #expect(layout.height == expected)
    }

    @Test("The first row peeks: the hero never fills more than 75 % of the window")
    func firstRowPeeks() {
        for width in stride(from: CGFloat(900), through: 2400, by: 150) {
            for window in stride(from: CGFloat(600), through: 1400, by: 100) {
                let layout = AppleMacHeroLayout(contentWidth: width, windowHeight: window)
                #expect(layout.height <= window * 0.75 + 0.5)
                #expect(layout.height <= AppleMacHeroLayout.maximumHeight)
            }
        }
    }

    @Test("Before the window is measured the hero keeps a sensible height")
    func unmeasured() {
        #expect(AppleMacHeroLayout().height == AppleMacHeroLayout.minimumHeight)
    }

    @Test("The copy inset grows from 24 to 48 pt with the width")
    func copyInset() {
        #expect(AppleMacHeroLayout(contentWidth: 800).horizontalPadding == 24)
        #expect(AppleMacHeroLayout(contentWidth: 1250).horizontalPadding == 36)
        #expect(AppleMacHeroLayout(contentWidth: 1600).horizontalPadding == 48)
        #expect(AppleMacHeroLayout(contentWidth: 2400).horizontalPadding == 48)
    }

    @Test("The fallback title is 6 % of the width, between 36 and 72 pt")
    func titleSize() {
        #expect(AppleMacHeroLayout(contentWidth: 500).titleFontSize == 36)
        #expect(AppleMacHeroLayout(contentWidth: 1000).titleFontSize == 60)
        #expect(AppleMacHeroLayout(contentWidth: 1600).titleFontSize == 72)
    }

    @Test("The synopsis shows only when the hero has room for it")
    func synopsisNeedsRoom() {
        #expect(AppleMacHeroLayout(contentWidth: 1200, windowHeight: 800).showsDescription)
        #expect(!AppleMacHeroLayout(contentWidth: 1200, windowHeight: 560).showsDescription)
    }

    @Test("The art is pulled up under the toolbar and past the stack's top padding")
    func pulledUnderToolbar() {
        #expect(AppleMacHeroLayout(contentWidth: 1200, windowHeight: 800, topInset: 52).topOverlap == 68)
    }

    @Test("Both fades are present: left 58 % to clear at 48 %, bottom from the page's black to clear at 34 %")
    func fades() throws {
        let leading = AppleMacHeroFade.leading
        #expect(try #require(leading.first) == .init(location: 0, opacity: 0.58))
        #expect(try #require(leading.last) == .init(location: 0.48, opacity: 0))
        let bottom = AppleMacHeroFade.bottom
        #expect(try #require(bottom.first) == .init(location: 0, opacity: 1))
        #expect(try #require(bottom.last) == .init(location: 0.34, opacity: 0))
        // Stops run in order, so the gradients draw as specified.
        #expect(leading.map(\.location) == leading.map(\.location).sorted())
        #expect(bottom.map(\.location) == bottom.map(\.location).sorted())
    }

    @Test("Dots: the active page is the wide capsule, every other page a 7 pt dot")
    func dots() {
        #expect(AppleMacHeroPageDots.size(position: 2, index: 2, count: 5) == CGSize(width: 22, height: 7))
        for position in [0, 1, 3, 4] {
            #expect(AppleMacHeroPageDots.size(position: position, index: 2, count: 5) == CGSize(width: 7, height: 7))
        }
        #expect(AppleMacHeroPageDots.size(position: 5, index: 2, count: 5) == .zero)
        #expect(AppleMacHeroPageDots.size(position: 0, index: 0, count: 0) == .zero)
        #expect(AppleMacHeroPageDots.hitSize > AppleMacHeroPageDots.dotSize)
    }

    @Test("A horizontal swipe turns one page per gesture, either way")
    func swipeTurnsOnePage() {
        var swipe = AppleMacHeroSwipe()
        swipe.begin()
        #expect(swipe.scroll(deltaX: -30, deltaY: 2) == nil)
        #expect(swipe.scroll(deltaX: -40, deltaY: 1) == 1)
        // The rest of the same gesture does nothing.
        #expect(swipe.scroll(deltaX: -200, deltaY: 0) == nil)
        swipe.begin()
        #expect(swipe.scroll(deltaX: 70, deltaY: 5) == -1)
    }

    @Test("Vertical scrolling over the hero never turns a page")
    func verticalScrollPassesThrough() {
        var swipe = AppleMacHeroSwipe()
        swipe.begin()
        for _ in 0 ..< 20 {
            #expect(swipe.scroll(deltaX: 10, deltaY: -40) == nil)
        }
    }

    @Test("The Mac trailer may play sound; every other trailer page stays muted")
    func macTrailerAllowsSound() throws {
        let embed = try #require(URL(string: "https://fixture.example/embed/trailer"))
        let mac = AppleYouTubePreviewHTML.document(embedURL: embed, startsPlaying: true, isLandscape: true,
                                                   startsMuted: true, allowsSound: true)
        #expect(mac.contains("const requiresMutedPlayback = false;"))
        #expect(mac.contains("mute=1"))
        let other = AppleYouTubePreviewHTML.document(embedURL: embed, startsPlaying: true, startsMuted: false)
        #expect(other.contains("const requiresMutedPlayback = true;"))
    }

    #if DEBUG && os(macOS)
    @Test("-OpenStreamSnapshotWindow takes an absolute PNG path and waits 12 s by default")
    func snapshotWindowArgument() throws {
        let request = try #require(AppleMacWindowShot.request(
            arguments: ["OpenStream", "-OpenStreamSnapshotWindow", "/tmp/fixture/mac-after.png",
                        "-OpenStreamWindowShotSize", "1600x1000"]))
        #expect(request.destination?.path == "/tmp/fixture/mac-after.png")
        #expect(request.delay == 12)
        #expect(request.size == CGSize(width: 1600, height: 1000))
        #expect(AppleMacWindowShot.request(arguments: ["OpenStream", "-OpenStreamSnapshotWindow", "relative.png"]) == nil)
        #expect(AppleMacWindowShot.request(arguments: ["OpenStream", "-OpenStreamSnapshotWindow", "/tmp/shot.txt"]) == nil)
    }
    #endif
}
