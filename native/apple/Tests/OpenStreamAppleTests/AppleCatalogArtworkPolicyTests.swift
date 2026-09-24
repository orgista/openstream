import Foundation
import Testing
@testable import OpenStreamApple

struct AppleCatalogArtworkPolicyTests {
    private let backdrop = URL(string: "https://fixture.example/backdrop.jpg")!
    private let poster = URL(string: "https://fixture.example/poster.jpg")!

    @Test func failedBackdropAdvancesToPosterThenCinemeta() {
        let item = AppleCatalogItem(mediaID: "tt1234567", type: "movie", name: "Fixture", posterURL: poster, backgroundURL: backdrop)
        let urls = AppleCatalogArtworkPolicy.candidates(item: item, landscape: true)
        #expect(urls.prefix(2) == [backdrop, poster])
        #expect(urls.count == 4)
        #expect(AppleCatalogArtworkPolicy.next(in: urls, failed: [backdrop]) == poster)
        #expect(AppleCatalogArtworkPolicy.next(in: urls, failed: [backdrop, poster]) == urls[2])
        #expect(AppleCatalogArtworkPolicy.next(in: urls, failed: Set(urls.dropLast())) == urls.last)
        #expect(AppleCatalogArtworkPolicy.next(in: urls, failed: Set(urls)) == nil)
    }

    @Test func posterOnlyLandscapeTileUsesRealArtImmediately() {
        let item = AppleCatalogItem(mediaID: "tt1234567", type: "movie", name: "Fixture", posterURL: poster)
        #expect(AppleCatalogArtworkPolicy.candidates(item: item, landscape: true).first == poster)
    }

    @Test func missingArtStillTriesCinemetaForCanonicalID() {
        let item = AppleCatalogItem(mediaID: "tt1234567", type: "movie", name: "Fixture")
        #expect(AppleCatalogArtworkPolicy.candidates(item: item, landscape: true).count == 2)
    }

    @Test func unknownIdentityDoesNotInventArt() {
        let item = AppleCatalogItem(mediaID: "unresolved-rank-2", type: "movie", name: "Fixture")
        #expect(AppleCatalogArtworkPolicy.candidates(item: item, landscape: true).isEmpty)
    }
}
