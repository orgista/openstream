import XCTest

/// A timing walk on a real Apple TV with the viewer's own library: no stubs, no
/// reset, nothing played or saved. It drives the remote and prints
/// `PERFWALK <step> <ms>` (press until the focused label changes, which
/// includes XCUITest's own snapshot cost); the app's trace carries the in-app
/// side (`tab → X` … `tab X on screen`). Skipped unless the runner gets
/// `TEST_RUNNER_OPENSTREAM_PERF_WALK=1`.
@MainActor
final class AppleTVPerfWalkUITests: OpenStreamUITestCase {
    private let app = XCUIApplication(bundleIdentifier: "com.orgista.openstream")
    private var remote: XCUIRemote { .shared }
    private var blind = false
    private let tabLabels: Set<String> = ["Search", "Discover", "Library", "Live", "Settings"]

    private var focusedLabel: String { blind ? "" : focused.label }

    private var focused: XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "hasFocus == true")).firstMatch
    }

    override func tearDown() {
        app.terminate()
    }

    /// Wakes a sleeping Apple TV, which refuses foreground launches until a
    /// remote press (the harness runs this before `devicectl` launches).
    func testWake() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["OPENSTREAM_PERF_WALK"] == "1", "device timing walk only")
        remote.press(.home)
        pause(3)
    }

    func testPerfWalk() throws {
        let environment = ProcessInfo.processInfo.environment
        try XCTSkipUnless(environment["OPENSTREAM_PERF_WALK"] == "1", "device timing walk only")
        let rounds = Int(environment["OPENSTREAM_PERF_ROUNDS"] ?? "") ?? 10
        remote.press(.home)
        pause(3)
        // Under a profiler the harness has already launched the app and
        // attached to it; a relaunch here would leave the profiler behind.
        if environment["OPENSTREAM_PERF_ACTIVATE"] == "1" {
            app.activate()
        } else {
            app.launchArguments = ["-OpenStreamTrace", "YES", "-OpenStreamMuteAudio", "YES"]
            app.launch()
        }
        for _ in 0 ..< 3 where !focused.waitForExistence(timeout: 10) { remote.press(.up) }
        // Some Apple TVs (display asleep) report no focus to XCUITest at all;
        // the remote still drives the app and its trace still times it.
        blind = !focused.exists
        if blind { print("PERFWALK blind: no element reports focus") }

        reachTabBar()
        for _ in 0 ..< 5 where blind || focused.label != "Search" { remote.press(.left); pause(0.8) }
        // Every tab, both directions, the way a viewer runs along the bar and
        // reads each one.
        for round in 1 ... rounds {
            for direction in [XCUIRemote.Button.right, .left] {
                for _ in 0 ..< 4 {
                    let from = focusedLabel
                    let ms = timedPress(direction)
                    print("PERFWALK tab r\(round) \(from)->\(focusedLabel) \(ms)")
                    pause(1.5)
                }
            }
        }

        // Focus along a full shelf on Discover.
        for _ in 0 ..< (blind ? 1 : 4) where blind || focused.label != "Discover" { remote.press(.right); pause(0.8) }
        pause(3)
        for _ in 0 ..< 3 { remote.press(.down); pause(1.2) }
        for round in 1 ... rounds {
            for direction in [XCUIRemote.Button.right, .left] {
                let ms = timedPress(direction)
                print("PERFWALK focus r\(round) \(direction == .right ? "right" : "left") \(blind ? "" : focused.identifier) \(ms)")
                pause(0.6)
            }
        }

        // Title page open and back.
        for round in 1 ... min(rounds, 5) {
            let start = Date()
            remote.press(.select)
            let play = app.descendants(matching: .any).matching(identifier: "detail.play").firstMatch
            let opened = blind ? play.waitForExistence(timeout: 1) : play.waitForExistence(timeout: 20)
            print("PERFWALK title r\(round) opened=\(opened) \(Int(Date().timeIntervalSince(start) * 1000))")
            pause(4)
            remote.press(.menu)
            pause(2.5)
            remote.press(.right)
            pause(1)
        }
    }

    /// Presses and returns the milliseconds until focus reports a new element.
    private func timedPress(_ button: XCUIRemote.Button) -> Int {
        guard !blind else { remote.press(button); return -1 }
        let before = focused.identifier + "|" + focused.label
        let start = Date()
        remote.press(button)
        while Date().timeIntervalSince(start) < 6, focused.identifier + "|" + focused.label == before {}
        return Int(Date().timeIntervalSince(start) * 1000)
    }

    private func reachTabBar() {
        for _ in 0 ..< (blind ? 4 : 6) where blind || !tabLabels.contains(focused.label) { remote.press(.up); pause(1) }
        XCTAssertTrue(blind || tabLabels.contains(focused.label), "never reached the tab bar; focus on '\(focused.label)'")
    }

    private func pause(_ seconds: TimeInterval) { Thread.sleep(forTimeInterval: seconds) }
}

