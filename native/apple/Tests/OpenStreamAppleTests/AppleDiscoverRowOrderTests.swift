import Foundation
import Testing
@testable import OpenStreamApple

@Suite("Discover row order")
struct AppleDiscoverRowOrderTests {
    private let featuredMovies = AppleDiscoverRowOrder.catalogID("fixture:movie:featured")
    private let featuredShows = AppleDiscoverRowOrder.catalogID("fixture:series:featured")

    private var defaultOrder: [String] {
        [AppleDiscoverRowOrder.continueWatching, AppleDiscoverRowOrder.library, AppleDiscoverRowOrder.topPicks,
         AppleDiscoverRowOrder.top10Movies, featuredMovies, featuredShows]
    }

    @Test func noSavedOrderKeepsTheDefault() {
        #expect(AppleDiscoverRowOrder.resolve(available: defaultOrder, custom: nil) == defaultOrder)
    }

    @Test func savedOrderIsApplied() {
        let custom = [featuredMovies, featuredShows, AppleDiscoverRowOrder.continueWatching,
                      AppleDiscoverRowOrder.library, AppleDiscoverRowOrder.topPicks, AppleDiscoverRowOrder.top10Movies]
        #expect(AppleDiscoverRowOrder.resolve(available: defaultOrder, custom: custom) == custom)
    }

    @Test func unknownRowsGoInAfterTheirDefaultNeighbour() {
        let newCatalog = AppleDiscoverRowOrder.catalogID("fixture:movie:new")
        let custom = [featuredMovies, AppleDiscoverRowOrder.library, AppleDiscoverRowOrder.continueWatching]
        let resolved = AppleDiscoverRowOrder.resolve(available: defaultOrder + [newCatalog], custom: custom)
        #expect(resolved == [featuredMovies, featuredShows, newCatalog, AppleDiscoverRowOrder.library,
                             AppleDiscoverRowOrder.topPicks, AppleDiscoverRowOrder.top10Movies,
                             AppleDiscoverRowOrder.continueWatching])
    }

    @Test func staleAndDuplicateIDsAreDropped() {
        let custom = [AppleDiscoverRowOrder.catalogID("fixture:removed"), featuredShows, featuredShows,
                      AppleDiscoverRowOrder.continueWatching, AppleDiscoverRowOrder.library,
                      AppleDiscoverRowOrder.topPicks, AppleDiscoverRowOrder.top10Movies, featuredMovies]
        #expect(AppleDiscoverRowOrder.resolve(available: defaultOrder, custom: custom)
                == Array(custom.dropFirst(2)))
    }

    @Test func continueWatchingStaysFirstByDefaultAndHidesWhenEmpty() {
        #expect(AppleDiscoverRowOrder.resolve(available: defaultOrder, custom: nil).first
                == AppleDiscoverRowOrder.continueWatching)
        let custom = [featuredMovies, AppleDiscoverRowOrder.continueWatching]
        let nothingToResume = defaultOrder.filter { $0 != AppleDiscoverRowOrder.continueWatching }
        #expect(!AppleDiscoverRowOrder.resolve(available: nothingToResume, custom: custom)
            .contains(AppleDiscoverRowOrder.continueWatching))
    }

    @Test func debugOrderMatchesShelfTitles() {
        let order = AppleDiscoverRowOrder.debugOrder(
            "featuredMovies, library",
            catalogTitles: [("fixture:movie:featured", "Featured Movies")])
        #expect(order == [featuredMovies, AppleDiscoverRowOrder.library])
    }

    @MainActor @Test func orderRoundTripsThroughConfigurationBackup() throws {
        let name = "discover-row-order-tests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = AppleSettingsStore(defaults: defaults, keychain: RowOrderTestCredentials())
        #expect(settings.discoverRowOrder == nil)
        #expect(AppleSettingsStore.configurationKeys.contains("openstream.settings.discover.rowOrder.v1"))
        let custom = [featuredMovies, AppleDiscoverRowOrder.library]
        settings.discoverRowOrder = custom
        let values = try settings.configurationValues()
        settings.discoverRowOrder = nil
        #expect(defaults.object(forKey: "openstream.settings.discover.rowOrder.v1") == nil)
        try settings.restoreConfiguration(values)
        #expect(settings.discoverRowOrder == custom)
        #expect(AppleSettingsStore(defaults: defaults, keychain: RowOrderTestCredentials()).discoverRowOrder == custom)
    }
}

private final class RowOrderTestCredentials: AppleCredentialStoring {
    private var values: [String: String] = [:]
    func string(for account: String) throws -> String? { values[account] }
    func set(_ value: String, for account: String) throws { values[account] = value }
    func remove(_ account: String) throws { values.removeValue(forKey: account) }
}
