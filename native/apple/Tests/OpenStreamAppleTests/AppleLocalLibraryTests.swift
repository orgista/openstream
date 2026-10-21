import Foundation
import Observation
import Testing
@testable import OpenStreamApple

@MainActor @Test func localTitleMatchingPrefersIMDbAndDistinguishesRemakes() {
    let movie = AppleCatalogItem(mediaID: "tt1160419", type: "movie", name: "Dune", releaseInfo: "2021")
    #expect(AppleLocalLibraryStore.matches(movie, .init(mediaID: "tt1160419", type: "movie", name: "Dune: Part One", releaseInfo: "2021")))
    #expect(!AppleLocalLibraryStore.matches(movie, .init(mediaID: "tt0087182", type: "movie", name: "Dune", releaseInfo: "1984")))
    #expect(AppleLocalLibraryStore.matches(movie, .init(mediaID: "local-file", type: "movie", name: "DÚNE", releaseInfo: "2021–")))
    #expect(!AppleLocalLibraryStore.matches(movie, .init(mediaID: "local-file", type: "movie", name: "Dune", releaseInfo: "1984")))
    #expect(!AppleLocalLibraryStore.matches(movie, .init(mediaID: "local-file", type: "series", name: "Dune", releaseInfo: "2021")))
}

@MainActor @Test func indexedGroupMatchingAnswersLikeMatchingEveryGroup() {
    let source = UUID()
    let files = ["Dune.2021.2160p.mkv", "Dune (1984).mkv", "DÚNE 2021 1080p.mkv", "Show.S01E01.mkv", "Arrival.2016.mkv"].map {
        AppleLibraryItem(sourceID: source, name: $0, url: URL(fileURLWithPath: "/" + $0), relativePath: $0, sizeBytes: 1)
    }
    let store = AppleLocalLibraryStore(groups: AppleLibrarySeries.groups(files), sources: [])
    let queries: [AppleCatalogItem] = [
        .init(mediaID: "tt1160419", type: "movie", name: "Dune", releaseInfo: "2021"),
        .init(mediaID: "local-x", type: "movie", name: "dune", releaseInfo: "1984"),
        .init(mediaID: "tt0087182", type: "series", name: "Dune", releaseInfo: "1984"),
        .init(mediaID: "tt123", type: "series", name: "Show"),
        .init(mediaID: "tt2543164", type: "movie", name: "Arrival", releaseInfo: "2016–"),
        .init(mediaID: "tt0000000", type: "movie", name: "Nothing Here", releaseInfo: "2001"),
    ]
    for query in queries {
        let expected = store.groups.filter { AppleLocalLibraryStore.matches(store.catalogItem(for: $0), query) }
        #expect(store.matchingGroups(query).map(\.id) == expected.map(\.id), "\(query.name) \(query.releaseInfo ?? "")")
    }
    #expect(!store.matchingGroups(queries[0]).isEmpty)
}

@MainActor @Test(arguments: [true, false])
func matchingGroupsKeepsItsSnapshotUntilTheNewRevisionIsPublished(hasIMDb: Bool) throws {
    let file = AppleLibraryItem(sourceID: UUID(), name: "Example.Film.2020.mkv",
        url: URL(fileURLWithPath: "/Example.Film.2020.mkv"), relativePath: "Example.Film.2020.mkv", sizeBytes: 1)
    let groups = AppleLibrarySeries.groups([file])
    let store = AppleLocalLibraryStore(groups: groups)
    let query = AppleCatalogItem(mediaID: hasIMDb ? "tt1234567" : "fixture", type: "movie", name: "Example Film", releaseInfo: "2020")
    let original = store.matchingGroups(query)
    _ = try #require(original.first)
    let observed = SortObservationChangeFlag()
    withObservationTracking {
        _ = store.contentRevision
    } onChange: {
        // Observation invokes this synchronously from the MainActor reset below.
        MainActor.assumeIsolated {
            #expect(store.matchingGroups(query).map(\.id) == original.map(\.id))
            observed.changed = true
        }
    }
    store.discardAfterReset()
    #expect(observed.changed)
    #expect(store.matchingGroups(query).isEmpty)
}

