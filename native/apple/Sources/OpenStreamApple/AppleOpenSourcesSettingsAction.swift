import SwiftUI

extension EnvironmentValues {
    /// Switches to Settings and opens Sources, the page where a stream source
    /// is added, fixed or signed in again. Set once by the root view; a title
    /// page's "Sources…" answer to a playback failure calls it. Nil outside
    /// the app's root (previews, debug fixtures), where the page falls back to
    /// its own `openSettings`.
    @Entry var appleOpenSourcesSettings: (@MainActor () -> Void)? = nil
}
