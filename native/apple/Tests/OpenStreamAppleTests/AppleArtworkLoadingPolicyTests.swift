import Foundation
import Testing
@testable import OpenStreamApple

struct AppleArtworkLoadingPolicyTests {
    @Test @MainActor func loadedIdentitySurvivesPauseAndColdLoadsWaitOnlyForMovement() async throws {
        let gate = AppleArtworkLoadingGate()
        gate.isPaused = true
        // Cached posters and nonmoving surfaces have no unconditional dwell.
        try await gate.waitUntilReady(isCached: true)
        var loaded = false
        let task = Task { @MainActor in
            try await gate.waitUntilReady(isCached: false)
            loaded = true
        }
        await Task.yield()
        #expect(!loaded)
        gate.isPaused = false
        try await task.value
        #expect(loaded)
        try await gate.waitUntilReady(isCached: false)
        #expect(!AppleArtworkLoadingPolicy.needsReload(loadedIdentity: "poster", requestedIdentity: "poster"))
        // A failed/cancelled replacement cleared the bitmap. Returning to the
        // old URL must reload even if its former identity is still remembered.
        #expect(AppleArtworkLoadingPolicy.needsReload(loadedIdentity: "poster", requestedIdentity: "poster", hasImage: false))
        #expect(AppleArtworkLoadingPolicy.needsReload(loadedIdentity: "poster", requestedIdentity: "other"))
    }

    @Test func prefetchIsTwentyAheadAndBounded() {
        let items = (0..<40).map { AppleCatalogItem(mediaID: "\($0)", type: "movie", name: "\($0)",
            posterURL: URL(string: "https://fixture.example/\($0).jpg")) }
        #expect(AppleArtworkPrefetchPolicy.ahead(after: items[5].id, in: items).count == 20)
        #expect(AppleArtworkPrefetchPolicy.ahead(after: items[5].id, in: items).first?.lastPathComponent == "6.jpg")
        #expect(AppleArtworkPrefetchPolicy.ahead(after: items[38].id, in: items).count == 1)
        #expect(AppleArtworkPrefetchPolicy.ahead(after: "missing", in: items).isEmpty)
        #expect(AppleArtworkLoadingPolicy.shouldPause(isScrolling: true, focusSettled: true))
        #expect(AppleArtworkLoadingPolicy.shouldPause(isScrolling: false, focusSettled: false))
        #expect(AppleArtworkLoadingPolicy.shouldPause(isScrolling: false, focusSettled: true) == false)
    }
}
