#if DEBUG && os(macOS)
import AppKit
import AVFoundation
import AVKit
import SwiftUI

/// Drives the Mac player's captions the way a viewer does and photographs
/// each step, DEBUG only (N38).
///
/// `-OpenStreamCaptionsProbe <dir>` with
/// `-OpenStreamCaptionsProbeSteps "stock:en,stock:off,app:fr,sidecar,app:off"`
/// runs once the player is on screen: `stock:` does what AVKit's CC menu does
/// (`select(_:in:)` on the item), `app:` what the app's own menu does
/// (through the host, as `AppleMacPlayerViewRepresentable` calls it),
/// `sidecar` adds `-OpenStreamCaptionsProbeSidecar <file.srt>` as an add-on
/// track and picks it. After each step it writes `<n>-<step>.png` (the window,
/// as `AppleMacWindowShot` renders it) and a line with what each renderer
/// holds: the item's selected legible option, the engine's active track and
/// app-drawn cues, and the text AVPlayer itself is rendering for the item
/// (`AVPlayerItemLegibleOutput`, which leaves player rendering on).
@MainActor
enum AppleDebugMacCaptionsProbe {
    /// Opens `-OpenStreamVisionPlaybackURL <file or 127.0.0.1 URL>` in the window's player
    /// stage when the probe is requested. The Mac's Settings are a window of
    /// their own, so the Sources pane's fixture hook never runs in the main
    /// window.
    struct Presenter: ViewModifier {
        let settings: AppleSettingsStore
        @State private var presentation: AppleStremioPlayerPresentation?

        func body(content: Content) -> some View {
            content
                .modifier(AppleMacPlayerStagePresenter(presentation: $presentation))
                .task {
                    let defaults = UserDefaults.standard
                    guard defaults.string(forKey: "OpenStreamCaptionsProbe") != nil,
                          let raw = defaults.string(forKey: "OpenStreamVisionPlaybackURL"),
                          let url = URL(string: raw), url.isFileURL || url.host == "127.0.0.1" else { return }
                    try? await Task.sleep(for: .seconds(2))
                    var next = AppleStremioPlayerPresentation(
                        request: ApplePlaybackRequest(url: url, mediaID: "captions-probe",
                                                      title: url.lastPathComponent, sourceKind: .files),
                        settings: settings)
                    next.sourceOptionsLoader = { [settings] in AppleDebugMacCaptionsProbe.fixtureOptions(playing: url, settings: settings) }
                    presentation = next
                }
        }
    }

    /// The ranking table's sample names as the Quality sheet's candidates.
    /// Every one plays the probe's own file.
    static func fixtureOptions(playing url: URL, settings: AppleSettingsStore) -> ApplePlaybackSourceOptions {
        let names = ["Film.2023.2160p.DV.HDR10.HEVC.DDP5.1.mkv", "Film.2023.2160p.HDR.HEVC.EAC3.mp4",
                     "Film.2023.1080p.WEB.H264.AAC.mp4", "Film.2023.1080p.WEB.H265.EAC3.mkv",
                     "Film.2023.720p.x264.AAC.mkv", "Film.2023.480p.XviD.MP3.avi"]
        let streams = names.map {
            AppleStremioHTTPPlaybackCandidate(title: $0, sourceURL: url.appending(queryItems: [.init(name: "n", value: $0)]),
                                              filename: $0)
        }
        func option(_ candidate: AppleStremioHTTPPlaybackCandidate) -> ApplePlaybackSourceOption {
            ApplePlaybackSourceOption(id: candidate.sourceURL, tier: AppleStremioCandidateRanking.traits(of: candidate).tier) { resume in
                AppleStremioPlayerPresentation(request: ApplePlaybackRequest(url: url, resumePosition: resume,
                    mediaID: "captions-probe", title: candidate.title, sourceKind: .files), settings: settings)
            }
        }
        let device = AppleStreamDeviceCapabilities.current
        let tiers = AppleStremioCandidateRanking.qualityTiers(streams, device: device)
        return ApplePlaybackSourceOptions(
            tiers: tiers,
            automatic: AppleStremioCandidateRanking.playbackOrder(streams, choice: .automatic, device: device).map(option),
            byTier: Dictionary(uniqueKeysWithValues: tiers.map { tier in
                (tier, AppleStremioCandidateRanking.playbackOrder(streams, choice: .tier(tier), device: device).map(option))
            }))
    }

