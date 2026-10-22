import Foundation
import Testing
@testable import OpenStreamApple

/// The launch prefetch warms the channels Live draws first (owner 2026-10-22).
struct AppleLivePrefetchTests {
    private static let source = UUID()

    private static func channel(_ number: Int, logo: Bool = true) -> AppleIPTVChannel {
        AppleIPTVChannel(id: "\(source.uuidString):\(number)", sourceID: source, name: "Channel \(number)",
                         logoURL: logo ? URL(string: "https://fixture.example/logo/\(number).png") : nil,
                         streamURL: URL(string: "https://fixture.example/live/\(number).ts")!)
    }

    private static let lineup = (1...250).map { channel($0) }

    @Test func theFirstHundredInPlaylistOrder() {
        let leading = AppleLivePrefetch.leadingChannels(Self.lineup, preferredIDs: [], hiddenIDs: [])
        #expect(leading.count == AppleLivePrefetch.leadingCount)
        #expect(leading.map(\.id) == Self.lineup.prefix(100).map(\.id))
    }

    @Test func watchedAndFavouriteChannelsComeFirstOnce() {
        let watched = Self.lineup[199].id, favourite = Self.lineup[149].id
        let leading = AppleLivePrefetch.leadingChannels(Self.lineup,
            preferredIDs: [watched, favourite, watched, "gone"], hiddenIDs: [], limit: 4)
        #expect(leading.map(\.id) == [watched, favourite, Self.lineup[0].id, Self.lineup[1].id])
    }

    @Test func hiddenChannelsAreSkippedEvenWhenFavourite() {
        let hidden = Self.lineup[0].id
        let leading = AppleLivePrefetch.leadingChannels(Self.lineup, preferredIDs: [hidden],
                                                        hiddenIDs: [hidden], limit: 2)
        #expect(leading.map(\.id) == [Self.lineup[1].id, Self.lineup[2].id])
    }

    @Test func logosAreRequestedAtTheRowsSize() {
        let requests = AppleLivePrefetch.logoRequests([Self.channel(1), Self.channel(2, logo: false)], displayScale: 3)
        #expect(requests.map(\.url) == [URL(string: "https://fixture.example/logo/1.png")!])
        // A 50 pt logo at 3x decodes into the 256 px bucket, as the row's own view does.
        #expect(requests.map(\.maximumPixelDimension) == [256])
    }

    /// The guide setup now runs at every launch: a playlist that lists one
    /// channel id twice must not trap (`Dictionary(uniqueKeysWithValues:)` did).
    @MainActor @Test func guideSetupTakesDuplicateChannelIDs() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let suite = "live-prefetch-duplicates-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let sources = AppleSourceStore(defaults: defaults, keychain: PrefetchTestCredentials(),
                                       documentsDirectory: root.appendingPathComponent("documents"))
        let source = try sources.addIPTV(name: "Fixture TV", type: .m3u,
            endpoint: "https://fixture.example/channels.m3u", username: "", password: "")
        let settings = AppleSettingsStore(defaults: defaults, keychain: PrefetchTestCredentials())
        func channel(_ name: String, shift: Double) -> AppleIPTVChannel {
            var channel = AppleIPTVChannel(id: "\(source.id.uuidString):dup", sourceID: source.id, name: name,
                streamURL: URL(string: "https://fixture.example/live/\(name).ts")!, guideID: "guide.\(name)")
            channel.guideShiftHours = shift
            return channel
        }
        let guide = AppleIPTVGuideStore()
        guide.configure(liveSources: [source], channels: [channel("First", shift: 1), channel("Second", shift: 2)],
                        sourceStore: sources, settings: settings)
        #expect(guide.channelDisplayNames == ["\(source.id.uuidString):dup": "First"])
        #expect(guide.channelProviderIDs == ["\(source.id.uuidString):dup": "guide.First"])
    }
}

private struct PrefetchTestCredentials: AppleCredentialStoring {
    func string(for account: String) throws -> String? { nil }
    func set(_ value: String, for account: String) throws {}
    func remove(_ account: String) throws {}
}
