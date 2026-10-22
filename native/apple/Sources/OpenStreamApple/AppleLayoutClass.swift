import SwiftUI

/// A window's layout, independent of the device family. The existing title-page
/// tablet breakpoint is 600 pt; checking both axes keeps rotated phones small.
/// The iPhone Duo (Xcode 27.2 device profile) is 466 x 678 pt folded and
/// 669 x 951 pt unfolded (inner panel 2007 x 2853 px at 3x): the breakpoint
/// sits between its two short sides.
enum AppleLayoutClass {
    static let minimumShortSide: CGFloat = 600

    static func isLarge(size: CGSize, isRegularWidth: Bool) -> Bool {
        isRegularWidth && min(size.width, size.height) >= minimumShortSide
    }

    static func settingsUseSplitView(size: CGSize, isRegularWidth: Bool, preservesPortraitStack: Bool) -> Bool {
        isLarge(size: size, isRegularWidth: isRegularWidth)
            && (!preservesPortraitStack || size.width > size.height)
    }

    /// Discover and Library keep the phone's landing chrome (no bar at rest, round
    /// Search and Refresh over the art) on every phone, an unfolded Duo included;
    /// only a large iPad window shows the stock bar with its title.
    static func usesPadLandingChrome(isLarge: Bool, isPhone: Bool) -> Bool {
        isLarge && !isPhone
    }
}

extension EnvironmentValues {
    @Entry var appleIsLargeLayout = false
    @Entry var appleExpandsPhoneLayout = false

    var appleUsesPadLandingChrome: Bool {
        // `appleExpandsPhoneLayout` is set only for a large window on a phone.
        AppleLayoutClass.usesPadLandingChrome(isLarge: appleIsLargeLayout, isPhone: appleExpandsPhoneLayout)
    }
}
