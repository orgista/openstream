import XCTest

/// Runs only with the demo launch environment supplied by the local test runner.
/// No demo address or credential is stored in the project or test plan.
@MainActor
final class AppStoreScreenshotUITests: XCTestCase {
    private let app = XCUIApplication(bundleIdentifier: "com.orgista.openstream")
    private var serverAdded = false
    private var liveAdded = false
    private var downloadAttempted = false
    private var emptyDownloadsVerified = false

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func button(_ label: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label == %@", label)).firstMatch
    }

    private func activate(_ target: XCUIElement) throws {
        XCTAssertTrue(target.waitForExistence(timeout: 30), "Expected navigation control is absent")
        #if os(tvOS)
        for step in 0..<40 {
            if target.hasFocus { XCUIRemote.shared.press(.select); Thread.sleep(forTimeInterval: 0.7); return }
            let focused = app.descendants(matching: .any).matching(NSPredicate(format: "hasFocus == true")).firstMatch
            if focused.exists {
                let from = focused.frame, to = target.frame
                if from.midY < 150 && to.midY > 150 {
                    XCUIRemote.shared.press(.down)
                } else if from.maxX < to.minX - 20 {
                    XCUIRemote.shared.press(.right)
                } else if from.minX > to.maxX + 20 {
                    XCUIRemote.shared.press(.left)
                } else if abs(to.midY - from.midY) > 35 {
                    XCUIRemote.shared.press(to.midY > from.midY ? .down : .up)
                } else {
                    XCUIRemote.shared.press(to.midX > from.midX ? .right : .left)
                }
            } else {
                XCUIRemote.shared.press(step % 2 == 0 ? .up : .right)
            }
        }
        capture("failure-focus")
        let focus = app.descendants(matching: .any).matching(NSPredicate(format: "hasFocus == true"))
            .allElementsBoundByIndex.map { "\($0.elementType.rawValue) \($0.identifier) \($0.frame)" }.joined(separator: "\n")
        let proof = XCTAttachment(string: focus + "\nTarget: \(target.frame)")
        proof.name = "proof-focus-geometry"; proof.lifetime = .keepAlways; add(proof)
        XCTFail("Remote could not reach the requested control")
        throw NavigationFailure.unreachable
        #else
        if !target.isHittable {
            #if os(iOS)
            app.swipeUp()
            #endif
        }
        target.tap()
        #endif
    }

    private func tab(_ name: String) throws {
        #if os(tvOS)
        for _ in 0..<6 { XCUIRemote.shared.press(.up) }
        #endif
        let target = app.descendants(matching: .any).matching(NSPredicate(format:
            "label == %@ AND (elementType == %d OR elementType == %d)", name,
            XCUIElement.ElementType.button.rawValue, XCUIElement.ElementType.tab.rawValue)).firstMatch
        try activate(target)
        #if os(tvOS)
        Thread.sleep(forTimeInterval: 2)
        #endif
    }

    private func back() {
        #if os(tvOS)
        XCUIRemote.shared.press(.menu)
        #else
        let back = app.navigationBars.buttons.firstMatch
        if back.exists { back.tap() }
        #endif
    }

