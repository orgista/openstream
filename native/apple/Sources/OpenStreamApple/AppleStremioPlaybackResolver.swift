import Foundation

public struct AppleResolvedStremioPlayback: Equatable, Sendable {
    public let stream: AppleStremioHTTPPlaybackCandidate
    public let preparedPlayback: ApplePreparedPlayback

    public init(
        stream: AppleStremioHTTPPlaybackCandidate,
        preparedPlayback: ApplePreparedPlayback
    ) {
        self.stream = stream
        self.preparedPlayback = preparedPlayback
    }
}

public enum AppleStremioPlaybackResolutionError: Swift.Error, Equatable, LocalizedError, Sendable {
    case noStreams
    case unsupportedOnly(AppleStremioUnsupportedReason)
    case externalDemuxRequired
    case gatewayUnavailable
    case noCompatibleHTTPStream

    public var errorDescription: String? {
        switch self {
        case .noStreams:
            "No streams available."
        case .unsupportedOnly(let reason):
            switch reason {
            case .torrent:
                "Torrent resolver required."
            case .externalLink:
                "External link only."
            case .youtube:
                "YouTube link only."
            case .invalidHTTPURL, .invalidLocator, .missingLocator:
                "No playable stream."
            }
        case .externalDemuxRequired:
            "External demuxer required."
        case .gatewayUnavailable:
            "Gateway unavailable."
        case .noCompatibleHTTPStream:
            "No compatible stream."
        }
    }
}

/// Coordinates the protocol client with AVAsset runtime inspection and the
/// existing playback route executor. Provider ordering is preserved: each
/// HTTP candidate is tried until one produces a real prepared playback URL.
public struct AppleStremioPlaybackResolver: Sendable {
    public typealias Inspector = @Sendable (URL) async throws -> AppleAssetInspection
    public typealias Preparer = @Sendable (
        URL,
        OpenStreamPlaybackDecision,
        AppleAssetInspection,
        AppleGatewayTranscodeRequest?
    ) async throws -> ApplePreparedPlayback

    private let client: AppleStremioPlaybackClient
    private let inspector: Inspector
    private let preparer: Preparer

    public init(
        client: AppleStremioPlaybackClient = AppleStremioPlaybackClient(),
        inspector: @escaping Inspector = { try await AppleAssetInspector.inspect(url: $0) },
        playbackPreparer: ApplePlaybackPreparer = ApplePlaybackPreparer()
    ) {
        self.client = client
        self.inspector = inspector
        preparer = { sourceURL, decision, inspection, gatewayRequest in
            try await playbackPreparer.prepare(
                sourceURL: sourceURL,
                decision: decision,
                inspectedAsset: inspection,
                gatewayRequest: gatewayRequest
            )
        }
    }

    public init(
        client: AppleStremioPlaybackClient,
        inspector: @escaping Inspector,
        preparer: @escaping Preparer
    ) {
        self.client = client
        self.inspector = inspector
        self.preparer = preparer
    }

