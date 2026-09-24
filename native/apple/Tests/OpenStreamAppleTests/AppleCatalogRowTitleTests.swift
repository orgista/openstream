import Foundation
import Testing
@testable import OpenStreamApple

/// Discover's row headings (owner, 2026-09-24: "Prime Video" drew twice, once
/// as "Prime  Video"; he wants "Prime Movies" and "Prime Shows").
@Suite("Catalog row titles")
struct AppleCatalogRowTitleTests {
    private let source = AppleSource(kind: .stremio, name: "Streaming Catalogs",
                                     url: URL(string: "https://fixture.example/manifest.json")!)

    private func section(_ id: String, _ type: String, _ name: String?, source: AppleSource? = nil) -> AppleCatalogSection {
        AppleCatalogSection(source: source ?? self.source,
                            catalog: AppleStremioCatalog(type: type, id: id, name: name),
                            items: [AppleCatalogItem(mediaID: "tt0000001", type: type, name: "Fixture")])
    }

    @Test("A service's movie catalog reads \"<Service> Movies\"", arguments: [
        ("amp", "Prime  Video", "Prime Movies"),
        ("nfx", "Netflix", "Netflix Movies"),
        ("dnp", "Disney+", "Disney+ Movies"),
        ("streaming.hbm", "HBO Max", "HBO Max Movies"),
    ])
    func movieCatalogs(id: String, name: String, expected: String) {
        #expect(AppleCatalogShelfPolicy.title(for: AppleStremioCatalog(type: "movie", id: id, name: name)) == expected)
    }

    @Test("A service's series catalog reads \"<Service> Shows\"", arguments: [
        ("amp", "Prime Video", "Prime Shows"),
        ("atp", "Apple TV+", "Apple TV+ Shows"),
        ("streaming.amp", "Prime Video", "Prime Shows"),
    ])
    func seriesCatalogs(id: String, name: String, expected: String) {
        #expect(AppleCatalogShelfPolicy.title(for: AppleStremioCatalog(type: "series", id: id, name: name)) == expected)
    }

    @Test func serviceIsKnownByNameWhenTheIDIsNot() {
        #expect(AppleCatalogShelfPolicy.title(for: AppleStremioCatalog(type: "movie", id: "custom-1", name: "Prime Video")) == "Prime Movies")
        #expect(AppleCatalogShelfPolicy.title(for: AppleStremioCatalog(type: "series", id: "custom-2", name: " netflix ")) == "Netflix Shows")
    }

    @Test func otherCatalogsKeepTheirNameWithWhitespaceCollapsed() {
        #expect(AppleCatalogShelfPolicy.title(for: AppleStremioCatalog(type: "movie", id: "top", name: "Popular")) == "Popular")
        #expect(AppleCatalogShelfPolicy.title(for: AppleStremioCatalog(type: "series", id: "disney", name: "Top 10  Disney+")) == "Top 10 Disney+")
        #expect(AppleCatalogShelfPolicy.title(for: AppleStremioCatalog(type: "movie", id: "netflix-top10-us", name: "Netflix Top 10 US")) == "Netflix Top 10 US")
        #expect(AppleCatalogShelfPolicy.title(for: AppleStremioCatalog(type: "movie", id: "x", name: "New\t Releases\n")) == "New Releases")
    }

    @Test func streamingCatalogsManifestDrawsTwoDistinctPrimeRows() throws {
        let sections = [section("amp", "movie", "Prime  Video"), section("amp", "series", "Prime Video")]
        let visible = AppleCatalogShelfPolicy.visibleSections(sections, activeSourceIDs: [source.id])
        #expect(visible.map(\.shelfTitle) == ["Prime Movies", "Prime Shows"])
    }

    @Test func noTwoRowsEverShareATitle() {
        let other = AppleSource(kind: .stremio, name: "TMDB", url: URL(string: "https://fixture.example/tmdb/manifest.json")!)
        let sections = [
            section("amp", "movie", "Prime Video"),
            section("streaming.amp", "movie", "Prime Video", source: other),
            section("amp", "series", "Prime Video"),
            section("top", "movie", "Popular"),
            section("top", "series", "Popular"),
            section("top", "movie", "Popular", source: other),
        ]
        let visible = AppleCatalogShelfPolicy.visibleSections(sections, activeSourceIDs: [source.id, other.id])
        let titles = visible.compactMap(\.shelfTitle)
        #expect(titles.count == visible.count)
        #expect(Set(titles.map { $0.lowercased() }).count == titles.count)
        #expect(titles == ["Popular Movies", "Popular Shows", "Prime Movies", "Prime Shows"])
    }

    @Test func typedTitleSwapsAnExistingTypeWord() {
        #expect(AppleCatalogShelfPolicy.typedTitle("Popular Movies", type: "series") == "Popular Shows")
        #expect(AppleCatalogShelfPolicy.typedTitle("Trending", type: "movie") == "Trending Movies")
        #expect(AppleCatalogShelfPolicy.typedTitle("Trending", type: "channel") == "Trending")
    }
}
