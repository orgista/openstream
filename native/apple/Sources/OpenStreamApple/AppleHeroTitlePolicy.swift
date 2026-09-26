import Foundation

/// What a home hero's title slot draws.
enum AppleHeroTitlePresentation: Equatable, Sendable {
    /// The wordmark: drawn, or its slot held empty while it loads, so
    /// nothing moves when it lands (owner, N62).
    case wordmark(URL)
    /// The name: there is no wordmark, it failed, or it did not load within
    /// the grace. The name then keeps the slot; a mark that lands later
    /// does not replace it.
    case name

    /// The wordmark the slot is loading or drawing, if any.
    var wordmarkURL: URL? {
        if case .wordmark(let url) = self { return url }
        return nil
    }

    var showsName: Bool { self == .name }
}

/// The hero always shows its title (owner/driver 2026-09-23: a Binnelanders
/// page drew neither wordmark nor name). It replaces, for the heroes, the
/// old rule (`AppleTVBillboardTitleTreatment`) that left the slot empty when
/// the art was a poster — that was the Binnelanders page: no backdrop, so the
/// poster was drawn and the title dropped. The rotation now only picks titles
/// with a backdrop (`AppleHeroRotation.hasBackdrop`), and when none has one
/// the name still goes over whatever art there is.
enum AppleHeroTitlePolicy {
    /// How long a page holds its wordmark's slot empty while the mark
    /// loads. Owner, N62: the hero showed the name, then swapped to the logo
    /// and the layout jumped. While the logo loads there is no title and its
    /// space stays reserved; the name stands in only when the logo is
    /// missing, fails, or has not loaded within five seconds. The page gate
    /// and the iPhone preload warm the marks, so one normally lands at once.
    static let loadingGrace: TimeInterval = 5.0

    /// - Parameters:
    ///   - wordmark: the page's wordmark URL, if it has one.
    ///   - loaded: the wordmark URL that has drawn, if any.
    ///   - failed: the wordmark URL that failed to load, if any.
    ///   - graceExpired: whether `loadingGrace` has passed since the page was shown.
    static func presentation(wordmark: URL?, loaded: URL?, failed: URL?, graceExpired: Bool) -> AppleHeroTitlePresentation {
        guard let wordmark, wordmark != failed else { return .name }
        if wordmark == loaded || !graceExpired { return .wordmark(wordmark) }
        return .name
    }
}
