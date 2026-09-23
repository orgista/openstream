import XCTest
import Vision

/// Focus behaviour on Apple TV, driven by the Siri Remote.
///
/// Every fix that depended on focus shipped unverified for a whole session,
/// because there is no way to press a remote from a script *except* from here:
/// `simctl` has no such API. Each of these assertions replaces something the
/// owner previously had to check by hand and report back.
@MainActor
final class AppleTVFocusUITests: XCTestCase {
    private var app: XCUIApplication!
    private var remote: XCUIRemote { .shared }

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication(bundleIdentifier: "com.orgista.openstream")
    }

    override func tearDown() {
        app?.terminate()
    }

    /// Launches on `screen` using the same DEBUG hook the headless captures
    /// use, with the interaction trace on so a failure leaves a timeline.
    private func launch(screen: String) {
        app.launchArguments += ["-OpenStreamVisionScreen", screen,
                                "-OpenStreamTrace", "YES"]
        app.launch()
    }

    /// Element type is not something a test should care about: SwiftUI decides
    /// it, and `.accessibilityElement(children: .combine)` turns a panel into a
    /// StaticText. Match on the identifier alone.
    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    /// Whatever currently holds focus, of any type.
    private var focusedElement: XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "hasFocus == true")).firstMatch
    }

    /// Waits for an element rather than sleeping: the guide loads over the
    /// network and a fixed sleep either flakes or wastes time.
    @discardableResult
    private func wait(for element: XCUIElement, _ timeout: TimeInterval = 30) -> Bool {
        element.waitForExistence(timeout: timeout)
    }

    // MARK: - The guide

    func testRawTSSwipeUpArmsBeforeCaptionArrival() async throws {
        guard let fixture = ProcessInfo.processInfo.environment["OPENSTREAM_SUBTITLE_FIXTURE_URL"],
              URL(string: fixture)?.host == "127.0.0.1" else {
            throw XCTSkip("Requires a localhost raw-TS fixture")
        }
        app.launchArguments = [
            "-OpenStreamInlineLiveFixture", "-OpenStreamVisionPlaybackURL", fixture,
            "-OpenStreamVisionPlaybackIsLive", "YES", "-OpenStreamTrace", "YES",
            "-openstream.settings.captions.preference.v1", "off",
            "-openstream.settings.subtitle.languages.v1", "(en)"
        ]
        app.launch()
        try await Task.sleep(for: .milliseconds(200))
        remote.press(.up)
        let notice = app.staticTexts["Captions on"].firstMatch
        XCTAssertTrue(notice.waitForExistence(timeout: 3))
        let armed = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        armed.name = "n7-tvos-armed"; armed.lifetime = .keepAlways; add(armed)
        // The fixture holds its first TS bytes until the real remote command
        // has armed captions. This proves discovery cannot precede the swipe.
        let controlURL = try XCTUnwrap(URL(string: fixture)?.deletingLastPathComponent().appendingPathComponent("release"))
        var release = URLRequest(url: controlURL)
        release.httpMethod = "POST"
        _ = try await URLSession.shared.data(for: release)
        let cue = app.staticTexts["N7 RAW TS CAPTIONS"].firstMatch
        let appeared = cue.waitForExistence(timeout: 45)
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "n7-tvos-first-cue"; shot.lifetime = .keepAlways; add(shot)
        XCTAssertTrue(appeared, "Armed raw-TS 608 did not render")
    }

    func testCaptionSelectionMatchesRendered608() throws {
        let env = ProcessInfo.processInfo.environment
        guard let fixture = env["OPENSTREAM_SUBTITLE_FIXTURE_URL"],
              URL(string: fixture)?.host == "127.0.0.1" else {
            throw XCTSkip("Requires a localhost 608 fixture")
        }
        let expectedCue = env["OPENSTREAM_SUBTITLE_FIXTURE_CUE"] ?? "N4 CAPTIONS WORK"
        let expectedTrack = env["OPENSTREAM_SUBTITLE_FIXTURE_TRACK"] ?? "English"
        app.launchArguments += [
            "-OpenStreamVisionPlaybackURL", fixture, "-OpenStreamVisionPlaybackIsLive", "YES",
            "-openstream.playback.engine", "engine", "-openstream.firstRunGuidanceSeen", "YES",
            "-openstream.settings.captions.preference.v1", "always",
            "-openstream.settings.subtitle.languages.v1", "(en)",
            "-openstream.sources.v1", "", "-openstream.sources.v1.pending-keychain-removals", "()",
            "-openstream.backup.icloud.enabled.v1", "NO",
            "-openstream.settings.discover.enabled.v1", "NO",
            "-openstream.settings.live.enabled.v1", "NO",
            "-openstream.settings.library.enabled.v1", "NO",
            "-openstream.settings.metadata.enabled.v1", "NO"
        ]
        launch(screen: "add-files")
        func capture(_ name: String) {
            let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            shot.name = name; shot.lifetime = .keepAlways; add(shot)
            let tree = XCTAttachment(string: app.debugDescription)
            tree.name = name + "-hierarchy"; tree.lifetime = .keepAlways; add(tree)
        }
        func cueVisible() throws -> Bool {
            let image = try XCTUnwrap(XCUIScreen.main.screenshot().image.cgImage)
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = false
            try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
            let text = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
            return text.filter { !$0.isWhitespace }.uppercased()
                .contains(expectedCue.filter { !$0.isWhitespace }.uppercased())
        }
        let deadline = Date().addingTimeInterval(45)
        while Date() < deadline {
            if try cueVisible() { break }
            Thread.sleep(forTimeInterval: 0.5)
        }
        XCTAssertTrue(try cueVisible(), "Default-on 608 did not render")
        func openMenu() {
            let subtitles = app.cells.matching(NSPredicate(format: "label == 'Subtitles'")).firstMatch
            for _ in 0..<5 {
                remote.press(.down)
                if subtitles.waitForExistence(timeout: 2) { break }
            }
            capture("n6-tvos-controls")
            XCTAssertEqual(app.cells.matching(NSPredicate(format: "label == 'Subtitles'")).count, 1,
                "tvOS must expose exactly one captions transport control")
            XCTAssertFalse(app.cells["AVLegibleSettings"].exists, "AVKit captions button returned")
            remote.press(.up)
            for _ in 0..<6 {
                if subtitles.hasFocus || subtitles.descendants(matching: .any)
                    .matching(NSPredicate(format: "hasFocus == true")).count > 0 { break }
                remote.press(.right)
            }
            remote.press(.select)
            XCTAssertTrue(app.staticTexts["Off"].firstMatch.waitForExistence(timeout: 5))
        }
        openMenu()
        capture("n6-tvos-english")
        XCTAssertTrue(app.cells.matching(NSPredicate(format: "label CONTAINS 'selected' AND label CONTAINS %@", expectedTrack)).firstMatch.exists)
        XCTAssertTrue(try cueVisible())
        for _ in 0..<4 {
            if focusedElement.label.contains("Off") { break }
            remote.press(.up)
        }
        XCTAssertTrue(focusedElement.label.contains("Off"))
        remote.press(.select)
        Thread.sleep(forTimeInterval: 2)
        XCTAssertFalse(try cueVisible(), "Off left a caption drawn")
        openMenu()
        capture("n6-tvos-off")
        XCTAssertTrue(app.cells.matching(NSPredicate(format: "label CONTAINS 'selected' AND label CONTAINS 'Off'")).firstMatch.exists)
        XCTAssertFalse(try cueVisible())
    }

    func testFullSubtitleMenuSelectsSpanish() throws {
        guard let fixture = ProcessInfo.processInfo.environment["OPENSTREAM_SUBTITLE_FIXTURE_URL"],
              URL(string: fixture)?.host == "127.0.0.1" else {
            throw XCTSkip("Requires a localhost three-track MKV fixture")
        }
        app.launchArguments += [
            "-OpenStreamVisionPlaybackURL", fixture, "-OpenStreamVisionPlaybackIsLive", "YES",
            "-openstream.playback.engine", "engine",
            "-openstream.firstRunGuidanceSeen", "YES",
            "-openstream.settings.captions.preference.v1", "off",
            "-openstream.settings.subtitle.languages.v1", "(en)",
            "-openstream.sources.v1", "", "-openstream.sources.v1.pending-keychain-removals", "()",
            "-openstream.backup.icloud.enabled.v1", "NO",
            "-openstream.settings.discover.enabled.v1", "NO",
            "-openstream.settings.live.enabled.v1", "NO",
            "-openstream.settings.library.enabled.v1", "NO",
            "-openstream.settings.metadata.enabled.v1", "NO"
        ]
        launch(screen: "add-files")
        let subtitles = element("Subtitles")
        for _ in 0..<15 {
            remote.press(.down)
            if subtitles.waitForExistence(timeout: 2) { break }
        }
        XCTAssertTrue(subtitles.exists)
        remote.press(.up)
        for _ in 0..<6 {
            if subtitles.hasFocus || subtitles.descendants(matching: .any)
                .matching(NSPredicate(format: "hasFocus == true")).count > 0 { break }
            remote.press(.right)
        }
        remote.press(.select)
        for title in ["Off", "English", "Spanish", "English SDH"] {
            XCTAssertTrue(app.staticTexts[title].firstMatch.waitForExistence(timeout: 5), "Missing " + title)
        }
        func attach(_ name: String) {
            let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            shot.name = name
            shot.lifetime = .keepAlways
            add(shot)
        }
        attach("n5-tvos-full-menu")
        for _ in 0..<5 {
            if focusedElement.label == "Spanish" { break }
            remote.press(.down)
        }
        XCTAssertEqual(focusedElement.label, "Spanish")
        remote.press(.select)
        XCTAssertTrue(app.staticTexts["HOLA DESDE ESPANA"].firstMatch.waitForExistence(timeout: 20))
        attach("n5-tvos-spanish-cue")
    }

    func testFirstLiveHLSPlayOffersCaptions() throws {
        guard let fixture = ProcessInfo.processInfo.environment["OPENSTREAM_CAPTION_FIXTURE_URL"],
              URL(string: fixture)?.host == "127.0.0.1" else {
            throw XCTSkip("A localhost OPENSTREAM_CAPTION_FIXTURE_URL is required")
        }
        app.launchArguments += [
            "-OpenStreamVisionPlaybackURL", fixture, "-OpenStreamVisionPlaybackIsLive", "YES",
            "-openstream.firstRunGuidanceSeen", "YES",
            "-openstream.settings.captions.preference.v1", "always",
            "-openstream.sources.v1", "", "-openstream.sources.v1.pending-keychain-removals", "()",
            "-openstream.backup.icloud.enabled.v1", "NO",
            "-openstream.settings.discover.enabled.v1", "NO",
            "-openstream.settings.live.enabled.v1", "NO",
            "-openstream.settings.library.enabled.v1", "NO",
            "-openstream.settings.metadata.enabled.v1", "NO"
        ]
        launch(screen: "add-files")
        let subtitles = app.descendants(matching: .any).matching(identifier: "Subtitles").firstMatch
        for _ in 0..<12 {
            remote.press(.down)
            if subtitles.waitForExistence(timeout: 2) { break }
        }
        XCTAssertTrue(subtitles.exists, "Captions must be available on the first fixture open")
        let controls = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        controls.name = "first-play-hls-cc-controls"
        controls.lifetime = .keepAlways
        add(controls)
        // Down reveals the transport with focus on its timeline. Up reaches
        // the row of AVKit menu controls before moving across that row.
        remote.press(.up)
        for _ in 0..<6 {
            if subtitles.hasFocus || subtitles.descendants(matching: .any)
                .matching(NSPredicate(format: "hasFocus == true")).count > 0 { break }
            remote.press(.right)
        }
        let hierarchy = XCTAttachment(string: app.debugDescription)
        hierarchy.name = "first-play-caption-controls-hierarchy"
        hierarchy.lifetime = .keepAlways
        add(hierarchy)
        XCTAssertTrue(subtitles.hasFocus || subtitles.descendants(matching: .any)
            .matching(NSPredicate(format: "hasFocus == true")).count > 0,
            "The remote must reach the captions menu")
        remote.press(.select)
        let cc = app.descendants(matching: .any).matching(NSPredicate(
            format: "label CONTAINS[c] 'CC' OR label CONTAINS[c] 'English'")).firstMatch
        XCTAssertTrue(cc.waitForExistence(timeout: 5), "The first-play menu must contain the embedded caption track")
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "first-play-hls-cc-menu"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    func testChapterIntroCanBeReachedAndSkippedWithTheRemote() throws {
        guard let fixture = ProcessInfo.processInfo.environment["OPENSTREAM_CHAPTER_FIXTURE_URL"],
              !fixture.isEmpty else {
            throw XCTSkip("OPENSTREAM_CHAPTER_FIXTURE_URL not set")
        }
        app.launchArguments += ["-OpenStreamVisionPlaybackURL", fixture]
        launch(screen: "add-files")
        let skip = element("player.skipIntro")
        XCTAssertTrue(wait(for: skip), "Chapter-backed Skip Intro never appeared")
        let surface = element("player.controls.show")
        let surfaceFocused = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hasFocus == true"), object: surface)
        XCTAssertEqual(XCTWaiter.wait(for: [surfaceFocused], timeout: 10), .completed,
                       "The playback surface must receive initial focus before pressing Down")
        remote.press(.down)
        let focused = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hasFocus == true"), object: skip)
        XCTAssertEqual(XCTWaiter.wait(for: [focused], timeout: 5), .completed,
                       "The remote must reach Skip Intro from the playback surface")
        let before = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        before.name = "tv-chapter-before-skip"
        before.lifetime = .keepAlways
        add(before)
        remote.press(.select)
        let hidden = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: skip)
        XCTAssertEqual(XCTWaiter.wait(for: [hidden], timeout: 10), .completed)
        let sought = app.staticTexts.matching(NSPredicate(format: "label MATCHES %@", "0:5[0-9]")).firstMatch
        XCTAssertTrue(sought.waitForExistence(timeout: 10), "Playback did not reach the 50-second chapter boundary")
        let after = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        after.name = "tv-chapter-after-skip"
        after.lifetime = .keepAlways
        add(after)
    }

    /// Owner Z17: the guide must open on the first channel, not the category
    /// chips, so the info panel describes what it is showing.
    func testGuideOpensFocusedOnAChannel() {
        launch(screen: "live")
        let panel = element("live.tv.info")
        XCTAssertTrue(wait(for: panel), "the guide's info panel never appeared")

        // Launching straight into a tab leaves focus on the tab bar, which is
        // correct tvOS behaviour. Z17 is about where focus lands when the
        // viewer moves *into* the guide, so press down first.
        XCTAssertTrue(focusedElement.waitForExistence(timeout: 10), "nothing holds focus at all")
        remote.press(.down)
        Thread.sleep(forTimeInterval: 1.5)

        let focused = focusedElement
        XCTAssertTrue(focused.exists, "pressing down from the tab bar left focus nowhere")
        XCTAssertTrue(
            focused.identifier.hasPrefix("guide.play.") || focused.identifier.hasPrefix("live.category."),
            "expected a channel or a category chip to hold focus, got '\(focused.identifier)'"
        )
        // Z17 proper: the first stop inside the guide should be a channel.
        XCTAssertTrue(
            focused.identifier.hasPrefix("guide.play."),
            "Z17: the guide should open on a channel, but focus went to '\(focused.identifier)'"
        )
    }

    /// Owner, twice: "would like to also see a preview of the channel similar
    /// to direct tv app — they preview the channel, it starts playing before
    /// you click".
    ///
    /// The preview is dwell-gated, so it can only be observed by actually
    /// holding focus on a rail cell — which is why it could never be checked
    /// from a headless capture: launching into the Live tab leaves focus on the
    /// tab bar and nothing ever previews. This moves focus onto a channel,
    /// waits past the dwell, and attaches what the screen looks like.
    func testChannelPreviewStartsAfterDwellingOnAChannel() {
        launch(screen: "live")
        XCTAssertTrue(wait(for: element("live.tv.info")), "the guide's info panel never appeared")
        XCTAssertTrue(focusedElement.waitForExistence(timeout: 10), "nothing holds focus at all")

        remote.press(.down)
        Thread.sleep(forTimeInterval: 1.5)
        let focused = focusedElement
        XCTAssertTrue(
            focused.identifier.hasPrefix("guide.play."),
            "expected a channel to hold focus, got '\(focused.identifier)'"
        )

        // Past the 1200 ms dwell, plus time for the stream to open.
        Thread.sleep(forTimeInterval: 8)

        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "guide-preview-after-dwell"
        shot.lifetime = .keepAlways
        add(shot)

        // The trace records what the preview did; keep it with the screenshot
        // so a failure explains itself.
        XCTAssertTrue(focused.exists, "focus left the channel during the dwell")
    }

    /// Owner: "channels when clicking make it freeze". Select on a rail cell
    /// must open the player rather than leaving focus nowhere.
    func testSelectingAChannelOpensThePlayer() {
        launch(screen: "live")
        XCTAssertTrue(wait(for: element("live.tv.info")), "the guide never appeared")

        // Into the guide first — Select on the tab bar only re-selects the tab.
        remote.press(.down)
        Thread.sleep(forTimeInterval: 1.5)
        remote.press(.select)

        // The player's focus catcher is a `Color.clear` button, so asserting on
        // it is fragile. The guide being covered is the reliable signal that
        // the full-screen player took over.
        let guidePanel = element("live.tv.info")
        let covered = NSPredicate(format: "exists == false OR isHittable == false")
        expectation(for: covered, evaluatedWith: guidePanel)
        waitForExpectations(timeout: 40)
    }

    /// Owner 18:55: Menu over a channel that never started must leave, not
    /// toggle the channel row over a black screen.
    func testMenuLeavesTheGuideRatherThanTrapping() {
        launch(screen: "live")
        XCTAssertTrue(wait(for: element("live.tv.info")), "the guide never appeared")

        // Enter the guide first. Pressing Menu while focus is still on the tab
        // bar is the app root, where stock tvOS leaves for the Home screen —
        // correct, and not what this test is about.
        XCTAssertTrue(focusedElement.waitForExistence(timeout: 10), "nothing holds focus at all")
        remote.press(.down)
        Thread.sleep(forTimeInterval: 1.5)
        XCTAssertTrue(
            focusedElement.identifier.hasPrefix("guide.play."),
            "expected a channel to hold focus before pressing Menu, got '\(focusedElement.identifier)'"
        )

        // Owner 2026-09-15: "in live I can't go back when pressing home/esc
        // from live to go to the top bar … I have to scroll all the way up."
        // Menu from inside the guide hands focus back up to the tab bar; it
        // used to be swallowed by an `onExitCommand` that then did nothing,
        // which is what "I have to scroll all the way up" meant.
        remote.press(.menu)
        Thread.sleep(forTimeInterval: 1.5)

        let focused = focusedElement
        XCTAssertTrue(focused.exists, "Menu left focus nowhere in the guide")
        XCTAssertFalse(
            focused.identifier.hasPrefix("guide.play."),
            "Menu did not leave the channel rail: focus is still on '\(focused.identifier)'"
        )
    }

    /// Owner 2026-09-21: "in live tv page you are unable to select favs bar
    /// back goes to the main top nav bar but there is no way to search in live
    /// or go to the favs bar". Menu from the grid lands on the category row
    /// first, a second Menu reaches the tab bar, and from the grid the
    /// Favorites chip and the search glyph are both reachable and selectable.
    func testLiveMenuReachesTheCategoryRowThenFavoritesAndSearch() {
        launch(screen: "live")
        XCTAssertTrue(wait(for: element("live.tv.info")), "the guide never appeared")
        XCTAssertTrue(focusedElement.waitForExistence(timeout: 10), "nothing holds focus at all")

        func settle() { Thread.sleep(forTimeInterval: 1.5) }
        func snap(_ name: String) {
            let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            shot.name = name
            shot.lifetime = .keepAlways
            add(shot)
        }

        // (b) A few rows into the grid, Menu goes to the chip row, not the tab bar.
        remote.press(.down); settle()
        remote.press(.down); settle()
        remote.press(.down); settle()
        XCTAssertTrue(focusedElement.identifier.hasPrefix("guide.play."),
                      "expected a channel before Menu, got '\(focusedElement.identifier)'")
        remote.press(.menu); settle()
        snap("4b-1-menu-from-grid-lands-on-chips")
        XCTAssertEqual(focusedElement.identifier, "live.category.All",
                       "Menu from the grid should land on the current chip, got '\(focusedElement.identifier)'")

        // A second Menu from the chip row is the system's: the tab bar.
        remote.press(.menu); settle()
        snap("4b-2-second-menu-reaches-tab-bar")
        XCTAssertEqual(focusedElement.label, "Live",
                       "Menu from the chip row should reach the tab bar, got '\(focusedElement.label)'")

        // (a) Into the grid, up to the chip row, right to Favorites, select.
        remote.press(.down); settle()
        XCTAssertTrue(focusedElement.identifier.hasPrefix("guide.play."),
                      "down from the tab bar should reach a channel, got '\(focusedElement.identifier)'")
        remote.press(.up); settle()
        XCTAssertTrue(focusedElement.identifier.hasPrefix("live.category."),
                      "up from the grid should reach the chip row, got '\(focusedElement.identifier)'")
        remote.press(.right); settle()
        XCTAssertEqual(focusedElement.identifier, "live.category.Favorites")
        remote.press(.select); settle()
        snap("4b-3-favorites-selected")
        XCTAssertTrue(element("live.category.Favorites").isSelected, "Select did not choose the Favorites chip")

        // Back to All so the next launch finds the guide as it was.
        remote.press(.left); settle()
        remote.press(.select); settle()
        XCTAssertTrue(element("live.category.All").isSelected, "could not return to All")

        // (c) Right along the chip row to the search glyph, then open it.
        for _ in 0 ..< 20 where focusedElement.identifier != "live.search" {
            remote.press(.right)
            Thread.sleep(forTimeInterval: 0.8)
        }
        XCTAssertEqual(focusedElement.identifier, "live.search", "never reached the search glyph")
        snap("4b-4-search-glyph-focused")
        remote.press(.select)
        let field = app.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10), "selecting the glyph did not open channel search")
        settle()
        snap("4b-5-channel-search-open")

        // Menu pops the search and returns to the guide.
        remote.press(.menu); settle()
        XCTAssertTrue(wait(for: element("live.search"), 10), "Menu did not return from search to the guide")
    }

    // MARK: - Search

    /// Owner F2/F4: reaching Search and what it shows.
    ///
    /// The tab is a bare magnifying glass with no title, so it is reached by
    /// going up to the bar and left along it. The deep link route
    /// (`openstream://search?query=…`) cannot be used here: `simctl openurl`
    /// makes tvOS put up its own "Open in OpenStream?" confirmation, which is a
    /// simulator artifact and needs a press of its own.
    func testSearchTabIsReachableAndTakesFocus() {
        launch(screen: "discover")
        XCTAssertTrue(focusedElement.waitForExistence(timeout: 30), "nothing holds focus at all")

        // Up until the tab bar has focus, then left to the leading tab.
        for _ in 0 ..< 3 {
            remote.press(.up)
            Thread.sleep(forTimeInterval: 1.2)
        }
        for _ in 0 ..< 5 {
            remote.press(.left)
            Thread.sleep(forTimeInterval: 1.0)
            if focusedElement.label == "Search" { break }
        }
        XCTAssertEqual(focusedElement.label, "Search",
                       "never reached the Search tab; focus sat on '\(focusedElement.label)'")

        remote.press(.select)
        Thread.sleep(forTimeInterval: 2.5)

        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "search-tab"
        shot.lifetime = .keepAlways
        add(shot)

        XCTAssertTrue(focusedElement.exists, "opening Search left focus nowhere")
        print("SEARCH focus after open: label='\(focusedElement.label)' id='\(focusedElement.identifier)'")
        // F2 (the result rows) is not covered here: `typeText` against the
        // search field fails on tvOS — the field never takes keyboard focus
        // that way — and driving 9 characters through the on-screen keyboard
        // with the remote would be its own source of flake.

    }

    // MARK: - The title page

    /// Diagnostic, not an assertion: prints where the remote actually lands on
    /// the title page, so a focus path is read off the device instead of
    /// guessed at.
    ///
    /// It earned its place immediately. Two attempts at a B22 test were written
    /// against an assumed layout and both failed on the *navigation*, not the
    /// behaviour: Down from the tab bar lands on an episode control whose
    /// identifier is empty (not `detail.play`), and Right from there walks the
    /// episode list rather than reaching My List / Rate — even though a static
    /// capture shows both sitting beside Play.
    func testDumpTitlePageFocusPath() {
        launch(screen: "detail")
        XCTAssertTrue(wait(for: element("detail.play"), 40), "the title page never appeared")
        print("FOCUSPATH start: label='\(focusedElement.label)' id='\(focusedElement.identifier)'")
        remote.press(.down)
        Thread.sleep(forTimeInterval: 1.5)
        print("FOCUSPATH down 1: label='\(focusedElement.label)' id='\(focusedElement.identifier)'")
        // Up from wherever Down landed: if My List / Rate are above, they are
        // reachable and the page simply opened further down. If Up goes
        // straight back to the tab bar, the icon row is not in the remote's
        // path at all, which would be a real defect.
        for step in 0 ..< 4 {
            remote.press(.up)
            Thread.sleep(forTimeInterval: 1.3)
            let f = focusedElement
            print("FOCUSPATH up \(step + 1): label='\(f.label)' id='\(f.identifier)'")
        }
    }

    /// Owner B25: "scrolling is slow".
    ///
    /// Smoothness cannot be asserted from a screenshot, but **dropped input**
    /// can be counted, and that is what a rail which cannot keep up actually
    /// does: presses arrive faster than it can move focus and some are lost.
    /// This drives ten rapid presses along a shelf and counts how many moved
    /// focus, printing the per-press cost so a regression has a number to beat.
    func testShelfSurvivesRapidPressesAndRecordsTheCost() {
        launch(screen: "discover")
        XCTAssertTrue(focusedElement.waitForExistence(timeout: 30), "nothing holds focus at all")

        // Into the content: the bar holds focus on launch.
        remote.press(.down)
        Thread.sleep(forTimeInterval: 2.0)
        // Some rail cells carry an identifier and no label, so focus is keyed
        // on both — otherwise every cell looks identical and nothing "moves".
        func focusKey() -> String {
            let f = focusedElement
            return "\(f.label)|\(f.identifier)"
        }
        var previous = focusKey()
        print("SCROLL start key='\(previous)'")
        XCTAssertNotEqual(previous, "|", "pressing down from the tab bar left focus nowhere")

        let presses = 10
        var moved = 0
        let started = Date()
        for _ in 0 ..< presses {
            remote.press(.right)
            Thread.sleep(forTimeInterval: 0.35)
            let current = focusKey()
            if current != previous { moved += 1 }
            print("SCROLL step key='\(current)'")
            previous = current
        }
        let elapsed = Date().timeIntervalSince(started)
        print("SCROLL moved \(moved)/\(presses) in \(String(format: "%.2f", elapsed))s "
              + "(\(String(format: "%.0f", elapsed / Double(presses) * 1000)) ms per press)")

        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "shelf-after-rapid-presses"
        shot.lifetime = .keepAlways
        add(shot)

        // Deliberately no assertion on `moved`. The first run of this reported
        // 1/10 and looked like dropped input — but the attached frame showed
        // focus sitting on the **last** poster of a four-item shelf, which is a
        // rail that reached its end and correctly stopped. The two disagree, so
        // the focus key is not a trustworthy measure of movement here and a
        // threshold built on it would be a false failure waiting to happen.
        //
        // What this still gives is the per-press cost, printed above: 619 ms
        // for ten presses on the Continue Watching shelf, which is the number a
        // future "scrolling is slow" report can be checked against.
        XCTAssertTrue(focusedElement.exists, "the shelf left focus nowhere")
    }

    /// Owner B24: the "Other sources" entry point.
    ///
    /// On Apple TV it is not a visible control — it lives in a `contextMenu` on
    /// the Play button, so the only way to it is a long press of Select. That
    /// is worth a test precisely because nothing on screen advertises it: if
    /// the menu ever stopped opening, nothing else would reveal it.
    func testOtherSourcesIsReachableByLongPressingPlay() {
        launch(screen: "detail")
        XCTAssertTrue(wait(for: element("detail.play"), 40), "the title page never appeared")
        XCTAssertTrue(focusedElement.waitForExistence(timeout: 10), "nothing holds focus at all")
        XCTAssertEqual(focusedElement.identifier, "detail.play",
                       "expected Play to hold focus on appear")

        remote.press(.select, forDuration: 2.0)
        Thread.sleep(forTimeInterval: 2.5)

        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "other-sources-context-menu"
        shot.lifetime = .keepAlways
        add(shot)

        let entry = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", "Other sources")).firstMatch
        XCTAssertTrue(entry.waitForExistence(timeout: 10),
                      "long-pressing Play did not reveal the Other sources entry")
    }

    /// Owner B23: the episode list must show which episode is focused.
    ///
    /// Down from Play lands on the episode rail (the focus-path diagnostic
    /// established that). This walks two episodes along and attaches the frame,
    /// so the thumbnails and the focused state can be looked at rather than
    /// assumed, and asserts the rail actually moves — a rail that swallows
    /// presses looks identical in a screenshot to one that works.
    func testEpisodeRailMovesAndShowsTheFocusedEpisode() {
        launch(screen: "detail")
        XCTAssertTrue(wait(for: element("detail.play"), 40), "the title page never appeared")

        remote.press(.down)
        Thread.sleep(forTimeInterval: 1.8)
        let first = focusedElement.label
        XCTAssertTrue(first.contains("Play S"),
                      "expected an episode to hold focus, got '\(first)'")

        remote.press(.right)
        Thread.sleep(forTimeInterval: 1.4)
        let second = focusedElement.label
        XCTAssertNotEqual(first, second, "the episode rail did not move on Right")

        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "episode-rail-focused"
        shot.lifetime = .keepAlways
        add(shot)
        print("EPISODES first='\(first)' second='\(second)'")
    }

    /// Owner B22: opening Rate must not drop focus onto Play.
    ///
    /// The risk is written into the source: pressing Rate replaces the button
    /// with the three choices, "and focus with nowhere to go falls back to
    /// `defaultFocus`, which is Play". The code hands focus to the first choice
    /// in the same breath to prevent that; this holds it there.
    ///
    /// The navigation matters and is not obvious — the focus-path diagnostic
    /// established it. The page opens with `detail.play` already focused, and
    /// the icon row sits on the same line to its right; pressing Down from Play
    /// skips the row and lands on the episode list instead.
    func testOpeningRateKeepsFocusOnTheChoicesNotPlay() {
        launch(screen: "detail")
        XCTAssertTrue(wait(for: element("detail.play"), 40), "the title page never appeared")
        XCTAssertTrue(focusedElement.waitForExistence(timeout: 10), "nothing holds focus at all")

        // Right along the action line until Rate holds focus. A fixed count
        // would break the moment another icon joins the row.
        var landedOnRate = focusedElement.label == "Rate"
        for _ in 0 ..< 4 where !landedOnRate {
            remote.press(.right)
            Thread.sleep(forTimeInterval: 1.2)
            landedOnRate = focusedElement.label == "Rate"
        }
        XCTAssertTrue(landedOnRate,
                      "never reached Rate; focus sat on '\(focusedElement.label)'")

        remote.press(.select)
        Thread.sleep(forTimeInterval: 2.0)

        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "rate-choices-open"
        shot.lifetime = .keepAlways
        add(shot)

        let focused = focusedElement
        XCTAssertTrue(focused.exists, "opening Rate left focus nowhere")
        XCTAssertNotEqual(focused.label, "Play",
                          "B22: opening Rate dropped focus back onto Play")
        XCTAssertTrue(["Not for Me", "I Like This", "Love This"].contains(focused.label),
                      "expected a rating choice to hold focus, got '\(focused.label)'")
    }

    /// Owner Z3/D4: the icon row must be reachable and keep focus, which is
    /// where the ring-over-label and focus-vs-selection bugs showed up.
    func testTitlePageIconRowTakesFocus() {
        launch(screen: "detail")
        let play = element("detail.play")
        XCTAssertTrue(wait(for: play, 40), "the title page never appeared")

        remote.press(.down)
        let iconRow = element("detail.icon-row")
        XCTAssertTrue(iconRow.waitForExistence(timeout: 10), "the My List / Rate row never appeared")

        XCTAssertTrue(focusedElement.exists, "pressing down from Play left focus nowhere")
    }

    // MARK: - Hero artwork

    /// Owner 2026-09-20: "wordmarks not loading on (library) ap tv".
    ///
    /// The Library hero built `AppleFeaturedHero` without a `wordmark:`
    /// argument at all, so `AppleTVBillboardTitleTreatment` could only ever
    /// answer `.text`. This walks to the Library tab with the remote and keeps
    /// the frame, so the wordmark lockup is something a person can look at.
    func testLibraryHeroDrawsItsWordmarkOverTheBackdrop() {
        launch(screen: "library")
        let play = element("home.featured.play")
        XCTAssertTrue(wait(for: play, 60), "the Library billboard never appeared")
        // Give the wordmark and any textless upgrade time to land before the
        // frame is taken; neither blocks the billboard from drawing.
        Thread.sleep(forTimeInterval: 8.0)

        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "tvos-library-hero-wordmark"
        shot.lifetime = .keepAlways
        add(shot)

        // Focus has to reach the hero for the frame to be worth anything.
        remote.press(.down)
        Thread.sleep(forTimeInterval: 1.5)
        let focusedShot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        focusedShot.name = "tvos-library-hero-focused"
        focusedShot.lifetime = .keepAlways
        add(focusedShot)

        print("LIBRARY HERO focused='\(focusedElement.label)'")
    }

    /// Discover's hero already worked. The textless change touches the same
    /// billboard, so this is the no-regression frame beside it.
    func testDiscoverHeroStillDrawsAfterTheTextlessChange() {
        launch(screen: "discover")
        let play = element("home.featured.play")
        XCTAssertTrue(wait(for: play, 60), "the Discover billboard never appeared")
        Thread.sleep(forTimeInterval: 8.0)

        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "tvos-discover-hero"
        shot.lifetime = .keepAlways
        add(shot)
        XCTAssertTrue(play.exists, "Discover lost its billboard actions")
    }

    /// N12: the Discover hero after the Apple TV app. Read-only: focus moves
    /// over the buttons and pages, nothing is selected. Frames: at rest, after
    /// one cycle, focus on Play/Resume, on My List, and the page `→` turns.
    func testDiscoverHeroButtonsAndPagingKeepFocus() {
        launch(screen: "discover")
        let play = element("home.featured.play")
        XCTAssertTrue(wait(for: play, 60), "the Discover billboard never appeared")
        Thread.sleep(forTimeInterval: 6.0)
        attachScreen("n12-hero-rest")
        Thread.sleep(forTimeInterval: 13.0)
        attachScreen("n12-hero-after-cycle")

        // Down from the tab bar goes to the first row (the route as it was
        // before N12, untouched); up from there lands on the hero's first button.
        remote.press(.down)
        Thread.sleep(forTimeInterval: 1.5)
        print("N12 HERO down-from-tab-bar focused='\(focusedElement.identifier)'")
        if !play.hasFocus {
            remote.press(.up)
            Thread.sleep(forTimeInterval: 1.5)
            print("N12 HERO up-from-row focused='\(focusedElement.identifier)'")
        }
        // Up lands on the button nearest the card above; walk left to Play.
        for _ in 0..<2 where !play.hasFocus {
            remote.press(.left)
            Thread.sleep(forTimeInterval: 1.0)
        }
        XCTAssertTrue(play.hasFocus, "the hero's Play/Resume never took focus, got '\(focusedElement.identifier)'")
        attachScreen("n12-hero-focus-play")

        let myList = element("home.featured.my-list")
        if myList.exists {
            remote.press(.right)
            Thread.sleep(forTimeInterval: 1.5)
            XCTAssertTrue(myList.hasFocus, "right from Play should focus My List, got '\(focusedElement.identifier)'")
            attachScreen("n12-hero-focus-mylist")
        }

        // Right past the last button turns the page and keeps focus in the hero.
        let pages = element("home.featured.pages")
        let before = pages.exists ? pages.label : ""
        for _ in 0..<3 { remote.press(.right); Thread.sleep(forTimeInterval: 0.8) }
        Thread.sleep(forTimeInterval: 2.0)
        attachScreen("n12-hero-paged-right")
        let heroIDs = ["home.featured.play", "home.featured.my-list", "home.featured.details"]
        XCTAssertTrue(heroIDs.contains(focusedElement.identifier),
                      "paging moved focus out of the hero, to '\(focusedElement.identifier)'")
        print("N12 HERO pages before='\(before)' after='\(pages.exists ? pages.label : "")' focused='\(focusedElement.identifier)'")

        // Left past Play turns back a page and keeps focus on Play.
        for _ in 0..<2 where !play.hasFocus {
            remote.press(.left)
            Thread.sleep(forTimeInterval: 1.0)
        }
        let beforeLeft = pages.exists ? pages.label : ""
        remote.press(.left)
        Thread.sleep(forTimeInterval: 2.0)
        print("N12 HERO left-from-play pages before='\(beforeLeft)' after='\(pages.exists ? pages.label : "")' focused='\(focusedElement.identifier)'")
        XCTAssertTrue(play.hasFocus, "left past Play should keep focus on Play, got '\(focusedElement.identifier)'")
        XCTAssertNotEqual(beforeLeft, pages.exists ? pages.label : "", "left past Play should turn the page")

        // Down to the row and back up returns to the hero.
        remote.press(.down)
        Thread.sleep(forTimeInterval: 1.5)
        print("N12 HERO down-from-hero focused='\(focusedElement.identifier)'")
        XCTAssertFalse(heroIDs.contains(focusedElement.identifier), "down from the hero should leave it for the rows")
        remote.press(.up)
        Thread.sleep(forTimeInterval: 2.0)
        print("N12 HERO up-from-row-2 focused='\(focusedElement.identifier)'")
        XCTAssertTrue(heroIDs.contains(focusedElement.identifier), "up from the first row should return to the hero")

        // Up and down leave the hero as before: the paging stops never catch them.
        remote.press(.up)
        Thread.sleep(forTimeInterval: 1.5)
        print("N12 HERO up-from-hero focused='\(focusedElement.identifier)' label='\(focusedElement.label)'")
        // After a trip to the rows the first up only scrolls the page back to
        // its top; the second reaches the tab bar. The Library hero, which N12
        // does not touch, does the same (measured 2026-09-23).
        if heroIDs.contains(focusedElement.identifier) {
            remote.press(.up)
            Thread.sleep(forTimeInterval: 2.0)
            print("N12 HERO up-from-hero-again focused='\(focusedElement.identifier)' label='\(focusedElement.label)'")
        }
        XCTAssertFalse(heroIDs.contains(focusedElement.identifier), "up from the hero should reach the tab bar")
        attachScreen("n12-hero-up-from-hero")
        remote.press(.down)
        Thread.sleep(forTimeInterval: 1.5)
        print("N12 HERO down-again focused='\(focusedElement.identifier)' label='\(focusedElement.label)'")
        remote.press(.down)
        Thread.sleep(forTimeInterval: 1.5)
        print("N12 HERO down-again-2 focused='\(focusedElement.identifier)' label='\(focusedElement.label)'")
        XCTAssertFalse(heroIDs.contains(focusedElement.identifier), "down from the hero should leave it for the rows")
    }

    private func attachScreen(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

}