    static func runIfRequested(host: ApplePlayerHost, coordinator: ApplePlaybackCoordinator,
                               subtitles: AppleStockPlayerSubtitles) async {
        let defaults = UserDefaults.standard
        guard let dir = defaults.string(forKey: "OpenStreamCaptionsProbe"), dir.hasPrefix("/") else { return }
        let steps = (defaults.string(forKey: "OpenStreamCaptionsProbeSteps") ?? "stock:en,stock:off")
            .split(separator: ",").map(String.init)
        let output = URL(fileURLWithPath: dir)
        let engine = coordinator.engine
        var log = ["CAPTIONS-PROBE engine=\(engine.kind.rawValue)"]
        // Wait for a ready item, then hold the picture on a cue.
        for _ in 0..<150 {
            if engine.avPlayer?.currentItem?.status == .readyToPlay || engine.route == .surface { break }
            try? await Task.sleep(for: .milliseconds(100))
        }
        try? await Task.sleep(for: .seconds(1.5))
        engine.pause()
        await engine.seek(to: 1.5)
        let legible = LegibleTap()
        if let item = engine.avPlayer?.currentItem { legible.attach(to: item) }
        log.append("CAPTIONS-PROBE route=\(engine.route) tracks=\(engine.subtitleTracks.map { "\($0.id):\($0.language ?? "-"):\($0.title)" })")
        log.append("CAPTIONS-PROBE menu=\(subtitles.menuEntries.map(\.title))")
        log.append("CAPTIONS-PROBE macAppMenu=\(AppleStockSubtitleMenuPolicy.showsAppMenu(tracks: engine.subtitleTracks, stockPlayerListsCaptions: subtitles.stockPlayerListsCaptions))")
        log.append(contentsOf: await state(engine: engine, legible: legible, label: "start"))
        shoot(to: output.appending(path: "0-start.png"), log: &log)
        for (index, step) in steps.enumerated() {
            let parts = step.split(separator: ":", maxSplits: 1).map(String.init)
            let action = parts.first ?? ""
            let argument = parts.count > 1 ? parts[1] : ""
            switch action {
            case "stock":
                stockSelect(language: argument == "off" ? nil : argument, engine: engine)
            case "app":
                let id = argument == "off" ? nil : trackID(language: argument, in: engine)
                host.selectSubtitleTrack(id: id)
                subtitles.refresh(from: engine)
            case "sidecar":
                if let path = defaults.string(forKey: "OpenStreamCaptionsProbeSidecar") {
                    engine.addExternalSubtitleTracks([AppleExternalSubtitleTrack(
                        id: "probe-sidecar", languageCode: argument.isEmpty ? "en" : argument,
                        displayName: "Probe", url: URL(fileURLWithPath: path))])
                    try? await Task.sleep(for: .milliseconds(300))
                    let id = engine.subtitleTracks.last { $0.id >= AetherPlaybackEngine.externalSubtitleTrackIDBase }?.id
                    host.selectSubtitleTrack(id: id)
                    subtitles.refresh(from: engine)
                }
            case "quality":
                // The player's own "…" menu item, sent as a click sends it.
                if let window = NSApp.windows.first(where: { $0.isVisible && $0.frame.width > 400 }),
                   let player = playerView(in: window.contentView) as? AVPlayerView,
                   let item = player.actionPopUpButtonMenu?.items.first(where: { $0.title.hasPrefix("Quality") }),
                   let action = item.action {
                    NSApp.sendAction(action, to: item.target, from: item)
                    try? await Task.sleep(for: .seconds(4))
                    if let sheet = window.attachedSheet ?? NSApp.windows.first(where: { $0 !== window && $0.isVisible && $0.frame.width > 200 }) {
                        shootWindow(sheet, to: output.appending(path: "\(index + 1)-quality-sheet.png"), log: &log)
                        log.append("CAPTIONS-PROBE quality sheet: \(texts(in: sheet.contentView))")
                    } else {
                        log.append("CAPTIONS-PROBE quality sheet: none")
                    }
                } else {
                    log.append("CAPTIONS-PROBE quality: no menu item")
                }
            case "engine":
                engine.selectSubtitleTrack(id: argument == "off" ? nil : trackID(language: argument, in: engine))
                subtitles.refresh(from: engine)
            case "detach":
                let layer = (engine as? AetherPlaybackEngine)?.aetherEngine.nativePlayerLayer
                log.append("CAPTIONS-PROBE engine layer: player=\(layer?.player != nil) inTree=\(layer?.superlayer != nil)")
                layer?.player = nil
            case "criteria":
                engine.avPlayer?.appliesMediaSelectionCriteriaAutomatically = argument == "on"
            default:
                log.append("CAPTIONS-PROBE unknown step \(step)")
            }
            // Play a moment so the cue for the new selection reaches both
            // renderers (legible output only pushes as the playhead moves),
            // then hold the frame for the shot.
            legible.reset()
            // A seek makes the legible output push the cue under the
            // playhead again; it only pushes on cue boundaries otherwise.
            await engine.seek(to: 1.5 + Double(index) * 0.2)
            engine.play()
            try? await Task.sleep(for: .seconds(1.2))
            engine.pause()
            try? await Task.sleep(for: .milliseconds(700))
            subtitles.refresh(from: engine)
            try? await Task.sleep(for: .milliseconds(300))
            log.append(contentsOf: await state(engine: engine, legible: legible, label: step))
            log.append("CAPTIONS-PROBE menu=\(subtitles.menuEntries.map { ($0.isSelected ? "✓" : "") + $0.title })")
            let name = "\(index + 1)-\(step.replacingOccurrences(of: ":", with: "-")).png"
            shoot(to: output.appending(path: name), log: &log)
        }
        if let window = NSApp.windows.first(where: { $0.isVisible && $0.frame.width > 400 }),
           let player = playerView(in: window.contentView) as? AVPlayerView {
            let items = player.actionPopUpButtonMenu?.items.map { item in
                item.title + (item.submenu.map { " [" + $0.items.map { ($0.state == .on ? "✓" : "") + $0.title }
                    .joined(separator: ", ") + "]" } ?? "")
            } ?? []
            log.append("CAPTIONS-PROBE player ⋯ menu: \(items)")
        }
        log.append("CAPTIONS-PROBE done")
        FileHandle.standardError.write(Data((log.joined(separator: "\n") + "\n").utf8))
        try? (log.joined(separator: "\n") + "\n").write(to: output.appending(path: "probe.log"),
                                                        atomically: true, encoding: .utf8)
    }

