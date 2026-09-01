import AVFoundation
import CoreMedia
import Foundation

public struct AppleAssetInspection: Sendable {
    public let formats: [OpenStreamFormat]
    public let playable: Bool
    public let protectedContent: Bool

    public init(formats: [OpenStreamFormat], playable: Bool, protectedContent: Bool) {
        self.formats = formats
        self.playable = playable
        self.protectedContent = protectedContent
    }
}

public enum AppleAssetInspector {
    public static func inspect(url: URL) async throws -> AppleAssetInspection {
        let asset = AVURLAsset(url: url)
        async let playable = asset.load(.isPlayable)
        async let protectedContent = asset.load(.hasProtectedContent)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        var formats: [OpenStreamFormat] = []

        for track in tracks {
            let descriptions = try await track.load(.formatDescriptions)
            let dimensions = try await track.load(.naturalSize)
            let frameRate = Double(try await track.load(.nominalFrameRate))
            let safeWidth = safeDimension(Double(dimensions.width))
            let safeHeight = safeDimension(Double(dimensions.height))
            let safeRate = safeFrameRate(frameRate)
            for description in descriptions {
                formats.append(inspect(
                    description: description,
                    width: safeWidth,
                    height: safeHeight,
                    frameRate: safeRate
                ))
            }
        }
        return try await AppleAssetInspection(formats: formats, playable: playable, protectedContent: protectedContent)
    }

    public static func safeDimension(_ value: Double) -> Int {
        guard value.isFinite, value > 0, value <= Double(Int.max) else { return 0 }
        guard value < Double(Int.max) else { return 0 }
        return Int(value)
    }

    public static func safeFrameRate(_ value: Double) -> Double {
        guard value.isFinite, value > 0 else { return 0.0 }
        return value
    }

    public static func inspect(
        description: CMFormatDescription,
        width: Int,
        height: Int,
        frameRate: Double
    ) -> OpenStreamFormat {
        let codec = fourCC(CMFormatDescriptionGetMediaSubType(description))
        let extensions = (CMFormatDescriptionGetExtensions(description) as NSDictionary?) ?? NSDictionary()
        let transfer = extensions[kCMFormatDescriptionExtension_TransferFunction] as? String
        let projectionKind = extensions[kCMFormatDescriptionExtension_ProjectionKind] as? String
        let hasLeftEye = (extensions[kCMFormatDescriptionExtension_HasLeftStereoEyeView] as? Bool) == true
        let hasRightEye = (extensions[kCMFormatDescriptionExtension_HasRightStereoEyeView] as? Bool) == true

        var dynamicRange: OpenStreamDynamicRange = .sdr
        var dolbyVisionProfile: OpenStreamDolbyVisionProfile?
        if codec == "dvh1" || codec == "dvhe" {
            dynamicRange = .dolbyVision
            dolbyVisionProfile = dolbyVisionConfiguration(in: extensions)?.profile(usingBaseTransferFunction: transfer) ?? .unknown
        } else if transfer == (kCMFormatDescriptionTransferFunction_SMPTE_ST_2084_PQ as String) {
            dynamicRange = .hdr10
        } else if transfer == (kCMFormatDescriptionTransferFunction_ITU_R_2100_HLG as String) {
            dynamicRange = .hlg
        }

        let projection = projection(
            kind: projectionKind,
            stereo: hasLeftEye && hasRightEye
        )
        let sanitizedWidth = max(0, width)
        let sanitizedHeight = max(0, height)
        let sanitizedFrameRate = (frameRate.isFinite && frameRate > 0) ? frameRate : 0.0
        return OpenStreamFormat(
            dynamicRange: dynamicRange,
            dolbyVisionProfile: dolbyVisionProfile,
            projection: projection,
            codec: codec,
            width: sanitizedWidth,
            height: sanitizedHeight,
            frameRate: sanitizedFrameRate
        )
    }

    private static func dolbyVisionConfiguration(in extensions: NSDictionary) -> DolbyVisionConfiguration? {
        guard let atoms = extensions[kCMFormatDescriptionExtension_SampleDescriptionExtensionAtoms] as? NSDictionary else { return nil }
        for key in ["dvcC", "dvvC"] {
            if let data = atoms[key] as? Data, let configuration = DolbyVisionConfiguration(record: data) {
                return configuration
            }
            if let records = atoms[key] as? [Data], let data = records.first, let configuration = DolbyVisionConfiguration(record: data) {
                return configuration
            }
        }
        return nil
    }

    static func projection(kind: String?, stereo: Bool) -> OpenStreamProjection {
        guard let kind else { return stereo ? .spatial : .flat }
        if kind == (kCMFormatDescriptionProjectionKind_HalfEquirectangular as String) {
            return stereo ? .stereo180 : .mono180
        }
        if kind == (kCMFormatDescriptionProjectionKind_Equirectangular as String) {
            return stereo ? .stereo360 : .mono360
        }
        if #available(iOS 26.0, macOS 26.0, tvOS 26.0, visionOS 26.0, *) {
            if kind == (kCMFormatDescriptionProjectionKind_AppleImmersiveVideo as String) { return .appleImmersive }
            if kind == (kCMFormatDescriptionProjectionKind_ParametricImmersive as String) { return .wideFOV }
        }
        return .unknown
    }

    private static func fourCC(_ value: FourCharCode) -> String {
        let bytes: [UInt8] = [
            UInt8((value >> 24) & 0xff),
            UInt8((value >> 16) & 0xff),
            UInt8((value >> 8) & 0xff),
            UInt8(value & 0xff),
        ]
        return String(bytes: bytes, encoding: .macOSRoman) ?? "????"
    }
}
