import Foundation
import Testing
@testable import OpenStreamApple

@Test func dolbyVisionConfigurationParsesProfileAndFlags() {
    let data = Data([1, 0, 16, 0b101, 0])
    let configuration = DolbyVisionConfiguration(record: data)
    #expect(configuration?.profile == 8)
    #expect(configuration?.hasRPU == true)
    #expect(configuration?.hasEnhancementLayer == false)
    #expect(configuration?.hasBaseLayer == true)
    #expect(configuration?.baseLayerSignalCompatibilityID == 0)
    #expect(configuration?.profile(usingBaseTransferFunction: "SMPTE_ST_2084_PQ") == .profile81)
    #expect(configuration?.profile(usingBaseTransferFunction: "ITU_R_2100_HLG") == .profile84)
}

@Test func dolbyVisionConfigurationParsesNonZeroIndexDataSlices() {
    let source = Data([0xff, 0xee, 1, 0, 16, 0b101, 0x20])
    let record = source[2..<7]
    #expect(record.startIndex == 2)

    let configuration = DolbyVisionConfiguration(record: record)
    #expect(configuration?.profile == 8)
    #expect(configuration?.hasRPU == true)
    #expect(configuration?.hasBaseLayer == true)
    #expect(configuration?.baseLayerSignalCompatibilityID == 2)
    #expect(DolbyVisionConfiguration(record: source[3..<7]) == nil)
}

@Test func dolbyVisionProfile8UsesExplicitBaseLayerCompatibilityBeforeTransferFallback() {
    let profile81 = DolbyVisionConfiguration(record: Data([1, 0, 16, 0b101, 0x10]))
    let profile82 = DolbyVisionConfiguration(record: Data([1, 0, 16, 0b101, 0x20]))
    let profile84 = DolbyVisionConfiguration(record: Data([1, 0, 16, 0b101, 0x40]))

    #expect(profile81?.profile(usingBaseTransferFunction: "ITU_R_2100_HLG") == .profile81)
    #expect(profile82?.profile(usingBaseTransferFunction: "SMPTE_ST_2084_PQ") == .profile82)
    #expect(profile84?.profile(usingBaseTransferFunction: "SMPTE_ST_2084_PQ") == .profile84)
}

@Test func negotiatorNeverTreatsDolbyVisionEligibilityAsAProfileGuarantee() {
    let report = OpenStreamCapabilityReport(
        platform: "tvOS",
        hdrEligible: true,
        dynamicRange: [.sdr: .supported, .dolbyVision: .runtimeCheck],
        projections: [.flat: .supported]
    )
    let format = OpenStreamFormat(
        dynamicRange: .dolbyVision,
        dolbyVisionProfile: .profile81,
        codec: "dvh1",
        width: 3840,
        height: 2160,
        frameRate: 23.976
    )
    let decision = OpenStreamCapabilityNegotiator.evaluate(format, against: report)
    #expect(decision.support == .runtimeCheck)
    #expect(decision.reasons.contains { $0.contains("profile") })
}

@Test func unsupportedProjectionBlocksTheRoute() {
    let report = OpenStreamCapabilityReport(
        platform: "tvOS",
        hdrEligible: true,
        dynamicRange: [.hdr10: .runtimeCheck],
        projections: [.stereo180: .unsupported]
    )
    let format = OpenStreamFormat(
        dynamicRange: .hdr10,
        projection: .stereo180,
        codec: "hvc1",
        width: 7680,
        height: 7680,
        frameRate: 90
    )
    #expect(OpenStreamCapabilityNegotiator.evaluate(format, against: report).support == .unsupported)
}

@Test func unknownProjectionMetadataIsNotClassifiedAsFlat() {
    #expect(AppleAssetInspector.projection(kind: nil, stereo: false) == .flat)
    #expect(AppleAssetInspector.projection(kind: "future-projection", stereo: false) == .unknown)
    #expect(AppleAssetInspector.projection(kind: "future-projection", stereo: true) == .unknown)
}

