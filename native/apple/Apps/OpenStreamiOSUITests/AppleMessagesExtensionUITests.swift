import XCTest

/// Drives the real Messages app to prove the OpenStream iMessage extension
/// loads, lists what the app published into the shared app group, and composes
/// a real message bubble.
///
/// Nothing else can reach it: the extension has no host app of its own,
/// `simctl` cannot open the Messages send menu, and `Messages.framework` does
/// not exist on macOS, so `swift test` cannot touch it. What the extension
/// *decides* — which titles it offers and what the bubble says — is covered by
/// `AppleMessagesShareTests` in the package; this covers that it is installed,
/// discoverable, renders, and inserts.
///
/// The rows come from `topshelf-v1.json` in `group.com.orgista.openstream`,
/// which the app writes only while Continue Watching publishing is on under
/// Settings › Privacy. Fixture runs publish their own Continue Watching title.
@MainActor
final class AppleMessagesExtensionUITests: OpenStreamUITestCase {
    private var messages: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        messages = XCUIApplication(bundleIdentifier: "com.apple.MobileSMS")
    }

    override func tearDown() {
        messages?.terminate()
    }

    func testOpenStreamComposesAShareBubble() throws {
        let fixtureRun = ProcessInfo.processInfo.environment["OPENSTREAM_STUB_DIR"]?.isEmpty == false
        let fixtureTitle = "Stub Movie Six"
        let host = XCUIApplication(bundleIdentifier: "com.orgista.openstream")
        defer { if fixtureRun { host.terminate() } }
        if fixtureRun {
            // The fixture Jellyfin resumes Stub Movie Six (`Tests/Fixtures/serve.py`).
            host.launchArguments = Self.stubbedLaunchArguments + ["-OpenStreamVisionScreen", "discover"]
            configureFixtureLaunch(host)
            host.launch()
            let continued = host.descendants(matching: .any).matching(NSPredicate(format:
                "identifier BEGINSWITH %@ AND label BEGINSWITH %@", "home.continue.", fixtureTitle)).firstMatch
            XCTAssertTrue(host.descendants(matching: .any).matching(NSPredicate(format:
                "identifier BEGINSWITH 'home.' OR identifier BEGINSWITH 'discover.'")).firstMatch
                .waitForExistence(timeout: 40), "Discover did not load the Messages fixture")
            for _ in 0..<8 where !continued.exists {
                host.swipeUp()
                _ = continued.waitForExistence(timeout: 3)
            }
            XCTAssertTrue(continued.exists, "the Messages fixture was not published in Continue Watching")
        }
        messages.launch()

        // iOS 26 opens Messages behind a one-time notice about message
        // screening; the conversation list is not hittable until it is gone.
        let acknowledge = messages.buttons["OK"]
        if acknowledge.waitForExistence(timeout: 5) { acknowledge.tap() }

        // Messages can restore the conversation instead of its list.
        let compose = messages.descendants(matching: .any).matching(identifier: "messageBodyField").firstMatch
        if !compose.exists {
            let list = messages.collectionViews["ConversationList"]
            XCTAssertTrue(list.waitForExistence(timeout: 20), "Messages showed neither a conversation nor its list")
            let conversation = list.cells.firstMatch
            XCTAssertTrue(conversation.waitForExistence(timeout: 20), "no conversation to open")
            conversation.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }
        XCTAssertTrue(compose.waitForExistence(timeout: 10), "the conversation never opened")
        // Match the compose field's adjacent add button, rather than an arbitrary
        // unlabelled button below y=400 (which can be a transcript control).
        let namedApps = messages.buttons.matching(NSPredicate(format:
            "identifier == %@ OR label == %@ OR label == %@", "Apps", "Apps", "Add")).firstMatch
        let adjacentApps = messages.buttons.matching(NSPredicate { value, _ in
            guard let button = value as? XCUIElementAttributes else { return false }
            let field = compose.frame
            return button.frame.maxX <= field.minX + 8 && abs(button.frame.midY - field.midY) < 36
        }).firstMatch
        let apps = namedApps.exists ? namedApps : adjacentApps
        XCTAssertTrue(apps.waitForExistence(timeout: 8), "no Apps control beside compose: \(messages.debugDescription)")
        apps.tap()

        // Host versions expose menu entries as cells, buttons, or combined elements.
        let entry = messages.descendants(matching: .any).matching(NSPredicate(format:
            "identifier CONTAINS %@ OR label == %@", "com.orgista.openstream.messages", "oStream")).firstMatch
        // Messages can report an edge as a tiny negative coordinate while the
        // entire row is visible. Allow one point of geometry rounding.
        let visibleEntry = NSPredicate { _, _ in
            entry.exists && !entry.frame.isEmpty && self.messages.frame.insetBy(dx: -1, dy: -1).contains(entry.frame)
        }
        for _ in 0..<6 {
            let visible = XCTNSPredicateExpectation(predicate: visibleEntry, object: nil)
            if XCTWaiter.wait(for: [visible], timeout: 2) == .completed { break }
            let more = messages.buttons["More"].firstMatch
            if more.exists, more.isHittable { more.tap() } else { messages.swipeUp() }
        }
        XCTAssertTrue(visibleEntry.evaluate(with: nil),
                      "oStream is not visible in the Messages menu: \(messages.debugDescription)")
        // Like ConversationList above, Messages nests app cells that XCTest
        // reports as unhittable even when the full cell is visible. Tap its
        // visible centre; the extension and staged bubble assertions still prove the selection.
        entry.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()

        let rows = messages.buttons.matching(identifier: "messages.share.row")
        let row = fixtureRun ? rows.matching(NSPredicate(format: "label BEGINSWITH %@", fixtureTitle + ",")).firstMatch
            : rows.firstMatch
        guard row.waitForExistence(timeout: 20) else {
            // No snapshot published: the extension still has to have loaded and
            // drawn rather than crashed or come up blank.
            XCTAssertTrue(
                !fixtureRun && messages.otherElements["messages.share.empty"].exists,
                "the extension drew neither a row nor its empty state"
            )
            return
        }

        // The subcaption is a claim about the sender, so it has to match the
        // shelf the title came from.
        let label = row.label
        XCTAssertTrue(
            label.hasSuffix("Watching now") || label.hasSuffix("On oStream"),
            "unexpected row wording: \(label)"
        )
        let title = String(label.split(separator: ",").first ?? "")
        row.tap()

        // A staged MSMessage renders as a link in the compose field, and the
        // send button only appears once there is something to send. iOS 26
        // appends ", 1 image" to the label when the poster loaded, so this
        // matches on the caption and subcaption rather than the whole string.
        let staged = messages.links.matching(
            NSPredicate(format: "label BEGINSWITH %@", label)
        ).firstMatch
        var composed = staged.waitForExistence(timeout: 10)
        if !composed, messages.state != .runningForeground {
            // The system host can leave the foreground after share selection.
            // Return to the conversation before reading
            // the staged message; a missing bubble must still fail.
            print("Messages host left foreground after share selection: \(messages.state.rawValue)")
            messages.activate()
            XCTAssertTrue(messages.wait(for: .runningForeground, timeout: 5), "Messages did not return")
            composed = staged.waitForExistence(timeout: 10)
        }
        XCTAssertTrue(composed, "no bubble was composed for \(title)")
        XCTAssertTrue(messages.buttons["sendButton"].exists, "composed bubble is not sendable")

        // Never leave the draft behind: this runs on the owner's simulator.
        let remove = messages.buttons["Remove app from message"]
        if remove.waitForExistence(timeout: 5) {
            remove.tap()
        }
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: staged)
        XCTAssertEqual(XCTWaiter().wait(for: [gone], timeout: 10), .completed,
                       "the composed bubble was left in the conversation")
    }
}
