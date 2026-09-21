import Foundation

/// Asks one question about a live channel: does it carry CEA-608 captions the
/// manifest never declared?
///
/// It fetches the head of the playlist's first segment and hands the bytes to
/// `AppleCEA608Detector`. The answer is cached per channel, so a channel is
/// probed once per app run and never while the viewer is waiting — the probe
/// is started alongside playback, not in front of it.
///
/// Nothing acts on the answer yet. `AppleHLSCaptionDeclaration` is the other
/// half: once a channel confirmed to carry embedded captions is available to
/// test against, the proxy declares `INSTREAM-ID="CC1"` for exactly the
/// channels this probe said yes to, and AVFoundation's existing caption
/// pipeline does the rest. Until then this records what the owner's real
/// lineup actually carries, in the trace, with no effect on playback.
public actor AppleLiveCaptionProbe {
    public static let shared = AppleLiveCaptionProbe()

    /// One segment's head is dozens of frames — far more than the detector's
    /// threshold — and small enough that a probe costs a fraction of a second.
    public static let maximumProbeBytes = 512 * 1024
    public static let requestTimeout: TimeInterval = 8

    public struct Result: Equatable, Sendable {
        public let carriesUndeclaredCaptions: Bool
        public let manifestAlreadyDeclares: Bool
    }

    private var answers: [String: Result] = [:]
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
            var sample = head
            if let manifest = Self.playlistText(head) {
                // An HLS channel: read what the manifest says, then scan the
                // first segment it names.
                alreadyDeclares = AppleHLSCaptionDeclaration.declaresClosedCaptions(manifest)
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
                                manifestAlreadyDeclares: alreadyDeclares)
            answers[channelID] = result
            appleTrace("caption probe \(channelID): read \(sample.count) bytes, embedded CEA-608 "
                + "\(carries ? "found" : "not found"), manifest declares captions: \(alreadyDeclares)")
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
