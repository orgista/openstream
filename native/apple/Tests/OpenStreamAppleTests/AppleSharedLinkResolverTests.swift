import Foundation
import Testing
@testable import OpenStreamApple

struct AppleSharedLinkResolverTests {
    @Test(arguments: [
        ("https://www.imdb.com/title/tt1234567/", SharedLink.imdb("tt1234567")),
        ("https://m.imdb.com/title/tt1234567", .imdb("tt1234567")),
        ("https://www.themoviedb.org/movie/123-title", .tmdb(.movie, 123)),
        ("https://themoviedb.org/tv/123", .tmdb(.show, 123)),
    ])
    func supported(value: (String, SharedLink)) throws {
        #expect(AppleSharedLinkResolver.parse(try #require(URL(string: value.0))) == value.1)
    }

    @Test(arguments: ["https://imdb.com.evil.test/title/tt123", "file:///title/tt123", "https://user:password@imdb.com/title/tt123",
                      "https://imdb.com/title/ttbad", "https://themoviedb.org/movie/0", "https://imdb.com:8443/title/tt123",
                      "https://www.netflix.com/title/973331", "https://tv.apple.com/us/movie/mayday/umc.cmc.abc",
                      "https://youtu.be/3iRUwVzRDZQ", "https://trakt.tv/movies/mayday-2021", "https://letterboxd.com/film/mayday/"])
    func rejectsEverythingElse(value: String) throws {
        #expect(AppleSharedLinkResolver.parse(try #require(URL(string: value))) == nil)
    }

    @Test func deepLink() throws {
        var components = try #require(URLComponents(string: "openstream://open"))
        components.queryItems = [.init(name: "url", value: "https://www.imdb.com/title/tt1234567/?ref_=share")]
        #expect(AppleAppRoute(url: try #require(components.url)) == .sharedLink(.imdb("tt1234567")))
        #expect(AppleAppRoute(url: try #require(URL(string: "openstream://open?url=https%3A%2F%2Fevil.test"))) == nil)
    }

    @Test func extractsOneLinkFromSharedText() throws {
        #expect(AppleSharedLinkResolver.link(in: "Watch this https://www.imdb.com/title/tt1234567/") == .imdb("tt1234567"))
        #expect(AppleSharedLinkResolver.link(in: "https://imdb.com/title/tt1 https://themoviedb.org/tv/2") == nil)
    }

    @Test func handoffAcceptsOnlyTitleSites() throws {
        #expect(AppleSharedLinkHandoff.deepLink(for: try #require(URL(string: "https://www.imdb.com/title/tt1234567/"))) != nil)
        #expect(AppleSharedLinkHandoff.deepLink(for: try #require(URL(string: "https://www.netflix.com/title/973331"))) == nil)
        #expect(AppleSharedLinkHandoff.deepLink(for: try #require(URL(string: "file:///tmp/movie"))) == nil)
    }

    @Test @MainActor func imdbIdentifierOpensTheViewersOwnTitle() async throws {
        let record = AppleMediaRecord(canonicalID: "tt1234567", kind: .series, title: "A Show", availability: [])
        let result = try await AppleSharedLinkResolution.resolve(.imdb("tt1234567"), records: [record], configuration: nil)
        #expect(result.record?.id == record.id)
        #expect(result.item?.type == "series")
    }

    @Test @MainActor func tmdbLinkWithoutAKeyIsUnreadable() async {
        await #expect(throws: AppleSharedLinkError.unreadable) {
            try await AppleSharedLinkResolution.resolve(.tmdb(.movie, 123), records: [], configuration: nil)
        }
    }

    @Test @MainActor func sharedRouteClearsPreviousSearchPrefill() {
        let router = AppleAppRouter()
        router.showSearch("Dune")
        router.open(.sharedLink(.imdb("tt1234567")))
        #expect(router.searchQuery.isEmpty)
        #expect(AppleSearchRoutePolicy.discoverShowsSearch(for: .sharedLink(.imdb("tt1234567")), hasDedicatedSearchTab: false))
    }
}
