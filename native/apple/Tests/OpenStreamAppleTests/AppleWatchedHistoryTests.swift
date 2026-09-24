import Foundation
import Testing
@testable import OpenStreamApple

@Suite("Watched history")
struct AppleWatchedHistoryTests {
    private let suiteName = "watched-history-tests.\(UUID())"

    @MainActor
    private func makeStore() throws -> (ApplePlaybackStore, UserDefaults) {
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        return (ApplePlaybackStore(defaults: defaults), defaults)
    }

    private func episode(_ season: Int, _ number: Int) -> AppleStremioEpisode {
        AppleStremioEpisode(id: "tt0903747:\(season):\(number)", title: "", season: season, episode: number, releaseInfo: nil)
    }

    private func key(_ mediaID: String) throws -> String {
        try #require(ApplePlaybackIdentity.storageKey(for: mediaID))
    }

    // MARK: Store

    @MainActor @Test func finishingAnEpisodeRecordsItAndStillLeavesContinueWatching() throws {
        let (store, defaults) = try makeStore()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let show = "fixture-show", part = episode(1, 1).id
        store.save(mediaID: show, position: 600, duration: 3_000, partID: part)
        #expect(store.progress(for: show) != nil)
        #expect(!store.isWatched(mediaID: part))

        store.save(mediaID: show, position: 2_990, duration: 3_000, partID: part)
        #expect(store.progress(for: show) == nil)
        #expect(store.isWatched(mediaID: part))
        #expect(!store.isWatched(mediaID: show))
        #expect(store.completedMediaIDs(among: [part, episode(1, 2).id]) == [part])
    }

    @MainActor @Test func finishingAFilmRecordsTheFilm() throws {
        let (store, defaults) = try makeStore()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        store.save(mediaID: "fixture-film", position: 5_990, duration: 6_000)
        #expect(store.progress(for: "fixture-film") == nil)
        #expect(store.isWatched(mediaID: "fixture-film"))
        // A fresh reader over the same defaults sees it too.
        #expect(ApplePlaybackStore(defaults: defaults).isWatched(mediaID: "fixture-film"))
    }

    @MainActor @Test func rewatchingPastTheResumeThresholdKeepsTheTick() throws {
        let (store, defaults) = try makeStore()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let show = "fixture-show", part = episode(1, 1).id
        store.save(mediaID: show, position: 2_990, duration: 3_000, partID: part)
        store.save(mediaID: show, position: 400, duration: 3_000, partID: part)
        #expect(store.isWatched(mediaID: part))
        #expect(store.progress(for: show)?.resumePosition(for: part) == 400)
    }

    @MainActor @Test func markAndUnmarkWatched() throws {
        let (store, defaults) = try makeStore()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let part = episode(2, 4).id
        store.markWatched(mediaID: part)
        #expect(store.isWatched(mediaID: part))
        store.markUnwatched(mediaID: part)
        #expect(!store.isWatched(mediaID: part))
        #expect(ApplePlaybackStore(defaults: defaults).configurationWatchedHistory().isEmpty)
    }

    @MainActor @Test func markingWatchedMovesTheFeed() throws {
        let (store, defaults) = try makeStore()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let before = ApplePlaybackProgressFeed.shared.revision
        store.markWatched(mediaID: episode(1, 1).id)
        #expect(ApplePlaybackProgressFeed.shared.revision != before)
    }

    @Test func historyKeepsTheNewestEntries() {
        let entries = Dictionary(uniqueKeysWithValues: (0..<10).map {
            ("id-\($0)", Date(timeIntervalSince1970: Double($0)))
        })
        let bounded = ApplePlaybackStore.boundedWatchedHistory(entries, limit: 3)
        #expect(Set(bounded.keys) == ["id-7", "id-8", "id-9"])
        #expect(ApplePlaybackStore.boundedWatchedHistory(entries, limit: 20) == entries)
    }

    @MainActor @Test func storeNeverHoldsMoreThanTheLimit() throws {
        let (store, defaults) = try makeStore()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let limit = ApplePlaybackStore.watchedHistoryLimit
        let entries = Dictionary(uniqueKeysWithValues: (0...limit).map {
            (ApplePlaybackIdentity.storageKey(for: "id-\($0)")!, Date(timeIntervalSince1970: Double($0)))
        })
        store.restoreConfigurationWatchedHistory(entries)
        let stored = ApplePlaybackStore(defaults: defaults).configurationWatchedHistory()
        #expect(stored.count == limit)
        #expect(stored[try key("id-0")] == nil)
        #expect(stored[try key("id-\(limit)")] != nil)
    }

