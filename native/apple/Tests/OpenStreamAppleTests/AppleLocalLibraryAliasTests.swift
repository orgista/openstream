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

    static func run(lookup: @escaping AppleLibraryMetadataResolver.Lookup = { _, _, _, _ in nil },
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
            groups: AppleLibrarySeries.groups(files), sources: [source], offlineIDs: offlineIDs)
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
    @Test func strongMatchRecordsOneClassPerFile() async throws {
        try await LocalAliasFixture.run { f in
            let file = f.file("Shows/Show/Season 1/Show.S01E01.mkv")
            try await f.manual(file)
            let store = f.store([file])
            await f.resolveAll(store)
            let key = try #require(ApplePlaybackIdentity.storageKey(for: store.playbackID(file)))
            #expect(try f.table().classes == ["li:series:tt0903747:1:1:734003200": [key]])
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
        try await LocalAliasFixture.run(lookup: { _, _, _, _ in
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
            #expect(try f.table().classes.count == 1)
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
            #expect(try f.table().classes.count == 1)
        }
    }
    @Test func twoCopiesStaySeparate() async throws {
        try await LocalAliasFixture.run { f in
            let first = f.file("Film.2020.1080p.mkv", size: 1000)
            let second = f.file("Film.2020.2160p.mkv", size: 2000)
            try await f.manual(first, kind: "movie")
            let store = f.store([first, second])
            await f.resolveAll(store)
            let table = try f.table()
            #expect(Set(table.classes.keys) == ["li:movie:tt0903747:1000", "li:movie:tt0903747:2000"])
            #expect(table.classes.values.allSatisfy { $0.count == 1 })
            f.playback.save(mediaID: store.playbackID(first), position: 600, duration: 3600)
            #expect(f.playback.progress(for: store.playbackID(second)) == nil)
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
