import Foundation
import Synchronization
import Testing
@testable import OpenStreamApple

@Suite("Top 10 artwork: TMDB matches kept on disk")
struct AppleTop10ArtworkStoreTests {
    private func temporaryFile() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "top10-\(UUID().uuidString).json")
    }

    @Test func chartTitlesCompareWithoutCaseArticleOrPunctuation() {
        #expect(AppleTop10ArtworkLookup.chartKey("UNABOMBER") == AppleTop10ArtworkLookup.chartKey("Unabomber"))
        #expect(AppleTop10ArtworkLookup.chartKey("A Different World") == "different world")
        #expect(AppleTop10ArtworkLookup.chartKey("The Widower: 'Til Death Do Us Part") == "widower til death do us part")
        #expect(AppleTop10ArtworkLookup.chartKey("The") == "the")
    }

    @Test func aMatchIsAskedOnceAndReadBackAfterARelaunch() async throws {
        let file = temporaryFile()
        defer { try? FileManager.default.removeItem(at: file) }
        let calls = Mutex(0)
        let found = AppleCatalogItem(mediaID: "tt1234567", type: "series", name: "Unabomber",
                                     backgroundURL: URL(string: "https://fixture.example/backdrop.jpg"))
        let store = AppleTop10ArtworkStore(fileURL: file) { _, _, _ in
            calls.withLock { $0 += 1 }
            return found
        }
        let configuration = try AppleTMDBConfiguration(credential: "fixture-key")
        #expect(store.cached(title: "UNABOMBER", type: "series") == nil)
        #expect(await store.resolve(title: "UNABOMBER", type: "series", configuration: configuration) == found)
        #expect(await store.resolve(title: "Unabomber", type: "series", configuration: configuration) == found)
        #expect(calls.withLock { $0 } == 1)
        let relaunched = AppleTop10ArtworkStore(fileURL: file) { _, _, _ in nil }
        #expect(relaunched.cached(title: "UNABOMBER", type: "series") == found)
    }

    @Test func aMissWaitsADayAndAFailureIsNotRemembered() async throws {
        let file = temporaryFile()
        defer { try? FileManager.default.removeItem(at: file) }
        let answers = Mutex<[Result<AppleCatalogItem?, Error>]>([.failure(URLError(.timedOut)), .success(nil), .success(nil)])
        let calls = Mutex(0)
        let store = AppleTop10ArtworkStore(fileURL: file) { _, _, _ in
            calls.withLock { $0 += 1 }
            return try answers.withLock { $0.removeFirst() }.get()
        }
        let configuration = try AppleTMDBConfiguration(credential: "fixture-key")
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        #expect(await store.resolve(title: "East of Eden", type: "series", configuration: configuration, now: now) == nil)
        #expect(await store.resolve(title: "East of Eden", type: "series", configuration: configuration, now: now) == nil)
        #expect(await store.resolve(title: "East of Eden", type: "series", configuration: configuration,
                                    now: now.addingTimeInterval(3600)) == nil)
        #expect(calls.withLock { $0 } == 2)
        _ = await store.resolve(title: "East of Eden", type: "series", configuration: configuration,
                                now: now.addingTimeInterval(AppleTop10ArtworkStore.missRetry + 1))
        #expect(calls.withLock { $0 } == 3)
    }
}
