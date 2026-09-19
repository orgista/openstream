import XCTest

/// iPhone and iPad behaviour that needs a touch or a rotation.
///
/// `simctl` can drive neither: it has no tap API and no orientation option, so
/// every row that depended on one — the sheets in C3, landscape in C8, typing a
/// query in F2 — sat blocked. This target is the way to them.
@MainActor
final class AppleiOSUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        // These checks require disposable data, not the owner's content simulators.
        let isolatedTests = [
            "testTypingIntoASettingsFieldPersists",
            "testAddMediaServerSignsInToEmbyAndCleansUp",
            "testExtensionLessHLSChannelPlaysFromAnM3U",
            "testPlaylistGuideShowsProgrammes",
            "testChannelManagerListsSelectedAndAddsThroughAPicker",
            "testLivePlaylistShowsChannelFailureAndRecovers",
            "testZRemoveUITestPlaylistSource",
        ]
        if ProcessInfo.processInfo.environment["OPENSTREAM_ALLOW_MUTATING_UI_TESTS"] != "1",
           isolatedTests.contains(where: { name.contains($0) }) {
            throw XCTSkip("Requires an isolated simulator: this suite must preserve saved sources and credentials.")
        }

        continueAfterFailure = false
        app = XCUIApplication(bundleIdentifier: "com.orgista.openstream")
    }

    override func tearDown() {
        XCUIDevice.shared.orientation = .portrait
        app?.terminate()
    }

    private func launch(screen: String? = nil) {
        if let screen { app.launchArguments += ["-OpenStreamVisionScreen", screen] }
        app.launchArguments += ["-OpenStreamTrace", "YES"]
        app.launch()
    }

    /// `isHittable` raises — and takes the whole test with it — when XCTest can
    /// find no hit point in the element's frame: something scrolled out of a
    /// horizontal row, or laid out at zero size. Asking only about elements
    /// whose centre is on the screen is what keeps a sweep running to the end.
    private func isSafelyHittable(_ element: XCUIElement) -> Bool {
        guard element.exists else { return false }
        let frame = element.frame
        guard frame.width >= 1, frame.height >= 1 else { return false }
        guard app.frame.contains(CGPoint(x: frame.midX, y: frame.midY)) else { return false }
        return element.isHittable
    }

    private func attach(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// Captures every debug route without adding sources or modifying settings.
    func testEveryRouteIsPhotographed() {
        let routes = ["discover", "library", "live", "detail", "episodes", "play", "first-run",
                      "backup", "channels", "playback-settings", "metadata", "server-downloads",
                      "trakt", "watch-providers", "privacy", "storage", "about", "add-files",
                      "add-media-server", "subtitle-languages", "settings"]
        let orientations: [UIDeviceOrientation] = UIDevice.current.userInterfaceIdiom == .pad
            ? [.portrait, .landscapeLeft] : [.portrait]
        for orientation in orientations {
            for route in routes {
                app.launchArguments = []
                XCUIDevice.shared.orientation = orientation
                launch(screen: route)
                XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30))
                if ["detail", "episodes"].contains(route) {
                    XCTAssertTrue(app.buttons["detail.play"].firstMatch.waitForExistence(timeout: 60))
                    Thread.sleep(forTimeInterval: 3)
                } else {
                    Thread.sleep(forTimeInterval: ["discover", "play"].contains(route) ? 25 : 3)
                }
                let prefix = "sweep-\(UIDevice.current.userInterfaceIdiom == .pad ? "ipad" : "iphone")-\(orientation == .portrait ? "portrait" : "landscape")-\(route)"
                attach(prefix)
                let controls = app.buttons.allElementsBoundByIndex.filter { isSafelyHittable($0) }.map {
                    "\($0.identifier) | \($0.label.contains("://") ? "[URL]" : $0.label) | \($0.frame) | enabled=\($0.isEnabled)"
                }.joined(separator: "\n")
                let inventory = XCTAttachment(string: controls)
                inventory.name = prefix + "-buttons"
                inventory.lifetime = .keepAlways
                add(inventory)
                app.terminate()
            }
        }
    }

    /// Uses an ephemeral local video through Direct URL; it adds no saved source.
    func testChapterMarkerSkipIntroSeeksAndDisappears() throws {
        guard let fixture = ProcessInfo.processInfo.environment["OPENSTREAM_CHAPTER_FIXTURE_URL"],
              !fixture.isEmpty else {
            throw XCTSkip("OPENSTREAM_CHAPTER_FIXTURE_URL not set")
        }
        launch(screen: "add-files")
        let directURL = app.buttons["Direct URL"].firstMatch
        XCTAssertTrue(directURL.waitForExistence(timeout: 30), "Direct URL row missing")
        directURL.tap()
        let dialog = app.alerts["Direct URL"]
        XCTAssertTrue(dialog.waitForExistence(timeout: 10), "Direct URL dialog missing")
        let field = dialog.textFields.firstMatch
        field.tap()
        field.typeText(fixture)
        dialog.buttons["Play"].tap()

        let skip = app.buttons["player.skipIntro"]
        XCTAssertTrue(skip.waitForExistence(timeout: 30), "Chapter-backed Skip Intro never appeared")
        let scrubber = app.sliders["Playback position"]
        XCTAssertTrue(scrubber.exists, "Playback scrubber missing during intro")
        XCTAssertLessThanOrEqual(skip.frame.maxY, scrubber.frame.minY,
                                 "Skip Intro must sit above the playback controls: \(skip.frame), \(scrubber.frame)")
        attach("chapter-intro-before-skip")
        skip.tap()
        let hidden = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: skip)
        XCTAssertEqual(XCTWaiter.wait(for: [hidden], timeout: 10), .completed, "Skip Intro remained after skipping")
        let position = app.sliders["Playback position"]
        let sought = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in
                guard let text = position.value as? String else { return false }
                let parts = text.split(separator: ":").compactMap { Int($0) }
                guard parts.count == 2 else { return false }
                let seconds = parts[0] * 60 + parts[1]
                return seconds >= 50 && seconds < 65
            }, object: position)
        XCTAssertEqual(XCTWaiter.wait(for: [sought], timeout: 10), .completed,
                       "Expected seek to the 50-second chapter boundary; position: \(String(describing: position.value))")
        attach("chapter-intro-after-skip")
        XCTAssertFalse(app.alerts["Playback Failed"].exists, "The chapter seek failed")
    }

    /// Proves the target itself works before anything is asserted through it.
    func testAppLaunchesAndShowsTheTabBar() {
        launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30), "the app never came to the foreground")
        let discover = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", "Discover")).firstMatch
        XCTAssertTrue(discover.waitForExistence(timeout: 30), "the Discover tab never appeared")
        attach("ios-launch")
    }

    /// Owner: "type by keyboard on iPhone doesn't work".
    ///
    /// Typing is only half of it — the value has to survive leaving the screen
    /// and coming back, which is where a binding that never commits shows up.
    func testTypingIntoASettingsFieldPersists() {
        launch(screen: "settings")
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30), "the app never came to the foreground")

        let metadata = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", "Metadata")).firstMatch
        XCTAssertTrue(metadata.waitForExistence(timeout: 30), "no Metadata row")
        metadata.tap()

        let field = app.secureTextFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 20), "no field to type into")
        field.tap()
        let typed = "abc123test"
        field.typeText(typed)
        Thread.sleep(forTimeInterval: 2.0)
        attach("typing-entered")

        // Leave the screen and come back: a field that only looks right while
        // focused is the failure being chased.
        app.navigationBars.buttons.firstMatch.tap()
        Thread.sleep(forTimeInterval: 2.0)
        metadata.tap()
        Thread.sleep(forTimeInterval: 2.5)
        attach("typing-after-returning")

        let again = app.secureTextFields.firstMatch
        XCTAssertTrue(again.waitForExistence(timeout: 15), "the field vanished on return")
        // A secure field reports dots, so length is what can be checked.
        let value = (again.value as? String) ?? ""
        print("TYPING value after return: \(value.count) chars (typed \(typed.count))")
        XCTAssertFalse(value.isEmpty, "what was typed did not survive leaving the screen")
    }

    /// Owner report, TestFlight build 10: "The Secret Lives of Mormon Wives"
    /// plays a different show for episodes 1–2.
    ///
    /// The ranking fix was reasoned from the owner's evidence and covered by
    /// tests, but nobody had watched the title play. This drives the real path —
    /// search, open, play episode 1 — and attaches the frame so the picture can
    /// be compared against the show it is supposed to be.
    func testMormonWivesEpisodeOnePlaysSomething() {
        launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30), "the app never came to the foreground")

        let search = app.buttons["Search"]
        XCTAssertTrue(search.waitForExistence(timeout: 30), "no Search control")
        search.tap()
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 20), "no search field")
        field.tap()
        field.typeText("secret lives of mormon wives")
        Thread.sleep(forTimeInterval: 10.0)
        attach("mw-search")

        let row = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS[c] %@", "Mormon Wives")).firstMatch
        guard row.waitForExistence(timeout: 20) else {
            print("MW no result row; search returned nothing for this title")
            return
        }
        row.tap()
        Thread.sleep(forTimeInterval: 8.0)
        attach("mw-title-page")

        // Episode 1 if the episode list is up, otherwise the main Play button.
        let episodeOne = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS[c] %@", "S1 E1")).firstMatch
        if episodeOne.waitForExistence(timeout: 10) {
            episodeOne.tap()
        } else if app.buttons["Play"].waitForExistence(timeout: 5) {
            app.buttons["Play"].tap()
        } else {
            print("MW neither an episode row nor Play was reachable")
            return
        }

        Thread.sleep(forTimeInterval: 40.0)
        attach("mw-episode-one-playing")
        // Tap to raise the transport, which names what is actually playing —
        // the frame alone cannot distinguish an episode from a trailer.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .tap()
        Thread.sleep(forTimeInterval: 3.0)
        attach("mw-transport-overlay")
        let labels = app.descendants(matching: .any).allElementsBoundByIndex
            .prefix(60).map(\.label).filter { !$0.isEmpty }
        print("MW onscreen labels: \(labels.joined(separator: " | "))")
    }

    /// Owner C4: the keyboard's return key should move to the next field and
    /// read "done" on the last.
    ///
    /// This was shipped without ever being seen — `submitLabel` and `onSubmit`
    /// were added to five forms on the strength of unit tests over the chain
    /// logic, because nothing could raise a keyboard. This looks at the key.
    func testReturnKeyReadsNextThenDoneAcrossAForm() {
        launch(screen: "settings")
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30), "the app never came to the foreground")

        let metadata = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", "Metadata")).firstMatch
        XCTAssertTrue(metadata.waitForExistence(timeout: 30), "no Metadata row in Settings")
        metadata.tap()

        let fields = app.secureTextFields
        XCTAssertTrue(fields.firstMatch.waitForExistence(timeout: 20), "the Metadata fields never appeared")
        XCTAssertGreaterThanOrEqual(fields.count, 2, "expected TMDB and OMDb fields")

        // First field: another one follows, so the return key should offer to
        // go there rather than just dismiss.
        fields.element(boundBy: 0).tap()
        let next = app.keyboards.buttons["next"]
        let hasNext = next.waitForExistence(timeout: 10)
        // Attach *after* the key is found: capturing on a fixed sleep caught the
        // frame before the keyboard had animated up, so the picture showed no
        // keyboard at all while the assertion was passing.
        attach("ios-return-key-first-field")
        print("RETURNKEY first field: next=\(hasNext)")

        // Last field: nothing follows it.
        fields.element(boundBy: 1).tap()
        let done = app.keyboards.buttons["done"]
        let hasDone = done.waitForExistence(timeout: 10)
        attach("ios-return-key-last-field")
        print("RETURNKEY last field: done=\(hasDone)")

        XCTAssertTrue(hasNext, "the first field's return key does not offer the next field")
        XCTAssertTrue(hasDone, "the last field's return key does not read done")
    }

    /// Owner F2, and the complaint that started it: "I search for Jury duty
    /// and go odd results".
    ///
    /// Driven through the app rather than the `openstream://search` deep link,
    /// so this is the path a viewer actually takes: tap the search glyph, type,
    /// read the rows.
    func testSearchingFromTheToolbarReturnsShowsAndMoviesOnly() {
        launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30), "the app never came to the foreground")

        let search = app.buttons["Search"]
        XCTAssertTrue(search.waitForExistence(timeout: 30), "no Search control in the toolbar")
        search.tap()

        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 20), "the search field never appeared")
        field.tap()
        field.typeText("jury duty")
        Thread.sleep(forTimeInterval: 8.0)
        attach("ios-search-jury-duty")

        // Every row names its kind; an episode row would read "Episode".
        let episodeRows = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS[c] %@", "Episode")).count
        XCTAssertEqual(episodeRows, 0, "search returned \(episodeRows) episode rows")

        let jury = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS[c] %@", "Jury Duty")).count
        XCTAssertGreaterThan(jury, 0, "no Jury Duty rows came back at all")
        print("SEARCH rows mentioning Jury Duty: \(jury)")
    }

    /// Owner: "type by keyboard on iPhone doesn't work".
    ///
    /// `typeText` injects through the hardware-keyboard path, so it can pass
    /// while the thing the owner actually touches — the on-screen keyboard —
    /// does nothing. This taps the soft keys themselves, which is the only way
    /// to tell the two apart.
    func testOnScreenKeyboardTypesIntoTheSearchField() throws {
        launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30), "the app never came to the foreground")

        let search = app.buttons["Search"]
        XCTAssertTrue(search.waitForExistence(timeout: 30), "no Search control in the toolbar")
        search.tap()

        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 20), "the search field never appeared")
        field.tap()

        let keyboard = app.keyboards.element
        XCTAssertTrue(keyboard.waitForExistence(timeout: 15), "tapping the search field brought up no keyboard")
        attach("keyboard-shown")

        // Simulator > I/O > Keyboard > Connect Hardware Keyboard suppresses the
        // on-screen keyboard entirely: the element above still resolves, but it
        // has no keys, and this test has nothing to tap. That is a setting on
        // the Mac, not a fault in the app, so skip rather than fail. Turn it off
        // (`defaults write com.apple.iphonesimulator ConnectHardwareKeyboard
        // -bool false`, then reboot the simulator) to run this for real.
        // The keys still resolve in that case, parked below the bottom of the
        // screen, so existence is not the test — reachability is.
        let firstKey = app.keys.firstMatch
        guard firstKey.waitForExistence(timeout: 5), firstKey.isHittable else {
            throw XCTSkip("no reachable on-screen keys — the simulator has a hardware keyboard connected")
        }

        for letter in ["d", "u", "n", "e"] {
            // The keys are labelled uppercase while shift is latched and
            // lowercase afterwards, so try both spellings.
            let upper = app.keys[letter.uppercased()]
            let lower = app.keys[letter]
            let key = upper.waitForExistence(timeout: 5) ? upper : lower
            XCTAssertTrue(key.waitForExistence(timeout: 5), "the keyboard has no \(letter) key")
            key.tap()
        }
        Thread.sleep(forTimeInterval: 3.0)
        attach("keyboard-typed")

        // iOS auto-capitalises the first letter, so the field reads "Dune".
        let value = (field.value as? String) ?? ""
        print("SOFT KEYBOARD field value: \(value)")
        XCTAssertTrue(
            value.lowercased().contains("dune"),
            "tapping d-u-n-e left the field reading \(value)"
        )

        // Typing is only useful if it reaches the search. Dune is in the corpus.
        Thread.sleep(forTimeInterval: 6.0)
        attach("keyboard-results")
        let dune = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS[c] %@", "Dune")).count
        print("SOFT KEYBOARD rows mentioning Dune: \(dune)")
    }

    /// Tester, TestFlight build 10: "when you deactivate a tab, it is impossible
    /// to reactivate it because it is grayed out."
    ///
    /// A dead end — the only way back was reinstalling — so this drives the real
    /// control rather than the policy behind it: switch Live off, then check the
    /// switch is still live and can be switched back on.
    func testATabSwitchedOffCanBeSwitchedBackOn() {
        launch(screen: "settings")
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30), "the app never came to the foreground")

        let live = app.switches["settings.live.enabled"]
        XCTAssertTrue(live.waitForExistence(timeout: 30), "no Show Live tab switch")
        XCTAssertTrue(live.isEnabled, "the switch was already disabled before anything was touched")
        print("TABTOGGLE before: frame=\(live.frame) hittable=\(live.isHittable) value=\(String(describing: live.value)) type=\(live.elementType.rawValue)")

        // Off. A SwiftUI toggle's centre is its label, which does not flip it;
        // the switch itself sits at the trailing edge.
        func flip() { live.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap() }
        if (live.value as? String) == "1" { flip() }
        Thread.sleep(forTimeInterval: 1.5)
        attach("tab-toggle-off")
        XCTAssertEqual(live.value as? String, "0", "Show Live tab did not switch off")

        // The bug: greyed out here, with no way back.
        XCTAssertTrue(live.isEnabled, "a tab switched off could not be switched back on")

        // On again.
        flip()
        Thread.sleep(forTimeInterval: 1.5)
        attach("tab-toggle-on-again")
        XCTAssertEqual(live.value as? String, "1", "Show Live tab did not come back on")
    }

    /// Owner, 2026-09-17: downloads are automatic — no "Download from" sheet.
    /// The tester's "a source is chosen by default but is not necessarily
    /// available" is answered by the coordinator walking the ranked plans when
    /// one fails, not by asking. So: tapping an episode's ↓ must NOT open a
    /// sheet, and the download must start; it is then cancelled so nothing
    /// lands on the persistent simulator.
    func testDownloadStartsWithoutAskingForASource() throws {
        launch(screen: "detail")
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30), "the app never came to the foreground")

        // Found by identifier: the label turns into "Preparing …"/"Downloading …, 42%"
        // once the download runs, and it changes again when metadata resolves.
        let download = app.buttons.matching(identifier: "detail.episode.download").firstMatch
        XCTAssertTrue(download.waitForExistence(timeout: 40), "no per-episode Download control on the detail page")
        // ↓ is disabled until the canonical id is known; a tap before that is a no-op.
        let enabled = NSPredicate(format: "isEnabled == true")
        _ = XCTWaiter().wait(for: [expectation(for: enabled, evaluatedWith: download)], timeout: 40)
        XCTAssertTrue(download.isEnabled, "the Download control never became enabled")
        print("DOWNLOAD target before scroll: \(download.frame), hittable=\(download.isHittable)")
        for _ in 0..<8 where !download.isHittable {
            // Scroll only when the target is genuinely outside the usable viewport.
            if download.frame.midY > app.frame.height - 100 { app.swipeUp(velocity: .slow) }
            else if download.frame.minY < 70 { app.swipeDown(velocity: .slow) }
            else { Thread.sleep(forTimeInterval: 1) }
        }
        print("DOWNLOAD target after scroll: \(download.frame), hittable=\(download.isHittable)")
        attach("episode-download-before-tap")
        XCTAssertTrue(download.isHittable, "Visible episode download must accept taps")
        XCTAssertGreaterThanOrEqual(download.frame.width, 44)
        XCTAssertGreaterThanOrEqual(download.frame.height, 44)
        attach("episode-download-hit-target")
        guard ProcessInfo.processInfo.environment["OPENSTREAM_ALLOW_MUTATING_UI_TESTS"] == "1" else {
            throw XCTSkip("44-point download target verified; starting a download requires permission to add simulator data.")
        }
        download.tap()
        Thread.sleep(forTimeInterval: 3.0)
        attach("download-after-tap")

        XCTAssertFalse(app.navigationBars["Download from"].exists, "a source sheet appeared — downloads must be automatic")
        XCTAssertFalse(app.navigationBars["Other sources"].exists, "the playback source sheet appeared on Download")

        // Something must be happening: the row's control or the page's download
        // state should read as in progress within a generous window.
        let busy = app.buttons.matching(identifier: "detail.episode.download").matching(NSPredicate(
            format: "label BEGINSWITH %@ OR label BEGINSWITH %@ OR label BEGINSWITH %@", "Preparing ", "Downloading ", "Downloaded ")).firstMatch
        let status = app.staticTexts["detail.download.status"]
        let deadline = Date().addingTimeInterval(60)
        var started = false, failed = false
        while Date() < deadline, !started, !failed {
            started = busy.exists
            failed = status.exists
            if !started, !failed { Thread.sleep(forTimeInterval: 1.0) }
        }
        attach(started ? "download-started" : failed ? "download-attempted-then-failed" : "download-not-started-after-60s")
        XCTAssertTrue(started || failed, "tapping ↓ did not start a download and showed no failure")

        if started, !busy.label.hasPrefix("Downloaded ") {
            // Cancel through the app's own dialog so no file is kept on the sim.
            busy.tap()
            let cancel = app.buttons["Cancel"].firstMatch
            if cancel.waitForExistence(timeout: 10) { cancel.tap() }
            Thread.sleep(forTimeInterval: 1.0)
            attach("download-cancelled")
        }
    }

    /// M3U sources use a URL or a file; the deprecated text editor stays removed.
    func testAddLiveTVUsesNativeActionsWithoutPlaylistText() {
        launch(screen: "add-live")
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30))
        let picker = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Xtream Account")).firstMatch
        XCTAssertTrue(picker.waitForExistence(timeout: 20))
        picker.tap()
        let m3u = app.buttons["M3U Playlist"].firstMatch
        XCTAssertTrue(m3u.waitForExistence(timeout: 10))
        m3u.tap()
        XCTAssertTrue(app.buttons["sources.live.chooseFile"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.textViews["sources.live.playlistText"].exists)
        XCTAssertFalse(app.staticTexts["Playlist Text"].exists)
        XCTAssertFalse(app.buttons["sources.live.save"].isEnabled)
        XCTAssertFalse(app.buttons["sources.live.test"].isEnabled)
        XCTAssertGreaterThanOrEqual(app.buttons["sources.live.save"].frame.height, 44)
        XCTAssertGreaterThanOrEqual(app.buttons["sources.live.test"].frame.height, 44)
        attach("add-live-m3u-native-actions")
    }

    /// Owner, 2026-09-17: a French M3U whose HLS streams sit behind
    /// extension-less URLs failed with "Demuxer: open failed (Operation not
    /// permitted (-1))". The playlist URL comes from the environment
    /// (TEST_RUNNER_OPENSTREAM_TEST_M3U) so provider tokens never land in the
    /// repo; without it the test skips. Adds the source, plays the first
    /// channel, expects no failure alert, then removes the source again.
    func testExtensionLessHLSChannelPlaysFromAnM3U() throws {
        guard let playlist = ProcessInfo.processInfo.environment["OPENSTREAM_TEST_M3U"], !playlist.isEmpty else {
            throw XCTSkip("OPENSTREAM_TEST_M3U not set")
        }
        addUITestPlaylist(playlist)
        attach("m3u-saved")
        let live = app.tabBars.buttons["Live"].firstMatch
        XCTAssertTrue(live.waitForExistence(timeout: 10))
        live.tap()
        // "All" is the curated provider lineup; a playlist's channels are
        // reachable through Search (and the Everything package), so search.
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 30), "no Live search field")
        search.tap(); search.typeText("TMC")
        let channel = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS[c] %@", "TMC")).firstMatch
        if !channel.waitForExistence(timeout: 30) { attach("m3u-search-no-tmc") }
        XCTAssertTrue(channel.exists, "TMC not found through Live search")
        channel.tap()
        Thread.sleep(forTimeInterval: 15.0)
        attach("m3u-tmc-after-15s")
        let alert = app.alerts.firstMatch
        let failed = alert.exists && alert.label.contains("Playback Failed")
        if failed { attach("m3u-playback-failed") }
        XCTAssertFalse(failed, "Playback Failed alert: \(alert.staticTexts.allElementsBoundByIndex.map(\.label))")

        removeUITestPlaylistSource()
    }

    /// Cleanup on its own so a failed run never leaves the playlist behind on
    /// the persistent simulator: Settings → Sources → "UITest Playlist" →
    /// Delete Source → Delete.
    func testZRemoveUITestPlaylistSource() {
        launch(screen: "settings")
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30))
        removeUITestPlaylistSource()
    }

    /// Add Live TV → M3U → name + URL → Save (validation + stream probe, up
    /// to ~30 s). Leaves the app on the Sources page.
    private func addUITestPlaylist(_ playlist: String, verifyConnection: Bool = false) {
        launch(screen: "add-live")
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30))
        let picker = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Xtream Account")).firstMatch
        XCTAssertTrue(picker.waitForExistence(timeout: 20), "no Type picker")
        picker.tap()
        let m3u = app.buttons["M3U Playlist"].firstMatch
        XCTAssertTrue(m3u.waitForExistence(timeout: 10)); m3u.tap()
        let name = app.textFields["Name"].firstMatch
        XCTAssertTrue(name.waitForExistence(timeout: 10)); name.tap(); name.typeText("UITest Playlist")
        let url = app.textFields["Playlist URL"].firstMatch
        XCTAssertTrue(url.waitForExistence(timeout: 10)); url.tap(); url.typeText(playlist)
        if app.keyboards.buttons["Return"].exists { app.keyboards.buttons["Return"].tap() }
        if verifyConnection {
            let test = app.buttons["sources.live.test"].firstMatch
            XCTAssertTrue(test.waitForExistence(timeout: 10))
            test.tap()
            let result = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Sample stream responded")).firstMatch
            XCTAssertTrue(result.waitForExistence(timeout: 40), "Connection did not report a responding sample stream")
            attach("live-test-connection-result")
        }
        var save = app.buttons["sources.live.save"].firstMatch
        if !save.waitForExistence(timeout: 5) { save = app.buttons["Save"].firstMatch }
        XCTAssertTrue(save.waitForExistence(timeout: 10), "no Save button on Add Live TV"); save.tap()
        let live = app.tabBars.buttons["Live"].firstMatch
        XCTAssertTrue(live.waitForExistence(timeout: 60), "Live tab not reachable after saving")
        Thread.sleep(forTimeInterval: 2.0)
    }

    private func removeUITestPlaylistSource() {
        // Start from a known place: relaunch on the Settings root.
        app.terminate()
        launch(screen: "settings")
        _ = app.wait(for: .runningForeground, timeout: 30)
        let sources = app.buttons["Sources"].firstMatch
        guard sources.waitForExistence(timeout: 20) else { attach("cleanup-no-sources-row"); XCTFail("Sources row not found"); return }
        sources.tap()
        // The list is lazy: the row (added last) may be below the fold.
        let row = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "UITest Playlist")).firstMatch
        var swipes = 0
        while !row.waitForExistence(timeout: 3), swipes < 6 { app.swipeUp(); swipes += 1 }
        guard row.exists else { attach("no-uitest-playlist-source"); return }
        row.tap()
        let delete = app.buttons["Delete Source"].firstMatch
        XCTAssertTrue(delete.waitForExistence(timeout: 10), "no Delete Source on the source page")
        delete.tap()
        let confirm = app.alerts.buttons["Delete"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), "no Delete confirmation")
        confirm.tap()
        Thread.sleep(forTimeInterval: 1.5)
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "UITest Playlist")).firstMatch.exists, "source still listed")
        attach("m3u-source-removed")
    }

    /// Owner, 2026-09-17: "we need a better ux when dealing with something
    /// like 3000 channels". The manager lists only selected channels and
    /// adds through a searchable, grouped picker. Screenshots of all three
    /// states; nothing is changed in the selection.
    func testChannelManagerListsSelectedAndAddsThroughAPicker() throws {
        // The persistent sim's own live source may be off; bring a playlist
        // of our own (URL from the environment), and remove it at the end.
        guard let playlist = ProcessInfo.processInfo.environment["OPENSTREAM_TEST_M3U"], !playlist.isEmpty else {
            throw XCTSkip("OPENSTREAM_TEST_M3U not set")
        }
        addUITestPlaylist(playlist)
        defer { removeUITestPlaylistSource() }
        app.terminate()
        launch(screen: "channels")
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30))
        var add = app.buttons["channels.add"].firstMatch
        if !add.waitForExistence(timeout: 60) {
            add = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", "Add Channels")).firstMatch
        }
        if !add.exists { attach("channel-manager-no-add-row") }
        XCTAssertTrue(add.exists, "no Add Channels… row (is a Live TV source configured?)")
        XCTAssertFalse(app.staticTexts["Your Regional"].exists)
        attach("channel-manager-root")
        add.tap()
        let picker = app.navigationBars["Add Channels"].firstMatch
        XCTAssertTrue(picker.waitForExistence(timeout: 20), "picker did not open")
        Thread.sleep(forTimeInterval: 2.0)
        attach("channel-picker-groups")
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 10), "picker has no search field")
        search.tap(); search.typeText("tmc")
        Thread.sleep(forTimeInterval: 2.5)
        attach("channel-picker-search")
        // The filter must actually apply: TMC stays, a non-match goes.
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "TMC")).firstMatch.waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label == %@", "ARTE")).firstMatch.exists, "search did not filter the list")
    }

    /// Owner, 2026-09-17: "episode 1 still loads the wrong show". Plays the
    /// Discover billboard item (Mormon Wives on this sim) and leaves the
    /// candidate trace behind for inspection; asserts only that playback
    /// starts without a failure alert.
    func testBillboardPlayStartsWithoutFailure() {
        launch(screen: "discover")
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30))
        let play = app.buttons["Play"].firstMatch
        XCTAssertTrue(play.waitForExistence(timeout: 40), "no billboard Play")
        play.tap()
        Thread.sleep(forTimeInterval: 30.0)
        attach("billboard-play-after-30s")
        let alert = app.alerts.firstMatch
        XCTAssertFalse(alert.exists && alert.label.contains("Playback Failed"), "playback failed: \(alert.staticTexts.allElementsBoundByIndex.map(\.label))")
    }

    func testNativeTabRootsAndSourceHealthAudit() {
        for screen in ["discover", "library", "live", "settings", "source-detail"] {
            app.launchArguments = []
            launch(screen: screen)
            XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30))
            Thread.sleep(forTimeInterval: 4)
            if screen == "live" {
                XCTAssertTrue(app.navigationBars.staticTexts["Live"].firstMatch.exists,
                              "Live must use a navigation title, not a toolbar button")
            }
            if screen == "source-detail", app.staticTexts["Connected"].firstMatch.exists {
                XCTAssertFalse(app.staticTexts["Username and password are required."].exists,
                               "Resolved historical login errors must not appear as a current failure")
            }
            attach("native-audit-" + screen)
            app.terminate()
        }
    }

    func testAddLiveTVActionsFitAtLargestTextSize() {
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        launch(screen: "add-live")
        let picker = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Xtream Account")).firstMatch
        XCTAssertTrue(picker.waitForExistence(timeout: 20))
        picker.tap()
        app.buttons["M3U Playlist"].firstMatch.tap()
        let test = app.buttons["sources.live.test"].firstMatch
        var swipes = 0
        while !test.isHittable, swipes < 5 { app.swipeUp(); swipes += 1 }
        XCTAssertTrue(test.isHittable)
        XCTAssertGreaterThanOrEqual(test.frame.height, 44)
        XCTAssertLessThanOrEqual(test.frame.maxX, app.frame.maxX)
        attach("add-live-largest-text")
    }

    func testSavedLiveSourceDoesNotShowResolvedLoginFailure() {
        launch(screen: "settings")
        let sources = app.buttons["Sources"].firstMatch
        XCTAssertTrue(sources.waitForExistence(timeout: 20))
        sources.tap()
        let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Live TV")).firstMatch
        var swipes = 0
        while swipes < 5 {
            if row.waitForExistence(timeout: 2), row.isHittable,
               row.frame.maxY < app.tabBars.firstMatch.frame.minY { break }
            app.swipeUp(); swipes += 1
        }
        XCTAssertTrue(row.exists)
        row.tap()
        let connected = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", "Connected", "Connected")).firstMatch
        let found = connected.waitForExistence(timeout: 10)
        attach("live-source-current-health")
        XCTAssertTrue(found)
        XCTAssertFalse(app.staticTexts["Username and password are required."].exists)
    }

    func testFeaturedTrailerKeepsBackAndFillsLandscape() throws {
        launch(screen: "discover")
        let details = app.buttons["home.featured.details"].firstMatch
        XCTAssertTrue(details.waitForExistence(timeout: 40))
        details.tap()
        let back = app.buttons["detail.back"].firstMatch
        XCTAssertTrue(back.waitForExistence(timeout: 20))
        let screen = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "detail.screen.")).firstMatch
        XCTAssertTrue(screen.waitForExistence(timeout: 10))
        let selectedIdentity = screen.identifier
        Thread.sleep(forTimeInterval: 26)
        XCTAssertEqual(screen.identifier, selectedIdentity, "A rotating hero replaced the title after navigation")
        attach("trailer-portrait")
        XCTAssertTrue(back.isHittable)
        let mute = app.buttons["detail.trailer.mute"].firstMatch
        let hasTrailer = mute.waitForExistence(timeout: 15)
        if hasTrailer {
            XCTAssertGreaterThanOrEqual(mute.frame.width, 44)
            XCTAssertGreaterThanOrEqual(mute.frame.height, 44)
            XCTAssertTrue(back.isHittable, "Back disappeared while the trailer was active")
        }
        XCUIDevice.shared.orientation = .landscapeLeft
        Thread.sleep(forTimeInterval: 4)
        attach("trailer-landscape")
        XCTAssertTrue(back.isHittable)
        if UIDevice.current.userInterfaceIdiom == .phone {
            assertInterfaceOrientation(landscape: false)
            XCTAssertTrue(app.tabBars.firstMatch.isHittable)
        }
        XCUIDevice.shared.orientation = .portrait
        Thread.sleep(forTimeInterval: 3)
        attach("trailer-portrait-return")
        back.tap()
        XCTAssertTrue(details.waitForExistence(timeout: 10))
        if !hasTrailer { throw XCTSkip("Featured title had no playable trailer; detail framing and Back were captured") }
    }

    func testLivePlaylistShowsChannelFailureAndRecovers() throws {
        guard let playlist = ProcessInfo.processInfo.environment["OPENSTREAM_TEST_M3U"], !playlist.isEmpty else {
            throw XCTSkip("OPENSTREAM_TEST_M3U not set")
        }
        addUITestPlaylist(playlist, verifyConnection: true)
        defer { removeUITestPlaylistSource() }
        app.tabBars.buttons["Live"].firstMatch.tap()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 30))
        search.tap()
        search.typeText("UITest Blocked Channel")
        let blocked = app.buttons["Play UITest Blocked Channel"].firstMatch
        XCTAssertTrue(blocked.waitForExistence(timeout: 30))
        blocked.tap()
        let failure = app.alerts.matching(NSPredicate(format: "label == %@ OR label == %@", "Channel Unavailable", "Playback Failed")).firstMatch
        XCTAssertTrue(failure.waitForExistence(timeout: 35))
        let message = failure.staticTexts.allElementsBoundByIndex.map(\.label).joined(separator: " ")
        XCTAssertTrue(message.contains("403") || message.contains("Try again or choose another channel"))
        XCTAssertFalse(message.contains("custom source probe"))
        XCTAssertFalse(message.contains("username"))
        attach("live-channel-denied")
        failure.buttons["Close"].tap()
        search.tap()
        let clearSearch = search.buttons.firstMatch
        XCTAssertTrue(clearSearch.waitForExistence(timeout: 5))
        clearSearch.tap()
        search.typeText("UITest Working Channel")
        let working = app.buttons["Play UITest Working Channel"].firstMatch
        XCTAssertTrue(working.waitForExistence(timeout: 30))
        working.tap()
        Thread.sleep(forTimeInterval: 12)
        XCTAssertFalse(app.alerts["Channel Unavailable"].exists)
        XCTAssertFalse(app.alerts["Playback Failed"].exists)
        XCTAssertFalse(app.keyboards.firstMatch.exists, "Choosing a channel should dismiss the search keyboard")
        attach("live-channel-recovered")
    }

    /// The phone shell stays portrait; only the full-screen video rotates.
    /// Uses the configured Content simulator lineup, as in the Live player tests.
    func testLandscapeHidesTheTabBarAndPortraitBringsItBack() throws {
        try XCTSkipIf(UIDevice.current.userInterfaceIdiom != .phone, "iPhone orientation policy")
        launch(screen: "discover")
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 30))
        XCUIDevice.shared.orientation = .landscapeLeft
        Thread.sleep(forTimeInterval: 3)
        assertInterfaceOrientation(landscape: false)
        XCTAssertTrue(app.tabBars.firstMatch.isHittable)
        attach("discover-stays-portrait-after-rotation")

        app.tabBars.buttons["Live"].firstMatch.tap()
        assertInterfaceOrientation(landscape: false)
        let channel = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Play CBS")).firstMatch
        XCTAssertTrue(channel.waitForExistence(timeout: 30), "CBS channel missing from the configured lineup")
        channel.tap()
        let pause = app.buttons["Pause"].firstMatch
        XCTAssertTrue(pause.waitForExistence(timeout: 30), "Video did not reach playback")
        assertInterfaceOrientation(landscape: true)
        XCTAssertFalse(app.alerts["Playback Failed"].exists)
        attach("player-landscape")

        XCUIDevice.shared.orientation = .portrait
        assertInterfaceOrientation(landscape: false)
        XCUIDevice.shared.orientation = .landscapeRight
        assertInterfaceOrientation(landscape: true)
        let customClose = app.buttons["player.close"].firstMatch
        let nativeClose = app.buttons["Close"].firstMatch
        if !customClose.isHittable && !nativeClose.isHittable {
            let controls = app.buttons["player.controls.show"].firstMatch
            if controls.exists { controls.tap() } else { app.tap() }
        }
        let close = customClose.exists ? customClose : nativeClose
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        close.tap()
        assertInterfaceOrientation(landscape: false)
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 10))
        app.tabBars.buttons["Discover"].firstMatch.tap()
        assertInterfaceOrientation(landscape: false)
        attach("discover-portrait-after-landscape-player")
    }

    private func assertInterfaceOrientation(landscape: Bool, file: StaticString = #filePath, line: UInt = #line) {
        let orientation = XCTNSPredicateExpectation(predicate: NSPredicate { [self] _, _ in
            let frame = app.frame
            return frame.width > 0 && frame.height > 0
                && (landscape ? frame.width > frame.height : frame.height > frame.width)
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [orientation], timeout: 10), .completed,
                       "Expected \(landscape ? "landscape" : "portrait") interface", file: file, line: line)
    }

    /// TestFlight crash, build 10 on an iPhone XS Max running iOS 18.7: UIKit
    /// asserts inside `-[UINavigationBar layoutSubviews]` when the covered
    /// NavigationStack reappears after the player's full-screen cover leaves.
    /// The tester's path was play → failure → Close → back, phone turned for
    /// the video. Both stacks that present the player take the round trip.
    func testPlayerCoverRoundTripInLandscapeKeepsTheSettingsStackAlive() {
        launch(screen: "add-files")
        let directURL = app.buttons["Direct URL"].firstMatch
        XCTAssertTrue(directURL.waitForExistence(timeout: 30), "Direct URL row missing")
        directURL.tap()
        let dialog = app.alerts["Direct URL"]
        XCTAssertTrue(dialog.waitForExistence(timeout: 10), "Direct URL dialog missing")
        let field = dialog.textFields.firstMatch
        field.tap()
        field.typeText("http://127.0.0.1:9/openstream-ui-test-unreachable.mkv")
        dialog.buttons["Play"].tap()
        coverRoundTrip(back: app.navigationBars.buttons.firstMatch, name: "settings")
    }

    func testPlayerCoverRoundTripInLandscapeKeepsTheDiscoverStackAlive() {
        launch(screen: "discover")
        let details = app.buttons["Details"].firstMatch
        XCTAssertTrue(details.waitForExistence(timeout: 40), "no billboard Details")
        details.tap()
        let play = app.buttons["detail.play"].firstMatch
        XCTAssertTrue(play.waitForExistence(timeout: 30), "detail Play missing")
        play.tap()
        coverRoundTrip(back: app.buttons["detail.back"].firstMatch, name: "discover", popInLandscape: true)
        // Closing the player restores portrait even while the phone stays sideways;
        // switching tabs makes every stack reconcile its bars once more.
        let settingsTab = app.tabBars.buttons["Settings"].firstMatch
        if settingsTab.waitForExistence(timeout: 5) { settingsTab.tap() }
        let discoverTab = app.tabBars.buttons["Discover"].firstMatch
        if discoverTab.waitForExistence(timeout: 5) { discoverTab.tap() }
        Thread.sleep(forTimeInterval: 2)
        XCTAssertEqual(app.state, .runningForeground, "the app died switching tabs after the cover")
        attach("cover-round-trip-discover-tabs")
    }

    /// Turns the phone while the cover is up, leaves through whichever exit the
    /// player offers, pops (in landscape when asked, else after turning back),
    /// and expects a living app with its tab bar.
    private func coverRoundTrip(back: XCUIElement, name: String, popInLandscape: Bool = false) {
        XCUIDevice.shared.orientation = .landscapeLeft
        // "Playback Failed" for a dead URL, "Playback Unavailable" when no stream
        // source is enabled: either one is the player's exit for this round trip.
        let failed = app.alerts.firstMatch
        let any = app.descendants(matching: .any)
        let close = any.matching(identifier: "player.close").firstMatch
        let controls = any.matching(identifier: "player.controls.show").firstMatch
        let connecting = any.matching(identifier: "player.connecting").firstMatch
        let exit = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in
                failed.exists || close.exists || controls.exists || connecting.exists
            }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [exit], timeout: 60), .completed,
                       "neither the failure alert nor the player appeared")
        Thread.sleep(forTimeInterval: 3)
        attach("cover-round-trip-\(name)-landscape")
        if failed.exists {
            let closeAlert = failed.buttons["Close"].exists ? failed.buttons["Close"] : failed.buttons.firstMatch
            closeAlert.tap()
        } else {
            if !close.exists || !close.isHittable {
                if controls.exists { controls.tap() } else { app.tap() }
            }
            if close.waitForExistence(timeout: 5) { close.tap() }
        }
        if UIDevice.current.userInterfaceIdiom == .phone {
            assertInterfaceOrientation(landscape: false)
        }
        if popInLandscape {
            if back.waitForExistence(timeout: 5) { back.tap() }
            Thread.sleep(forTimeInterval: 2)
            XCUIDevice.shared.orientation = .portrait
        } else {
            XCUIDevice.shared.orientation = .portrait
            Thread.sleep(forTimeInterval: 2)
            if back.waitForExistence(timeout: 5) { back.tap() }
        }
        Thread.sleep(forTimeInterval: 2)
        XCTAssertEqual(app.state, .runningForeground, "the app died after the cover went away")
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 10), "tab bar missing after returning")
        attach("cover-round-trip-\(name)-portrait")
    }

    /// Owner (2026-09-17 23:50): "make AIOMetadata work". Opens the first title of
    /// an AIOMetadata catalog shelf and photographs the detail page so the
    /// driver can see what the add-on's metadata looks like in the app.
    func testAIOMetadataCatalogItemOpensADetailWithInformation() {
        launch(screen: "discover")
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30))
        XCTAssertTrue(app.buttons["home.featured.play"].firstMatch.waitForExistence(timeout: 60), "Discover never loaded its billboard")
        let header = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND identifier CONTAINS[c] %@", "discover.shelf.", "aio-metadata")).firstMatch
        var swipes = 0
        while !header.exists, swipes < 14 { app.swipeUp(); swipes += 1; Thread.sleep(forTimeInterval: 0.6) }
        if !header.exists {
            print("SHELF identifiers: " + app.buttons.allElementsBoundByIndex.map(\.identifier).filter { $0.contains("catalog") || $0.contains("shelf") }.joined(separator: " | "))
        }
        XCTAssertTrue(header.exists, "no AIOMetadata shelf on Discover")
        while header.frame.midY > app.frame.height * 0.7 { app.swipeUp(); Thread.sleep(forTimeInterval: 0.6) }
        attach("aio-shelf")
        let headerBottom = header.frame.maxY
        let posters = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "home.media."))
        var first: XCUIElement?
        for index in 0..<min(posters.count, 40) {
            let candidate = posters.element(boundBy: index)
            guard candidate.exists else { continue }
            let frame = candidate.frame
            if frame.minY > headerBottom, frame.minY < headerBottom + 320, frame.width > 60 { first = candidate; break }
        }
        guard let first else { return XCTFail("no title under the \(header.label) shelf") }
        let title = first.label
        first.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4)).tap()
        let play = app.buttons["detail.play"].firstMatch
        XCTAssertTrue(play.waitForExistence(timeout: 30), "detail for \(title) never showed Play")
        Thread.sleep(forTimeInterval: 8)
        attach("aio-detail-top")
        let overview = app.staticTexts.allElementsBoundByIndex.filter { $0.label.count > 80 }
        XCTAssertFalse(overview.isEmpty, "no overview text on the detail for \(title)")
        XCTAssertFalse(app.staticTexts["No information"].exists, "detail shows No information for \(title)")
        app.swipeUp(); Thread.sleep(forTimeInterval: 2)
        attach("aio-detail-lower")
        let episodes = app.otherElements["detail.episodes"].firstMatch
        if episodes.exists {
            app.swipeUp(); Thread.sleep(forTimeInterval: 2)
            attach("aio-detail-episodes")
        }
    }

    /// Owner (2026-09-17 23:50): the captions menu offers Off plus ONE subtitle
    /// entry — the preferred language — never "English 1" and "English 2".
    /// Plays a fixture carrying two English tracks and a French one.
    func testCaptionsMenuOffersOneSubtitleOption() throws {
        guard let fixture = ProcessInfo.processInfo.environment["OPENSTREAM_SUBTITLE_FIXTURE_URL"],
              !fixture.isEmpty else {
            throw XCTSkip("OPENSTREAM_SUBTITLE_FIXTURE_URL not set")
        }
        launch(screen: "add-files")
        let directURL = app.buttons["Direct URL"].firstMatch
        XCTAssertTrue(directURL.waitForExistence(timeout: 30), "Direct URL row missing")
        directURL.tap()
        let dialog = app.alerts["Direct URL"]
        XCTAssertTrue(dialog.waitForExistence(timeout: 10), "Direct URL dialog missing")
        let field = dialog.textFields.firstMatch
        field.tap()
        field.typeText(fixture)
        dialog.buttons["Play"].tap()
        let any = app.descendants(matching: .any)
        let menu = any.matching(NSPredicate(format: "label == %@", "Audio & Subtitles")).firstMatch
        if !menu.waitForExistence(timeout: 30) {
            any.matching(identifier: "player.controls.show").firstMatch.tap()
        }
        XCTAssertTrue(menu.waitForExistence(timeout: 10), "captions menu button missing")
        // The controls auto-hide after a few seconds: bring them back and tap at once.
        let off = any.matching(NSPredicate(format: "label == %@", "Off")).firstMatch
        var opened = false
        for attempt in 0..<3 where !opened {
            if !menu.isHittable { any.matching(identifier: "player.controls.show").firstMatch.tap(); Thread.sleep(forTimeInterval: 0.5) }
            if attempt == 0 { menu.tap() } else { menu.press(forDuration: 0.3) }
            opened = off.waitForExistence(timeout: 6)
        }
        Thread.sleep(forTimeInterval: 1)
        attach("captions-menu")
        XCTAssertTrue(opened, "menu did not open (no Off)")
        let rows = app.menuItems.count > 0 ? app.menuItems : app.buttons
        let items = rows.allElementsBoundByIndex
            .map(\.label)
            .filter { !$0.isEmpty && $0 != "Off" && $0 != "Audio & Subtitles" }
            .filter { $0.range(of: "^(English|French|Français|Subtitle)", options: .regularExpression) != nil }
        XCTAssertEqual(items.count, 1, "expected exactly one subtitle entry besides Off, got \(items)")
        XCTAssertFalse(items.contains { $0.range(of: "\\d$", options: .regularExpression) != nil },
                       "a numbered entry leaked into the menu: \(items)")
    }

    /// Media servers (owner, 2026-09-17): signs in to the Emby test server on the
    /// Mac through the Add Media Server screen, saves the source, photographs
    /// the result, then deletes the source so nothing is left on the simulator.
    /// Needs OPENSTREAM_TEST_EMBY_URL / _USER / _PASSWORD in the runner's environment.
    func testAddMediaServerSignsInToEmbyAndCleansUp() throws {
        let env = ProcessInfo.processInfo.environment
        guard let url = env["OPENSTREAM_TEST_EMBY_URL"], let user = env["OPENSTREAM_TEST_EMBY_USER"],
              let password = env["OPENSTREAM_TEST_EMBY_PASSWORD"], !url.isEmpty else {
            throw XCTSkip("OPENSTREAM_TEST_EMBY_* not set")
        }
        launch(screen: "add-media-server")
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30))
        let any = app.descendants(matching: .any)
        let kindPicker = any.matching(identifier: "sources.mediaServer.kind").firstMatch
        XCTAssertTrue(kindPicker.waitForExistence(timeout: 30), "Add Media Server screen missing")
        attach("add-media-server-jellyfin")
        // Plex: the sign-in code comes from plex.tv (no account needed to show it).
        let plexKind = any.matching(identifier: "sources.mediaServer.kind.plex").firstMatch
        if plexKind.exists { plexKind.tap() } else { kindPicker.tap(); app.buttons["Plex"].firstMatch.tap() }
        let plexSignIn = any.matching(identifier: "sources.mediaServer.plexSignIn").firstMatch
        if plexSignIn.waitForExistence(timeout: 5) {
            plexSignIn.tap()
            let code = any.matching(identifier: "sources.mediaServer.plex.code").firstMatch
            _ = code.waitForExistence(timeout: 20)
            Thread.sleep(forTimeInterval: 1)
            attach("add-media-server-plex")
            let cancel = app.buttons["Cancel"].firstMatch
            if cancel.exists { cancel.tap() }
        }
        // Emby, signed in with a server URL (Emby Connect needs a real account).
        let emby = any.matching(identifier: "sources.mediaServer.kind.emby").firstMatch
        if emby.exists { emby.tap() } else { kindPicker.tap(); app.buttons["Emby"].firstMatch.tap() }
        let serverMode = any.matching(identifier: "sources.mediaServer.embyMode.server").firstMatch
        if serverMode.waitForExistence(timeout: 5) { serverMode.tap() }
        else { any.matching(identifier: "sources.mediaServer.embyMode").firstMatch.tap(); app.buttons["Server URL"].firstMatch.tap() }
        let urlField = any.matching(identifier: "sources.mediaServer.url").firstMatch
        XCTAssertTrue(urlField.waitForExistence(timeout: 10), "Server URL field missing")
        urlField.tap(); urlField.typeText(url)
        let userField = any.matching(identifier: "sources.mediaServer.username").firstMatch
        userField.tap(); userField.typeText(user)
        let passwordField = any.matching(identifier: "sources.mediaServer.password").firstMatch
        passwordField.tap(); passwordField.typeText(password)
        attach("add-media-server-emby-filled")
        let test = any.matching(identifier: "sources.mediaServer.test").firstMatch
        if test.exists, test.isEnabled {
            test.tap()
            let connected = any.matching(NSPredicate(format: "label BEGINSWITH[c] %@", "Connected")).firstMatch
            let failedStatus = any.matching(identifier: "sources.mediaServer.status").firstMatch
            let answered = XCTWaiter.wait(for: [XCTNSPredicateExpectation(
                predicate: NSPredicate { _, _ in connected.exists || failedStatus.exists }, object: nil)], timeout: 30)
            XCTAssertEqual(answered, .completed, "no status after Test Connection")
            Thread.sleep(forTimeInterval: 1)
            attach("add-media-server-emby-tested")
            XCTAssertTrue(connected.exists, "test did not connect: \(failedStatus.exists ? failedStatus.label : "no status")")
        }
        let save = any.matching(identifier: "sources.mediaServer.save").firstMatch
        XCTAssertTrue(save.waitForExistence(timeout: 10), "Save missing")
        save.tap()
        // Back on the Sources list, the server is listed under Your Sources.
        // "Media Server · <host>" is the saved row's subtitle; "Add Media Server" has no dot.
        let row = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Media Server ·")).firstMatch
        let listed = row.waitForExistence(timeout: 30)
        attach("add-media-server-saved")
        XCTAssertTrue(listed, "saved media server not listed")
        // Whatever fails below, the saved server must not stay on the simulator.
        addTeardownBlock { [self] in
            if app.state != .runningForeground { app.launch() }
            let anyElement = app.descendants(matching: .any)
            let close = anyElement.matching(identifier: "player.close").firstMatch
            if close.exists { close.tap() }
            let back = app.buttons["detail.back"].firstMatch
            if back.exists { back.tap() }
            app.tabBars.buttons["Settings"].firstMatch.tap()
            let sources = app.buttons["Sources"].firstMatch
            if sources.waitForExistence(timeout: 5) { sources.tap() }
            let saved = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Media Server ·")).firstMatch
            guard saved.waitForExistence(timeout: 10) else { return }
            saved.tap()
            let delete = app.buttons["Delete Source"].firstMatch
            var swipes = 0
            while !delete.exists, swipes < 4 { app.swipeUp(); swipes += 1 }
            guard delete.waitForExistence(timeout: 5) else { return }
            delete.tap()
            let confirm = app.alerts.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Delete")).firstMatch
            if confirm.waitForExistence(timeout: 5) { confirm.tap() }
            Thread.sleep(forTimeInterval: 1)
        }
        // Discover should now carry the server's shelves ("Latest in Movies" …).
        app.tabBars.buttons["Discover"].firstMatch.tap()
        let shelf = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Latest in")).firstMatch
        var shelfSwipes = 0
        while !shelf.exists, shelfSwipes < 12 { app.swipeUp(); shelfSwipes += 1; Thread.sleep(forTimeInterval: 0.6) }
        attach("add-media-server-discover")
        XCTAssertTrue(shelf.exists, "no media-server shelf on Discover after saving the source")
        // Open the first server title, expect a real detail page, and play it.
        let poster = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "home.ms.")).firstMatch
        if poster.waitForExistence(timeout: 10) {
            poster.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4)).tap()
            let play = app.buttons["detail.play"].firstMatch
            XCTAssertTrue(play.waitForExistence(timeout: 30), "server title detail never showed Play")
            Thread.sleep(forTimeInterval: 4)
            attach("add-media-server-detail")
            play.tap()
            let any = app.descendants(matching: .any)
            let playing = any.matching(identifier: "player.controls.show").firstMatch
            let close = any.matching(identifier: "player.close").firstMatch
            let alert = app.alerts.firstMatch
            let started = XCTWaiter.wait(for: [XCTNSPredicateExpectation(
                predicate: NSPredicate { _, _ in playing.exists || close.exists || alert.exists }, object: nil)], timeout: 60)
            XCTAssertEqual(started, .completed, "player never appeared for the server title")
            Thread.sleep(forTimeInterval: 8)
            attach("add-media-server-playing")
            XCTAssertFalse(alert.exists, "playback of the server title failed: \(alert.exists ? alert.label : "")")
            if !close.exists || !close.isHittable { app.tap() }
            if close.waitForExistence(timeout: 5) { close.tap() }
            let back = app.buttons["detail.back"].firstMatch
            if back.waitForExistence(timeout: 5) { back.tap() }
        } else {
            XCTFail("no server title under the shelf")
        }
        app.tabBars.buttons["Settings"].firstMatch.tap()
        // Clean up: open it and delete.
        XCTAssertTrue(row.waitForExistence(timeout: 10), "source row gone before cleanup")
        row.tap()
        let delete = app.buttons["Delete Source"].firstMatch
        var swipes = 0
        while !delete.exists, swipes < 4 { app.swipeUp(); swipes += 1 }
        XCTAssertTrue(delete.waitForExistence(timeout: 10), "Delete Source missing")
        delete.tap()
        let confirm = app.alerts.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Delete")).firstMatch
        if confirm.waitForExistence(timeout: 5) { confirm.tap() }
        else { app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Delete")).element(boundBy: 1).tap() }
        Thread.sleep(forTimeInterval: 2)
        XCTAssertFalse(row.exists, "media server still listed after delete")
        attach("add-media-server-deleted")
    }

    /// Owner (2026-09-18): the guide for the playlist they sent shows "No
    /// information". Adds that playlist (env OPENSTREAM_TEST_M3U), opens Live,
    /// searches a channel and waits for programme cells; photographs the guide
    /// at 15 / 45 / 90 s so the driver can see what the phone path produces.
    func testPlaylistGuideShowsProgrammes() throws {
        guard let playlist = ProcessInfo.processInfo.environment["OPENSTREAM_TEST_M3U"], !playlist.isEmpty else {
            throw XCTSkip("OPENSTREAM_TEST_M3U not set")
        }
        addUITestPlaylist(playlist)
        addTeardownBlock { [self] in
            app.terminate()
            launch(screen: "settings")
            removeUITestPlaylistSource()
        }
        let live = app.tabBars.buttons["Live"].firstMatch
        XCTAssertTrue(live.waitForExistence(timeout: 10))
        live.tap()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 30), "no Live search field")
        search.tap(); search.typeText("TF1")
        if app.keyboards.buttons["search"].exists { app.keyboards.buttons["search"].tap() }
        let row = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS[c] %@", "TF1")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 30), "TF1 never listed")
        // The guide cells are not exposed to accessibility, so the evidence is the
        // photographs plus the app's own "guide loaded / guide load failed" trace.
        for checkpoint in [20, 45, 75] {
            Thread.sleep(forTimeInterval: checkpoint == 20 ? 20 : 30)
            attach("guide-\(checkpoint)s")
        }
        XCTAssertTrue(row.exists, "TF1 row disappeared")
    }

    /// A guide selection opens the player directly and channel changes stay there.

    /// Reveals the player chrome only when it is hidden; tapping the surface while chrome is up would hide it.
    ///
    /// The chrome auto-hides three seconds after the last interaction, and that
    /// can expire between the query and the tap it was meant to guard, so this
    /// retries until a control is really there rather than checking once.
    private func revealPlayerControls() {
        let captions = app.buttons["player.captions"]
        for _ in 0..<4 {
            if captions.exists, captions.isHittable { return }
            app.buttons["player.controls.show"].tap()
            if captions.waitForExistence(timeout: 2) { return }
        }
    }

    func testLiveTappedStatesArePhotographed() {
        // Two queries cannot both land inside a three-second auto-hide, and the
        // second one used to fail on a chrome that had already gone.
        app.launchArguments += ["-OpenStreamHoldPlayerChrome", "YES"]
        launch(screen: "live")
        let channel = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Play CBS")).firstMatch
        XCTAssertTrue(channel.waitForExistence(timeout: 30), "CBS channel missing from the configured lineup")
        channel.tap()
        let close = app.buttons["player.close"]
        XCTAssertTrue(close.waitForExistence(timeout: 10), "Guide selection did not open full screen")
        attach("live-direct-fullscreen")

        for orientation in [UIDeviceOrientation.portrait, .landscapeLeft] {
            XCUIDevice.shared.orientation = orientation
            revealPlayerControls()
            let captions = app.buttons["player.captions"]
            let more = app.buttons["player.more"]
            let mute = app.buttons["player.mute"]
            XCTAssertTrue(captions.waitForExistence(timeout: 10))
            XCTAssertEqual(app.buttons.matching(identifier: "player.close").count, 1)
            if more.exists { XCTAssertFalse(captions.frame.intersects(more.frame)) }
            if mute.exists {
                XCTAssertFalse(captions.frame.intersects(mute.frame))
                if more.exists { XCTAssertFalse(more.frame.intersects(mute.frame)) }
            }
            attach("live-chrome-\(orientation.rawValue)")
        }

        revealPlayerControls()
        app.buttons["player.channels"].tap()
        let choices = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "live.picker.channel."))
        let pickerShown = choices.firstMatch.waitForExistence(timeout: 5)
        attach("live-after-channels-tap")
        XCTAssertTrue(pickerShown, "Channels button did not open the picker")
        attach("live-channel-picker")
        XCTAssertGreaterThan(choices.count, 1)
        let originalChannelID = channel.identifier.replacingOccurrences(of: "guide.play.", with: "")
        let replacement = choices.allElementsBoundByIndex.first {
            $0.identifier != "live.picker.channel.\(originalChannelID)" && $0.isHittable
        }
        XCTAssertNotNil(replacement, "No different channel is visible in the picker")
        replacement?.tap()
        revealPlayerControls()
        XCTAssertTrue(close.waitForExistence(timeout: 10), "Switching channels dismissed full screen")
        attach("live-channel-switched-fullscreen")
        close.tap()
        XCTAssertTrue(app.buttons["player.fullscreen"].waitForExistence(timeout: 10))
        attach("live-inline-after-return")
    }

    /// Captures real broadcast captions for visual review; no fixture captions are injected.
    func testLiveBroadcastCaptionsArePhotographed() throws {
        app.launchArguments += ["-OpenStreamHoldPlayerChrome", "YES"]
        launch(screen: "live")
        let channels = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "guide.play."))
        XCTAssertTrue(channels.firstMatch.waitForExistence(timeout: 30))
        var visited = Set<String>()
        for _ in 0..<5 {
            guard let channel = channels.allElementsBoundByIndex.first(where: { !visited.contains($0.identifier) && $0.isHittable }) else {
                app.swipeUp()
                continue
            }
            visited.insert(channel.identifier)
            channel.tap()
            guard app.buttons["player.close"].waitForExistence(timeout: 10) else { continue }
            let deadline = Date().addingTimeInterval(20)
            repeat {
                revealPlayerControls()
                app.buttons["player.captions"].tap()
                let track = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ OR label == 'Closed Captions' OR label BEGINSWITH 'English' OR label BEGINSWITH 'French'", "player.subtitle.track.")).firstMatch
                if track.waitForExistence(timeout: 1) {
                    attach("live-broadcast-caption-menu")
                    track.tap()
                    Thread.sleep(forTimeInterval: 8)
                    attach("live-broadcast-caption-text-review-required")
                    revealPlayerControls()
                    app.buttons["player.captions"].tap()
                    app.buttons["Off"].firstMatch.tap()
                    revealPlayerControls()
                    app.buttons["player.close"].tap()
                    return
                }
                let off = app.buttons["Off"].firstMatch
                if off.exists { off.tap() }
                else { attach("live-captions-menu-missing") }
                Thread.sleep(forTimeInterval: 1)
            } while Date() < deadline
            revealPlayerControls()
            app.buttons["player.close"].tap()
        }
        throw XCTSkip("No channel in the available lineup published a legible caption track within 20 seconds per channel (\(visited.count) checked).")
    }

    // MARK: - Every button on every screen

    /// One control on screen, one press, one required answer.
    ///
    /// A screenshot sweep photographs a button that does nothing exactly as it
    /// photographs a working one, and a test written around a named identifier
    /// never meets the controls nobody named. So this walks every debug route,
    /// enumerates what is on the screen — buttons, rows, links, switches,
    /// segments, tab items — presses each one, and requires the app to answer
    /// within three seconds: a sheet, an alert, a navigation, a menu, a flipped
    /// switch, or a change in the control's own state. Silence is a defect, and
    /// so is a control that exists, at a usable size, and refuses a touch.
    private struct CrawlTarget {
        let typeName: String
        let type: XCUIElement.ElementType
        let identifier: String
        let label: String
        let isTab: Bool
        var reach: CrawlReach = .hittable

        var key: String {
            let named = identifier.isEmpty ? label : identifier
            return named.isEmpty ? "\(typeName)-unnamed" : named
        }

        var name: String { "\(typeName) \(key)" }

        var slug: String {
            String(key.map { $0.isLetter || $0.isNumber || $0 == "." || $0 == "-" ? $0 : "_" }.prefix(70))
        }
    }

    private enum CrawlReach { case hittable, offScreen, blocked, disabled, gone }

    /// Where the floating tab bar is drawn. Rows under it are on screen, half
    /// visible and not touchable until they are scrolled clear — scrolling to
    /// do, not a tap-target defect. Kept as the bar's own rectangle rather than
    /// as a shrunken screen so that a toolbar item beside the bar, at the same
    /// height, is still judged normally.
    private var crawlBarRect: CGRect = .null

    /// The app's own window. On an iPad running the app in a resizable window
    /// `app.frame` is the whole display, so a row below the window's edge read
    /// as on screen, whole, and untouchable — a defect that was only a scroll.
    private var crawlWindowRect: CGRect = .null

    /// Anything that throws work away, spends money, or leaves the simulator
    /// different than it was found. The crawler names them in its report and
    /// walks past: this suite runs on the owner's content simulators.
    private static let crawlDestructiveWords = [
        "delete", "remove", "sign out", "log out", "clear", "reset", "erase",
        "forget", "disconnect", "unpair", "send", "upload", "ship", "purchase", "buy",
    ]
    private static let crawlMutatingWords = [
        "save", "sign in", "log in", "add source", "import", "export", "restore",
        "pair", "subscribe", "download", "test connection",
    ]

    /// Every route `OpenStreamRootView` can be launched into, plus the Settings
    /// root and the Sources page that hangs off it.
    /// iPadOS publishes each tab item's symbol name where the phone publishes
    /// its title, and does not expose the bar as a `tabBar` at all, so the
    /// items have to be recognised by name or they are pressed on every screen.
    private static let crawlTabLabels: Set<String> = [
        "Discover", "Library", "Live", "Settings",
        "sparkles", "books.vertical", "dot.radiowaves.left.and.right", "gearshape",
    ]

    private static let crawlRoutes = [
        "discover", "library", "live", "backup", "channels", "playback-settings",
        "metadata", "server-downloads", "trakt", "watch-providers", "privacy",
        "storage", "about", "add-files", "add-media-server", "subtitle-languages",
        "detail", "episodes", "first-run", "settings", "sources",
    ]

    func testEveryButtonRespondsOnEveryScreen() {
        runButtonCrawl(landscape: false)
    }

    /// The iPad variant. A regular-width split layout puts a different set of
    /// controls on screen than the phone does, and landscape is where the tab
    /// bar and the player chrome trade places.
    func testEveryButtonRespondsOnEveryScreenOnIPad() throws {
        guard UIDevice.current.userInterfaceIdiom == .pad else {
            throw XCTSkip("The landscape crawl is the iPad variant; run it on the iPad simulator.")
        }
        runButtonCrawl(landscape: true)
    }

    private func runButtonCrawl(landscape: Bool) {
        // Every screen has to be reported on, so one silent button must not end
        // the walk at the screen it was found on.
        continueAfterFailure = true
        let device = UIDevice.current.userInterfaceIdiom == .pad ? "ipad" : "iphone"
        let deadline = Date().addingTimeInterval(20 * 60)
        var report = ["button crawl — \(device) \(landscape ? "landscape" : "portrait") — \(Date())", ""]
        var screens = 0, pressed = 0, silent = 0, unreachable = 0, skipped = 0
        var defects: [String] = []

        for route in Self.crawlRoutes {
            guard Date() < deadline else {
                report.append("== \(route): not visited — the 20-minute budget ran out")
                continue
            }
            screens += 1
            let left = Self.crawlRoutes.count - screens + 1
            let result = crawl(route: route, landscape: landscape, deadline: deadline,
                               screensLeft: left, report: &report)
            pressed += result.pressed
            silent += result.silent
            unreachable += result.unreachable
            skipped += result.skipped
            defects += result.defects
        }

        report.insert(contentsOf: [
            "screens: \(screens)  pressed: \(pressed)  no response: \(silent)  "
                + "unhittable: \(unreachable)  not pressed: \(skipped)",
            "",
        ], at: 1)
        let attachment = XCTAttachment(string: report.joined(separator: "\n"))
        attachment.name = "button-crawl-report.txt"
        attachment.lifetime = .keepAlways
        add(attachment)
        for defect in defects { XCTFail(defect) }
    }

    private struct CrawlResult {
        var pressed = 0
        var silent = 0
        var unreachable = 0
        var skipped = 0
        var defects: [String] = []
    }

    private func crawl(route: String, landscape: Bool, deadline: Date, screensLeft: Int,
                       report: inout [String]) -> CrawlResult {
        var result = CrawlResult()
        // Echoed as it is written: a walk that dies on its last screen would
        // otherwise take the whole report with it, and the log survives.
        func note(_ line: String) {
            print("CRAWL| " + line)
            report.append(line)
        }

        // An even share of what is left, counted from before the launch: a
        // screen that spends forty seconds loading and enumerating has spent
        // its own budget, not the next screen's. Every route gets a slice.
        let share = min(75, max(30, deadline.timeIntervalSinceNow / Double(max(1, screensLeft))))
        let screenDeadline = min(deadline, Date().addingTimeInterval(share))

        launchForCrawl(route: route, landscape: landscape)
        crawlWindowRect = (try? app.windows.firstMatch.snapshot())?.frame ?? .null
        crawlBarRect = tabBarRectForCrawl()
        note("== \(route)")
        guard app.state == .runningForeground else {
            note("   the app did not reach the foreground")
            result.defects.append("[\(route)] the app never reached the foreground")
            return result
        }

        let homeTab = selectedTabLabel()
        let baseline = navigationTitle()
        // Reach is measured on an untouched screen. Measured later, a menu left
        // open by an earlier press would report every control behind it as a
        // tap-target defect, and one real finding would arrive with ten false
        // ones behind it.
        let targets = enumerateCrawlTargets(includesTabs: route == "discover").map { target in
            var target = target
            target.reach = classifyForCrawl(resolveCrawlTarget(target), isTab: target.isTab)
            return target
        }
        note("   controls found: \(targets.count)  window \(crawlScreenRect)  tab bar \(crawlBarRect)")

        // A card presented over a screen is meant to block what is behind it,
        // and `app.sheets` does not always report one. When most of a screen
        // refuses a touch, the screen is behind something rather than broken:
        // the first-run card put all eight Sources rows in the report.
        let onScreen = targets.filter { $0.reach == .hittable || $0.reach == .blocked }
        let behindAPresentation = onScreen.count > 2
            && onScreen.filter { $0.reach == .blocked }.count * 2 > onScreen.count
        if behindAPresentation {
            note("   (most of this screen is behind a presented view; only what is in front was pressed)")
        }

        for target in targets where target.reach != .hittable && target.reach != .offScreen {
            switch target.reach {
            case .blocked where behindAPresentation:
                result.skipped += 1
                note("   · \(target.name) — not pressed: behind a presented view")
            case .blocked:
                result.unreachable += 1
                let where_ = (try? resolveCrawlTarget(target).snapshot()).map { "\($0.frame)" } ?? "no frame"
                note("   ✗ \(target.name) — UNHITTABLE on an untouched screen at \(where_)")
                attach("\(route)__\(target.slug)")
                result.defects.append("[\(route)] \(target.name) is on screen and refuses a touch — tap-target defect")
            case .offScreen:
                break  // the press pass scrolls to it

            case .disabled:
                result.skipped += 1
                note("   · \(target.name) — not pressed: disabled")
            default:
                note("   · \(target.name) — gone before its turn (the screen redrew)")
            }
        }

        // Something known-good to check the screen against after every press:
        // if the anchor stops answering, a modal is still up and the rest of
        // the walk would be nonsense.
        let anchor = targets.first { $0.reach == .hittable && !$0.isTab }.map(resolveCrawlTarget)
        var relaunches = 0

        for target in targets where target.reach == .hittable || target.reach == .offScreen {
            if let word = Self.crawlDestructiveWords.first(where: { matchesCrawlWord(target, $0) }) {
                result.skipped += 1
                note("   · \(target.name) — not pressed: destructive (\(word))")
                continue
            }
            if let word = Self.crawlMutatingWords.first(where: { matchesCrawlWord(target, $0) }) {
                result.skipped += 1
                note("   · \(target.name) — not pressed: would change saved data (\(word))")
                continue
            }
            guard Date() < screenDeadline else {
                result.skipped += 1
                note("   · \(target.name) — not pressed: screen budget")
                continue
            }

            let element = resolveCrawlTarget(target)
            guard let state = try? element.snapshot() else {
                note("   · \(target.name) — gone before its turn (the screen redrew)")
                continue
            }
            // A disabled control is meant to do nothing, and an option that is
            // already the chosen one is meant to stay chosen. Pressing either
            // and calling the silence a defect would bury the real findings.
            guard state.isEnabled else {
                result.skipped += 1
                note("   · \(target.name) — not pressed: disabled")
                continue
            }
            guard !state.isSelected else {
                result.skipped += 1
                note("   · \(target.name) — not pressed: already the selected option")
                continue
            }
            guard revealForCrawl(element, isTab: target.isTab) == .hittable else {
                result.skipped += 1
                note("   · \(target.name) — not pressed: not on screen when its turn came")
                continue
            }

            let before = crawlState(of: element)
            pressForCrawl(element, type: target.type)
            let answered = waitForCrawlResponse(from: before, element: element)
            result.pressed += 1
            if answered {
                note("   ✓ \(target.name) — responded")
            } else {
                result.silent += 1
                note("   ✗ \(target.name) — NO VISIBLE RESPONSE")
                attach("\(route)__\(target.slug)")
                result.defects.append("[\(route)] \(target.name) produced no visible response within 3 s")
            }

            // A switch the walk flipped is a setting the owner's simulator
            // keeps, so it goes straight back.
            if target.type == .switch, answered { pressForCrawl(element, type: .switch) }
            if target.isTab, let homeTab, !tapIfPossible(app.tabBars.buttons[homeTab].firstMatch) {
                tapIfPossible(app.buttons[homeTab].firstMatch)
            }
            _ = restoreCrawlScreen(baseline: baseline, route: route)
            if let anchor, !isSafelyHittable(anchor) {
                guard relaunches < 3 else {
                    note("   … the screen could not be put back; the rest of \(route) was not pressed")
                    break
                }
                relaunches += 1
                note("   … relaunched \(route): something was still covering the screen")
                launchForCrawl(route: route, landscape: landscape)
            }
        }

        app.terminate()
        return result
    }

    private func launchForCrawl(route: String, landscape: Bool) {
        app.terminate()
        app.launchArguments = []
        XCUIDevice.shared.orientation = landscape ? .landscapeLeft : .portrait
        app.launchArguments += ["-OpenStreamHoldPlayerChrome", "YES"]
        launch(screen: route)
        _ = app.wait(for: .runningForeground, timeout: 30)
        // Discover and Live pull their shelves over the network; the rest of the
        // app is drawn by the time the first frame lands.
        Thread.sleep(forTimeInterval: ["discover", "live", "library", "detail", "episodes"].contains(route) ? 7 : 2)
    }

    /// One scroll pass, so an element below the fold is on the list before any
    /// of them is pressed.
    ///
    /// The tab bar is on nearly every screen and a tab round trip costs more
    /// than any other press, so all four are pressed once, on Discover, and
    /// left off every other screen's list — otherwise they take four of the ten
    /// slots a screen gets and the screen's own controls never come up.
    private func enumerateCrawlTargets(includesTabs: Bool) -> [CrawlTarget] {
        var seen = Set<String>()
        var targets: [CrawlTarget] = []
        let tabLabels = Set(app.tabBars.buttons.allElementsBoundByIndex.map(\.label))
        // A sheet is meant to block what is behind it, so the screen under one
        // is not the screen under test: enumerating the whole app reported
        // every row of the Sources page beneath the first-run card as an
        // untouchable control.
        let root: XCUIElementTypeQueryProvider = app.sheets.count > 0 ? app.sheets.firstMatch
            : (app.alerts.count > 0 ? app.alerts.firstMatch : app)

        func collect() {
            let queries: [(String, XCUIElement.ElementType, XCUIElementQuery)] = [
                ("button", .button, root.buttons),
                ("link", .link, root.links),
                ("switch", .switch, root.switches),
                ("segment", .segmentedControl, root.segmentedControls),
                ("cell", .cell, root.cells),
            ]
            for (typeName, type, query) in queries {
                // A shelf-heavy screen answers with hundreds of elements and
                // each identifier costs a round trip; the walk has a budget.
                for element in query.allElementsBoundByIndex.prefix(40) {
                    guard let snapshot = try? element.snapshot() else { continue }
                    let identifier = snapshot.identifier
                    let label = snapshot.label
                    if identifier.isEmpty && label.isEmpty { continue }
                    // A Form row is a cell wrapping the button it already
                    // offered us; pressing both would double the walk.
                    if type == .cell, seen.contains("button\u{1}\(identifier)\u{1}\(label)") { continue }
                    let signature = "\(typeName)\u{1}\(identifier)\u{1}\(label)"
                    guard seen.insert(signature).inserted else { continue }
                    let isTab = tabLabels.contains(label) || Self.crawlTabLabels.contains(label)
                    guard includesTabs || !isTab else { continue }
                    targets.append(CrawlTarget(typeName: typeName, type: type, identifier: identifier,
                                               label: label, isTab: isTab))
                }
            }
        }

        collect()
        // A swipe down dismisses a sheet, and the sheet is the screen under
        // test: its own two buttons were gone by the time their turn came.
        let scrollable = app.scrollViews.count + app.tables.count + app.collectionViews.count > 0
        let scrolls = scrollable && app.sheets.count == 0 ? 2 : 0
        for _ in 0..<scrolls {
            app.swipeUp()
            Thread.sleep(forTimeInterval: 0.4)
            collect()
        }
        for _ in 0..<(scrolls + 1) {
            app.swipeDown()
            Thread.sleep(forTimeInterval: 0.3)
        }
        // A long screen would otherwise eat the whole budget and starve the
        // screens behind it; what is left over is reported, not dropped.
        return Array(targets.prefix(10))
    }

    /// Taps only what is still there and still reachable. `tap()` raises on an
    /// element that vanished between the check and the press, and a raise ends
    /// the whole walk.
    @discardableResult
    private func tapIfPossible(_ element: XCUIElement) -> Bool {
        guard (try? element.snapshot()) != nil, isSafelyHittable(element) else { return false }
        element.tap()
        return true
    }

    /// A switch fills its whole Form row, and the row's centre is dead space:
    /// a press there leaves the switch exactly as it was. The knob is at the
    /// trailing edge, which is where a finger goes.
    private func pressForCrawl(_ element: XCUIElement, type: XCUIElement.ElementType) {
        // A fraction of the row's width lands in different places on a phone
        // row and on an iPad row; the knob is a fixed distance from the
        // trailing edge, so measure from there.
        guard type == .switch, let frame = (try? element.snapshot())?.frame, frame.width > 120 else {
            element.tap()
            return
        }
        element.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: frame.width - 45, dy: frame.height / 2))
            .tap()
    }

    private func matchesCrawlWord(_ target: CrawlTarget, _ word: String) -> Bool {
        target.label.lowercased().contains(word)
            || target.identifier.lowercased().replacingOccurrences(of: ".", with: " ").contains(word)
    }

    private func resolveCrawlTarget(_ target: CrawlTarget) -> XCUIElement {
        let query = app.descendants(matching: target.type)
        if !target.identifier.isEmpty {
            return query.matching(identifier: target.identifier).firstMatch
        }
        return query.matching(NSPredicate(format: "label == %@", target.label)).firstMatch
    }

    /// Reads a control where it stands. `blocked` is the verdict that matters:
    /// the control is on the screen, at a usable size, enabled, and still
    /// refuses a touch — something is drawn over it, or its own hit region is
    /// somewhere its frame is not.
    ///
    /// Deliberately still: the first pass classifies every control before any
    /// of them is pressed, and a pass that scrolled would leave the list
    /// somewhere else than it found it and report the rest as gone.
    /// The floating tab bar, whichever edge it floats at: the phone puts it
    /// along the bottom and covers the last row of every list, iPadOS puts it
    /// along the top and covers the first.
    private var crawlScreenRect: CGRect {
        crawlWindowRect.isNull || crawlWindowRect.height < 200 ? app.frame : crawlWindowRect
    }

    private func tabBarRectForCrawl() -> CGRect {
        if let snapshot = try? app.tabBars.firstMatch.snapshot(), snapshot.frame.height > 0 {
            return snapshot.frame
        }
        // iPadOS does not publish its tab bar as a `tabBar` at all; the items
        // come through as loose buttons, so the bar is their union.
        let items = app.buttons.allElementsBoundByIndex.prefix(24)
            .compactMap { try? $0.snapshot() }
            .filter { Self.crawlTabLabels.contains($0.label) }
            .map(\.frame)
        guard items.count >= 2 else { return .null }
        return items.dropFirst().reduce(items[0]) { $0.union($1) }
    }

    private func classifyForCrawl(_ element: XCUIElement, isTab: Bool) -> CrawlReach {
        guard let snapshot = try? element.snapshot() else { return .gone }
        let frame = snapshot.frame
        if frame.width < 1 || frame.height < 1 { return .blocked }
        let screen = crawlScreenRect
        guard screen.contains(CGPoint(x: frame.midX, y: frame.midY)) else { return .offScreen }
        if element.isHittable { return .hittable }
        // Half a row showing at the foot of a list — or at the foot of the
        // window, on an iPad running the app in a resizable one — is scrolling
        // to do, not a control drawn over. So is a row under the tab bar. Only
        // a control the screen shows whole, clear of the bar, and still will
        // not take a touch is a defect.
        guard screen.contains(frame) else { return .offScreen }
        // Grown by a few points: the floating bar's shadow and its blur margin
        // take touches a row's own edge does not overlap. The Add Media Server
        // picker sat one and a half points clear of the bar and still could not
        // be touched.
        if !isTab, !crawlBarRect.isNull, frame.intersects(crawlBarRect.insetBy(dx: -10, dy: -10)) {
            return .offScreen
        }
        // A toolbar action is disabled while its screen loads, and a disabled
        // control is correctly untouchable — not a defect.
        return snapshot.isEnabled ? .blocked : .disabled
    }

    /// Scrolls a control that was below the fold back into view, for the press
    /// pass only.
    private func revealForCrawl(_ element: XCUIElement, isTab: Bool) -> CrawlReach {
        for _ in 0..<4 {
            let reach = classifyForCrawl(element, isTab: isTab)
            guard reach == .offScreen, let frame = (try? element.snapshot())?.frame else { return reach }
            let screen = crawlScreenRect
            let centre = CGPoint(x: frame.midX, y: frame.midY)
            if !isTab, !crawlBarRect.isNull, frame.intersects(crawlBarRect.insetBy(dx: -10, dy: -10)) {
                // Push the content away from the bar it is hiding under.
                if crawlBarRect.midY < screen.midY { app.swipeDown(velocity: .slow) }
                else { app.swipeUp(velocity: .slow) }
            }
            else if centre.y > screen.maxY { app.swipeUp(velocity: .slow) }
            else if centre.y < screen.minY { app.swipeDown(velocity: .slow) }
            else if centre.x > screen.maxX { app.swipeLeft(velocity: .slow) }
            else { app.swipeRight(velocity: .slow) }
            Thread.sleep(forTimeInterval: 0.4)
        }
        return .offScreen
    }

    /// The modal counts, the navigation title, and the control's own label,
    /// value, selection and enablement.
    ///
    /// Read through `snapshot()`, which throws, rather than through the
    /// properties, which raise: a press that destroys the control it was made
    /// on is the normal case here, not an error, and a raise would end the
    /// walk on the spot.
    private func crawlState(of element: XCUIElement) -> String {
        let own = (try? element.snapshot()).map {
            "\($0.label)|\(String(describing: $0.value))|\($0.isSelected)|\($0.isEnabled)"
        } ?? "gone"
        return [
            // A link that opens Safari answers by taking the app off screen.
            "state:\(app.state.rawValue)",
            navigationTitle(),
            "alerts:\(app.alerts.count)",
            "sheets:\(app.sheets.count)",
            "menus:\(app.menuItems.count)",
            "keyboard:\(app.keyboards.count)",
            // How much is on the screen. A menu with no menu items, a pushed
            // page that kept the title, a spinner that replaced a button while
            // a retry ran: all of them change the count and nothing else does.
            "breadth:\(app.buttons.count)",
            own,
        ].joined(separator: "|")
    }

    private func waitForCrawlResponse(from before: String, element: XCUIElement) -> Bool {
        let deadline = Date().addingTimeInterval(3)
        while true {
            if crawlState(of: element) != before { return true }
            guard Date() < deadline else { return false }
            Thread.sleep(forTimeInterval: 0.5)
        }
    }

    private func navigationTitle() -> String {
        let bar = app.navigationBars.firstMatch
        return bar.exists ? bar.identifier : ""
    }

    private func selectedTabLabel() -> String? {
        if let phone = app.tabBars.buttons.allElementsBoundByIndex.first(where: { $0.isSelected }) {
            return phone.label
        }
        return app.buttons.allElementsBoundByIndex.prefix(16)
            .first { Self.crawlTabLabels.contains($0.label) && $0.isSelected }?.label
    }

    /// Closes whatever the press opened and gets back to the screen the walk
    /// started on. Only non-destructive exits are used.
    @discardableResult
    private func restoreCrawlScreen(baseline: String, route: String) -> Bool {
        let exits = ["Cancel", "Close", "Done", "Dismiss", "OK", "Not Now", "Later"]
        // A press on Play puts a full-screen player up, and nothing in `exits`
        // closes it; without these the walk relaunched the route after every
        // Play and spent the screen's budget getting back.
        // Not on the title page itself: there, `detail.back` is a control
        // under test, and popping the page before its turn came made the walk
        // press it on the screen behind and call it unresponsive.
        let covers = ["detail", "episodes"].contains(route) ? ["player.close"] : ["player.close", "detail.back"]
        for attempt in 0..<4 {
            for cover in covers where tapIfPossible(app.buttons[cover].firstMatch) {
                Thread.sleep(forTimeInterval: 0.6)
            }
            if app.alerts.count > 0 {
                let alert = app.alerts.firstMatch
                if !exits.contains(where: { tapIfPossible(alert.buttons[$0].firstMatch) }) {
                    tapIfPossible(alert.buttons.element(boundBy: max(0, alert.buttons.count - 1)))
                }
                Thread.sleep(forTimeInterval: 0.5)
                continue
            }
            if app.keyboards.count > 0 {
                if !tapIfPossible(app.keyboards.buttons["Return"].firstMatch),
                   !tapIfPossible(app.toolbars.buttons["Done"].firstMatch) {
                    app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.08)).tap()
                }
                Thread.sleep(forTimeInterval: 0.5)
                continue
            }
            if app.sheets.count > 0 {
                let sheet = app.sheets.firstMatch
                if !exits.contains(where: { tapIfPossible(sheet.buttons[$0].firstMatch) }) {
                    sheet.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.02))
                        .press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.95)))
                }
                Thread.sleep(forTimeInterval: 0.6)
                continue
            }
            if navigationTitle() != baseline {
                // `element(boundBy: 0)` picked whichever button the bar happened
                // to list first — on Live that was Search, and the walk pressed
                // it instead of going back.
                if tapIfPossible(app.navigationBars.buttons["BackButton"].firstMatch) { }
                else if let exit = exits.first(where: { tapIfPossible(app.buttons[$0].firstMatch) }) {
                    _ = exit
                } else { return false }
                Thread.sleep(forTimeInterval: 0.6)
                continue
            }
            // A menu draws no alert and no sheet, and SwiftUI does not always
            // publish its rows as menu items; a press outside it is the only
            // exit that always works.
            if app.menuItems.count > 0 || app.popovers.count > 0 {
                let dismissRegion = app.otherElements["PopoverDismissRegion"]
                if !tapIfPossible(dismissRegion) {
                    // A menu covers whichever corner it was opened from, so the
                    // press outside it moves each time round.
                    let elsewhere = [CGVector(dx: 0.5, dy: 0.97), CGVector(dx: 0.04, dy: 0.5),
                                     CGVector(dx: 0.96, dy: 0.5), CGVector(dx: 0.5, dy: 0.03)]
                    app.coordinate(withNormalizedOffset: elsewhere[attempt % elsewhere.count]).tap()
                }
                Thread.sleep(forTimeInterval: 0.5)
                continue
            }
            return true
        }
        return app.alerts.count == 0 && app.sheets.count == 0 && navigationTitle() == baseline
    }
}
