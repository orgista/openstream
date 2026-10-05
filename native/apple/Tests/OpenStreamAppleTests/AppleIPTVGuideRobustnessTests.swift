import Foundation
import Synchronization
import Testing
@testable import OpenStreamApple

@Suite("Guide robustness")
struct AppleIPTVGuideRobustnessTests {
    @Test func missingOffsetUsesConfiguredZoneAndExplicitOffsetWins() throws {
        let xml = Data("""
        <tv>
        <programme channel="a" start="20301005090000" stop="20301005100000"><title>Local</title></programme>
        <programme channel="a" start="20301005090000 +0000" stop="20301005100000 +0000"><title>UTC</title></programme>
        <programme channel="a" start="bad" stop="20301005100000"><title>Bad</title></programme>
        <programme channel="a" start="20301005110000" stop="20301005100000"><title>Reversed</title></programme>
        </tv>
        """.utf8)
        let programmes = AppleIPTVGuideXMLTVParser().parse(data: xml, defaultOffsetHours: -5)
        #expect(programmes.count == 2)
        let local = try #require(programmes.first { $0.title == "Local" })
        let utc = try #require(programmes.first { $0.title == "UTC" })
        #expect(local.start.timeIntervalSince(utc.start) == 5 * 3600)
    }

    @Test func cacheExpiresByProgrammeEndAndKeepsFutureData() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = AppleIPTVGuideDiskCache(directory: directory)
        let now = Date(timeIntervalSince1970: 1000)
        func programme(_ id: String, end: Date) -> AppleIPTVProgramme {
            AppleIPTVProgramme(id: id, channelID: "a", title: id, subtitle: nil, description: nil,
                start: now.addingTimeInterval(-100), end: end, category: nil, isLive: false)
        }
        await cache.store([programme("old", end: now), programme("next", end: now.addingTimeInterval(60))], key: "fixture")
        let restored = await cache.programmes(key: "fixture", now: now)
        #expect(restored.map(\.id) == ["next"])
        #expect(await cache.programmes(key: "other", now: now).isEmpty)
        #expect(await cache.programmes(key: "fixture", now: now.addingTimeInterval(60)).isEmpty)
    }
    @MainActor @Test func xmltvRefreshPopulatesMoreThanFiftyChannelsAndRestoresWithoutNetwork() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let disk = AppleIPTVGuideDiskCache(directory: directory)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [RobustGuideProtocol.self]
        let loader = AppleIPTVGuideLoader(session: URLSession(configuration: config))
        let source = UUID()
        let mapping = Dictionary(uniqueKeysWithValues: (0..<80).map { (source.uuidString + ":" + String($0), "p" + String($0)) })
        let url = URL(string: "https://fixture.example/guide.xml")!
        RobustGuideProtocol.requests.withLock { $0 = 0 }
        let first = AppleIPTVGuideStore(loader: loader, diskCache: disk)
        first.configure(xmltvURL: url, sourceID: source, channelMapping: mapping, timeShiftHours: 2)
        await first.refreshVisible(channelIDs: [source.uuidString + ":0"])
        #expect(first.guide(for: mapping.keys).allProgrammes.count == 80)
        let original = AppleIPTVGuideXMLTVParser().parse(data: Data("<tv><programme channel=\"p0\" start=\"20301005090000 +0000\" stop=\"20301005100000 +0000\"><title>Programme 0</title></programme></tv>".utf8))
        #expect(first.guide(for: mapping.keys).allProgrammes.first?.start == original.first?.start.addingTimeInterval(7200))
        let relaunched = AppleIPTVGuideStore(loader: loader, diskCache: disk)
        relaunched.configure(xmltvURL: url, sourceID: source, channelMapping: mapping, timeShiftHours: 2)
        await relaunched.refreshVisible(channelIDs: Set(mapping.keys))
        #expect(relaunched.guide(for: mapping.keys).allProgrammes.count == 80)
        #expect(RobustGuideProtocol.requests.withLock { $0 } == 1)
    }

}


private final class RobustGuideProtocol: URLProtocol {
    static let requests = Mutex(0)
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.requests.withLock { $0 += 1 }
        let entries = (0..<80).map { index in
            "<programme channel=\"p\(index)\" start=\"20301005090000 +0000\" stop=\"20301005100000 +0000\"><title>Programme \(index)</title></programme>"
        }.joined()
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(("<tv>" + entries + "</tv>").utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
