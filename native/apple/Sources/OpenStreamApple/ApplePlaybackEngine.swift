import AVFoundation
import CoreGraphics
import Foundation

public enum ApplePlaybackEnginePhase: Equatable, Sendable {
    case idle
    case loading
    case playing
    case paused
    case seeking
    case rebuffering
    case stalled(reconnecting: Bool)
    case ended
    case error(String)
}

public enum ApplePlaybackPresentationRoute: String, Equatable, Sendable, CaseIterable {
    case none
    case avPlayer
    case surface
    case audioOnly
}

public struct ApplePlaybackTrack: Identifiable, Equatable, Sendable {
    public let id: Int
    public let title: String
    public let language: String?
    public let codec: String?
    public let isDefault: Bool

    public init(id: Int, title: String, language: String? = nil, codec: String? = nil, isDefault: Bool = false) {
        self.id = id
        self.title = title
        self.language = language
        self.codec = codec
        self.isDefault = isDefault
    }
}

/// One contiguous same-styling span of a rich-text subtitle cue, bridged from
/// the engine's `SubtitleTextRun`. Plain values only; the overlay applies the
/// host's font and foreground preference when a run leaves them default.
public struct AppleSubtitleTextRun: Sendable, Equatable {
    public let text: String
    public let isBold: Bool
    public let isItalic: Bool
    public let isUnderlined: Bool
    public let isStruckThrough: Bool

    public init(text: String, isBold: Bool = false, isItalic: Bool = false,
                isUnderlined: Bool = false, isStruckThrough: Bool = false) {
        self.text = text
        self.isBold = isBold
        self.isItalic = isItalic
        self.isUnderlined = isUnderlined
        self.isStruckThrough = isStruckThrough
    }
}

/// The payload of a subtitle cue, mirroring the engine's `SubtitleCue.Body`:
/// plain `.text`, styled `.richText`, or a rendered `.image` bitmap (PGS/DVB).
public enum AppleSubtitleCueBody {
    case text(String)
    case richText([AppleSubtitleTextRun])
    case image(CGImage)
}

extension AppleSubtitleCueBody: Equatable {
    public static func == (lhs: AppleSubtitleCueBody, rhs: AppleSubtitleCueBody) -> Bool {
        switch (lhs, rhs) {
        case (.text(let a), .text(let b)):
            return a == b
        case (.richText(let a), .richText(let b)):
            return a == b
        case (.image(let a), .image(let b)):
            // CGImage has no value equality; identity is the practical signal
            // that the decoded bitmap is unchanged.
            return a === b
        default:
            return false
        }
    }
}

/// One decoded subtitle cue bridged from the engine. `startTime`/`endTime` are
/// source-PTS seconds; the overlay renders the cue active at the current
/// position. On `.avPlayer` routes the system player's own captions menu
/// renders the track, so `subtitleCues` stays empty there.
public struct AppleSubtitleCue: Identifiable, Equatable {
    public let id: Int
    public let startTime: Double
    public let endTime: Double
    public let body: AppleSubtitleCueBody

    public init(id: Int, startTime: Double, endTime: Double, body: AppleSubtitleCueBody) {
        self.id = id
        self.startTime = startTime
        self.endTime = endTime
        self.body = body
    }

    /// Plain text for `.text` and `.richText` (runs concatenated); nil for `.image`.
    public var text: String? {
        switch body {
        case .text(let s): return s
        case .richText(let runs): return runs.map(\.text).joined()
        case .image: return nil
        }
    }
}

public enum ApplePlaybackEngineEvent: Equatable, Sendable {
    case phase(ApplePlaybackEnginePhase)
    case route(ApplePlaybackPresentationRoute)
    case position(Double)
    case duration(Double?)
    case tracks
    case failure(ApplePlaybackFailure?)
}

public enum ApplePlaybackEngineKind: String, CaseIterable, Sendable {
    case openStream = "engine"
    case native = "native"
}

