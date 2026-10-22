import CoreGraphics
import SwiftUI

/// Where the Live stage puts its two columns on iPhone and iPad.
enum AppleLiveStagePolicy {
    /// The guide column never gets narrower than this beside the player.
    static let minimumGuideWidth: CGFloat = 340
    static let phoneLogoSize = CGSize(width: 50, height: 50)
    static let phoneChannelRowHeight: CGFloat = 88
    static let phoneProgrammeLineHeight: CGFloat = 3
    static let phoneCategoryHeight: CGFloat = 52
    static let phoneGuideRowHeight: CGFloat = 64

    /// iPad windows split when wide enough in landscape. A large phone window
    /// (an unfolded Duo; the root already checked its size class and size)
    /// splits on its side and stacks upright, where the stage spans the width
    /// and the list fills the height below it.
    static func sideBySide(isRegularWidth: Bool, size: CGSize, expandsPhoneLayout: Bool = false) -> Bool {
        guard size.width > size.height else { return false }
        if expandsPhoneLayout { return true }
        return isRegularWidth && size.width >= minimumGuideWidth / 0.38
    }

    /// Beside the list on a large phone window the stage's column continues
    /// with the playing channel's schedule (`AppleLiveStageSchedule`). The
    /// iPad keeps its stage alone.
    static func showsSchedule(sideBySide: Bool, expandsPhoneLayout: Bool) -> Bool {
        sideBySide && expandsPhoneLayout
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
