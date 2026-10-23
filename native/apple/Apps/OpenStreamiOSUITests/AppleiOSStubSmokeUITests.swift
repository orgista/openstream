import XCTest

/// Launch → Discover row → title page → back, with every control-plane
/// request answered from `Apps/TestPlans/Stubs` (`-OpenStreamStubNetwork`):
/// isolated sources and the same screen every run. The trailer check uses
/// YouTube's live official player.
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

    func testDuoLayoutReferenceScreens() throws {
        let isPad = UIDevice.current.userInterfaceIdiom == .pad
        let orientations: [UIDeviceOrientation] = isPad ? [.portrait, .landscapeLeft] : [.portrait]
        defer { XCUIDevice.shared.orientation = .portrait }
        for orientation in orientations {
            XCUIDevice.shared.orientation = orientation
            let prefix = "duo-\(isPad ? "ipad" : "iphone")-\(orientation == .portrait ? "portrait" : "landscape")"
            func capture(_ screen: String) {
                let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
                shot.name = prefix + "-" + screen
                shot.lifetime = .keepAlways
                add(shot)
                let hierarchy = XCTAttachment(string: app.debugDescription)
                hierarchy.name = prefix + "-" + screen + "-elements"
                hierarchy.lifetime = .keepAlways
                add(hierarchy)
            }
            func open(_ screen: String) {
                app.terminate()
                app.launchArguments = Self.stubbedLaunchArguments + ["-OpenStreamVisionScreen", screen]
                configureFixtureLaunch(app)
                app.launch()
                XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30))
            }
            open("discover")
            let details = app.buttons["home.featured.details"].firstMatch
            XCTAssertTrue(details.waitForExistence(timeout: 60))
            XCTAssertTrue(app.buttons["Search"].firstMatch.isHittable)
            capture("discover")
            details.tap()
            let play = app.buttons["detail.play"].firstMatch
            XCTAssertTrue(play.waitForExistence(timeout: 30))
            let back = app.buttons["detail.back"].firstMatch
            XCTAssertTrue(back.waitForExistence(timeout: 10))
            XCTAssertEqual(back.label, "Back")
            if min(app.frame.width, app.frame.height) < 600 {
                XCTAssertEqual(back.frame.minX, 16, accuracy: 1)
                XCTAssertGreaterThanOrEqual(back.frame.width, 44)
                XCTAssertGreaterThanOrEqual(back.frame.height, 44)
            }
            capture("title")
            open("live")
            XCTAssertTrue(app.descendants(matching: .any)["live.stage.player"].firstMatch.waitForExistence(timeout: 60))
            XCTAssertTrue(app.buttons["live.guide"].firstMatch.exists)
            capture("live")
            open("settings")
            XCTAssertTrue(app.buttons["Sources"].firstMatch.waitForExistence(timeout: 30))
            capture("settings")
        }
    }

    func testLargeWindowOnPhoneUsesThePadPresentation() throws {
        guard UIDevice.current.userInterfaceIdiom == .phone else {
            throw XCTSkip("Phone-hosted large window proof")
        }
        app.launchArguments = Self.stubbedLaunchArguments + ["-OpenStreamDebugLayoutSize", "951,669",
                                                            "-OpenStreamVisionScreen", "discover"]
        configureFixtureLaunch(app)
        app.launch()
        let captureButton = app.buttons["debug.layout.capture"].firstMatch
        XCTAssertTrue(captureButton.waitForExistence(timeout: 30))
        // Owner rule "no unused real estate": the unfolded canvas is used edge to edge.
        func assertSpansCanvas(_ element: XCUIElement, _ canvas: CGRect, _ what: String) {
            XCTAssertEqual(element.frame.minX, canvas.minX, accuracy: 2, what + " starts at the window edge")
            XCTAssertEqual(element.frame.width, canvas.width, accuracy: 2, what + " spans the window")
        }
        var captureIndex = 0
        func capture(_ name: String) {
            captureButton.tap()
            let value = captureButton.value as? String ?? ""
            XCTAssertTrue(value.contains("duo-layout-\(captureIndex).png"), value)
            let record = XCTAttachment(string: value)
            record.name = name + "-canvas"
            record.lifetime = .keepAlways
            add(record)
            let preview = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            preview.name = name + "-host"
            preview.lifetime = .keepAlways
            add(preview)
            let hierarchy = XCTAttachment(string: app.debugDescription)
            hierarchy.name = name + "-elements"
            hierarchy.lifetime = .keepAlways
            add(hierarchy)
            captureIndex += 1
        }
        for shape in ["wide", "portrait"] {
            if shape == "portrait" {
                app.buttons["debug.layout.rotate"].firstMatch.tap()
            }
            let size = shape == "wide" ? "951x669" : "669x951"
            XCTAssertTrue((captureButton.value as? String ?? "").contains(size + " phone regular"))
            tapTab("Discover")
            let details = app.buttons["home.featured.details"].firstMatch
            XCTAssertTrue(details.waitForExistence(timeout: 60))
            // A phone keeps its landing chrome at any size (owner 2026-10-20): no bar, round Search over the art.
            XCTAssertFalse(app.navigationBars["Discover"].exists)
            XCTAssertTrue(app.buttons["discover.compact-title.search"].firstMatch.isHittable)
            let play = app.buttons["home.featured.play"].firstMatch
            XCTAssertTrue(play.waitForExistence(timeout: 10))
            let canvas = app.windows.containing(.button, identifier: "home.featured.play").firstMatch
            XCTAssertTrue(canvas.exists)
            let canvasFrame = canvas.frame
            let scale = min(canvas.frame.width / (shape == "wide" ? 951 : 669),
                            canvas.frame.height / (shape == "wide" ? 669 : 951))
            XCTAssertEqual(play.frame.minX / scale, 24, accuracy: 2)
            XCTAssertEqual(play.frame.width / scale, 180, accuracy: 2)
            let heroAtEdges = expectation(for: NSPredicate { _, _ in
                self.heroArtReachesBothEdges(of: canvasFrame, rows: [120, 160, 200, 240, 280].map { $0 * scale })
            }, evaluatedWith: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [heroAtEdges], timeout: 15), .completed,
                           "The Discover hero's art reaches both edges")
            capture("duo-large-\(shape)-discover")
            details.tap()
            XCTAssertTrue(app.buttons["detail.play"].firstMatch.waitForExistence(timeout: 30))
            capture("duo-large-\(shape)-title")
            app.buttons["detail.back"].firstMatch.tap()
            XCTAssertTrue(details.waitForExistence(timeout: 10), "Back must return to Discover")

            tapTab("Library")
            XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "library.title."))
                .firstMatch.waitForExistence(timeout: 60))
            XCTAssertFalse(app.navigationBars["Library"].exists)
            XCTAssertTrue(app.buttons["library.compact-title.search"].firstMatch.isHittable)
            capture("duo-large-\(shape)-library")
            tapTab("Live")
            let stage = app.descendants(matching: .any)["live.stage.player"].firstMatch
            XCTAssertTrue(stage.waitForExistence(timeout: 60))
            let guide = app.buttons["live.guide"].firstMatch
            XCTAssertTrue(guide.exists)
            let schedule = app.descendants(matching: .any)["live.stage.schedule"].firstMatch
            let list = app.descendants(matching: .any)["live.list"].firstMatch
            XCTAssertTrue(list.exists)
            if shape == "wide" {
                XCTAssertGreaterThan(guide.frame.midX, stage.frame.maxX)
                XCTAssertTrue(schedule.waitForExistence(timeout: 10), "The stage's column must continue with the schedule")
                XCTAssertGreaterThanOrEqual(schedule.frame.minY, stage.frame.maxY - 1)
                XCTAssertLessThan(schedule.frame.maxX, guide.frame.minX)
                // Stage and channel list side by side share the whole width.
                XCTAssertEqual(stage.frame.minX, canvasFrame.minX, accuracy: 2, "The Live stage starts at the window edge")
                XCTAssertGreaterThanOrEqual(list.frame.minX, stage.frame.maxX - 2)
                XCTAssertGreaterThanOrEqual(list.frame.maxX, tabColumnEdge(canvasFrame) - 24 * scale,
                                            "The channel list reaches the tab bar")
            } else {
                XCTAssertGreaterThan(guide.frame.minY, stage.frame.maxY)
                XCTAssertFalse(schedule.exists)
                assertSpansCanvas(stage, canvasFrame, "The Live stage")
                assertSpansCanvas(list, canvasFrame, "The channel list")
            }
            let playing = expectation(for: NSPredicate(format: "value == %@", "Playing"), evaluatedWith: stage)
            XCTAssertEqual(XCTWaiter.wait(for: [playing], timeout: 30), .completed)
            capture("duo-large-\(shape)-live")
            tapTab("Settings")
            let sources = app.buttons["Sources"].firstMatch
            XCTAssertTrue(sources.waitForExistence(timeout: 30))
            XCTAssertTrue(sources.isHittable)
            let mediaServer = app.buttons["Media Server"].firstMatch
            XCTAssertTrue(mediaServer.waitForExistence(timeout: 15))
            let beside = expectation(for: NSPredicate { _, _ in
                mediaServer.exists && sources.exists && mediaServer.frame.minX > sources.frame.maxX
            }, evaluatedWith: nil)
            let splitResult = XCTWaiter.wait(for: [beside], timeout: 15)
            capture("duo-large-\(shape)-settings")
            XCTAssertEqual(splitResult, .completed, "Settings must keep both panes beside each other")
            XCTAssertGreaterThanOrEqual(app.navigationBars.count, 2)
        }
        tapTab("Discover")
        app.buttons["home.featured.details"].firstMatch.tap()
        XCTAssertTrue(app.buttons["detail.play"].firstMatch.waitForExistence(timeout: 30))
        app.buttons["debug.layout.fold"].firstMatch.tap()
        XCTAssertTrue((captureButton.value as? String ?? "").contains("466x678 phone compact"))
        XCTAssertTrue(app.buttons["detail.play"].firstMatch.waitForExistence(timeout: 15))
        capture("duo-folded-title")
        app.buttons["debug.layout.fold"].firstMatch.tap()
        XCTAssertTrue((captureButton.value as? String ?? "").contains("669x951 phone regular"))
        XCTAssertTrue(app.buttons["detail.play"].firstMatch.waitForExistence(timeout: 15))
        capture("duo-unfolded-title")
    }

    /// Every iPad window keeps the iPad's layout: a 1/3 split (compact width,
    /// under 600 pt) gets the bar over the landing hero, the title page's
    /// toolbar Back, the iPad's Live page and a pushed Settings stack.
    func testCompactIPadWindowKeepsThePadLayout() throws {
        guard UIDevice.current.userInterfaceIdiom == .pad else {
            throw XCTSkip("iPad split-window proof")
        }
        app.launchArguments = Self.stubbedLaunchArguments + ["-OpenStreamDebugLayoutSize", "375,1032,compact",
                                                            "-OpenStreamVisionScreen", "discover"]
        configureFixtureLaunch(app)
        app.launch()
        let captureButton = app.buttons["debug.layout.capture"].firstMatch
        XCTAssertTrue(captureButton.waitForExistence(timeout: 30))
        XCTAssertTrue((captureButton.value as? String ?? "").contains("375x1032 pad compact"))
        func capture(_ name: String) {
            captureButton.tap()
            let record = XCTAttachment(string: captureButton.value as? String ?? "")
            record.name = name + "-canvas"
            record.lifetime = .keepAlways
            add(record)
            let hierarchy = XCTAttachment(string: app.debugDescription)
            hierarchy.name = name + "-elements"
            hierarchy.lifetime = .keepAlways
            add(hierarchy)
        }
        let details = app.buttons["home.featured.details"].firstMatch
        XCTAssertTrue(details.waitForExistence(timeout: 60))
        XCTAssertTrue(app.navigationBars["Discover"].exists, "An iPad split keeps the bar over the hero")
        XCTAssertFalse(app.buttons["discover.compact-title.search"].exists)
        capture("ipad-split-discover")
        details.tap()
        XCTAssertTrue(app.buttons["detail.play"].firstMatch.waitForExistence(timeout: 30))
        let back = app.navigationBars.buttons["detail.back"].firstMatch
        XCTAssertTrue(back.waitForExistence(timeout: 10), "The iPad title page keeps Back in its toolbar")
        capture("ipad-split-title")
        back.tap()
        XCTAssertTrue(details.waitForExistence(timeout: 10))

        tapTab("Library")
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "library.title."))
            .firstMatch.waitForExistence(timeout: 60))
        XCTAssertTrue(app.navigationBars["Library"].exists)
        capture("ipad-split-library")
        tapTab("Live")
        let stage = app.descendants(matching: .any)["live.stage.player"].firstMatch
        XCTAssertTrue(stage.waitForExistence(timeout: 60))
        XCTAssertTrue(app.buttons["live.guide"].firstMatch.exists)
        XCTAssertGreaterThan(app.buttons["live.guide"].firstMatch.frame.minY, stage.frame.maxY - 1)
        capture("ipad-split-live")
        tapTab("Settings")
        XCTAssertTrue(app.buttons["Sources"].firstMatch.waitForExistence(timeout: 30))
        XCTAssertFalse(app.buttons["Media Server"].exists, "A compact iPad window pushes Settings pages")
        capture("ipad-split-settings")
    }

    /// A 1/2 split on a 13-inch iPad on its side stacks Live like full screen.
    func testHalfIPadWindowStacksLive() throws {
        guard UIDevice.current.userInterfaceIdiom == .pad else {
            throw XCTSkip("iPad split-window proof")
        }
        app.launchArguments = Self.stubbedLaunchArguments + ["-OpenStreamDebugLayoutSize", "683,1032",
                                                            "-OpenStreamVisionScreen", "live"]
        configureFixtureLaunch(app)
        app.launch()
        let captureButton = app.buttons["debug.layout.capture"].firstMatch
        XCTAssertTrue(captureButton.waitForExistence(timeout: 30))
        XCTAssertTrue((captureButton.value as? String ?? "").contains("683x1032 pad regular"))
        let stage = app.descendants(matching: .any)["live.stage.player"].firstMatch
        XCTAssertTrue(stage.waitForExistence(timeout: 60))
        let bar = app.descendants(matching: .any)["live.categories"].firstMatch
        let list = app.descendants(matching: .any)["live.list"].firstMatch
        XCTAssertTrue(bar.exists && list.exists)
        XCTAssertEqual(stage.frame.width, bar.frame.width, accuracy: 1, "The stage spans the window")
        XCTAssertEqual(bar.frame.minY, stage.frame.maxY, accuracy: 1)
        XCTAssertEqual(list.frame.minX, bar.frame.minX, accuracy: 1)
        XCTAssertEqual(list.frame.width, bar.frame.width, accuracy: 1)
        captureButton.tap()
        let record = XCTAttachment(string: (captureButton.value as? String ?? "")
            + "\nstage: \(stage.frame)\nbar: \(bar.frame)\nlist: \(list.frame)")
        record.name = "ipad-half-live-canvas"
        record.lifetime = .keepAlways
        add(record)
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "ipad-half-live"
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// The hero's art, not the page's black background, reaches both side edges of `window`:
    /// at each edge at least one sample, `rows` points below the window's top, is not the page's
    /// pure black. The screenshot is lossless, so even near-black art (10, 10, 10 in a stub) counts;
    /// several rows keep one black spot in the art from reading as a gap.
    private func heroArtReachesBothEdges(of window: CGRect, rows: [CGFloat]) -> Bool {
        guard let image = XCUIScreen.main.screenshot().image.cgImage, app.frame.width > 0 else { return false }
        let ratio = CGFloat(image.width) / app.frame.width
        let width = image.width, height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return false }
        func differsFromPage(x: CGFloat, y: CGFloat) -> Bool {
            let column = min(max(Int(x * ratio), 0), width - 1), row = min(max(Int(y * ratio), 0), height - 1)
            let offset = (row * width + column) * 4
            return pixels[offset..<offset + 3].contains { $0 > 3 }
        }
        return [window.minX + 2, window.maxX - 3].allSatisfy { x in
            rows.contains { differsFromPage(x: x, y: window.minY + $0) }
        }
    }

    /// Where a side tab bar (the unfolded Duo's) begins, else the window's edge.
    private func tabColumnEdge(_ window: CGRect) -> CGFloat {
        let rail = app.toolbars.buttons["Discover"].firstMatch
        return rail.exists && rail.frame.minX > window.midX ? rail.frame.minX : window.maxX
    }

    private func tapTab(_ title: String) {
        let tabBarButton = app.tabBars.buttons[title].firstMatch
        let railButton = app.toolbars.buttons[title].firstMatch
        let available = expectation(for: NSPredicate { _, _ in
            (tabBarButton.exists && tabBarButton.isHittable) || (railButton.exists && railButton.isHittable)
        }, evaluatedWith: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [available], timeout: 15), .completed)
        let button = tabBarButton.exists && tabBarButton.isHittable ? tabBarButton : railButton
        button.tap()
    }

    func testDuoNativeScreensAndTransitions() async throws {
        guard ProcessInfo.processInfo.environment["OPENSTREAM_DUO_DEFAULT_POSTURE"] != "1" else {
            throw XCTSkip("Native fold control is unavailable; default window has its own capture test")
        }
        try await captureNativeDuoScreens(exercisesFolding: true)
    }

    func testDuoNativeDefaultPostureScreens() async throws {
        guard ProcessInfo.processInfo.environment["OPENSTREAM_DUO_DEFAULT_POSTURE"] == "1" else {
            throw XCTSkip("Opt-in native Duo default-window capture")
        }
        try await captureNativeDuoScreens(exercisesFolding: false)
    }

    private func captureNativeDuoScreens(exercisesFolding: Bool) async throws {
        guard let address = ProcessInfo.processInfo.environment["OPENSTREAM_DUO_CONTROL_URL"] else {
            throw XCTSkip("Native Duo capture requires its loopback control server")
        }
        let controlURL = try XCTUnwrap(URL(string: address))
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        executionTimeAllowance = 600

        func wait(_ predicate: NSPredicate, on object: Any? = nil, timeout: TimeInterval = 30) async {
            let pending = XCTNSPredicateExpectation(predicate: predicate, object: object)
            let result = await XCTWaiter.fulfillment(of: [pending], timeout: timeout)
            XCTAssertEqual(result, .completed, predicate.predicateFormat)
        }
        func request(_ command: String, tag: String? = nil) async throws {
            var components = try XCTUnwrap(URLComponents(url: controlURL.appendingPathComponent(command),
                                                        resolvingAgainstBaseURL: false))
            if let tag { components.queryItems = [URLQueryItem(name: "tag", value: tag)] }
            let url = try XCTUnwrap(components.url)
            let (_, response) = try await session.data(for: URLRequest(url: url, timeoutInterval: 60))
            XCTAssertEqual(try XCTUnwrap(response as? HTTPURLResponse).statusCode, 200)
        }
        func setFolded(_ folded: Bool) async throws {
            try await request(folded ? "fold" : "unfold")
            await wait(NSPredicate { _, _ in
                let frame = self.app.frame
                let shortSide = min(frame.width, frame.height)
                return !frame.isEmpty && (folded ? shortSide < 600 : shortSide >= 600)
            })
        }
        func capture(_ tag: String) async throws {
            XCTAssertEqual(app.state, .runningForeground)
            XCTAssertFalse(app.buttons["debug.layout.capture"].exists)
            let image = XCTAttachment(screenshot: app.screenshot())
            image.name = tag; image.lifetime = .keepAlways; add(image)
            let tree = XCTAttachment(string: "app.frame=\(app.frame)\n" + app.debugDescription)
            tree.name = tag + "-elements"; tree.lifetime = .keepAlways; add(tree)
            try await request("capture", tag: tag)
        }
        func tab(_ title: String) async {
            let tabBarButton = app.tabBars.buttons[title].firstMatch
            let railButton = app.toolbars.buttons[title].firstMatch
            await wait(NSPredicate { _, _ in
                (tabBarButton.exists && tabBarButton.isHittable) || (railButton.exists && railButton.isHittable)
            })
            let button = tabBarButton.exists && tabBarButton.isHittable ? tabBarButton : railButton
            button.tap()
            await wait(NSPredicate(format: "selected == true"), on: button)
        }
        func seconds() -> Double? {
            let slider = app.sliders.firstMatch
            guard slider.exists, let text = slider.value as? String,
                  text.range(of: #"^\d+:\d{2}(:\d{2})?$"#, options: .regularExpression) != nil else { return nil }
            return text.split(separator: ":").reduce(0) { $0 * 60 + (Double($1) ?? 0) }
        }
        func playing(after position: Double? = nil) async {
            await wait(NSPredicate { _, _ in
                let transport = self.app.buttons["player.play-pause"].firstMatch
                guard transport.exists, transport.label == "Pause",
                      let current = seconds() else { return false }
                return position.map { current > $0 } ?? true
            }, timeout: 60)
        }

        app.launchArguments = Self.stubbedLaunchArguments + ["-OpenStreamVisionScreen", "discover",
                                                             "-OpenStreamHoldPlayerChrome", "YES"]
        configureFixtureLaunch(app)
        app.launch()
        await wait(NSPredicate { _, _ in self.app.state == .runningForeground })
        let details = app.buttons["home.featured.details"].firstMatch
        let detail = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "detail.screen.")).firstMatch
        let play = app.buttons["detail.play"].firstMatch
        let back = app.buttons["detail.back"].firstMatch
        let stage = app.descendants(matching: .any)["live.stage.player"].firstMatch

        // Owner rule "no unused real estate": the art and the stage run edge to edge in every posture.
        func assertSpansWindow(_ element: XCUIElement, _ what: String) {
            XCTAssertEqual(element.frame.minX, app.frame.minX, accuracy: 1, what + " starts at the window edge")
            XCTAssertEqual(element.frame.width, app.frame.width, accuracy: 1, what + " spans the window")
        }
        defer { XCUIDevice.shared.orientation = .portrait }
        let small = min(app.frame.width, app.frame.height) < 600
        let passes: [(folded: Bool, landscape: Bool)] = exercisesFolding
            ? [(true, false), (true, true), (false, false), (false, true)]
            : [(small, false), (small, true)]
        for (index, pass) in passes.enumerated() {
            let folded = pass.folded
            let posture = exercisesFolding ? (folded ? "folded" : "unfolded")
                : (folded ? "default-small-window" : "default-large-window")
            let shape = posture + (pass.landscape ? "-landscape" : "")
            let exercisesTransitions = exercisesFolding && index == 0
            if exercisesFolding { try await setFolded(folded) }
            XCUIDevice.shared.orientation = pass.landscape ? .landscapeLeft : .portrait
            // A large window follows the device; a small phone window stays upright outside the player.
            await wait(NSPredicate { _, _ in
                (self.app.frame.width > self.app.frame.height) == (pass.landscape && !folded)
            })
            await tab("Discover")
            await wait(NSPredicate(format: "exists == true AND hittable == true"), on: details, timeout: 60)
            // Below the folded screen's status bar, which sits in the column beside the content.
            // The art loads after the hero's buttons.
            await wait(NSPredicate { _, _ in
                self.heroArtReachesBothEdges(of: self.app.frame, rows: [180, 220, 260, 300, 340])
            }, timeout: 15)
            try await capture("duo-native-\(shape)-discover")
            details.tap()
            await wait(NSPredicate(format: "exists == true"), on: play)
            await wait(NSPredicate(format: "exists == true"), on: detail)
            let titleID = detail.identifier
            XCTAssertFalse(titleID.isEmpty)
            try await capture("duo-native-\(shape)-title")
            if exercisesTransitions {
                for next in [false, true] {
                    try await setFolded(next)
                    await wait(NSPredicate(format: "exists == true AND hittable == true"), on: back)
                    XCTAssertEqual(detail.identifier, titleID)
                    XCTAssertTrue(play.exists)
                    try await capture("duo-native-title-transition-\(next ? "folded" : "unfolded")")
                }
            }
            back.tap()
            await wait(NSPredicate(format: "exists == false"), on: back)
            await wait(NSPredicate(format: "hittable == true"), on: details)

            await tab("Library")
            let tile = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "library.title.")).firstMatch
            await wait(NSPredicate(format: "exists == true"), on: tile, timeout: 60)
            try await capture("duo-native-\(shape)-library")
            await tab("Live")
            await wait(NSPredicate(format: "exists == true AND value == %@", "Playing"), on: stage, timeout: 60)
            let guide = app.buttons["live.guide"].firstMatch
            XCTAssertTrue(guide.exists)
            if folded {
                assertSpansWindow(stage, "The Live stage")
                let categories = app.descendants(matching: .any)["live.categories"].firstMatch
                XCTAssertGreaterThanOrEqual(categories.frame.minY, stage.frame.maxY - 1, "The stage stays above the category row")
            }
            if !folded {
                let list = app.descendants(matching: .any)["live.list"].firstMatch
                XCTAssertTrue(list.exists)
                if app.frame.width > app.frame.height {
                    XCTAssertGreaterThan(guide.frame.midX, stage.frame.maxX)
                    // Stage and channel list side by side share the whole width.
                    XCTAssertEqual(stage.frame.minX, app.frame.minX, accuracy: 1, "The Live stage starts at the window edge")
                    XCTAssertGreaterThanOrEqual(list.frame.minX, stage.frame.maxX - 1)
                    XCTAssertGreaterThanOrEqual(list.frame.maxX, tabColumnEdge(app.frame) - 24,
                                                "The channel list reaches the tab bar")
                } else {
                    XCTAssertGreaterThan(guide.frame.minY, stage.frame.maxY)
                    assertSpansWindow(stage, "The Live stage")
                    assertSpansWindow(list, "The channel list")
                }
            }
            try await capture("duo-native-\(shape)-live")
            await tab("Settings")
            let sources = app.buttons["Sources"].firstMatch
            await wait(NSPredicate(format: "exists == true AND hittable == true"), on: sources)
            if !folded {
                let mediaServer = app.buttons["Media Server"].firstMatch
                await wait(NSPredicate(format: "exists == true"), on: mediaServer)
                XCTAssertGreaterThan(mediaServer.frame.minX, sources.frame.maxX)
                XCTAssertGreaterThanOrEqual(app.navigationBars.count, 2)
            }
            try await capture("duo-native-\(shape)-settings")

            await tab("Discover")
            await wait(NSPredicate(format: "exists == true AND hittable == true"), on: details)
            details.tap()
            await wait(NSPredicate(format: "exists == true AND hittable == true"), on: play)
            let playingTitleID = detail.identifier
            play.tap()
            let ready = app.descendants(matching: .any)["player.playback.ready"].firstMatch
            await wait(NSPredicate(format: "exists == true"), on: ready, timeout: 60)
            await playing()
            let start = try XCTUnwrap(seconds())
            await playing(after: start)
            try await capture("duo-native-\(shape)-player")
            if exercisesTransitions {
                for next in [false, true] {
                    let previous = try XCTUnwrap(seconds())
                    try await setFolded(next)
                    await wait(NSPredicate(format: "exists == true"), on: ready)
                    await playing()
                    XCTAssertGreaterThanOrEqual(try XCTUnwrap(seconds()), previous - 1)
                    await playing(after: previous)
                    try await capture("duo-native-player-transition-\(next ? "folded" : "unfolded")")
                }
            }
            let close = app.buttons["player.close"].firstMatch
            await wait(NSPredicate(format: "exists == true AND hittable == true"), on: close)
            close.tap()
            await wait(NSPredicate(format: "exists == true AND hittable == true"), on: back)
            XCTAssertEqual(detail.identifier, playingTitleID)
            back.tap()
            await wait(NSPredicate(format: "exists == false"), on: back)
        }
        if exercisesFolding { try await setFolded(true) }
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

    /// Requires network access to YouTube's official player.
    func testMediaServerHeroTrailerReachesPlaying() {
        app.launchArguments += ["-OpenStreamDebugTrailerKeys", "M7lc1UVf-VE",
                                "-openstream.settings.trailer.autoplay.v1", "YES"]
        configureFixtureLaunch(app)
        app.launch()
        let details = app.buttons["home.featured.details"].firstMatch
        XCTAssertTrue(details.waitForExistence(timeout: 60), "A media-server-only setup has no Discover hero")
        details.tap()
        XCTAssertTrue(app.buttons["detail.play"].firstMatch.waitForExistence(timeout: 30))
        let preview = app.buttons["detail.trailer.toggle"].firstMatch
        let playing = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true AND value == 'Playing'"), object: preview)
        XCTAssertEqual(XCTWaiter.wait(for: [playing], timeout: 60), .completed,
                       "The official YouTube player never revealed playing video")
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "official-trailer-playing"
        shot.lifetime = .keepAlways
        add(shot)
    }

    func testServerHostedTrailerReachesPlaying() {
        app.launchArguments += ["-openstream.settings.trailer.autoplay.v1", "NO"]
        configureFixtureLaunch(app)
        app.launch()
        let details = app.buttons["home.featured.details"].firstMatch
        XCTAssertTrue(details.waitForExistence(timeout: 60))
        details.tap()
        let trailer = app.buttons["detail.serverTrailer"].firstMatch
        XCTAssertTrue(trailer.waitForExistence(timeout: 30))
        trailer.tap()
        let playing = app.descendants(matching: .any).matching(identifier: "trailer.player.playing").firstMatch
        XCTAssertTrue(playing.waitForExistence(timeout: 30),
                       "The server-hosted trailer clock never advanced")
        XCTAssertEqual(playing.label, "")
        XCTAssertEqual(playing.frame.size, .zero)
    }

    func testDiscoverRowOpensATitleFromStubsAndComesBack() {
        configureFixtureLaunch(app)
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30))

        // Discover is lazy: the fixture Jellyfin's shelves sit under the hero,
        // so a poster is not in the hierarchy until it has scrolled into view.
        // Stub Movie Five leads the server's Latest row: Six, the newest, is in
        // Continue Watching, and Discover shows a title once.
        let poster = app.descendants(matching: .any).matching(Self.serverShelfItem("jf-movie-5")).firstMatch
        XCTAssertTrue(app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH 'home.' OR identifier BEGINSWITH 'discover.'")).firstMatch
            .waitForExistence(timeout: 60), "Discover never drew")
        // The row is lazy and a page swipe can carry it past the top: scroll
        // until it is on screen, and back down a little when it went by.
        // A frame check, not `isHittable`: a card still outside the window has
        // no activation point, and asking for one fails the test outright.
        let visible = app.frame.insetBy(dx: 0, dy: 80)
        func onScreen() -> Bool {
            guard let frame = (try? poster.snapshot())?.frame else { return false }
            return visible.contains(CGPoint(x: frame.midX, y: frame.midY))
        }
        for _ in 0 ..< 10 where !onScreen() {
            guard let frame = (try? poster.snapshot())?.frame else { app.swipeUp(); _ = poster.waitForExistence(timeout: 3); continue }
            if frame.midY < app.frame.midY { app.swipeDown() } else { app.swipeUp() }
            Thread.sleep(forTimeInterval: 0.6)
        }
        XCTAssertTrue(onScreen(), "the fixture server's row never drew")
        poster.tap()

        let play = app.buttons["detail.play"].firstMatch
        XCTAssertTrue(play.waitForExistence(timeout: 30), "the title page never opened")
        XCTAssertTrue(app.staticTexts["Stub Movie Five"].firstMatch.waitForExistence(timeout: 10))

        if min(app.frame.width, app.frame.height) < 600 {
            // Owner, 2026-10-19: "in the content page there is a search icon we don't need".
            XCTAssertFalse(app.buttons["Search"].firstMatch.isHittable)
            XCTAssertFalse(app.navigationBars.firstMatch.exists)
            let compactTitle = app.staticTexts["detail.compact-title"].firstMatch
            XCTAssertFalse(compactTitle.exists)
            // The compact title appears once the hero block has scrolled away: Play
            // is gone from the hierarchy or its frame is above the status bar. A
            // page that cannot scroll at all (Play's frame unchanged after the first
            // swipe) keeps the hero, and no compact title is the right outcome.
            // Snapshots, not live reads: iOS 27 has no status-bar element and Play
            // can leave the hierarchy mid-loop, and a live read of either raises.
            let statusBarBottom = (try? app.statusBars.firstMatch.snapshot())?.frame.maxY ?? 0
            let startFrame = (try? play.snapshot())?.frame ?? .zero
            for swipe in 0..<6 {
                app.swipeUp()
                let playFrame = (try? play.snapshot())?.frame
                if swipe == 0, let playFrame, playFrame == startFrame {
                    print("note: the stub title page cannot scroll; compact title not asserted")
                    break
                }
                if playFrame == nil || playFrame!.maxY < statusBarBottom {
                    XCTAssertTrue(compactTitle.waitForExistence(timeout: 5),
                                  "the hero scrolled away but the compact title never appeared")
                    break
                }
            }
        }

        let back = app.buttons["detail.back"].firstMatch
        if back.waitForExistence(timeout: 5) {
            if min(app.frame.width, app.frame.height) < 600 {
                // Row 30: a 44 pt control on every iOS, glass included (iOS 27 measured 26.67 pt before).
                XCTAssertGreaterThanOrEqual(back.frame.width, 44, "Back is narrower than 44 pt")
                XCTAssertGreaterThanOrEqual(back.frame.height, 44, "Back is shorter than 44 pt")
            }
            back.tap()
        } else { app.navigationBars.buttons.firstMatch.tap() }
        XCTAssertFalse(play.waitForExistence(timeout: 5), "the title page did not close")
        XCTAssertTrue(poster.waitForExistence(timeout: 30), "Discover did not come back")
    }

    /// Library → Unmatched → Match picks a title, which leaves the shelf with
    /// its art; Use Automatic Match on the title page puts it back.
    func testUnmatchedShelfMatchesAndReverts() throws {
        // The reset clears metadata keys and lookup caches left on the
        // simulator, so the fixture's misses cache as no-matches. Match
        // searches TMDB, answered from the stub files.
        app.launchArguments = ["-OpenStreamLibraryTitlesFixture"] + Self.stubbedLaunchArguments
            + (try tmdbFixtureKeyLaunchArguments())
        app.launchEnvironment["OPENSTREAM_LIBRARY_FIXTURE_PATH"] = Self.stubDirectory + "/library-unmatched"
        app.launch()
        func shot(_ name: String) {
            let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            shot.name = name
            shot.lifetime = .keepAlways
            add(shot)
        }
        func reveal(_ element: XCUIElement) {
            for _ in 0 ..< 6 where !(element.exists && element.isHittable) {
                app.swipeUp()
                _ = element.waitForExistence(timeout: 2)
            }
        }

        // The Library is lazy: Unmatched sits under the other shelves and only
        // enters the hierarchy once it scrolls into view.
        let tile = app.buttons["library.unmatched.Quiet Harbor Home Video"].firstMatch
        XCTAssertTrue(app.buttons["library.title.Quiet Harbor Home Video"].firstMatch.waitForExistence(timeout: 60),
                      "the fixture library never drew")
        reveal(tile)
        XCTAssertTrue(tile.exists && tile.isHittable, "the Unmatched shelf never drew")
        XCTAssertTrue(app.buttons["library.unmatched.Lantern Street Rehearsal"].firstMatch.exists)
        shot("unmatched-shelf")
        tile.tap()

        let query = app.textFields["detail.fixMatch.query"].firstMatch
        XCTAssertTrue(query.waitForExistence(timeout: 10), "Match did not open")
        XCTAssertTrue(app.navigationBars["Match"].exists)
        query.tap()
        query.typeText("Stub Movie Two")
        app.buttons["detail.fixMatch.search"].firstMatch.tap()
        let result = app.buttons["detail.fixMatch.result.tt0000002"].firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 20), "no search result")
        shot("unmatched-match-results")
        result.tap()
        XCTAssertTrue(tile.waitForNonExistence(timeout: 10), "the matched title stayed on the Unmatched shelf")
        XCTAssertTrue(app.buttons["library.unmatched.Lantern Street Rehearsal"].firstMatch.exists)
        shot("unmatched-after-match")

        let matched = app.buttons["library.title.Quiet Harbor Home Video"].firstMatch
        app.swipeDown()
        reveal(matched)
        matched.tap()
        let play = app.buttons["detail.play"].firstMatch
        XCTAssertTrue(play.waitForExistence(timeout: 30), "the title page never opened")
        XCTAssertTrue(app.staticTexts["Stub Movie Two"].firstMatch.waitForExistence(timeout: 10))
        play.press(forDuration: 1.2)
        XCTAssertTrue(app.buttons["detail.fixMatch"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["detail.fixMatch"].firstMatch.label, "Change Metadata")
        let automatic = app.buttons["detail.automaticMatch"].firstMatch
        XCTAssertTrue(automatic.exists, "a manual match offers no way back")
        shot("unmatched-title-menu")
        automatic.tap()
        XCTAssertTrue(app.staticTexts["Quiet Harbor Home Video"].firstMatch.waitForExistence(timeout: 10),
                      "the automatic title did not replace the manual match")
        shot("unmatched-after-automatic-match")
        let back = app.buttons["detail.back"].firstMatch
        let backExists = back.waitForExistence(timeout: 5)
        if !backExists {
            let hierarchy = XCTAttachment(string: app.debugDescription)
            hierarchy.name = "unmatched-after-automatic-match-elements"
            hierarchy.lifetime = .keepAlways
            add(hierarchy)
        }
        XCTAssertTrue(backExists, "automatic matching lost the title page's Back control")
        back.tap()
        XCTAssertTrue(matched.waitForExistence(timeout: 10), "the Library did not come back")
        reveal(tile)
        XCTAssertTrue(tile.exists, "Use Automatic Match did not return the title to Unmatched")
    }
}
