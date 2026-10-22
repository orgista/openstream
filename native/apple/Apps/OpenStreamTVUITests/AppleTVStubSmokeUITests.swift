import Network
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

    func testLoadingIndicatorsStaySingleThroughDiscoverDetailAndPlayback() {
        continueAfterFailure = true
        configureFixtureLaunch(app)
        app.launch()
        sampleLoadingIndicators("discover", for: 6)
        XCTAssertTrue(focus(Self.serverShelfItem("jf-movie-5"), pressing: .down), "Discover poster never took focus")
        remote.press(.select)
        sampleLoadingIndicators("detail", for: 6)
        let play = element("detail.play")
        XCTAssertTrue(play.waitForExistence(timeout: 30))
        XCTAssertTrue(focus("detail.play", pressing: .right))
        remote.press(.select)
        sampleLoadingIndicators("playback", for: 12)
        XCTAssertTrue(element("player.playback.ready").waitForExistence(timeout: 45))
    }

    func testLiveLoadingIndicatorsStaySingleOnTheSoftwareRoute() async throws {
        continueAfterFailure = true
        let base = try XCTUnwrap(ProcessInfo.processInfo.environment["OPENSTREAM_STUB_MEDIA_BASE"])
        var mediaURL = try XCTUnwrap(URL(string: base + "/media/mkv-vp9-opus.mkv"))
        if ProcessInfo.processInfo.environment["OPENSTREAM_PLAYER_DOTS_DEVICE"] == "1" {
            let fixture = try await PlayerDotsLoopbackFixture.download(from: mediaURL)
            addTeardownBlock { await fixture.stop() }
            mediaURL = try await fixture.start()
        }
        app.launchArguments = ["-OpenStreamInlineLiveFixture",
            "-OpenStreamVisionPlaybackURL", mediaURL.absoluteString,
            "-OpenStreamVisionPlaybackIsLive", "YES", "-OpenStreamMuteAudio", "YES"]
        configureFixtureLaunch(app)
        app.launch()
        XCTAssertGreaterThan(sampleLoadingIndicators("live-software", for: 30), 0,
            "The software fixture must exercise a visible loading indicator")
    }

    func testSeriesLoadingIndicatorsStaySingleWhileTheTitlePageLoads() {
        continueAfterFailure = true
        app.launchArguments += ["-OpenStreamVisionScreen", "detail"]
        configureFixtureLaunch(app)
        app.launch()
        sampleLoadingIndicators("series-detail", for: 12)
        XCTAssertTrue(element("detail.episodes").waitForExistence(timeout: 30))
    }

    func testLiveLoadingIndicatorsStaySingleOnTheAVPlayerRoute() throws {
        continueAfterFailure = true
        let base = try XCTUnwrap(ProcessInfo.processInfo.environment["OPENSTREAM_STUB_MEDIA_BASE"])
        app.launchArguments = ["-OpenStreamInlineLiveFixture",
            "-OpenStreamVisionPlaybackURL", base + "/live/cbs.ts",
            "-OpenStreamVisionPlaybackIsLive", "YES", "-OpenStreamMuteAudio", "YES"]
        configureFixtureLaunch(app)
        app.launch()
        sampleLoadingIndicators("live-avplayer", for: 15)
    }

    func testDeviceLoadingIndicatorsStaySingleThroughDiscoverDetailAndPlayback() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["OPENSTREAM_PLAYER_DOTS_DEVICE"] == "1",
            "Requires the DevTV device run")
        continueAfterFailure = true
        app.launchArguments = ["-OpenStreamVisionScreen", "discover", "-OpenStreamMuteAudio", "YES",
            "-OpenStreamTrace", "YES"]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30), "OpenStream did not become foreground")
        sampleLoadingIndicators("device-discover", for: 6)
        XCTAssertTrue(focus(NSPredicate(format: "identifier BEGINSWITH 'home.ms.'"), pressing: .down))
        remote.press(.select)
        sampleLoadingIndicators("device-detail", for: 6)
        XCTAssertTrue(element("detail.play").waitForExistence(timeout: 45))
        if let fixture = ProcessInfo.processInfo.environment["OPENSTREAM_PLAYER_DOTS_MEDIA_URL"] {
            app.terminate()
            app.launchArguments = ["-OpenStreamVisionScreen", "add-files",
                "-OpenStreamVisionPlaybackURL", fixture, "-OpenStreamVisionPlaybackIsLive", "NO",
                "-OpenStreamMuteAudio", "YES", "-OpenStreamTrace", "YES"]
            app.launch()
        } else {
            XCTAssertTrue(focus("detail.play", pressing: .right))
            remote.press(.select)
        }
        sampleLoadingIndicators("device-playback", for: 20)
        XCTAssertTrue(element("player.playback.ready").waitForExistence(timeout: 60))
        remote.press(.menu)
    }

    @discardableResult
    private func sampleLoadingIndicators(_ phase: String, for seconds: TimeInterval) -> Int {
        let start = Date()
        var sample = 0
        var maximum = 0
        var attachedDuplicateHierarchy = false
        repeat {
            // tvOS exposes a circular ProgressView and its UIKit spinner as nested indicators.
            // On screen by frame: `isHittable` fails the test for an indicator with no activation point.
            let screen = app.frame
            let indicators = app.activityIndicators.allElementsBoundByAccessibilityElement.filter {
                guard let frame = (try? $0.snapshot())?.frame, !frame.isEmpty, screen.intersects(frame) else { return false }
                return $0.descendants(matching: .activityIndicator).count == 0
            }
            maximum = max(maximum, indicators.count)
            let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            let elapsed = Int(Date().timeIntervalSince(start) * 1_000)
            shot.name = "player-dots-\(phase)-\(sample)-\(elapsed)ms-\(indicators.count)-indicators"
            shot.lifetime = .keepAlways
            add(shot)
            if indicators.count > 1, !attachedDuplicateHierarchy {
                let hierarchy = app.debugDescription.replacingOccurrences(
                    of: #"[A-Za-z][A-Za-z0-9+.-]*://\S+"#, with: "<URL>", options: .regularExpression)
                let detail = XCTAttachment(string: hierarchy)
                detail.name = "player-dots-\(phase)-duplicate-hierarchy"
                detail.lifetime = .keepAlways
                add(detail)
                attachedDuplicateHierarchy = true
            }
            sample += 1
            let delay = start.addingTimeInterval(Double(sample) * 0.25).timeIntervalSinceNow
            if delay > 0 { Thread.sleep(forTimeInterval: delay) }
        } while Date().timeIntervalSince(start) < seconds
        XCTAssertLessThanOrEqual(maximum, 1, "\(phase) showed multiple loading indicators")
        return maximum
    }

    func testServerHostedTrailerReachesPlaying() {
        app.launchArguments += ["-openstream.settings.trailer.autoplay.v1", "NO"]
        configureFixtureLaunch(app)
        app.launch()
        XCTAssertTrue(focusedElement.waitForExistence(timeout: 60))
        XCTAssertTrue(focus(Self.serverShelfItem("jf-movie-5"), pressing: .down), "The fixture poster never took focus")
        remote.press(.select)
        XCTAssertTrue(element("detail.play").waitForExistence(timeout: 30))
        let trailer = NSPredicate(format: "identifier == 'detail.icon-row' AND label == 'Play Trailer'")
        XCTAssertTrue(app.buttons.matching(trailer).firstMatch.waitForExistence(timeout: 30))
        XCTAssertTrue(focus(trailer, pressing: .right))
        remote.press(.select)
        let playing = element("trailer.player.playing")
        XCTAssertTrue(playing.waitForExistence(timeout: 30), "The server-hosted trailer clock never advanced")
        XCTAssertEqual(playing.label, "")
        XCTAssertEqual(playing.frame.size, .zero)
    }

    func testDiscoverRowOpensATitleFromStubsAndComesBack() {
        configureFixtureLaunch(app)
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30))

        XCTAssertTrue(focusedElement.waitForExistence(timeout: 60), "Discover never took focus")
        // Stub Movie Five leads the fixture server's Latest row: Six, the newest,
        // is in Continue Watching, and Discover shows a title once.
        let posterMatch = Self.serverShelfItem("jf-movie-5")
        let poster = app.descendants(matching: .any).matching(posterMatch).firstMatch

        // Walk focus down from the hero until the poster holds it (the shelf
        // is lazy and only enters the hierarchy as focus reaches it), then open.
        let focusedPoster = app.descendants(matching: .any).matching(NSCompoundPredicate(
            andPredicateWithSubpredicates: [NSPredicate(format: "hasFocus == true"), posterMatch])).firstMatch
        for _ in 0 ..< 10 where !focusedPoster.exists {
            remote.press(.down)
            _ = focusedPoster.waitForExistence(timeout: 2)
        }
        XCTAssertTrue(focusedPoster.exists, "focus never reached the fixture server's poster; sits on '\(focusedElement.identifier)'")
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "discover-stub-movies-tv"
        shot.lifetime = .keepAlways
        add(shot)
        remote.press(.select)

        let play = element("detail.play")
        XCTAssertTrue(play.waitForExistence(timeout: 30), "the title page never opened")
        XCTAssertTrue(app.staticTexts["Stub Movie Five"].firstMatch.waitForExistence(timeout: 10))

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

