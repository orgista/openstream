import CoreGraphics
import Testing
@testable import OpenStreamApple

/// N44: the Mac hero's trailer is drawn at its art's own geometry — the same
/// aspect-fill scale about the same centre — so the crossfade from the art
/// to the trailer never reads as a zoom, in a window or full screen.
@Suite("Mac hero: the trailer keeps the art's geometry")
struct AppleMacHeroArtMatchedTrailerTests {
    /// A 1440 pt window, a 1100 pt one, the owner's 3440 × 1440 display
    /// maximised and full screen, a 3000 × 1200 window, and a narrow one.
    private static let heroes: [CGSize] = [
        CGSize(width: 1_440, height: 675), CGSize(width: 1_100, height: 570),
        CGSize(width: 3_440, height: 680), CGSize(width: 3_000, height: 680),
        CGSize(width: 900, height: 600),
    ]
    private static let backdrop = CGSize(width: 1_920, height: 1_080)

    private func isClose(_ a: CGRect, _ b: CGRect, within tolerance: CGFloat = 0.001) -> Bool {
        abs(a.minX - b.minX) < tolerance && abs(a.minY - b.minY) < tolerance
            && abs(a.width - b.width) < tolerance && abs(a.height - b.height) < tolerance
    }

    @Test("Over a 16:9 still the trailer's raster is exactly the still's rect", arguments: heroes)
    func sameRectAsTheArt(hero: CGSize) {
        let art = AppleTrailerPreviewLayout.aspectFillFrame(of: Self.backdrop, in: hero)
        let trailer = AppleTrailerPreviewLayout.artMatchedFrame(in: hero, art: Self.backdrop)
        #expect(isClose(trailer, art))
    }

    @Test("Art and trailer show the same part of themselves: no zoom, no shift", arguments: heroes)
    func sameCrop(hero: CGSize) {
        let viewport = CGRect(origin: .zero, size: hero)
        let art = AppleTrailerPreviewLayout.aspectFillFrame(of: Self.backdrop, in: hero)
        let trailer = AppleTrailerPreviewLayout.artMatchedFrame(in: hero, art: Self.backdrop)
        let artCrop = AppleMacHeroCrop.visibleFraction(of: art, through: viewport)
        let trailerCrop = AppleMacHeroCrop.visibleFraction(of: trailer, through: viewport)
        #expect(isClose(artCrop, trailerCrop))
    }

    /// The probe's 1440 pt window: Project Hail Mary's picture band is 75 %
    /// of its raster. Covering the hero with the band drew it 1.111× the art.
    @Test("A letterboxed trailer is not enlarged to crop its mattes")
    func letterboxedIsNotEnlarged() {
        let hero = CGSize(width: 1_440, height: 675)
        let bandFraction: CGFloat = 0.75
        let art = AppleTrailerPreviewLayout.aspectFillFrame(of: Self.backdrop, in: hero)
        let bandCovering = hero.height / bandFraction
        #expect(bandCovering / art.height > 1.1)
        let trailer = AppleTrailerPreviewLayout.artMatchedFrame(in: hero, art: Self.backdrop)
        #expect(abs(trailer.height / art.height - 1) < 0.0001)
    }

    @Test("Over a still that is not 16:9 the trailer covers the still, centred on it",
          arguments: [CGSize(width: 2_000, height: 1_000), CGSize(width: 1_600, height: 1_200),
                      CGSize(width: 1_850, height: 1_000)])
    func coversOtherStills(still: CGSize) {
        for hero in Self.heroes {
            let art = AppleTrailerPreviewLayout.aspectFillFrame(of: still, in: hero)
            let trailer = AppleTrailerPreviewLayout.artMatchedFrame(in: hero, art: still)
            #expect(abs(trailer.width / trailer.height - 16.0 / 9.0) < 0.0001)
            #expect(trailer.minX <= art.minX + 0.001 && trailer.maxX >= art.maxX - 0.001)
            #expect(trailer.minY <= art.minY + 0.001 && trailer.maxY >= art.maxY - 0.001)
            #expect(abs(trailer.midX - art.midX) < 0.001 && abs(trailer.midY - art.midY) < 0.001)
            // Matches the still along one side, so it is no larger than it must be.
            #expect(abs(trailer.width - art.width) < 0.001 || abs(trailer.height - art.height) < 0.001)
        }
    }

    @Test("Before the still has decoded it is drawn as a 16:9 still would be", arguments: heroes)
    func noStillYet(hero: CGSize) {
        let trailer = AppleTrailerPreviewLayout.artMatchedFrame(in: hero, art: nil)
        #expect(isClose(trailer, AppleTrailerPreviewLayout.coverFrame(in: hero)))
        #expect(isClose(trailer, AppleTrailerPreviewLayout.aspectFillFrame(of: Self.backdrop, in: hero)))
    }

    @Test("The visible fraction of a picture through the hero")
    func visibleFraction() {
        let hero = CGRect(x: 0, y: 0, width: 1_440, height: 675)
        #expect(AppleMacHeroCrop.visibleFraction(of: hero, through: hero) == CGRect(x: 0, y: 0, width: 1, height: 1))
        let drawn = CGRect(x: 0, y: -67.5, width: 1_440, height: 810)
        let crop = AppleMacHeroCrop.visibleFraction(of: drawn, through: hero)
        #expect(abs(crop.minY - 67.5 / 810) < 0.0001 && abs(crop.height - 675 / 810) < 0.0001)
        #expect(AppleMacHeroCrop.visibleFraction(of: .zero, through: hero) == .zero)
    }
}

@Suite("Hero art luminance: a centred still")
struct AppleHeroArtLuminanceAnchorTests {
    /// 16:9, dark except its middle third of rows.
    private let map = AppleHeroLuminanceMap(
        columns: 16, rows: 9,
        values: (0 ..< 9).flatMap { row in [Float](repeating: (3 ..< 6).contains(row) ? 0.9 : 0.01, count: 16) },
        aspectRatio: 16.0 / 9.0)

    @Test("Pinned top-leading, a wide hero reads the art's top; centred, its middle")
    func anchorMovesTheReading() throws {
        // A 1600 × 300 hero draws the art 1600 × 900: rows 0–300 pinned at
        // the top, rows 300–600 centred.
        let frame = CGSize(width: 1_600, height: 300)
        let region = CGRect(x: 100, y: 100, width: 400, height: 100)
        let top = try #require(map.reading(region: region, in: frame))
        let centred = try #require(map.reading(region: region, in: frame, anchor: CGPoint(x: 0.5, y: 0.5)))
        #expect(AppleHeroArtTone(reading: top) == .dark)
        #expect(AppleHeroArtTone(reading: centred) == .bright)
    }

    @Test("A still with no overhang reads the same either way")
    func noOverhang() {
        let frame = CGSize(width: 1_600, height: 900)
        let region = CGRect(x: 40, y: 400, width: 480, height: 200)
        #expect(map.reading(region: region, in: frame) == map.reading(region: region, in: frame, anchor: CGPoint(x: 0.5, y: 0.5)))
    }
}
