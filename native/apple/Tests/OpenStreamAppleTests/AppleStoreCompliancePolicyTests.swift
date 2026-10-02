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

    // MARK: B6 — no bundled channel lineup

    @Test("The app's resource bundle ships no channel lineup")
    func resourceBundleHasNoChannelLineup() throws {
        let bundle = AppleChannelLineupPresets.resourceBundle
        #expect(bundle.url(forResource: "premier-us-extended", withExtension: "json") == nil)
        #expect(bundle.url(forResource: "premier-us", withExtension: "json") == nil)
        #expect(bundle.urls(forResourcesWithExtension: "json", subdirectory: "ChannelLineup")?.isEmpty ?? true)
        if let resourcePath = bundle.resourcePath {
            let contents = (try? FileManager.default.subpathsOfDirectory(atPath: resourcePath)) ?? []
            #expect(!contents.contains { $0.localizedCaseInsensitiveContains("ChannelLineup") || $0.hasPrefix("premier-us") })
        }
        // The package manifest no longer copies it in either.
        // …/Tests/OpenStreamAppleTests/Fixtures/ChannelLineup/premier-us-extended.json → package root
        let manifest = AppleChannelLineupPresets.debugFixtureURL
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Package.swift")
        let text = try String(contentsOf: manifest, encoding: .utf8)
        #expect(!text.contains("ChannelLineup"))
        #expect(!FileManager.default.fileExists(atPath: manifest.deletingLastPathComponent()
            .appendingPathComponent("Sources/OpenStreamApple/Resources/ChannelLineup").path))
    }

    @Test("A Release build has an empty lineup and falls back to the playlist")
    func releaseLineupIsEmpty() throws {
        #expect(try AppleChannelLineupPresets.lineup(allowDebugFixture: false).isEmpty)
        // Debug keeps the fixture so the Premier Guide paths stay testable.
        #expect(try AppleChannelLineupPresets.lineup(allowDebugFixture: true).count >= 300)
        #expect(AppleChannelLineupPresets.debugFixtureURL.path.contains("/Tests/OpenStreamAppleTests/Fixtures/ChannelLineup/"))

        // Without a lineup, the Premier Guide groups nothing by number and the
        // snapshot shows every playlist channel, named and logo'd by the playlist.
        let channels = [
            AppleIPTVChannel(id: "1", sourceID: UUID(), name: "ESPN", group: "Sports",
                             logoURL: URL(string: "http://x/espn.png"), streamURL: URL(string: "http://x/1")!),
            AppleIPTVChannel(id: "2", sourceID: UUID(), name: "Local News 7", group: "News",
                             streamURL: URL(string: "http://x/2")!),
        ]
        let groups = AppleChannelProjection.premierGuideGroups(from: channels, entries: [])
        #expect(groups.map(\.name) == ["Other"])
        #expect(groups.flatMap(\.channels).map(\.id) == ["1", "2"])
        let snapshot = AppleLiveChannelSnapshot.build(groups: groups, package: .premierGuide, custom: .init(),
                                                      entries: [], favoriteIDs: [], category: "All")
        #expect(snapshot.channels.map(\.id) == ["1", "2"])
        #expect(snapshot.channels.first?.logoURL == URL(string: "http://x/espn.png"))
        #expect(snapshot.categories == ["All", "Favorites"])
    }

    @Test("Package choices follow the lineup: no Premier Guide without one")
    func packageChoicesFollowTheLineup() {
        if AppleChannelLineupPresets.isAvailable {
            #expect(AppleLiveChannelPackage.available == AppleLiveChannelPackage.allCases)
            #expect(AppleLiveChannelPackage.defaultPackage == .premierGuide)
        } else {
            #expect(AppleLiveChannelPackage.available == [.everything, .custom])
            #expect(AppleLiveChannelPackage.defaultPackage == .everything)
        }
    }
}
