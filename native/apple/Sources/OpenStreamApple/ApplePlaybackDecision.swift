import Foundation

public struct AppleStreamDescriptors: Codable, Equatable, Sendable {
    public var width: Int?
    public var height: Int?
    public var container: String?
    public var videoCodec: String?
    public var videoLevel: Double?
    public var dolbyVisionProfile: Int?
    public var audioCodec: String?
    public var subtitleCodec: String?
    public var bitrate: Int?
    public var duration: Double?

    public init(container: String? = nil, videoCodec: String? = nil, videoLevel: Double? = nil,
                dolbyVisionProfile: Int? = nil, audioCodec: String? = nil, subtitleCodec: String? = nil,
                bitrate: Int? = nil, duration: Double? = nil, width: Int? = nil, height: Int? = nil) {
        self.width = width
        self.height = height
        self.container = container
        self.videoCodec = videoCodec
        self.videoLevel = videoLevel
        self.dolbyVisionProfile = dolbyVisionProfile
        self.audioCodec = audioCodec
        self.subtitleCodec = subtitleCodec
        self.bitrate = bitrate
        self.duration = duration
    }
}

public struct AppleDeviceCapabilities: Equatable, Sendable {
    public var hardwareHEVCLevel: Double = 5.1
    public var hardwareAV1: Bool = false
    public var nativeVideoCodecs: Set<String> = ["h264", "hevc", "mpeg4"]
    public var nativeAudioCodecs: Set<String> = ["aac", "ac3", "eac3", "flac", "alac", "mp3", "pcm_s16le", "pcm_s24le"]
    public init() {}
}

public struct ApplePlaybackDecision: Equatable, Sendable {
    public enum Video: Equatable, Sendable { case originalBytes, localSoftwareDecode, serverTranscode }
    public enum Audio: Equatable, Sendable { case passthrough, localDecode(String), serverTranscode }
    public enum Subtitle: Equatable, Sendable { case embedded, none, serverBurnIn }
    public enum Reason: Equatable, Sendable {
        case containerNotNative, videoLevelAboveHardware(Double), dolbyVisionProfileUnsupported(Int)
        case audioCodecUnsupported(String), videoCodecUnsupported(String), bitrateAboveRouteLimit, engineFailure
    }
    public var video: Video
    public var audio: Audio
    public var subtitle: Subtitle
    public var reasons: [Reason]

    public static func decide(_ descriptors: AppleStreamDescriptors, remote: Bool = false, failedOriginal: Bool = false,
                              capabilities: AppleDeviceCapabilities = .init()) -> Self {
        var reasons: [Reason] = []
        var video: Video = .originalBytes
        var audio: Audio = .passthrough
        if let container = descriptors.container?.lowercased(), !["mp4", "mov", "m4v", "m3u8"].contains(container) {
            reasons.append(.containerNotNative)
        }
        if let codec = descriptors.videoCodec?.lowercased(),
           !capabilities.nativeVideoCodecs.contains(codec), !(codec == "av1" && capabilities.hardwareAV1) {
            reasons.append(.videoCodecUnsupported(codec))
            if !remote { video = .localSoftwareDecode }
        }
        if let level = descriptors.videoLevel, level > capabilities.hardwareHEVCLevel {
            reasons.append(.videoLevelAboveHardware(level))
            video = remote ? .originalBytes : .localSoftwareDecode
        }
        if let profile = descriptors.dolbyVisionProfile, ![5, 8].contains(profile) {
            reasons.append(.dolbyVisionProfileUnsupported(profile))
        }
        if let codec = descriptors.audioCodec?.lowercased(), !capabilities.nativeAudioCodecs.contains(codec) {
            reasons.append(.audioCodecUnsupported(codec))
            audio = .localDecode(codec)
        }
        if failedOriginal { reasons.append(.engineFailure) }
        return Self(video: video, audio: audio,
                    subtitle: descriptors.subtitleCodec == nil ? .none : .embedded, reasons: reasons)
    }

    public func mismatch(observedSoftwareDecode: Bool) -> Bool {
        (video == .localSoftwareDecode) != observedSoftwareDecode
    }
}

