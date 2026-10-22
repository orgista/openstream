import Foundation
import Synchronization
import Testing
@testable import OpenStreamApple

@Suite("Top 10 rows: TMDB's weekly chart kept on disk")
struct AppleTop10StoreTests {
    private func temporaryFile() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "top10-\(UUID().uuidString).json")
    }

    private let movie = AppleCatalogItem(mediaID: "tt1234567", type: "movie", name: "Nimona")
    private let show = AppleCatalogItem(mediaID: "tt7654321", type: "series", name: "Unabomber")

    @Test func aFreshChartIsKeptAndReadBackAfterARelaunch() async throws {
        let file = temporaryFile()
        defer { try? FileManager.default.removeItem(at: file) }
        let calls = Mutex(0)
        let store = AppleTop10Store(fileURL: file) { [movie, show] type, _ in
            calls.withLock { $0 += 1 }
            return type == "movie" ? [movie] : [show]
        }
        let configuration = try AppleTMDBConfiguration(credential: "fixture-key")
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        #expect(await store.stored() == nil)
        let chart = try await store.latest(configuration: configuration, now: now)
        #expect(chart.movies == [movie] && chart.shows == [show])
        _ = try await store.latest(configuration: configuration, now: now.addingTimeInterval(60))
        #expect(calls.withLock { $0 } == 2)

        let relaunched = AppleTop10Store(fileURL: file) { _, _ in [] }
        #expect(await relaunched.stored() == chart)
    }

    @Test func aStaleChartIsAskedAgainAndAFailureLeavesTheKeptOne() async throws {
        let file = temporaryFile()
        defer { try? FileManager.default.removeItem(at: file) }
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let kept = AppleTop10Store.Chart(movies: [movie], shows: [show], fetchedAt: now)
        try JSONEncoder().encode(kept).write(to: file)
        let configuration = try AppleTMDBConfiguration(credential: "fixture-key")

        let failing = AppleTop10Store(fileURL: file) { _, _ in throw URLError(.notConnectedToInternet) }
        #expect(try await failing.latest(configuration: configuration, now: now.addingTimeInterval(60)) == kept)
        await #expect(throws: URLError.self) {
            try await failing.latest(configuration: configuration, now: now.addingTimeInterval(AppleTop10Store.refreshInterval + 1))
        }
        #expect(await failing.stored() == kept)
    }
}
