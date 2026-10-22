import CoreGraphics
import SwiftUI

/// Where the Live stage puts its two columns on iPhone and iPad.
enum AppleLiveStagePolicy {
    /// The guide column never gets narrower than this beside the player.
    static let minimumGuideWidth: CGFloat = 340
    static let phoneLogoSize = CGSize(width: 50, height: 50)
    static let phoneChannelRowHeight: CGFloat = 88
    static let phoneProgrammeLineHeight: CGFloat = 3
    /// Paramount+ on DevPlus (2026-10-21): one flat #121212 panel from the stage's bottom edge
    /// carries the category strip and the rows; the strip is 81 pt from the stage to the first row,
    /// its underline 1 pt, as wide as the label, 6 pt under it; labels about 40 pt apart.
    static let phoneCategoryHeight: CGFloat = 81
    static let phoneCategorySpacing: CGFloat = 40
    static let phoneCategoryUnderlineHeight: CGFloat = 1
    static let phoneCategoryUnderlineGap: CGFloat = 6
    static let phonePanel = Color(white: 18 / 255)
    static let phoneGuideRowHeight: CGFloat = 64

    /// Side by side only in a regular-width window wider than it is tall and
    /// wide enough for both columns; stacked everywhere else. Decided by the
    /// window, never the device, so a resized iPad window (or a foldable's
    /// inner screen) follows its own shape.
    static func sideBySide(isRegularWidth: Bool, size: CGSize) -> Bool {
        isRegularWidth && size.width > size.height
            && size.width >= minimumGuideWidth / 0.38
    }

    /// The player column's width beside the guide: 62 %, leaving the guide
    /// at least `minimumGuideWidth`.
    static func playerWidth(total: CGFloat) -> CGFloat {
        max(0, min((total * 0.62).rounded(.down), total - minimumGuideWidth))
    }
}

#if os(iOS)
/// The system tab bar keeps its standard opaque background over the Live
/// list on iOS 18, so the rows do not show through it (owner decision
/// 2026-10-09). iOS 26 keeps its own Liquid Glass bar untouched.
struct AppleLiveTabBarBackground: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content
        } else {
            content.toolbarBackground(.visible, for: .tabBar)
        }
    }
}
#endif
