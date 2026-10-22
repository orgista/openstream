import Testing
@testable import OpenStreamApple

struct ApplePlaybackDecisionTests {
    @Test func originalFirstEvenOnRemoteHighBitrate() {
        let descriptor = AppleStreamDescriptors(container: "mkv", videoCodec: "hevc", videoLevel: 5.2,
            dolbyVisionProfile: 7, audioCodec: "truehd", subtitleCodec: "pgs", bitrate: 60_000_000)
        let result = ApplePlaybackDecision.decide(descriptor, remote: true)
        #expect(result.video == .originalBytes)
        #expect(result.audio == .localDecode("truehd"))
        #expect(result.subtitle == .embedded)
        #expect(result.reasons.contains(.containerNotNative))
        #expect(result.reasons.contains(.videoLevelAboveHardware(5.2)))
        #expect(result.reasons.contains(.dolbyVisionProfileUnsupported(7)))
        #expect(result.reasons.contains(.bitrateAboveRouteLimit) == false)
    }
    @Test func matroskaOriginalKeepsNativeAudioAndEmbeddedSubtitles() {
        let decision = ApplePlaybackDecision.decide(.init(container: "mkv", videoCodec: "h264", audioCodec: "aac", subtitleCodec: "pgs"))
        #expect(decision.video == .originalBytes)
        #expect(decision.audio == .passthrough)
        #expect(decision.subtitle == .embedded)
        #expect(decision.reasons == [.containerNotNative])
        let dv = ApplePlaybackDecision.decide(.init(container: "mp4", videoCodec: "hevc", dolbyVisionProfile: 7))
        #expect(dv.video == .originalBytes)
        #expect(dv.reasons == [.dolbyVisionProfileUnsupported(7)])
    }

    @Test func localHighLevelIsSoftwareAndNativeAudioPassesThrough() {
        let decision = ApplePlaybackDecision.decide(.init(container: "mp4", videoCodec: "hevc", videoLevel: 5.2, audioCodec: "aac"))
        #expect(decision.video == .localSoftwareDecode)
        #expect(decision.audio == .passthrough)
    }
    @Test func conversionOnlyAfterFailureAndFallbackIsBounded() {
        let direct = AppleMediaServerPlaybackInfo.MediaSource(id: "original", supportsDirectPlay: true)
        let converted = AppleMediaServerPlaybackInfo.MediaSource(id: "converted", transcodingURLPath: "/stream.m3u8")
        #expect(AppleJellyfinPlaybackPolicy.select([converted, direct], failed: [])?.id == "original")
        #expect(AppleJellyfinPlaybackPolicy.route(for: converted, afterFailure: false) == .original)
        #expect(AppleJellyfinPlaybackPolicy.route(for: converted, afterFailure: true) == .conversion)
        #expect(AppleJellyfinPlaybackPolicy.conversionDecision(for: converted).video == .serverTranscode)
        #expect(ApplePlaybackFallbackPolicy.next(triedConversion: false, nextVersionAvailable: true) == .conversion)
        #expect(ApplePlaybackFallbackPolicy.next(triedConversion: true, nextVersionAvailable: true) == .nextVersion)
        #expect(ApplePlaybackFallbackPolicy.next(triedConversion: true, nextVersionAvailable: false) == .unavailable)
    }
    @Test func observedMismatchIsDiagnosticOnly() {
        let decision = ApplePlaybackDecision.decide(.init(container: "mp4", videoCodec: "h264", audioCodec: "aac"))
        #expect(decision.mismatch(observedSoftwareDecode: true))
        #expect(decision.video == .originalBytes)
    }
}

import Foundation

struct AppleJellyfinNegotiationTests {
    @Test func sourceDescriptorsDecodeAndAudioConversionCopiesVideo() throws {
        let data = Data(#"{"Id":"v1","Container":"mkv","RunTimeTicks":60000000000,"Bitrate":60000000,"SupportsTranscoding":true,"TranscodingUrl":"/Videos/item/master.m3u8?VideoCodec=h264","MediaStreams":[{"Type":"Video","Codec":"hevc","Level":153,"Height":2160,"VideoRangeType":"HDR10"},{"Type":"Audio","Codec":"truehd","Index":2,"Channels":8,"Profile":"Dolby Atmos"}]}"#.utf8)
        let source = try JSONDecoder().decode(AppleMediaServerPlaybackInfo.MediaSource.self, from: data)
        #expect(source.descriptors.videoLevel == 5.1)
        #expect(source.descriptors.duration == 6000)
        #expect(source.formatBadges.contains(.uhd))
        #expect(source.formatBadges.contains(.hdr10))
        #expect(source.formatBadges.contains(.surround71))
        #expect(AppleJellyfinPlaybackPolicy.isAudioOnlyMismatch(source))
        let decision = AppleJellyfinPlaybackPolicy.conversionDecision(for: source)
        #expect(decision.video == .originalBytes)
        #expect(decision.audio == .serverTranscode)
        let session = AppleMediaServerSession(kind: .jellyfin, baseURL: URL(string: "https://fixture.example/")!, accessToken: "fixture", userID: "viewer")
        let url = try AppleJellyfinPlaybackPolicy.conversionURL(source.transcodingURLPath!, session: session, audioStreamIndex: 2, audioOnly: true, videoCodec: source.descriptors.videoCodec)
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        #expect(query.contains(URLQueryItem(name: "AllowVideoStreamCopy", value: "true")))
        #expect(query.contains(URLQueryItem(name: "VideoCodec", value: "hevc")))
        #expect(query.contains(URLQueryItem(name: "VideoCodec", value: "h264")) == false)
        #expect(query.contains(URLQueryItem(name: "AllowAudioStreamCopy", value: "false")))
        #expect(query.contains(URLQueryItem(name: "AudioStreamIndex", value: "2")))
        #expect(throws: AppleMediaServerError.unsupported) {
            try AppleJellyfinPlaybackPolicy.conversionURL("https://other.example/stream", session: session)
        }
    }

    @Test func highestQualityDirectVersionWinsAndStickyChoiceWinsOverQuality() {
        let low = AppleMediaServerPlaybackInfo.MediaSource(id: "low", supportsDirectPlay: true, name: "1080p")
        let high = AppleMediaServerPlaybackInfo.MediaSource(id: "high", supportsDirectPlay: true, name: "2160p")
        #expect(AppleJellyfinPlaybackPolicy.select([low, high], failed: [])?.id == "high")
        #expect(AppleJellyfinPlaybackPolicy.select([low, high], failed: [], preferred: "low")?.id == "low")
        #expect(AppleJellyfinPlaybackPolicy.select([low, high], failed: ["high"])?.id == "low")
        #expect(AppleJellyfinPlaybackPolicy.select([low, high], failed: ["low", "high"]) == nil)
    }
}
