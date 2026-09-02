import Foundation
import Testing
@testable import OpenStreamApple

private func stremioSource(
    url: String = "https://addon.example/config/manifest.json",
    enabled: Bool = true,
    resources: [String] = ["stream", "subtitles"]
) -> AppleSource {
    AppleSource(
        kind: .stremio,
        name: "Example",
        url: URL(string: url)!,
        isEnabled: enabled,
        manifestID: "example.addon",
        resources: resources
    )
}

@Test func stremioPlaybackClientEncodesEachPathSegmentAndParsesHTTPStreams() async throws {
    let client = AppleStremioPlaybackClient { request in
        #expect(request.url?.absoluteString ==
            "https://addon.example/config/stream/series/tt123%3A1%2F%2E%2E%2F%C3%A9.json")
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
        #expect(request.value(forHTTPHeaderField: "User-Agent") == "OpenStream/1.0 Apple")
        let data = Data(#"{"streams":[{"title":"1080p\nHEVC","url":"https://media.example/movie.mp4?token=one","behaviorHints":{"filename":"Film\t2026.mp4"}}]}"#.utf8)
        return (
            data,
            HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        )
    }

    let result = try await client.streams(
        source: stremioSource(),
        type: "series",
        mediaID: "tt123:1/../é"
    )

    #expect(result.httpCandidates.count == 1)
    #expect(result.httpCandidates[0].title == "1080p HEVC")
    #expect(result.httpCandidates[0].filename == "Film 2026.mp4")
    #expect(result.httpCandidates[0].requiresRuntimeInspection)
    #expect(result.unsupported.isEmpty)
}

