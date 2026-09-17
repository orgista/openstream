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
    private let orderedMatches: [AppleCatalogSearchMatch]
    private let relatedItemsBySourceID: [AppleSource.ID: [AppleCatalogItem]]
    private let sourceNamesByID: [AppleSource.ID: String]

    init(sections: [AppleCatalogSection] = [], sources: [AppleSource] = []) {
        let allSourcesByID = sources.reduce(into: [AppleSource.ID: AppleSource]()) {
            $0[$1.id] = $1
        }
        let activeSourcesByID = allSourcesByID.filter { $0.value.isEnabled }
        var matches: [String: AppleCatalogSearchMatch] = [:]
        var ordered: [AppleCatalogSearchMatch] = []
        var related: [AppleSource.ID: [AppleCatalogItem]] = [:]
        var seenRelatedIDs: [AppleSource.ID: Set<String>] = [:]

        for section in sections {
            guard let source = activeSourcesByID[section.sourceID] else { continue }
            for item in section.items {
                if seenRelatedIDs[section.sourceID, default: []].insert(item.id).inserted {
                    related[section.sourceID, default: []].append(item)
                }
                let recordID = AppleMediaIngestion.catalogRecord(
                    instanceID: source.id,
                    item: item
                ).id
                if matches[recordID] == nil {
                    let match = AppleCatalogSearchMatch(item: item, source: source)
                    matches[recordID] = match
                    ordered.append(match)
                }
            }
        }

        matchesByRecordID = matches
        orderedMatches = ordered
        relatedItemsBySourceID = related
        sourceNamesByID = allSourcesByID.mapValues(\.name)
    }

    static func buildOffMain(
        sections: [AppleCatalogSection],
        sources: [AppleSource]
    ) async -> AppleCatalogSearchLookup {
        let work = Task.detached(priority: .userInitiated) {
            AppleCatalogSearchLookup(sections: sections, sources: sources)
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

    func relatedItems(for sourceID: AppleSource.ID) -> [AppleCatalogItem] {
        relatedItemsBySourceID[sourceID] ?? []
    }

    func sourceName(for record: AppleMediaRecord) -> String {
        let names = record.availability.compactMap { sourceNamesByID[$0.instanceID] }
        return names.isEmpty ? "Local source" : names.joined(separator: ", ")
    }

    func match(title: String, type: String, seasonTitle: String? = nil) -> AppleCatalogSearchMatch? {
        let wanted = Set([title, seasonTitle ?? ""].map(Self.normalized).filter { !$0.isEmpty })
        return orderedMatches.first { match in
            match.item.type.caseInsensitiveCompare(type) == .orderedSame
                && wanted.contains(Self.normalized(match.item.name))
        }
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
    /// public surface.
    static func mergedResults(
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
        return recordsByID.values.sorted { lhs, rhs in
            let lhsTitle = normalized(lhs.title)
            let rhsTitle = normalized(rhs.title)
            if lhsTitle != rhsTitle { return lhsTitle < rhsTitle }
            return lhs.id < rhs.id
        }.prefix(limit).map { $0 }
    }

    /// One row per title: the normalised name and the year.
    ///
    /// The kind is deliberately *not* part of the key. A library file's kind is
    /// `.video`, which is the absence of a classification rather than a real
    /// one, so including it would keep a local copy and its catalog entry apart
    /// — the merge that makes a result useful.
    private static func collapseKey(_ record: AppleMediaRecord) -> String {
        "\(normalized(record.title))|\(record.year.map(String.init) ?? "")"
    }

    private static func matches(_ record: AppleMediaRecord, tokens: [Substring]) -> Bool {
        let haystack = normalized(
            ([record.title] + record.aliases + [record.canonicalID ?? ""]).joined(separator: " ")
        )
        return !tokens.isEmpty && tokens.allSatisfy(haystack.contains)
    }

    private static func merge(_ lhs: AppleMediaRecord, _ rhs: AppleMediaRecord) -> AppleMediaRecord {
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

    private static func metadataScore(_ record: AppleMediaRecord) -> Int {
        (record.summary == nil ? 0 : 4)
            + (record.artworkURL == nil ? 0 : 2)
            + (record.year == nil ? 0 : 1)
            + min(record.aliases.count, 2)
    }

    private static func normalized(_ value: String) -> String {
        value.folding(
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
