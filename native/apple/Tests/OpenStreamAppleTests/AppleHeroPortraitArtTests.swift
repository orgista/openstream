import CoreGraphics
import Foundation
import Testing
@testable import OpenStreamApple

/// Owner items 6 and 19 (2026-10-09): the iPhone's portrait hero picks its
/// art in a fixed order, before it draws, and never shows the title twice.
@Suite struct AppleHeroPortraitArtTests {
    @Test func facesBeatSaliencyAndTheLargestFaceHasDoubleWeight() {
        let point = AppleHeroFocalPoint.choose(faces: [
            CGRect(x: 0, y: 0.6, width: 0.2, height: 0.2),
            CGRect(x: 0.6, y: 0.2, width: 0.4, height: 0.4)
        ], salientRegions: [CGRect(x: 0, y: 0, width: 0.1, height: 0.1)])
        #expect(abs(point.x - 1.7 / 3) < 0.001)
        #expect(abs(point.y - 0.5) < 0.001)
        #expect(AppleHeroFocalPoint.choose(faces: [], salientRegions: []) == CGPoint(x: 0.5, y: 0.5))
        let saliency = AppleHeroFocalPoint.choose(faces: [], salientRegions: [
            CGRect(x: 0.1, y: 0.6, width: 0.2, height: 0.2)
        ])
        #expect(abs(saliency.x - 0.2) < 0.001 && abs(saliency.y - 0.3) < 0.001)
    }

    @Test func subjectCropPositionsTheSubjectAndClampsToImageEdges() {
        let frame = CGSize(width: 400, height: 500)
        for focal in [CGPoint(x: 0, y: 0), CGPoint(x: 0.8, y: 0.3), CGPoint(x: 1, y: 1)] {
            let rect = AppleHeroPortraitArt.fillRect(imageSize: CGSize(width: 1280, height: 720),
                in: frame, focal: focal, subjectAnchor: CGPoint(x: 0.5, y: 0.4))
            #expect(rect.minX <= 0 && rect.maxX >= frame.width - 0.001)
            #expect(rect.minY <= 0 && rect.maxY >= frame.height - 0.001)
        }
        let rect = AppleHeroPortraitArt.fillRect(imageSize: CGSize(width: 1280, height: 720),
            in: frame, focal: CGPoint(x: 0.5, y: 0.4), subjectAnchor: CGPoint(x: 0.5, y: 0.4))
        #expect(abs(rect.midX - frame.width / 2) < 0.001)
    }

