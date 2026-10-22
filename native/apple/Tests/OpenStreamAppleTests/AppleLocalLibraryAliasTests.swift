import Foundation
import Testing
@testable import OpenStreamApple

private struct AliasCredentialStub: AppleCredentialStoring {
    func string(for account: String) throws -> String? { nil }
    func set(_ value: String, for account: String) throws {}
    func remove(_ account: String) throws {}
}

@MainActor private struct LocalAliasFixture {
    let defaults: UserDefaults
    let root: URL
    let resolver: AppleLibraryMetadataResolver
    let playback: ApplePlaybackStore
    let source: AppleSource
    let sources: AppleSourceStore
    let settings: AppleSettingsStore
    var blobDirectory: URL { root.appendingPathComponent("Playback") }

    static func run(lookup: @escaping AppleLibraryMetadataResolver.Lookup = { _, _, _ in nil },
                    _ body: (Self) async throws -> Void) async throws {
        let suite = "local-alias-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
        let resolver = AppleLibraryMetadataResolver(directory: root.appendingPathComponent("Titles"),
            matchDirectory: root.appendingPathComponent("Matches"), lookup: lookup)
        let playback = ApplePlaybackStore(defaults: defaults, blobDirectory: root.appendingPathComponent("Playback"))
        let source = AppleSource(kind: .library, name: "Fixture", url: root.appendingPathComponent("Media"))
        let sources = AppleSourceStore(defaults: defaults, keychain: AliasCredentialStub(), documentsDirectory: root)
        let settings = AppleSettingsStore(defaults: defaults, keychain: AliasCredentialStub())
        try await body(Self(defaults: defaults, root: root, resolver: resolver, playback: playback,
            source: source, sources: sources, settings: settings))
    }

    func file(_ path: String, size: Int64 = 734003200) -> AppleLibraryItem {
        AppleLibraryItem(sourceID: source.id, name: URL(fileURLWithPath: path).lastPathComponent,
            url: root.appendingPathComponent("Media").appendingPathComponent(path), relativePath: path, sizeBytes: size)
    }
    func store(_ files: [AppleLibraryItem], offlineIDs: [String: String] = [:]) -> AppleLocalLibraryStore {
        AppleLocalLibraryStore(resolver: resolver, playbackStore: playback,
            groups: AppleLibrarySeries.groups(files), sources: [source], offlineIDs: offlineIDs,
            versionCacheURL: root.appendingPathComponent("MediaVersions-v1.json"))
    }
    func table() throws -> AppleIdentityAliasTable {
        let data = AppleIdentityAliasStore(defaults: defaults, blobDirectory: blobDirectory).blobData
        return try data.map { try JSONDecoder().decode(AppleIdentityAliasTable.self, from: $0) } ?? .init()
    }
    func manual(_ file: AppleLibraryItem, kind: String = "series") async throws {
        try await resolver.correctMatch(for: file,
            candidate: AppleCatalogItem(mediaID: "tt0903747", type: kind, name: kind == "series" ? "Show" : "Film", releaseInfo: "2020"), provider: "fixture")
    }
    func resolveAll(_ store: AppleLocalLibraryStore) async {
        for group in store.groups { await store.resolve(group, sourceStore: sources, settings: settings) }
    }
}

@MainActor @Suite struct AppleLocalLibraryAliasTests {
    @Test func defaultDVDPlayOpensTheDiscMenu() async throws {
        try await LocalAliasFixture.run { f in
            let file = f.file("Film.2020.iso")
            let store = f.store([file])
            let presentation = try await store.presentation(for: file, sourceStore: f.sources,
                settings: f.settings, engineOverride: .openStream)
            #expect(presentation.request.hints.disc?.start == .menu)
            #expect(presentation.request.hints.disc?.engineTitleID == nil)
        }
    }