@Test func stremioStreamParsingSeparatesDirectHTTPFromUnsupportedLocators() throws {
    let data = Data(#"""
    {
      "streams": [
        {"title":"HTTPS","url":"https://media.example/film.mkv"},
        {"title":"Duplicate","url":"https://media.example/film.mkv"},
        {"name":"HTTP","url":"http://192.168.1.20/live.m3u8"},
        {"title":"Torrent","infoHash":"0123456789abcdef0123456789abcdef01234567","fileIdx":2},
        {"title":"Base32","infoHash":"ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"},
        {"title":"YouTube","ytId":"dQw4w9WgXcQ"},
        {"title":"Related","externalUrl":"stremio:///detail/movie/tt123"},
        {"title":"Unsafe","url":"file:///private/movie.mp4"},
        {"title":"Credentials","url":"https://user:pass@media.example/movie.mp4"},
        {"title":"Invalid hash","infoHash":"not-a-hash"},
        {"title":"Missing"},
        42
      ]
    }
    """#.utf8)

    let result = try AppleStremioPlaybackClient.parseStreams(data)

    #expect(result.httpCandidates.map(\.title) == ["HTTPS", "HTTP"])
    #expect(result.httpCandidates.map(\.sourceURL.scheme) == ["https", "http"])
    #expect(result.unsupported.count == 8)
    #expect(result.unsupported[0].reason == .torrent(
        infoHash: "0123456789abcdef0123456789abcdef01234567",
        fileIndex: 2
    ))
    #expect(result.unsupported[1].reason == .torrent(
        infoHash: "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567",
        fileIndex: nil
    ))
    #expect(result.unsupported[2].reason == .youtube(videoID: "dQw4w9WgXcQ"))
    #expect(result.unsupported[3].reason == .externalLink(URL(string: "stremio:///detail/movie/tt123")!))
    #expect(result.unsupported[4].reason == .invalidHTTPURL)
    #expect(result.unsupported[5].reason == .invalidHTTPURL)
    #expect(result.unsupported[6].reason == .invalidLocator)
    #expect(result.unsupported[7].reason == .missingLocator)
}

@Test func malformedStreamMembersDoNotDiscardLaterQualityAlternatives() throws {
    var values: [[String: Any]] = []
    for index in 0 ..< 75 {
        values.append([
            "title": index == 70 ? "2160p DV P8 HEVC" : "1080p H.264 \(index)",
            "url": "https://media.example/\(index).mp4",
        ])
    }
    let payload: [String: Any] = ["streams": ["bad", NSNull()] + values]
    let data = try JSONSerialization.data(withJSONObject: payload)

    let result = try AppleStremioPlaybackClient.parseStreams(data)

    #expect(result.httpCandidates.count == 75)
    #expect(result.httpCandidates.contains { $0.title == "2160p DV P8 HEVC" })
}

@Test func streamLabelsBoundAdversarialCombiningScalars() throws {
    let combiningTitle = "A" + String(repeating: "\u{0301}", count: 10_000)
    let combiningFilename = "F" + String(repeating: "\u{0301}", count: 10_000)
    let payload: [String: Any] = [
        "streams": [[
            "title": combiningTitle,
            "url": "https://media.example/movie.mp4",
            "behaviorHints": ["filename": combiningFilename],
        ]],
    ]

    let result = try AppleStremioPlaybackClient.parseStreams(
        JSONSerialization.data(withJSONObject: payload)
    )

    let stream = try #require(result.httpCandidates.first)
    #expect(stream.title.unicodeScalars.count == 120)
    #expect(stream.title.utf8.count <= 120 * 4)
    #expect(stream.filename?.unicodeScalars.count == 240)
    #expect(stream.filename?.utf8.count ?? 0 <= 240 * 4)
}

@Test func stremioSubtitleClientEncodesEpisodeIdentityAndKeepsSafeTracks() async throws {
    let client = AppleStremioPlaybackClient { request in
        #expect(request.url?.absoluteString ==
            "https://addon.example/config/subtitles/series/tt765%3A2%3A6.json")
        let data = Data(#"""
        {
          "subtitles": [
            {"id":"english-1","url":"https://subs.example/film.srt?token=1","lang":"eng"},
            {"id":"japanese-1","url":"https://subs.example/path with spaces/film.ass#track","lang":"jpn"},
            {"id":"french-1","url":"http://subs.example/film.ttml","lang":"fra"},
            {"id":"webvtt","url":"https://subs.example/film.vtt","lang":""},
            {"id":"duplicate","url":"https://subs.example/film.vtt","lang":"spa"},
            {"id":"unsafe","url":"file:///private/film.srt","lang":"eng"},
            3
          ]
        }
        """#.utf8)
        return (
            data,
            HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        )
    }

    let tracks = try await client.subtitles(
        source: stremioSource(),
        type: "series",
        mediaID: "tt765:2:6"
    )

    #expect(tracks.map(\.id) == ["english-1", "japanese-1", "french-1", "webvtt"])
    #expect(tracks.map(\.language) == ["eng", "jpn", "fra", "und"])
    #expect(tracks.map(\.mimeType) == [
        "application/x-subrip", "text/x-ssa", "application/ttml+xml", "text/vtt",
    ])
    #expect(tracks[1].url.absoluteString.contains("path%20with%20spaces"))
}

@Test func stremioPlaybackClientRetriesTransientStatusesWithBoundedBackoff() async throws {
    let recorder = PlaybackRequestRecorder()
    let client = AppleStremioPlaybackClient(
        loader: { request in
            let attempt = await recorder.recordRequest()
            let status = attempt == 1 ? 503 : (attempt == 2 ? 429 : 200)
            let data = Data(#"{"streams":[]}"#.utf8)
            return (
                data,
                HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            )
        },
        sleeper: { duration in await recorder.recordSleep(duration) }
    )

    let result = try await client.streams(source: stremioSource(), type: "movie", mediaID: "tt1")

    #expect(result == .empty)
    #expect(await recorder.requestCount == 3)
    #expect(await recorder.sleeps == [.milliseconds(250), .milliseconds(500)])
}

@Test func stremioPlaybackClientRetriesTransportErrorsButNotOrdinaryHTTPFailures() async throws {
    let transportRecorder = PlaybackRequestRecorder()
    let transportClient = AppleStremioPlaybackClient(
        loader: { request in
            let attempt = await transportRecorder.recordRequest()
            if attempt < 4 { throw URLError(.timedOut) }
            return (
                Data(#"{"streams":[]}"#.utf8),
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            )
        },
        sleeper: { duration in await transportRecorder.recordSleep(duration) }
    )
    _ = try await transportClient.streams(source: stremioSource(), type: "movie", mediaID: "tt1")
    #expect(await transportRecorder.requestCount == 4)
    #expect(await transportRecorder.sleeps == [.milliseconds(250), .milliseconds(500), .seconds(1)])

    let ordinaryRecorder = PlaybackRequestRecorder()
    let ordinaryClient = AppleStremioPlaybackClient { request in
        _ = await ordinaryRecorder.recordRequest()
        return (
            Data(),
            HTTPURLResponse(url: request.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!
        )
    }
    do {
        _ = try await ordinaryClient.streams(source: stremioSource(), type: "movie", mediaID: "tt1")
        Issue.record("Expected a non-retryable HTTP failure")
    } catch let error as AppleStremioPlaybackError {
        #expect(error == .requestFailed(404))
    }
    #expect(await ordinaryRecorder.requestCount == 1)
}

@Test func stremioPlaybackClientRejectsOversizedAndInsecureResponses() async throws {
    let oversized = AppleStremioPlaybackClient { request in
        let headers = ["Content-Length": "\(AppleStremioPlaybackClient.maximumResponseBytes + 1)"]
        return (
            Data(#"{"streams":[]}"#.utf8),
            HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: headers)!
        )
    }
    do {
        _ = try await oversized.streams(source: stremioSource(), type: "movie", mediaID: "tt1")
        Issue.record("Expected an oversized response failure")
    } catch let error as AppleStremioPlaybackError {
        #expect(error == .responseTooLarge)
    }

    let insecure = AppleStremioPlaybackClient { request in
        return (
            Data(#"{"streams":[]}"#.utf8),
            HTTPURLResponse(
                url: request.url!,
                statusCode: 302,
                httpVersion: nil,
                headerFields: ["Location": "http://addon.example/stream/movie/tt1.json"]
            )!
        )
    }
    do {
        _ = try await insecure.streams(source: stremioSource(), type: "movie", mediaID: "tt1")
        Issue.record("Expected an insecure redirect failure")
    } catch let error as AppleStremioPlaybackError {
        #expect(error == .insecureRedirect)
    }
}

@Test func stremioPlaybackClientSkipsNetworkForUnavailableResources() async throws {
    let client = AppleStremioPlaybackClient { _ in
        Issue.record("No request should be made")
        throw URLError(.unknown)
    }

    let disabled = try await client.streams(
        source: stremioSource(enabled: false),
        type: "movie",
        mediaID: "tt1"
    )
    let noStreams = try await client.streams(
        source: stremioSource(resources: ["subtitles"]),
        type: "movie",
        mediaID: "tt1"
    )
    let noSubtitles = try await client.subtitles(
        source: stremioSource(resources: ["stream"]),
        type: "movie",
        mediaID: "tt1"
    )

    #expect(disabled == .empty)
    #expect(noStreams == .empty)
    #expect(noSubtitles.isEmpty)
}

@Test func stremioPlaybackClientRejectsInvalidSourceIdentityAndPayload() async throws {
    let client = AppleStremioPlaybackClient { request in
        (
            Data("not json".utf8),
            HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        )
    }

    do {
        _ = try await client.streams(source: stremioSource(), type: "movie", mediaID: "   ")
        Issue.record("Expected an invalid media identity")
    } catch let error as AppleStremioPlaybackError {
        #expect(error == .invalidMediaIdentity)
    }

    do {
        _ = try await client.streams(source: stremioSource(), type: "movie", mediaID: "tt1")
        Issue.record("Expected invalid JSON to fail")
    } catch let error as AppleStremioPlaybackError {
        #expect(error == .invalidPayload)
    }

    do {
        _ = try await client.streams(
            source: stremioSource(url: "http://addon.example/manifest.json"),
            type: "movie",
            mediaID: "tt1"
        )
        Issue.record("Expected an invalid source")
    } catch let error as AppleStremioPlaybackError {
        #expect(error == .invalidSource)
    }
}

@Test func stremioPlaybackResolverInspectsCandidatesUntilOnePrepares() async throws {
    let recorder = PlaybackResolutionRecorder()
    let client = AppleStremioPlaybackClient { request in
        let data = Data(#"""
        {"streams":[
          {"title":"First","url":"https://media.example/first.mp4"},
          {"title":"Second","url":"https://media.example/second.mp4"}
        ]}
        """#.utf8)
        return (
            data,
            HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        )
    }
    let inspection = playableInspection()
    let resolver = AppleStremioPlaybackResolver(
        client: client,
        inspector: { url in
            await recorder.recordInspection(url)
            return inspection
        },
        preparer: { url, decision, receivedInspection, gatewayRequest in
            await recorder.recordPreparation(url, decision: decision, inspection: receivedInspection)
            #expect(gatewayRequest == nil)
            if url.lastPathComponent == "first.mp4" {
                throw ApplePlaybackPreparationError.unavailable(["Rejected"])
            }
            return ApplePreparedPlayback(route: .direct(url), url: url)
        }
    )
    let item = AppleCatalogItem(mediaID: "tt123", type: "movie", name: "Film")

    let result = try await resolver.resolve(source: stremioSource(), item: item)

    #expect(result.stream.title == "Second")
    #expect(result.preparedPlayback.url == URL(string: "https://media.example/second.mp4"))
    #expect(await recorder.inspected.map(\.lastPathComponent) == ["first.mp4", "second.mp4"])
    #expect(await recorder.prepared.map(\.lastPathComponent) == ["first.mp4", "second.mp4"])
    #expect(await recorder.decisions.allSatisfy { $0.support == .supported })
}

@Test func stremioPlaybackResolverUsesPlaybackAddonForCatalogOnlyTitles() async throws {
    let catalogSource = AppleSource(
        kind: .stremio,
        name: "Catalogs",
        url: URL(string: "https://catalog.example/manifest.json")!,
        resources: ["catalog"]
    )
    let playbackSource = stremioSource(url: "https://streams.example/manifest.json")
    let client = AppleStremioPlaybackClient { request in
        #expect(request.url?.host == "streams.example")
        return (
            Data(#"{"streams":[{"title":"Direct","url":"https://media.example/film.mp4"}]}"#.utf8),
            HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        )
    }
    let resolver = AppleStremioPlaybackResolver(
        client: client,
        inspector: { _ in playableInspection() },
        preparer: { url, _, _, _ in ApplePreparedPlayback(route: .direct(url), url: url) }
    )

    let result = try await resolver.resolve(
        sources: [catalogSource, playbackSource],
        preferredSourceID: catalogSource.id,
        item: AppleCatalogItem(mediaID: "tt123", type: "movie", name: "Film")
    )

    #expect(result.stream.title == "Direct")
    #expect(result.preparedPlayback.url == URL(string: "https://media.example/film.mp4"))
}

@Test func stremioPlaybackResolverReportsUnsupportedOnlyResultsWithoutInspecting() async throws {
    let recorder = PlaybackResolutionRecorder()
    let client = AppleStremioPlaybackClient { request in
        let data = Data(#"{"streams":[{"title":"Torrent","infoHash":"0123456789abcdef0123456789abcdef01234567"}]}"#.utf8)
        return (
            data,
            HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        )
    }
    let resolver = AppleStremioPlaybackResolver(
        client: client,
        inspector: { url in
            await recorder.recordInspection(url)
            return playableInspection()
        },
        preparer: { url, _, _, _ in ApplePreparedPlayback(route: .direct(url), url: url) }
    )

    do {
        _ = try await resolver.resolve(
            source: stremioSource(),
            item: AppleCatalogItem(mediaID: "tt123", type: "movie", name: "Film")
        )
        Issue.record("Expected the unsupported locator to remain non-playable")
    } catch let error as AppleStremioPlaybackResolutionError {
        #expect(error == .unsupportedOnly(.torrent(
            infoHash: "0123456789abcdef0123456789abcdef01234567",
            fileIndex: nil
        )))
        #expect(error.localizedDescription == "Torrent resolver required.")
    }
    #expect(await recorder.inspected.isEmpty)
}

@Test func stremioPlaybackResolverPassesRejectedRemoteStreamToConfiguredGateway() async throws {
    let sourceURL = URL(string: "https://media.example/film.mkv")!
    let config = try AppleTranscodeGatewayConfig(
        baseURL: "https://gateway.example",
        sessionToken: String(repeating: "g", count: 32)
    )
    let client = AppleStremioPlaybackClient { request in
        let data = Data(#"{"streams":[{"title":"MKV","url":"https://media.example/film.mkv"}]}"#.utf8)
        return (
            data,
            HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        )
    }
    let resolver = AppleStremioPlaybackResolver(
        client: client,
        inspector: { _ in throw URLError(.cannotDecodeContentData) },
        preparer: { url, decision, inspection, request in
            #expect(url == sourceURL)
            #expect(decision.support == .unsupported)
            #expect(!inspection.playable)
            #expect(request == AppleGatewayTranscodeRequest(
                config: config,
                source: .remoteURL(sourceURL),
                maximumWidth: 3_840,
                maximumHeight: 2_160
            ))
            let scopedURL = URL(string: "https://gateway.example/api/transcode/media?transcodeId=gggggggggggggggggggggggggggggggg")!
            return ApplePreparedPlayback(route: .gatewayTranscode(url), url: scopedURL)
        }
    )

    let result = try await resolver.resolve(
        source: stremioSource(),
        item: AppleCatalogItem(mediaID: "tt123", type: "movie", name: "Film"),
        gatewayConfig: config
    )

    #expect(result.preparedPlayback.route == .gatewayTranscode(sourceURL))
    #expect(result.preparedPlayback.requestHeaders.isEmpty)
}

@Test func stremioPlaybackDecisionUsesRuntimeEvidenceRatherThanCodecLabels() {
    let playable = AppleStremioPlaybackResolver.decision(for: playableInspection())
    let rejected = AppleStremioPlaybackResolver.decision(for: AppleAssetInspection(
        formats: [OpenStreamFormat(
            dynamicRange: .sdr,
            codec: "avc1",
            width: 1920,
            height: 1080,
            frameRate: 24
        )],
        playable: false,
        readable: true,
        exportable: false,
        protectedContent: false
    ))

    #expect(playable.support == .supported)
    #expect(rejected.support == .unsupported)
}

private func playableInspection() -> AppleAssetInspection {
    AppleAssetInspection(
        formats: [],
        playable: true,
        readable: true,
        exportable: false,
        protectedContent: false
    )
}

private actor PlaybackRequestRecorder {
    private(set) var requestCount = 0
    private(set) var sleeps: [Duration] = []

    func recordRequest() -> Int {
        requestCount += 1
        return requestCount
    }

    func recordSleep(_ duration: Duration) {
        sleeps.append(duration)
    }
}

private actor PlaybackResolutionRecorder {
    private(set) var inspected: [URL] = []
    private(set) var prepared: [URL] = []
    private(set) var decisions: [OpenStreamPlaybackDecision] = []

    func recordInspection(_ url: URL) {
        inspected.append(url)
    }

    func recordPreparation(
        _ url: URL,
        decision: OpenStreamPlaybackDecision,
        inspection: AppleAssetInspection
    ) {
        prepared.append(url)
        decisions.append(decision)
        #expect(inspection == playableInspection())
    }
}
