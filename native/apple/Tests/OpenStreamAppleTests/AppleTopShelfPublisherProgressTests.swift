import Foundation
import Synchronization
import Testing
@testable import OpenStreamApple

/// Review of 2b1f930: the Top Shelf bar follows the playback store, so a
/// new saved position republishes even when the media records are unchanged.
@Suite(.serialized)
@MainActor
struct AppleTopShelfPublisherProgressTests {
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