/// The same timing walk run against OpenStream and Plex on one Apple TV, so
/// XCUITest's own cost is the same on both sides. Elements are found the same
/// way in both apps (focus queries, labels), and "drawn" means the screen
/// stopped changing: a downscaled screenshot is polled until it holds still
/// for `quiet` seconds, and the step ends at the last change. Prints
/// `CMPWALK <app> <step> <ms>`; screenshots go into the result bundle.
/// Skipped unless the runner gets `TEST_RUNNER_OPENSTREAM_PERF_WALK=1`.
@MainActor
final class AppleTVPlexCompareUITests: OpenStreamUITestCase {
    private struct Target {
        let name: String
        let app: XCUIApplication
        let launchArguments: [String]
        let playIdentifier: String
        var isPlex: Bool { name == "plex" }
    }

    private let openStream = Target(
        name: "openstream", app: XCUIApplication(bundleIdentifier: "com.orgista.openstream"),
        launchArguments: ["-OpenStreamTrace", "YES"], playIdentifier: "detail.play")
    private let plex = Target(
        name: "plex", app: XCUIApplication(bundleIdentifier: "com.plexapp.plex"),
        launchArguments: [], playIdentifier: "action-button-watch")

    private var remote: XCUIRemote { .shared }
    private var environment: [String: String] { ProcessInfo.processInfo.environment }
    private var keepShots = true

    override func setUpWithError() throws {
        try XCTSkipUnless(environment["OPENSTREAM_PERF_WALK"] == "1", "device timing walk only")
        executionTimeAllowance = 3600
    }

    /// Prints what an app shows (element tree, focus, screenshots), for
    /// writing its locators and for checking Plex is signed in.
    func testDumpPlex() throws { try dump(plex) }
    func testDumpOpenStream() throws { try dump(openStream) }
    func testLaunchPlex() throws { launches(plex) }
    func testLaunchOpenStream() throws { launches(openStream) }
    func testWalkPlex() throws { walks(plex) }
    func testWalkOpenStream() throws { walks(openStream) }

    /// `OPENSTREAM_CMP_STEPS`: comma-separated remote buttons (`up`, `select`, …),
    /// `waitN` seconds, `shot`, `dump` (element tree) and `focus`, run after a launch.
    private func dump(_ target: Target) throws {
        let steps = (environment["OPENSTREAM_CMP_STEPS"] ?? "wait15,shot,dump").split(separator: ",").map(String.init)
        let buttons: [String: XCUIRemote.Button] = ["up": .up, "down": .down, "left": .left, "right": .right,
                                                    "select": .select, "menu": .menu, "playpause": .playPause]
        remote.press(.home)
        pause(3)
        target.app.launchArguments = target.launchArguments
        target.app.launch()
        for (index, step) in steps.enumerated() {
            if let button = buttons[step] {
                remote.press(button)
                pause(1.2)
                print("CMPDUMP \(target.name) \(step) → '\(focus(target).label)' id='\(focus(target).id)'")
            } else if step.hasPrefix("wait"), let seconds = Double(step.dropFirst(4)) {
                pause(seconds)
            } else if step == "shot" {
                shot(target, "dump-\(index)")
            } else if step == "dump" {
                print("CMPDUMP \(target.name) tree at \(index)\n\(target.app.debugDescription)")
            } else if step == "focus" {
                print("CMPDUMP \(target.name) focus '\(focus(target).label)' id='\(focus(target).id)'")
            }
        }
        target.app.terminate()
    }

