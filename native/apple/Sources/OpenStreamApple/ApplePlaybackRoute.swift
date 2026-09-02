import AVFoundation
import Foundation

public enum ApplePlaybackRoute: Equatable, Sendable {
    case direct(URL)
    case nativeOfflineExport(URL)
    case gatewayTranscode(URL)
    case requiresExternalDemux(URL)
    case unavailable([String])
}

public struct AppleAssetSuitability: Equatable, Sendable {
    public var isPlayable: Bool
    public var isReadable: Bool
    public var isExportable: Bool
    public var isProtected: Bool
    public var enabledVideoTracksArePlayableAndDecodable: Bool
    public var enabledAudioTracksArePlayableAndDecodable: Bool

    public init(
        isPlayable: Bool,
        isReadable: Bool,
        isExportable: Bool,
        isProtected: Bool,
        enabledVideoTracksArePlayableAndDecodable: Bool = true,
        enabledAudioTracksArePlayableAndDecodable: Bool = true
    ) {
        self.isPlayable = isPlayable
        self.isReadable = isReadable
        self.isExportable = isExportable
        self.isProtected = isProtected
        self.enabledVideoTracksArePlayableAndDecodable = enabledVideoTracksArePlayableAndDecodable
        self.enabledAudioTracksArePlayableAndDecodable = enabledAudioTracksArePlayableAndDecodable
    }

    public var supportsDirectPlayback: Bool {
        isPlayable
            && enabledVideoTracksArePlayableAndDecodable
            && enabledAudioTracksArePlayableAndDecodable
    }

    public var supportsNativeOfflineExport: Bool {
        isReadable
            && isExportable
            && !isProtected
            && enabledVideoTracksArePlayableAndDecodable
            && enabledAudioTracksArePlayableAndDecodable
    }
}

public enum ApplePlaybackRoutePolicy {
    public static func route(
        sourceURL: URL,
        decision: OpenStreamPlaybackDecision,
        suitability: AppleAssetSuitability? = nil,
        gatewayConfigured: Bool = false
    ) -> ApplePlaybackRoute {
        if let suitability, suitability.isProtected {
            return suitability.supportsDirectPlayback
                ? .direct(sourceURL)
                : .unavailable(unavailableReasons(decision, fallback: "Protected media is not playable on this device."))
        }
        if suitability?.supportsDirectPlayback == true { return .direct(sourceURL) }

        let requiresExternalDemux = isMatroska(sourceURL) || suitability?.isReadable == false
        if requiresExternalDemux {
            return gatewayConfigured ? .gatewayTranscode(sourceURL) : .requiresExternalDemux(sourceURL)
        }

        if let suitability {
            if sourceURL.isFileURL && suitability.supportsNativeOfflineExport {
                return .nativeOfflineExport(sourceURL)
            }
            if gatewayConfigured { return .gatewayTranscode(sourceURL) }
            return .unavailable(unavailableReasons(decision, fallback: "The asset failed the system playback checks."))
        }

        return switch decision.support {
        case .supported, .runtimeCheck:
            .direct(sourceURL)
        case .unsupported where gatewayConfigured:
            .gatewayTranscode(sourceURL)
        case .unsupported where isMatroska(sourceURL):
            .requiresExternalDemux(sourceURL)
        case .unsupported:
            .unavailable(unavailableReasons(decision, fallback: "The asset requires runtime inspection."))
        }
    }

    public static func inspectAndRoute(
        sourceURL: URL,
        decision: OpenStreamPlaybackDecision,
        gatewayConfigured: Bool = false
    ) async throws -> ApplePlaybackRoute {
        let inspection = try await AppleAssetInspector.inspect(url: sourceURL)
        return route(
            sourceURL: sourceURL,
            decision: decision,
            suitability: inspection.suitability,
            gatewayConfigured: gatewayConfigured
        )
    }

    private static func isMatroska(_ url: URL) -> Bool {
        let fileExtension = url.pathExtension.lowercased()
        return fileExtension == "mkv" || fileExtension == "matroska"
    }

