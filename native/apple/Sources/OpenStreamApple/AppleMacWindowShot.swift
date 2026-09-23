#if DEBUG && os(macOS)
import AppKit

/// Renders the app's own window to a PNG, and dumps the menu bar, on request
/// from a launch argument.
///
/// This exists because a macOS screenshot could not be taken from a headless
/// session at all, and the repo had concluded it was impossible
/// (`HANDOFF-NEXT-SESSION.md:324`). `screencapture -x` returns the wallpaper
/// with every window erased without a Screen Recording grant, `-l<windowid>`
/// and `-R` fail outright, ScreenCaptureKit is refused
/// (`SCStreamErrorDomain -3801`), and XCUITest needs an Accessibility grant
/// that cannot be given non-interactively.
///
/// None of that applies to an app drawing itself. `cacheDisplay(in:to:)` is
/// the app rendering its own layer tree into its own bitmap: no TCC grant, no
/// window ever brought to the front, and nothing of anyone else's screen in
/// the frame. The previous session drove this from lldb; lldb's Objective-C
/// evaluator has no AppKit headers, so `NSMakeRect` and `stringWithFormat:`
/// are both unavailable there and the expression is a liability. In the app it
/// is ordinary code.
///
/// DEBUG and macOS only, behind an explicit launch argument, so a shipped
/// build has no path to it.
public enum AppleMacWindowShot {
    public struct Request {
        /// A bare filename. It is written inside the app's own container, the
        /// only place a sandboxed app may write without a user's consent; the
        /// caller copies it out.
        public let filename: String
        public let size: CGSize
        public let delay: TimeInterval
        /// Set by `-OpenStreamSnapshotWindow`: an absolute path to write the
        /// PNG to instead, for an unsandboxed debug build a script launched.
        public var destination: URL? = nil
    }

    /// `-OpenStreamWindowShot <name.png> [-OpenStreamWindowShotSize 1280x860]
    ///  [-OpenStreamWindowShotDelay 11]`, or
    /// `-OpenStreamSnapshotWindow </absolute/path.png>` (12 s by default, the
    /// same size and delay flags).
    public static func request(
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) -> Request? {
        let size = value(of: "-OpenStreamWindowShotSize", in: arguments)
            .flatMap(parseSize) ?? CGSize(width: 1280, height: 860)
        let delay = value(of: "-OpenStreamWindowShotDelay", in: arguments).flatMap(Double.init)
        if let path = value(of: "-OpenStreamSnapshotWindow", in: arguments),
           path.hasPrefix("/"), path.lowercased().hasSuffix(".png") {
            let destination = URL(fileURLWithPath: path)
            return Request(filename: destination.lastPathComponent, size: size, delay: delay ?? 12,
                           destination: destination)
        }
        guard let name = value(of: "-OpenStreamWindowShot", in: arguments),
              !name.isEmpty, !name.contains("/") else { return nil }
        return Request(filename: name, size: size, delay: delay ?? 11)
    }

    private static func value(of flag: String, in arguments: [String]) -> String? {
        guard let marker = arguments.firstIndex(of: flag),
              arguments.indices.contains(marker + 1) else { return nil }
        return arguments[marker + 1]
    }

    static func parseSize(_ value: String) -> CGSize? {
        let parts = value.lowercased().split(separator: "x")
        guard parts.count == 2, let w = Double(parts[0]), let h = Double(parts[1]),
              w >= 200, h >= 200, w <= 8_000, h <= 8_000 else { return nil }
        return CGSize(width: w, height: h)
    }

