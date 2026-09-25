import SwiftUI

/// The tab's toolbar, handed down to the pages pushed on it.
///
/// A title page covered Discover's and Library's `.toolbar`, so opening one
/// swapped the bar: Search and Refresh went and a different back button came
/// (owner, 2026-09-24: "content page changes the nav bar — let's make the GUI
/// consistent"). Discover and Library put their own items here; a title page
/// draws them unchanged with its back button beside them
/// (`appleTitlePageToolbar`), as the Apple TV app on the Mac keeps its bar.
/// A page pushed with `navigationDestination` takes the stack's environment,
/// not the view that declared it, so each destination is handed this
/// explicitly; a `NavigationLink` destination inherits it.
struct AppleTabToolbarContext {
    let tab: OpenStreamTab
    /// Read by the page's bar as it draws, not when the page was pushed: a
    /// pushed page's copy of this is not rebuilt with the tab, and a Bool
    /// here left Refresh spinning after the tab had finished.
    let isRefreshing: () -> Bool
    let onSearch: () -> Void
    let onRefresh: () -> Void
}

extension EnvironmentValues {
    @Entry var appleTabToolbar: AppleTabToolbarContext? = nil
}

#if !os(tvOS)
extension View {
    /// The title page's bar: a round ‹ at the leading edge, then the tab's
    /// own Search and Refresh. ⌘[ and Esc go back too, except while
    /// `backIsBlocked` (a player is up and owns Esc).
    func appleTitlePageToolbar(backIsBlocked: Bool = false, onBack: @escaping () -> Void) -> some View {
        modifier(AppleTitlePageToolbar(backIsBlocked: backIsBlocked, onBack: onBack))
    }
}

private struct AppleTitlePageToolbar: ViewModifier {
    let backIsBlocked: Bool
    let onBack: () -> Void
    @Environment(\.appleTabToolbar) private var tabToolbar

    func body(content: Content) -> some View {
        // Read here, in `body`, so the page redraws when the tab's store
        // changes; the toolbar builder below runs outside that tracking.
        let isRefreshing = tabToolbar?.isRefreshing() ?? false
        return content
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    Button(action: onBack) {
                        Label("Back", systemImage: "chevron.left")
                    }
                    .keyboardShortcut("[", modifiers: .command)
                    .help("Back")
                    .accessibilityIdentifier("detail.back")
                    .appleVisionActionTarget()
                }
                if let tabToolbar {
                    AppleTabToolbar(tab: tabToolbar.tab, isRefreshing: isRefreshing,
                                    onSearch: tabToolbar.onSearch, onRefresh: tabToolbar.onRefresh)
                }
            }
            #if os(macOS)
            // Esc, which the round button cannot carry beside ⌘[.
            .background {
                Button("Back", action: onBack)
                    .keyboardShortcut(.cancelAction)
                    .disabled(backIsBlocked)
                    .opacity(0)
                    .frame(width: 0, height: 0)
                    .accessibilityHidden(true)
            }
            #endif
    }
}
#endif
