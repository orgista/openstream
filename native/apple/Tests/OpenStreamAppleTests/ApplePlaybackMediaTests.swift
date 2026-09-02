import Foundation
import Testing
@testable import OpenStreamApple

@Test func playbackIdentityIsStableAndNeverContainsTheSourceValue() throws {
    let mediaID = "file:///Users/example/Movies/private-title.mp4"
    let first = try #require(ApplePlaybackIdentity.storageKey(for: mediaID))
    let second = try #require(ApplePlaybackIdentity.storageKey(for: mediaID))

    #expect(first == second)
    #expect(ApplePlaybackIdentity.isStorageKey(first))
    #expect(!first.contains("private-title"))
    #expect(first.count == 71)
}

@MainActor
@Test func playbackStoreUsesOpaqueKeysAndThirtySecondCompletionThreshold() throws {
    let suiteName = "openstream-playback-tests-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let store = ApplePlaybackStore(defaults: defaults)
    let rawMediaID = "/Users/example/Movies/private-title.mp4"

    store.save(mediaID: rawMediaID, position: 569, duration: 600)
    #expect(store.progress(for: rawMediaID)?.resumePosition == 569)

    let data = try #require(defaults.data(forKey: "openstream.playback.progress.v1"))
    let persisted = try JSONDecoder().decode([String: ApplePlaybackProgress].self, from: data)
    let key = try #require(persisted.keys.first)
    #expect(ApplePlaybackIdentity.isStorageKey(key))
    #expect(!key.contains("private-title"))

    store.save(mediaID: rawMediaID, position: 570, duration: 600)
    #expect(store.progress(for: rawMediaID) == nil)
}

@Test func routePolicyRequiresRuntimeSuitabilityAndNeverExportsMatroska() {
    let localMovie = URL(fileURLWithPath: "/tmp/movie.mp4")
    let localMKV = URL(fileURLWithPath: "/tmp/movie.mkv")
    let remoteMKV = URL(string: "https://media.example/movie.mkv")!
    let unsupported = OpenStreamPlaybackDecision(support: .unsupported, reasons: ["runtime rejected asset"])

    #expect(ApplePlaybackRoutePolicy.route(
        sourceURL: localMovie,
        decision: unsupported,
        suitability: .init(
            isPlayable: false,
            isReadable: true,
            isExportable: true,
            isProtected: false
        )
    ) == .nativeOfflineExport(localMovie))

    #expect(ApplePlaybackRoutePolicy.route(
        sourceURL: localMKV,
        decision: unsupported,
        suitability: .init(
            isPlayable: false,
            isReadable: true,
            isExportable: true,
            isProtected: false
        )
    ) == .requiresExternalDemux(localMKV))

    #expect(ApplePlaybackRoutePolicy.route(
        sourceURL: remoteMKV,
        decision: unsupported,
        gatewayConfigured: true
    ) == .gatewayTranscode(remoteMKV))
}

@Test func protectedNonplayableAndUnreadableAssetsNeverUseNativeExport() {
    let localMovie = URL(fileURLWithPath: "/tmp/movie.mp4")
    let remoteMovie = URL(string: "https://media.example/movie.mp4")!
    let unsupported = OpenStreamPlaybackDecision(support: .unsupported, reasons: ["decoder unavailable"])

    #expect(ApplePlaybackRoutePolicy.route(
        sourceURL: localMovie,
        decision: unsupported,
        suitability: .init(
            isPlayable: false,
            isReadable: true,
            isExportable: true,
            isProtected: true
        ),
        gatewayConfigured: true
    ) == .unavailable(["decoder unavailable"]))

    #expect(ApplePlaybackRoutePolicy.route(
        sourceURL: remoteMovie,
        decision: unsupported,
        suitability: .init(
            isPlayable: false,
            isReadable: false,
            isExportable: false,
            isProtected: false
        )
    ) == .requiresExternalDemux(remoteMovie))

    #expect(ApplePlaybackRoutePolicy.route(
        sourceURL: localMovie,
        decision: unsupported,
        suitability: .init(
            isPlayable: false,
            isReadable: true,
            isExportable: false,
            isProtected: false
        )
    ) == .unavailable(["decoder unavailable"]))
}

@Test func negotiatorNeedsConcreteAssetAndTrackEvidence() {
    let report = OpenStreamCapabilityReport(
        platform: "tvOS",
        hdrEligible: true,
        dynamicRange: [.sdr: .supported],
        projections: [.flat: .supported]
    )
    let format = OpenStreamFormat(
        dynamicRange: .sdr,
        codec: "hvc1",
        width: 1920,
        height: 1080,
        frameRate: 24
    )

    #expect(OpenStreamCapabilityNegotiator.evaluate(format, against: report).support == .runtimeCheck)

    let evidence = OpenStreamRuntimePlaybackEvidence(
        assetIsPlayable: true,
        assetIsReadable: true,
        assetIsExportable: true,
        hasProtectedContent: false,
        enabledVideoTracksArePlayableAndDecodable: true,
        enabledAudioTracksArePlayableAndDecodable: true
    )
    #expect(OpenStreamCapabilityNegotiator.evaluate(
        format,
        against: report,
        runtime: evidence
    ).support == .supported)
}

@Test func playbackPreparerExecutesGatewayRouteAndReturnsItsPlaybackRequest() async throws {
    let sourceURL = URL(fileURLWithPath: "/tmp/movie.mkv")
    let config = try AppleTranscodeGatewayConfig(
        baseURL: "https://gateway.example",
        sessionToken: String(repeating: "a", count: 32)
    )
    let client = AppleTranscodeGatewayClient { request in
        guard let url = request.url else { throw URLError(.badURL) }
        let body: Data
        switch url.path {
        case "/api/transcode/capabilities":
            body = Data(#"{"available":true,"version":"1","hardwareAccelerated":true}"#.utf8)
        case "/api/transcode/smb-sessions":
            body = Data(#"{"transcodeUrl":"/gateway/transcode/media?transcodeId=cccccccccccccccccccccccccccccccc"}"#.utf8)
        default:
            throw URLError(.unsupportedURL)
        }
        guard let response = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        ) else {
            throw URLError(.badServerResponse)
        }
        return (body, response)
    }
    let preparer = ApplePlaybackPreparer(gatewayClient: client)

    let prepared = try await preparer.prepare(
        sourceURL: sourceURL,
        decision: .init(support: .unsupported, reasons: ["container"]),
        gatewayRequest: .init(
            config: config,
            smbURI: "smb://nas/media/movie.mkv",
            maximumWidth: 3840,
            maximumHeight: 2160
        )
    )

    #expect(prepared.route == .gatewayTranscode(sourceURL))
    #expect(prepared.url.absoluteString == "https://gateway.example/api/transcode/media?transcodeId=cccccccccccccccccccccccccccccccc")
    #expect(prepared.requestHeaders.isEmpty)
}

@MainActor
@Test func preparedPlaybackIsDirectlyConsumableByThePlayerSession() throws {
    let suiteName = "openstream-prepared-player-tests-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let url = URL(fileURLWithPath: "/tmp/prepared-movie.mp4")
    let prepared = ApplePreparedPlayback(route: .direct(url), url: url)
    let session = ApplePlayerSession(
        preparedPlayback: prepared,
        progressStore: ApplePlaybackStore(defaults: defaults)
    )
    defer { session.stop(saveProgress: false) }

    #expect(prepared.requestHeaders.isEmpty)
    #expect(session.player.currentItem === session.playerItem)
    #expect(ApplePlaybackIdentity.isStorageKey(session.mediaIdentity))
}