    private func capture(_ name: String) {
        #if os(macOS)
        let screenProof = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenProof.name = "proof-screen-" + name
        screenProof.lifetime = .keepAlways
        add(screenProof)
        let attachment = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        #else
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        #endif
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func fill(_ identifier: String, _ value: String) throws {
        let secure = app.secureTextFields.matching(identifier: identifier).firstMatch
        let identified = app.textFields.matching(identifier: identifier).firstMatch
        let fallback = ["sources.live.name": "Name", "sources.live.endpoint": "Playlist URL"][identifier]
        let text = identified.exists ? identified : (fallback.map { app.textFields[$0] } ?? identified)
        let field = secure.exists ? secure : text
        try activate(field)
        field.typeText(value)
        if !secure.exists {
            XCTAssertEqual(field.value as? String, value, "The input field dropped characters")
        }
        #if os(tvOS)
        XCUIRemote.shared.press(.menu)
        #endif
    }

    private func sources() throws {
        try tab("Settings")
        #if !os(tvOS)
        try activate(button("Sources"))
        #endif
    }

    func testAppStorePass() throws {
        let processEnvironment = ProcessInfo.processInfo.environment
        var env = processEnvironment
        if let hex = processEnvironment["OPENSTREAM_DEMO_CONFIG_HEX"] {
            let bytes = stride(from: 0, to: hex.count, by: 2).compactMap { offset -> UInt8? in
                let start = hex.index(hex.startIndex, offsetBy: offset)
                let end = hex.index(start, offsetBy: 2)
                return UInt8(hex[start..<end], radix: 16)
            }
            env = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(bytes)) as? [String: String])
        }
        guard let server = env["OPENSTREAM_DEMO_SERVER"],
              let user = env["OPENSTREAM_DEMO_USER"],
              let password = env["OPENSTREAM_DEMO_PASSWORD"],
              let playlist = env["OPENSTREAM_TEST_M3U"] else {
            throw XCTSkip("The private demo launch environment is required")
        }
        continueAfterFailure = false
        XCTAssertTrue(server.contains("://"), "The demo server environment lost its URL scheme delimiter")
        XCTAssertFalse(password.isEmpty, "The demo password environment is empty")
        app.launchArguments = ["-OpenStreamMuteAudio", "YES", "-OpenStreamTrace", "YES"]
        app.launchEnvironment = ["OPENSTREAM_DEMO_SERVER": server, "OPENSTREAM_DEMO_USER": user,
                                 "OPENSTREAM_DEMO_PASSWORD": password, "OPENSTREAM_TEST_M3U": playlist]
        app.launch()
        defer { try? removeDemoDownloads(); try? removeDemoSources(); app.terminate() }
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 45))
        #if os(macOS)
        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 30))
        let corner = window.coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 1)).withOffset(CGVector(dx: -3, dy: -3))
        let size = window.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 1437, dy: 897))
        corner.press(forDuration: 0.1, thenDragTo: size)
        #endif
        if button("Not Now").waitForExistence(timeout: 8) { try activate(button("Not Now")) }
        XCTAssertFalse(app.staticTexts["Couldn't Load Your Catalogs"].exists)
        try sources()
        capture("07-sources")
        #if os(iOS)
        back()
        try activate(button("Storage"))
        Thread.sleep(forTimeInterval: 2)
        XCTAssertFalse(button("Delete All Downloads").isEnabled, "Demo downloads require an initially empty download store")
        emptyDownloadsVerified = true
        back()
        try sources()
        #endif
        try activate(button("Media Server"))
        try fill("sources.mediaServer.name", "Home Server")
        try fill("sources.mediaServer.url", server)
        #if os(tvOS)
        let quick = element("sources.mediaServer.quickConnect")
        XCTAssertTrue(quick.waitForExistence(timeout: 15))
        try activate(quick)
        let code = element("sources.mediaServer.quickConnect.code")
        XCTAssertTrue(code.waitForExistence(timeout: 15))
        let token = try authenticate(server: server, user: user, password: password)
        var parts = URLComponents(string: server + "/QuickConnect/Authorize")!
        parts.queryItems = [URLQueryItem(name: "code", value: code.label.filter(\.isNumber))]
        var request = URLRequest(url: parts.url!)
        request.httpMethod = "POST"
        request.setValue("MediaBrowser Token=\"\(token)\"", forHTTPHeaderField: "Authorization")
        try send(request)
        let connected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: code)
        XCTAssertEqual(XCTWaiter.wait(for: [connected], timeout: 45), .completed, "Quick Connect did not save the source")
        #else
        try fill("sources.mediaServer.username", user)
        try fill("sources.mediaServer.password", password)
        #if os(iOS)
        app.toolbars.buttons["Done"].firstMatch.tapIfPresent()
        #endif
        XCTAssertEqual(app.textFields.matching(identifier: "sources.mediaServer.url").firstMatch.value as? String, server)
        try activate(element("sources.mediaServer.save"))
        #endif
        serverAdded = true
        let saved = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: element("sources.mediaServer.save"))
        let saveResult = XCTWaiter.wait(for: [saved], timeout: 45)
        if saveResult != .completed { capture("failure-source-save") }
        XCTAssertEqual(saveResult, .completed, "Source save did not dismiss the form")
        app.terminate()
        app.launch()
        try tab("Discover")
        let movie = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Big Buck Bunny'")).firstMatch
        let firstPoster = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'home.ms.'")).firstMatch
        XCTAssertTrue(firstPoster.waitForExistence(timeout: 90), "Saved server did not produce its library after relaunch")
        capture("01-discover")
        let shelfY = firstPoster.frame.midY
        for _ in 0..<12 {
            if movie.exists && movie.frame.width > 0 && app.frame.contains(CGPoint(x: movie.frame.midX, y: movie.frame.midY)) { break }
            #if os(tvOS)
            XCUIRemote.shared.press(.right)
            #else
            app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: app.frame.width * 0.9, dy: shelfY))
                .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: .zero)
                    .withOffset(CGVector(dx: app.frame.width * 0.1, dy: shelfY)))
            #endif
        }
        XCTAssertTrue(movie.exists, "The demo movie is absent from the shelf")
        try activate(movie)
        XCTAssertTrue(element("detail.play").waitForExistence(timeout: 30))
        capture("02-title")
        try activate(element("detail.play"))
        XCTAssertTrue(element("player.close").waitForExistence(timeout: 45))
        #if os(iOS)
        XCUIDevice.shared.orientation = .landscapeLeft
        #endif
        Thread.sleep(forTimeInterval: 20)
        #if os(tvOS)
        XCUIRemote.shared.press(.select)
        #else
        app.tap()
        #endif
        capture("04-player")
        XCTAssertFalse(element("player.play-pause").label.isEmpty)
        if element("player.skip-forward").exists {
            for _ in 0..<3 { try activate(element("player.skip-forward")) }
        }
        try activate(element("player.close"))
        #if os(iOS)
        XCUIDevice.shared.orientation = .portrait
        #endif
        XCTAssertTrue(element("detail.play").waitForExistence(timeout: 30))
        let resume = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS 'Resume'"), object: element("detail.play"))
        let resumed = XCTWaiter.wait(for: [resume], timeout: 15)
        if resumed != .completed { capture("failure-resume") }
        XCTAssertEqual(resumed, .completed, "Playback did not retain a resume position")
        try activate(element("detail.play"))
        XCTAssertTrue(element("player.close").waitForExistence(timeout: 30))
        try activate(element("player.close"))
        #if os(iOS)
        let download = element("detail.download")
        XCTAssertTrue(download.waitForExistence(timeout: 30))
        downloadAttempted = true
        try activate(download)
        let complete = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label BEGINSWITH 'Downloaded'"), object: download)
        let downloaded = XCTWaiter.wait(for: [complete], timeout: 180)
        if downloaded != .completed { capture("failure-download") }
        XCTAssertEqual(downloaded, .completed, "The demo download did not complete")
        try activate(element("detail.play"))
        XCTAssertTrue(element("player.close").waitForExistence(timeout: 45))
        Thread.sleep(forTimeInterval: 3)
        try activate(element("player.close"))
        #endif
        back()
        try tab("Library")
        try tab("Discover")
        capture("06-continue-watching")
        try sources()
        try activate(button("Live TV"))
        #if os(tvOS)
        try activate(element("sources.live.type.m3u"))
        #else
        let typePicker = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Xtream Account")).firstMatch
        try activate(typePicker)
        try activate(button("M3U Playlist"))
        #endif
        try fill("sources.live.name", "Open Movies")
        try fill("sources.live.endpoint", playlist)
        #if os(iOS)
        app.toolbars.buttons["Done"].firstMatch.tapIfPresent()
        #endif
        try activate(element("sources.live.save"))
        liveAdded = true
        try tab("Live")
        Thread.sleep(forTimeInterval: 8)
        capture("05-live")
        try tab("Settings")
        #if !os(tvOS)
        back()
        #endif
        capture("09-settings")
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'add-on'")).firstMatch.exists)
        // Cleanup uses the same source editor as the owner; it never resets the app.
        try removeDemoDownloads()
        try removeDemoSources()
    }

    private func removeDemoDownloads() throws {
        #if os(iOS)
        guard emptyDownloadsVerified, downloadAttempted else { return }
        try tab("Settings")
        for _ in 0..<3 where !button("Storage").exists { back() }
        try activate(button("Storage"))
        Thread.sleep(forTimeInterval: 2)
        let remove = button("Delete All Downloads")
        if remove.isEnabled {
            try activate(remove)
            try activate(app.alerts.buttons["Delete"])
            let removed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isEnabled == false"), object: remove)
            XCTAssertEqual(XCTWaiter.wait(for: [removed], timeout: 30), .completed)
        }
        downloadAttempted = false
        back()
        #endif
    }

    private func removeDemoSources() throws {
        for name in [serverAdded ? "Home Server" : nil, liveAdded ? "Open Movies" : nil].compactMap({ $0 }) {
            try sources()
            let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", name)).firstMatch
            if row.waitForExistence(timeout: 5) {
                try activate(row)
                let remove = button("Remove Source")
                if remove.exists { try activate(remove) }
                else if button("Delete Source").exists { try activate(button("Delete Source")) }
                let confirm = button("Remove")
                if confirm.waitForExistence(timeout: 2) { try activate(confirm) }
                else if button("Delete").waitForExistence(timeout: 2) { try activate(button("Delete")) }
                if name == "Home Server" { serverAdded = false } else { liveAdded = false }
            }
        }
    }

    private func authenticate(server: String, user: String, password: String) throws -> String {
        var request = URLRequest(url: URL(string: server + "/Users/AuthenticateByName")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("MediaBrowser Client=\"OpenStream UITests\", Device=\"Simulator\", DeviceId=\"screenshots\", Version=\"1.0\"", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["Username": user, "Pw": password])
        let data = try send(request)
        return try XCTUnwrap((JSONSerialization.jsonObject(with: data) as? [String: Any])?["AccessToken"] as? String)
    }

    @discardableResult private func send(_ request: URLRequest) throws -> Data {
        // XCTest's expectation keeps this synchronous UI test on its actor while
        // URLSession performs the request. Credentials never enter attachments.
        let done = expectation(description: "Demo server answered")
        let result = ResponseBox()
        URLSession.shared.dataTask(with: request) { data, response, error in
            result.set(data: data, status: (response as? HTTPURLResponse)?.statusCode, error: error)
            done.fulfill()
        }.resume()
        wait(for: [done], timeout: 30)
        return try result.value()
    }
    private enum NavigationFailure: Error { case unreachable }
}

private final class ResponseBox: @unchecked Sendable {
    private let lock = NSLock()
    private var data: Data?
    private var status: Int?
    private var error: Error?
    func set(data: Data?, status: Int?, error: Error?) {
        lock.lock(); defer { lock.unlock() }
        self.data = data; self.status = status; self.error = error
    }
    func value() throws -> Data {
        lock.lock(); defer { lock.unlock() }
        if let error { throw error }
        guard status == 200 || status == 204, let data else { throw URLError(.badServerResponse) }
        return data
    }
}

#if !os(tvOS)
private extension XCUIElement {
    func tapIfPresent() { if exists { tap() } }
}
#endif
