import Foundation
import Testing
@testable import OpenStreamApple

@Suite struct AppleTop10TitleMatchTests {
    @MainActor @Test func rankingArticleDifferenceResolvesRealArtwork() async throws {
        let client = AppleStremioCatalogClient { request in
            let data = Data(#"{"metas":[{"id":"tt1234567","type":"movie","name":"Seemingly Perfect Family","poster":"https://fixture.example/poster.jpg"},{"id":"tt7654321","type":"movie","name":"The Perfect Family"}]}"#.utf8)
            return (data, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        let match = try #require(await AppleTop10ArtworkLookup.find(
            title: "The Seemingly Perfect Family", type: "movie", seasonTitle: nil, sources: [], client: client))
        #expect(match.item.mediaID == "tt1234567")
        #expect(match.item.posterURL == URL(string: "https://fixture.example/poster.jpg"))
    }

    @MainActor @Test func coldSearchDeadlineGetsOneFreshAttempt() async throws {
        let attempts = Top10TitleSearchAttempts()
        let client = AppleStremioCatalogClient { request in
            if await attempts.next() == 1 { try await Task.sleep(for: .seconds(5)) }
            let data = Data(#"{"metas":[{"id":"tt1234567","type":"movie","name":"A Film","poster":"https://fixture.example/poster.jpg"}]}"#.utf8)
            return (data, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        let match = await AppleTop10ArtworkLookup.find(title: "A Film", type: "movie", seasonTitle: nil,
            sources: [], client: client, deadline: .milliseconds(20), retryDeadline: .seconds(1))
        #expect(match?.item.mediaID == "tt1234567")
        #expect(await attempts.count == 2)
    }

    @Test func exactMatchWinsOverArticleVariant() {
        let lookup = lookup([("tt1234567", "Perfect Family"), ("tt7654321", "The Perfect Family")])
        #expect(lookup.match(title: "The Perfect Family", type: "movie", ignoringLeadingArticle: true)?.item.mediaID == "tt7654321")
    }

    @Test func ambiguousArticleVariantsStayUnresolved() {
        let lookup = lookup([("tt1234567", "A Perfect Family"), ("tt7654321", "The Perfect Family")])
        #expect(lookup.match(title: "Perfect Family", type: "movie", ignoringLeadingArticle: true) == nil)
    }

    @Test func matchingDoesNotDropMeaningfulWordsOrCrossMediaTypes() {
        let lookup = lookup([("tt1234567", "Perfect Family")])
        #expect(lookup.match(title: "The Seemingly Perfect Family", type: "movie", ignoringLeadingArticle: true) == nil)
        #expect(lookup.match(title: "The Perfect Family", type: "series", ignoringLeadingArticle: true) == nil)
        #expect(lookup.match(title: "The Perfect Family", type: "movie") == nil)
    }

    private func lookup(_ titles: [(String, String)]) -> AppleCatalogSearchLookup {
        let catalog = AppleStremioCatalog(type: "movie", id: "top")
        let source = AppleSource(kind: .stremio, name: "Fixture", url: URL(string: "https://fixture.example/manifest.json")!,
                                 resources: ["catalog"], catalogs: [catalog])
        let items = titles.map { AppleCatalogItem(mediaID: $0.0, type: "movie", name: $0.1) }
        return AppleCatalogSearchLookup(sections: [.init(source: source, catalog: catalog, items: items)], sources: [source])
    }
}

private actor Top10TitleSearchAttempts {
    private(set) var count = 0
    func next() -> Int { count += 1; return count }
}