    /// 1. Cold launch → first focused element (interactive) → screen still
    /// (visible posters drawn). Plex opens on its profile picker; its Home is
    /// timed from the press that picks the first profile.
    private func launches(_ target: Target) {
        let app = target.app
        remote.press(.home)
        pause(3)
        for round in 1 ... (Int(environment["OPENSTREAM_CMP_LAUNCHES"] ?? "") ?? 10) {
            keepShots = round == 1
            app.terminate()
            pause(4)
            app.launchArguments = target.launchArguments
            let start = Date()
            app.launch()
            let launched = ms(since: start)
            let interactive = focused(target).waitForExistence(timeout: 30) ? ms(since: start) : -1
            var line = "launch r\(round) launched=\(launched) interactive=\(interactive)"
            var homeStart = start
            if target.isPlex {
                let picker = settle(start: start, timeout: 20)
                line += " picker=\(picker.ms)"
                shot(target, "1-picker")
                homeStart = Date()
                remote.press(.select)
                let deadline = Date().addingTimeInterval(30)
                while Date() < deadline, focus(target).id.hasPrefix("switch-user") || focus(target).id.isEmpty && focus(target).label.isEmpty {}
                line += " home.interactive=\(ms(since: homeStart))"
            }
            let drawn = settle(start: homeStart, timeout: 30, quiet: 2)
            log(target, "\(line) drawn=\(drawn.ms) settled=\(drawn.settled)")
            shot(target, "1-home")
        }
        app.terminate()
    }

    private func walks(_ target: Target) {
        let app = target.app
        let title = environment["OPENSTREAM_CMP_TITLE"] ?? "Practical Magic 2"
        remote.press(.home)
        pause(3)
        app.terminate()
        pause(3)
        app.launchArguments = target.launchArguments
        app.launch()
        _ = focused(target).waitForExistence(timeout: 30)
        if target.isPlex {
            pause(3)
            remote.press(.select)
        }
        pause(15)

        for round in 1 ... (Int(environment["OPENSTREAM_CMP_WALKS"] ?? "") ?? 5) {
            keepShots = round == 1
            goHome(target)
            shot(target, "0-home")

            // 2. Home → library page: first changed frame, then screen still.
            moveToLibraryTab(target)
            let tabStart = Date()
            let before = signature()
            remote.press(target.isPlex ? .select : .right)
            let firstFrame = firstChange(from: before, start: tabStart, timeout: 10)
            let tabDrawn = settle(start: tabStart, timeout: 20)
            log(target, "tab r\(round) first=\(firstFrame) drawn=\(tabDrawn.ms) settled=\(tabDrawn.settled)")
            shot(target, "2-library")

            // 3. Focus along a full row: 10 moves right.
            enterRow(target)
            log(target, "row r\(round) start '\(focus(target).label)'")
            var moves: [Int] = []
            for _ in 0 ..< 10 {
                moves.append(timedPress(target, .right))
                pause(0.6)
            }
            log(target, "focus r\(round) \(moves.map(String.init).joined(separator: " ")) max=\(moves.max() ?? -1) at '\(focus(target).label)'")
            shot(target, "3-row")

            // 4. Open the comparison title → play button shown → screen still.
            guard findInRow(target, title) else {
                log(target, "title r\(round) '\(title)' not found in the row")
                continue
            }
            pause(1)
            let openStart = Date()
            remote.press(.select)
            let play = target.app.descendants(matching: .any).matching(identifier: target.playIdentifier).firstMatch
            let shown = play.waitForExistence(timeout: 20) ? ms(since: openStart) : -1
            let pageDrawn = settle(start: openStart, timeout: 20)
            log(target, "title r\(round) shown=\(shown) drawn=\(pageDrawn.ms) settled=\(pageDrawn.settled)")
            shot(target, "4-title")

            // 5. Play → first video frame.
            for _ in 0 ..< 4 where play.exists && !play.hasFocus { remote.press(.up); pause(0.8) }
            let page = signature()
            let playStart = Date()
            remote.press(.select)
            // Plex's video never reaches screenshots (its frames stay black), so
            // its first frame comes from the server log's "state playing" report,
            // matched against this wall-clock press time.
            log(target, "play r\(round) pressed epoch=\(String(format: "%.3f", playStart.timeIntervalSince1970))")
            let video = firstVideoFrame(target, page: page, start: playStart, timeout: target.isPlex ? 45 : 30)
            log(target, "play r\(round) firstframe=\(video)")
            shot(target, "5-play")
            pause(3)

            // 6. Back out of playback: title page, then the library page.
            let backStart = Date()
            remote.press(.menu)
            let pageAgain = play.waitForExistence(timeout: 15) ? ms(since: backStart) : -1
            let pageBack = settle(start: backStart, timeout: 15)
            shot(target, "6-title-after")
            let libraryStart = Date()
            remote.press(.menu)
            let libraryDrawn = settle(start: libraryStart, timeout: 20)
            log(target, "back r\(round) page=\(pageAgain) pagedrawn=\(pageBack.ms) library=\(libraryDrawn.ms) settled=\(libraryDrawn.settled)")
            shot(target, "6-library-after")
        }
        app.terminate()
    }

