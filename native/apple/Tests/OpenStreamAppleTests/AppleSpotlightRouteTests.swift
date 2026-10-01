import Foundation
import Testing
@testable import OpenStreamApple

@MainActor
@Suite("Spotlight result opens the title")
struct AppleSpotlightRouteTests {
    private let recordID = String(repeating: "ab12", count: 16)

    @Test("A Spotlight item identifier (the record id) routes to that title's page")
    func identifierRoutesToMedia() {
        #expect(AppleAppRoute(spotlightIdentifier: recordID) == .media(id: recordID, action: .display))
        #expect(AppleAppRoute(spotlightIdentifier: recordID.uppercased()) == .media(id: recordID, action: .display))
    }

    @Test("Anything that is not a record id is refused", arguments: ["", "abc", "https://fixture.example/x",
                                                                 String(repeating: "z", count: 64)])
    func refusesForeignIdentifiers(_ identifier: String) {
        #expect(AppleAppRoute(spotlightIdentifier: identifier) == nil)
    }

    @Test("The router opens the media route and bumps its revision; foreign activities change nothing")
    func routerOpensResult() {
        let router = AppleAppRouter()
        #expect(!router.openSpotlightResult(identifier: nil))
        #expect(!router.openSpotlightResult(identifier: "not-ours"))
        #expect(router.route == nil)
        #expect(router.revision == 0)
        #expect(router.openSpotlightResult(identifier: recordID))
        #expect(router.route == .media(id: recordID, action: .display))
        #expect(router.revision == 1)
    }

    @Test("The indexed identifier and the deep link agree on the same route")
    func indexMatchesDeepLink() throws {
        let url = try #require(URL(string: "openstream://media/\(recordID)?action=display"))
        #expect(AppleAppRoute(url: url) == AppleAppRoute(spotlightIdentifier: recordID))
    }
}
