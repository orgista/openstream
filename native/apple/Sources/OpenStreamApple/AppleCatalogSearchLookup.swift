import Foundation
import Observation

struct AppleCatalogSearchMatch: Equatable, Sendable {
    let item: AppleCatalogItem
    let source: AppleSource
}

/// A render-ready projection of catalog data for Search. Building this once
/// avoids regenerating every media record for every visible result row.
struct AppleCatalogSearchLookup: Sendable {
    private let matchesByRecordID: [String: AppleCatalogSearchMatch]
    /// The same matches keyed by the source and hashed item reference each
    /// record's availability carries. A merged search row keeps the id of
    /// whichever record had the richer metadata, and that record may be one
    /// the shelves no longer list; its other availabilities still name items
    /// that are listed.
    private let matchesByAvailability: [String: AppleCatalogSearchMatch]
    private let activeCatalogSourcesByID: [AppleSource.ID: AppleSource]
    /// Every listed item, including the ones `matchesByRecordID` folds into
    /// an earlier record with the same IMDb id. Title matching runs over these:
    /// TMDB's "Wonka's The Golden Ticket" and Cinemeta's "The Golden Ticket"
    /// share one IMDb id, search shows them as one row, and the Top 10 still
    /// has to find the name Netflix ranks (Apple TV verification 2026-10-01).
    private let titleMatches: [AppleCatalogSearchMatch]
    private let relatedItemsBySourceID: [AppleSource.ID: [AppleCatalogItem]]
    private let sourceNamesByID: [AppleSource.ID: String]
    /// Each match's title as `match(title:)` compares it, in `titleMatches`
    /// order — only when built with `indexesTitles`, otherwise empty and
    /// worked out per call. Discover's two Top 10 rows match 20 titles
    /// against every catalog title each time Discover draws, and folding
    /// and splitting those names there was its heaviest app code while
    /// scrolling (N34 trace).
    private let normalizedTitles: [String]
    private let articleFreeTitles: [String]

    init(sections: [AppleCatalogSection] = [], sources: [AppleSource] = [], indexesTitles: Bool = false) {
        let allSourcesByID = sources.reduce(into: [AppleSource.ID: AppleSource]()) {
            $0[$1.id] = $1
        }
        let activeSourcesByID = allSourcesByID.filter { $0.value.isEnabled }
        var matches: [String: AppleCatalogSearchMatch] = [:]
        var matchesByAvailability: [String: AppleCatalogSearchMatch] = [:]
        var titled: [AppleCatalogSearchMatch] = []
        var related: [AppleSource.ID: [AppleCatalogItem]] = [:]
        var seenRelatedIDs: [AppleSource.ID: Set<String>] = [:]

        for section in sections {
            guard let source = activeSourcesByID[section.sourceID] else { continue }
            for item in section.items {
                let match = AppleCatalogSearchMatch(item: item, source: source)
                if seenRelatedIDs[section.sourceID, default: []].insert(item.id).inserted {
                    related[section.sourceID, default: []].append(item)
                    titled.append(match)
                }
                let record = AppleMediaIngestion.catalogRecord(instanceID: source.id, item: item)
                if matches[record.id] == nil {
                    matches[record.id] = match
                }
                for availability in record.availability where matchesByAvailability[Self.key(availability)] == nil {
                    matchesByAvailability[Self.key(availability)] = match
                }
            }
        }

        matchesByRecordID = matches
        self.matchesByAvailability = matchesByAvailability
        activeCatalogSourcesByID = activeSourcesByID.filter { $0.value.kind == .stremio }
        titleMatches = titled
        relatedItemsBySourceID = related
        sourceNamesByID = allSourcesByID.mapValues(\.name)
        if indexesTitles {
            normalizedTitles = titled.map { Self.normalized($0.item.name) }
            articleFreeTitles = normalizedTitles.map(Self.removingLeadingArticle)
        } else {
            normalizedTitles = []
            articleFreeTitles = []
        }
    }

    static func buildOffMain(
        sections: [AppleCatalogSection],
        sources: [AppleSource]
    ) async -> AppleCatalogSearchLookup {
        let work = Task.detached(priority: .userInitiated) {
            AppleCatalogSearchLookup(sections: sections, sources: sources, indexesTitles: true)
        }
        return await withTaskCancellationHandler {
            await work.value
        } onCancel: {
            work.cancel()
        }
    }

