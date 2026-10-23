import XCTest

/// Apple TV Top Shelf, verified on the simulator with no hardware remote.
///
/// A previous pre-ship pass reported the shelf "unverifiable without a
/// physical remote". `XCUIRemote` sends the same HID events the Siri Remote
/// does, so the home screen is drivable from here: launch the app once so
/// `AppleTopShelfPublisher` writes `topshelf-v1.json` into the app group,
/// press Home, walk focus onto the OpenStream icon, and look at what the
/// shelf renders.
@MainActor
final class AppleTVTopShelfUITests: OpenStreamUITestCase {
    private var remote: XCUIRemote { .shared }
    /// tvOS renders the home screen and the Top Shelf in PineBoard; HeadBoard
    /// is the surrounding springboard. Both are queried — whichever exposes
    /// the shelf wins, and the other is only dumped for diagnosis.
    private let pineBoard = XCUIApplication(bundleIdentifier: "com.apple.PineBoard")
    private let headBoard = XCUIApplication(bundleIdentifier: "com.apple.HeadBoard")

    private func watchPartOfATitle(in app: XCUIApplication, matching title: NSPredicate,
                                  inLibrary: Bool = false) -> Bool {
        func focus(_ predicate: NSPredicate, pressing direction: XCUIRemote.Button) -> Bool {
            let target = app.descendants(matching: .any).matching(NSCompoundPredicate(andPredicateWithSubpredicates: [
                NSPredicate(format: "hasFocus == true"), predicate])).firstMatch
            for _ in 0 ..< 12 where !target.exists {
                remote.press(direction)
                _ = target.waitForExistence(timeout: 1.5)
            }
            return target.exists
        }
        if inLibrary {
            for _ in 0..<8 { remote.press(.up) }
            guard focus(NSPredicate(format: "label == 'Library' AND elementType == %d",
                Int(XCUIElement.ElementType.button.rawValue)), pressing: .right) else {
                XCTFail("Library never took focus")
                return false
            }
            remote.press(.select)
        }
        guard app.descendants(matching: .any).matching(title).firstMatch.waitForExistence(timeout: 120) else {
            XCTFail("No playable title appeared")
            return false
        }
        guard focus(title, pressing: .down) else {
            XCTFail("The title never took focus")
            return false
        }
        remote.press(.select)
        guard focus(NSPredicate(format: "identifier == 'detail.play'"), pressing: .right) else {
            XCTFail("Play never took focus")
            return false
        }
        remote.press(.select)
        if inLibrary {
            let elapsed = app.staticTexts.matching(NSPredicate(
                format: "identifier BEGINSWITH 'Elapsed Time' AND label MATCHES %@", #"\d+:\d{2}(:\d{2})?"#)).firstMatch
            for _ in 0..<3 where !elapsed.exists {
                remote.press(.down)
                _ = elapsed.waitForExistence(timeout: 2)
            }
            var initial: Double?
            let advancing = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                guard elapsed.exists else { return false }
                let seconds = elapsed.label.split(separator: ":").reduce(0) { $0 * 60 + (Double($1) ?? 0) }
                guard let start = initial else { initial = seconds; return false }
                return seconds > start
            }, object: nil)
            guard XCTWaiter.wait(for: [advancing], timeout: 60) == .completed else {
                XCTFail("Playback time never advanced")
                return false
            }
            attach("owner-playing")
        } else {
            let ready = app.descendants(matching: .any)["player.playback.ready"].firstMatch
            guard ready.waitForExistence(timeout: 60) else {
                XCTFail("The fixture title never played")
                return false
            }
        }
        Thread.sleep(forTimeInterval: 30)
        remote.press(.menu)
        Thread.sleep(forTimeInterval: 2)
        remote.press(.menu)
        if inLibrary {
            for _ in 0..<8 { remote.press(.up) }
            guard focus(NSPredicate(format: "label == 'Discover' AND elementType == %d",
                Int(XCUIElement.ElementType.button.rawValue)), pressing: .left) else {
                XCTFail("Discover never took focus")
                return false
            }
            remote.press(.select)
        }
        return true
    }

