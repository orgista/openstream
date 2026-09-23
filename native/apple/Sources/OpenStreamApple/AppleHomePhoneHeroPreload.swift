import SwiftUI

/// One iPhone hero page's still and wordmark at the sizes the page draws them,
/// for `AppleHomePhoneHeroCarousel` to warm the image caches with. Never shown.
struct AppleHomePhoneHeroPreload: View {
    let item: AppleCatalogItem
    let wordmark: URL?
    let width: CGFloat

    var body: some View {
        ZStack {
            AppleCatalogArtwork(url: item.backgroundURL ?? item.posterURL)
                .frame(width: max(width, 1), height: AppleHomePhoneHero<EmptyView>.artHeight)
            if case .wordmark(let url) = AppleTVBillboardTitleTreatment.choose(
                hasBackdrop: item.backgroundURL != nil, wordmark: wordmark
            ) {
                AppleTrimmedTitleLogo(url: url, alignment: .center)
                    .frame(width: 280, height: 96)
            }
        }
        .frame(width: max(width, 1), height: AppleHomePhoneHero<EmptyView>.artHeight)
        .clipped()
    }
}
