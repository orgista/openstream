import Foundation
import Synchronization
import Testing
@testable import OpenStreamApple

private struct TopShelfTestCredentials: AppleCredentialStoring {
    func string(for account: String) throws -> String? { nil }
    func set(_ value: String, for account: String) throws {}
    func remove(_ account: String) throws {}
}

/// Review of 2b1f930: the Top Shelf bar follows the playback store, so a
/// new saved position republishes even when the media records are unchanged.
@Suite(.serialized)
@MainActor
struct AppleTopShelfPublisherProgressTests {
    @Test func unresolvedHomeKeepsTheIndexRowUntilHomePublishes() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let suite = UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let source = AppleSource(kind: .mediaServer, name: "Fixture Server",
            url: URL(string: "https://fixture.example/server")!)
        var record = AppleMediaIngestion.catalogRecord(instanceID: source.id, item: AppleCatalogItem(
            mediaID: AppleMediaServerItemReference(sourceID: source.id, itemID: "film").mediaID,
            type: "movie", name: "Fixture Film"))
        record.progress = 0.3
        let feed = AppleTopShelfHeroFeed()
        let publisher = AppleTopShelfPublisher(writer: .init(containerProvider: { root }))
        let reader = AppleTopShelfSnapshotReader(containerProvider: { root })
        let playback = ApplePlaybackStore(defaults: defaults)
        feed.updateContinueWatching([], isLoaded: false)
        #expect(feed.continueWatching == nil)
        await publisher.publish(records: [record], sources: [source], continueWatching: feed.continueWatching,
            enabled: true, playbackStore: playback)
        #expect(try #require(reader.read()).continueWatching.map(\.id) == [record.id])
        record.progress = 0.4
        feed.updateContinueWatching([record], isLoaded: true)
        feed.updateContinueWatching([], isLoaded: false)
        await publisher.publish(records: [record], sources: [source], continueWatching: feed.continueWatching,
            enabled: true, playbackStore: playback)
        #expect(try #require(reader.read()).continueWatching.first?.progress == 0.4)
        feed.updateContinueWatching([], isLoaded: true)
        await publisher.publish(records: [record], sources: [source], continueWatching: feed.continueWatching,
            enabled: true, playbackStore: playback)
        #expect(try #require(reader.read()).continueWatching.isEmpty)
    }

    @Test func routeCacheContainsOnlyContinuedTitlesAndSkipsUnchangedWrites() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appending(path: "routes.json")
        let source = AppleSource(kind: .mediaServer, name: "Fixture Server",
            url: URL(string: "https://fixture.example/server")!)
        let records = (0..<40).map { index in
            AppleMediaIngestion.catalogRecord(instanceID: source.id, item: AppleCatalogItem(
                mediaID: AppleMediaServerItemReference(sourceID: source.id, itemID: "film-\(index)").mediaID,
                type: "movie", name: "Fixture Film \(index)"))
        }
        let routes = AppleTopShelfRouteStore(fileURL: url)
        let publisher = AppleTopShelfPublisher(writer: .init(containerProvider: { root }), routes: routes)
        await publisher.publish(records: records, sources: [source], continueWatching: [records[0]], enabled: true)
        #expect(try JSONDecoder().decode([AppleMediaRecord].self, from: Data(contentsOf: url)).map(\.id) == [records[0].id])
        let stamp = Date(timeIntervalSince1970: 123)
        try FileManager.default.setAttributes([.modificationDate: stamp], ofItemAtPath: url.path)
        var same = records[0]
        same.progress = 0.5
        same.lastVerified = same.lastVerified.addingTimeInterval(60)
        await publisher.publish(records: records, sources: [source], continueWatching: [same], enabled: true)
        #expect(try url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate == stamp)
        try await routes.save(records: records, sources: [source], enabled: true)
        #expect(try JSONDecoder().decode([AppleMediaRecord].self, from: Data(contentsOf: url)).count
            == AppleContinueWatchingResolver.maximumCount)
    }

    @Test(arguments: [AppleStorageLocation.Platform.appleTV, .other])
    func productionResetDirectoriesRemoveTheRouteFile(platform: AppleStorageLocation.Platform) async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let support = root.appending(path: platform == .appleTV
            ? "Library/Caches/Application Support" : "Library/Application Support")
        let url = support.appending(path: "OpenStream").appending(path: AppleTopShelfRouteStore.filename)
        let routes = AppleTopShelfRouteStore(fileURL: url)
        try await routes.save(records: [], sources: [], enabled: true)
        let report = AppleDeviceReset.wipe(directories: AppleDeviceReset.libraryTree(root: root))
        #expect(report.failedItems == 0)
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test(arguments: [false, true])
    func sourceRemovalAndSignOutDeleteTheRouteFile(signOut: Bool) async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appending(path: "routes.json")
        let suite = UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let source = AppleSource(kind: .mediaServer, name: "Fixture Server",
            url: URL(string: "https://fixture.example/server")!)
        defaults.set(try JSONEncoder().encode([source]), forKey: "openstream.sources.v1")
        let store = AppleSourceStore(defaults: defaults, keychain: TopShelfTestCredentials(), topShelfRoutesURL: url)
        try await AppleTopShelfRouteStore(fileURL: url).save(records: [], sources: [], enabled: true)
        if signOut {
            _ = try store.restoreConfigurationSources([source], secrets: nil, merge: false)
            #expect(store.sources.first?.needsSignIn == true)
        } else {
            #expect(store.remove(id: source.id))
        }
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test func serverRoutesUseTheIngestedTypeAndLegacyRoutesUseLoadedItems() throws {
        let source = AppleSource(kind: .mediaServer, name: "Fixture Server",
            url: URL(string: "https://fixture.example/server")!)
        let item = AppleCatalogItem(mediaID: AppleMediaServerItemReference(sourceID: source.id, itemID: "film").mediaID,
            type: "video", name: "Fixture Film")
        var record = AppleMediaIngestion.catalogRecord(instanceID: source.id, item: item)
        #expect(record.kind.rawValue != item.type)
        #expect(AppleCatalogSearchMatch.mediaServer(record, sources: [source])?.item.type == item.type)
        record.availability = [.init(instanceID: source.id, capability: .resolvable,
            itemReference: "\(item.type)|\(item.mediaID)")]
        #expect(AppleContinueWatchingResolver.isOpenable(record, sources: [source]))
        let legacy = try #require(AppleCatalogSearchMatch.mediaServer(record, sources: [source], items: [item]))
        #expect(legacy.item.mediaID == item.mediaID)
        #expect(AppleCatalogSearchMatch.mediaServer(record, sources: [], items: [item]) == nil)
    }

    @Test func missingRoutesConvergeWithoutChangingIndexOrPersistingEpisodeProgress() {
        let source = AppleSource(kind: .mediaServer, name: "Fixture Server",
            url: URL(string: "https://fixture.example/server")!)
        let item = AppleCatalogItem(mediaID: AppleMediaServerItemReference(sourceID: source.id, itemID: "show").mediaID,
            type: "series", name: "Fixture Series")
        var continued = AppleMediaIngestion.catalogRecord(instanceID: source.id, item: item)
        continued.progress = 0.6
        let index: [AppleMediaRecord] = []
        let missing = AppleTopShelfPublisher.missingRecords(records: index, continueWatching: [continued], sources: [source])
        #expect(missing.map(\.id) == [continued.id])
        #expect(missing.first?.progress == nil)
        #expect(AppleTopShelfPublisher.missingRecords(records: missing,
            continueWatching: [continued], sources: [source]).isEmpty)
        let reverified = AppleMediaIngestion.catalogRecord(instanceID: source.id, item: item,
            verifiedAt: continued.lastVerified.addingTimeInterval(60))
        #expect(AppleTopShelfPublisher.missingRecords(records: missing,
            continueWatching: [reverified], sources: [source]).isEmpty)
        #expect(AppleTopShelfPublisher.missingRecords(records: index,
            continueWatching: [continued], sources: []).isEmpty)
        var privateRecord = continued
        privateRecord.isPrivate = true
        #expect(AppleTopShelfPublisher.missingRecords(records: [privateRecord],
            continueWatching: [continued], sources: [source]).isEmpty)
    }

    @Test func homeFeedIgnoresVerificationChurnAndPublishesProgressChanges() throws {
        let feed = AppleTopShelfHeroFeed()
        var record = AppleMediaRecord(kind: .movie, title: "Fixture Film", availability: [])
        record.progress = 0.2
        feed.updateContinueWatching([record])
        let original = try #require(feed.continueWatching?.first)
        record.lastVerified = original.lastVerified.addingTimeInterval(60)
        feed.updateContinueWatching([record])
        #expect(feed.continueWatching?.first?.lastVerified == original.lastVerified)
        record.progress = 0.3
        feed.updateContinueWatching([record])
        #expect(feed.continueWatching?.first?.progress == 0.3)
        record.backdropURL = URL(string: "https://fixture.example/art/still.png")
        feed.updateContinueWatching([record])
        #expect(feed.continueWatching?.first?.backdropURL == record.backdropURL)
        feed.discardAfterReset()
        #expect(feed.continueWatching == nil)
        #expect(feed.heroes.isEmpty)
    }

    @Test func coldShelfRouteResolvesWithoutLoadedShelvesOrAnIndexWrite() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let routeURL = root.appending(path: "routes.json")
        let source = AppleSource(kind: .mediaServer, name: "Fixture Server",
            url: URL(string: "https://fixture.example/server")!)
        let item = AppleCatalogItem(mediaID: AppleMediaServerItemReference(sourceID: source.id, itemID: "film").mediaID,
            type: "movie", name: "Fixture Film", backgroundURL: URL(string: "https://fixture.example/art/still.png"))
        var record = AppleMediaIngestion.catalogRecord(instanceID: source.id, item: item)
        record.progress = 0.3
        let publisher = AppleTopShelfPublisher(writer: .init(containerProvider: { root }),
            routes: AppleTopShelfRouteStore(fileURL: routeURL))
        await publisher.publish(records: [], sources: [source], continueWatching: [record], enabled: true)
        let coldRoutes = AppleTopShelfRouteStore(fileURL: routeURL)
        let restored = try #require(await coldRoutes.record(id: record.id))
        #expect(restored.progress == nil)
        let unwatched = AppleMediaIngestion.catalogRecord(instanceID: source.id, item: AppleCatalogItem(
            mediaID: AppleMediaServerItemReference(sourceID: source.id, itemID: "unwatched").mediaID,
            type: "movie", name: "Unwatched Fixture Film"))
        try JSONEncoder().encode([restored, unwatched]).write(to: routeURL)
        let coldPublisher = AppleTopShelfPublisher(writer: .init(containerProvider: { root }), routes: coldRoutes)
        await coldPublisher.publish(records: [], sources: [source], enabled: true)
        #expect(try #require(AppleTopShelfSnapshotReader(containerProvider: { root }).read())
            .continueWatching.map(\.id) == [record.id])
        #expect(try JSONDecoder().decode([AppleMediaRecord].self, from: Data(contentsOf: routeURL)).map(\.id) == [record.id])
        var staleIndexRecord = record
        staleIndexRecord.progress = nil
        await coldPublisher.publish(records: [staleIndexRecord], sources: [source], enabled: true)
        #expect(try #require(AppleTopShelfSnapshotReader(containerProvider: { root }).read())
            .continueWatching.map(\.id) == [record.id])
        let match = try #require(AppleCatalogSearchMatch.mediaServer(restored, sources: [source]))
        #expect(match.item.mediaID == item.mediaID)
        #expect(match.item.name == item.name)
        #expect(match.source.id == source.id)
        let suite = UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let paths = Mutex<[String]>([])
        let client = AppleMediaServerClient(loader: { request in
            let url = try #require(request.url)
            paths.withLock { $0.append(url.path) }
            let body = Data(#"{"Id":"film","Name":"Fixture Film","Type":"Movie"}"#.utf8)
            return (body, try #require(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)))
        })
        let library = AppleMediaServerLibraryStore(client: client, progressDefaults: defaults)
        library.prepareRoute(source: match.source, session: AppleMediaServerSession(kind: .jellyfin,
            baseURL: source.url, accessToken: "fixture", userID: "fixture"))
        library.prepareRoute(source: match.source, session: AppleMediaServerSession(kind: .jellyfin,
            baseURL: URL(string: "https://fixture.example/replaced")!, accessToken: "fixture", userID: "fixture"))
        let reference = try #require(AppleMediaServerItemReference.parse(match.item.mediaID))
        let detail = try await library.detail(for: reference)
        #expect(detail.item.id == "film")
        #expect(library.shelves.isEmpty)
        #expect(library.continueWatching.isEmpty)
        #expect(paths.withLock { $0.count } == 1)
        #expect(paths.withLock { !$0[0].hasPrefix("/replaced") })
        var disabled = source
        disabled.isEnabled = false
        #expect(AppleCatalogSearchMatch.mediaServer(restored, sources: [disabled]) == nil)
        #expect(AppleCatalogSearchMatch.mediaServer(restored, sources: []) == nil)
        let snapshot = try #require(AppleTopShelfSnapshotReader(containerProvider: { root }).read())
        #expect(AppleAppRoute(url: snapshot.continueWatching[0].displayURL) == .media(id: record.id, action: .display))
        await coldPublisher.publish(records: [], sources: [source], continueWatching: [], enabled: true)
        #expect(try #require(AppleTopShelfSnapshotReader(containerProvider: { root }).read()).continueWatching.isEmpty)
    }

    @Test func routeCacheWriteFailureDoesNotPreventSnapshotPublication() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let blocked = root.appending(path: "blocked")
        try Data().write(to: blocked)
        let publisher = AppleTopShelfPublisher(writer: .init(containerProvider: { root }),
            routes: AppleTopShelfRouteStore(fileURL: blocked.appending(path: "routes.json")))
        await publisher.publish(records: [], sources: [], enabled: true)
        #expect(AppleTopShelfSnapshotReader(containerProvider: { root }).read() != nil)
        try FileManager.default.removeItem(at: blocked)
        await publisher.publish(records: [], sources: [], enabled: true)
        #expect(FileManager.default.fileExists(atPath: blocked.appending(path: "routes.json").path))
    }

    @Test func enabledSourceFilteringOnlyChangesContinueWatching() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let metadata = AppleMediaRecord(kind: .movie, title: "Fixture Favorite",
            availability: [.init(instanceID: AppleMediaAvailability.metadataOnlyInstanceID,
                capability: .resolvable, itemReference: "fixture")], isFavorite: true, progress: 0.3)
        try await AppleTopShelfSnapshotWriter(containerProvider: { root })
            .write(records: [metadata], sources: [], continueWatching: [metadata], enabled: true)
        let snapshot = try #require(AppleTopShelfSnapshotReader(containerProvider: { root }).read())
        #expect(snapshot.continueWatching.isEmpty)
        #expect(snapshot.favorites.map(\.id) == [metadata.id])
        #expect(snapshot.recentlyAdded.map(\.id) == [metadata.id])
    }

    @Test func removingAllSourcesClearsVisibleSectionsAndKeepsRecentlyAddedHistory() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = AppleSource(kind: .mediaServer, name: "Fixture Server",
                                 url: URL(string: "https://fixture.example/server")!)
        let item = AppleCatalogItem(mediaID: AppleMediaServerItemReference(sourceID: source.id, itemID: "fixture-film").mediaID,
            type: "movie", name: "Fixture Film",
            backgroundURL: URL(string: "https://fixture.example/art/still.png"))
        var record = AppleMediaIngestion.catalogRecord(instanceID: source.id, item: item)
        record.progress = 0.3
        let hero = AppleTopShelfHero.page(record: record, item: item, wordmark: nil)
        let writer = AppleTopShelfSnapshotWriter(containerProvider: { root })
        let reader = AppleTopShelfSnapshotReader(containerProvider: { root })

        try await writer.write(records: [record], sources: [source], heroes: [hero], enabled: true)
        #expect(try #require(reader.read()).continueWatching.map(\.id) == [record.id])
        try await writer.write(records: [record], sources: [], heroes: [hero], enabled: true)
        let empty = try #require(reader.read())
        #expect(empty.continueWatching.isEmpty)
        #expect(empty.recentlyAdded.map(\.id) == [record.id])
        #expect(empty.favorites.isEmpty)
        #expect(AppleTopShelfContentBuilder.sections(for: empty).isEmpty)
        #expect(AppleTopShelfContentBuilder.carouselItems(for: empty).isEmpty)
    }

    @Test func aCleanLibraryPublishesNoFixtureContent() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let writer = AppleTopShelfSnapshotWriter(containerProvider: { root })
        try await writer.write(records: [], sources: [], enabled: true)
        let snapshot = try #require(AppleTopShelfSnapshotReader(containerProvider: { root }).read())
        #expect(AppleTopShelfContentBuilder.sections(for: snapshot).isEmpty)
        #expect(AppleTopShelfContentBuilder.carouselItems(for: snapshot).isEmpty)
        #expect(snapshot.heroes.isEmpty)
    }

    @Test func aPlayedServerTitleAppearsWithUnchangedCatalogRecords() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let suite = UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let source = AppleSource(kind: .mediaServer, name: "Fixture Server",
                                 url: URL(string: "https://fixture.example/server")!)
        let records = (0..<3).map { index in
            AppleMediaIngestion.catalogRecord(instanceID: source.id, item: AppleCatalogItem(
                mediaID: AppleMediaServerItemReference(sourceID: source.id, itemID: "film-\(index)").mediaID,
                type: "movie", name: "Fixture Film \(index)"))
        }
        let store = ApplePlaybackStore(defaults: defaults)
        let publisher = AppleTopShelfPublisher(writer: .init(containerProvider: { root }))
        let reader = AppleTopShelfSnapshotReader(containerProvider: { root })
        await publisher.publish(records: records, sources: [source], enabled: true, playbackStore: store)
        #expect(try #require(reader.read()).continueWatching.isEmpty)

        store.save(mediaID: records[0].id, position: 30, duration: 300)
        await publisher.publish(records: records, sources: [source], enabled: true, playbackStore: store)
        let snapshot = try #require(reader.read())
        #expect(snapshot.continueWatching.map(\.id) == [records[0].id])
        #expect(snapshot.continueWatching.first?.progress == 0.1)
        #expect(Set(snapshot.topPicks.map(\.id)) == Set(records.dropFirst().map(\.id)))

        store.save(mediaID: records[1].id, position: 60, duration: 300)
        await publisher.publish(records: records, sources: [source], enabled: true, playbackStore: store)
        #expect(try #require(reader.read()).continueWatching.map(\.id) == [records[1].id, records[0].id])
        store.removeFromContinueWatching(mediaID: records[1].id)
        await publisher.publish(records: records, sources: [source], enabled: true, playbackStore: store)
        #expect(try #require(reader.read()).continueWatching.map(\.id) == [records[0].id])
    }

    @Test(arguments: [(false, false), (true, true)])
    func disabledAndPrivateServerTitlesStayOffTheShelf(isEnabled: Bool, isPrivate: Bool) async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = AppleSource(kind: .mediaServer, name: "Fixture Server",
            url: URL(string: "https://fixture.example/server")!, isEnabled: isEnabled)
        var record = AppleMediaIngestion.catalogRecord(instanceID: source.id, item: AppleCatalogItem(
            mediaID: AppleMediaServerItemReference(sourceID: source.id, itemID: "film").mediaID,
            type: "movie", name: "Fixture Film"))
        record.progress = 0.3
        record.isPrivate = isPrivate
        try await AppleTopShelfSnapshotWriter(containerProvider: { root })
            .write(records: [record], sources: [source], enabled: true)
        let snapshot = try #require(AppleTopShelfSnapshotReader(containerProvider: { root }).read())
        #expect(snapshot.continueWatching.isEmpty)
        #expect(snapshot.recentlyAdded.isEmpty == isPrivate)
    }

    @Test func resolvedHomeRowKeepsServerProgressAndMembershipOutsideTheIndex() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let suite = UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let source = AppleSource(kind: .mediaServer, name: "Fixture Server",
                                 url: URL(string: "https://fixture.example/server")!)
        let items = (0..<3).map { index in
            AppleCatalogItem(mediaID: AppleMediaServerItemReference(sourceID: source.id, itemID: "film-\(index)").mediaID,
                type: "movie", name: "Fixture Film \(index)")
        }
        let records = items.map { AppleMediaIngestion.catalogRecord(instanceID: source.id, item: $0) }
        let store = ApplePlaybackStore(defaults: defaults)
        let publisher = AppleTopShelfPublisher(writer: .init(containerProvider: { root }))
        let reader = AppleTopShelfSnapshotReader(containerProvider: { root })
        store.save(mediaID: items[0].mediaID, position: 30, duration: 300)
        store.save(mediaID: items[1].mediaID, position: 60, duration: 300)
        func homeRow() -> [AppleMediaRecord] {
            [1, 0].map { index in
                AppleTopShelfPublisher.continueWatchingRecord(records[index], item: items[index],
                    sourceID: source.id, playbackStore: store)
            }
        }

        await publisher.publish(records: [records[2]], sources: [source], continueWatching: homeRow(),
            enabled: true, playbackStore: store)
        let first = try #require(reader.read())
        #expect(first.continueWatching.map(\.id) == [records[1].id, records[0].id])
        #expect(first.continueWatching.map(\.progress) == [0.2, 0.1])
        #expect(first.topPicks.map(\.id) == [records[2].id])

        store.save(mediaID: items[0].mediaID, position: 90, duration: 300)
        await publisher.publish(records: [records[2]], sources: [source], continueWatching: homeRow(),
            enabled: true, playbackStore: store)
        #expect(try #require(reader.read()).continueWatching.map(\.progress) == [0.2, 0.3])
        await publisher.publish(records: [records[2]], sources: [source], continueWatching: [],
            enabled: true, playbackStore: store)
        #expect(try #require(reader.read()).continueWatching.isEmpty)
    }

    @Test func resolvedHomeRowCapsAndFiltersWithoutDroppingUpNext() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = AppleSource(kind: .mediaServer, name: "Fixture Server",
                                 url: URL(string: "https://fixture.example/server")!)
        let records = (0..<14).map { index in
            AppleMediaIngestion.catalogRecord(instanceID: source.id, item: AppleCatalogItem(
                mediaID: AppleMediaServerItemReference(sourceID: source.id, itemID: "show-\(index)").mediaID,
                type: "series", name: "Fixture Series \(index)"))
        }
        var privateRecord = records[13]
        privateRecord.isPrivate = true
        try await AppleTopShelfSnapshotWriter(containerProvider: { root }).write(records: [], sources: [source],
            continueWatching: [privateRecord] + records, enabled: true)
        let snapshot = try #require(AppleTopShelfSnapshotReader(containerProvider: { root }).read())
        #expect(snapshot.continueWatching.map(\.id) == Array(records.prefix(12)).map(\.id))
        #expect(snapshot.continueWatching.allSatisfy { $0.progress == nil })

        privateRecord = records[0]
        privateRecord.isPrivate = true
        try await AppleTopShelfSnapshotWriter(containerProvider: { root }).write(records: [privateRecord], sources: [source],
            continueWatching: [records[0]], enabled: true)
        #expect(try #require(AppleTopShelfSnapshotReader(containerProvider: { root }).read()).continueWatching.isEmpty)
    }

    @Test func shelfLinksResolveTheExactServerRouteAndRejectDisabledSources() {
        let source = AppleSource(kind: .mediaServer, name: "Fixture Server",
                                 url: URL(string: "https://fixture.example/server")!)
        let otherSource = AppleSource(kind: .mediaServer, name: "Other Server",
                                      url: URL(string: "https://fixture.example/other-server")!)
        let item = AppleCatalogItem(mediaID: AppleMediaServerItemReference(sourceID: source.id, itemID: "film").mediaID,
            type: "movie", name: "Fixture Film")
        let record = AppleMediaIngestion.catalogRecord(instanceID: source.id, item: item)
        let match = AppleCatalogSearchMatch.mediaServer(record, sources: [otherSource, source])
        #expect(match?.item == item)
        #expect(match?.source.id == source.id)
        #expect(AppleCatalogSearchMatch.mediaServer(record, sources: [otherSource]) == nil)
        var disabled = source
        disabled.isEnabled = false
        #expect(AppleCatalogSearchMatch.mediaServer(record, sources: [disabled]) == nil)
    }

    @Test func purgedSnapshotIsRepublishedWithoutInputChanges() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let suite = UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = ApplePlaybackStore(defaults: defaults)
        let publisher = AppleTopShelfPublisher(writer: .init(containerProvider: { root }))
        let url = AppleTopShelfSnapshotWriter.snapshotURL(in: root)
        await publisher.publish(records: [], sources: [], enabled: true, playbackStore: store)
        try FileManager.default.removeItem(at: url)
        await publisher.publish(records: [], sources: [], enabled: true, playbackStore: store)
        #expect(FileManager.default.fileExists(atPath: url.path))
    }

    @Test func disablingRemovesCachesAndLegacySnapshots() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let cache = root.appending(path: "Library/Caches").appending(path: AppleTopShelfSnapshotWriter.filename)
        let legacy = root.appending(path: AppleTopShelfSnapshotWriter.filename)
        try FileManager.default.createDirectory(at: cache.deletingLastPathComponent(), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let writer = AppleTopShelfSnapshotWriter(containerProvider: { root }, snapshotLocation: { _ in cache })
        try Data("legacy".utf8).write(to: legacy)
        try Data("cached".utf8).write(to: cache)
        try await writer.write(records: [], enabled: false)
        #expect(FileManager.default.fileExists(atPath: cache.path) == false)
        #expect(FileManager.default.fileExists(atPath: legacy.path) == false)
        // Opting out also removes legacy data when the cache was already purged.
        try Data("legacy".utf8).write(to: legacy)
        try await writer.write(records: [], enabled: false)
        #expect(FileManager.default.fileExists(atPath: legacy.path) == false)
    }

    @Test func oneCompletionSnapshotServesManyEpisodeLists() throws {
        let suite = UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = ApplePlaybackStore(defaults: defaults)
        store.markWatched(mediaID: "tt1:1:1")
        store.save(mediaID: "tt2:1:1", position: 995, duration: 1000)
        let snapshot = store.completionProgress()
        #expect(store.completedMediaIDs(among: [], progress: snapshot).isEmpty)
        #expect(store.completedMediaIDs(among: ["tt1:1:1", "tt1:1:2"], progress: snapshot) == ["tt1:1:1"])
        #expect(store.completedMediaIDs(among: ["tt2:1:1", "tt2:1:2"], progress: snapshot) == ["tt2:1:1"])
    }

    @Test func aFailedWriteIsRetriedOnTheNextUnchangedPublish() async throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "openstream-topshelf-retry-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let suite = "openstream-topshelf-retry-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = ApplePlaybackStore(defaults: defaults)
        let publisher = AppleTopShelfPublisher(writer: AppleTopShelfSnapshotWriter(containerProvider: { root }))
        let reader = AppleTopShelfSnapshotReader(containerProvider: { root })

        // The missing directory makes the real writer fail; no mock bypasses its I/O.
        await publisher.publish(records: [], sources: [], enabled: true, playbackStore: store)
        #expect(reader.read() == nil)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        await publisher.publish(records: [], sources: [], enabled: true, playbackStore: store)
        #expect(try #require(reader.read()).version == 1)
    }

    @Test func anUnavailableContainerIsRetriedOnTheNextUnchangedPublish() async throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "openstream-topshelf-container-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let available = Mutex(false)
        let writer = AppleTopShelfSnapshotWriter(containerProvider: { available.withLock { $0 ? root : nil } })
        let suite = "openstream-topshelf-container-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = ApplePlaybackStore(defaults: defaults)
        let publisher = AppleTopShelfPublisher(writer: writer)
        let reader = AppleTopShelfSnapshotReader(containerProvider: { root })

        await publisher.publish(records: [], sources: [], enabled: true, playbackStore: store)
        #expect(reader.read() == nil)
        available.withLock { $0 = true }
        await publisher.publish(records: [], sources: [], enabled: true, playbackStore: store)
        #expect(try #require(reader.read()).version == 1)
    }

    @Test func aMissingContainerReportsAWriteFailure() async throws {
        let writer = AppleTopShelfSnapshotWriter(containerProvider: { nil })
        await #expect(throws: (any Error).self) {
            try await writer.write(records: [], enabled: true)
        }
    }

    @Test func aWrittenSnapshotIsReadableAndDisablingRemovesIt() async throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "openstream-topshelf-readable-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let item = AppleCatalogItem(mediaID: "tt0000001", type: "movie", name: "Fixture Movie")
        var record = AppleMediaIngestion.catalogRecord(instanceID: UUID(), item: item)
        record.progress = 0.3
        let writer = AppleTopShelfSnapshotWriter(containerProvider: { root })
        let reader = AppleTopShelfSnapshotReader(containerProvider: { root })

        try await writer.write(records: [record], enabled: true)
        let snapshot = try #require(reader.read())
        #expect(snapshot.continueWatching.map(\.title) == ["Fixture Movie"])
        #expect(AppleTopShelfContentBuilder.sections(for: snapshot).map(\.title) == ["Continue Watching"])
        try await writer.write(records: [], enabled: false)
        #expect(reader.read() == nil)
        // Already absent is a successful privacy opt-out too.
        try await writer.write(records: [], enabled: false)
    }

    @Test func aNewSavedPositionRepublishesWithUnchangedRecords() async throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "openstream-topshelf-publisher-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let suite = "openstream-topshelf-publisher-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let source = AppleSource(kind: .mediaServer, name: "Fixture Server",
                                 url: URL(string: "https://fixture.example/server")!)
        let record = AppleMediaRecord(
            canonicalID: "tt0000001", kind: .series, title: "Series",
            availability: [.init(instanceID: source.id, capability: .direct, itemReference: "series|fixture")],
            progress: 0.2)
        let store = ApplePlaybackStore(defaults: defaults)
        let publisher = AppleTopShelfPublisher(writer: AppleTopShelfSnapshotWriter(containerProvider: { root }))
        let reader = AppleTopShelfSnapshotReader(containerProvider: { root })

        store.save(mediaID: record.id, position: 600, duration: 3000, partID: "tt0000001:1:1")
        await publisher.publish(records: [record], sources: [source], enabled: true, playbackStore: store)
        let first = try #require(reader.read()?.continueWatching.first?.progress)
        #expect(abs(first - 0.2) < 0.001)

        store.save(mediaID: record.id, position: 1500, duration: 3000, partID: "tt0000001:1:1")
        await publisher.publish(records: [record], sources: [source], enabled: true, playbackStore: store)
        let second = try #require(reader.read()?.continueWatching.first?.progress)
        #expect(abs(second - 0.5) < 0.001)
    }
}