@MainActor @Test func localSeasonRowsKeepUncatalogedEpisodesAndDeduplicateCopies() {
    let source = UUID()
    let files = ["Show.S01E01.1080p.mkv", "Show.S01E01.2160p.mkv", "Show.S02E03.1080p.mkv"].map {
        AppleLibraryItem(sourceID: source, name: $0, url: URL(fileURLWithPath: "/" + $0), relativePath: $0, sizeBytes: 1)
    }
    let group = AppleLibrarySeries.groups(files)[0]
    let enriched = AppleStremioEpisode(id: "tt123:1:1", title: "Pilot", season: 1, episode: 1, overview: "Overview")
    let episodes = AppleLocalLibraryStore.episodes(group: group, mediaID: "tt123", enriched: [enriched])
    #expect(episodes.count == 2)
    #expect(episodes[0] == enriched)
    #expect(episodes[1].season == 2)
    #expect(episodes[1].episode == 3)
    #expect(AppleLocalLibraryStore.format(files[0]) == "1080P · MKV")
    let store = AppleLocalLibraryStore()
    let selected = store.localFiles(for: .init(mediaID: "tt123", type: "series", name: "Show"), group: group, episode: episodes[0])
    #expect(selected.count == 2)
    #expect(selected.first?.name == "Show.S01E01.2160p.mkv")
    #expect(store.localFiles(for: .init(mediaID: "tt123", type: "series", name: "Show"), group: group, episode: episodes[1]).count == 1)
}

@MainActor @Test func localUnnumberedEpisodePlaysTheFileShownByItsRow() {
    let file = AppleLibraryItem(sourceID: UUID(), name: "Pilot.mkv", url: URL(fileURLWithPath: "/Pilot.mkv"),
        relativePath: "Shows/Example/Season 1/Pilot.mkv", sizeBytes: 1)
    let group = AppleLibrarySeries.groups([file])[0]
    let episodes = AppleLocalLibraryStore.episodes(group: group, mediaID: "local-example", enriched: [])
    let files = AppleLocalLibraryStore().localFiles(for: .init(mediaID: "local-example", type: "series", name: "Example"),
        group: group, episode: episodes[0])
    #expect(files == [file])
}

@MainActor @Test func localSeriesResumesLatestUnfinishedEpisodeAcrossSeasons() {
    let source = UUID()
    let files = ["Example.S01E01.mkv", "Example.S02E03.mkv", "Example.S02E04.mkv"].map {
        AppleLibraryItem(sourceID: source, name: $0, url: URL(fileURLWithPath: "/" + $0), relativePath: $0, sizeBytes: 1)
    }
    let groups = AppleLibrarySeries.groups(files)
    let episodes = AppleLocalLibraryStore.episodes(group: groups[0], mediaID: "tt-example", enriched: [])
    let resumed = AppleLocalLibraryStore.resumeEpisode(in: groups, episodes: episodes) { file in
        let number = files.firstIndex(of: file)!
        return ApplePlaybackProgress(position: number == 2 ? 1000 : 120, duration: 1000,
            updatedAt: Date(timeIntervalSince1970: Double(number + 1)))
    }
    #expect(resumed?.season == 2)
    #expect(resumed?.episode == 3)
}

/// Library shelves read nothing but `sorted(...)` in their body. Once the
/// sort is memoised, the cached answer must still register `groups` and
/// `metadata`, or a title's metadata landing never redraws the shelf.
@MainActor @Test(.timeLimit(.minutes(1))) func memoisedLibrarySortStillObservesTheLibrary() async throws {
    let file = AppleLibraryItem(sourceID: UUID(), name: "Example.Film.2020.mkv",
        url: URL(fileURLWithPath: "/Example.Film.2020.mkv"), relativePath: "Example.Film.2020.mkv", sizeBytes: 1)
    let group = AppleLibrarySeries.groups([file])[0]
    // `resolve` goes through the shared resolver, whose disk cache answers
    // before any lookup; seed it so the metadata update needs no network.
    let folder = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("LibraryTitles-v1").appendingPathComponent(file.sourceID.uuidString)
    defer { try? FileManager.default.removeItem(at: folder) }
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let item = AppleCatalogItem(mediaID: "tt0000001", type: "movie", name: "Example Film", releaseInfo: "2020")
    try JSONEncoder().encode(SeededMetadataEntry(value: item, checkedAt: Date(), addedAt: Date(), schema: 2))
        .write(to: folder.appendingPathComponent(AppleLibraryMetadataResolver.cacheKey(file) + ".json"))
    let suite = "memoised-sort-\(UUID())"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let sourceStore = AppleSourceStore(defaults: defaults, keychain: SortObservationCredentialStub(),
        documentsDirectory: FileManager.default.temporaryDirectory.appending(path: suite))
    let settings = AppleSettingsStore(defaults: defaults, keychain: SortObservationCredentialStub())

    let store = AppleLocalLibraryStore()
    _ = store.sorted(.title)
    let flag = SortObservationChangeFlag()
    withObservationTracking {
        _ = store.sorted(.title)
    } onChange: {
        Task { @MainActor in flag.changed = true }
    }
    await store.resolve(group, sourceStore: sourceStore, settings: settings)
    #expect(store.metadata[group.id] == item)
    while !flag.changed { try await Task.sleep(for: .milliseconds(10)) }
    #expect(flag.changed)
}