    public func resolve(
        source: AppleSource,
        item: AppleCatalogItem,
        gatewayConfig: AppleTranscodeGatewayConfig? = nil
    ) async throws -> AppleResolvedStremioPlayback {
        let selection = try await client.streams(
            source: source,
            type: item.type,
            mediaID: item.mediaID
        )
        guard !selection.httpCandidates.isEmpty || !selection.unsupported.isEmpty else {
            throw AppleStremioPlaybackResolutionError.noStreams
        }

        var needsExternalDemux = false
        var gatewayFailed = false
        for stream in selection.httpCandidates {
            try Task.checkCancellation()
            do {
                let inspection: AppleAssetInspection
                do {
                    inspection = try await inspector(stream.sourceURL)
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    guard gatewayConfig != nil else { continue }
                    inspection = Self.rejectedInspection
                }
                try Task.checkCancellation()
                let gatewayRequest: AppleGatewayTranscodeRequest? = if !inspection.suitability.supportsDirectPlayback,
                                                                       let gatewayConfig {
                    AppleGatewayTranscodeRequest(
                        config: gatewayConfig,
                        source: .remoteURL(stream.sourceURL),
                        maximumWidth: 3_840,
                        maximumHeight: 2_160
                    )
                } else {
                    nil
                }
                let prepared = try await preparer(
                    stream.sourceURL,
                    Self.decision(for: inspection),
                    inspection,
                    gatewayRequest
                )
                return AppleResolvedStremioPlayback(stream: stream, preparedPlayback: prepared)
            } catch is CancellationError {
                throw CancellationError()
            } catch ApplePlaybackPreparationError.externalDemuxRequired {
                needsExternalDemux = true
            } catch {
                if gatewayConfig != nil { gatewayFailed = true }
                continue
            }
        }

        if gatewayFailed {
            throw AppleStremioPlaybackResolutionError.gatewayUnavailable
        }
        if needsExternalDemux {
            throw AppleStremioPlaybackResolutionError.externalDemuxRequired
        }
        if selection.httpCandidates.isEmpty, let unsupported = selection.unsupported.first {
            throw AppleStremioPlaybackResolutionError.unsupportedOnly(unsupported.reason)
        }
        throw AppleStremioPlaybackResolutionError.noCompatibleHTTPStream
    }

    /// Catalog and playback resources commonly come from different add-ons.
    /// Try every enabled stream provider, preferring the catalog provider only
    /// when it can also serve streams.
    public func resolve(
        sources: [AppleSource],
        preferredSourceID: AppleSource.ID? = nil,
        item: AppleCatalogItem,
        gatewayConfig: AppleTranscodeGatewayConfig? = nil
    ) async throws -> AppleResolvedStremioPlayback {
        let candidates = sources
            .filter { source in
                source.kind == .stremio
                    && source.isEnabled
                    && source.resources.contains { $0.caseInsensitiveCompare("stream") == .orderedSame }
            }
            .sorted { lhs, rhs in
                let lhsPreferred = lhs.id == preferredSourceID
                let rhsPreferred = rhs.id == preferredSourceID
                return lhsPreferred && !rhsPreferred
            }
        guard !candidates.isEmpty else { throw AppleStremioPlaybackResolutionError.noStreams }

        var bestError: AppleStremioPlaybackResolutionError = .noStreams
        for source in candidates {
            try Task.checkCancellation()
            do {
                return try await resolve(source: source, item: item, gatewayConfig: gatewayConfig)
            } catch is CancellationError {
                throw CancellationError()
            } catch let error as AppleStremioPlaybackResolutionError {
                if Self.priority(of: error) > Self.priority(of: bestError) { bestError = error }
            } catch {
                continue
            }
        }
        throw bestError
    }

    public static func decision(for inspection: AppleAssetInspection) -> OpenStreamPlaybackDecision {
        let evidence = inspection.runtimeEvidence
        guard evidence.supportsDirectPlayback else {
            let reason: String
            if evidence.hasProtectedContent && !evidence.assetIsPlayable {
                reason = "Protected media failed the system playback check."
            } else if !evidence.assetIsPlayable {
                reason = "The asset failed the system playback check."
            } else {
                reason = "An enabled track failed the system playback check."
            }
            return OpenStreamPlaybackDecision(support: .unsupported, reasons: [reason])
        }
        return OpenStreamPlaybackDecision(support: .supported, reasons: [])
    }

    private static let rejectedInspection = AppleAssetInspection(
        formats: [],
        playable: false,
        readable: false,
        exportable: false,
        protectedContent: false
    )

    private static func priority(of error: AppleStremioPlaybackResolutionError) -> Int {
        switch error {
        case .gatewayUnavailable: 5
        case .externalDemuxRequired: 4
        case .noCompatibleHTTPStream: 3
        case .unsupportedOnly: 2
        case .noStreams: 1
        }
    }
}