    @MainActor @Test func restoreIsAUnionWhereTheLaterFinishWins() throws {
        let (store, defaults) = try makeStore()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let early = Date(timeIntervalSince1970: 100), late = Date(timeIntervalSince1970: 200)
        store.markWatched(mediaID: "local-only", at: early)
        store.markWatched(mediaID: "both", at: late)
        store.restoreConfigurationWatchedHistory([
            try key("incoming-only"): early,
            try key("both"): early,
        ])
        let history = store.configurationWatchedHistory()
        #expect(history[try key("local-only")] == early)
        #expect(history[try key("incoming-only")] == early)
        #expect(history[try key("both")] == late)
        store.restoreConfigurationWatchedHistory([try key("both"): Date(timeIntervalSince1970: 300)])
        #expect(store.configurationWatchedHistory()[try key("both")] == Date(timeIntervalSince1970: 300))
    }

    // MARK: Up Next

    private var twoSeasons: [AppleStremioEpisode] {
        [episode(2, 2), episode(1, 3), episode(2, 1), episode(1, 1), episode(0, 1), episode(1, 2)]
    }

    @Test func upNextFollowsTheLastWatchedEpisode() {
        let episodes = twoSeasons
        #expect(AppleStremioEpisodePolicy.upNext(from: episodes, completedIDs: [])?.id == episode(1, 1).id)
        let first2: Set = [episode(1, 1).id, episode(1, 2).id]
        #expect(AppleStremioEpisodePolicy.upNext(from: episodes, completedIDs: first2)?.id == episode(1, 3).id)
        // A skipped episode is behind the viewer, not next.
        let gap: Set = [episode(1, 1).id, episode(1, 3).id]
        #expect(AppleStremioEpisodePolicy.upNext(from: episodes, completedIDs: gap)?.id == episode(2, 1).id)
        // Specials do not count as progress through the show.
        #expect(AppleStremioEpisodePolicy.upNext(from: episodes, completedIDs: [episode(0, 1).id])?.id == episode(1, 1).id)
    }

    @Test func upNextCrossesIntoTheNextSeason() {
        let season1: Set = [episode(1, 1).id, episode(1, 2).id, episode(1, 3).id]
        #expect(AppleStremioEpisodePolicy.upNext(from: twoSeasons, completedIDs: season1)?.id == episode(2, 1).id)
    }

    @Test func finishedShowStartsOver() {
        let all = Set(twoSeasons.map(\.id))
        let next = AppleStremioEpisodePolicy.upNext(from: twoSeasons, completedIDs: all)
        #expect(next?.id == episode(1, 1).id)
        // The last episode alone watched also wraps round.
        #expect(AppleStremioEpisodePolicy.upNext(from: twoSeasons, completedIDs: [episode(2, 2).id])?.id == episode(1, 1).id)
    }

    @Test func seasonSelectionUsesUpNextOnlyInItsSeason() {
        let watched: Set = [episode(1, 1).id, episode(1, 3).id]
        // Up Next is S2E1; season 1 still offers its first unfinished episode.
        #expect(AppleStremioEpisodePolicy.defaultEpisode(in: 1, from: twoSeasons, completedIDs: watched)?.id == episode(1, 2).id)
        #expect(AppleStremioEpisodePolicy.defaultEpisode(in: 2, from: twoSeasons, completedIDs: watched)?.id == episode(2, 1).id)
        let first: Set = [episode(1, 1).id]
        #expect(AppleStremioEpisodePolicy.defaultEpisode(in: 1, from: twoSeasons, completedIDs: first)?.id == episode(1, 2).id)
    }

