import Foundation
import Observation

public enum AppleMediaRouteAction: String, Equatable, Sendable {
    case display
    case play
}

public enum AppleAppRoute: Equatable, Sendable {
    case search(String)
    case media(id: String, action: AppleMediaRouteAction)
    case continueWatching

    public init?(url: URL) {
        guard url.scheme?.lowercased() == "openstream", url.user == nil, url.password == nil else { return nil }
        let host = url.host?.lowercased() ?? ""
        let pieces = url.path.split(separator: "/").map(String.init)
        switch host {
        case "search":
            guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                  let value = components.queryItems?.first(where: { $0.name == "query" })?.value?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                  !value.isEmpty, value.count <= 200 else { return nil }
            self = .search(value)
        case "media":
            guard let id = pieces.first, id.count == 64,
                  id.allSatisfy({ $0.isHexDigit }),
                  let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
            let actionValue = components.queryItems?.first(where: { $0.name == "action" })?.value ?? "display"
            guard let action = AppleMediaRouteAction(rawValue: actionValue) else { return nil }
            self = .media(id: id.lowercased(), action: action)
        case "continue":
            guard pieces.isEmpty else { return nil }
            self = .continueWatching
        default:
            return nil
        }
    }
}

public extension AppleAppRoute {
    /// A tapped Spotlight result: the item's unique identifier is the media
    /// record id (`AppleSpotlightIndexer`), so it opens that title's page.
    init?(spotlightIdentifier: String) {
        let id = spotlightIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard id.count == 64, id.allSatisfy(\.isHexDigit) else { return nil }
        self = .media(id: id, action: .display)
    }
}

@MainActor
@Observable
public final class AppleAppRouter {
    public private(set) var route: AppleAppRoute?
    public private(set) var searchQuery = ""
    public private(set) var revision = 0

    public init() {}

    public func open(_ url: URL) {
        guard let value = AppleAppRoute(url: url) else { return }
        open(value)
    }

    /// A route that did not come from a URL: an App Intent (Siri, Shortcuts,
    /// Spotlight) handed over through `AppleAppIntentHandoff`.
    public func open(_ value: AppleAppRoute) {
        route = value
        if case .search(let query) = value { searchQuery = query }
        revision &+= 1
    }

    /// Continues a tapped Spotlight result (`CSSearchableItemActionType`):
    /// `identifier` is `CSSearchableItemActivityIdentifier` from the activity.
    /// False, and nothing changes, for anything that is not one of ours.
    @discardableResult
    public func openSpotlightResult(identifier: String?) -> Bool {
        guard let identifier, let value = AppleAppRoute(spotlightIdentifier: identifier) else { return false }
        appleTrace("spotlight result → media route")
        open(value)
        return true
    }

    /// Opens Search with nothing typed yet — the Mac ⌘F path.
    ///
    /// Separate from `showSearch(_:)` because that one deliberately refuses an
    /// empty query: it serves `openstream://search?query=…` deep links, and a
    /// link with no term in it is a malformed link. A menu command is the
    /// opposite case — an empty field is exactly what it should open.
    public func openSearch() {
        searchQuery = ""
        route = .search("")
        revision &+= 1
    }

    public func showSearch(_ query: String) {
        let clean = String(query.trimmingCharacters(in: .whitespacesAndNewlines).prefix(200))
        guard !clean.isEmpty else { return }
        searchQuery = clean
        route = .search(clean)
        revision &+= 1
    }
}