    @Test func strongMatchRecordsOneClassPerFile() async throws {
        try await LocalAliasFixture.run { f in
            let file = f.file("Shows/Show/Season 1/Show.S01E01.mkv")
            try await f.manual(file)
            let store = f.store([file])
            await f.resolveAll(store)
            let key = try #require(ApplePlaybackIdentity.storageKey(for: store.playbackID(file)))
            #expect(try f.table().classes["li:series:tt0903747:1:1:734003200"] == [key])
            #expect(try f.table().classes["li:series:tt0903747:1:1"]?.contains(key) == true)
            let storage = ApplePlaybackBlobStorage.storage(defaults: f.defaults, directory: f.blobDirectory)
            let url = storage.fileURL(forKey: "openstream.identity.aliases.v1")
            let sentinel = Date(timeIntervalSince1970: 1234)
            try FileManager.default.setAttributes([.modificationDate: sentinel], ofItemAtPath: url.path)
            await f.resolveAll(store)
            #expect(try FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date == sentinel)
        }
    }
    @Test func renamedFileJoinsTheSameClass() async throws {
        try await LocalAliasFixture.run { f in
            let old = f.file("Shows/Show/Season 1/Show.S01E01.mkv")
            let new = f.file("Moved/Shows/Show/Season 1/Show.S01E01.renamed.mkv")
            try await f.manual(old)
            let oldStore = f.store([old])
            await f.resolveAll(oldStore)
            f.playback.save(mediaID: oldStore.playbackID(old), position: 600, duration: 3600)
            let newStore = f.store([new])
            await f.resolveAll(newStore)
            let members = try #require(f.table().classes["li:series:tt0903747:1:1:734003200"])
            #expect(members.count == 2)
            #expect(Set(members) == Set([oldStore.playbackID(old), newStore.playbackID(new)].compactMap { ApplePlaybackIdentity.storageKey(for: $0) }))
            #expect(newStore.continueWatching.map(\.id) == newStore.groups.map(\.id))
            #expect(f.playback.progress(for: newStore.playbackID(new))?.position == 600)
        }
    }
    @Test func weakMatchRecordsNothing() async throws {
        try await LocalAliasFixture.run(lookup: { _, _, _ in
            AppleCatalogItem(mediaID: "tt0903747", type: "movie", name: "Film", releaseInfo: "2019")
        }) { f in
            let file = f.file("Film.2020.mkv")
            let store = f.store([file])
            await f.resolveAll(store)
            #expect(await f.resolver.matchRecord(for: file)?.confidence == 0.6)
            #expect(try f.table().classes.isEmpty)
            // Weak evidence is deduped until an explicit metadata refresh.
            try await f.manual(file, kind: "movie")
            await f.resolveAll(store)
            #expect(try f.table().classes.isEmpty)
            for group in store.groups {
                await store.resolve(group, sourceStore: f.sources, settings: f.settings, refresh: true)
            }
            #expect(try f.table().classes["li:movie:tt0903747"] != nil)
        }
    }
    @Test func noMatchRecordsNothing() async throws {
        try await LocalAliasFixture.run { f in
            let store = f.store([f.file("Film.2020.mkv")])
            await f.resolveAll(store)
            let table = try f.table()
            #expect(table.classes.isEmpty)
            // A newly resolved match must still record after an earlier miss.
            try await f.manual(store.groups[0].items[0], kind: "movie")
            await f.resolveAll(store)
            #expect(try f.table().classes["li:movie:tt0903747"] != nil)
        }
    }
    @Test func twoCopiesShareTitleAndKeepVersionScopes() async throws {
        try await LocalAliasFixture.run { f in
            let first = f.file("Film.2020.1080p.mkv", size: 1000)
            let second = f.file("Film.2020.2160p.mkv", size: 2000)
            try await f.manual(first, kind: "movie")
            let store = f.store([first, second])
            await f.resolveAll(store)
            let table = try f.table()
            #expect(table.classes["li:movie:tt0903747:1000"]?.count == 1)
            #expect(table.classes["li:movie:tt0903747:2000"]?.count == 1)
            #expect(table.classes["li:movie:tt0903747"] != nil)
            f.playback.save(mediaID: store.playbackID(first), position: 600, duration: 3600)
            #expect(f.playback.progress(for: store.playbackID(second))?.position == 600)
            _ = store.mediaVersions(for: first)
            #expect(f.playback.versionProgress(itemID: "li:movie:tt0903747", versionID: store.playbackID(first))?.position == 600)
            #expect(f.playback.versionProgress(itemID: "li:movie:tt0903747", versionID: store.playbackID(second)) == nil)
        }
    }
    @Test func unmatchedSameTitleCopiesAreNeitherMergedNorAliased() async throws {
        try await LocalAliasFixture.run { f in
            let first = f.file("Film.2020.1080p.mkv", size: 1000)
            let second = f.file("Film.2020.2160p.mkv", size: 2000)
            let store = f.store([first, second])
            await f.resolveAll(store)
            let one = store.mediaVersions(for: first)
            let two = store.mediaVersions(for: second)
            #expect(one.count == 1 && two.count == 1)
            #expect(one.first?.itemID == store.playbackID(first))
            #expect(two.first?.itemID == store.playbackID(second))
            let table = try f.table()
            #expect(table.classes.isEmpty)
            f.playback.save(mediaID: store.playbackID(first), position: 600, duration: 3600)
            #expect(f.playback.progress(for: store.playbackID(second)) == nil)
        }
    }

