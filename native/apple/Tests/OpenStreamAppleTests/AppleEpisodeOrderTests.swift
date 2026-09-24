import Testing
@testable import OpenStreamApple

/// N32 #14: a daily show's season must read in number order, never string
/// order ("Episode 1000" before "Episode 816"), with the air date breaking ties.
@Suite("Episode order")
struct AppleEpisodeOrderTests {
    private func episode(_ id: String, _ season: Int?, _ number: Int?, aired: String? = nil) -> AppleStremioEpisode {
        AppleStremioEpisode(id: id, title: "Episode \(number.map(String.init) ?? "?")",
                            season: season, episode: number, releaseInfo: aired)
    }

    @Test func numbersSortNumerically() {
        let episodes = [episode("c", 1, 1000), episode("b", 1, 818), episode("d", 1, 9), episode("a", 1, 816), episode("e", 1, 1)]
        #expect(AppleStremioEpisodePolicy.episodes(in: 1, from: episodes).map(\.episode) == [1, 9, 816, 818, 1000])
    }

    @Test func seasonsSortBeforeEpisodes() {
        let episodes = [episode("x", 10, 1), episode("y", 2, 5), episode("z", 2, 1)]
        #expect(AppleStremioEpisodePolicy.episodes(in: nil, from: episodes).map(\.id) == ["z", "y", "x"])
    }

    @Test func sameNumberFallsBackToAirDateThenUndatedLast() {
        let episodes = [
            episode("undated", 1, 5),
            episode("late", 1, 5, aired: "1984-09-12T00:00:00.000Z"),
            episode("early", 1, 5, aired: "1984-09-10T00:00:00.000Z"),
        ]
        #expect(AppleStremioEpisodePolicy.episodes(in: 1, from: episodes).map(\.id) == ["early", "late", "undated"])
    }
}