    func match(for recordID: String) -> AppleCatalogSearchMatch? {
        matchesByRecordID[recordID]
    }

    /// The listed catalog item a search row stands for: its own id first, then
    /// any item one of its merged availabilities names.
    func match(for record: AppleMediaRecord) -> AppleCatalogSearchMatch? {
        matchesByRecordID[record.id]
            ?? record.availability.lazy.compactMap { matchesByAvailability[Self.key($0)] }.first
    }

    /// A title page for a catalog record no shelf lists any more.
    ///
    /// The media index keeps catalog records after they leave the shelves —
    /// every title page that opens writes one, and a shelf refresh retains
    /// the most recent ones — so Search finds them locally while no loaded
    /// section holds their item, and the row could not open (N49 #7). The
    /// item reference is hashed, but a record with an IMDb id names the
    /// title outright, which is all the title page needs to load it.
    ///
    /// The record's saved art comes with it: the backdrop it was ingested
    /// with, else the image service's backdrop for the IMDb id — so a
    /// landscape card such as Continue Watching draws a still, not a poster
    /// cropped to 16:9 — and its poster behind that.
    func rebuiltMatch(for record: AppleMediaRecord) -> AppleCatalogSearchMatch? {
        guard record.kind == .movie || record.kind == .series,
              let mediaID = record.canonicalID,
              AppleStremioMetadataClient.isIMDBIdentifier(mediaID),
              let source = record.availability
                  .filter({ $0.capability == .resolvable })
                  .lazy.compactMap({ activeCatalogSourcesByID[$0.instanceID] }).first else {
            return nil
        }
        let item = AppleCatalogItem(
            mediaID: mediaID,
            type: record.kind == .series ? "series" : "movie",
            name: record.title,
            posterURL: record.artworkURL,
            backgroundURL: record.backdropURL
                ?? AppleCatalogArtworkPolicy.imageServiceURL(kind: "background", mediaID: mediaID),
            summary: record.summary,
            releaseInfo: record.year.map(String.init),
            year: record.year
        )
        return AppleCatalogSearchMatch(item: item, source: source)
    }

    /// Resolves a search row against every lookup, preferring a listed item in
    /// any of them over a rebuilt one.
    static func match(
        for record: AppleMediaRecord,
        in lookups: [AppleCatalogSearchLookup]
    ) -> AppleCatalogSearchMatch? {
        lookups.lazy.compactMap { $0.match(for: record) }.first
            ?? lookups.lazy.compactMap { $0.rebuiltMatch(for: record) }.first
    }

    /// False for the empty lookup a screen holds before its first build.
    var hasSources: Bool { !sourceNamesByID.isEmpty }

    /// Whether any add-on the record came from is an enabled catalog source.
    func hasActiveCatalogSource(for record: AppleMediaRecord) -> Bool {
        record.availability.contains { activeCatalogSourcesByID[$0.instanceID] != nil }
    }

    /// Whether a row that resolves to no title page should still be listed.
    ///
    /// A record whose every availability is a catalog entry has nothing else
    /// to offer: shown, it was a row that looked tappable and did nothing.
    /// Library files, server titles and channels are listed as before.
    static func listsUnmatched(_ record: AppleMediaRecord) -> Bool {
        !record.availability.allSatisfy { $0.capability == .resolvable }
    }

    func relatedItems(for sourceID: AppleSource.ID) -> [AppleCatalogItem] {
        relatedItemsBySourceID[sourceID] ?? []
    }

    func sourceName(for record: AppleMediaRecord) -> String {
        let names = record.availability.compactMap { sourceNamesByID[$0.instanceID] }
        return names.isEmpty ? "Local source" : names.joined(separator: ", ")
    }

    func match(title: String, type: String, seasonTitle: String? = nil,
               ignoringLeadingArticle: Bool = false) -> AppleCatalogSearchMatch? {
        let wanted = Set([title, seasonTitle ?? ""].map(Self.normalized).filter { !$0.isEmpty })
        let typed = titleMatches.indices.filter {
            titleMatches[$0].item.type.caseInsensitiveCompare(type) == .orderedSame
        }
        if let exact = typed.first(where: { wanted.contains(normalizedTitle(at: $0)) }) {
            return withArtwork(titleMatches[exact], among: typed)
        }
        guard ignoringLeadingArticle else { return nil }
        // Ranking feeds and metadata catalogs sometimes differ only by "The".
        // Keep exact matches first, and never guess between distinct title IDs.
        let withoutArticles = Set(wanted.map(Self.removingLeadingArticle).filter { !$0.isEmpty })
        let candidates = typed.filter { withoutArticles.contains(articleFreeTitle(at: $0)) }.map { titleMatches[$0] }
        guard let first = candidates.first,
              candidates.allSatisfy({ Self.titleIdentity($0.item) == Self.titleIdentity(first.item) }) else { return nil }
        return withArtwork(first, among: typed)
    }