    @Test func anUnmatchedStackSharesOneTimeline() async throws {
        try await LocalAliasFixture.run { f in
            let parts = [f.file("Film.2020.cd1.mkv", size: 1000), f.file("Film.2020.cd2.mkv", size: 1000)]
            let store = f.store(parts)
            await f.resolveAll(store)
            let one = try #require(store.mediaVersions(for: parts[0]).first)
            let two = try #require(store.mediaVersions(for: parts[1]).first)
            #expect(one.parts.map(\.reference) == parts.map(\.id))
            #expect(one.itemID == two.itemID && one.id == two.id)
            #expect(one.itemID != store.playbackID(parts[0]))
        }
    }

    /// A stack whose probe fails plays part by part on each file's own
    /// position, learns each part's length from playback, and then resumes
    /// through the whole cumulative timeline.
    @Test func aStackWithAFailingProbePlaysPartByPartAndLearnsItsTimeline() async throws {
        try await LocalAliasFixture.run { f in
            let folder = f.root.appendingPathComponent("Downloads")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let downloads = AppleSource(id: AppleLocalLibraryStore.downloadsID, kind: .library, name: "Downloads", url: folder)
            let parts = ["Film.2020.cd1.mkv", "Film.2020.cd2.mkv"].map { name in
                AppleLibraryItem(sourceID: downloads.id, name: name, url: folder.appendingPathComponent(name),
                    relativePath: name, sizeBytes: 16)
            }
            // Not media: the probe fails and reports no duration.
            for part in parts { try Data(repeating: 7, count: 16).write(to: part.url) }
            let store = AppleLocalLibraryStore(resolver: f.resolver, playbackStore: f.playback,
                groups: AppleLibrarySeries.groups(parts), sources: [downloads],
                versionCacheURL: f.root.appendingPathComponent("MediaVersions-v1.json"))
            await f.resolveAll(store)

            let first = try await store.presentation(for: parts[0], sourceStore: f.sources, settings: f.settings, engineOverride: .openStream)
            #expect(first.request.url == parts[0].url)
            #expect(first.request.hints.versionID == nil)
            #expect(first.request.mediaID == store.playbackID(parts[0]))
            first.coordinator.progressWriter?(900, 1800)
            #expect(f.playback.fileProgress(for: store.playbackID(parts[0]))?.position == 900)

            let second = try await store.presentation(for: parts[1], sourceStore: f.sources, settings: f.settings,
                continuingPart: true, engineOverride: .openStream)
            #expect(second.request.url == parts[1].url)
            #expect(second.request.hints.versionID == nil)
            second.coordinator.progressWriter?(300, 2400)

            let resumed = try await store.presentation(for: parts[0], sourceStore: f.sources, settings: f.settings, engineOverride: .openStream)
            #expect(resumed.request.hints.versionDuration == 4200)
            #expect(resumed.request.url == parts[1].url)
            #expect(resumed.request.resumePosition == 300)
            #expect(resumed.request.hints.versionOffset == 1800)
        }
    }

