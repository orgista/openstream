import CoreGraphics
import Foundation
import Observation
import SwiftUI

/// What the cue layer draws for one cue: a line of text or a decoded bitmap
/// (PGS/DVB) with its authored geometry. Rich-text runs are flattened, as the
/// transport overlay always did.
enum AppleSubtitleCueContent: Equatable {
    case text(String)
    case image(AppleSubtitleBitmap)

    init(_ cue: AppleSubtitleCue) {
        switch cue.body {
        case .text(let s): self = .text(s)
        case .richText(let runs): self = .text(runs.map(\.text).joined())
        case .image(let bitmap): self = .image(bitmap)
        }
    }
}

/// Who draws subtitle cues, and which one is on screen.
enum AppleSubtitleCueLayerPolicy {
    /// True when the app has to draw cues over the stock AVKit player.
    ///
    /// On `.surface` the transport overlay carries its own cue layer. On
    /// `.avPlayer` the OpenStream engine keeps AVPlayer's legible group
    /// deselected on purpose (the WebVTT rendition exists for PiP and AirPlay
    /// only, Sodalite#38) and expects the host to draw; nothing did, so every
    /// MKV/TS subtitle and every live-TS caption played blank on a device
    /// (Q4a8 paths 1 and 2). Native embedded tracks remain AVKit's to draw;
    /// native add-on tracks publish cues to this same layer.
    static func mountsOverStockPlayer(
        engine: ApplePlaybackEngineKind,
        route: ApplePlaybackPresentationRoute
    ) -> Bool {
        route == .avPlayer
    }

    /// Every cue overlapping `position`, in the engine's order. Plural because
    /// a PGS composition is one cue per object: a sign at the top and the line
    /// of dialogue at the bottom are on screen together, and `.first` used to
    /// drop one of them (Q4a8 §4). The engine empties its cue list when no
    /// track is selected, so "no track" reads as empty here too.
    static func activeCues(in cues: [AppleSubtitleCue], at position: Double) -> [AppleSubtitleCue] {
        cues.filter { position >= $0.startTime && position < $0.endTime }
    }

    /// One row of the app's subtitle menu on the stock player.
    struct MenuEntry: Equatable, Identifiable {
        let trackID: Int?
        let title: String
        let isSelected: Bool
        var id: String { trackID.map(String.init) ?? "off" }
    }

    /// "Off" and then the same tracks the transport overlay's menu lists.
    static func menuEntries(
        tracks: [ApplePlaybackTrack],
        preferredLanguages: [String],
        languagesAreExplicit: Bool,
        activeTrackID: Int?
    ) -> [MenuEntry] {
        let visible = AppleSubtitleTrackFilter.visible(
            tracks, preferredLanguages: preferredLanguages, isExplicitChoice: languagesAreExplicit)
        guard !visible.isEmpty else { return [] }
        return [MenuEntry(trackID: nil, title: "Off", isSelected: activeTrackID == nil)]
            + visible.map { MenuEntry(trackID: $0.id, title: $0.title, isSelected: $0.id == activeTrackID) }
    }
}

/// Follows an engine's cues and tracks for the stock-player cue layer and the
/// app's subtitle menu. The transport overlay's model does the same job on
/// `.surface`; this is the part of it the stock player needs.
@MainActor
@Observable
final class AppleStockPlayerSubtitles {
    private(set) var cues: [AppleSubtitleCue] = []
    private(set) var menuEntries: [AppleSubtitleCueLayerPolicy.MenuEntry] = []

    /// Runs for as long as the calling `.task` lives.
    func follow(_ engine: any ApplePlaybackEngine) async {
        refresh(from: engine)
        for await event in engine.events {
            switch event {
            case .position, .tracks, .route, .phase:
                refresh(from: engine)
            case .duration, .failure:
                break
            }
        }
    }

    /// The only selection path the stock player uses, so the menu tick and the
    /// cue on screen change together even while paused (no position ticks).
    func select(_ id: Int?, on engine: any ApplePlaybackEngine) {
        engine.selectSubtitleTrack(id: id)
        refresh(from: engine)
    }

    func refresh(from engine: any ApplePlaybackEngine) {
        let next = AppleSubtitleCueLayerPolicy.activeCues(in: engine.subtitleCues, at: engine.position)
        if next != cues { cues = next }
        // Same persisted list the overlay model reads, so both menus agree.
        let chosen = UserDefaults.standard.stringArray(forKey: AppleSubtitleLanguages.defaultsKey)
        let entries = AppleSubtitleCueLayerPolicy.menuEntries(
            tracks: engine.subtitleTracks,
            preferredLanguages: chosen ?? [],
            languagesAreExplicit: chosen != nil,
            activeTrackID: engine.activeSubtitleTrackID)
        if entries != menuEntries { menuEntries = entries }
    }
}