private actor PlayerDotsLoopbackFixture {
    private let media: Data
    private var listener: NWListener?
    private var connections: [UUID: NWConnection] = [:]
    private var requests: [UUID: Task<Void, Never>] = [:]

    private init(media: Data) { self.media = media }

    static func download(from url: URL) async throws -> PlayerDotsLoopbackFixture {
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        let media: Data
        let response: URLResponse
        do {
            (media, response) = try await URLSession.shared.data(for: request)
        } catch {
            try Task.checkCancellation()
            throw Failure.downloadUnavailable
        }
        guard (response as? HTTPURLResponse)?.statusCode == 200, !media.isEmpty else {
            throw Failure.invalidDownload
        }
        return PlayerDotsLoopbackFixture(media: media)
    }

    func start() async throws -> URL {
        let parameters = NWParameters.tcp
        parameters.requiredInterfaceType = .loopback
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        let listener = try NWListener(using: parameters)
        self.listener = listener
        listener.newConnectionHandler = { [weak self] connection in
            guard let self else { connection.cancel(); return }
            Task { await self.accept(connection) }
        }
        let port: UInt16 = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                listener.stateUpdateHandler = { state in
                    switch state {
                    case .ready:
                        listener.stateUpdateHandler = nil
                        if let port = listener.port {
                            continuation.resume(returning: port.rawValue)
                        } else {
                            continuation.resume(throwing: Failure.listenerUnavailable)
                        }
                    case let .failed(error):
                        listener.stateUpdateHandler = nil
                        continuation.resume(throwing: error)
                    case .cancelled:
                        listener.stateUpdateHandler = nil
                        continuation.resume(throwing: CancellationError())
                    default:
                        break
                    }
                }
                listener.start(queue: DispatchQueue(label: "player-dots.loopback.listener"))
            }
        } onCancel: {
            listener.cancel()
        }
        return try XCTUnwrap(URL(string: "http://127.0.0.1:\(port)/fixture.mkv"))
    }

    func stop() async {
        listener?.cancel()
        listener = nil
        let pending = Array(requests.values)
        for request in pending { request.cancel() }
        for connection in connections.values { connection.cancel() }
        for request in pending { await request.value }
    }

    private func accept(_ connection: NWConnection) {
        guard listener != nil else { connection.cancel(); return }
        let id = UUID()
        connections[id] = connection
        requests[id] = Task { await serve(connection, id: id) }
    }

    private func serve(_ connection: NWConnection, id: UUID) async {
        defer { connection.cancel(); connections[id] = nil; requests[id] = nil }
        connection.start(queue: DispatchQueue(label: "player-dots.loopback.request"))
        do {
            var header = Data()
            while header.range(of: Data("\r\n\r\n".utf8)) == nil {
                let chunk: Data = try await withCheckedThrowingContinuation { continuation in
                    connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { data, _, _, error in
                        if let error { continuation.resume(throwing: error) }
                        else { continuation.resume(returning: data ?? Data()) }
                    }
                }
                guard !chunk.isEmpty else { return }
                header.append(chunk)
                guard header.count <= 16_384 else { return }
            }
            let lines = String(decoding: header, as: UTF8.self).components(separatedBy: "\r\n")
            let request = lines[0].split(separator: " ")
            guard request.count >= 2, request[0] == "GET" || request[0] == "HEAD",
                  request[1] == "/fixture.mkv" else { return }
            let rangeHeader = lines.first { $0.lowercased().hasPrefix("range:") }
                .map { $0.dropFirst(6).trimmingCharacters(in: .whitespaces) }
            let range = byteRange(rangeHeader)
            let status: String
            if range == nil { status = "416 Range Not Satisfiable" }
            else if rangeHeader == nil { status = "200 OK" }
            else { status = "206 Partial Content" }
            var response = "HTTP/1.1 \(status)\r\nContent-Type: video/x-matroska\r\nAccept-Ranges: bytes\r\nConnection: close\r\n"
            response += "Content-Length: \(range?.count ?? 0)\r\n"
            if let range, rangeHeader != nil {
                response += "Content-Range: bytes \(range.lowerBound)-\(range.upperBound - 1)/\(media.count)\r\n"
            } else if range == nil {
                response += "Content-Range: bytes */\(media.count)\r\n"
            }
            var packet = Data((response + "\r\n").utf8)
            if request[0] == "GET", let range { packet.append(media.subdata(in: range)) }
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                connection.send(content: packet, isComplete: true, completion: .contentProcessed { error in
                    if let error { continuation.resume(throwing: error) }
                    else { continuation.resume() }
                })
            }
        } catch {
            // Media probes can close a range request before consuming its body.
            return
        }
    }

    private func byteRange(_ header: String?) -> Range<Int>? {
        guard let header else { return 0..<media.count }
        guard header.lowercased().hasPrefix("bytes=") else { return nil }
        let bounds = header.dropFirst(6).split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        guard bounds.count == 2 else { return nil }
        if bounds[0].isEmpty {
            guard let suffix = Int(bounds[1]), suffix > 0 else { return nil }
            return max(0, media.count - suffix)..<media.count
        }
        guard let start = Int(bounds[0]), start >= 0, start < media.count else { return nil }
        if bounds[1].isEmpty { return start..<media.count }
        guard let end = Int(bounds[1]), end >= start else { return nil }
        return start..<(min(end, media.count - 1) + 1)
    }

    private enum Failure: LocalizedError {
        case downloadUnavailable, invalidDownload, listenerUnavailable

        var errorDescription: String? {
            switch self {
            case .downloadUnavailable:
                "Device fixture download failed; check Mini LAN transport and test-runner local-network permission."
            case .invalidDownload:
                "The Mini fixture server did not return video data."
            case .listenerUnavailable:
                "The test runner could not open its loopback fixture listener."
            }
        }
    }
}