    @Test func playAndItsPromptUseTheLastPlayedCopy() async throws {
        try await LocalAliasFixture.run { f in
            let low = f.file("Film.2020.1080p.mkv", size: 1000)
            let high = f.file("Film.2020.2160p.mkv", size: 2000)
            try await f.manual(low, kind: "movie")
            let cacheURL = f.root.appendingPathComponent("MediaVersions-v1.json")
            let probe = f.store([low, high])
            await f.resolveAll(probe)
            var versions = probe.mediaVersions(for: low)
            try #require(versions.count == 2)
            for index in versions.indices {
                versions[index].parts[0].duration = versions[index].parts[0].reference == high.id ? 7200 : 6000
            }
            AppleMediaVersionCache(url: cacheURL).record(versions)
            let store = f.store([low, high])
            await f.resolveAll(store)
            let itemID = versions[0].itemID
            let highID = try #require(versions.first { $0.parts[0].reference == high.id }?.id)
            let lowID = try #require(versions.first { $0.parts[0].reference == low.id }?.id)
            f.playback.saveVersion(itemID: itemID, versionID: highID, position: 600, duration: 7200)
            f.playback.preferVersion(lowID, itemID: itemID)
            // Play on the 4K file still resumes the 1080p copy played last, and
            // the runtime differs, so it asks about exactly that copy.
            await #expect(throws: AppleVersionResumeConfirmation(position: 600, versionID: lowID)) {
                _ = try await store.presentation(for: high, sourceStore: f.sources, settings: f.settings, engineOverride: .openStream)
            }
            #expect(f.playback.preferredVersion(itemID: itemID) == lowID)
        }
    }

    @Test func playNamesTheCopyItActuallyTried() async throws {
        try await LocalAliasFixture.run { f in
            let low = f.file("Film.2020.1080p.mkv", size: 1000)
            let high = f.file("Film.2020.2160p.mkv", size: 2000)
            try await f.manual(low, kind: "movie")
            let store = f.store([low, high])
            await f.resolveAll(store)
            let versions = store.mediaVersions(for: low)
            try #require(versions.count == 2)
            let lowID = try #require(versions.first { $0.parts[0].reference == low.id }?.id)
            f.playback.preferVersion(lowID, itemID: versions[0].itemID)
            // Play on the 4K file selects the 1080p copy played last; a failure
            // blacklists the file `attempting` ends on.
            var attempted = high
            let presentation = try await store.presentation(attempting: &attempted, sourceStore: f.sources,
                settings: f.settings, engineOverride: .openStream)
            #expect(attempted.id == low.id)
            #expect(presentation.request.hints.libraryFileURL == low.url)
        }
    }
    @Test func oneLibraryPublishWritesTheVersionCacheOnce() async throws {
        try await LocalAliasFixture.run { f in
            let files = [f.file("Alpha.2020.mkv"), f.file("Beta.2021.mkv"), f.file("Gamma.2022.mkv")]
            for (index, file) in files.enumerated() {
                try await f.resolver.correctMatch(for: file, candidate: AppleCatalogItem(mediaID: "tt000000\(index + 1)",
                    type: "movie", name: file.name, releaseInfo: "2020"), provider: "fixture")
            }
            let store = f.store(files)
            #expect(store.groups.count == 3)
            await store.recordAllIdentityAliases()
            #expect(store.mediaVersionCache.versions.count == 3)
            #expect(store.mediaVersionCache.diskWrites == 1)
            // The next launch rebuilds the same versions with a newer timestamp: no write.
            let relaunched = f.store(files)
            await relaunched.recordAllIdentityAliases()
            #expect(relaunched.mediaVersionCache.versions.count == 3)
            #expect(relaunched.mediaVersionCache.diskWrites == 0)
        }
    }

    @Test(arguments: [
        ["Shows/Show/Show.2020-01-01.mkv", "Shows/Show/Show.2020-01-02.mkv"],
        ["Shows/Show/Pilot.mkv", "Shows/Show/Arrival.mkv"]
    ]) func dailyAndUnnumberedEpisodesKeepSeparateTimelines(paths: [String]) async throws {
        try await LocalAliasFixture.run { f in
            let files = paths.map { f.file($0, size: 1000) }
            try await f.manual(files[0])
            let library = f.store(files)
            await f.resolveAll(library)
            let first = try #require(library.mediaVersions(for: files[0]).first)
            let second = try #require(library.mediaVersions(for: files[1]).first)
            #expect(first.itemID != second.itemID)
            f.playback.saveVersion(itemID: first.itemID, versionID: first.id, position: 600, duration: 3600)
            #expect(f.playback.progress(for: second.itemID) == nil)
        }
    }

    @Test func aCancelledVersionPressDoesNotPrepareOrMigratePlayback() async throws {
        try await LocalAliasFixture.run { f in
            let file = f.file("Film.2020.2160p.mkv")
            let library = f.store([file])
            let task = Task { @MainActor in
                _ = try await library.presentation(for: file, sourceStore: f.sources, settings: f.settings, explicitVersion: true)
            }
            task.cancel()
            await #expect(throws: CancellationError.self) { try await task.value }
            #expect(f.playback.configurationProgress().isEmpty)
            #expect(FileManager.default.fileExists(atPath: f.root.appendingPathComponent("MediaVersions-v1.json").path) == false)
        }
    }

    @Test func copiesAcrossLocalSourcesProduceOneContinueWatchingCard() async throws {
        try await LocalAliasFixture.run { f in
            let first = f.file("Film.2020.1080p.mkv", size: 1000)
            let other = AppleSource(kind: .library, name: "Other", url: f.root.appendingPathComponent("Other"))
            let second = AppleLibraryItem(sourceID: other.id, name: "Film.2020.2160p.mkv",
                url: other.url.appendingPathComponent("Film.2020.2160p.mkv"), relativePath: "Film.2020.2160p.mkv", sizeBytes: 2000)
            try await f.manual(first, kind: "movie")
            try await f.manual(second, kind: "movie")
            let library = AppleLocalLibraryStore(resolver: f.resolver, playbackStore: f.playback,
                groups: AppleLibrarySeries.groups([first, second]), sources: [f.source, other],
                versionCacheURL: f.root.appendingPathComponent("MediaVersions-v1.json"))
            await f.resolveAll(library)
            let versions = library.mediaVersions(for: first)
            #expect(versions.count == 2)
            let version = try #require(versions.first)
            f.playback.saveVersion(itemID: version.itemID, versionID: version.id, position: 600, duration: 3600)
            #expect(library.continueWatching.count == 1)
        }
    }

    @Test func saveCompletionIndexSyncAndRowResolutionWithTwoVersions() async throws {
        try await LocalAliasFixture.run { f in
            let first = f.file("Film.2020.1080p.mkv", size: 1000)
            let second = f.file("Film.2020.2160p.mkv", size: 2000)
            try await f.manual(first, kind: "movie")
            let library = f.store([first, second])
            await f.resolveAll(library)
            let versions = library.mediaVersions(for: first)
            #expect(versions.count == 2)
            let itemID = try #require(versions.first?.itemID)
            f.playback.saveVersion(itemID: itemID, versionID: library.playbackID(first), position: 600, duration: 3600)
            library.refreshProgress()
            #expect(library.continueWatching.count == 1)
            f.playback.saveVersion(itemID: itemID, versionID: library.playbackID(first), position: 3600, duration: 3600)
            let repository = AppleMediaIndexRepository(fileURL: f.root.appendingPathComponent("index.json"))
            try await repository.replace(instanceID: f.source.id, with: [first, second].map { AppleMediaIngestion.libraryRecord(source: f.source, item: $0) })
            library.refreshProgress()
            #expect(library.continueWatching.isEmpty)
            #expect(f.playback.completedMediaIDs(among: [library.playbackID(first), library.playbackID(second)]).count == 2)
            #expect(library.sorted(.added).count == 1)
        }
    }

    @Test func extrasDownloadsAndZeroSizeRecordNothing() async throws {
        try await LocalAliasFixture.run { f in
            let extra = f.file("Film.2020-trailer.mkv")
            let zero = f.file("Empty.2020.mkv", size: 0)
            let download = f.file("Downloaded.2020.mkv")
            for file in [extra, zero, download] { try await f.manual(file, kind: "movie") }
            let store = f.store([extra, zero, download], offlineIDs: [download.id: "fixture-download"])
            await f.resolveAll(store)
            #expect(AppleLibraryTitleParser.parse(extra).role == .trailer)
            #expect(try f.table().classes.isEmpty)
        }
    }
    @Test func strongMatchIDsReadsOnly() async throws {
        try await LocalAliasFixture.run { f in
            let file = f.file("Shows/Show/Season 1/Show.S01E01.mkv")
            let missing = await f.resolver.strongMatchIDs(for: file)
            #expect(missing.map { _ in true } == nil)
            let folder = f.root.appendingPathComponent("Matches")
            #expect(FileManager.default.fileExists(atPath: folder.path) == false)
            try await f.manual(file)
            let url = try #require(FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil).first)
            let before = try Data(contentsOf: url)
            let sentinel = Date(timeIntervalSince1970: 1234)
            try FileManager.default.setAttributes([.modificationDate: sentinel], ofItemAtPath: url.path)
            for _ in 0..<10 {
                let ids = await f.resolver.strongMatchIDs(for: file)
                #expect(ids?.kind == .series)
                #expect(ids?.imdb == "tt0903747")
                #expect(ids?.tmdb == nil)
            }
            #expect(try Data(contentsOf: url) == before)
            #expect(try FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date == sentinel)
        }
    }
    @Test func legacyEpisodeLookupIsPureAndExplicitPairKeepsParity() throws {
        try ApplePlaybackAliasFixture.run { f in
            let file = AppleLibraryItem(sourceID: UUID(), name: "Pilot.mkv", url: URL(fileURLWithPath: "/Pilot.mkv"),
                relativePath: "Shows/Show/Season 1/Pilot.mkv", sizeBytes: 1)
            let group = AppleLibrarySeries.groups([file])[0]
            let rows = AppleLocalLibraryStore.episodes(group: group, mediaID: "tt1", enriched: [])
            let current = AppleLocalLibraryStore.fileEpisodeID(file)
            f.store.markWatched(mediaID: "tt1:1:1")
            let before = f.defaults.dictionaryRepresentation().compactMapValues { $0 as? Data }
            let completed = AppleLocalLibraryStore.completedEpisodeIDs(rows, group: group, mediaID: "tt1", store: f.store)
            #expect(f.defaults.dictionaryRepresentation().compactMapValues { $0 as? Data } == before)
            f.store.recordIdentityAlias(classID: AppleLogicalItemKey.legacyEpisodeClass(fileEpisodeID: current),
                mediaIDs: [current, "tt1:1:1"])
            #expect(f.store.completedMediaIDs(among: rows.map(\.id)) == completed)
            let data = try #require(f.defaults.data(forKey: "openstream.identity.aliases.v1"))
            let table = try JSONDecoder().decode(AppleIdentityAliasTable.self, from: data)
            #expect(table.classes[AppleLogicalItemKey.legacyEpisodeClass(fileEpisodeID: current)] == [current, "tt1:1:1"].compactMap { ApplePlaybackIdentity.storageKey(for: $0) }.sorted())
        }
    }
    @Test func resolveRecordsFilenamePairUsingResolvedShowID() async throws {
        try await LocalAliasFixture.run { f in
            let file = f.file("Shows/Show/Season 1/Pilot.mkv")
            try await f.manual(file)
            let store = f.store([file])
            await f.resolveAll(store)
            let current = AppleLocalLibraryStore.fileEpisodeID(file)
            #expect(try f.table().classes["le:" + current] == [current, "tt0903747:1:1"]
                .compactMap { ApplePlaybackIdentity.storageKey(for: $0) }.sorted())
        }
    }

    @Test func filenameLookupDoesNotBorrowAnotherCopiesPositionalHistory() throws {
        try ApplePlaybackAliasFixture.run { f in
            let source = UUID()
            func file(_ name: String, size: Int64) -> AppleLibraryItem {
                AppleLibraryItem(sourceID: source, name: name, url: URL(fileURLWithPath: "/" + name),
                    relativePath: "Shows/Show/Season 1/" + name, sizeBytes: size)
            }
            let old = file("Pilot.mkv", size: 1000)
            let renamed = file("Renamed Pilot.mkv", size: 1000)
            let copy = file("Other Pilot.mkv", size: 2000)
            let oldID = AppleLocalLibraryStore.fileEpisodeID(old)
            let newID = AppleLocalLibraryStore.fileEpisodeID(renamed)
            let copyID = AppleLocalLibraryStore.fileEpisodeID(copy)
            f.store.recordIdentityAlias(classID: "le:" + oldID, mediaIDs: [oldID, "tt1:1:1"])
            f.store.recordIdentityAliases([
                (classID: "li:series:tt1:1000", mediaIDs: [oldID, newID]),
                (classID: "le:" + copyID, mediaIDs: [copyID, "tt1:1:1"])])
            f.store.markWatched(mediaID: "tt1:1:1")
            var group = try #require(AppleLibrarySeries.groups([old]).first)
            group.items = [copy, renamed]
            let rows = AppleLocalLibraryStore.episodes(group: group, mediaID: "tt1", enriched: [])
            #expect(AppleLocalLibraryStore.completedEpisodeIDs(rows, group: group, mediaID: "tt1", store: f.store) == [newID])
        }
    }

}
