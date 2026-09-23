import SwiftUI

/// A home hero's title slot: the wordmark when it has drawn, otherwise the
/// name — never nothing (`AppleHeroTitlePolicy`). Each hero supplies its own
/// mark and name styling; this owns only which of the two is on screen.
struct AppleHeroTitleLockup<Mark: View, Name: View>: View {
    /// The page being shown; the loading grace restarts when it changes.
    let pageID: String
    let wordmark: URL?
    var alignment: Alignment = .leading
    /// The wordmark view. It must call `onLoadResult` as
    /// `AppleTrimmedTitleLogo` does: true once drawn, false when it failed.
    @ViewBuilder let mark: (_ url: URL, _ onLoadResult: @escaping (Bool) -> Void) -> Mark
    @ViewBuilder let name: () -> Name

    @State private var loadedWordmark: URL?
    @State private var failedWordmark: URL?
    /// The page whose grace has run out. Keyed by page rather than a flag, so
    /// the frame a new page arrives on does not inherit the last one's.
    @State private var graceExpiredPage: String?

    var body: some View {
        let presentation = AppleHeroTitlePolicy.presentation(
            wordmark: wordmark, loaded: loadedWordmark, failed: failedWordmark, graceExpired: graceExpiredPage == pageID
        )
        ZStack(alignment: alignment) {
            if presentation.showsName {
                name()
            }
            if let url = presentation.wordmarkURL {
                mark(url) { loaded in
                    if loaded { loadedWordmark = url } else { failedWordmark = url }
                }
                // Only one of the two is the title for VoiceOver.
                .accessibilityHidden(presentation.showsName)
            }
        }
        .task(id: pageID) {
            try? await Task.sleep(for: .seconds(AppleHeroTitlePolicy.loadingGrace))
            guard !Task.isCancelled else { return }
            graceExpiredPage = pageID
        }
    }
}
