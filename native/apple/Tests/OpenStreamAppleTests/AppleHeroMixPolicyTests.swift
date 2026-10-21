import Foundation
import Testing
@testable import OpenStreamApple

@Suite("Discover hero mix")
struct AppleHeroMixPolicyTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func candidate(_ id: String, resume: Double? = nil, relevant: Bool = false,
                           age: Double? = nil, watched: Bool = false, completed: Bool = false,
                           disliked: Bool = false, accessible: Bool = true, art: Bool = true) -> AppleHeroMixPolicy.Candidate {
        .init(id: id, resumeAt: resume.map { now.addingTimeInterval($0) }, relevant: relevant,
              releaseDate: age.map { now.addingTimeInterval(-$0 * 86_400) },
              state: .init(meaningfulProgress: watched, completed: completed, disliked: disliked),
              accessible: accessible, hasBackdrop: art)
    }
    private func ids(_ values: [AppleHeroMixPolicy.Candidate]) -> [String] {
        AppleHeroMixPolicy.select(values, now: now)
    }

    @Test(arguments: [0, 1, 5]) func resumePrecedenceAndQuotas(count: Int) {
        let resumes = (0..<count).map { candidate("resume\($0)", resume: Double(-$0)) }
        let values = resumes + [candidate("pick1", relevant: true), candidate("pick2", relevant: true),
                                candidate("pick3", relevant: true), candidate("release", age: 2)]
        let deck = ids(values)
        if count > 0 { #expect(deck.first == "resume0") }
        #expect(deck.contains("pick1"))
        #expect(deck.contains("pick2"))
        #expect(deck.contains("release"))
        if count == 5 { #expect(deck == ["resume0", "pick1", "pick2", "release", "resume1"]) }
    }

    @Test func sparseAndNoConfidenceUseExistingOrder() {
        let values = [candidate("r1", resume: 0), candidate("r2", resume: -1), candidate("yearOnly")]
        #expect(ids(values) == values.map(\.id))
        #expect(ids([]).isEmpty)
    }

    @Test(arguments: [0.0, 90.0, 90.0001, -0.001]) func releaseWindow(age: Double) {
        let values = (0..<5).map { candidate("r\($0)", resume: Double(-$0)) } + [candidate("new", age: age)]
        #expect(ids(values).contains("new") == (age >= 0 && age <= 90))
    }

    @Test func yearAloneIsNotAReleaseDate() {
        #expect(AppleHeroMixPolicy.releaseDate("2026") == nil)
        #expect(AppleHeroMixPolicy.releaseDate("2026–2027") == nil)
        #expect(AppleHeroMixPolicy.releaseDate("2026-02-30") == nil)
        #expect(AppleHeroMixPolicy.releaseDate("2026-10-13") != nil)
        #expect(AppleHeroMixPolicy.releaseDate("2026-10-13T00:00:00.000Z") != nil)
    }

    @Test func watchedAndCompletedCannotTakeUnseenSlots() {
        let resumes = (0..<5).map { candidate("r\($0)", resume: Double(-$0)) }
        #expect(ids(resumes + [candidate("watched", relevant: true, age: 1, watched: true),
                               candidate("finished", relevant: true, age: 1, completed: true)]) == resumes.map(\.id))
    }

    @Test func dislikesAndInaccessibleAreExcludedEvenFromFallback() {
        #expect(ids([candidate("down", resume: 1, disliked: true), candidate("offline", accessible: false),
                     candidate("ok")]) == ["ok"])
    }

    @Test func latestResumeAndDeterministicTies() {
        let a = candidate("a", resume: 2), b = candidate("b", resume: 2), old = candidate("old", resume: 0)
        #expect(ids([old, b, a]).first == "a")
        #expect(ids([b, a, old]).first == "a")
        let r = (0..<5).map { candidate("r\($0)", resume: Double(-$0)) }
        #expect(ids(r + [candidate("z", age: 1), candidate("a", age: 1)])[1] == "a")
    }

    @Test func quotasDoNotDoubleCountSameTitle() {
        let r = (0..<5).map { candidate("r\($0)", resume: Double(-$0)) }
        #expect(ids(r + [candidate("both", relevant: true, age: 1), candidate("both", relevant: true),
                         candidate("pick", relevant: true), candidate("release", age: 2)])
                == ["r0", "both", "pick", "release", "r1"])
    }

    @Test func artworkGateAndArtlessFallback() {
        #expect(ids([candidate("noArt", resume: 0, art: false), candidate("art")]) == ["art"])
        #expect(ids([candidate("noArt", art: false)]) == ["noArt"])
        #expect(AppleHeroRotation.interval == 6)
    }

    @Test func sectionsAreGatheredRoundRobin() {
        #expect(AppleHeroMixPolicy.fairlyGather([[1, 2, 3], [], [4, 5], [6]]) == [1, 4, 6, 2, 5, 3])
    }

    @Test func canonicalIdentityKeepsKindAndStableRepresentative() {
        let movie = AppleCatalogItem(mediaID: "tt0000001", type: "movie", name: "Title")
        let duplicate = AppleCatalogItem(mediaID: "other", type: "movie", name: "Title", imdbID: "tt0000001")
        let series = AppleCatalogItem(mediaID: "tt0000001", type: "series", name: "Title")
        #expect(AppleRecommendationInputs.identity(movie) == AppleRecommendationInputs.identity(duplicate))
        #expect(AppleRecommendationInputs.identity(movie) != AppleRecommendationInputs.identity(series))
        #expect(AppleRecommendationInputs.prefers(duplicate, sourceID: "b", accessible: true,
            over: movie, sourceID: "a", accessible: true))
        #expect(AppleRecommendationInputs.prefers(movie, sourceID: "a", accessible: true,
            over: movie, sourceID: "b", accessible: true))
    }

    @Test func duplicateWatchStateIsConservative() {
        var state = AppleHeroMixPolicy.State()
        state.merge(.init(meaningfulProgress: true))
        state.merge(.init(completed: true, disliked: true))
        state.merge(.init())
        #expect(state.meaningfulProgress)
        #expect(state.completed)
        #expect(state.disliked)
    }

    @Test func releaseYearAndCompletenessDoNotCreateAffinity() {
        let title = AppleRankableTitle(id: "yearOnly", genres: [], releaseYear: 2026,
            metadataCompleteness: 1, isResumable: false, isCompleted: false)
        let ranked = AppleRecommendationRanker.rankWithProvenance([title], history: [], ratings: [:],
            now: now, limit: 1, requiresAffinity: true)
        #expect(ranked.isEmpty)
    }

    @Test func relevantAndReleaseFromLaterSectionsParticipate() {
        let r = (0..<5).map { candidate("r\($0)", resume: Double(-$0)) }
        let gathered = AppleHeroMixPolicy.fairlyGather([
            [candidate("ordinary")], [candidate("relevant", relevant: true)], [candidate("release", age: 1)]])
        #expect(ids(r + gathered) == ["r0", "relevant", "release", "r1", "r2"])
    }

    @Test func meaningfulProgressBoundaries() {
        func state(_ position: Double, _ duration: Double) -> AppleHeroMixPolicy.State {
            AppleHeroMixPolicy.watchState(progress: [.init(position: position, duration: duration)],
                                         completed: false, recordProgress: nil, disliked: false)
        }
        #expect(state(1, 1000).meaningfulProgress == false)
        #expect(state(50, 1000).meaningfulProgress)
        #expect(state(60, 10000).meaningfulProgress)
        #expect(state(.nan, 1000).meaningfulProgress == false)
        #expect(state(1000, 1000).completed)
    }

    @MainActor private func resume(_ id: String, source: AppleSource, at: Date?, type: String = "movie") -> AppleDiscoverView.IndexedCatalogItem {
        let item = AppleCatalogItem(mediaID: id, type: type, name: id,
            backgroundURL: URL(string: "https://fixture.example/backdrop.jpg"))
        return .init(record: AppleMediaIngestion.catalogRecord(instanceID: source.id, item: item),
                     item: item, source: source, continueWatchingUpdatedAt: at)
    }

    @MainActor private func recommendations(_ resumes: [AppleDiscoverView.IndexedCatalogItem], sources: [AppleSource]) async throws -> AppleDiscoverView.RecommendationResult {
        try await AppleDiscoverView.buildRecommendations(.init(sections: [], relations: [], sources: sources,
            records: [], lookup: AppleCatalogSearchLookup(), progress: [:], activity: [:], availableEpisodes: [:],
            completed: [:], unwatched: [:], removed: [:], ratings: [:], serverContinueWatching: resumes,
            serverShelves: [], artwork: [:], debugHeroTitle: nil, now: now))
    }

    @MainActor @Test func undatedServerResumeDoesNotBeatRealWatchDate() async throws {
        let source = AppleSource(kind: .mediaServer, name: "Fixture", url: URL(string: "https://fixture.example")!)
        let undated = resume(AppleMediaServerItemReference(sourceID: source.id, itemID: "a").mediaID, source: source, at: nil)
        let dated = resume(AppleMediaServerItemReference(sourceID: source.id, itemID: "z").mediaID, source: source, at: Date(timeIntervalSince1970: 1_700_000_000))
        let result = try await recommendations([undated, dated], sources: [source])
        #expect(result.heroes.first?.id == dated.id)
    }

    @MainActor @Test(arguments: [AppleXtreamReference.Kind.movie, .series])
    func xtreamResumesRemainHeroEligible(kind: AppleXtreamReference.Kind) async throws {
        let source = AppleSource(kind: .liveTV, name: "Fixture", url: URL(string: "https://fixture.example")!)
        let value = resume(AppleXtreamReference(sourceID: source.id, kind: kind, providerID: "1").mediaID, source: source, at: now, type: kind == .series ? "series" : "movie")
        let result = try await recommendations([value], sources: [source])
        #expect(result.heroes.map(\.id) == [value.id])
        var disabled = source
        disabled.isEnabled = false
        #expect(try await recommendations([value], sources: [disabled]).heroes.isEmpty)
    }

    @MainActor @Test(arguments: [AppleXtreamReference.Kind.movie, .series])
    func mergedXtreamResumeUsesTitlePageRecordWatchDate(kind: AppleXtreamReference.Kind) async throws {
        let suiteName = "ship19.xtream.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = ApplePlaybackStore(defaults: defaults)
        let source = AppleSource(kind: .liveTV, name: "Fixture", url: URL(string: "https://fixture.example")!)
        let reference = AppleXtreamReference(sourceID: source.id, kind: kind, providerID: "1")
        let value = resume(reference.mediaID, source: source, at: nil, type: kind == .series ? "series" : "movie")
        // The title page writes both movies and series under progressRecordID, with an episode part for series.
        store.save(mediaID: value.record.id, position: 600, duration: 1200,
            partID: kind == .series ? reference.mediaID + ":1:1" : nil)
        let activity = try #require(store.lastActivity(for: value.record.id))
        #expect(store.lastActivity(for: value.item.mediaID) == nil)

        let merged = AppleDiscoverView.mergedContinueWatching(local: [],
            mediaServerLibrary: AppleMediaServerLibraryStore(progressDefaults: defaults),
            xtreamItems: [value.item], xtreamSource: { $0 == reference ? source : nil },
            sources: [source], playbackStore: store)
        let resumed = try #require(merged.first)
        #expect(merged.count == 1)
        #expect(resumed.record.progress == 0.5)
        #expect(resumed.continueWatchingUpdatedAt == activity.updatedAt)

        let olderSource = AppleSource(kind: .mediaServer, name: "Older fixture", url: URL(string: "https://fixture.example")!)
        let older = resume(AppleMediaServerItemReference(sourceID: olderSource.id, itemID: "older").mediaID,
            source: olderSource, at: activity.updatedAt.addingTimeInterval(-86_400))
        let result = try await recommendations([older] + merged, sources: [olderSource, source])
        #expect(result.heroes.first?.id == value.id)
    }

    @MainActor @Test func displacedHeroResumesRemainInContinueWatching() async throws {
        let source = AppleSource(kind: .mediaServer, name: "Fixture", url: URL(string: "https://fixture.example")!)
        let values = (0..<8).map { index in
            resume(AppleMediaServerItemReference(sourceID: source.id, itemID: "item\(index)").mediaID,
                   source: source, at: now.addingTimeInterval(Double(-index)))
        }
        let result = try await recommendations(values, sources: [source])
        #expect(result.heroes.count == AppleHeroRotation.maximumCandidates)
        #expect(result.continueWatching.map(\.id) == values.map(\.id))
        #expect(Set(result.continueWatching.map(\.id)).subtracting(result.heroes.map(\.id)).count == 3)
    }

    @Test func releaseDayFormatterIsReused() {
        #expect(AppleHeroMixPolicy.releaseDayFormatter === AppleHeroMixPolicy.releaseDayFormatter)
    }

    @MainActor @Test(arguments: [false, true])
    func revalidationPreservesCachedHeroesAndRows(catalogChanged: Bool) async throws {
        let catalog = AppleStremioCatalog(type: "movie", id: "top")
        let source = AppleSource(kind: .stremio, name: "Fixture",
            url: try #require(URL(string: "https://fixture.example/manifest.json")),
            resources: ["catalog", "meta"], catalogs: [catalog])
        let items = (1...12).map { index in
            AppleCatalogItem(mediaID: String(format: "tt%07d", index), type: "movie", name: "Fixture \(index)",
                backgroundURL: URL(string: "https://fixture.example/\(index).jpg"),
                releaseInfo: "2026", genres: ["Action"], year: 2026)
        }
        let section = AppleCatalogSection(source: source, catalog: catalog, items: items)
        var records = items.map { AppleMediaIngestion.catalogRecord(instanceID: source.id, item: $0, verifiedAt: now) }
        records[0].isFavorite = true
        let resumeKey = try #require(ApplePlaybackIdentity.storageKey(for: records[0].id))
        let watchedKey = try #require(ApplePlaybackIdentity.storageKey(for: records[1].id))
        let progress = ApplePlaybackProgress(position: 120, duration: 1200, updatedAt: now)
        let otherRecords = [AppleMediaKind.channel, .video].map { kind in
            AppleMediaRecord(kind: kind, title: "Fixture \(kind.rawValue)", availability: [
                .init(instanceID: source.id, capability: .direct, itemReference: kind.rawValue)
            ])
        }
        var saved = [resumeKey: progress]
        for record in otherRecords {
            let key = try #require(ApplePlaybackIdentity.storageKey(for: record.id))
            saved[key] = ApplePlaybackProgress(position: 120, duration: 1200, updatedAt: now.addingTimeInterval(60))
        }
        func snapshot(_ records: [AppleMediaRecord], section: AppleCatalogSection) -> AppleDiscoverView.RecommendationSnapshot {
            .init(sections: [section], relations: [], sources: [source], records: records,
                lookup: AppleCatalogSearchLookup(sections: [section], sources: [source]),
                progress: saved, activity: saved, availableEpisodes: [:],
                completed: [watchedKey: now], unwatched: [:], removed: [:],
                ratings: [ApplePlaybackIdentity.digest(for: items[2].mediaID): .down],
                serverContinueWatching: [], serverShelves: [], artwork: [:], debugHeroTitle: nil, now: now)
        }
        let input = snapshot(records + records + otherRecords, section: section)
        let original = try await AppleDiscoverView.buildRecommendations(input)
        #expect(original.heroes.first?.item.mediaID == items[0].mediaID)
        #expect(!original.heroes.contains { $0.item.mediaID == items[2].mediaID })
        #expect(original.continueWatching.map(\.item.mediaID) == [items[0].mediaID])
        #expect(!original.picks.isEmpty)
        #expect(original.seedHeading != nil)
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = AppleMetadataDiskCache(directory: directory)
        let state = AppleDiscoverRecommendationCache.WatchState(progress: input.progress, activity: input.activity,
            completed: input.completed, unwatched: input.unwatched, removed: input.removed,
            ratings: input.ratings.mapValues(\.rawValue))
        let key = try #require(await AppleDiscoverRecommendationCache.key(scope: "revalidation", state: state, indexURL: nil))
        let favoriteIDs: Set<String> = [records[0].id]
        await AppleDiscoverRecommendationCache.store(original, key: key, favoriteIDs: favoriteIDs, cache: cache)
        let restored = try #require(await AppleDiscoverRecommendationCache.restore(key, sources: [source], cache: cache))
        #expect(restored.heroes.first?.record.isFavorite == true)
        var refreshedItems = items
        if catalogChanged {
            refreshedItems[0] = AppleCatalogItem(mediaID: items[0].mediaID, type: "movie", name: "Updated Fixture 1",
                backgroundURL: URL(string: "https://fixture.example/updated.jpg"),
                releaseInfo: "2026", genres: ["Action"], year: 2026)
        }
        let refreshedSection = AppleCatalogSection(source: source, catalog: catalog, items: refreshedItems)
        let fresh = try await AppleDiscoverView.buildRecommendations(snapshot(input.records, section: refreshedSection))
        #expect(restored.heroes.map(\.id) == fresh.heroes.map(\.id))
        if catalogChanged {
            #expect(restored.heroes.first?.item == items[0])
            #expect(fresh.heroes.first?.item == refreshedItems[0])
            #expect(restored.heroes.first?.item != fresh.heroes.first?.item)
            #expect(restored.seedHeading != fresh.seedHeading)
            #expect(fresh.seedHeading?.contains(refreshedItems[0].name) == true)
            await AppleDiscoverRecommendationCache.store(fresh, key: key, favoriteIDs: favoriteIDs, cache: cache)
            let revalidated = try #require(await AppleDiscoverRecommendationCache.restore(key, sources: [source], cache: cache))
            #expect(revalidated.heroes.map(\.item) == fresh.heroes.map(\.item))
            #expect(revalidated.heroes.first?.record.isFavorite == true)
            #expect(revalidated.seedHeading == fresh.seedHeading)
        } else {
            #expect(restored.heroes.map(\.item) == fresh.heroes.map(\.item))
            #expect(restored.seedHeading == fresh.seedHeading)
        }
        #expect(restored.heroes.map(\.source.id) == fresh.heroes.map(\.source.id))
        #expect(restored.picks.map(\.id) == fresh.picks.map(\.id))
        #expect(restored.continueWatching.map(\.id) == fresh.continueWatching.map(\.id))
        #expect(restored.seedItems.map(\.id) == fresh.seedItems.map(\.id))
    }

    @MainActor @Test(arguments: [true, false])
    func indexedVideoKeepsItsCatalogResume(hasCanonicalID: Bool) async throws {
        let catalog = AppleStremioCatalog(type: "movie", id: "top")
        let source = AppleSource(kind: .stremio, name: "Fixture",
            url: try #require(URL(string: "https://fixture.example/manifest.json")),
            resources: ["catalog", "meta"], catalogs: [catalog])
        let item = AppleCatalogItem(mediaID: "tt1234567", type: "movie", name: "Fixture",
            backgroundURL: URL(string: "https://fixture.example/backdrop.jpg"))
        let section = AppleCatalogSection(source: source, catalog: catalog, items: [item])
        let catalogRecord = AppleMediaIngestion.catalogRecord(instanceID: source.id, item: item)
        let record = AppleMediaRecord(canonicalID: hasCanonicalID ? item.mediaID : nil, kind: .video,
            title: item.name, availability: catalogRecord.availability)
        let key = try #require(ApplePlaybackIdentity.storageKey(for: record.id))
        let progress = ApplePlaybackProgress(position: 120, duration: 1200, updatedAt: now)
        let snapshot = AppleDiscoverView.RecommendationSnapshot(sections: [section], relations: [], sources: [source],
            records: [record], lookup: AppleCatalogSearchLookup(sections: [section], sources: [source]),
            progress: [key: progress], activity: [key: progress], availableEpisodes: [:], completed: [:],
            unwatched: [:], removed: [:], ratings: [:], serverContinueWatching: [], serverShelves: [],
            artwork: [:], debugHeroTitle: nil, now: now)
        let result = try await AppleDiscoverView.buildRecommendations(snapshot)
        #expect(result.continueWatching.map(\.id) == [record.id])
        #expect(result.continueWatching.first?.continueWatchingUpdatedAt == now)
        #expect(result.heroes.first?.item.mediaID == item.mediaID)
    }

}
