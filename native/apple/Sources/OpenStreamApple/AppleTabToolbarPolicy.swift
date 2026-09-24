/// The trailing toolbar items each tab draws.
///
/// Discover and Library carry the same two, in the same order and drawn by the
/// same `AppleTabToolbar` (owner, 2026-09-24: Discover showed Search + Refresh
/// while Library showed Sort + Refresh). Library's Sort went ("don't need
/// it"). Apple TV draws none: Search is its own tab there and nothing floats
/// over the billboard (X4). Live and Settings keep their own.
enum AppleTabToolbarPolicy {
    enum Item: String, CaseIterable, Sendable { case search, refresh }

    static func items(for tab: OpenStreamTab, isTV: Bool = isTVPlatform) -> [Item] {
        guard !isTV else { return [] }
        switch tab {
        case .home, .library: return [.search, .refresh]
        case .search, .live, .settings: return []
        }
    }

    static var isTVPlatform: Bool {
        #if os(tvOS)
        true
        #else
        false
        #endif
    }
}