    /// The matched item, or — when it carries no art of its own and no IMDb
    /// id the image service could draw from — another listed item for the
    /// same IMDb id that has art, so a Top 10 tile found by one catalog's name
    /// can still draw another catalog's poster.
    private func withArtwork(_ match: AppleCatalogSearchMatch, among typed: [Int]) -> AppleCatalogSearchMatch {
        guard match.item.posterURL == nil, match.item.backgroundURL == nil,
              !AppleStremioMetadataClient.isIMDBIdentifier(match.item.mediaID) else { return match }
        let identity = Self.titleIdentity(match.item)
        return typed.lazy.map { titleMatches[$0] }.first {
            Self.titleIdentity($0.item) == identity && ($0.item.posterURL != nil || $0.item.backgroundURL != nil)
        } ?? match
    }

    /// One title across catalogs: its IMDb id when known, else its own id.
    private static func titleIdentity(_ item: AppleCatalogItem) -> String {
        if AppleStremioMetadataClient.isIMDBIdentifier(item.mediaID) { return item.mediaID }
        return item.imdbID ?? item.mediaID
    }

    private func normalizedTitle(at index: Int) -> String {
        normalizedTitles.isEmpty ? Self.normalized(titleMatches[index].item.name) : normalizedTitles[index]
    }

    private func articleFreeTitle(at index: Int) -> String {
        articleFreeTitles.isEmpty ? Self.removingLeadingArticle(normalizedTitle(at: index)) : articleFreeTitles[index]
    }

    private static func key(_ availability: AppleMediaAvailability) -> String {
        "\(availability.instanceID.uuidString)|\(availability.itemReference)"
    }

    private static func removingLeadingArticle(_ value: String) -> String {
        let words = value.split(separator: " ")
        guard let first = words.first, ["the", "a", "an"].contains(first) else { return value }
        return words.dropFirst().joined(separator: " ")
    }

    private static func normalized(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}

struct AppleCatalogSearchMetrics: Equatable, Sendable {
    let debounceDuration: Duration
    let fetchDuration: Duration
}

@MainActor
@Observable
final class AppleCatalogSearchStore {
    typealias LocalSearch = @MainActor (String) async -> [AppleMediaRecord]

    private(set) var results: [AppleMediaRecord] = []
    private(set) var lookup = AppleCatalogSearchLookup()
    private(set) var isSearching = false
    private(set) var metrics: AppleCatalogSearchMetrics?

    private let pipeline: AppleCatalogSearchPipeline
    private let debounce: Duration
    private let maximumResults: Int
    private var generation: UInt64 = 0

    init(
        client: AppleStremioCatalogClient = AppleStremioCatalogClient(),
        debounce: Duration = .milliseconds(100),
        deadline: Duration = .seconds(2),
        maximumResults: Int = 100,
        maximumConcurrentRequests: Int = AppleCatalogDiscoveryPolicy.maximumConcurrentRequests
    ) {
        self.pipeline = AppleCatalogSearchPipeline(
            client: client,
            deadline: max(deadline, .milliseconds(1)),
            maximumConcurrentRequests: maximumConcurrentRequests
        )
        self.debounce = max(debounce, .zero)
        self.maximumResults = min(max(maximumResults, 1), 100)
    }