    @Test func titlePageButtonNamesTheEpisode() throws {
        let watched: Set = [episode(1, 1).id, episode(1, 2).id]
        let next = try #require(AppleStremioEpisodePolicy.upNext(from: twoSeasons, completedIDs: watched))
        let action = AppleTitlePagePolicy.primaryAction(type: "series", progress: nil, selectedEpisode: next,
                                                        isPlayable: true, hasTrailer: false, namesEpisode: true)
        #expect(action.title == "Play S1, E3")
        #expect(action.displayTitle(hasCompletedDownload: true) == "Play Offline")
        let restart = try #require(AppleStremioEpisodePolicy.upNext(from: twoSeasons, completedIDs: Set(twoSeasons.map(\.id))))
        #expect(AppleTitlePagePolicy.primaryAction(type: "series", progress: nil, selectedEpisode: restart,
                                                   isPlayable: true, hasTrailer: false, namesEpisode: true).title == "Play S1, E1")
        // Heroes and films keep the bare verb.
        #expect(AppleTitlePagePolicy.primaryAction(type: "series", progress: nil, selectedEpisode: next,
                                                   isPlayable: true, hasTrailer: false) == .play)
        #expect(AppleTitlePagePolicy.primaryAction(type: "movie", progress: nil, selectedEpisode: nil,
                                                   isPlayable: true, hasTrailer: false, namesEpisode: true) == .play)
    }

    @Test func heroPicksUpNextAcrossSeasons() {
        let item = AppleCatalogItem(mediaID: "tt0903747", type: "series", name: "Fixture")
        let season1: Set = [episode(1, 1).id, episode(1, 2).id, episode(1, 3).id]
        #expect(AppleTitlePagePolicy.heroEpisode(item: item, progress: nil, episodes: twoSeasons,
                                                 completedIDs: season1)?.id == episode(2, 1).id)
    }

    // MARK: Backup and iCloud

    @Test func backupRoundTripsWatchedHistoryPlainAndEncrypted() throws {
        let history = ["sha256:fixture-a": Date(timeIntervalSince1970: 1_000), "sha256:fixture-b": Date(timeIntervalSince1970: 2_000)]
        let snapshot = AppleConfigurationSnapshot(watchedHistory: history)
        let plain = try AppleConfigurationFile.decode(AppleConfigurationFile.encode(snapshot: snapshot)).snapshot
        #expect(plain.watchedHistory == history)
        let sealed = try AppleConfigurationFile.encode(snapshot: snapshot, passphrase: "fixture passphrase")
        #expect(try AppleConfigurationFile.decode(sealed, passphrase: "fixture passphrase").snapshot.watchedHistory == history)
    }

    @Test func snapshotWithoutWatchedHistoryImports() throws {
        let data = try AppleConfigurationFile.encode(snapshot: AppleConfigurationSnapshot(watchedHistory: ["sha256:x": .now]))
        var json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var body = try #require(json["snapshot"] as? [String: Any])
        body.removeValue(forKey: "watchedHistory")
        json["snapshot"] = body
        let old = try JSONSerialization.data(withJSONObject: json)
        let restored = try AppleConfigurationFile.decode(old).snapshot
        #expect(restored.watchedHistory.isEmpty)
    }

    @Test func cloudKeepsNewest500WatchedAndFitsBudget() throws {
        let history = Dictionary(uniqueKeysWithValues: (0..<700).map {
            ("id-\($0)", Date(timeIntervalSince1970: Double($0)))
        })
        let data = try AppleConfigurationSnapshot(watchedHistory: history).cloudData()
        #expect(data.count <= AppleConfigurationSnapshot.maximumCloudBytes)
        let restored = try JSONDecoder().decode(AppleConfigurationSnapshot.self, from: data)
        #expect(restored.watchedHistory.count == 500)
        #expect(restored.watchedHistory["id-699"] != nil)
        #expect(restored.watchedHistory["id-0"] == nil)
    }

    @Test func cloudByteTrimDropsTheOldestOfEitherList() throws {
        let longPart = String(repeating: "a", count: 4_000)
        let progress = Dictionary(uniqueKeysWithValues: (0..<150).map {
            ("progress-\($0)", ApplePlaybackProgress(position: 10, duration: 100,
                updatedAt: Date(timeIntervalSince1970: Double(1_000 + $0)), partID: longPart))
        })
        // About 5% over the budget, so only a few dozen re-encodes.
        let history = Dictionary(uniqueKeysWithValues: (0..<350).map {
            ("watched-\($0)-" + String(repeating: "b", count: 1_000), Date(timeIntervalSince1970: Double($0)))
        })
        let data = try AppleConfigurationSnapshot(playbackProgress: progress, watchedHistory: history).cloudData()
        #expect(data.count <= AppleConfigurationSnapshot.maximumCloudBytes)
        let restored = try JSONDecoder().decode(AppleConfigurationSnapshot.self, from: data)
        // Every watched entry is older than every progress entry, so they go first.
        #expect(restored.watchedHistory.count < 350)
        #expect(restored.watchedHistory["watched-349-" + String(repeating: "b", count: 1_000)] != nil)
        #expect(restored.playbackProgress.count == 150)
    }

    @Test func snapshotMergeIsAUnionWhereTheLaterFinishWins() {
        let local = AppleConfigurationSnapshot(watchedHistory: ["a": Date(timeIntervalSince1970: 5), "b": Date(timeIntervalSince1970: 1)])
        let incoming = AppleConfigurationSnapshot(watchedHistory: ["b": Date(timeIntervalSince1970: 9), "c": Date(timeIntervalSince1970: 2)])
        let merged = local.merging(incoming)
        #expect(merged.watchedHistory == ["a": Date(timeIntervalSince1970: 5), "b": Date(timeIntervalSince1970: 9),
                                          "c": Date(timeIntervalSince1970: 2)])
    }
}
