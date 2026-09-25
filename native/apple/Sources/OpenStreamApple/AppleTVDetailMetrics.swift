import CoreGraphics
import Foundation

/// The platform a layout decision is made for. Kept as data so tests on the
/// Mac can assert the tvOS branch without compiling for tvOS.
public enum AppleUIPlatform: Sendable, Equatable {
    case iOS
    case tvOS
    case visionOS
    case macOS

    public static var current: AppleUIPlatform {
        #if os(tvOS)
        .tvOS
        #elseif os(visionOS)
        .visionOS
        #elseif os(macOS)
        .macOS
        #else
        .iOS
        #endif
    }
}

/// Focus targets on the Apple TV title page. Play is the default.
enum AppleTVDetailFocus: Hashable, Sendable {
    case play
    case myList
    case rate
    /// One of the three choices Rate expands into.
    ///
    /// Expanding replaces the Rate button with the choices, which removes the
    /// view that had focus. Without a target of their own, focus fell back to
    /// `defaultFocus` and the remote jumped to Play — the owner's "when you
    /// rate if you click rate it sends you back to Play button" (2026-09-15).
    case rateChoice(Int)
}

/// How the Apple TV title page gets Play focused when it opens.
///
/// `defaultFocus` alone was not enough (UI tests, 2026-09-23): a focus request
/// made while the push is still animating is dropped, so the page could open
/// with nothing focused, and on another run focus carried over from the page
/// underneath and landed on Rate — from where Down reaches nothing. Until the
/// opening target has held focus once, the page keeps asking for it and sends
/// any other title-row focus back to it. After that the remote is the user's.
/// The target is Play, or My List on a page with nothing to play, which has
/// no Play button (N22c).
enum AppleTVDetailOpeningFocus {
    /// How long the page keeps asking before it gives up and leaves focus to
    /// the engine, and how often it asks.
    static let attempts = 30
    static let interval: Duration = .milliseconds(100)

    /// The first control on the title row: Play, or My List without it.
    static func target(showsPlay: Bool) -> AppleTVDetailFocus {
        showsPlay ? .play : .myList
    }

    /// Whether `focus` means the target has taken focus, so the opening is over.
    static func settles(on focus: AppleTVDetailFocus?, target: AppleTVDetailFocus = .play) -> Bool {
        focus == target
    }

    /// The focus to request while the opening is not over yet: the target,
    /// unless focus has already moved below the title row (`nil` there means
    /// an episode or a shelf holds it), which only a user can do.
    static func correction(for focus: AppleTVDetailFocus?, hasHadAnyFocus: Bool,
                           target: AppleTVDetailFocus = .play) -> AppleTVDetailFocus? {
        switch focus {
        case let focus? where focus == target: nil
        case .play, .myList, .rate, .rateChoice: target
        case nil: hasHadAnyFocus ? nil : target
        }
    }
}

/// Where focus goes when it climbs back onto the title row from below.
///
/// Focus is geometric, and the shelves below span the screen while the title
/// row sits at the leading edge, so Up from a card in the middle landed on
/// Rate — the last thing anyone climbs up for (N41 survey, both kinds of
/// title page). The Apple TV app goes back to its primary action; so does
/// this page. `nil` is focus below the title row; moves along the row are the
/// user's and are left alone.
enum AppleTVDetailReturnFocus {
    static func correction(from old: AppleTVDetailFocus?, to new: AppleTVDetailFocus?,
                           target: AppleTVDetailFocus) -> AppleTVDetailFocus? {
        guard old == nil, let new, new != target else { return nil }
        return target
    }
}

/// Apple TV title page geometry from the rework plan (FEEDBACK section C,
/// task 5): a 1920x1080 backdrop, the overlay anchored bottom-leading at
/// (80, bottom 60), a 220x66 Play pill, 38 pt glyph actions whose centers are
/// 120 pt apart, then synopsis, Episodes and More Like This below the fold.
/// Every number lives here so tests can assert the layout without a view.
enum AppleTVDetailMetrics {
    // Screen and hero
    static let screenSize = CGSize(width: 1920, height: 1080)
    static var heroFrame: CGRect { CGRect(origin: .zero, size: screenSize) }

    // Overlay anchor: HIG safe zone, 80 pt from the sides and 60 pt from the bottom.
    static let overlayLeadingInset: CGFloat = 80
    static let overlayBottomInset: CGFloat = 60
    static var overlayOrigin: CGPoint {
        CGPoint(x: overlayLeadingInset, y: screenSize.height - overlayBottomInset)
    }
    static let overlayColumnWidth: CGFloat = 900
    static let overlaySpacing: CGFloat = 24

    // Title: wordmark when it loads, Title 1 (76 pt) text only if it fails.
    static let wordmarkMaxSize = CGSize(width: 560, height: 180)
    static let titleFontSize: CGFloat = 76
    static let titleLineLimit = 2

    // Metadata line: Body 29 with Caption 2 (23 pt) badges.
    static let metadataFontSize: CGFloat = 29
    static let badgeFontSize: CGFloat = 23
    static let badgeHeight: CGFloat = 40
    static let badgeHorizontalPadding: CGFloat = 10
    static let badgeCornerRadius: CGFloat = 6
    static let badgeGap: CGFloat = 14

    // Play pill: 220x66, Callout 31.
    static let pillSize = CGSize(width: 220, height: 66)
    static let pillFontSize: CGFloat = 31
    static let pillGlyphSize: CGFloat = 28
    static let pillGlyphSpacing: CGFloat = 12
    static let pillToIconSpacing: CGFloat = 40

    // My List / Rate: 38 pt glyphs, Caption 2 labels, centers 120 pt apart.
    static let iconGlyphSize: CGFloat = 38
    static let iconDiscSize: CGFloat = 80
    static let iconLabelFontSize: CGFloat = 23
    static let iconLabelSpacing: CGFloat = 8
    static let iconCellWidth: CGFloat = 120

    /// Horizontal centers of `count` glyph cells laid out edge to edge.
    static func iconCenters(count: Int) -> [CGFloat] {
        (0 ..< max(0, count)).map { iconCellWidth * (CGFloat($0) + 0.5) }
    }

    // Below the fold
    static let synopsisFontSize: CGFloat = 29
    static let synopsisColumnWidth: CGFloat = 900
    static let sectionSpacing: CGFloat = 60
    static let shelfTitleFontSize: CGFloat = 38
    static let shelfTitleSpacing: CGFloat = 24
    static let shelfVerticalBleed: CGFloat = 24

    // Episodes: 16:9 cards 400x225.
    static let episodeCardSize = CGSize(width: 400, height: 225)
    static let episodeCardGap: CGFloat = 40
    static let episodeTitleFontSize: CGFloat = 29
    static let episodeSubtitleFontSize: CGFloat = 25
    static let seasonPillHeight: CGFloat = 56
    static let seasonPillFontSize: CGFloat = 29
    static let seasonPillGap: CGFloat = 16

    // More Like This: 260x390 posters, 40 pt gaps, Caption 1 names.
    static let posterSize = CGSize(width: 260, height: 390)
    static let posterGap: CGFloat = 40
    static let posterNameFontSize: CGFloat = 25

    // Focus treatment shared by cards and glyphs
    static let cardCornerRadius: CGFloat = 18
    static let focusRingWidth: CGFloat = 4
    static let focusScale: CGFloat = 1.06

    /// The full-screen tvOS layout replaces the phone/iPad detail page only on
    /// Apple TV; every other platform keeps its current branch.
    static func usesTVDetailLayout(on platform: AppleUIPlatform) -> Bool {
        platform == .tvOS
    }
}