    private static func trackID(language: String, in engine: any ApplePlaybackEngine) -> Int? {
        let wanted = AppleSubtitleTrackFilter.normalized(language)
        return engine.subtitleTracks.first { AppleSubtitleTrackFilter.normalized($0.language ?? "") == wanted }?.id
    }

    private static func stockSelect(language: String?, engine: any ApplePlaybackEngine) {
        guard let item = engine.avPlayer?.currentItem,
              let group = item.asset.mediaSelectionGroup(forMediaCharacteristic: .legible) else { return }
        let option = language.flatMap { wanted in
            group.options.first {
                AppleSubtitleTrackFilter.normalized($0.extendedLanguageTag ?? $0.locale?.identifier ?? "")
                    == AppleSubtitleTrackFilter.normalized(wanted)
                    && !$0.hasMediaCharacteristic(.containsOnlyForcedSubtitles)
            }
        }
        item.select(option, in: group)
    }

    private static func state(engine: any ApplePlaybackEngine, legible: LegibleTap, label: String) async -> [String] {
        var selected = "no item"
        var options: [String] = []
        if let item = engine.avPlayer?.currentItem,
           let group = try? await item.asset.loadMediaSelectionGroup(for: .legible) {
            selected = item.currentMediaSelection.selectedMediaOption(in: group)?.displayName ?? "none"
            options = group.options.map { "\($0.displayName)[\($0.extendedLanguageTag ?? "-")]" }
        }
        let cues = AppleSubtitleCueLayerPolicy.activeCues(in: engine.subtitleCues, at: engine.position)
        return ["CAPTIONS-PROBE [\(label)] avkitOptions=\(options) avkitSelected=\(selected) "
                + "engineActive=\(engine.activeSubtitleTrackID.map(String.init) ?? "nil") "
                + "criteriaAuto=\(engine.avPlayer?.appliesMediaSelectionCriteriaAutomatically.description ?? "-") "
                + "appCues=\(cues.compactMap(\.text)) avplayerRenders=\(legible.recent)"]
    }

