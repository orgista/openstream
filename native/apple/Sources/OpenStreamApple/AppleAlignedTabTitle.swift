import SwiftUI

/// How a tab root is titled on each platform.
enum AppleTabTitleStyle: Equatable, Sendable {
    /// iPhone and iPad: a stock navigation title that collapses with scrolling.
    case largeNavigationTitle
    /// Apple TV: no page title under the tab bar (the stock TV app has none).
    case hidden
    /// Mac and Vision Pro: the stock inline-large navigation title.
    case inlineLargeNavigationTitle
}

/// Uses a native navigation title so iOS does not turn plain text into toolbar chrome.
struct AppleAlignedTabTitle: ViewModifier {
    let title: String

    static func style(for platform: AppleUIPlatform) -> AppleTabTitleStyle {
        switch platform {
        case .iOS: .largeNavigationTitle
        case .tvOS: .hidden
        case .visionOS, .macOS: .inlineLargeNavigationTitle
        }
    }

    func body(content: Content) -> some View {
        #if os(iOS)
        content
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.large)
        #elseif os(tvOS)
        content
        #else
        content
            .navigationTitle(title)
            .toolbarTitleDisplayMode(.inlineLarge)
        #endif
    }
}

extension View {
    func appleAlignedTabTitle(_ title: String) -> some View { modifier(AppleAlignedTabTitle(title: title)) }
}