    func search(
        query: String,
        sources: [AppleSource],
        baseSections: [AppleCatalogSection],
        localSearch: @escaping LocalSearch
    ) async {
        generation &+= 1
        let currentGeneration = generation
        let value = String(query.trimmingCharacters(in: .whitespacesAndNewlines).prefix(200))
        guard !value.isEmpty else {
            results = []
            lookup = AppleCatalogSearchLookup(sections: baseSections, sources: sources)
            metrics = nil
            isSearching = false
            return
        }

        isSearching = true
        defer {
            if generation == currentGeneration { isSearching = false }
        }
        // The rows on screen re-rank against what is typed now, before the
        // add-ons answer: "saturday night live" sat under the
        // "saturday night li" list (Life, Lights, then Live) until the slow
        // search came back (Apple TV regression 2026-10-01).
        results = Self.mergedResults(results, matching: value, limit: maximumResults)

        let clock = ContinuousClock()
        let debounceStart = clock.now
        do {
            try await Task.sleep(for: debounce)
        } catch {
            return
        }
        let debounceDuration = debounceStart.duration(to: clock.now)
        guard generation == currentGeneration, !Task.isCancelled else { return }

        let fetchStart = clock.now
        let pipeline = pipeline
        async let remoteSections = pipeline.fetch(query: value, sources: sources)
        let localRecords = await localSearch(value)
        let fetchedSections = await remoteSections
        let fetchDuration = fetchStart.duration(to: clock.now)
        guard generation == currentGeneration, !Task.isCancelled else { return }

        let remoteRecords = fetchedSections.flatMap { AppleMediaIngestion.catalogRecords(section: $0) }
        results = Self.mergedResults(
            localRecords + remoteRecords,
            matching: value,
            limit: maximumResults
        )
        lookup = AppleCatalogSearchLookup(
            sections: fetchedSections + baseSections,
            sources: sources
        )
        metrics = AppleCatalogSearchMetrics(
            debounceDuration: debounceDuration,
            fetchDuration: fetchDuration
        )
    }

    /// Search results are titles, not files.
    ///
    /// The media index holds one record per library **file**, so a show with
    /// eight episodes on disk produced eight near-identical rows, and an add-on
    /// catalog can return episode entries of its own on top of that. The owner
    /// searched "Jury Duty" and got a page of them: "I don't want episode
    /// results ideally show and movies only" (2026-09-15).
    ///
    /// Two changes: episodes are dropped outright, and what is left collapses
    /// on title and year rather than on record id. That also merges a local
    /// copy with its catalog entry, so one row carries the catalog's artwork
    /// and summary *and* the local availability, instead of appearing twice.
    ///
    /// Channels are kept — the field offers "movies, shows, and channels".
    /// Internal rather than private so the collapsing rules can be tested
    /// directly; the duplicate-row bug lived here and was invisible from the
    /// public surface. It and its helpers read nothing but their arguments,
    /// so they are `nonisolated`: callers need not wait for the main actor.
    nonisolated static func mergedResults(
        _ values: [AppleMediaRecord],
        matching query: String,
        limit: Int
    ) -> [AppleMediaRecord] {
        let tokens = normalized(query).split(separator: " ")
        var recordsByID: [String: AppleMediaRecord] = [:]
        // Two records naming the same canonical id are the same title, whatever
        // their years say. Searching "jury duty" returned the 2007 series twice
        // — once from Cinemeta carrying its year, once from the TMDB add-on
        // with none — because the collapse key is title|year and "2007" and ""
        // are different keys. The first record to claim a canonical id owns the
        // key; later ones with that id merge into it.
        var keysByCanonicalID: [String: String] = [:]
        for value in values where value.kind != .episode && matches(value, tokens: tokens) {
            var key = collapseKey(value)
            if let canonical = value.canonicalID, !canonical.isEmpty {
                if let claimed = keysByCanonicalID[canonical] {
                    key = claimed
                } else {
                    keysByCanonicalID[canonical] = key
                }
            }
            if let existing = recordsByID[key] {
                recordsByID[key] = merge(existing, value)
            } else {
                recordsByID[key] = value
            }
        }
        let normalizedQuery = tokens.joined(separator: " ")
        return recordsByID.values.sorted { lhs, rhs in
            let lhsRank = relevance(lhs, query: normalizedQuery)
            let rhsRank = relevance(rhs, query: normalizedQuery)
            if lhsRank != rhsRank { return lhsRank < rhsRank }
            if lhsRank == 0, let exactOrder = exactMatchOrder(lhs, rhs) { return exactOrder }
            let lhsTitle = normalized(lhs.title)
            let rhsTitle = normalized(rhs.title)
            if lhsTitle != rhsTitle { return lhsTitle < rhsTitle }
            return lhs.id < rhs.id
        }.prefix(limit).map { $0 }
    }