    /// AVKit draws captions in Core Animation layers inside the player
    /// view, which `cacheDisplay` leaves out with the video. Rendering the
    /// player view's layer tree directly keeps them; the layers carrying
    /// content are listed so an empty frame can be told from a missed one.
    private static func shootPlayerLayers(to url: URL, log: inout [String]) {
        guard let window = NSApp.windows.first(where: { $0.isVisible && $0.contentView != nil && $0.frame.width > 400 }),
              let player = playerView(in: window.contentView), let layer = player.layer else {
            log.append("CAPTIONS-PROBE layers: no player view")
            return
        }
        var drawn: [String] = []
        func visit(_ layer: CALayer, depth: Int) {
            if layer.contents != nil || (layer as? CATextLayer)?.string != nil, !layer.isHidden, layer.opacity > 0,
               layer.bounds.width > 4, layer.bounds.height > 4 {
                drawn.append("\(type(of: layer))@\(Int(layer.frame.minY))h\(Int(layer.bounds.height))")
            }
            layer.sublayers?.forEach { visit($0, depth: depth + 1) }
        }
        visit(layer, depth: 0)
        log.append("CAPTIONS-PROBE layers with content: \(drawn.prefix(12))")
        let scale = window.backingScaleFactor
        let size = CGSize(width: layer.bounds.width * scale, height: layer.bounds.height * scale)
        guard let context = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8,
                                      bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
        context.setFillColor(CGColor(gray: 0.2, alpha: 1))
        context.fill(CGRect(origin: .zero, size: size))
        context.scaleBy(x: scale, y: scale)
        layer.render(in: context)
        if let image = context.makeImage() {
            let rep = NSBitmapImageRep(cgImage: image)
            if let data = rep.representation(using: .png, properties: [:]), (try? data.write(to: url)) != nil {
                log.append("CAPTIONS-PROBE layers shot: \(url.lastPathComponent)")
            }
        }
    }

    private static func shootWindow(_ window: NSWindow, to url: URL, log: inout [String]) {
        guard let frameView = window.contentView?.superview,
              let rep = frameView.bitmapImageRepForCachingDisplay(in: frameView.bounds) else { return }
        frameView.cacheDisplay(in: frameView.bounds, to: rep)
        if let data = rep.representation(using: .png, properties: [:]), (try? data.write(to: url)) != nil {
            log.append("CAPTIONS-PROBE shot: \(url.lastPathComponent)")
        }
    }

    /// The accessibility labels under `view`, for reading a sheet's rows.
    private static func texts(in view: NSView?) -> [String] {
        guard let view else { return [] }
        var found: [String] = []
        var pending: [Any] = [view]
        while let next = pending.popLast(), found.count < 40 {
            if let element = next as? NSView {
                let label = element.accessibilityLabel() ?? (element as? NSTextField)?.stringValue ?? ""
                if !label.isEmpty, !found.contains(label) { found.append(label) }
                pending.append(contentsOf: (element.accessibilityChildren() ?? []).reversed())
                pending.append(contentsOf: element.subviews.reversed())
            } else if let element = next as? NSAccessibilityElement {
                let label = element.accessibilityLabel() ?? ""
                if !label.isEmpty, !found.contains(label) { found.append(label) }
                pending.append(contentsOf: (element.accessibilityChildren() ?? []).reversed())
            }
        }
        return found
    }

    private static func playerView(in view: NSView?) -> NSView? {
        guard let view else { return nil }
        if view is AVPlayerView { return view }
        for subview in view.subviews { if let found = playerView(in: subview) { return found } }
        return nil
    }

    private static func shoot(to url: URL, log: inout [String]) {
        shootPlayerLayers(to: url.deletingPathExtension().appendingPathExtension("layers.png"), log: &log)
        guard let window = NSApp.windows.first(where: { $0.isVisible && $0.contentView != nil && $0.frame.width > 400 }),
              let frameView = window.contentView?.superview,
              let rep = frameView.bitmapImageRepForCachingDisplay(in: frameView.bounds) else {
            log.append("CAPTIONS-PROBE shot: no window")
            return
        }
        frameView.cacheDisplay(in: frameView.bounds, to: rep)
        if let data = rep.representation(using: .png, properties: [:]), (try? data.write(to: url)) != nil {
            log.append("CAPTIONS-PROBE shot: \(url.lastPathComponent)")
        }
    }

    /// The strings AVPlayer delivers for the selected legible option. Player
    /// rendering stays on (`suppressesPlayerRendering` is false), so this
    /// reads what AVKit draws without changing it.
    @MainActor
    private final class LegibleTap: NSObject, AVPlayerItemLegibleOutputPushDelegate {
        private(set) var recent: [String] = []
        private let output = AVPlayerItemLegibleOutput()

        func reset() { recent = [] }

        func attach(to item: AVPlayerItem) {
            output.suppressesPlayerRendering = false
            output.setDelegate(self, queue: .main)
            item.add(output)
        }

        nonisolated func legibleOutput(_ output: AVPlayerItemLegibleOutput,
                                       didOutputAttributedStrings strings: [NSAttributedString],
                                       nativeSampleBuffers nativeSamples: [Any], forItemTime itemTime: CMTime) {
            let texts = strings.map(\.string)
            MainActor.assumeIsolated { self.recent = texts }
        }
    }
}
#endif
