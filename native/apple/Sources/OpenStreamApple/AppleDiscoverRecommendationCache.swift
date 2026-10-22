import Foundation

/// A prepared Discover answer in the existing metadata cache, revalidated after first paint.
enum AppleDiscoverRecommendationCache {
    struct Key: Equatable, Sendable {
        let scope: String
        let fingerprint: String
    }

    struct WatchState: Codable, Sendable {
        var progress: [String: ApplePlaybackProgress] = [:]
        var activity: [String: ApplePlaybackProgress] = [:]
        var completed: [String: Date] = [:]
        var unwatched: [String: Date] = [:]
        var removed: [String: Date] = [:]
        var ratings: [String: Int] = [:]
    }

    private struct Fingerprint: Encodable {
        let state: WatchState
        let indexSize: UInt64?
        let indexModifiedAt: Date?
    }

    private struct Item: Codable {
        let record: AppleMediaRecord
        let item: AppleCatalogItem
        let sourceID: UUID
        let updatedAt: Date?

        init(_ value: AppleDiscoverView.IndexedCatalogItem) {
            record = value.record
            item = value.item
            sourceID = value.source.id
            updatedAt = value.continueWatchingUpdatedAt
        }

        func resolve(sources: [UUID: AppleSource], favoriteIDs: Set<String>) -> AppleDiscoverView.IndexedCatalogItem? {
            guard let source = sources[sourceID] else { return nil }
            var restoredRecord = record
            restoredRecord.isFavorite = favoriteIDs.contains(record.id)
            return .init(record: restoredRecord, item: item, source: source, continueWatchingUpdatedAt: updatedAt)
        }
    }

    private struct Answer: Codable {
        let fingerprint: String
        let favoriteIDs: Set<String>
        let continueWatching: [Item]
        let picks: [Item]
        let heroes: [Item]
        let seedHeading: String?
        let seedItems: [Item]
    }

    static func scope(sourceIdentity: String, namespace: String, metadataConfiguration: AppleTMDBConfiguration?,
                      top10ListsEnabled: Bool, heroTitle: String) -> String {
        [sourceIdentity, AppleSourceKind.allCases.map(\.rawValue).joined(separator: ";"), namespace,
         AppleCatalogArtworkPolicy.configurationMarker(metadataConfiguration), "top10:\(top10ListsEnabled)",
         heroTitle].joined(separator: "|")
    }

    @concurrent nonisolated static func key(scope: String, state: WatchState,
                                           indexURL: URL? = AppleMediaIndexRepository.defaultFileURL) async -> Key? {
        let attributes = indexURL.flatMap { try? FileManager.default.attributesOfItem(atPath: $0.path) }
        let fingerprint = Fingerprint(state: state, indexSize: attributes?[.size] as? UInt64,
            indexModifiedAt: attributes?[.modificationDate] as? Date)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        guard let data = try? encoder.encode(fingerprint) else { return nil }
        return Key(scope: ApplePlaybackIdentity.digest(for: scope),
            fingerprint: ApplePlaybackIdentity.digest(for: String(decoding: data, as: UTF8.self)))
    }

    @concurrent nonisolated static func restore(_ key: Key, sources: [AppleSource],
                                               cache: AppleMetadataDiskCache = .shared) async -> AppleDiscoverView.RecommendationResult? {
        guard let entry = await cache.entry(source: key.scope, type: "discover-v1", mediaID: "recommendations"),
              entry.freshness == .fresh,
              let answer = try? JSONDecoder().decode(Answer.self, from: entry.payload),
              answer.fingerprint == key.fingerprint else { return nil }
        var enabled = Dictionary(sources.filter(\.isEnabled).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        if !enabled.isEmpty, let metadata = answer.heroes.first(where: { $0.sourceID == AppleMediaAvailability.metadataOnlyInstanceID }) {
            enabled[metadata.sourceID] = AppleCatalogSearchMatch.metadataOnly(metadata.item).source
        }
        let values = answer.continueWatching + answer.picks + answer.heroes + answer.seedItems
        guard values.allSatisfy({ enabled[$0.sourceID] != nil }) else { return nil }
        return .init(continueWatching: answer.continueWatching.compactMap { $0.resolve(sources: enabled, favoriteIDs: answer.favoriteIDs) },
            picks: answer.picks.compactMap { $0.resolve(sources: enabled, favoriteIDs: answer.favoriteIDs) },
            heroes: answer.heroes.compactMap { $0.resolve(sources: enabled, favoriteIDs: answer.favoriteIDs) },
            seedHeading: answer.seedHeading, seedItems: answer.seedItems.compactMap { $0.resolve(sources: enabled, favoriteIDs: answer.favoriteIDs) })
    }

    @concurrent nonisolated static func store(_ result: AppleDiscoverView.RecommendationResult, key: Key,
                                             favoriteIDs: Set<String>,
                                             cache: AppleMetadataDiskCache = .shared) async {
        let answer = Answer(fingerprint: key.fingerprint, favoriteIDs: favoriteIDs, continueWatching: result.continueWatching.map(Item.init),
            picks: result.picks.map(Item.init), heroes: result.heroes.map(Item.init),
            seedHeading: result.seedHeading, seedItems: result.seedItems.map(Item.init))
        guard let data = try? JSONEncoder().encode(answer) else { return }
        await cache.store(data, source: key.scope, type: "discover-v1", mediaID: "recommendations")
    }
}