    /// How directly a matched title answers the query — 0 best.
    ///
    /// Alphabetical order alone is right only when nothing that matched sorts
    /// ahead of the thing that was asked for. Typing "Dune" on the phone
    /// returned *Be Dune Teen*, *Children of Dune* and *Destination Dune* above
    /// *Dune* itself, because every one of them contains the word and B, C and
    /// D-e sort before D-u (owner review, 2026-09-17). The corpus test missed
    /// it: none of its 206 titles is a decoy that sorts ahead of an exact match.
    ///
    /// Ties still break alphabetically, so *Dune* stays ahead of *Dune: Part
    /// Two* and the ordering that was already right does not move.
    nonisolated static func relevance(_ record: AppleMediaRecord, query: String) -> Int {
        guard !query.isEmpty else { return 2 }
        let title = normalized(record.title)
        if title == query { return 0 }
        if record.aliases.contains(where: { normalized($0) == query }) { return 0 }
        if title.hasPrefix(query) { return 1 }
        return 2
    }

    /// Among titles that all match the query exactly, which comes first.
    ///
    /// "stranger things" put the 2013 film above the 2016 series, because
    /// exact matches then fell back to alphabetical order and the id (full
    /// test 2026-10-01). The title more sources carry is the one people mean
    /// (the merged rows are the popularity signal there is), then the newer
    /// one, then a show or film ahead of a bare library file. Nil when none
    /// of those tells them apart.
    nonisolated static func exactMatchOrder(_ lhs: AppleMediaRecord, _ rhs: AppleMediaRecord) -> Bool? {
        let lhsSources = Set(lhs.availability.map(\.instanceID)).count
        let rhsSources = Set(rhs.availability.map(\.instanceID)).count
        if lhsSources != rhsSources { return lhsSources > rhsSources }
        if let lhsYear = lhs.year, let rhsYear = rhs.year, lhsYear != rhsYear { return lhsYear > rhsYear }
        let lhsTitled = lhs.kind == .series || lhs.kind == .movie
        let rhsTitled = rhs.kind == .series || rhs.kind == .movie
        if lhsTitled != rhsTitled { return lhsTitled }
        return nil
    }

    /// One row per title: the normalised name and the year.
    ///
    /// The kind is deliberately *not* part of the key. A library file's kind is
    /// `.video`, which is the absence of a classification rather than a real
    /// one, so including it would keep a local copy and its catalog entry apart
    /// — the merge that makes a result useful.
    nonisolated private static func collapseKey(_ record: AppleMediaRecord) -> String {
        "\(normalized(record.title))|\(record.year.map(String.init) ?? "")"
    }

    /// Whether a record answers the query.
    ///
    /// This used to be raw substring containment over the title, the aliases
    /// **and the canonical id**, which produced the "odd results" the owner
    /// reported. Measured against a 206-title corpus: "Her" returned
    /// *Sherlock*, "Ran" returned *Stranger Things*, "It" returned 18 titles,
    /// and a bare digit string matched whichever title happened to carry those
    /// digits in its IMDb number.
    ///
    /// A token now has to begin a word — "her" does not begin "sherlock" — or
    /// begin the title with its spaces removed, which is what lets "mash" find
    /// *M\*A\*S\*H* and "walle" find *WALL·E*. The id is matched only in full.
    nonisolated private static func matches(_ record: AppleMediaRecord, tokens: [Substring]) -> Bool {
        guard !tokens.isEmpty else { return false }
        if let canonical = record.canonicalID?.lowercased(),
           tokens.count == 1, tokens[0] == canonical {
            return true
        }
        let words = normalized(([record.title] + record.aliases).joined(separator: " "))
            .split(separator: " ")
        let compact = words.joined()
        return tokens.allSatisfy { token in
            // A four-digit token may be the year rather than part of the title:
            // people type "dune 2021" and "it 2017" to tell two versions apart,
            // and that used to return **nothing**, because the year appears
            // nowhere in the title. Still falls through to the title, so "1917"
            // and "2001" keep finding the films named after them.
            if token.count == 4, let year = Int(token), record.year == year { return true }
            return words.contains { $0.hasPrefix(token) } || compact.hasPrefix(token)
        }
    }