@Test func negotiatorRejectsMalformedGeometryAndRequiresUnknownCodecChecks() {
    let report = OpenStreamCapabilityReport(
        platform: "tvOS",
        hdrEligible: true,
        dynamicRange: [.sdr: .supported],
        projections: [.flat: .supported]
    )

    for format in [
        OpenStreamFormat(dynamicRange: .sdr, codec: "hvc1", width: 0, height: 1080, frameRate: 24),
        OpenStreamFormat(dynamicRange: .sdr, codec: "hvc1", width: 1920, height: -1, frameRate: 24),
        OpenStreamFormat(dynamicRange: .sdr, codec: "hvc1", width: 100_000, height: 1080, frameRate: 24),
        OpenStreamFormat(dynamicRange: .sdr, codec: "hvc1", width: 1920, height: 1080, frameRate: .nan),
        OpenStreamFormat(dynamicRange: .sdr, codec: "hvc1", width: 1920, height: 1080, frameRate: .infinity),
        OpenStreamFormat(dynamicRange: .sdr, codec: "hvc1", width: 1920, height: 1080, frameRate: 0),
        OpenStreamFormat(dynamicRange: .sdr, codec: "", width: 1920, height: 1080, frameRate: 24),
    ] {
        #expect(OpenStreamCapabilityNegotiator.evaluate(format, against: report).support == .unsupported)
    }

    let unknownCodec = OpenStreamFormat(
        dynamicRange: .sdr,
        codec: "zzzz",
        width: 1920,
        height: 1080,
        frameRate: 24
    )
    let unknownDecision = OpenStreamCapabilityNegotiator.evaluate(unknownCodec, against: report)
    #expect(unknownDecision.support == .runtimeCheck)
    #expect(unknownDecision.reasons.contains { $0.lowercased().contains("codec") })

    let knownCodec = OpenStreamFormat(
        dynamicRange: .sdr,
        codec: "hvc1",
        width: 1920,
        height: 1080,
        frameRate: 24
    )
    #expect(OpenStreamCapabilityNegotiator.evaluate(knownCodec, against: report).support == .runtimeCheck)
}

@Test func appleOfflinePolicyChoosesTheBestDeviceCompatibleVariant() {
    let variants = [
        AppleOfflineVariant(
            url: URL(string: "https://example.test/4k.m3u8")!,
            width: 3840,
            height: 2160,
            bitrate: 18_000_000,
            codec: .hevc,
            dynamicRange: .dolbyVision,
            estimatedBytes: 9_000_000_000
        ),
        AppleOfflineVariant(
            url: URL(string: "https://example.test/1080.m3u8")!,
            width: 1920,
            height: 1080,
            bitrate: 7_000_000,
            codec: .hevc,
            dynamicRange: .hdr10,
            estimatedBytes: 3_000_000_000
        ),
        AppleOfflineVariant(
            url: URL(string: "https://example.test/720.m3u8")!,
            width: 1280,
            height: 720,
            bitrate: 3_000_000,
            codec: .avc,
            dynamicRange: .sdr,
            estimatedBytes: 1_000_000_000
        ),
    ]
    let device = AppleOfflineDeviceProfile(
        maximumWidth: 1920,
        maximumHeight: 1080,
        codecs: [.avc, .hevc],
        dynamicRanges: [.sdr, .hdr10],
        availableBytes: 5_000_000_000
    )

    #expect(AppleOfflineQualityPolicy.bestVariant(from: variants, for: device)?.height == 1080)
}

@Test func playbackProgressOnlyResumesMeaningfulUnfinishedPlayback() {
    #expect(ApplePlaybackProgress(position: 5, duration: 600).resumePosition == nil)
    #expect(ApplePlaybackProgress(position: 120, duration: 600).resumePosition == 120)
    #expect(ApplePlaybackProgress(position: 569, duration: 600).resumePosition == 569)
    #expect(ApplePlaybackProgress(position: 570, duration: 600).resumePosition == nil)
    #expect(ApplePlaybackProgress(position: 590, duration: 600).resumePosition == nil)
}

@Test func appleOfflineStoreCopiesListsAndRemovesLocalMedia() async throws {
    let root = FileManager.default.temporaryDirectory
        .appending(path: "openstream-offline-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let source = root.appending(path: "source.mp4")
    try Data([0, 1, 2, 3]).write(to: source)
    let store = AppleOfflineMediaStore(rootDirectory: root.appending(path: "library"))

    let record = try await store.makeAvailable(mediaID: "movie:1", sourceURL: source)
    #expect(FileManager.default.fileExists(atPath: record.localURL.path))
    #expect(await store.record(for: "movie:1")?.sourceExtension == "mp4")
    #expect(await store.allRecords().map(\.mediaID) == ["movie:1"])

    try await store.remove(mediaID: "movie:1")
    #expect(await store.record(for: "movie:1") == nil)
}