enum AppleJellyfinPlaybackPolicy {
    enum Route: Equatable { case original, conversion }
    static func select(_ sources: [AppleMediaServerPlaybackInfo.MediaSource], failed: Set<String>, preferred: String? = nil) -> AppleMediaServerPlaybackInfo.MediaSource? {
        let available = sources.filter { !failed.contains($0.id) }
        if let preferred, let source = available.first(where: { $0.id == preferred }) { return source }
        let ranked = available.enumerated().sorted { lhs, rhs in
            func rank(_ source: AppleMediaServerPlaybackInfo.MediaSource) -> (Int, Int, Int, Int) {
                let height = source.mediaStreams.first { $0.type?.lowercased() == "video" }?.height
                    ?? AppleStremioCandidateRanking.resolution(source.name ?? "")
                let badges = source.formatBadges
                let range = badges.contains(.dolbyVision) ? 3 : badges.contains(.hdr10Plus) ? 2 : badges.contains(.hdr10) ? 1 : 0
                return (source.supportsDirectPlay ? 2 : source.supportsDirectStream ? 1 : 0, height, range, source.bitrate ?? 0)
            }
            let a = rank(lhs.element), b = rank(rhs.element)
            return a == b ? lhs.offset < rhs.offset : a > b
        }.map(\.element)
        return ranked.first
    }
    static func route(for source: AppleMediaServerPlaybackInfo.MediaSource, afterFailure: Bool) -> Route {
        afterFailure && source.transcodingURLPath != nil ? .conversion : .original
    }

    static func conversionURL(_ path: String, session: AppleMediaServerSession, audioStreamIndex: Int? = nil, audioOnly: Bool = false, videoCodec: String? = nil) throws -> URL {
        guard let url = URL(string: path, relativeTo: session.baseURL)?.absoluteURL,
              url.scheme == session.baseURL.scheme, url.host == session.baseURL.host,
              url.port == session.baseURL.port else { throw AppleMediaServerError.unsupported }
        guard audioOnly else { return url }
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { throw AppleMediaServerError.unsupported }
        var overrides = ["AllowVideoStreamCopy": "true", "AllowAudioStreamCopy": "false", "AudioCodec": "aac"]
        if let videoCodec, !videoCodec.isEmpty { overrides["VideoCodec"] = videoCodec }
        let names = Set(overrides.keys.map { $0.lowercased() })
        var query = (components.queryItems ?? []).filter { !names.contains($0.name.lowercased()) && $0.name.lowercased() != "audiostreamindex" }
        query += overrides.keys.sorted().map { URLQueryItem(name: $0, value: overrides[$0]) }
        if let audioStreamIndex { query.append(URLQueryItem(name: "AudioStreamIndex", value: String(audioStreamIndex))) }
        components.queryItems = query
        guard let result = components.url else { throw AppleMediaServerError.unsupported }
        return result
    }

    static func conversionDecision(for source: AppleMediaServerPlaybackInfo.MediaSource) -> ApplePlaybackDecision {
        var decision = ApplePlaybackDecision.decide(source.descriptors, remote: true, failedOriginal: true)
        let audioOnly = isAudioOnlyMismatch(source)
        decision.video = audioOnly ? .originalBytes : .serverTranscode
        decision.audio = .serverTranscode
        return decision
    }

    static func isAudioOnlyMismatch(_ source: AppleMediaServerPlaybackInfo.MediaSource) -> Bool {
        let reasons = ApplePlaybackDecision.decide(source.descriptors, remote: true).reasons
        return reasons.contains { if case .audioCodecUnsupported = $0 { true } else { false } }
            && !reasons.contains { reason in
                switch reason {
                case .videoCodecUnsupported, .videoLevelAboveHardware, .dolbyVisionProfileUnsupported, .bitrateAboveRouteLimit: true
                default: false
                }
            }
    }

    /// Aether accepts original containers and decodes unsupported audio locally.
    /// No bitrate limit or speculative codec restriction asks the server to lower quality.
    static var deviceProfile: [String: Any] {
        ["Name": "oStream",
         "DirectPlayProfiles": [["Type": "Video"], ["Type": "Audio"]],
         "TranscodingProfiles": [["Type": "Video", "Context": "Streaming", "Protocol": "hls",
                                    "Container": "ts", "VideoCodec": "h264", "AudioCodec": "aac", "CopyTimestamps": true]]]
    }
}

enum ApplePlaybackFallbackPolicy {
    enum Step: Equatable { case conversion, nextVersion, unavailable }
    static func next(triedConversion: Bool, nextVersionAvailable: Bool) -> Step {
        if !triedConversion { return .conversion }
        return nextVersionAvailable ? .nextVersion : .unavailable
    }
}
