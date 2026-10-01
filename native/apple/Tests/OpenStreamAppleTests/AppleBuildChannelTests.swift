import Foundation
import Testing
@testable import OpenStreamApple

@Suite struct AppleBuildChannelTests {
    @Test func sandboxReceiptIsRecognised() {
        #expect(AppleBuildChannel.isSandboxReceipt("sandboxReceipt"))
    }

    @Test func appStoreReceiptAndNoReceiptAreNotSandbox() {
        #expect(!AppleBuildChannel.isSandboxReceipt("receipt"))
        #expect(!AppleBuildChannel.isSandboxReceipt(nil))
    }
}

@Suite struct AppleTestCatalogSeedPolicyTests {
    /// TestFlight, App Review and the App Store all run Release archives; App
    /// Review's carries the same sandbox receipt as TestFlight. None of them
    /// may start with a catalog the user did not add.
    @Test func releaseBuildsNeverSeedWhateverTheReceipt() {
        #expect(!AppleTestCatalogSeedPolicy.seedsTestCatalogs(isDebugBuild: false))
        #expect(AppleTestCatalogSeedPolicy.manifests(isDebugBuild: false).isEmpty)
    }

    @Test func debugBuildsSeedTheTestCatalogs() {
        #expect(AppleTestCatalogSeedPolicy.seedsTestCatalogs(isDebugBuild: true))
        #expect(!AppleTestCatalogSeedPolicy.manifests(isDebugBuild: true).isEmpty)
    }

    /// The store follows the policy for the build it was compiled in (tests
    /// run as DEBUG).
    @MainActor @Test func storeFollowsThePolicyForThisBuild() {
        #expect(AppleTestCatalogSeedPolicy.isDebugBuild)
        #expect(AppleSourceStore.seedsTestCatalogs == AppleTestCatalogSeedPolicy.seedsTestCatalogs(isDebugBuild: true))
        #expect(AppleSourceStore.testCatalogManifests == AppleTestCatalogSeedPolicy.manifests(isDebugBuild: true))
    }
}

@Suite struct AppleTraceDefaultTests {
    @Test func sandboxReceiptTracesUnlessTheBuildSaysOtherwise() {
        #expect(AppleInteractionTrace.defaultEnabled(infoPlistFlag: nil, isTestFlight: true))
        #expect(!AppleInteractionTrace.defaultEnabled(infoPlistFlag: false, isTestFlight: true))
    }

    @Test func appStoreStaysOffUnlessTheBuildTurnsItOn() {
        #expect(!AppleInteractionTrace.defaultEnabled(infoPlistFlag: nil, isTestFlight: false))
        #expect(AppleInteractionTrace.defaultEnabled(infoPlistFlag: true, isTestFlight: false))
    }
}

@Suite struct AppleAttributionTests {
    @Test func tmdbLogoShipsInTheBundle() {
        #expect(AppleTMDBAttributionRow.logo != nil)
    }

    @Test func noSourcesSaysTheAppShipsNoContent() {
        #expect(AppleDiscoverEmptyState.noSources.footnote == AppleAttribution.noContentDisclaimer)
        #expect(AppleDiscoverEmptyState.nothingToShow.footnote == nil)
        #expect(AppleAttribution.tmdbNotice == "This product uses the TMDB API but is not endorsed or certified by TMDB.")
    }
}
