import Foundation
import Testing
@testable import OpenStreamApple

private final class SeedCredentialStore: AppleCredentialStoring, @unchecked Sendable {
    private var values: [String: String] = [:]
    func string(for reference: String) throws -> String? { values[reference] }
    func set(_ value: String, for reference: String) throws { values[reference] = value }
    func remove(_ reference: String) throws { values[reference] = nil }
}

@MainActor
private func seedStore(manifestName: String = "AIOMetadata") -> (AppleSourceStore, UserDefaults) {
    let defaults = UserDefaults(suiteName: "seed.\(UUID().uuidString)")!
    let manifest = """
    {"id":"community.aiometadata","version":"1.0.0","name":"\(manifestName)","description":"test",
     "resources":["catalog","meta"],"types":["movie","series"],
     "catalogs":[{"type":"movie","id":"aio.popular","name":"Popular"}]}
    """
    let client = AppleManifestClient(loader: { url in
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Type": "application/json"])!
        return (Data(manifest.utf8), response)
    })
    let store = AppleSourceStore(
        defaults: defaults, storageKey: "seed.sources", keychain: SeedCredentialStore(),
        documentsDirectory: FileManager.default.temporaryDirectory, manifestClient: client)
    return (store, defaults)
}

@Suite @MainActor struct AppleTestCatalogSeedTests {
    @Test func seedsAIOMetadataOnceWithItsCatalogs() async throws {
        let (store, _) = seedStore()
        await store.seedTestCatalogsIfNeeded(force: true)
        let added = store.sources.filter { $0.kind == .stremio }
        #expect(added.count == 1)
        #expect(added.first?.name == "AIOMetadata")
        #expect(added.first?.url.host == "aiometadata.elfhosted.com")
        #expect(added.first?.catalogs.map(\.id) == ["aio.popular"])

        await store.seedTestCatalogsIfNeeded(force: true)
        #expect(store.sources.filter { $0.kind == .stremio }.count == 1)
    }

    /// seed-sim.sh: a device set up from the dev-sources file gets only
    /// that file, never AIOMetadata beside it (Apple TV check 2026-10-01).
    @Test func devSourcesSetupSkipsTheTestCatalogs() async {
        let (store, _) = seedStore()
        store.markTestCatalogsSeeded()
        await store.seedTestCatalogsIfNeeded(force: true)
        #expect(store.sources.filter { $0.kind == .stremio }.isEmpty)
    }

    @Test func aDeletedSeedStaysDeleted() async throws {
        let (store, _) = seedStore()
        await store.seedTestCatalogsIfNeeded(force: true)
        let id = try #require(store.sources.first { $0.kind == .stremio }?.id)
        #expect(store.remove(id: id))
        await store.seedTestCatalogsIfNeeded(force: true)
        #expect(store.sources.filter { $0.kind == .stremio }.isEmpty)
    }
}
