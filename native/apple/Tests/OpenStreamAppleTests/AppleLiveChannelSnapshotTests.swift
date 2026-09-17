import Foundation
import Testing
@testable import OpenStreamApple

@Test func liveSnapshotKeepsCategoriesFavoritesAndChannelIDsConsistent() throws {
    let source = UUID()
    let channels = [
        AppleIPTVChannel(id: "news", sourceID: source, name: "CNN HD", group: "News", streamURL: URL(string: "https://fixture.example/news.ts")!),
        AppleIPTVChannel(id: "sports", sourceID: source, name: "ESPN (EAST)", group: "Sports", streamURL: URL(string: "https://fixture.example/sports.ts")!)
    ]
    let entries = try AppleChannelLineupPresets.premierUS()
    let snapshot = AppleLiveChannelSnapshot.build(groups: [.init(name: "All", channels: channels)],
        package: .everything, custom: .init(), entries: entries, favoriteIDs: ["sports"], category: "Favorites")
    #expect(snapshot.channels.map(\.id) == ["sports"])
    #expect(snapshot.channelIDs == ["sports"])
    #expect(snapshot.categories.contains("News"))
    #expect(snapshot.categories.contains("Sports"))
    let all = AppleLiveChannelSnapshot.build(groups: [.init(name: "All", channels: channels)],
        package: .everything, custom: .init(), entries: entries, favoriteIDs: [], category: "All")
    #expect(Set(all.channelIDs) == ["news", "sports"])
}

/// Owner 2026-09-14: "reduce the live line up to the premier safe thing we did
/// with iPhone and android". `premierGuideGroups` returns the curated lineup
/// *and* an "Other" group of everything it could not match, and the guide was
/// flattening both — 4749 of the owner's 9376 channels reached the grid.
@Suite("Premier Guide lineup")
struct ApplePremierGuideLineupTests {
    private let source = UUID()

    private func channel(_ id: String, _ name: String) -> AppleIPTVChannel {
        AppleIPTVChannel(id: id, sourceID: source, name: name, group: "All",
                         streamURL: URL(string: "https://fixture.example/\(id).ts")!)
    }

    private var lineup: [AppleChannelLineupEntry] {
        [AppleChannelLineupEntry(number: 2, name: "CBS", aliases: ["CBS (EAST)"], category: "Local"),
         AppleChannelLineupEntry(number: 5, name: "FOX", aliases: ["FOX (EAST)"], category: "Local")]
    }

    private var channels: [AppleIPTVChannel] {
        [channel("cbs", "CBS (EAST)"), channel("fox", "FOX (EAST)"),
         channel("rando1", "PPV Barker 14"), channel("rando2", "24/7 Kitchen Nightmares")]
    }

    @Test func allShowsOnlyTheCuratedLineup() {
        let snapshot = AppleLiveChannelSnapshot.build(
            groups: [.init(name: "All", channels: channels)], package: .premierGuide,
            custom: .init(), entries: lineup, favoriteIDs: [], category: "All")
        #expect(snapshot.channelIDs == ["cbs", "fox"])
    }

    @Test func everythingStillShowsEverything() {
        let snapshot = AppleLiveChannelSnapshot.build(
            groups: [.init(name: "All", channels: channels)], package: .everything,
            custom: .init(), entries: lineup, favoriteIDs: [], category: "All")
        #expect(snapshot.channelIDs.count == 4)
    }

    /// An empty guide would be worse than an unfiltered one.
    @Test func aLineupThatMatchesNothingFallsBackToTheChannelsWeHave() {
        let snapshot = AppleLiveChannelSnapshot.build(
            groups: [.init(name: "All", channels: channels)], package: .premierGuide,
            custom: .init(), entries: [], favoriteIDs: [], category: "All")
        #expect(snapshot.channelIDs.count == 4)
    }

    @Test func favoritesAreNotLimitedToTheLineup() {
        let snapshot = AppleLiveChannelSnapshot.build(
            groups: [.init(name: "All", channels: channels)], package: .premierGuide,
            custom: .init(), entries: lineup, favoriteIDs: ["rando1"], category: "Favorites")
        #expect(snapshot.channelIDs == ["rando1"])
    }
}