    // MARK: Navigation

    private func focused(_ target: Target) -> XCUIElement {
        target.app.descendants(matching: .any).matching(NSPredicate(format: "hasFocus == true")).firstMatch
    }

    /// The focused element's label and identifier, empty when nothing has
    /// focus (a full-screen player), where reading them would fail the test.
    private func focus(_ target: Target) -> (label: String, id: String) {
        let element = focused(target)
        guard element.exists else { return ("", "") }
        return (element.label, element.identifier)
    }

    /// Focus on the navigation item that opens Home (Plex's sidebar, OpenStream's tab bar).
    private func goHome(_ target: Target) {
        if target.isPlex {
            for _ in 0 ..< 6 where !focus(target).id.hasPrefix("primary-navigation") { remote.press(.left); pause(0.8) }
            for _ in 0 ..< 6 where focus(target).id != "primary-navigation-home" { remote.press(.up); pause(0.8) }
            remote.press(.select)
        } else {
            for _ in 0 ..< 8 where !["Search", "Discover", "Library", "Live", "Settings"].contains(focus(target).label) {
                remote.press(.up); pause(0.8)
            }
            for _ in 0 ..< 5 where focus(target).label != "Discover" {
                remote.press(focus(target).label == "Search" ? .right : .left); pause(0.8)
            }
        }
        pause(3)
    }

    /// Leaves focus one press before the library page: Plex on "Movies" in the
    /// sidebar (select opens it), OpenStream on "Discover" (right opens Library).
    private func moveToLibraryTab(_ target: Target) {
        if target.isPlex {
            for _ in 0 ..< 6 where !focus(target).id.hasPrefix("primary-navigation") { remote.press(.left); pause(0.8) }
            for _ in 0 ..< 6 where focus(target).label != "Movies" { remote.press(.down); pause(0.8) }
        }
        pause(1)
    }

    /// Focus onto the first poster of the walk's row.
    private func enterRow(_ target: Target) {
        pause(1)
        if target.isPlex { return }
        for _ in 0 ..< 6 where focus(target).id != "library.shelf.Movies" { remote.press(.down); pause(1) }
        remote.press(.down)
        pause(1.5)
    }

    private func findInRow(_ target: Target, _ title: String) -> Bool {
        for direction in [XCUIRemote.Button.right, .left] {
            for _ in 0 ..< 40 {
                if focus(target).label.contains(title) { return true }
                let before = focus(target).label
                remote.press(direction)
                pause(0.7)
                if focus(target).label == before { break }
            }
        }
        return focus(target).label.contains(title)
    }

    /// Presses and returns the milliseconds until focus reports a new element.
    private func timedPress(_ target: Target, _ button: XCUIRemote.Button) -> Int {
        let before = focus(target)
        let start = Date()
        remote.press(button)
        while Date().timeIntervalSince(start) < 6, focus(target) == before {}
        return ms(since: start)
    }

