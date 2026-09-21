import Testing
@testable import OpenStreamApple

/// A Siri phrase or a deep link used to select Discover and then push
/// Discover's own search page on top — on Apple TV, which already carries
/// Search as a tab. The pushed page also carried a `navigationTitle`, which on
/// tvOS draws over the page.
@Suite("Search route destination")
struct AppleSearchRoutePolicyTests {
    @Test func aPlatformWithASearchTabDoesNotAlsoPushSearch() {
        #expect(AppleSearchRoutePolicy.discoverPushesSearch(hasDedicatedSearchTab: true) == false)
    }

    @Test func aPlatformWithoutOneReachesSearchByPushingIt() {
        #expect(AppleSearchRoutePolicy.discoverPushesSearch(hasDedicatedSearchTab: false))
    }

    /// Apple TV is the platform with the tab; the phone and pad push.
    @Test func theTelevisionIsTheOneWithTheTab() {
        #if os(tvOS)
        #expect(AppleSearchRoutePolicy.platformHasDedicatedSearchTab)
        #else
        #expect(!AppleSearchRoutePolicy.platformHasDedicatedSearchTab)
        #endif
    }

    /// The two halves must agree: wherever the tab exists, nothing pushes.
    @Test func theTwoHalvesNeverBothFire() {
        let pushes = AppleSearchRoutePolicy.discoverPushesSearch(
            hasDedicatedSearchTab: AppleSearchRoutePolicy.platformHasDedicatedSearchTab)
        #expect(pushes != AppleSearchRoutePolicy.platformHasDedicatedSearchTab)
    }
}

/// `openSearch()` is the Mac ⌘F path, added because Search on macOS is a page
/// pushed from Discover with no tab and no shortcut to reach it.
@Suite("Opening search with no query")
@MainActor
struct AppleAppRouterOpenSearchTests {
    @Test("⌘F routes to Search with an empty field")
    func openSearchRoutesWithNoQuery() {
        let router = AppleAppRouter()
        router.openSearch()
        #expect(router.route == .search(""))
        #expect(router.searchQuery.isEmpty)
        #expect(router.revision == 1)
    }

    /// `showSearch(_:)` serves `openstream://search?query=…`, where a link with
    /// no term in it is a malformed link. That refusal is why ⌘F needed its own
    /// entry point rather than passing an empty string through this one.
    @Test("A deep link with no term is still refused")
    func showSearchStillRefusesAnEmptyQuery() {
        let router = AppleAppRouter()
        router.showSearch("   ")
        #expect(router.route == nil)
        #expect(router.revision == 0)
    }

    @Test("⌘F clears a query left over from an earlier deep link")
    func openSearchClearsAPreviousQuery() {
        let router = AppleAppRouter()
        router.showSearch("dune")
        #expect(router.searchQuery == "dune")
        router.openSearch()
        #expect(router.searchQuery.isEmpty)
        #expect(router.revision == 2)
    }
}
