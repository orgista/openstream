import SwiftUI

/// One iPhone hero page's still and wordmark at the sizes the page draws them,
/// for `AppleHomePhoneHeroCarousel` to warm the image caches with. Never shown.
struct AppleHomePhoneHeroPreload: View {
    let item: AppleCatalogItem
    let wordmark: URL?
    let width: CGFloat
    let artHeight: CGFloat
    /// The bottom of the large title, as the page passes it to its stage.
    var topInset: CGFloat = 0

    var body: some View {
        ZStack {
            // Settles the next page's art (and remembers it) before it
            // slides in, so it arrives drawn, already cropped.
            AppleHomePhonePortraitStage(item: item, topInset: topInset)
                .frame(width: max(width, 1), height: artHeight)
            // The page draws its wordmark whatever the art (`AppleHeroTitlePolicy`).
            if let url = wordmark {
                AppleTrimmedTitleLogo(url: url, alignment: .center)
                    .frame(width: 280, height: 96)
            }
        }
        .frame(width: max(width, 1), height: artHeight)
        .clipped()
    }
}
