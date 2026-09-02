import Foundation
import Testing
@testable import OpenStreamApple

@Test func iptvPolicyAndXtreamEndpointKeepCredentialsOutOfTheBaseURL() throws {
    #expect(try AppleIPTVEndpointPolicy.normalize(" HTTP://TV.Example:8080/base ").absoluteString ==
        "http://tv.example:8080/base")
    #expect(throws: AppleIPTVError.invalidEndpoint) {
        try AppleIPTVEndpointPolicy.normalize("ftp://tv.example/playlist.m3u")
    }
    #expect(throws: AppleIPTVError.invalidEndpoint) {
        try AppleIPTVEndpointPolicy.normalize("http://user:pass@tv.example/playlist.m3u")
    }

    let url = try AppleIPTVClient.xtreamPlaylistURL(
        baseURL: URL(string: "https://tv.example/panel")!,
        username: "viewer+one",
        password: "secret value"
    )
    let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
    #expect(components.path == "/panel/get.php")
    let query = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
    #expect(query["username"] == "viewer+one")
    #expect(query["password"] == "secret value")
    #expect(query["type"] == "m3u_plus")
    #expect(query["output"] == "m3u8")
}

@Test func iptvParserKeepsMetadataHeadersAndSafeRelativeStreams() throws {
    let sourceID = UUID()
    let data = Data(#"""
    #EXTM3U url-tvg="https://guide.example/guide.xml"
    #EXTINF:-1 tvg-id="news.one" tvg-logo="https://img.example/news.png" group-title="News",News One
    #EXTVLCOPT:http-user-agent=Provider Player
    #EXTVLCOPT:http-referrer=https://tv.example/
    live/news.m3u8
    #EXTINF:-1 group-title="Movies",Cinema
    https://cdn.example/cinema.m3u8
    #EXTINF:-1,Duplicate
    https://cdn.example/cinema.m3u8
    #EXTINF:-1,Unsafe
    file:///private/movie.mp4
    """#.utf8)

    let channels = try AppleIPTVClient.parseM3U(
        data,
        sourceID: sourceID,
        baseURL: URL(string: "https://tv.example/playlist/main.m3u")!
    )

    #expect(channels.count == 2)
    #expect(channels[0].name == "News One")
    #expect(channels[0].group == "News")
    #expect(channels[0].streamURL == URL(string: "https://tv.example/playlist/live/news.m3u8"))
    #expect(channels[0].logoURL == URL(string: "https://img.example/news.png"))
    #expect(channels[0].userAgent == "Provider Player")
    #expect(channels[0].referer == "https://tv.example/")
    #expect(channels[1].name == "Cinema")
}

@MainActor
@Test func iptvAndLibrarySourcesPersistWithoutLeakingCredentialsIntoURLs() throws {
    let suiteName = "openstream-live-library-tests-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let store = AppleSourceStore(defaults: defaults)

    let live = try store.addIPTV(
        name: "Home TV",
        type: .xtream,
        endpoint: "http://192.168.1.50:8080",
        username: "viewer",
        password: "secret"
    )
    let folder = URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: "OpenStream Media")
    let library = try store.addLibraryFolder(name: "Media", url: folder, bookmarkData: Data([1, 2, 3]))

    #expect(live.url.absoluteString == "http://192.168.1.50:8080")
    #expect(!live.url.absoluteString.contains("viewer"))
    #expect(live.username == "viewer")
    #expect(library.bookmarkData == Data([1, 2, 3]))
    #expect(AppleSourceStore(defaults: defaults).sources == store.sources)
}

@Test func libraryScannerFindsOnlySupportedVideoFiles() async throws {
    let root = FileManager.default.temporaryDirectory
        .appending(path: "openstream-library-test-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try Data([0]).write(to: root.appending(path: "Movie.mp4"))
    try Data([0]).write(to: root.appending(path: "Clip.mkv"))
    try Data([0]).write(to: root.appending(path: "Notes.txt"))

    let source = AppleSource(kind: .library, name: "Test", url: root)
    let items = try await AppleLibraryScanner().scan(source: source)

    #expect(items.map(\.name) == ["Clip.mkv", "Movie.mp4"])
    #expect(items.allSatisfy { $0.sourceID == source.id })
}

@Test func stremioMetadataClientLoadsEpisodeIdentitiesForSeriesPlayback() async throws {
    let source = AppleSource(
        kind: .stremio,
        name: "Catalog",
        url: URL(string: "https://catalog.example/config/manifest.json")!,
        resources: ["catalog", "meta"]
    )
    let client = AppleStremioMetadataClient { request in
        #expect(request.url?.absoluteString == "https://catalog.example/config/meta/series/tt123.json")
        let data = Data(#"""
        {"meta":{"videos":[
          {"id":"tt123:1:1","title":"Pilot","season":1,"episode":1},
          {"id":"tt123:1:2","name":"Second","season":"1","episode":"2"},
          {"id":"","title":"Bad"}
        ]}}
        """#.utf8)
        return (
            data,
            HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        )
    }

    let episodes = try await client.episodes(source: source, mediaID: "tt123")

    #expect(episodes.map(\.id) == ["tt123:1:1", "tt123:1:2"])
    #expect(episodes.map(\.displayTitle) == ["S1 E1 · Pilot", "S1 E2 · Second"])
}

@Test func stremioMetadataClientFallsBackToDedicatedMetadataAddon() async throws {
    let catalog = AppleSource(
        kind: .stremio,
        name: "Catalog only",
        url: URL(string: "https://catalog.example/manifest.json")!,
        resources: ["catalog"]
    )
    let metadata = AppleSource(
        kind: .stremio,
        name: "Metadata",
        url: URL(string: "https://meta.example/manifest.json")!,
        resources: ["meta"]
    )
    let client = AppleStremioMetadataClient { request in
        #expect(request.url?.host == "meta.example")
        let data = Data(#"{"meta":{"videos":[{"id":"tt456:1:1","title":"Pilot","season":1,"episode":1}]}}"#.utf8)
        return (
            data,
            HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        )
    }

    let episodes = try await client.episodes(
        sources: [catalog, metadata],
        preferredSourceID: catalog.id,
        mediaID: "tt456"
    )

    #expect(episodes.map(\.id) == ["tt456:1:1"])
}