/// The active subtitle cues, sat against the **picture** rather than the
/// screen. Shared by the transport overlay (`.surface`) and the stock player
/// (`.avPlayer`). Draws nothing when `cues` is empty; never takes focus or
/// touches.
///
/// Text cues rest at the bottom, lifted by `textBottomLift` (the controls).
/// Bitmap cues (PGS/DVB) are placed where the disc authored them, on the full
/// screen the video fills, and do not move with the controls.
struct AppleSubtitleCueLayer: View {
    let cues: [AppleSubtitleCue]
    let videoSize: CGSize?
    var textBottomLift: CGFloat = 0

    var body: some View {
        ZStack {
            AppleSubtitleTextCues(cues: cues.filter { $0.text != nil }, videoSize: videoSize)
                .padding(.bottom, textBottomLift)
            AppleSubtitleBitmapCues(cues: cues.filter { $0.text == nil }, videoSize: videoSize)
                // The video ignores the safe area, so its rect is the screen's.
                .ignoresSafeArea()
        }
        .allowsHitTesting(false)
    }
}

/// Text cues as centred lines at the bottom of the picture.
private struct AppleSubtitleTextCues: View {
    let cues: [AppleSubtitleCue]
    let videoSize: CGSize?

    var body: some View {
        // On Apple TV the video is full-bleed so the inset adds nothing; on a
        // phone in portrait the video letterboxes into a band and the caption
        // used to float ~450 pt below it, in the black (2026-09-16). See
        // `AppleVideoFitting`.
        GeometryReader { proxy in
            VStack {
                Spacer()
                if !cues.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(cues) { cue in
                            Text(cue.text ?? "")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white)
                                .multilineTextAlignment(.center)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .shadow(color: .black, radius: 2)
                    // Inside the frame, not outside it. Padding applied
                    // *after* `.frame` expands the view instead of lifting
                    // the cue within it — which is why the first attempt
                    // built, passed its geometry tests and changed nothing
                    // on screen (2026-09-16).
                    .padding(.bottom, AppleVideoFitting.captionBottomInset(
                        container: proxy.size,
                        videoSize: videoSize
                    ))
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .bottom)
        }
    }
}

/// Bitmap cues, each at its authored rect on the picture
/// (`AppleVideoFitting.bitmapSubtitleFrame`). No shadow: PGS carries its own
/// antialiased outline. No size cap: a 1920×1080 canvas on a 1920 pt wide
/// Apple TV picture draws at 1:1, and smaller on a phone.
private struct AppleSubtitleBitmapCues: View {
    let cues: [AppleSubtitleCue]
    let videoSize: CGSize?

    var body: some View {
        GeometryReader { proxy in
            ForEach(cues) { cue in
                if case .image(let bitmap) = cue.body {
                    let frame = AppleVideoFitting.bitmapSubtitleFrame(
                        rect: bitmap.rect,
                        canvasSize: bitmap.canvasSize,
                        container: proxy.size,
                        videoSize: videoSize
                    )
                    Image(decorative: bitmap.image, scale: 1)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: frame.width, height: frame.height)
                        .position(x: frame.midX, y: frame.midY)
                }
            }
        }
    }
}

/// The cue layer mounted over the stock AVKit player. Its caller decides when
/// (`AppleSubtitleCueLayerPolicy.mountsOverStockPlayer`) and owns `subtitles`
/// so its own captions control can select through the same object.
struct AppleStockPlayerCueLayer: View {
    let engine: any ApplePlaybackEngine
    let subtitles: AppleStockPlayerSubtitles
    /// Extra lift for text cues, e.g. the live footer while it is up.
    var textBottomLift: CGFloat = 0

    var body: some View {
        // 24: the overlay's resting inset with its controls hidden. AVKit's
        // own bar is drawn by AVKit, which says nothing about its height.
        AppleSubtitleCueLayer(cues: subtitles.cues, videoSize: engine.videoSize,
                              textBottomLift: 24 + textBottomLift)
            .accessibilityIdentifier("player.stockCueLayer")
            .task(id: ObjectIdentifier(engine)) { await subtitles.follow(engine) }
    }
}
