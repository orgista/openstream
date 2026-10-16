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