    /// Waits out `delay`, resizes the window, renders it, writes it, and
    /// reports on stderr. stderr because a GUI app launched from a script has
    /// a pipe on stdout, where a handful of lines stay in the block buffer of
    /// a process that never exits.
    @MainActor
    public static func run(_ request: Request) async {
        // A breadcrumb before the wait, so a run that produces nothing can be
        // told apart from a run that never started. Without it, "no window
        // yet", "the argument did not parse" and "the scene never built its
        // content" all look identical from outside: an empty directory.
        write("OPENSTREAM-SHOT started delay=\(request.delay) size=\(Int(request.size.width))x\(Int(request.size.height))\n",
              to: "shot-start.log")
        try? await Task.sleep(for: .seconds(request.delay))
        var lines = [String]()
        guard let window = NSApp.windows.first(where: { $0.contentView != nil }) else {
            emit(["OPENSTREAM-SHOT verdict: no window with a content view"])
            return
        }
        for candidate in NSApp.windows {
            lines.append("OPENSTREAM-SHOT candidate: \(candidate.className) visible=\(candidate.isVisible) sheet=\(candidate.attachedSheet != nil) frame=\(NSStringFromRect(candidate.frame))")
        }
        window.setFrame(
            NSRect(origin: window.frame.origin, size: request.size),
            display: true
        )
        // One turn of the run loop so SwiftUI lays the new size out before the
        // shutter; without it the image is the pre-resize frame.
        await Task.yield()
        try? await Task.sleep(for: .seconds(2))

        lines.append("OPENSTREAM-SHOT window: \(window.className) frame=\(NSStringFromRect(window.frame))")
        lines.append("OPENSTREAM-SHOT styleMask resizable=\(window.styleMask.contains(.resizable)) fullScreenPrimary=\(window.collectionBehavior.contains(.fullScreenPrimary))")
        lines.append("OPENSTREAM-SHOT subviews: \(window.contentView?.subviews.count ?? -1)")

        // A sheet is its own `NSWindow`, so a player or an importer presented
        // over the main window is not in the main window's layer tree at all —
        // the first attempt at capturing local playback photographed the Add
        // Files page the player had covered (2026-09-21). The base window is
        // still the one that gets resized; the sheet is captured at whatever
        // size it chose.
        let target = window.attachedSheet ?? window
        if target !== window {
            lines.append("OPENSTREAM-SHOT capturing the attached sheet: \(target.className)")
        }

        // `contentView.superview` is the NSThemeFrame, so the titlebar is in
        // the frame — which on macOS is where SwiftUI puts the tab bar.
        guard let frameView = target.contentView?.superview,
              let rep = frameView.bitmapImageRepForCachingDisplay(in: frameView.bounds) else {
            emit(lines + ["OPENSTREAM-SHOT verdict: could not make a bitmap rep"])
            return
        }
        frameView.cacheDisplay(in: frameView.bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else {
            emit(lines + ["OPENSTREAM-SHOT verdict: PNG encoding failed"])
            return
        }
        let url = request.destination ?? URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: request.filename)
        do {
            try data.write(to: url, options: .atomic)
            lines.append("OPENSTREAM-SHOT path: \(url.path)")
            lines.append("OPENSTREAM-SHOT bytes: \(data.count)")
            lines.append("OPENSTREAM-SHOT distinctColours: \(distinctColours(in: rep))")
        } catch {
            lines.append("OPENSTREAM-SHOT verdict: write failed \(error)")
            emit(lines)
            return
        }
        lines.append(contentsOf: menuDump())
        lines.append("OPENSTREAM-SHOT verdict: PASS")
        emit(lines)
    }

    /// A blank window is the failure this whole exercise started from, and a
    /// PNG of one is a perfectly valid PNG. One distinct colour means blank.
    private static func distinctColours(in rep: NSBitmapImageRep) -> Int {
        var seen = Set<UInt32>()
        let stepX = max(1, rep.pixelsWide / 120)
        let stepY = max(1, rep.pixelsHigh / 120)
        for y in stride(from: 0, to: rep.pixelsHigh, by: stepY) {
            for x in stride(from: 0, to: rep.pixelsWide, by: stepX) {
                guard let colour = rep.colorAt(x: x, y: y) else { continue }
                let key = UInt32(colour.redComponent * 255) << 16
                    | UInt32(colour.greenComponent * 255) << 8
                    | UInt32(colour.blueComponent * 255)
                seen.insert(key)
                if seen.count > 64 { return seen.count }
            }
        }
        return seen.count
    }

    /// Every menu, item and key equivalent the app declares.
    ///
    /// The macOS sweep's menu-bar row could only be answered by reading the
    /// real `NSApp.mainMenu`, because what SwiftUI does with a `.commands`
    /// block is not obvious from the source — an auto-generated "Toggle
    /// Sidebar ⌘S" was landing in *Help*.
    public static func menuDump() -> [String] {
        guard let main = NSApp.mainMenu else { return ["OPENSTREAM-MENU mainMenu: nil"] }
        var lines = ["OPENSTREAM-MENU menus: \(main.items.count)"]
        for menu in main.items {
            let submenu = menu.submenu
            lines.append("OPENSTREAM-MENU [\(menu.title)] items=\(submenu?.items.count ?? 0)")
            for item in submenu?.items ?? [] {
                if item.isSeparatorItem { continue }
                let key = item.keyEquivalent.isEmpty
                    ? ""
                    : "  key=\(modifierString(item.keyEquivalentModifierMask))\(printable(item.keyEquivalent))"
                lines.append("OPENSTREAM-MENU     \(item.title)\(key)\(item.isEnabled ? "" : "  (disabled)")")
            }
        }
        return lines
    }

    private static func printable(_ key: String) -> String {
        switch key.unicodeScalars.first?.value {
        case 0xF702: "left"
        case 0xF703: "right"
        case 0x20: "space"
        default: key
        }
    }

    private static func modifierString(_ mask: NSEvent.ModifierFlags) -> String {
        var out = ""
        if mask.contains(.control) { out += "ctrl-" }
        if mask.contains(.option) { out += "opt-" }
        if mask.contains(.shift) { out += "shift-" }
        if mask.contains(.command) { out += "cmd-" }
        return out
    }

    /// stderr *and* a file beside the PNG.
    ///
    /// The file is what makes the launch mechanism a free choice: `open -g`
    /// starts the app without bringing it to the front — which matters,
    /// because the owner is using this Mac — but hands the caller no pipe to
    /// read stderr from.
    private static func emit(_ lines: [String]) {
        write(lines.joined(separator: "\n") + "\n", to: "shot.log")
    }

    private static func write(_ text: String, to filename: String) {
        FileHandle.standardError.write(Data(text.utf8))
        try? Data(text.utf8).write(
            to: URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: filename),
            options: .atomic
        )
    }
}
#endif
