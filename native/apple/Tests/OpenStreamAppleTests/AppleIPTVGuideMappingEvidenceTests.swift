import Foundation
import Testing
import Synchronization
@testable import OpenStreamApple

@Suite("Durable guide mapping evidence", .serialized)
struct AppleIPTVGuideMappingEvidenceTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func resolve(_ names: [String: String], declared: String? = nil, manual: String? = nil,
                         previous: AppleIPTVGuideMappingEvidence? = nil, uniqueName: Bool = true,
                         shift: Double = 0, correction: Double = 0, fetchedAt: Date? = nil) -> AppleIPTVGuideMappingEvidence? {
        AppleIPTVGuideMappingEvidence.resolve(id: "local", declaredID: declared, manualID: manual,
            name: "News HD", uniqueName: uniqueName, index: .init(names: names), available: Set(names.keys),
            previous: previous, channelShiftHours: shift, correctionHours: correction, fetchedAt: fetchedAt ?? now)
    }

    @Test func providerGuideIDChangeRetainsManualFavoriteAndRecentKeys() throws {
        let source = UUID()
        func playlist(_ guideID: String) throws -> [AppleIPTVChannel] {
            try AppleIPTVClient.parseM3U(Data("""
            #EXTM3U
            #EXTINF:-1 tvg-id="\(guideID)",News
            https://fixture.example/live/news.m3u8
            """.utf8), sourceID: source, baseURL: URL(string: "https://fixture.example/playlist.m3u")!)
        }
        let original = try #require(playlist("old").first)
        let received = try playlist("new")
        let channel = try #require(AppleIPTVChannelCache.reconciled(received, previous: [original], sourceID: source).first)
        let manual = [original.id: "station"]
        let favorites: Set<String> = [original.id]
        let recents = [original.id]
        #expect(channel.id == original.id && channel.guideID == "new")
        #expect(manual[channel.id] == "station" && favorites.contains(channel.id) && recents.contains(channel.id))
        let decoded = try JSONDecoder().decode(AppleIPTVChannel.self, from: JSONEncoder().encode(channel))
        #expect(decoded.id == original.id && decoded.guideID == "new")
        let duplicate = received[0].withLocalIdentity("different")
        #expect(AppleIPTVChannelCache.reconciled(received + [duplicate], previous: [original], sourceID: source).map(\.id) == (received + [duplicate]).map(\.id))
        #expect(AppleIPTVChannelCache.reconciled(received, previous: [original], sourceID: UUID()) == received)
    }

    @Test func duplicateNamesNeedIdentityAndManualAlwaysWins() throws {
        let names = ["1.news": "News", "10.news": "News FHD"]
        #expect(resolve(names) == nil)
        #expect(resolve(["1.news": "News"], uniqueName: false) == nil)
        let exact = try #require(resolve(names, declared: "10.news"))
        #expect(exact.providerID == "10.news" && exact.origin == .providerID && exact.confidence == 1)
        let manual = try #require(resolve(names, declared: "10.news", manual: "1.news"))
        #expect(manual.providerID == "1.news" && manual.origin == .manual)
        #expect(resolve(names, declared: "10.news", previous: manual)?.providerID == "10.news")
    }

    @Test func providerIDChangeKeepsManualAndPreviouslyResolvedIdentity() throws {
        let previous = try #require(resolve(["old": "News"], declared: "old"))
        let retained = try #require(resolve(["old": "News", "other": "News"], declared: "changed", previous: previous))
        #expect(retained.providerID == "old" && retained.declaredProviderID == "changed")
        #expect(resolve(["new": "News"], declared: "new", previous: previous)?.providerID == "new")
        let manual = try #require(resolve(["old": "News"], declared: "changed", manual: "old"))
        let vanished = try #require(resolve(["new": "News"], declared: "new", manual: "old", previous: manual))
        #expect(vanished.providerID == "old" && vanished.isStale)
        let byName = try #require(resolve(["new": "News"]))
        #expect(byName.origin == .name && byName.confidence == 0.95)
    }

    @Test func explicitDSTOffsetsAndFractionalCorrectionApplyOnceToRawData() throws {
        let raw = AppleIPTVGuideXMLTVParser().parse(data: Data("""
        <tv>
        <programme channel="one" start="20261101013000 -0400" stop="20261101013000 -0500"><title>Fallback</title></programme>
        </tv>
        """.utf8), defaultOffsetHours: 9)
        let programme = try #require(raw.first)
        #expect(programme.end.timeIntervalSince(programme.start) == 3600)
        let first = try #require(resolve(["one": "News"], declared: "one", shift: -4.5, correction: 1))
        let corrected = try #require(resolve(["one": "News"], declared: "one", previous: first, shift: -4.5, correction: 2))
        #expect(first.project(raw, channelID: "local").first?.start == programme.start.addingTimeInterval(-3.5 * 3600))
        #expect(corrected.project(raw, channelID: "local").first?.start == programme.start.addingTimeInterval(-2.5 * 3600))
        #expect(corrected.project(raw, channelID: "local") == corrected.project(raw, channelID: "local"))
    }

    @Test func coveragePreservesGapsAndEvidenceRoundTripsWithoutChangingLegacySettings() throws {
        var evidence = try #require(resolve(["one": "News"], manual: "one"))
        func programme(_ start: Double, _ end: Double) -> AppleIPTVProgramme {
            AppleIPTVProgramme(id: String(start), channelID: "local", title: "Fixture", subtitle: nil,
                description: nil, start: now.addingTimeInterval(start), end: now.addingTimeInterval(end), category: nil, isLive: false)
        }
        evidence.coverage = AppleIPTVGuideMappingEvidence.coverage(of: [programme(0, 60), programme(30, 90), programme(120, 180)])
        #expect(evidence.coverage == [DateInterval(start: now, duration: 90), DateInterval(start: now.addingTimeInterval(120), duration: 60)])
        let snapshot = AppleIPTVGuideDiskCache.Snapshot(programmes: [], channelNames: [:], mappingEvidence: ["local": evidence])
        let restored = try JSONDecoder().decode(AppleIPTVGuideDiskCache.Snapshot.self, from: JSONEncoder().encode(snapshot))
        #expect(restored.mappingEvidence?["local"] == evidence)
        let legacy = try JSONDecoder().decode(AppleIPTVGuideDiskCache.Snapshot.self, from: Data("{\"programmes\":[],\"channelNames\":{}}".utf8))
        #expect(legacy.mappingEvidence == nil)
    }
    @Test func failedOrEmptyRefreshCannotClaimNewCoverageOrEraseManualGuide() throws {
        var previous = try #require(resolve(["one": "News"], manual: "one"))
        let raw = AppleIPTVProgramme(id: "fixture", channelID: "one", title: "Fixture", subtitle: nil,
            description: nil, start: now, end: now.addingTimeInterval(3600), category: nil, isLive: false)
        let saved = previous.project([raw], channelID: "local")
        previous.coverage = AppleIPTVGuideMappingEvidence.coverage(of: saved)
        let incoming = try #require(resolve(["other": "News"], manual: "one", previous: previous, fetchedAt: now.addingTimeInterval(60)))
        let failed = AppleIPTVGuideMappingEvidence.replacement(providerProgrammes: nil, channelID: "local",
            evidence: incoming, previousProgrammes: saved, previousEvidence: previous)
        #expect(failed.programmes == saved && failed.evidence == previous)
        let empty = AppleIPTVGuideMappingEvidence.replacement(providerProgrammes: [], channelID: "local",
            evidence: incoming, previousProgrammes: saved, previousEvidence: previous)
        #expect(empty.programmes == saved && empty.evidence.isStale)
        #expect(empty.evidence.coverage == previous.coverage && empty.evidence.fetchedAt == previous.fetchedAt)
        let changed = try #require(resolve(["other": "News"], manual: "other"))
        let reassigned = AppleIPTVGuideMappingEvidence.replacement(providerProgrammes: [], channelID: "local",
            evidence: changed, previousProgrammes: saved, previousEvidence: previous)
        #expect(reassigned.programmes.isEmpty && reassigned.evidence.providerID == "other")
    }

    @MainActor @Test func failureAndMissingManualTargetRetainGuideAndEvidenceAcrossRestart() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let disk = AppleIPTVGuideDiskCache(directory: directory)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MappingEvidenceProtocol.self]
        let loader = AppleIPTVGuideLoader(session: URLSession(configuration: configuration))
        let store = AppleIPTVGuideStore(loader: loader, diskCache: disk)
        let url = URL(string: "https://fixture.example/evidence.xml")!
        let start = try #require(AppleIPTVGuideXMLTVParser.parseDate("20261101013000 -0400", defaultOffsetHours: 0))
        MappingEvidenceProtocol.state.withLock { $0 = 0 }
        store.manualChannelMapping = ["local": "one"]
        store.configure(xmltvURL: url, channelMapping: ["local": "one"], channelShifts: ["local": -0.5], timeShiftHours: 1)
        await store.refreshVisible(channelIDs: ["local"], now: start)
        let original = try #require(store.guide(for: ["local"]).allProgrammes.first)
        let evidence = try #require(store.mappingEvidence["local"])
        #expect(original.start == start.addingTimeInterval(1800))
        MappingEvidenceProtocol.state.withLock { $0 = 1 }
        store.configure(xmltvURL: url, channelMapping: ["local": "changed"], defaultOffsetHours: 2, channelShifts: ["local": -0.5], timeShiftHours: 1)
        await store.refreshVisible(channelIDs: ["local"], force: true, now: start.addingTimeInterval(60))
        #expect(store.guide(for: ["local"]).allProgrammes == [original])
        #expect(store.mappingEvidence["local"] == evidence)
        #expect(store.manualChannelMapping == ["local": "one"])
        let restarted = AppleIPTVGuideStore(loader: loader, diskCache: disk)
        restarted.manualChannelMapping = ["local": "one"]
        restarted.configure(xmltvURL: url, channelMapping: ["local": "changed"], defaultOffsetHours: 2)
        await restarted.refreshVisible(channelIDs: ["local"], force: true, now: start.addingTimeInterval(120))
        #expect(restarted.guide(for: ["local"]).allProgrammes == [original])
        #expect(restarted.mappingEvidence["local"]?.fetchedAt == evidence.fetchedAt)
        MappingEvidenceProtocol.state.withLock { $0 = 2 }
        await restarted.refreshVisible(channelIDs: ["local"], force: true, now: start.addingTimeInterval(180))
        #expect(restarted.guide(for: ["local"]).allProgrammes == [original])
        #expect(restarted.mappingEvidence["local"]?.isStale == true)
        #expect(restarted.mappingEvidence["local"]?.providerID == "one")
        #expect(restarted.mappingEvidence["local"]?.fetchedAt == evidence.fetchedAt)
    }

    @MainActor @Test func legacyManualGuideCacheMigratesOfflineWithProviderIdentitySeparate() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let disk = AppleIPTVGuideDiskCache(directory: directory)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MappingEvidenceProtocol.self]
        MappingEvidenceProtocol.state.withLock { $0 = 1 }
        let start = try #require(AppleIPTVGuideXMLTVParser.parseDate("20261101013000 -0400", defaultOffsetHours: 0))
        let raw = AppleIPTVProgramme(id: "legacy", channelID: "one", title: "Saved guide", subtitle: nil,
            description: nil, start: start, end: start.addingTimeInterval(3600), category: nil, isLive: false)
        // The old Live view folded the manual assignment into channelMapping as well as the manual dictionary.
        let legacyKey = "|https://fixture.example/evidence.xml|0.0|0.0|local=one|local=one|"
        await disk.store([raw], key: legacyKey, channelNames: ["one": "News"], fetchedAt: start, isRawXMLTV: true)
        let store = AppleIPTVGuideStore(loader: AppleIPTVGuideLoader(session: URLSession(configuration: configuration)), diskCache: disk)
        store.channelDisplayNames = ["local": "News"]
        store.manualChannelMapping = ["local": "one"]
        store.configure(xmltvURL: URL(string: "https://fixture.example/evidence.xml")!, channelMapping: ["local": "declared"])
        await store.refreshVisible(channelIDs: ["local"], now: start)
        #expect(store.guide(for: ["local"]).allProgrammes.first?.title == "Saved guide")
        #expect(store.mappingEvidence["local"]?.origin == .manual)
        #expect(store.mappingEvidence["local"]?.declaredProviderID == "declared")
        #expect(store.mappingEvidence["local"]?.fetchedAt == start)
        #expect(store.manualChannelMapping == ["local": "one"])
    }

    @MainActor @Test func offsetChangeProjectsFreshRawCacheOnceWithoutAnotherRequest() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MappingEvidenceProtocol.self]
        MappingEvidenceProtocol.state.withLock { $0 = 0 }
        let store = AppleIPTVGuideStore(loader: AppleIPTVGuideLoader(session: URLSession(configuration: configuration)),
            diskCache: AppleIPTVGuideDiskCache(directory: directory))
        let url = URL(string: "https://fixture.example/evidence.xml")!
        let start = try #require(AppleIPTVGuideXMLTVParser.parseDate("20261101013000 -0400", defaultOffsetHours: 0))
        store.configure(xmltvURL: url, channelMapping: ["local": "one"], timeShiftHours: 1)
        await store.refreshVisible(channelIDs: ["local"], now: start)
        MappingEvidenceProtocol.state.withLock { $0 = 1 } // Any further request would fail.
        store.configure(xmltvURL: url, channelMapping: ["local": "one"], timeShiftHours: 2)
        await store.refreshVisible(channelIDs: ["local"], now: start.addingTimeInterval(60))
        #expect(store.guide(for: ["local"]).allProgrammes.first?.start == start.addingTimeInterval(7200))
        #expect(store.mappingEvidence["local"]?.correctionHours == 2)
        await store.refreshVisible(channelIDs: ["local"], now: start.addingTimeInterval(120))
        #expect(store.guide(for: ["local"]).allProgrammes.first?.start == start.addingTimeInterval(7200))
    }

}


private final class MappingEvidenceProtocol: URLProtocol {
    static let state = Mutex(0)
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let state = Self.state.withLock { $0 }
        if state == 1 {
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
            return
        }
        let body = state == 2 ? "<tv><channel id=\"new\"><display-name>News</display-name></channel></tv>" : """
        <tv><channel id="one"><display-name>News</display-name></channel>
        <programme channel="one" start="20261101013000 -0400" stop="20261101013000 -0500"><title>Fixture</title></programme></tv>
        """
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
