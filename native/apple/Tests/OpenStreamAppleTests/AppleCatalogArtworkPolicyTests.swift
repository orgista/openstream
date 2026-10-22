import Foundation
import Testing
@testable import OpenStreamApple

struct AppleCatalogArtworkPolicyTests {
    private let backdrop = URL(string: "https://fixture.example/backdrop.jpg")!
    private let poster = URL(string: "https://fixture.example/poster.jpg")!

    @Test func tmdbDisplayRequestWaitsForGeometryBeforeChoosingOneSizedURL() {
        let url = URL(string: "https://image.tmdb.org/t/p/w500/poster.jpg")!
        let pending = AppleCatalogArtworkPolicy.displayRequest(url: url, pixels: .zero, purpose: .poster)
        #expect(pending.url == nil)
        #expect(pending.waitsForGeometry)
        let measured = AppleCatalogArtworkPolicy.displayRequest(url: url, pixels: CGSize(width: 400, height: 600), purpose: .poster)
        #expect(measured.url == URL(string: "https://image.tmdb.org/t/p/w342/poster.jpg"))
        #expect(measured.waitsForGeometry == false)
        #expect(measured.fixedPixelDimension == 513)
    }

    @Test func tmdbResizingWithinBucketKeepsURLAndDecodeIdentityAndCrossingChangesOnce() {
        let url = URL(string: "https://image.tmdb.org/t/p/w500/poster.jpg")!
        let first = AppleCatalogArtworkPolicy.displayRequest(url: url, pixels: CGSize(width: 400, height: 600), purpose: .poster)
        let within = AppleCatalogArtworkPolicy.displayRequest(url: url, pixels: CGSize(width: 420, height: 630), purpose: .poster)
        let crossed = AppleCatalogArtworkPolicy.displayRequest(url: url, pixels: CGSize(width: 440, height: 660), purpose: .poster)
        #expect(first == within)
        #expect(crossed.url == URL(string: "https://image.tmdb.org/t/p/w500/poster.jpg"))
        #expect(crossed.fixedPixelDimension == 750)
        #expect(crossed != first)
    }

    @Test func displayRequestNeverHoldsOrRewritesSignedOrProviderURLs() {
        let urls = [poster, URL(string: "https://image.tmdb.org/t/p/w500/poster.jpg?signature=fixture")!,
                    URL(string: "https://image.tmdb.org/not-an-image.jpg")!]
        for url in urls {
            let pending = AppleCatalogArtworkPolicy.displayRequest(url: url, pixels: .zero, purpose: .poster)
            let measured = AppleCatalogArtworkPolicy.displayRequest(url: url, pixels: CGSize(width: 400, height: 600), purpose: .poster)
            #expect(pending.url == url)
            #expect(pending == measured)
            #expect(pending.waitsForGeometry == false)
            #expect(pending.fixedPixelDimension == nil)
        }
    }

    @Test func metadataTaskMarkerContainsNoCredentialAndChangesWithConfiguration() throws {
        let first = try AppleTMDBConfiguration(credential: "fixture-key-one")
        let second = try AppleTMDBConfiguration(credential: "fixture-key-two")
        let marker = AppleCatalogArtworkPolicy.configurationMarker(first)
        #expect(marker.contains(first.credential) == false)
        #expect(marker == AppleCatalogArtworkPolicy.configurationMarker(first))
        #expect(marker != AppleCatalogArtworkPolicy.configurationMarker(second))
        #expect(AppleCatalogArtworkPolicy.configurationMarker(nil) == "metadata-off")
    }

    @Test func failedBackdropAdvancesToPoster() {
        let item = AppleCatalogItem(mediaID: "tt1234567", type: "movie", name: "Fixture", posterURL: poster, backgroundURL: backdrop)
        let urls = AppleCatalogArtworkPolicy.candidates(item: item, landscape: true)
        #expect(urls == [backdrop, poster])
        #expect(AppleCatalogArtworkPolicy.next(in: urls, failed: [backdrop]) == poster)
        #expect(AppleCatalogArtworkPolicy.next(in: urls, failed: Set(urls)) == nil)
    }

