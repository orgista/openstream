import Foundation
import Synchronization

/// Asks one question about a live channel: does it carry CEA-608 captions the
/// manifest never declared?
///
/// It fetches the head of the playlist's first segment and hands the bytes to
/// `AppleCEA608Detector`. The answer is cached per channel, so a channel is
/// probed once per app run and never while the viewer is waiting — the probe
/// is started alongside playback, not in front of it.
///
/// A yes for an HLS media playlist is acted on at the channel's NEXT start
/// (`AppleLiveCaptionWrapPolicy`): the local proxy serves a one-variant master
/// that declares `INSTREAM-ID="CC1"` in front of the provider's playlist, and
/// AVFoundation's own caption pipeline does the rest. A channel already playing
/// when the answer lands is never reloaded for it.
public actor AppleLiveCaptionProbe {
    public static let shared = AppleLiveCaptionProbe()

    /// One segment's head is dozens of frames — far more than the detector's
    /// threshold — and small enough that a probe costs a fraction of a second.
    public static let maximumProbeBytes = 512 * 1024
    public static let requestTimeout: TimeInterval = 8

    public struct Result: Equatable, Sendable {
        public let carriesUndeclaredCaptions: Bool
        public let manifestAlreadyDeclares: Bool
        /// The URL answered with an HLS media playlist (segments, no
        /// variants) — the only shape a synthesized master can wrap. False for
        /// a raw transport stream and for a master.
        public var isMediaPlaylist: Bool = false

        /// Play this channel through a caption-declaring master next time.
        public var wrapsInCaptionMaster: Bool {
            AppleLiveCaptionWrapPolicy.shouldWrap(
                carriesEmbeddedCaptions: carriesUndeclaredCaptions,
                manifestDeclaresCaptions: manifestAlreadyDeclares,
                isMediaPlaylist: isMediaPlaylist)
        }
    }

    private var answers: [String: Result] = [:]
    /// The channels whose next start should be wrapped, readable without a
    /// hop: `startChannelNow` builds the request synchronously on the main
    /// actor and must not wait on this actor.
    private nonisolated let wrappedChannelIDs = Mutex<Set<String>>([])
    private var inFlight = Set<String>()
    private let session: URLSession

    public init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = Self.requestTimeout
            self.session = URLSession(configuration: configuration)
        }
    }

    public func cachedResult(channelID: String) -> Result? { answers[channelID] }

    /// True once a finished probe said this channel is an HLS media playlist
    /// carrying CEA-608 its manifest never declared. False until then, so a
    /// probe still in flight leaves the current start untouched.
    public nonisolated func wrapsInCaptionMaster(channelID: String) -> Bool {
        wrappedChannelIDs.withLock { $0.contains(channelID) }
    }

    /// The headers a provider insists on. Same three a live request carries, so
    /// the probe is not refused where playback is allowed.
    public nonisolated static func headers(for channel: AppleIPTVChannel) -> [String: String] {
        var headers: [String: String] = [:]
        if let agent = channel.userAgent { headers["User-Agent"] = agent }
        if let referer = channel.referer { headers["Referer"] = referer }
        if let origin = channel.origin { headers["Origin"] = origin }
        return headers
    }

    /// Probes once per channel per run. Returns whatever is known now; a first
    /// call starts the work and returns `nil`, which is why the caller treats
    /// this as reporting rather than as a gate on playback.
    @discardableResult
    public func probe(channelID: String, playlistURL: URL, headers: [String: String] = [:]) async -> Result? {
        if let answer = answers[channelID] { return answer }
        guard !inFlight.contains(channelID) else { return nil }
        inFlight.insert(channelID)
        defer { inFlight.remove(channelID) }
        appleTrace("caption probe started for \(channelID)")
        do {
            let head = try await bytes(at: playlistURL, headers: headers, limit: Self.maximumProbeBytes)
            var alreadyDeclares = false
            var isMediaPlaylist = false
            var sample = head
            if let manifest = Self.playlistText(head) {
                // An HLS channel: read what the manifest says, then scan the
                // first segment it names.
                alreadyDeclares = AppleHLSCaptionDeclaration.declaresClosedCaptions(manifest)
                isMediaPlaylist = !AppleHLSCaptionDeclaration.isMasterPlaylist(manifest)
                guard let segmentURI = AppleHLSCaptionDeclaration.firstSegmentURI(in: manifest),
                      let segmentURL = URL(string: segmentURI, relativeTo: playlistURL)?.absoluteURL else {
                    appleTrace("caption probe \(channelID): the playlist names no segment")
                    return nil
                }
                sample = try await bytes(at: segmentURL, headers: headers, limit: Self.maximumProbeBytes)
            }
            // A provider that hands back the transport stream itself, with no
            // manifest, is the common case on this lineup — those bytes are
            // exactly what needs scanning, so they are used as they arrived.
            let carries = AppleCEA608Detector.carriesCEA608(in: sample)
            let result = Result(carriesUndeclaredCaptions: carries && !alreadyDeclares,
                                manifestAlreadyDeclares: alreadyDeclares,
                                isMediaPlaylist: isMediaPlaylist)
            answers[channelID] = result
            if result.wrapsInCaptionMaster {
                wrappedChannelIDs.withLock { _ = $0.insert(channelID) }
            }
            appleTrace("caption probe \(channelID): read \(sample.count) bytes, embedded CEA-608 "
                + "\(carries ? "found" : "not found"), manifest declares captions: \(alreadyDeclares), "
                + "caption master on next start: \(result.wrapsInCaptionMaster)")
            return result
        } catch {
            appleTrace("caption probe failed for \(channelID): \(AppleDiagnosticRedactor.redact(String(describing: error)))")
            return nil
        }
    }

    /// The bytes read as an HLS playlist, or `nil` when the provider handed
    /// back media instead of a manifest.
    static func playlistText(_ data: Data) -> String? {
        let head = String(decoding: data.prefix(8_192), as: UTF8.self)
        guard head.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("#EXTM3U") else { return nil }
        return String(decoding: data.prefix(2 * 1024 * 1024), as: UTF8.self)
    }

    /// Reads at most `limit` bytes and then stops.
    ///
    /// `URLSession.data(for:)` cannot be used here: a live channel's URL often
    /// answers with the transport stream itself, which never ends, and the
    /// request timeout only fires when data *stops* arriving. The first probe
    /// written that way sat on the connection until the app was killed
    /// (measured on the iPad, 2026-09-20). `Range` is still sent for the
    /// servers that honour it; the byte count is what guarantees the stop.
    private func bytes(at url: URL, headers: [String: String], limit: Int) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = Self.requestTimeout
        for (key, value) in headers { request.setValue(value, forHTTPHeaderField: key) }
        request.setValue("bytes=0-\(limit - 1)", forHTTPHeaderField: "Range")
        let (stream, _) = try await session.bytes(for: request)
        var data = Data()
        data.reserveCapacity(min(limit, 512 * 1024))
        for try await byte in stream {
            data.append(byte)
            if data.count >= limit { break }
        }
        return data
    }
}

/// Whether a live channel plays through a synthesized master that declares its
/// CEA-608 (`AppleHLSCaptionDeclaration.master(wrapping:)`).
///
/// AVFoundation only discovers in-band 608 through a master's
/// `CLOSED-CAPTIONS` attribute; a bare media playlist carrying it plays with no
/// captions track at all. Wrapping is limited to exactly that case: a manifest
/// that already speaks about captions (including `CLOSED-CAPTIONS=NONE`) is the
/// provider's word and stays as served, and a raw transport stream or a master
/// has nothing a one-variant wrapper could correctly stand in front of.
public enum AppleLiveCaptionWrapPolicy {
    public static func shouldWrap(
        carriesEmbeddedCaptions: Bool, manifestDeclaresCaptions: Bool, isMediaPlaylist: Bool
    ) -> Bool {
        carriesEmbeddedCaptions && !manifestDeclaresCaptions && isMediaPlaylist
    }
}