    private static func unavailableReasons(
        _ decision: OpenStreamPlaybackDecision,
        fallback: String
    ) -> [String] {
        decision.reasons.isEmpty ? [fallback] : decision.reasons
    }
}

public enum AppleLocalTranscodeError: Swift.Error, LocalizedError, Sendable {
    case sourceMustBeLocal
    case protectedContent
    case assetNotReadable
    case assetNotExportable
    case enabledTrackNotDecodable
    case externalDemuxRequired
    case noCompatibleExporter
    case unsupportedOutput
    case exportFailed(String)

    public var errorDescription: String? {
        switch self {
        case .sourceMustBeLocal: "Local transcoding requires a file stored on this device."
        case .protectedContent: "Protected media cannot be converted into an offline copy."
        case .assetNotReadable: "The system media stack cannot read this file."
        case .assetNotExportable: "The system media stack cannot export this file."
        case .enabledTrackNotDecodable: "An enabled audio or video track cannot be decoded by the system media stack."
        case .externalDemuxRequired: "This container requires an external demuxer; native offline export was not attempted."
        case .noCompatibleExporter: "This file cannot be converted by the system media stack."
        case .unsupportedOutput: "No compatible local output format is available."
        case .exportFailed(let message): "Local conversion failed: \(message)"
        }
    }
}

/// Produces a cached compatible file only for local, unprotected assets that
/// AVFoundation has already proven readable and exportable. This is not a
/// general-purpose MKV demuxer or a live transcoder.
public actor AppleNativeMediaExporter {
    private let outputDirectory: URL
    private let fileManager: FileManager

    public init(
        outputDirectory: URL? = nil,
        fileManager: FileManager = .default
    ) {
        self.fileManager = fileManager
        self.outputDirectory = outputDirectory ?? fileManager.temporaryDirectory
            .appending(path: "OpenStreamTranscodes", directoryHint: .isDirectory)
    }

    public func compatibleURL(for sourceURL: URL) async throws -> URL {
        guard sourceURL.isFileURL else { throw AppleLocalTranscodeError.sourceMustBeLocal }
        let sourceExtension = sourceURL.pathExtension.lowercased()
        guard sourceExtension != "mkv", sourceExtension != "matroska" else {
            throw AppleLocalTranscodeError.externalDemuxRequired
        }

        let inspection = try await AppleAssetInspector.inspect(url: sourceURL)
        guard !inspection.protectedContent else { throw AppleLocalTranscodeError.protectedContent }
        guard inspection.readable else { throw AppleLocalTranscodeError.assetNotReadable }
        guard inspection.exportable else { throw AppleLocalTranscodeError.assetNotExportable }
        guard inspection.videoTracks.allSatisfy(\.supportsPlayback),
              inspection.audioTracks.allSatisfy(\.supportsPlayback) else {
            throw AppleLocalTranscodeError.enabledTrackNotDecodable
        }

        try fileManager.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

        let destination = outputDirectory
            .appending(path: ApplePlaybackIdentity.digest(for: sourceURL.standardizedFileURL.absoluteString))
            .appendingPathExtension("mp4")
        if fileManager.fileExists(atPath: destination.path) { return destination }

        let asset = AVURLAsset(url: sourceURL)
        guard let exporter = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality) else {
            throw AppleLocalTranscodeError.noCompatibleExporter
        }
        guard exporter.supportedFileTypes.contains(.mp4) else {
            throw AppleLocalTranscodeError.unsupportedOutput
        }

        do {
            try await exporter.export(to: destination, as: .mp4)
            return destination
        } catch {
            try? fileManager.removeItem(at: destination)
            throw AppleLocalTranscodeError.exportFailed(error.localizedDescription)
        }
    }

    public func removeCachedFiles() throws {
        guard fileManager.fileExists(atPath: outputDirectory.path) else { return }
        try fileManager.removeItem(at: outputDirectory)
    }

}

@available(*, deprecated, renamed: "AppleNativeMediaExporter")
public typealias AppleLocalTranscoder = AppleNativeMediaExporter