private struct SeededMetadataEntry: Encodable {
    let value: AppleCatalogItem?
    let checkedAt: Date
    let addedAt: Date
    let schema: Int
}

private struct SortObservationCredentialStub: AppleCredentialStoring {
    func string(for account: String) throws -> String? { nil }
    func set(_ value: String, for account: String) throws {}
    func remove(_ account: String) throws {}
}

@MainActor
private final class SortObservationChangeFlag {
    var changed = false
}

@MainActor @Test func unnumberedLocalEpisodesReadLegacyWatchedWithoutRewritingHistory() throws {
    let suite = "local-legacy-watched-\(UUID())"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let store = ApplePlaybackStore(defaults: defaults)
    let source = UUID()
    let files = ["Pilot.mkv", "Finale.mkv"].map {
        AppleLibraryItem(sourceID: source, name: $0, url: URL(fileURLWithPath: "/" + $0),
            relativePath: "Shows/Example/Season 1/" + $0, sizeBytes: 1)
    }
    var group = try #require(AppleLibrarySeries.groups([files[0]]).first)
    group.items = files
    let episodes = AppleLocalLibraryStore.episodes(group: group, mediaID: "tt-example", enriched: [])
    let watchedAt = Date(timeIntervalSince1970: 100)
    store.markWatched(mediaID: "tt-example:1:1", at: watchedAt)
    let originalHistory = store.configurationWatchedHistory()
    let completed = AppleLocalLibraryStore.completedEpisodeIDs(episodes, group: group, mediaID: "tt-example", store: store)
    #expect(completed == [episodes[0].id])
    #expect(episodes[0].id == AppleLocalLibraryStore.fileEpisodeID(files[0]))
    #expect(AppleLocalLibraryStore.nextFilenameEpisode(in: episodes, completedIDs: completed)?.id == episodes[1].id)
    #expect(store.configurationWatchedHistory() == originalHistory)
    #expect(store.configurationWatchedHistory()[episodes[0].id] == nil)
    store.markUnwatched(mediaID: episodes[0].id, at: watchedAt.addingTimeInterval(1))
    #expect(AppleLocalLibraryStore.completedEpisodeIDs(episodes, group: group, mediaID: "tt-example", store: store).isEmpty)
    let legacyKey = try #require(ApplePlaybackIdentity.storageKey(for: "tt-example:1:1"))
    #expect(store.configurationWatchedHistory()[legacyKey] == watchedAt)
    store.markWatched(mediaID: episodes[0].id, at: watchedAt.addingTimeInterval(2))
    #expect(AppleLocalLibraryStore.completedEpisodeIDs(episodes, group: group, mediaID: "tt-example", store: store) == [episodes[0].id])
}

@MainActor @Test func legacyUnwatchedLocalEpisodeDoesNotRegainItsTick() throws {
    let suite = "local-legacy-reset-\(UUID())"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let store = ApplePlaybackStore(defaults: defaults)
    let file = AppleLibraryItem(sourceID: UUID(), name: "Pilot.mkv", url: URL(fileURLWithPath: "/Pilot.mkv"),
        relativePath: "Shows/Example/Season 1/Pilot.mkv", sizeBytes: 1)
    let group = try #require(AppleLibrarySeries.groups([file]).first)
    let episodes = AppleLocalLibraryStore.episodes(group: group, mediaID: "tt-example", enriched: [])
    store.markWatched(mediaID: "tt-example:1:1", at: Date(timeIntervalSince1970: 100))
    store.markUnwatched(mediaID: "tt-example:1:1", at: Date(timeIntervalSince1970: 101))
    #expect(AppleLocalLibraryStore.completedEpisodeIDs(episodes, group: group, mediaID: "tt-example", store: store).isEmpty)
}

