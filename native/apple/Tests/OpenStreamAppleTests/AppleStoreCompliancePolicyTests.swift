import Foundation
import Testing
@testable import OpenStreamApple

/// Owner decisions of 2026-10-01 from the App Store compliance audit (B4–B6):
/// no service brands on Discover rows, Netflix Top 10 off by default, and no
/// channel lineup in the shipped app.
@Suite("App Store compliance policy")
struct AppleStoreCompliancePolicyTests {
    private struct NoCredentials: AppleCredentialStoring {
        func string(for account: String) throws -> String? { nil }
        func set(_ value: String, for account: String) throws {}
        func remove(_ account: String) throws {}
    }

    private func freshDefaults() -> UserDefaults {
        let suite = "openstream.tests.compliance.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    // MARK: B4 — no service-brand row titles

    /// The Streaming Catalogs add-on's catalogs, as its manifest names them,
    /// plus the ids the app used to promote to brands.
    private static let serviceCatalogIDs = ["nfx", "nfk", "hbm", "dnp", "hlu", "amp", "pmp", "atp", "pcp", "pct",
                                            "cru", "streaming.nfx", "streaming.amp", "netflix-top10-us"]

    @Test("The app never heads a row with a brand the add-on did not name")
    func rowTitlesComeOnlyFromTheCatalogName() {
        let brands = ["Netflix", "Disney+", "HBO Max", "Hulu", "Prime", "Paramount+", "Apple TV+", "Peacock", "Crunchyroll"]
        for id in Self.serviceCatalogIDs {
            for type in ["movie", "series"] {
                let unnamed = AppleCatalogShelfPolicy.title(for: AppleStremioCatalog(type: type, id: id, name: nil))
                #expect(!brands.contains { unnamed.localizedCaseInsensitiveContains($0) }, "\(id)/\(type) → \(unnamed)")
                let neutral = AppleCatalogShelfPolicy.title(for: AppleStremioCatalog(type: type, id: id, name: "Popular Movies"))
                #expect(neutral == "Popular Movies", "\(id)/\(type) → \(neutral)")
            }
        }
    }

    @Test("Discover's visible rows carry no brand the add-on did not give them")
    func visibleRowsAreNotRebranded() {
        let source = AppleSource(kind: .stremio, name: "Streaming Catalogs",
                                 url: URL(string: "https://fixture.example/manifest.json")!)
        let sections = [("nfx", "movie", "Popular Movies"), ("nfx", "series", "Popular Shows"),
                        ("dnp", "movie", "Family Movies"), ("amp", "series", "Prime Video")].map { id, type, name in
            AppleCatalogSection(source: source, catalog: AppleStremioCatalog(type: type, id: id, name: name),
                                items: [AppleCatalogItem(mediaID: "tt-\(id)-\(type)", type: type, name: "Fixture \(id)")])
        }
        let titles = AppleCatalogShelfPolicy.visibleSections(sections, activeSourceIDs: [source.id]).compactMap(\.shelfTitle)
        #expect(titles == ["Family Movies", "Popular Movies", "Popular Shows", "Prime Video"])
    }

    // MARK: B5 — Netflix Top 10 off by default

    @MainActor
    @Test("Top 10 lists are off until the viewer turns them on")
    func top10ListsDefaultOff() {
        let defaults = freshDefaults()
        let store = AppleSettingsStore(defaults: defaults, keychain: NoCredentials())
        #expect(store.top10ListsEnabled == false)
        store.top10ListsEnabled = true
        #expect(AppleSettingsStore(defaults: defaults, keychain: NoCredentials()).top10ListsEnabled == true)
    }

    @MainActor
    @Test("Discover Rows settings list no Top 10 row by default")
    func discoverRowsOmitTop10ByDefault() {
        let defaults = freshDefaults()
        let settings = AppleSettingsStore(defaults: defaults, keychain: NoCredentials())
        let sourceStore = AppleSourceStore(defaults: defaults, storageKey: "compliance.sources",
                                           documentsDirectory: FileManager.default.temporaryDirectory)
        let ids = AppleDiscoverRowsSettingsView.rows(settings: settings, sourceStore: sourceStore, catalogStore: nil).map(\.id)
        #expect(!ids.contains(AppleDiscoverRowOrder.top10Movies))
        #expect(!ids.contains(AppleDiscoverRowOrder.top10Shows))
    }

    // MARK: B6 — bundled organisation preset, never a channel source

    @Test("Every build bundles Complete Guide")
    func resourceBundleContainsChannelLineup() throws {
        let bundle = AppleChannelLineupPresets.resourceBundle
        #expect(bundle.url(forResource: "complete-us", withExtension: "json", subdirectory: "ChannelLineup") != nil)
        #expect(try AppleChannelLineupPresets.readFile().channels.count >= 300)
    }

    @Test("A missing lineup falls back to the viewer's playlist")
    func unavailableLineupFallsBackToPlaylist() throws {
        // Without a lineup, the Complete Guide groups nothing by number and the
        // snapshot shows every playlist channel, named and logo'd by the playlist.
        let channels = [
            AppleIPTVChannel(id: "1", sourceID: UUID(), name: "ESPN", group: "Sports",
                             logoURL: URL(string: "http://x/espn.png"), streamURL: URL(string: "http://x/1")!),
            AppleIPTVChannel(id: "2", sourceID: UUID(), name: "Local News 7", group: "News",
                             streamURL: URL(string: "http://x/2")!),
        ]
        let groups = AppleChannelProjection.completeGuideGroups(from: channels, entries: [])
        #expect(groups.map(\.name) == ["Other"])
        #expect(groups.flatMap(\.channels).map(\.id) == ["1", "2"])
        let snapshot = AppleLiveChannelSnapshot.build(groups: groups, package: .completeGuide, custom: .init(),
                                                      entries: [], favoriteIDs: [], category: "All")
        #expect(snapshot.channels.map(\.id) == ["1", "2"])
        #expect(snapshot.channels.first?.logoURL == URL(string: "http://x/espn.png"))
        // The playlist's own groups still give the chips (Apple TV pass 2026-10-02).
        #expect(snapshot.categories == ["All", "Favorites", "News", "Sports"])
    }

    @Test("Package picker titles are the same in every build")
    func packageChoicesFollowTheLineup() {
        #expect(AppleLiveChannelPackage.available.map(\.title) == ["Complete Guide", "Everything", "Custom"])
        #expect(AppleLiveChannelPackage.defaultPackage(for: []) == .everything)
    }
}