    @Test func posterOnlyLandscapeTileUsesRealArtImmediately() {
        let item = AppleCatalogItem(mediaID: "tt1234567", type: "movie", name: "Fixture", posterURL: poster)
        #expect(AppleCatalogArtworkPolicy.candidates(item: item, landscape: true).first == poster)
    }

    @Test func unknownIdentityDoesNotInventArt() {
        let item = AppleCatalogItem(mediaID: "unresolved-rank-2", type: "movie", name: "Fixture")
        #expect(AppleCatalogArtworkPolicy.candidates(item: item, landscape: true).isEmpty)
    }

    @Test func resolvedLandscapeArtPrecedesPosterFramingButSourceBackdropWins() {
        let item = AppleCatalogItem(mediaID: "tt1234567", type: "movie", name: "Fixture", posterURL: poster)
        let fallback = AppleArtworkResolver.Artwork(posterURL: nil, backgroundURL: backdrop)
        #expect(AppleCatalogArtworkPolicy.candidates(item: item, landscape: true, fallback: fallback).first == backdrop)
        let supplied = AppleCatalogItem(mediaID: "tt1234567", type: "movie", name: "Fixture", posterURL: poster, backgroundURL: poster)
        #expect(AppleCatalogArtworkPolicy.candidates(item: supplied, landscape: true, fallback: fallback).first == poster)
    }

    @Test func logoPurposeKeepsSourceLogoFirstAndNeverUsesPosterAsLogo() {
        let item = AppleCatalogItem(mediaID: "tt1234567", type: "movie", name: "Fixture", posterURL: poster, logoURL: backdrop)
        let fallback = AppleArtworkResolver.Artwork(posterURL: poster, backgroundURL: backdrop, logoURL: poster)
        #expect(AppleCatalogArtworkPolicy.candidates(item: item, purpose: .logo, fallback: fallback) == [backdrop, poster])
        let missing = AppleCatalogItem(mediaID: "tt1234567", type: "movie", name: "Fixture", posterURL: poster)
        #expect(AppleCatalogArtworkPolicy.candidates(item: missing, purpose: .logo).isEmpty)
    }

    @Test func landscapePosterFallbackUsesPosterSizesAndPortraitBackdropFallbackUsesBackdropSizes() {
        let item = AppleCatalogItem(mediaID: "tt1234567", type: "movie", name: "Fixture", posterURL: poster, backgroundURL: backdrop)
        #expect(AppleCatalogArtworkPolicy.purpose(of: poster, item: item, fallback: nil, preferred: .resume) == .poster)
        #expect(AppleCatalogArtworkPolicy.purpose(of: backdrop, item: item, fallback: nil, preferred: .poster) == .resume)
        #expect(AppleCatalogArtworkPolicy.purpose(of: backdrop, item: item, fallback: nil, preferred: .hero) == .hero)
    }

    /// Wonka's The Golden Ticket, Apple TV Top 10 (2026-10-01): a poster and
    /// no backdrop showed the poster's dark top third as a box.
    @Test func aPortraitPosterInASixteenByNineCardIsDrawnWhole() {
        #expect(AppleCatalogArtworkPolicy.framing(landscapeCard: true, imageWidth: 500, imageHeight: 750)
            == .posterInFrame(aspect: 500.0 / 750.0))
    }

    @Test func wideArtAndPosterCardsStillFill() {
        #expect(AppleCatalogArtworkPolicy.framing(landscapeCard: true, imageWidth: 1280, imageHeight: 720) == .fill)
        #expect(AppleCatalogArtworkPolicy.framing(landscapeCard: true, imageWidth: 720, imageHeight: 720) == .fill)
        #expect(AppleCatalogArtworkPolicy.framing(landscapeCard: false, imageWidth: 500, imageHeight: 750) == .fill)
        #expect(AppleCatalogArtworkPolicy.framing(landscapeCard: true, imageWidth: 0, imageHeight: 0) == .fill)
    }
}