@MainActor @Test func filenameAliasDoesNotBorrowDeduplicatedNumberedEpisodeHistory() throws {
    let suite = "local-legacy-dedup-\(UUID())"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let store = ApplePlaybackStore(defaults: defaults)
    let source = UUID()
    let numbered = AppleLibraryItem(sourceID: source, name: "Example.S01E02.mkv", url: URL(fileURLWithPath: "/Example.S01E02.mkv"),
        relativePath: "Shows/Example/Season 1/Example.S01E02.mkv", sizeBytes: 1)
    let filename = AppleLibraryItem(sourceID: source, name: "Pilot.mkv", url: URL(fileURLWithPath: "/Pilot.mkv"),
        relativePath: "Shows/Example/Season 1/Pilot.mkv", sizeBytes: 1)
    var group = try #require(AppleLibrarySeries.groups([numbered]).first)
    group.items = [numbered, filename]
    let episodes = AppleLocalLibraryStore.episodes(group: group, mediaID: "tt-example", enriched: [])
    store.markWatched(mediaID: "tt-example:1:2", at: Date(timeIntervalSince1970: 100))
    let completed = AppleLocalLibraryStore.completedEpisodeIDs(episodes, group: group, mediaID: "tt-example", store: store)
    #expect(completed == ["tt-example:1:2"])
    #expect(completed.contains(AppleLocalLibraryStore.fileEpisodeID(filename)) == false)
}

@MainActor @Test(.timeLimit(.minutes(1)))
func cancelledLibraryReloadAllowsWaitingReloadWithNewestSources() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let firstFolder = root.appendingPathComponent("first")
    let newestFolder = root.appendingPathComponent("newest")
    for folder in [firstFolder, newestFolder] {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("fixture".utf8).write(to: folder.appendingPathComponent(folder.lastPathComponent + ".2020.mkv"))
    }
    let suite = "library-reload-\(UUID())"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let sourceStore = AppleSourceStore(defaults: defaults, keychain: SortObservationCredentialStub(),
        documentsDirectory: root.appendingPathComponent("documents"))
    let settings = AppleSettingsStore(defaults: defaults, keychain: SortObservationCredentialStub())
    let firstSource = try sourceStore.addLibraryFolder(name: "First", url: firstFolder, bookmarkData: nil)
    let probe = LibraryReloadMatchProbe()
    let resolver = AppleLibraryMetadataResolver(directory: root.appendingPathComponent("metadata")) { title, _, _, _ in
        await probe.lookup(title.title)
    }
    let library = AppleLocalLibraryStore(resolver: resolver, playbackStore: ApplePlaybackStore(defaults: defaults),
        versionCacheURL: root.appendingPathComponent("versions.json"))
    let index = AppleMediaIndexStore(repository: AppleMediaIndexRepository(fileURL: root.appendingPathComponent("index.json")))
    let first = Task { await library.reload(sourceStore: sourceStore, mediaIndex: index, settings: settings) }
    await probe.waitUntilStarted()
    #expect(library.isLoading)
    let newestSource = try sourceStore.addLibraryFolder(name: "Newest", url: newestFolder, bookmarkData: nil)
    let started = AsyncStream<Void>.makeStream()
    var secondFinished = false
    let second = Task {
        started.continuation.yield(())
        await library.reload(sourceStore: sourceStore, mediaIndex: index, settings: settings)
        secondFinished = true
    }
    var iterator = started.stream.makeAsyncIterator()
    _ = await iterator.next()
    #expect(!secondFinished)
    first.cancel()
    await first.value
    await probe.finish()
    await second.value
    #expect(!library.isLoading)
    #expect(Set(library.groups.flatMap(\.items).map(\.sourceID).filter { $0 != AppleLocalLibraryStore.downloadsID }) == [firstSource.id, newestSource.id])
    #expect(Set(library.sources.map(\.id).filter { $0 != AppleLocalLibraryStore.downloadsID }) == [firstSource.id, newestSource.id])
    #expect(index.records.contains { $0.title.localizedCaseInsensitiveContains("newest") })
}

private actor LibraryReloadMatchProbe {
    private var calls = 0
    private var started: CheckedContinuation<Void, Never>?
    private var response: CheckedContinuation<Void, Never>?

    func lookup(_ title: String) async -> AppleCatalogItem? {
        calls += 1
        if calls == 1 {
            await withCheckedContinuation { continuation in
                response = continuation
                started?.resume()
                started = nil
            }
        }
        return AppleCatalogItem(mediaID: "local-" + title, type: "movie", name: title)
    }

    func waitUntilStarted() async {
        if calls > 0 { return }
        await withCheckedContinuation { started = $0 }
    }

    func finish() {
        response?.resume()
        response = nil
    }
}
