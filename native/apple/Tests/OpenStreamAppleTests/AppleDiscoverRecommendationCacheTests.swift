import Foundation
import Testing
@testable import OpenStreamApple

@Suite("Discover recommendation persistence")
struct AppleDiscoverRecommendationCacheTests {
    @Test func restoresDeckAndRowsWithCurrentSources() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = AppleMetadataDiskCache(directory: directory)
        let source = source()
        let item = AppleCatalogItem(mediaID: "tt1234567", type: "movie", name: "Movie",
            backgroundURL: URL(string: "https://fixture.example/backdrop.jpg"))
        let record = AppleMediaRecord(canonicalID: item.mediaID, kind: .movie, title: item.name,
            availability: [.init(instanceID: source.id, capability: .resolvable, itemReference: "movie|tt1234567")])
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let value = AppleDiscoverView.IndexedCatalogItem(record: record, item: item, source: source,
            continueWatchingUpdatedAt: date)
        let result = AppleDiscoverView.RecommendationResult(continueWatching: [value], picks: [value],
            heroes: [value], seedHeading: "Because you watched Movie", seedItems: [value])
        let key = try #require(await AppleDiscoverRecommendationCache.key(scope: "viewer", state: .init(), indexURL: nil))
        #expect(await AppleDiscoverRecommendationCache.restore(key, sources: [source], cache: cache) == nil)
        await AppleDiscoverRecommendationCache.store(result, key: key, favoriteIDs: [record.id], cache: cache)
        var current = source
        current.name = "Current Source"
        let restored = try #require(await AppleDiscoverRecommendationCache.restore(key, sources: [current], cache: cache))
        #expect(restored.heroes.map(\.id) == [record.id])
        #expect(restored.picks.map(\.id) == [record.id])
        #expect(restored.continueWatching.first?.continueWatchingUpdatedAt == date)
        #expect(restored.seedItems.map(\.id) == [record.id])
        #expect(restored.seedHeading == result.seedHeading)
        #expect(restored.heroes.first?.source.name == "Current Source")
        #expect(restored.heroes.first?.record.isFavorite == true)
        #expect(restored.continueWatching.first?.record.isFavorite == true)
        current.isEnabled = false
        #expect(await AppleDiscoverRecommendationCache.restore(key, sources: [current], cache: cache) == nil)
        #expect(await AppleDiscoverRecommendationCache.restore(key, sources: [], cache: cache) == nil)
        let changed = try #require(await AppleDiscoverRecommendationCache.key(scope: "viewer",
            state: .init(removed: [record.id: date]), indexURL: nil))
        #expect(await AppleDiscoverRecommendationCache.restore(changed, sources: [source], cache: cache) == nil)
    }

    @Test func watchChangesAndIndexReplacementInvalidateSavedResult() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let index = directory.appending(path: "index.json")
        try Data("first".utf8).write(to: index)
        let original = try #require(await AppleDiscoverRecommendationCache.key(scope: "viewer", state: .init(), indexURL: index))
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let progress = ApplePlaybackProgress(position: 100, duration: 1000, updatedAt: date)
        let changes: [AppleDiscoverRecommendationCache.WatchState] = [
            .init(progress: ["title": progress]), .init(activity: ["title": progress]),
            .init(completed: ["title": date]), .init(unwatched: ["title": date]),
            .init(removed: ["title": date]), .init(ratings: ["title": AppleTitleRating.down.rawValue])
        ]
        for state in changes {
            #expect(await AppleDiscoverRecommendationCache.key(scope: "viewer", state: state, indexURL: index) != original)
        }
        try Data("replacement".utf8).write(to: index)
        #expect(await AppleDiscoverRecommendationCache.key(scope: "viewer", state: .init(), indexURL: index) != original)
        #expect(await AppleDiscoverRecommendationCache.key(scope: "other viewer", state: .init(), indexURL: index) != original)
    }

    @Test func invalidPayloadIsAMiss() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = AppleMetadataDiskCache(directory: directory)
        let key = try #require(await AppleDiscoverRecommendationCache.key(scope: "viewer", state: .init(), indexURL: nil))
        await cache.store(Data("invalid".utf8), source: key.scope, type: "discover-v1", mediaID: "recommendations")
        #expect(await AppleDiscoverRecommendationCache.restore(key, sources: [source()], cache: cache) == nil)
    }

    @Test func settledCatalogDoesNotKeepARecommendationSkeleton() {
        #expect(!AppleDiscoverView.showsLoadingContent(hasContent: true, hasRecommendations: false, isLoading: false))
        #expect(!AppleDiscoverView.showsLoadingContent(hasContent: true, hasRecommendations: true, isLoading: false))
    }

    @Test func initialPreparationKeepsTheSkeletonUntilAnAnswerArrives() {
        #expect(AppleDiscoverView.showsLoadingContent(hasContent: true, hasRecommendations: false, isLoading: true))
        #expect(AppleDiscoverView.showsLoadingContent(hasContent: false, hasRecommendations: false, isLoading: true))
        #expect(!AppleDiscoverView.showsLoadingContent(hasContent: true, hasRecommendations: true, isLoading: true))
    }

    private func source() -> AppleSource {
        AppleSource(kind: .stremio, name: "Fixture", url: URL(string: "https://fixture.example/manifest.json")!,
            resources: ["catalog", "meta"])
    }
}