    private func attach(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "diagnostic-topshelf-\(name)"
        shot.lifetime = .keepAlways
        add(shot)
    }

    func testCleanInstallHasNoTopShelfContent() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["OPENSTREAM_TOPSHELF_CLEAN_INSTALL"] == "YES",
                          "Requires the isolated clean-install run")
        let app = XCUIApplication(bundleIdentifier: "com.orgista.openstream")
        app.launchArguments = ["-OpenStreamTrace", "YES"]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 60))
        XCTAssertTrue(app.staticTexts["No Sources"].waitForExistence(timeout: 60))
        XCTAssertFalse(app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH 'home.continue.'")).firstMatch.exists)
        Thread.sleep(forTimeInterval: 25)
        attach("clean-app")
        XCTAssertTrue(focusAppOnHome(), "never managed to focus the oStream icon")
        attach("clean-home")
        let texts = homeScreenTexts()
        XCTAssertFalse(texts.isEmpty, "Home screen accessibility snapshot was unavailable")
        for title in ["top-shelf/swipe-up-affordance/label", "Continue Watching", "Recently Added", "Stub Movie Five"] {
            XCTAssertFalse(texts.contains(title))
        }
    }

    func testTopShelfShowsRealContentWhenTheAppIconIsFocused() {
        // 1. Run the app so the snapshot on disk is current rather than
        //    whatever the last session happened to leave behind.
        let app = XCUIApplication(bundleIdentifier: "com.orgista.openstream")
        app.launchArguments += ["-OpenStreamTrace", "YES"]
        configureFixtureLaunch(app)
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 60), "the app never came to the foreground")
        attach("00-app-running")
        // The shelf lists what was watched here. On the fixtures, watch part of
        // a title from the fixture Jellyfin first (`Tests/Fixtures/serve.py`).
        if ProcessInfo.processInfo.environment["OPENSTREAM_STUB_DIR"]?.isEmpty == false {
            guard watchPartOfATitle(in: app, matching: Self.serverShelfItem("jf-movie-5")) else { return }
        } else if ProcessInfo.processInfo.environment["OPENSTREAM_TOPSHELF_PLAY_OWNER"] == "YES" {
            guard watchPartOfATitle(in: app, matching: NSPredicate(
                format: "identifier BEGINSWITH 'library.title.'"), inLibrary: true) else { return }
        }
        Thread.sleep(forTimeInterval: 25)
        attach("01-app-running")
        let homeTree = XCTAttachment(string: app.debugDescription)
        homeTree.name = "diagnostic-topshelf-home-tree"
        homeTree.lifetime = .keepAlways
        add(homeTree)

        // 2. Home, then leftmost, then step right until OpenStream has focus.
        // A device whose TV button opens the Apple TV app (DevTV) lands there
        // first; a second press goes on to the home screen, which ignores it.
        let focusedOnOpenStream = focusAppOnHome()
        // Give the extension time to be launched and to hand back content.
        Thread.sleep(forTimeInterval: 8)
        attach("03-top-shelf")
        print("TOPSHELF focused element: \(focusedLabel() ?? "<none>")")

        // 3. What the shelf actually put on screen.
        let texts = homeScreenTexts()
        print("TOPSHELF visible strings (\(texts.count)): \(texts.joined(separator: " | "))")
        print("TOPSHELF PineBoard tree:\n\(pineBoard.debugDescription)")

        XCTAssertTrue(focusedOnOpenStream, "never managed to focus the oStream icon on the home screen")
        let expected = ProcessInfo.processInfo.environment["OPENSTREAM_TOPSHELF_EXPECT"]?
            .split(separator: "\u{1f}").map(String.init) ?? []
        // The full-screen carousel (owner 2026-10-15): PineBoard exposes the
        // pages' titles and its own swipe-up affordance, not the context titles.
        let isCarousel = texts.contains("top-shelf/swipe-up-affordance/label")
        // The stubbed title exists only on the simulator's fixtures; a device
        // runs its own sources.
        let stubbed = ProcessInfo.processInfo.environment["OPENSTREAM_STUB_DIR"]?.isEmpty == false
        let wanted = (stubbed ? ["Stub Movie"] : []) + expected
        let hit = wanted.filter { needle in
            texts.contains { $0.localizedCaseInsensitiveContains(needle) }
        }
        print("TOPSHELF carousel: \(isCarousel) matched: \(hit)")
        XCTAssertTrue(isCarousel, "the Top Shelf is not the full-screen carousel")
        XCTAssertTrue(wanted.isEmpty || !hit.isEmpty, "the Top Shelf showed none of \(wanted) — it is empty or stale")

        // 4. Swipe up: the carousel takes the whole screen, and Right moves
        //    to the next page (owner 2026-10-16: "swipe for full screen not working").
        remote.press(.up)
        let fullScreen = waitForHomeScreen {
            // An empty read is a failed snapshot, not a full-screen shelf.
            !$0.isEmpty && !$0.contains("top-shelf/swipe-up-affordance/label")
        }
        attach("04-full-screen")
        print("TOPSHELF full-screen strings (\(fullScreen.count)): \(fullScreen.joined(separator: " | "))")
        XCTAssertFalse(fullScreen.isEmpty || fullScreen.contains("top-shelf/swipe-up-affordance/label"),
                       "Up did not take the shelf full screen")
        remote.press(.right)
        let nextPage = waitForHomeScreen { $0.contains { $0.hasPrefix("page ") } }
        attach("05-next-page")
        print("TOPSHELF next-page strings: \(nextPage.joined(separator: " | "))")
        XCTAssertTrue(nextPage.contains { $0.hasPrefix("page ") }, "Right did not page the full-screen carousel")
        // Deliberately no `press(.home)` here: the run ends with the shelf on
        // screen so a `simctl io screenshot` from outside catches the same frame.
    }

    private func focusAppOnHome() -> Bool {
        remote.press(.home)
        Thread.sleep(forTimeInterval: 4)
        remote.press(.home)
        Thread.sleep(forTimeInterval: 4)
        for _ in 0..<8 { remote.press(.left); Thread.sleep(forTimeInterval: 0.4) }
        remote.press(.up)
        Thread.sleep(forTimeInterval: 2)
        for _ in 0..<8 {
            let focused = focusedLabel()
            if focused?.localizedCaseInsensitiveContains("oStream") == true,
               focused?.localizedCaseInsensitiveContains("UITests") != true { return true }
            remote.press(.right)
            Thread.sleep(forTimeInterval: 1.5)
        }
        return false
    }

    /// From a snapshot: a query on a host with no accessibility server
    /// (hardware) fails the test, a snapshot only throws.
    private func focusedLabel() -> String? {
        for host in [pineBoard, headBoard] {
            guard let snapshot = try? host.snapshot() else { continue }
            var stack = [snapshot]
            while let node = stack.popLast() {
                if node.hasFocus, !node.label.isEmpty { return node.label }
                stack.append(contentsOf: node.children)
            }
        }
        return nil
    }

    /// The home screen's strings once `matches` holds, or the last ones read
    /// when `timeout` runs out (the caller's assertion then fails on them).
    private func waitForHomeScreen(_ matches: ([String]) -> Bool, timeout: TimeInterval = 8) -> [String] {
        let deadline = Date().addingTimeInterval(timeout)
        var texts = homeScreenTexts()
        while !matches(texts), Date() < deadline {
            Thread.sleep(forTimeInterval: 0.5)
            texts = homeScreenTexts()
        }
        return texts
    }

    /// One snapshot of the whole tree per host. Walking `allElementsBoundByIndex`
    /// re-queries per element and the home screen mutates under it — the first
    /// run of this test died on "Failed to get matching snapshot", not on
    /// anything the shelf did.
    private func homeScreenTexts() -> [String] {
        var out: [String] = []
        for host in [pineBoard, headBoard] {
            guard let snapshot = try? host.snapshot() else { continue }
            var stack = [snapshot]
            while let node = stack.popLast() {
                if !node.label.isEmpty { out.append(node.label) }
                if !node.identifier.isEmpty { out.append(node.identifier) }
                if let value = node.value as? String, !value.isEmpty { out.append(value) }
                stack.append(contentsOf: node.children)
            }
        }
        return Array(Set(out)).sorted()
    }
}