    // MARK: Screen stability

    /// A 64×36 grey thumbnail of the whole screen.
    private func signature() -> [UInt8] {
        let image = XCUIScreen.main.screenshot().image
        let width = 64, height = 36
        var pixels = [UInt8](repeating: 0, count: width * height)
        guard let cg = image.cgImage,
              let context = CGContext(data: &pixels, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(),
                                      bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return pixels }
        context.interpolationQuality = .low
        context.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
        return pixels
    }

    private func difference(_ a: [UInt8], _ b: [UInt8]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return 1 }
        var total = 0
        for index in a.indices { total += abs(Int(a[index]) - Int(b[index])) }
        return Double(total) / Double(a.count) / 255
    }

    private func luma(_ a: [UInt8]) -> Double { Double(a.reduce(0) { $0 + Int($1) }) / Double(max(a.count, 1)) / 255 }

    /// Polls until the screen holds still for `quiet` seconds; returns the
    /// milliseconds from `start` to the last change (the midpoint of the
    /// screenshot that first showed the final picture).
    private func settle(start: Date, timeout: TimeInterval, quiet: TimeInterval = 1.5,
                        threshold: Double = 0.006) -> (ms: Int, settled: Bool) {
        var previous = signature()
        var lastChange = Date()
        var lastChangeMs = ms(since: start)
        while Date().timeIntervalSince(start) < timeout {
            let before = Date()
            let current = signature()
            if difference(current, previous) > threshold {
                lastChange = Date()
                lastChangeMs = Int((before.timeIntervalSince(start) + lastChange.timeIntervalSince(start)) * 500)
                previous = current
            } else if Date().timeIntervalSince(lastChange) >= quiet {
                return (lastChangeMs, true)
            }
        }
        return (lastChangeMs, false)
    }

    private func firstChange(from before: [UInt8], start: Date, timeout: TimeInterval) -> Int {
        while Date().timeIntervalSince(start) < timeout {
            let shotStart = Date()
            if difference(signature(), before) > 0.01 {
                return Int((shotStart.timeIntervalSince(start) + Date().timeIntervalSince(start)) * 500)
            }
        }
        return -1
    }

    /// The first moment the picture keeps moving across most of the screen
    /// after leaving the title page: two successive thumbnails differ and
    /// neither is near-black or the page itself. Prints the timeline
    /// (`ms:moved/fromPage/luma/brightest`), which also shows a loading
    /// spinner ending when video frames never reach screenshots.
    private func firstVideoFrame(_ target: Target, page: [UInt8], start: Date, timeout: TimeInterval) -> Int {
        var previous = page
        var previousMs = 0
        var timeline: [String] = []
        defer { log(target, "playtimeline " + timeline.joined(separator: " ")) }
        while Date().timeIntervalSince(start) < timeout {
            let shotStart = Date()
            let current = signature()
            let at = Int((shotStart.timeIntervalSince(start) + Date().timeIntervalSince(start)) * 500)
            let moved = difference(current, previous)
            let fromPage = difference(current, page)
            timeline.append("\(at):\(String(format: "%.3f/%.3f/%.2f/%d", moved, fromPage, luma(current), current.max() ?? 0))")
            if moved > 0.02, fromPage > 0.05, luma(current) > 0.04, luma(previous) > 0.04, previousMs > 0 {
                return previousMs
            }
            if fromPage > 0.05, luma(current) > 0.04 { previousMs = at } else { previousMs = 0 }
            previous = current
            // Each 4K screenshot grows testmanagerd; DevTV kills it at its memory
            // high-water mark during Plex's long buffering.
            if target.isPlex { pause(1) }
        }
        return -1
    }

    // MARK: Output

    private func ms(since start: Date) -> Int { Int(Date().timeIntervalSince(start) * 1000) }

    private func log(_ target: Target, _ line: String) { print("CMPWALK \(target.name) \(line)") }

    private func shot(_ target: Target, _ step: String) {
        guard keepShots else { return }
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot(), quality: .medium)
        attachment.name = "\(target.name)-\(step)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func pause(_ seconds: TimeInterval) { Thread.sleep(forTimeInterval: seconds) }
}
