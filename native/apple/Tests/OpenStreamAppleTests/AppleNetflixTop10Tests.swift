import Testing
import Foundation
@testable import OpenStreamApple

@Suite("AppleNetflixTop10 Tests")
struct AppleNetflixTop10Tests {
    
    @Test("Parse inline TSV fixture")
    func testParseTSV() async throws {
        let tsv = """
        country_name\tcountry_iso2\tweek\tcategory\tweekly_rank\tshow_title\tseason_title
        United States\tUS\t2026-09-01\tFilms\t1\tThe Big Movie\tN/A
        United States\tUS\t2026-09-01\tTV\t1\tThe Big Show\tSeason 1
        United States\tUS\t2026-08-25\tFilms\t1\tOld Movie\tN/A
        United Kingdom\tGB\t2026-09-01\tFilms\t1\tUK Movie\tN/A
        """
        
        // Setup mock URLProtocol to return the fixture
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: config)
        
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, tsv.data(using: .utf8)!)
        }
        
        let client = AppleNetflixTop10Client(session: session, country: "US")
        let result = try await client.latestWeek()
        
        #expect(result.films.count == 1)
        #expect(result.films[0].title == "The Big Movie")
        #expect(result.films[0].rank == 1)
        #expect(result.films[0].category == "movie")
        
        #expect(result.tv.count == 1)
        #expect(result.tv[0].title == "The Big Show")
        #expect(result.tv[0].seasonTitle == "Season 1")
        #expect(result.tv[0].category == "series")
    }

}

class MockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?
    
    override class func canInit(with request: URLRequest) -> Bool {
        return true
    }
    
    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        return request
    }
    
    override func startLoading() {
        guard let handler = MockURLProtocol.requestHandler else {
            fatalError("Handler is unavailable.")
        }
        
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }
    
    override func stopLoading() {}
}

@Test func netflixStreamingParserKeepsOnlyNewestWeekWithUnsortedRows() throws {
    var parser = AppleNetflixTop10Parser(country: "US")
    try parser.consume("country_iso2\tweek\tcategory\tweekly_rank\tshow_title\tseason_title")
    for n in 0..<10_000 {
        try parser.consume("US\t2026-08-01\tFilms\t1\tOld \(n)\tN/A")
    }
    try parser.consume("US\t2026-09-01\tFilms\t2\tSecond\tN/A")
    try parser.consume("US\t2026-08-01\tFilms\t1\tOld\tN/A")
    try parser.consume("GB\t2026-09-08\tFilms\t1\tForeign\tN/A")
    try parser.consume("US\t2026-09-01\tFilms\t1\tFirst\tN/A")
    try parser.consume("US\t2026-09-01\tFilms\t1\tDuplicate\tN/A")
    try parser.consume("US\t2026-09-01\tTV\t1\tShow\tSeason 1")
    let result = try parser.finish()
    #expect(result.films.map(\.title) == ["First", "Second"])
    #expect(result.tv.map(\.title) == ["Show"])
    #expect(parser.isOtherCountry(Array("GB\t2026-09-08\tFilms\t1\tForeign\tN/A".utf8)))
    #expect(!parser.isOtherCountry(Array("us\t2026-09-08\tFilms\t1\tHome\tN/A".utf8)))
    #expect(!parser.isOtherCountry(Array("US".utf8)))
}

private final class Top10WeekCacheProtocol: URLProtocol {
    nonisolated(unsafe) static var requests: [URLRequest] = []
    nonisolated(unsafe) static var status = 200
    static let tsv = "country_iso2\tweek\tcategory\tweekly_rank\tshow_title\tseason_title\nUS\t2026-10-05\tFilms\t1\tFirst\tN/A\n"

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.requests.append(request)
        let response = HTTPURLResponse(url: request.url!, statusCode: Self.status, httpVersion: nil,
                                       headerFields: ["ETag": "\"week-41\""])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if Self.status == 200 { client?.urlProtocol(self, didLoad: Data(Self.tsv.utf8)) }
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

/// One test drives the protocol's shared state, so nothing else runs beside it.
@Test func top10WeekIsKeptOnDiskAndRevalidatedDaily() async throws {
    let file = FileManager.default.temporaryDirectory.appending(path: "netflix-top10-\(UUID().uuidString).json")
    defer { try? FileManager.default.removeItem(at: file) }
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [Top10WeekCacheProtocol.self]
    let session = URLSession(configuration: configuration)
    let now = Date(timeIntervalSince1970: 2_000_000_000)

    let first = try await AppleNetflixTop10Client(session: session, fileURL: file).latestWeek(now: now)
    #expect(first.films.map(\.title) == ["First"])
    #expect(Top10WeekCacheProtocol.requests.count == 1)

    // A relaunch the same day reads the disk and asks nobody.
    let relaunch = AppleNetflixTop10Client(session: session, fileURL: file)
    #expect(try await relaunch.latestWeek(now: now.addingTimeInterval(3600)) == first)
    #expect(Top10WeekCacheProtocol.requests.count == 1)

    // The kept week is there at launch without the network, before the refresh may run.
    #expect(await AppleNetflixTop10Client(session: session, fileURL: file).storedWeek(now: now) == first)
    #expect(await AppleNetflixTop10Client(session: session).storedWeek(now: now) == nil)
    #expect(Top10WeekCacheProtocol.requests.count == 1)

    // A day later it asks with the file's validator; 304 keeps the saved week.
    Top10WeekCacheProtocol.status = 304
    let revalidated = try await relaunch.latestWeek(now: now.addingTimeInterval(AppleNetflixTop10Client.refreshInterval + 1))
    #expect(revalidated == first)
    #expect(Top10WeekCacheProtocol.requests.count == 2)
    #expect(Top10WeekCacheProtocol.requests.last?.value(forHTTPHeaderField: "If-None-Match") == "\"week-41\"")

    // Two callers at once share one download.
    Top10WeekCacheProtocol.status = 200
    let fresh = AppleNetflixTop10Client(session: session)
    async let one = fresh.latestWeek(now: now)
    async let two = fresh.latestWeek(now: now)
    let both = try await [one, two]
    #expect(both.allSatisfy { $0.films.map(\.title) == ["First"] })
    #expect(Top10WeekCacheProtocol.requests.count == 3)
}
