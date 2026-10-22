#if os(iOS) || os(visionOS)
import XCTest

/// The iPad's screens, and Vision Pro drawing the same ones (spec avp-native
/// 2026-10-18): the same checkpoints run unchanged on the iPad and the
/// Vision Pro simulators. Each checkpoint keeps a screenshot, the
/// accessibility tree and the system audit's findings as attachments.
@MainActor
final class ApplePadParityUITests: XCTestCase {
    private let app = XCUIApplication(bundleIdentifier: "com.orgista.openstream")
    private var teardownAdded = false

    /// An 11-inch iPad on its side; Vision Pro's opening window
    /// (`AppleVisionPlayerWindowPolicy.defaultWindowSize`).
    private static let defaultSize = CGSize(width: 1180, height: 820)
    #if os(visionOS)
    /// `AppleVisionPlayerWindowPolicy.browseMinimum`.
    private static let smallestSize = CGSize(width: 960, height: 600)
    #else
    override func setUpWithError() throws {
        try super.setUpWithError()
        try XCTSkipIf(UIDevice.current.userInterfaceIdiom != .pad, "iPad parity")
    }
    #endif

    private var stubs: String {
        ProcessInfo.processInfo.environment["OPENSTREAM_STUB_DIR"]
            ?? URL(fileURLWithPath: #filePath).deletingLastPathComponent()
                .deletingLastPathComponent().appendingPathComponent("TestPlans/Stubs").path
    }

    func testDiscoverLibraryAndSettingsUseTheIPadLayout() throws {
        launch("discover")
        let pages = element("home.featured.pages")
        XCTAssertTrue(pages.waitForExistence(timeout: 60), "Discover has no billboard pages")
        XCTAssertTrue((pages.value as? String)?.hasPrefix("Page ") == true)
        let previousPage = try XCTUnwrap(pages.value as? String)
        contentWindow.swipeLeft()
        let changed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value != %@", previousPage), object: pages)
        XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 5), .completed, "Swiping did not page the billboard")
        let myList = element("home.featured.my-list")
        XCTAssertTrue(myList.exists)
        myList.tap()
        let saved = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "Saved"), object: myList)
        XCTAssertEqual(XCTWaiter.wait(for: [saved], timeout: 10), .completed)
        try checkpoint("discover-billboard")
        // The stub folder source leaves the Library empty on both platforms,
        // so this is the page and its controls, not a billboard.
        launch("library")
        XCTAssertTrue(element("library.sort").waitForExistence(timeout: 60), "Library did not draw")
        try checkpoint("library")
        launch("settings")
        XCTAssertTrue(element("settings.discover.enabled").waitForExistence(timeout: 60), "Settings did not draw")
        let shownSection = app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@ AND selected == true", "Sources")).firstMatch
        XCTAssertTrue(shownSection.waitForExistence(timeout: 10), "Settings is not a sidebar and a pane")
        try checkpoint("settings")
    }

    func testLiveStageGuideAndSearchUseTheOnNowList() throws {
        launch("live")
        XCTAssertTrue(element("live.stage.player").waitForExistence(timeout: 60))
        XCTAssertTrue(element("live.categories").exists)
        XCTAssertTrue(element("live.list").exists)
        let channel = app.buttons.matching(NSPredicate(format: "label == %@", "Play Fixture News")).firstMatch
        XCTAssertTrue(channel.waitForExistence(timeout: 20))
        #if os(iOS)
        // Paramount+ on iPad (owner 2026-10-21): the stage spans the window, the list fills the rest below it.
        let stage = element("live.stage.player")
        XCTAssertEqual(stage.frame.width, app.frame.width, accuracy: 1)
        XCTAssertGreaterThan(element("live.guide").frame.minY, stage.frame.maxY - 1)
        XCTAssertGreaterThan(channel.frame.minY, stage.frame.maxY - 1)
        #endif
        try checkpoint("live-stage")
        element("live.guide").tap()
        let done = element("live.guide.done")
        XCTAssertTrue(done.waitForExistence(timeout: 15))
        let guideReady = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"), object: done)
        XCTAssertEqual(XCTWaiter.wait(for: [guideReady], timeout: 5), .completed, "The Guide did not finish presenting")
        try checkpoint("live-guide")
        done.tap()
        element("live.search").tap()
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 15))
        field.tap()
        field.typeText("Fixture News\n")
        XCTAssertTrue(channel.waitForExistence(timeout: 15))
        try checkpoint("live-search")
        // A row on the stage plays in the frame above the list. (Choosing a
        // search result does not switch the channel on the iPad either.)
        launch("live")
        XCTAssertTrue(channel.waitForExistence(timeout: 60))
        channel.tap()
        let playing = app.descendants(matching: .any).matching(
            NSPredicate(format: "label == %@", "Live player for Fixture News")).firstMatch
        let started = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "Playing"), object: playing)
        XCTAssertEqual(XCTWaiter.wait(for: [started], timeout: 45), .completed, "The channel did not play inline")
        capture("live-inline")
    }

    /// The fixture Jellyfin's Stub Series (`Tests/Fixtures/serve.py`): two seasons of three chapters.
    func testSeriesHasEpisodeRailAndSeasonMenu() throws {
        launch("detail")
        XCTAssertTrue(screen("detail.screen.series.").waitForExistence(timeout: 60))
        XCTAssertTrue(element("detail.play").waitForExistence(timeout: 30))
        try checkpoint("series-hero")
        let rail = element("detail.episodes")
        scrollTo(rail)
        XCTAssertTrue(rail.exists)
        let seasonOne = rail.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Chapter 1."))
        XCTAssertTrue(seasonOne.firstMatch.waitForExistence(timeout: 15))
        XCTAssertGreaterThanOrEqual(seasonOne.count, 2)
        XCTAssertEqual(seasonOne.element(boundBy: 0).frame.minY, seasonOne.element(boundBy: 1).frame.minY,
                       accuracy: 2, "Episodes are stacked instead of a rail")
        try checkpoint("series-episodes")
        element("detail.season").tap()
        let seasonTwo = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier == %@ OR label == %@", "detail.season.2", "Season 2")).firstMatch
        XCTAssertTrue(seasonTwo.waitForExistence(timeout: 10))
        capture("series-season-menu")
        seasonTwo.tap()
        XCTAssertTrue(rail.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Chapter 2.1")).firstMatch
            .waitForExistence(timeout: 15), "Season 2's episodes did not load")
        try checkpoint("series-season-two")
    }

    func testMovieHeroHasMetadataAndPlay() throws {
        launch("detail-movie")
        XCTAssertTrue(screen("detail.screen.movie.").waitForExistence(timeout: 60))
        XCTAssertTrue(element("detail.play").waitForExistence(timeout: 30))
        XCTAssertTrue(element("detail.play").isHittable)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Stub Movie")).firstMatch.exists)
        try checkpoint("movie-hero")
    }

    func testPortraitTitleHeroContainsThePlayAction() throws {
        #if os(visionOS)
        launch("detail-movie", size: CGSize(width: Self.smallestSize.width, height: 1100))
        #else
        launch("detail-movie", size: CGSize(width: 820, height: 1180))
        #endif
        let play = element("detail.play")
        XCTAssertTrue(play.waitForExistence(timeout: 60))
        let reachable = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"), object: play)
        XCTAssertEqual(XCTWaiter.wait(for: [reachable], timeout: 5), .completed, "Play is not reachable upright")
        XCTAssertLessThan(play.frame.maxY, contentWindow.frame.maxY, "Play fell below the window")
        try checkpoint("movie-hero-portrait")
    }

    func testLargestTextKeepsRowsTitleAndLiveActionsReachable() throws {
        // The iPad leaves out the billboard at these sizes and opens on the rows.
        launch("discover", largestText: true)
        let poster = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "home.ms.")).firstMatch
        XCTAssertTrue(poster.waitForExistence(timeout: 60))
        XCTAssertTrue(poster.isHittable, "The largest text size hid Discover's first row")
        capture("discover-largest-text")
        launch("library", largestText: true)
        XCTAssertTrue(element("library.sort").waitForExistence(timeout: 60))
        capture("library-largest-text")
        launch("detail-movie", largestText: true)
        let play = element("detail.play")
        XCTAssertTrue(play.waitForExistence(timeout: 60))
        XCTAssertTrue(play.isHittable, "The largest text size hid Play")
        capture("movie-largest-text")
        launch("detail", largestText: true)
        XCTAssertTrue(element("detail.play").waitForExistence(timeout: 60))
        let episodes = element("detail.episodes")
        scrollTo(episodes)
        XCTAssertTrue(episodes.exists)
        capture("episodes-largest-text")
        launch("live", largestText: true)
        let channel = app.buttons.matching(NSPredicate(format: "label == %@", "Play Fixture News")).firstMatch
        XCTAssertTrue(channel.waitForExistence(timeout: 60))
        scrollTo(channel)
        XCTAssertTrue(channel.isHittable, "The largest text size hid the channel list")
        capture("live-largest-text")
    }

    #if os(visionOS)
    func testSmallestWindowKeepsTheIPadLayout() throws {
        launch("live", size: Self.smallestSize)
        let channel = app.buttons.matching(NSPredicate(format: "label == %@", "Play Fixture News")).firstMatch
        XCTAssertTrue(channel.waitForExistence(timeout: 60))
        XCTAssertTrue(channel.isHittable)
        let player = element("live.stage.player")
        XCTAssertGreaterThan(channel.frame.minX, player.frame.maxX - 1,
                             "The channel list left the player's side in the smallest window")
        try checkpoint("live-stage-smallest")
        launch("detail", size: Self.smallestSize)
        let play = element("detail.play")
        XCTAssertTrue(play.waitForExistence(timeout: 60))
        XCTAssertTrue(play.isHittable)
        try checkpoint("series-hero-smallest")
    }
    #endif

    private func launch(_ screen: String, size: CGSize = ApplePadParityUITests.defaultSize, largestText: Bool = false) {
        continueAfterFailure = false
        if !teardownAdded {
            teardownAdded = true
            addTeardownBlock { @MainActor [self] in
                defer {
                    app.terminate()
                    #if os(iOS)
                    XCUIDevice.shared.orientation = .portrait
                    #endif
                }
                if let run = testRun, run.totalFailureCount > 0 { capture("failure-\(name)") }
            }
        }
        #if os(iOS)
        XCUIDevice.shared.orientation = size.width > size.height ? .landscapeLeft : .portrait
        #endif
        app.terminate()
        app.launchArguments = ["-OpenStreamStubNetwork", stubs, "-OpenStreamResetOnLaunch", "YES",
            "-OpenStreamStubMediaBase", "http://127.0.0.1:8767", "-OpenStreamMuteAudio", "YES",
            "-OpenStreamTrace", "YES", "-openstream.firstRunGuidanceSeen", "YES",
            "-openstream.backup.icloud.enabled.v1", "NO", "-OpenStreamVisionScreen", screen,
            "-openstream.settings.trailer.autoplay.v1", "NO"]
        if largestText {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        }
        #if os(visionOS)
        app.launchArguments += ["-OpenStreamVisionBrowseWidth", String(Int(size.width)),
                                "-OpenStreamVisionBrowseHeight", String(Int(size.height))]
        #endif
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 45))
        #if os(visionOS)
        let fitted = XCTNSPredicateExpectation(predicate: NSPredicate { object, _ in
            guard let window = object as? XCUIElement else { return false }
            let frame = window.frame
            return frame.height > 0 && abs(frame.width / frame.height - size.width / size.height) <= 0.02
        }, object: contentWindow)
        XCTAssertEqual(XCTWaiter.wait(for: [fitted], timeout: 15), .completed, "The window did not take its requested size")
        #endif
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func screen(_ prefix: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", prefix)).firstMatch
    }

    private var contentWindow: XCUIElement {
        app.windows.allElementsBoundByIndex.filter { $0.frame.width >= 480 && $0.frame.height >= 260 }
            .min { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height } ?? app.windows.firstMatch
    }

    private func scrollTo(_ element: XCUIElement) {
        for _ in 0..<12 {
            if element.exists, element.isHittable,
               element.frame.midY < contentWindow.frame.maxY - 80 { return }
            let start = contentWindow.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.82))
            let end = contentWindow.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.30))
            start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.3)
        }
    }

    /// A screenshot and the accessibility tree, plus the system audit's
    /// findings as attachments. The audit is recorded, not enforced: the
    /// iPad must stay as it is, and these runs compare the two platforms.
    private func checkpoint(_ name: String) throws {
        capture(name)
        var findings: [String] = []
        try app.performAccessibilityAudit { issue in
            findings.append(issue.detailedDescription + "\n" + (issue.element?.debugDescription ?? "Application-level issue"))
            return true
        }
        let audit = XCTAttachment(string: findings.isEmpty ? "No findings" : findings.joined(separator: "\n\n"))
        audit.name = "\(name)-audit-\(findings.count)"
        audit.lifetime = .keepAlways
        add(audit)
    }

    /// The Vision Pro simulator's `XCUIScreen` screenshot comes back blank, so
    /// a runner can pass `OPENSTREAM_VISION_CAPTURE_URL`, an endpoint on the
    /// host that saves `simctl io screenshot` under `?name=`.
    private func capture(_ name: String) {
        let tree = XCTAttachment(string: app.debugDescription)
        tree.name = name + "-accessibility"
        tree.lifetime = .keepAlways
        add(tree)
        guard let endpoint = ProcessInfo.processInfo.environment["OPENSTREAM_VISION_CAPTURE_URL"],
              var components = URLComponents(string: endpoint) else {
            let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            shot.name = name
            shot.lifetime = .keepAlways
            add(shot)
            return
        }
        components.queryItems = [URLQueryItem(name: "name", value: name)]
        guard let url = components.url else { return XCTFail("Bad capture endpoint \(endpoint)") }
        let saved = expectation(description: "capture \(name)")
        URLSession.shared.dataTask(with: url) { _, response, error in
            XCTAssertNil(error)
            XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200, "Host capture of \(name) failed")
            saved.fulfill()
        }.resume()
        wait(for: [saved], timeout: 30)
    }
}
#endif