    @Test func focalPointIsLoadedFromTheHashedArtworkCacheBeforeDetection() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = AppleArtworkDiskCache(directory: directory)
        let url = URL(string: "https://fixture.example/artwork.jpg")!
        await cache.store(try JSONEncoder().encode([0.2, 0.7]), for: url, variant: "focal-v1")
        let context = try #require(CGContext(data: nil, width: 2, height: 2, bitsPerComponent: 8,
            bytesPerRow: 8, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let image = try #require(context.makeImage())
        let detector = AppleHeroFocalPoint(cache: cache)
        #expect(try await detector.point(image: image, url: url) == CGPoint(x: 0.2, y: 0.7))
        let uncachedURL = URL(string: "https://fixture.example/blank.jpg")!
        let detected = try await detector.point(image: image, url: uncachedURL)
        #expect(detected.x.isFinite && (0...1).contains(detected.x))
        #expect(detected.y.isFinite && (0...1).contains(detected.y))
        #expect(await cache.contains(url: uncachedURL, variant: "focal-v1"))
        #expect(try await detector.point(image: image, url: uncachedURL) == detected)
    }

    private let textlessPoster = URL(string: "https://fixture.example/poster-null.jpg")!
    private let poster = URL(string: "https://fixture.example/poster-en.jpg")!
    private let textlessBackdrop = URL(string: "https://fixture.example/backdrop-null.jpg")!
    private let backdrop = URL(string: "https://fixture.example/backdrop.jpg")!
    private let logo = URL(string: "https://fixture.example/logo.png")!

    private var all: AppleHeroPortraitArt.Candidates {
        .init(textlessPoster: textlessPoster, poster: poster, textlessBackdrop: textlessBackdrop,
              backdrop: backdrop, logo: logo)
    }

    @Test func theTextlessPosterComesFirst() {
        #expect(AppleHeroPortraitArt.choose(all) == .keyArt(textlessPoster))
        #expect(AppleHeroPortraitArt.choose(all).source == .poster)
    }

    @Test func withoutATextlessPosterTheTextlessBackdropWins() {
        var candidates = all
        candidates.textlessPoster = nil
        #expect(AppleHeroPortraitArt.choose(candidates) == .backdrop(textlessBackdrop))
    }

    @Test func aTextlessBackdropBeatsATitledPoster() {
        let candidates = AppleHeroPortraitArt.Candidates(poster: poster, textlessBackdrop: textlessBackdrop,
                                                         backdrop: backdrop, logo: logo)
        let art = AppleHeroPortraitArt.choose(candidates)
        #expect(art == .backdrop(textlessBackdrop))
        #expect(art.showsTitle)
    }

    /// Lead review 2026-10-14: the item's own backdrop may carry the title
    /// ("SOU…" cut off, then the wordmark again under it), so it is never
    /// aspect-filled; with only titled art the hero is the card, no title.
    @Test(arguments: [
        AppleHeroPortraitArt.Candidates(poster: URL(string: "https://fixture.example/poster-en.jpg")!,
                                        backdrop: URL(string: "https://fixture.example/backdrop.jpg")!,
                                        logo: URL(string: "https://fixture.example/logo.png")!),
        AppleHeroPortraitArt.Candidates(poster: URL(string: "https://fixture.example/poster-en.jpg")!),
    ])
    func titledArtOnlyIsTheCardWithNoTitle(_ candidates: AppleHeroPortraitArt.Candidates) {
        let art = AppleHeroPortraitArt.choose(candidates)
        #expect(art == .posterCard(poster))
        #expect(!art.showsTitle)
    }

    @Test func aTitledBackdropAloneIsACardNeverACrop() {
        let art = AppleHeroPortraitArt.choose(.init(backdrop: backdrop, logo: logo))
        #expect(art == .posterCard(backdrop))
        #expect(!art.showsTitle)
    }

    @Test func aTitledPosterIsTheLastResortCard() {
        let candidates = AppleHeroPortraitArt.Candidates(poster: poster, logo: logo)
        let art = AppleHeroPortraitArt.choose(candidates)
        #expect(art == .posterCard(poster))
        #expect(art.source == .fallback)
    }

    @Test func nothingAtAllIsNone() {
        #expect(AppleHeroPortraitArt.choose(.init()) == AppleHeroPortraitArt.none)
        #expect(AppleHeroPortraitArt.none.imageURL == nil)
    }

    @Test func aFailedImageMovesToTheNextKind() {
        #expect(AppleHeroPortraitArt.choose(all, failed: [textlessPoster]) == .backdrop(textlessBackdrop))
        #expect(AppleHeroPortraitArt.choose(all, failed: [textlessPoster, textlessBackdrop]) == .posterCard(poster))
        #expect(AppleHeroPortraitArt.choose(all, failed: [textlessPoster, textlessBackdrop, poster]) == .posterCard(backdrop))
        #expect(AppleHeroPortraitArt.choose(all, failed: [textlessPoster, textlessBackdrop, poster, backdrop])
                == AppleHeroPortraitArt.none)
    }

    // MARK: Title suppression

    @Test func aTitledPosterSuppressesTheTextTitleAndWordmark() {
        #expect(AppleHeroPortraitArt.posterCard(poster).showsTitle == false)
    }

    @Test func textlessArtKeepsTheTitle() {
        #expect(AppleHeroPortraitArt.keyArt(textlessPoster).showsTitle)
        #expect(AppleHeroPortraitArt.backdrop(backdrop).showsTitle)
        #expect(AppleHeroPortraitArt.none.showsTitle)
    }

    // MARK: Server and IPTV items map onto the same order

    @Test func aMediaServerItemsOwnArtCountsAsTitled() {
        // Jellyfin Primary → posterURL, Backdrop → backgroundURL, Logo → logoURL.
        let item = AppleCatalogItem(mediaID: "jellyfin:abc", type: "movie", name: "Server Film",
                                    posterURL: poster, backgroundURL: backdrop, logoURL: logo)
        let candidates = AppleHeroPortraitArt.Candidates(item: item)
        #expect(candidates.logo == logo)
        #expect(AppleHeroPortraitArt.choose(candidates) == .posterCard(poster))
    }

    @Test func tmdbsTextlessBackdropBeatsTheItemsOwnArt() {
        let item = AppleCatalogItem(mediaID: "tt0000002", type: "movie", name: "Film",
                                    posterURL: poster, backgroundURL: backdrop)
        let candidates = AppleHeroPortraitArt.Candidates(item: item, tmdbBackdrop: textlessBackdrop, tmdbLogo: logo)
        #expect(AppleHeroPortraitArt.choose(candidates) == .backdrop(textlessBackdrop))
    }

    @Test func anIPTVItemWithOnlyItsIconGetsTheCardWithNoTextTitle() {
        let item = AppleCatalogItem(mediaID: "xtream:1:vod:2", type: "movie", name: "IPTV Film", posterURL: poster)
        let art = AppleHeroPortraitArt.choose(.init(item: item))
        #expect(art == .posterCard(poster))
        #expect(!art.showsTitle)
    }

    @Test func tmdbArtTakesPrecedenceOverTheItemsOwn() {
        let item = AppleCatalogItem(mediaID: "tt0000001", type: "movie", name: "Film",
                                    posterURL: poster, backgroundURL: backdrop)
        let candidates = AppleHeroPortraitArt.Candidates(item: item, tmdbPoster: textlessPoster, tmdbLogo: logo)
        #expect(AppleHeroPortraitArt.choose(candidates) == .keyArt(textlessPoster))
        #expect(candidates.logo == logo)
    }


    // MARK: Crop

    @Test func aPosterIsCroppedWithTheTopBias() {
        // A 2:3 poster in 430 × 538: 645 pt tall, 107 pt to lose.
        let rect = AppleHeroPortraitArt.fillRect(imageSize: CGSize(width: 780, height: 1170),
                                                 in: CGSize(width: 430, height: 538))
        #expect(abs(rect.width - 430) < 0.5)
        #expect(abs(rect.height - 645) < 0.5)
        #expect(abs(rect.minY - (-107 * 0.35)) < 0.5)
        #expect(abs(rect.minX) < 0.5)
    }

    @Test func aBackdropIsCentredAcrossAndFillsTheHeight() {
        let rect = AppleHeroPortraitArt.fillRect(imageSize: CGSize(width: 1280, height: 720),
                                                 in: CGSize(width: 430, height: 538))
        #expect(abs(rect.height - 538) < 0.5)
        #expect(rect.minY == 0)
        #expect(abs(rect.midX - 215) < 0.5)
    }

    @Test func theCropNeverLeavesAGap() {
        for focal in [CGPoint(x: -1, y: -1), CGPoint(x: 2, y: 2), CGPoint(x: 0, y: 1)] {
            let rect = AppleHeroPortraitArt.fillRect(imageSize: CGSize(width: 1000, height: 1500),
                                                     in: CGSize(width: 375, height: 469), focal: focal)
            #expect(rect.minX <= 0 && rect.maxX >= 375 - 0.001)
            #expect(rect.minY <= 0 && rect.maxY >= 469 - 0.001)
        }
    }

    // MARK: Geometry

    /// Owner 2026-10-14: full-bleed again, as 0d100ce had it: from the top
    /// edge to 73 % of the screen, held so ≥ 90 pt of the first row peeks
    /// above the tab bar. The width no longer sets the height.
    @Test(arguments: [
        // iPhone SE (3rd gen): 667 pt, 49 pt tab bar: the peek clamp wins.
        (AppleHomePhoneHeroLayout(containerHeight: 667, topInset: 116, bottomInset: 49), CGFloat(466)),
        // iPhone 16e: 844 pt, 83 pt tab bar: the peek clamp wins.
        (AppleHomePhoneHeroLayout(containerHeight: 844, topInset: 143, bottomInset: 83), CGFloat(609)),
        // iPhone 15 Pro Max: 932 pt: 73 % of the screen.
        (AppleHomePhoneHeroLayout(containerHeight: 932, topInset: 155, bottomInset: 83), CGFloat(932 * 0.73)),
    ])
    func thePhoneArtIsFullBleed(_ layout: AppleHomePhoneHeroLayout, expected: CGFloat) {
        #expect(abs(layout.artHeight - expected) < 0.5)
        let peek = layout.containerHeight - layout.bottomInset - layout.artHeight - AppleHomePhoneHeroLayout.firstRowLead
        #expect(peek >= AppleHomePhoneHeroLayout.minimumRowPeek - 0.001)
        #expect(layout.topOverlap == layout.topInset + AppleHomePhoneHeroLayout.stackTopPadding)
    }

    @Test func aPosterFillsTheTallFrameCentredAcross() {
        // A 2:3 poster in 430 × 680 (15 Pro Max): it fills the height and
        // loses 23 pt across, centred; nothing is lost top or bottom.
        let rect = AppleHeroPortraitArt.fillRect(imageSize: CGSize(width: 780, height: 1170),
                                                 in: CGSize(width: 430, height: 680))
        #expect(abs(rect.height - 680) < 0.5)
        #expect(abs(rect.width - 453.3) < 0.5)
        #expect(abs(rect.midX - 215) < 0.5)
        #expect(rect.minY == 0)
    }

    @Test func aPosterKeepsItsTopBiasInTheShortSEFrame() {
        // The same poster in 375 × 466 (iPhone SE): it fills the width and
        // 96.5 pt are cropped, 35 % of them from the top (`focalPoint`).
        let rect = AppleHeroPortraitArt.fillRect(imageSize: CGSize(width: 780, height: 1170),
                                                 in: CGSize(width: 375, height: 466))
        #expect(abs(rect.width - 375) < 0.5)
        #expect(abs(rect.height - 562.5) < 0.5)
        #expect(rect.minX == 0)
        #expect(abs(rect.minY - -(562.5 - 466) * AppleHeroPortraitArt.focalPoint.y) < 0.5)
    }

    @Test func theTrailerCoverIsDrawnTopEdgeUp() throws {
        // A 1 × 4 image, three red rows over one blue, drawn four times its
        // frame's height from the top: only red lands in the frame (the blue
        // edge is far enough below it that smoothing cannot reach it).
        let red: [UInt8] = [255, 0, 0, 255], blue: [UInt8] = [0, 0, 255, 255]
        let pixels = red + red + red + blue // RGBA, top row first
        let provider = try #require(CGDataProvider(data: Data(pixels) as CFData))
        let image = try #require(CGImage(width: 1, height: 4, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 4,
                                         space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                         bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                                         provider: provider, decode: nil, shouldInterpolate: false,
                                         intent: .defaultIntent))
        let cover = try #require(AppleHeroPortraitCover.draw(image, in: CGRect(x: 0, y: 0, width: 4, height: 16),
                                                             frame: CGSize(width: 4, height: 4), scale: 2))
        #expect(cover.width == 8 && cover.height == 8)
        let data = try #require(cover.dataProvider?.data as Data?)
        for row in [0, cover.height - 1] {
            let pixel = data.subdata(in: (row * cover.bytesPerRow)..<(row * cover.bytesPerRow + 4))
            // BGRX, little-endian: red is the third byte.
            #expect(pixel[pixel.startIndex + 2] > 200 && pixel[pixel.startIndex] < 50, "row \(row)")
        }
    }

    @Test(arguments: [
        (CGSize(width: 375, height: 466), CGFloat(116)),
        (CGSize(width: 390, height: 609), CGFloat(143)),
        (CGSize(width: 430, height: 680), CGFloat(155)),
    ])
    func thePosterCardSitsBetweenTheTitleAndTheButtons(_ frame: CGSize, topInset: CGFloat) {
        let card = AppleHeroPortraitArt.posterCardRect(posterAspect: 2.0 / 3.0, in: frame, topInset: topInset)
        #expect(card.minY >= topInset)
        #expect(card.maxY <= frame.height - AppleHeroPortraitArt.posterCardBottomReserve + 0.001)
        #expect(card.width <= frame.width * AppleHeroPortraitArt.posterCardWidthFraction + 0.001)
        #expect(abs(card.midX - frame.width / 2) < 0.001)
        #expect(abs(card.width / card.height - 2.0 / 3.0) < 0.001)
    }

    @Test func aTitledBackdropCardIsWiderAndStillClearOfTheTitleAndButtons() {
        let frame = CGSize(width: 390, height: 609)
        let card = AppleHeroPortraitArt.posterCardRect(posterAspect: 16.0 / 9.0, in: frame, topInset: 143)
        #expect(abs(card.width - frame.width * AppleHeroPortraitArt.landscapeCardWidthFraction) < 0.001)
        #expect(card.minY >= 143)
        #expect(card.maxY <= frame.height - AppleHeroPortraitArt.posterCardBottomReserve + 0.001)
        #expect(abs(card.width / card.height - 16.0 / 9.0) < 0.001)
    }

    /// The owner's iPhone 15 Pro Max on iOS 18 going back to Discover
    /// (trace 2026-10-15 23:50): the bar settles from 115 to 97 pt and back,
    /// with one-frame heights either side of the 931 pt screen.
    @Test func theIOS18BarDoesNotMoveOrResizeTheArt() {
        let readings: [(CGFloat, CGFloat)] = [(945, 115), (936, 102), (931, 97), (932, 98), (924, 98), (924, 105), (929, 113), (931, 115)]
        var drawn = AppleHomePhoneHeroLayout(containerHeight: 931, topInset: 115, bottomInset: 83)
        let resting = drawn
        for (height, top) in readings {
            drawn = AppleHomePhoneHeroLayout.settled(drawn: drawn,
                measured: AppleHomePhoneHeroLayout(containerHeight: height, topInset: top, bottomInset: 83))
        }
        #expect(drawn == resting)
    }

    @Test func theFirstMeasuredReadingIsDrawnAndUnmeasuredOnesAreNot() {
        let unmeasured = AppleHomePhoneHeroLayout(containerHeight: 699)
        let measured = AppleHomePhoneHeroLayout(containerHeight: 965, topInset: 149, bottomInset: 83)
        #expect(AppleHomePhoneHeroLayout.settled(drawn: AppleHomePhoneHeroLayout(), measured: unmeasured) == AppleHomePhoneHeroLayout())
        #expect(AppleHomePhoneHeroLayout.settled(drawn: AppleHomePhoneHeroLayout(), measured: measured) == measured)
    }

    @Test func aTallerBarAtTheSameHeightIsKept() {
        let drawn = AppleHomePhoneHeroLayout(containerHeight: 844, topInset: 101, bottomInset: 83)
        let taller = AppleHomePhoneHeroLayout(containerHeight: 844, topInset: 143, bottomInset: 83)
        #expect(AppleHomePhoneHeroLayout.settled(drawn: drawn, measured: taller).topInset == 143)
    }

    @Test func aPosterCardInAnUnmeasuredFrameIsEmpty() {
        #expect(AppleHeroPortraitArt.posterCardRect(posterAspect: 2.0 / 3.0, in: .zero, topInset: 100) == .zero)
    }
}
