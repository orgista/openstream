/// Which subtitle tracks the stock player's own CC menu cannot reach, so the
/// app's captions menu has to be the one shown for them.
///
/// AVKit lists the item's legible renditions and nothing else. Add-on
/// subtitle files (sidecars, ids from 1 000 000) never become one, and
/// neither do bitmap tracks (PGS, DVB, VobSub) or CEA-708, which the engine
/// draws itself. A stream whose tracks are all native text renditions needs no
/// second menu: AVKit's drives them through `ApplePlayerSubtitleSelection`.
@MainActor
enum AppleMacSubtitleMenuPolicy {
    static func showsAppMenu(tracks: [ApplePlaybackTrack]) -> Bool {
        tracks.contains { !hasNativeRendition($0) }
    }

    static func hasNativeRendition(_ track: ApplePlaybackTrack) -> Bool {
        guard track.id < NativePlaybackEngine.externalSubtitleTrackIDBase else { return false }
        let codec = track.codec?.lowercased() ?? ""
        if ["eia_708", "cea708", "cea_708"].contains(codec) { return false }
        return !ApplePlayerSubtitleSelection.isBitmap(track)
    }
}

#if os(macOS)
import AVKit
import SwiftUI

/// The Mac's `AVPlayerView`, as the full player and Live's inline player both
/// use it: the picture scaled by View ▸ Zoom to Fill, and the "…" button
/// carrying Other sources and — for tracks AVKit's CC menu cannot reach — the
/// app's Subtitles menu.
struct AppleMacPlayerViewRepresentable: NSViewRepresentable {
    let playerView: AVPlayerView
    var zoomToFill = false
    /// AVKit's own full-screen button moves the video into a window of its
    /// own, away from the app's captions and buttons. Off wherever the app
    /// has a full-window player to offer instead.
    var showsAVKitFullScreenButton = false
    /// The full player takes the keyboard from the page it covers, so a
    /// Return cannot press the page's Play button again underneath it.
    var takesKeyboardFocus = false
    var subtitleEntries: [AppleSubtitleCueLayerPolicy.MenuEntry] = []
    var showsSubtitleMenu = false
    var onSelectSubtitle: (Int?) -> Void = { _ in }
    var onOtherSources: (() -> Void)?

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> AVPlayerView {
        if takesKeyboardFocus {
            Task { @MainActor [weak playerView] in
                guard let playerView, let window = playerView.window else { return }
                window.makeFirstResponder(playerView)
            }
        }
        return playerView
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        let gravity = AppleMacPlayerFramePolicy.videoGravity(zoomToFill: zoomToFill)
        if nsView.videoGravity != gravity { nsView.videoGravity = gravity }
        if nsView.showsFullScreenToggleButton != showsAVKitFullScreenButton {
            nsView.showsFullScreenToggleButton = showsAVKitFullScreenButton
        }
        context.coordinator.onSelectSubtitle = onSelectSubtitle
        context.coordinator.onOtherSources = onOtherSources
        // Rebuilt only when what it lists changes: replacing the menu while
        // it is open would close it under the pointer.
        let signature = MenuSignature(otherSources: onOtherSources != nil,
                                      subtitles: showsSubtitleMenu ? subtitleEntries : [])
        guard signature != context.coordinator.menuSignature else { return }
        context.coordinator.menuSignature = signature
        nsView.actionPopUpButtonMenu = actionMenu(coordinator: context.coordinator)
    }

    struct MenuSignature: Equatable {
        let otherSources: Bool
        let subtitles: [AppleSubtitleCueLayerPolicy.MenuEntry]
    }

    private func actionMenu(coordinator: Coordinator) -> NSMenu? {
        let menu = NSMenu(title: "Options")
        if onOtherSources != nil {
            let item = NSMenuItem(title: "Other Sources…", action: #selector(Coordinator.showOtherSources(_:)),
                                  keyEquivalent: "")
            item.target = coordinator
            item.image = NSImage(systemSymbolName: "list.bullet", accessibilityDescription: nil)
            menu.addItem(item)
        }
        if showsSubtitleMenu, !subtitleEntries.isEmpty {
            let tracks = NSMenu(title: "Subtitles")
            for entry in subtitleEntries {
                let item = NSMenuItem(title: entry.title, action: #selector(Coordinator.selectSubtitle(_:)),
                                      keyEquivalent: "")
                item.target = coordinator
                item.representedObject = entry.trackID
                item.state = entry.isSelected ? .on : .off
                tracks.addItem(item)
            }
            let item = NSMenuItem(title: "Subtitles", action: nil, keyEquivalent: "")
            item.image = NSImage(systemSymbolName: "captions.bubble", accessibilityDescription: nil)
            item.submenu = tracks
            menu.addItem(item)
        }
        return menu.items.isEmpty ? nil : menu
    }

    @MainActor final class Coordinator: NSObject {
        var menuSignature: MenuSignature?
        var onSelectSubtitle: (Int?) -> Void = { _ in }
        var onOtherSources: (() -> Void)?

        @objc func selectSubtitle(_ sender: NSMenuItem) {
            onSelectSubtitle(sender.representedObject as? Int)
        }

        @objc func showOtherSources(_ sender: NSMenuItem) {
            onOtherSources?()
        }
    }
}
#endif