@MainActor
public protocol ApplePlaybackEngine: AnyObject {
    var kind: ApplePlaybackEngineKind { get }
    var phase: ApplePlaybackEnginePhase { get }
    var route: ApplePlaybackPresentationRoute { get }
    var position: Double { get }
    var duration: Double? { get }
    var audioTracks: [ApplePlaybackTrack] { get }
    var subtitleTracks: [ApplePlaybackTrack] { get }
    /// The subtitle track the engine is rendering right now, or nil for none.
    ///
    /// The overlay keeps its own record of what the viewer picked, but that
    /// record starts empty — and the engine auto-selects a track at load when
    /// the viewer's captions preference asks for one. Without this the CC key
    /// would read "off" over a picture with captions on it.
    var activeSubtitleTrackID: Int? { get }
    /// The picture's pixel dimensions once known, for laying out anything that
    /// has to sit against the video rather than the screen — subtitles, above
    /// all. Nil while unknown, and on routes that cannot report it; callers
    /// fall back to `AppleVideoFitting.assumedAspect`.
    var videoSize: CGSize? { get }
    /// Decoded cues for the active subtitle track, for the overlay to render on
    /// `.surface` routes. Empty on `.avPlayer` routes where the system player's
    /// own captions menu renders the track.
    var subtitleCues: [AppleSubtitleCue] { get }
    /// The stream's own chapter markers (Matroska chapters, MPEG-4 chapter
    /// tracks), for Skip Intro. Empty when the file carries none.
    var chapters: [AppleChapter] { get }
    var failure: ApplePlaybackFailure? { get }
    /// Non-nil only on `.avPlayer` routes.
    var avPlayer: AVPlayer? { get }
    /// The span the stream can actually be seeked within, on the same axis as
    /// `position`. Nil when the engine has nothing to report — no item loaded,
    /// or a live source with no rewind at all.
    ///
    /// Read from the player, never from `ApplePlaybackRequest.dvrWindowSeconds`:
    /// that number is a load hint every live request carries as 1800, and the
    /// transport used to clamp its seeks to it. See `AppleSeekableRange`.
    var seekableRange: AppleSeekableRange? { get }
    /// A fresh stream per call; every property change is emitted.
    var events: AsyncStream<ApplePlaybackEngineEvent> { get }
    func load(_ request: ApplePlaybackRequest) async throws
    func play()
    func pause()
    var maximumPlaybackRate: Float { get }
    func setPlaybackRate(_ rate: Float)
    func stop()
    func seek(to seconds: Double) async
    func selectAudioTrack(id: Int)
    func selectSubtitleTrack(id: Int?)
    /// Append subtitle files fetched from add-ons to `subtitleTracks`, after the
    /// tracks embedded in the media. Engines that cannot render an external
    /// file ignore them.
    func addExternalSubtitleTracks(_ tracks: [AppleExternalSubtitleTrack])
}

public extension ApplePlaybackEngine {
    func addExternalSubtitleTracks(_ tracks: [AppleExternalSubtitleTrack]) {}
    /// Engines that cannot report their selection say nothing, and the overlay
    /// falls back to the last track it selected itself.
    var activeSubtitleTrackID: Int? { nil }
    /// Most routes cannot report this; the fitting falls back to 16:9.
    var videoSize: CGSize? { nil }

    /// Engines that know nothing about their seekable span report none, and
    /// the transport treats the stream as live-edge-only.
    var seekableRange: AppleSeekableRange? { nil }

    /// `AVPlayerItem.seekableTimeRanges`, folded to the one contiguous range
    /// that matters. Live HLS reports a single sliding range; a VOD item
    /// reports its whole timeline. Shared by both engines, because both end up
    /// behind an `AVPlayer` on the routes where this is knowable.
    @MainActor
    func avPlayerSeekableRange(_ player: AVPlayer?) -> AppleSeekableRange? {
        guard let item = player?.currentItem else { return nil }
        let ranges = item.seekableTimeRanges.map(\.timeRangeValue).filter { $0.duration.isNumeric }
        guard let first = ranges.first else { return nil }
        // Take the outer bounds: a stream with a gap is still seekable across
        // the parts it holds, and the player clamps inside them for us.
        let start = ranges.reduce(first.start.seconds) { Swift.min($0, $1.start.seconds) }
        let end = ranges.reduce(first.end.seconds) { Swift.max($0, $1.end.seconds) }
        return AppleSeekableRange(start: start, end: end)
    }

    var maximumPlaybackRate: Float { 2 }
    func setPlaybackRate(_ rate: Float) {
        guard rate.isFinite, rate >= 0, rate <= maximumPlaybackRate else { return }
        if let avPlayer { avPlayer.rate = rate }
        else if rate == 0 { pause() }
        else { play() }
    }
}

// Cues are immutable values (text runs, or a decoded CGImage that is never
// mutated after creation); they may be parsed off the main actor and handed
// back to it.
extension AppleSubtitleTextRun: @unchecked Sendable {}
extension AppleSubtitleCueBody: @unchecked Sendable {}
extension AppleSubtitleCue: @unchecked Sendable {}

// MARK: - Caption preferences

public extension ApplePlaybackEngine {
    /// Hands the viewer's caption settings to whichever engine is playing.
    ///
    /// Every call site used to do this with `as? AetherPlaybackEngine`, so on
    /// the AVPlayer route — which on Apple TV takes MP4, M4V, MOV and HLS, i.e.
    /// most well-formed content — the chosen language and the captions
    /// preference were dropped on the floor (owner 2026-09-15: "subtitles are
    /// not working"). One call, both engines.
    @MainActor
    func applyCaptionPreferences(
        preference: AppleCaptionsPreference,
        languages: [String],
        languagesAreExplicit: Bool
    ) {
        if let aether = self as? AetherPlaybackEngine {
            aether.captionsPreference = preference
            aether.preferredSubtitleLanguages = languages
            aether.subtitleLanguagesAreExplicit = languagesAreExplicit
        } else if let native = self as? NativePlaybackEngine {
            native.captionsPreference = preference
            native.preferredSubtitleLanguages = languages
            native.subtitleLanguagesAreExplicit = languagesAreExplicit
        }
    }

    /// The captions preference alone, for the live toggle in the transport.
    @MainActor
    func applyCaptionPreference(_ preference: AppleCaptionsPreference) {
        if let aether = self as? AetherPlaybackEngine {
            aether.captionsPreference = preference
        } else if let native = self as? NativePlaybackEngine {
            native.captionsPreference = preference
        }
    }
}

public extension ApplePlaybackEngine {
    var chapters: [AppleChapter] { [] }
}
