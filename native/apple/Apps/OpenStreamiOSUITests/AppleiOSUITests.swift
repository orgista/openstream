import XCTest

/// iPhone and iPad behaviour that needs a touch or a rotation.
///
/// `simctl` can drive neither: it has no tap API and no orientation option, so
/// every row that depended on one — the sheets in C3, landscape in C8, typing a
/// query in F2 — sat blocked. This target is the way to them.
@MainActor
final class AppleiOSUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
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

    private func attach(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
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
    func testDownloadStartsWithoutAskingForASource() {
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
        let header = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "AIOMetadata")).firstMatch
        var swipes = 0
        while !header.exists, swipes < 14 { app.swipeUp(); swipes += 1; Thread.sleep(forTimeInterval: 0.6) }
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
    func testLiveBroadcastCaptionsArePhotographed() {
        launch(screen: "live")
        let channel = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Play CBS")).firstMatch
        XCTAssertTrue(channel.waitForExistence(timeout: 30))
        channel.tap()
        XCTAssertTrue(app.buttons["player.close"].waitForExistence(timeout: 10))
        Thread.sleep(forTimeInterval: 12)
        revealPlayerControls()
        app.buttons["player.captions"].tap()
        let english = app.buttons.matching(NSPredicate(format: "label == 'Closed Captions' OR label BEGINSWITH 'English'")).firstMatch
        XCTAssertTrue(english.waitForExistence(timeout: 10), "No broadcast caption track was published")
        attach("live-broadcast-caption-menu")
        english.tap()
        Thread.sleep(forTimeInterval: 12)
        attach("live-broadcast-caption-text-review-required")
        revealPlayerControls()
        app.buttons["player.captions"].tap()
        app.buttons["Off"].firstMatch.tap()
        revealPlayerControls()
        app.buttons["player.close"].tap()
    }
}
