import XCTest

/// Launch → Discover row → title page → back on the Apple TV, with every
/// control-plane request answered from `Apps/TestPlans/Stubs`
/// (`-OpenStreamStubNetwork`): no network, no owner sources.
@MainActor
final class AppleTVStubSmokeUITests: OpenStreamUITestCase {
    private var app: XCUIApplication!
    private var remote: XCUIRemote { .shared }

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication(bundleIdentifier: "com.orgista.openstream")
        app.launchArguments = Self.stubbedLaunchArguments
    }

    override func tearDown() {
        app?.terminate()
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private var focusedElement: XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "hasFocus == true")).firstMatch
    }

    func testDiscoverRowOpensATitleFromStubsAndComesBack() {
        configureFixtureLaunch(app)
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30))

        XCTAssertTrue(focusedElement.waitForExistence(timeout: 60), "Discover never took focus")
        // f82ef99 deduplicates the previous three rows: Movie One is already
        // in Your Library, so the catalog shelf starts with Movie Two.
        let posterID = "home.media.movie:tt0000002"
        let poster = element(posterID)

        // Walk focus down from the hero until the poster holds it (the shelf
        // is lazy and only enters the hierarchy as focus reaches it), then open.
        let focusedPoster = app.descendants(matching: .any).matching(NSPredicate(
            format: "hasFocus == true AND identifier == %@", posterID)).firstMatch
        for _ in 0 ..< 10 where !focusedPoster.exists {
            remote.press(.down)
            _ = focusedPoster.waitForExistence(timeout: 2)
        }
        XCTAssertTrue(focusedPoster.exists, "focus never reached the stub poster; sits on '\(focusedElement.identifier)'")
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "discover-stub-movies-tv"
        shot.lifetime = .keepAlways
        add(shot)
        remote.press(.select)

        let play = element("detail.play")
        XCTAssertTrue(play.waitForExistence(timeout: 30), "the title page never opened")
        XCTAssertTrue(app.staticTexts["Stub Movie Two"].firstMatch.waitForExistence(timeout: 10))

        remote.press(.menu)
        XCTAssertTrue(poster.waitForExistence(timeout: 30), "Discover did not come back")
    }

    /// Moves focus one way until `identifier` holds it.
    @discardableResult
    private func focus(_ identifier: String, pressing direction: XCUIRemote.Button, limit: Int = 12) -> Bool {
        focus(NSPredicate(format: "identifier == %@", identifier), pressing: direction, limit: limit)
    }

    /// Form rows take focus as a cell that carries the row's label, not the
    /// identifier of the button inside it.
    @discardableResult
    private func focus(_ predicate: NSPredicate, pressing direction: XCUIRemote.Button, limit: Int = 12) -> Bool {
        let target = app.descendants(matching: .any).matching(NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "hasFocus == true"), predicate])).firstMatch
        for _ in 0 ..< limit where !target.exists {
            remote.press(direction)
            _ = target.waitForExistence(timeout: 1.5)
        }
        return target.exists
    }

    /// Library → Unmatched → Match picks a title, which leaves the shelf with
    /// its art; Use Automatic Match on the title page puts it back.
    func testUnmatchedShelfMatchesAndReverts() {
        // The reset clears metadata keys and lookup caches left on the
        // simulator, so the fixture's misses cache as no-matches.
        app.launchArguments = ["-OpenStreamLibraryTitlesFixture"] + Self.stubbedLaunchArguments
        app.launchEnvironment["OPENSTREAM_LIBRARY_FIXTURE_PATH"] = Self.stubDirectory + "/library-unmatched"
        app.launch()
        func shot(_ name: String) {
            let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            shot.name = name
            shot.lifetime = .keepAlways
            add(shot)
        }

        // The Library is lazy: Unmatched enters the hierarchy as focus reaches it.
        let tileID = "library.unmatched.Quiet Harbor Home Video"
        XCTAssertTrue(focusedElement.waitForExistence(timeout: 60), "the Library never took focus")
        // The shelf is A–Z, so focus lands on Lantern Street first.
        let firstID = "library.unmatched.Lantern Street Rehearsal"
        XCTAssertTrue(focus(firstID, pressing: .down), "focus never reached Unmatched; sits on '\(focusedElement.identifier)'")
        XCTAssertTrue(focus(tileID, pressing: .right, limit: 3))
        shot("unmatched-shelf-tv")
        remote.press(.select)

        let query = element("detail.fixMatch.query")
        XCTAssertTrue(query.waitForExistence(timeout: 10), "Match did not open")
        XCTAssertTrue(focus("detail.fixMatch.query", pressing: .up))
        remote.press(.select)
        sleep(2)
        app.typeText("Stub Movie Two")
        remote.press(.menu)
        XCTAssertTrue(focus(NSPredicate(format: "label == 'Search'"), pressing: .down), "Search never took focus")
        remote.press(.select)
        let resultID = "detail.fixMatch.result.tt0000002"
        XCTAssertTrue(element(resultID).waitForExistence(timeout: 20), "no search result")
        XCTAssertTrue(focus(NSPredicate(format: "label CONTAINS '2024'"), pressing: .down), "the result never took focus")
        shot("unmatched-match-results-tv")
        remote.press(.select)
        XCTAssertTrue(element(tileID).waitForNonExistence(timeout: 10), "the matched title stayed on the Unmatched shelf")
        shot("unmatched-after-match-tv")

        XCTAssertTrue(focus("library.title.Quiet Harbor Home Video", pressing: .up), "the matched title never took focus")
        remote.press(.select)
        let play = element("detail.play")
        XCTAssertTrue(play.waitForExistence(timeout: 30), "the title page never opened")
        XCTAssertTrue(focus("detail.play", pressing: .right))
        remote.press(.select, forDuration: 1.5)
        XCTAssertTrue(element("detail.fixMatch").waitForExistence(timeout: 5))
        XCTAssertEqual(element("detail.fixMatch").label, "Change Metadata")
        // Menu items take focus as an unlabelled cell around the item.
        let automatic = app.cells.containing(.any, identifier: "detail.automaticMatch").firstMatch
        XCTAssertTrue(automatic.waitForExistence(timeout: 5), "a manual match offers no way back")
        for _ in 0 ..< 6 where !automatic.hasFocus { remote.press(.down) }
        XCTAssertTrue(automatic.hasFocus, "Use Automatic Match never took focus")
        shot("unmatched-title-menu-tv")
        remote.press(.select)

        remote.press(.menu)
        // Focus may come back to any Unmatched tile, the reverted one included.
        XCTAssertTrue(focus(NSPredicate(format: "identifier BEGINSWITH 'library.unmatched.'"), pressing: .down),
                      "Unmatched did not come back")
        XCTAssertTrue(element(tileID).hasFocus || focus(tileID, pressing: .right, limit: 3),
                      "Use Automatic Match did not return the title to Unmatched")
    }
}
