import Foundation
import Testing
@testable import OpenStreamApple

/// Full test 2026-10-01: "stranger things" listed the 2013 film first, twice
/// (Cinemeta and the TMDB add-on not merged), and the 2016 series third.
@MainActor
@Suite("Search exact-match ranking and IMDb merging")
struct AppleSearchExactMatchRankingTests {
    let cinemeta = UUID()
    let tmdb = UUID()

    private func catalogRecord(_ source: UUID, id: String, type: String, year: String,
                               imdbID: String? = nil) -> AppleMediaRecord {
        AppleMediaIngestion.catalogRecord(
            instanceID: source,
            item: AppleCatalogItem(mediaID: id, type: type, name: "Stranger Things",
                                   releaseInfo: year, imdbID: imdbID))
    }

    @Test func tmdbRowsMergeWithCinemetaByIMDbID() {
        let results = AppleCatalogSearchStore.mergedResults(
            [catalogRecord(cinemeta, id: "tt3007000", type: "movie", year: "2013"),
             catalogRecord(tmdb, id: "tmdb:250000", type: "movie", year: "2012", imdbID: "tt3007000")],
            matching: "stranger things", limit: 20)
        #expect(results.count == 1)
    }

    @Test func theSeriesMoreSourcesCarryAndNewerRanksFirst() {
        let results = AppleCatalogSearchStore.mergedResults(
            [catalogRecord(cinemeta, id: "tt3007000", type: "movie", year: "2013"),
             catalogRecord(tmdb, id: "tmdb:250000", type: "movie", year: "2013", imdbID: "tt3007000"),
             catalogRecord(cinemeta, id: "tt4574334", type: "series", year: "2016-"),
             catalogRecord(tmdb, id: "tmdb:66732", type: "series", year: "2016", imdbID: "tt4574334")],
            matching: "stranger things", limit: 20)
        #expect(results.map(\.canonicalID) == ["tt4574334", "tt3007000"])
    }

    @Test func aNonIMDbValueIsNotKept() {
        #expect(AppleCatalogItem(mediaID: "tmdb:1", type: "movie", name: "X", imdbID: "tmdb:1").imdbID == nil)
    }
}
