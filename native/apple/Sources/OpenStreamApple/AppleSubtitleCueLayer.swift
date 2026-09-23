import CoreGraphics
import Foundation
import Observation
import SwiftUI

/// What the cue layer draws for one cue: a line of text or a decoded bitmap
/// (PGS/DVB). Rich-text runs are flattened, as the transport overlay always did.
enum AppleSubtitleCueContent: Equatable {
    case text(String)
    case image(CGImage)

    init(_ cue: AppleSubtitleCue) {
        switch cue.body {
        case .text(let s): self = .text(s)
        case .richText(let runs): self = .text(runs.map(\.text).joined())
        case .image(let image): self = .image(image)
        }
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.text(let a), .text(let b)): return a == b
        // CGImage has no value equality; identity is the practical signal.
        case (.image(let a), .image(let b)): return a === b
        default: return false
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
    /// (Q4a8 paths 1 and 2). The native engine's tracks are AVKit's to draw.
    static func mountsOverStockPlayer(
        engine: ApplePlaybackEngineKind,
        route: ApplePlaybackPresentationRoute
    ) -> Bool {
        engine == .openStream && route == .avPlayer
    }

    /// The cue overlapping `position`, or nil. The engine empties its cue list
    /// when no track is selected, so "no track" reads as nil here too.
    static func activeCue(in cues: [AppleSubtitleCue], at position: Double) -> AppleSubtitleCue? {
        cues.first { position >= $0.startTime && position < $0.endTime }
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
    private(set) var cue: AppleSubtitleCue?
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
        let next = AppleSubtitleCueLayerPolicy.activeCue(in: engine.subtitleCues, at: engine.position)
        if next != cue { cue = next }
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

/// The subtitle cue, sat against the **picture** rather than the screen. Shared
/// by the transport overlay (`.surface`) and the stock player (`.avPlayer`).
/// Draws nothing when `cue` is nil; never takes focus or touches.
struct AppleSubtitleCueLayer: View {
    let cue: AppleSubtitleCue?
    let videoSize: CGSize?

    var body: some View {
        // On Apple TV the video is full-bleed so the inset adds nothing; on a
        // phone in portrait the video letterboxes into a band and the caption
        // used to float ~450 pt below it, in the black (2026-09-16). See
        // `AppleVideoFitting`.
        GeometryReader { proxy in
            VStack {
                Spacer()
                if let cue {
                    AppleSubtitleCueLabel(content: AppleSubtitleCueContent(cue))
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
        .allowsHitTesting(false)
    }
}

/// Text cues as a centred label; `.image` cues (PGS/DVB) as the decoded bitmap.
private struct AppleSubtitleCueLabel: View {
    let content: AppleSubtitleCueContent

    var body: some View {
        switch content {
        case .text(let s):
            Text(s)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
        case .image(let cgImage):
            Image(decorative: cgImage, scale: 1)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxHeight: 120)
        }
    }
}

/// The cue layer mounted over the stock AVKit player. Its caller decides when
/// (`AppleSubtitleCueLayerPolicy.mountsOverStockPlayer`) and owns `subtitles`
/// so its own captions control can select through the same object.
struct AppleStockPlayerCueLayer: View {
    let engine: any ApplePlaybackEngine
    let subtitles: AppleStockPlayerSubtitles

    var body: some View {
        AppleSubtitleCueLayer(cue: subtitles.cue, videoSize: engine.videoSize)
            // The overlay's resting inset with its controls hidden. AVKit's
            // own bar is drawn by AVKit, which says nothing about its height.
            .padding(.bottom, 24)
            .accessibilityIdentifier("player.stockCueLayer")
            .task(id: ObjectIdentifier(engine)) { await subtitles.follow(engine) }
    }
}
