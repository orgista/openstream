import Foundation
import Testing
@testable import OpenStreamApple

/// Owner 2026-09-15: "I search for Jury duty and go odd results[,] I don't want
/// episode results ideally show and movies only."
///
/// The media index holds one record per library *file*, so a show with eight
/// episodes on disk produced eight near-identical rows.
@MainActor
@Suite(.serialized)
struct AppleSearchResultShapeTests {
    @Test func indexedTitleOpensWithMetadataAndAnEnabledSource() throws {
        let source = AppleSource(kind: .mediaServer, name: "Fixture", url: try #require(URL(string: "https://fixture.example")))
        let reference = AppleMediaServerItemReference(sourceID: source.id, itemID: "wick").mediaID
        let item = AppleCatalogItem(mediaID: reference, type: "movie", name: "John Wick",
            posterURL: URL(string: "https://fixture.example/wick.jpg"), releaseInfo: "2014", imdbID: "tt2911666")
        let record = AppleMediaIngestion.catalogRecord(instanceID: source.id, item: item)
        let match = try #require(AppleCatalogSearchMatch.indexed(record, sources: [source]))
        #expect(match.item.mediaID == "tt2911666")
        #expect(match.item.name == item.name)
        #expect(match.item.posterURL == item.posterURL)
        #expect(match.source.id == source.id)
        var disabled = source
        disabled.isEnabled = false
        #expect(AppleCatalogSearchMatch.indexed(record, sources: [disabled]) == nil)
        #expect(AppleCatalogSearchMatch.indexed(record, sources: []) == nil)
    }

    @Test func eachDisplayedMatchIsResolvedOncePerResultSet() async throws {
        let source = AppleSource(kind: .library, name: "Fixture", url: URL(fileURLWithPath: "/fixture"))
        let record = AppleMediaRecord(kind: .movie, title: "John Wick",
            availability: [.init(instanceID: source.id, capability: .direct, itemReference: "wick")])
        let subject = store()
        var resolutions = 0
        await subject.search(query: "wick", resolveMatch: {
            resolutions += 1
            return AppleCatalogSearchMatch.indexed($0, sources: [source])
        }) { _ in [record, record] }
        #expect(resolutions == 1)
        let row = try #require(subject.rows.first)
        #expect(row.record == record)
        #expect(row.match.item.name == "John Wick")
        #expect(subject.rows.count == 1)
        #expect(resolutions == 1)
    }

    @Test func cancelledRevisionUpdatesDoNotRestartSearch() async {
        let subject = store()
        let cancelled = Task { @MainActor in await subject.coalesceRevision("scan-1") }
        cancelled.cancel()
        await cancelled.value
        #expect(subject.contentRevision.isEmpty)
        await subject.coalesceRevision("scan-2")
        #expect(subject.contentRevision == "scan-2")
        #expect(subject.results.isEmpty)
    }

    @Test func sharedLinksIgnoreContentRevisionsButTextQueriesRefresh() async {
        let subject = store()
        let query = subject.taskIdentity(query: "wick")
        let link = "https://www.imdb.com/title/tt2911666/"
        let sharedLink = subject.taskIdentity(query: link)
        await subject.coalesceRevision("scan-complete")
        #expect(subject.taskIdentity(query: "wick") != query)
        #expect(subject.taskIdentity(query: "wick 4") != subject.taskIdentity(query: "wick"))
        #expect(subject.taskIdentity(query: link) == sharedLink)
    }

    @Test(arguments: [AppleMediaKind.video, .movie, .channel])
    func enabledFilesServerTitlesAndChannelsKeepTitlePageRows(kind: AppleMediaKind) async throws {
        let source = AppleSource(kind: kind == .movie ? .mediaServer : .library,
            name: "Fixture", url: URL(fileURLWithPath: "/fixture"))
        let retained = AppleMediaRecord(kind: kind, title: "Fixture Star",
            availability: [.init(instanceID: source.id, capability: .direct, itemReference: "star")])
        let subject = store()
        await subject.search(query: "star", resolveMatch: { AppleCatalogSearchMatch.indexed($0, sources: [source]) }) { _ in [retained] }
        #expect(subject.rows.count == 1)
        #expect(subject.rows.first?.match.source.id == source.id)
        await subject.search(query: "star", resolveMatch: { AppleCatalogSearchMatch.indexed($0, sources: []) }) { _ in [retained] }
        #expect(subject.rows.isEmpty)
        var disabled = source
        disabled.isEnabled = false
        await subject.search(query: "star", resolveMatch: { AppleCatalogSearchMatch.indexed($0, sources: [disabled]) }) { _ in [retained] }
        #expect(subject.rows.isEmpty)
    }

    private func store() -> AppleCatalogSearchStore {
        AppleCatalogSearchStore(debounce: .milliseconds(1), maximumResults: 50, revisionDebounce: .zero)
    }

    private func record(
        _ kind: AppleMediaKind,
        _ title: String,
        year: Int? = nil,
        reference: String = UUID().uuidString,
        summary: String? = nil,
        artwork: URL? = nil
    ) -> AppleMediaRecord {
        AppleMediaRecord(
            canonicalID: reference,
            kind: kind,
            title: title,
            year: year,
            summary: summary,
            artworkURL: artwork,
            availability: [.init(instanceID: UUID(), capability: .direct, itemReference: reference)]
        )
    }

    /// Eight files on disk, one show.
    @Test func everyEpisodeFileOfAShowCollapsesToOneRow() async {
        let subject = store()
        let files = (1 ... 8).map { record(.video, "Jury Duty", year: 2023, reference: "s1e\($0)") }
        await subject.search(query: "jury duty") { _ in files }
        #expect(subject.results.count == 1)
        #expect(subject.results.first?.title == "Jury Duty")
    }

    /// A source that returns episodes has them dropped outright.
    @Test func episodeRecordsAreNotResults() async {
        let subject = store()
        let mixed = [
            record(.series, "Jury Duty", year: 2023),
            record(.episode, "Jury Duty", year: 2023, reference: "ep1"),
            record(.episode, "Jury Duty", year: 2023, reference: "ep2"),
        ]
        await subject.search(query: "jury duty") { _ in mixed }
        #expect(subject.results.count == 1)
        #expect(subject.results.allSatisfy { $0.kind != .episode })
    }

    /// The local copy and its catalog entry become one row that carries the
    /// catalog's artwork *and* both sources' availability.
    @Test func aLocalCopyMergesWithItsCatalogEntry() async {
        let subject = store()
        let local = record(.video, "Jury Duty", year: 2023, reference: "local")
        let catalog = record(
            .series, "Jury Duty", year: 2023, reference: "tt15557874",
            summary: "A man thinks he is a juror.",
            artwork: URL(string: "https://example.com/art.jpg")
        )
        await subject.search(query: "jury duty") { _ in [local, catalog] }
        #expect(subject.results.count == 1)
        let merged = subject.results.first
        #expect(merged?.summary != nil)
        #expect(merged?.artworkURL != nil)
        #expect(merged?.availability.count == 2)
    }

    /// Different years are different titles and must not merge.
    @Test func twoFilmsOfTheSameNameStaySeparate() async {
        let subject = store()
        let films = [record(.movie, "Dune", year: 1984), record(.movie, "Dune", year: 2021)]
        await subject.search(query: "dune") { _ in films }
        #expect(subject.results.count == 2)
    }

    /// The field offers "movies, shows, and channels" — live channels stay.
    @Test func channelsAreStillResults() async {
        let subject = store()
        await subject.search(query: "news") { _ in
            [self.record(.channel, "News Channel")]
        }
        #expect(subject.results.count == 1)
        #expect(subject.results.first?.kind == .channel)
    }

    /// Apple TV regression 2026-10-01: the exact title sat under near
    /// matches left over from the half-typed query until the search answered.
    @Test func rowsReRankForTheTypedQueryBeforeTheSearchAnswers() async {
        let subject = store()
        let typed = [record(.movie, "Saturday Night Life", year: 2006),
                     record(.series, "Saturday Night Lights", year: 2026),
                     record(.series, "Saturday Night Live", year: 1975)]
        await subject.search(query: "saturday night li") { _ in typed }
        #expect(subject.results.first?.title == "Saturday Night Life")

        let (gate, release) = AsyncStream<Void>.makeStream()
        let pending = Task { @MainActor in
            await subject.search(query: "saturday night live") { _ in
                for await _ in gate { break }
                return typed
            }
        }
        while !subject.isSearching { await Task.yield() }
        #expect(subject.results.map(\.title) == ["Saturday Night Live"])
        release.yield()
        release.finish()
        await pending.value
        #expect(subject.results.first?.title == "Saturday Night Live")
    }
}
