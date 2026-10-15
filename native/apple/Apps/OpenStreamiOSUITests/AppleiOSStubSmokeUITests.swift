import XCTest

/// Launch → Discover row → title page → back, with every control-plane
/// request answered from `Apps/TestPlans/Stubs` (`-OpenStreamStubNetwork`):
/// no network, no owner sources, the same screen every run.
@MainActor
final class AppleiOSStubSmokeUITests: OpenStreamUITestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication(bundleIdentifier: "com.orgista.openstream")
        app.launchArguments = Self.stubbedLaunchArguments
    }

    override func tearDown() {
        app?.terminate()
    }

    func testTitlePageFillDistribution() throws {
        guard ProcessInfo.processInfo.environment["OPENSTREAM_DETAIL_SPEED_MEASURE"] == "1" else {
            throw XCTSkip("Opt-in repeated library opening measurement")
        }
        app.launchArguments = ["-OpenStreamLibraryTitlesFixture", "-OpenStreamStubNetwork", Self.stubDirectory,
            "-OpenStreamTrace", "YES", "-OpenStreamMuteAudio", "YES",
            "-OpenStreamDebugDetailsDelay", "2"]
        app.launchEnvironment["OPENSTREAM_LIBRARY_FIXTURE_PATH"] = Self.stubDirectory + "/library"
        for mode in ["cold", "warm"] {
            for sample in 1...10 {
                if mode == "cold" {
                    app.terminate()
                    app.launchEnvironment["OPENSTREAM_DETAIL_SPEED_COLD"] = mode == "cold" ? "1" : "0"
                    app.launch()
                }
                let tile = app.descendants(matching: .any).matching(identifier: "library.title.Stub Movie One").firstMatch
                XCTAssertTrue(tile.waitForExistence(timeout: 60))
                // The same shelf dwell in both builds lets the normal library
                // matcher publish catalog fields before navigation.
                Thread.sleep(forTimeInterval: 2)
                tile.tap()
                XCTAssertTrue(app.buttons["detail.play"].firstMatch.waitForExistence(timeout: 20))
                Thread.sleep(forTimeInterval: 2)
                let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
                shot.name = "detail-speed-\(mode)-\(sample)"
                shot.lifetime = .keepAlways
                add(shot)
                let back = app.buttons["detail.back"].firstMatch
                if back.exists { back.tap() } else { app.navigationBars.buttons.firstMatch.tap() }
                XCTAssertTrue(tile.waitForExistence(timeout: 10))
            }
        }
    }

    func testDiscoverRowOpensATitleFromStubsAndComesBack() {
        configureFixtureLaunch(app)
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30))

        // Discover is lazy: the stub shelf sits under the hero, so it is not
        // in the hierarchy until it has scrolled into view.
        let poster = app.descendants(matching: .any).matching(identifier: "home.media.movie:tt0000001").firstMatch
        XCTAssertTrue(app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH 'home.' OR identifier BEGINSWITH 'discover.'")).firstMatch
            .waitForExistence(timeout: 60), "Discover never drew")
        for _ in 0 ..< 8 where !(poster.exists && poster.isHittable) {
            app.swipeUp()
            _ = poster.waitForExistence(timeout: 3)
        }
        XCTAssertTrue(poster.exists && poster.isHittable, "the stub catalog row never drew")
        poster.tap()

        let play = app.buttons["detail.play"].firstMatch
        XCTAssertTrue(play.waitForExistence(timeout: 30), "the title page never opened")
        XCTAssertTrue(app.staticTexts["Stub Movie One"].firstMatch.waitForExistence(timeout: 10))

        let back = app.buttons["detail.back"].firstMatch
        if back.waitForExistence(timeout: 5) { back.tap() } else { app.navigationBars.buttons.firstMatch.tap() }
        XCTAssertFalse(play.waitForExistence(timeout: 5), "the title page did not close")
        XCTAssertTrue(poster.waitForExistence(timeout: 30), "Discover did not come back")
    }
}