    nonisolated private static func merge(_ lhs: AppleMediaRecord, _ rhs: AppleMediaRecord) -> AppleMediaRecord {
        var result = metadataScore(rhs) > metadataScore(lhs) ? rhs : lhs
        result.availability = Dictionary(grouping: lhs.availability + rhs.availability, by: \.instanceID)
            .compactMap { _, values in values.max { $0.lastVerified < $1.lastVerified } }
            .sorted { $0.instanceID.uuidString < $1.instanceID.uuidString }
        result.aliases = Array(Set(lhs.aliases + rhs.aliases)).sorted()
        result.isFavorite = lhs.isFavorite || rhs.isFavorite
        result.progress = lhs.progress ?? rhs.progress
        result.isPrivate = lhs.isPrivate || rhs.isPrivate
        result.lastVerified = max(lhs.lastVerified, rhs.lastVerified)
        return result
    }

    nonisolated private static func metadataScore(_ record: AppleMediaRecord) -> Int {
        (record.summary == nil ? 0 : 4)
            + (record.artworkURL == nil ? 0 : 2)
            + (record.year == nil ? 0 : 1)
            + min(record.aliases.count, 2)
    }

    nonisolated private static func normalized(_ value: String) -> String {
        // "&" becomes "and" before punctuation is stripped, so "Law & Order"
        // and someone typing "law and order" reach the same words.
        value.replacingOccurrences(of: "&", with: " and ")
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: Locale(identifier: "en_US_POSIX")
            )
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}

private struct AppleCatalogSearchPipeline: Sendable {
    private static let maximumRequests = 16

    let client: AppleStremioCatalogClient
    let deadline: Duration
    let maximumConcurrentRequests: Int

    func fetch(query: String, sources: [AppleSource]) async -> [AppleCatalogSection] {
        let requests = Self.requests(sources: sources)
        guard !requests.isEmpty, !Task.isCancelled else { return [] }
        let concurrency = min(max(maximumConcurrentRequests, 1), requests.count)

        return await withTaskGroup(of: Event.self, returning: [AppleCatalogSection].self) { group in
            var nextIndex = 0
            var completed = 0
            var sectionsByIndex: [Int: AppleCatalogSection] = [:]

            func enqueue(_ index: Int) {
                let request = requests[index]
                group.addTask {
                    do {
                        let items = try await client.search(
                            source: request.source,
                            catalog: request.catalog,
                            query: query
                        )
                        return .result(index, items)
                    } catch {
                        return .result(index, nil)
                    }
                }
            }

            while nextIndex < concurrency {
                enqueue(nextIndex)
                nextIndex += 1
            }
            group.addTask {
                do {
                    try await Task.sleep(for: deadline)
                    return .deadline
                } catch {
                    return .deadlineCancelled
                }
            }

            searchLoop: while let event = await group.next() {
                if Task.isCancelled {
                    group.cancelAll()
                    break
                }
                switch event {
                case .result(let index, let items):
                    completed += 1
                    if let items, !items.isEmpty {
                        let request = requests[index]
                        sectionsByIndex[index] = AppleCatalogSection(
                            source: request.source,
                            catalog: request.catalog,
                            items: items
                        )
                    }
                    if nextIndex < requests.count {
                        enqueue(nextIndex)
                        nextIndex += 1
                    }
                    if completed == requests.count {
                        group.cancelAll()
                        break searchLoop
                    }
                case .deadline:
                    group.cancelAll()
                    break searchLoop
                case .deadlineCancelled:
                    break
                }
            }

            return sectionsByIndex.keys.sorted().compactMap { sectionsByIndex[$0] }
        }
    }

    private static func requests(sources: [AppleSource]) -> [Request] {
        var values: [Request] = []
        var seen = Set<String>()
        sourceLoop: for source in sources where source.kind == .stremio && source.isEnabled {
            guard source.resources.contains(where: { $0.caseInsensitiveCompare("catalog") == .orderedSame }) else {
                continue
            }
            for catalog in source.catalogs where catalog.supportsSearch {
                let key = "\(source.id.uuidString):\(catalog.type):\(catalog.id)"
                guard ["movie", "series"].contains(catalog.type),
                      !catalog.id.isEmpty,
                      seen.insert(key).inserted else {
                    continue
                }
                values.append(Request(source: source, catalog: catalog))
                if values.count == maximumRequests { break sourceLoop }
            }
        }
        return values
    }

    private struct Request: Sendable {
        let source: AppleSource
        let catalog: AppleStremioCatalog
    }

    private enum Event: Sendable {
        case result(Int, [AppleCatalogItem]?)
        case deadline
        case deadlineCancelled
    }
}
