import XCTest

/// Base for every UI test class: a failed test leaves a full-screen
/// screenshot in the result bundle, taken before the subclass tears the app
/// down, so a red run can be read without re-running it.
@MainActor
class OpenStreamUITestCase: XCTestCase {
    override func tearDownWithError() throws {
        if let run = testRun, run.totalFailureCount > 0 {
            let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            shot.name = "failure-\(name)"
            shot.lifetime = .keepAlways
            add(shot)
        }
        try super.tearDownWithError()
    }

    /// The stub fixtures beside the test plans (`Apps/TestPlans/Stubs`): from
    /// the plan's `OPENSTREAM_STUB_DIR`, else resolved from this file's path.
    static var stubDirectory: String {
        if let path = ProcessInfo.processInfo.environment["OPENSTREAM_STUB_DIR"], !path.isEmpty { return path }
        return URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("TestPlans/Stubs").path
    }

    /// Launch arguments for a stubbed, silent, traced run.
    static var stubbedLaunchArguments: [String] {
        ["-OpenStreamStubNetwork", stubDirectory, "-OpenStreamResetOnLaunch", "YES",
         "-OpenStreamTrace", "YES", "-OpenStreamMuteAudio", "YES"]
    }

    /// A fixture Jellyfin title on a Discover shelf (`Tests/Fixtures/serve.py`, /jf):
    /// `home.ms.<shelf>.ms:<source>:<item>`.
    static func serverShelfItem(_ itemID: String) -> NSPredicate {
        NSPredicate(format: "identifier BEGINSWITH 'home.ms.' AND identifier ENDSWITH %@", ":" + itemID)
    }

    /// `-OpenStreamDevSources` with only a TMDB key, so a stubbed run can search
    /// (`TestPlans/Stubs/api.themoviedb.org`). The app deletes the file once read.
    func tmdbFixtureKeyLaunchArguments() throws -> [String] {
        let file = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("tmdb-fixture-\(UUID().uuidString).json")
        try Data(#"{"version":1,"sources":[],"settings":{"tmdbAPIKey":"fixture"}}"#.utf8).write(to: file)
        return ["-OpenStreamDevSources", file.path]
    }
    /// Lazy Form rows must be built, and completely above the floating tab bar, before a tap.
    func scrollToControl(_ element: XCUIElement, in app: XCUIApplication, limit: Int = 12) {
        for _ in 0..<limit {
            let bar = app.tabBars.firstMatch
            let bottom = bar.exists && bar.frame.minY > app.frame.midY ? bar.frame.minY - 16 : app.frame.maxY - 16
            if element.exists, element.frame.minY >= app.frame.minY + 70,
               element.frame.maxY < bottom, element.isHittable { return }
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.72))
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35))
            start.press(forDuration: 0.05, thenDragTo: end)
        }
    }

    /// Test-plan arguments belong to the runner. Forward fixture settings to each
    /// app launch, including tests that replace launchArguments between routes.
    func configureFixtureLaunch(_ app: XCUIApplication) {
        guard ProcessInfo.processInfo.environment["OPENSTREAM_STUB_DIR"]?.isEmpty == false else { return }
        let mediaBase = ProcessInfo.processInfo.environment["OPENSTREAM_STUB_MEDIA_BASE"] ?? "http://127.0.0.1:8767"
        for (key, value) in [("-OpenStreamStubNetwork", Self.stubDirectory),
                             ("-OpenStreamStubMediaBase", mediaBase),
                             ("-OpenStreamMuteAudio", "YES"), ("-OpenStreamTrace", "YES")] {
            if !app.launchArguments.contains(key) { app.launchArguments += [key, value] }
        }
    }

}
