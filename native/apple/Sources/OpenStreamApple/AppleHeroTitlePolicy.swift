import Foundation

/// What a home hero's title slot draws.
enum AppleHeroTitlePresentation: Equatable, Sendable {
    /// The wordmark: drawn, or inside the short grace while it loads.
    case wordmark(URL)
    /// The name, while the wordmark keeps loading underneath; it takes over
    /// the slot the moment it lands.
    case nameWhileLoading(URL)
    /// The name: there is no wordmark, or it failed.
    case name

    /// The wordmark the slot keeps loading, if any.
    var wordmarkURL: URL? {
        switch self {
        case .wordmark(let url), .nameWhileLoading(let url): url
        case .name: nil
        }
    }

    var showsName: Bool {
        if case .wordmark = self { return false }
        return true
    }
}

/// The hero always shows its title (owner/driver 2026-09-23: a Binnelanders
/// page drew neither wordmark nor name). It replaces, for the heroes, the
/// old rule (`AppleTVBillboardTitleTreatment`) that left the slot empty when
/// the art was a poster — that was the Binnelanders page: no backdrop, so the
/// poster was drawn and the title dropped. The rotation now only picks titles
/// with a backdrop (`AppleHeroRotation.hasBackdrop`), and when none has one
/// the name still goes over whatever art there is.
enum AppleHeroTitlePolicy {
    /// How long a page shows an empty slot while its wordmark loads. Short:
    /// long enough that a mark already in the caches (the page gate and the
    /// iPhone preload warm them) lands without the name flashing first, short
    /// enough that a slow mark never leaves a page without a title. The title
    /// page's 3 s grace (`AppleTitleLogoPolicy`) is for a page the viewer
    /// chose; a rotating page may only be up for a few seconds.
    static let loadingGrace: TimeInterval = 0.3

    /// - Parameters:
    ///   - wordmark: the page's wordmark URL, if it has one.
    ///   - loaded: the wordmark URL that has drawn, if any.
    ///   - failed: the wordmark URL that failed to load, if any.
    ///   - graceExpired: whether `loadingGrace` has passed since the page was shown.
    static func presentation(wordmark: URL?, loaded: URL?, failed: URL?, graceExpired: Bool) -> AppleHeroTitlePresentation {
        guard let wordmark, wordmark != failed else { return .name }
        if wordmark == loaded || !graceExpired { return .wordmark(wordmark) }
        return .nameWhileLoading(wordmark)
    }
}
