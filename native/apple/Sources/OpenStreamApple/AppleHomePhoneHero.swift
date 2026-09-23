import SwiftUI

/// Discover's hero on an iPhone in portrait, after the Apple TV app's (owner
/// 2026-09-22 with two reference screenshots, and the Figma "iOS-OpenStream"
/// frame): art edge to edge, 540 pt tall, fading to black by 65 %; then,
/// centred, an optional "New Season" capsule, the wordmark (or the name in
/// black-weight capitals), "TV Show · Thriller · Drama" with the rating, and
/// the buttons. iPad, landscape and every other platform keep
/// `AppleFeaturedHero`.
///
/// The copy is laid out in the flow, not overlaid: at the accessibility text
/// sizes it grows the hero downwards past the art rather than clipping the
/// buttons, and the fade has already reached black by then.
struct AppleHomePhoneHero<Actions: View>: View {
    static var artHeight: CGFloat { 540 }

    let item: AppleCatalogItem
    let wordmark: URL?
    let badge: AppleHeroBadge?
    /// The still and the inline trailer, from `AppleHomeBillboard`.
    let stage: AnyView
    let onOpenDetails: () -> Void
    @ViewBuilder var actions: Actions

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .largeTitle) private var titleSize: CGFloat = 48
    @State private var failedWordmark: URL?

    var body: some View {
        VStack(spacing: 12) {
            if let badge {
                Text(badge.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .overlay { Capsule().strokeBorder(.white.opacity(0.6), lineWidth: 1) }
            }
            // The title block is the way into the title page, as tapping the
            // hero is in the Apple TV app; Details is no longer a button of
            // its own.
            Button(action: onOpenDetails) {
                VStack(spacing: 10) {
                    title
                    AppleHomePhoneHeroMetadata(item: item)
                }
                .frame(maxWidth: .infinity)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityHint("Opens the title page")
            .accessibilityIdentifier("home.featured.details")
            actions
                .padding(.top, 4)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity)
        .frame(minHeight: Self.artHeight, alignment: .bottom)
        .background(alignment: .top) {
            stage
                .frame(maxWidth: .infinity)
                .frame(height: Self.artHeight)
                .clipped()
                .overlay { AppleHomePhoneHeroFade().allowsHitTesting(false) }
        }
        .background(Color.black)
        .accessibilityElement(children: .contain)
    }

    /// The wordmark when the title has one, otherwise the name — the rule the
    /// Apple TV billboard uses (`AppleTVBillboardTitleTreatment`), so a poster
    /// that already carries its title gets no second copy.
    @ViewBuilder
    private var title: some View {
        switch AppleTVBillboardTitleTreatment.choose(hasBackdrop: item.backgroundURL != nil, wordmark: wordmark) {
        case .wordmark(let url) where url != failedWordmark:
            AppleTrimmedTitleLogo(url: url, alignment: .center) { loaded in
                if !loaded { failedWordmark = url }
            }
            .frame(maxWidth: 280)
            .frame(height: dynamicTypeSize.isAccessibilitySize ? 120 : 96)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(item.name)
            .accessibilityAddTraits(.isHeader)
        case .wordmark, .text:
            Text(item.name.uppercased())
                .font(.system(size: min(max(titleSize, 42), dynamicTypeSize.isAccessibilitySize ? 64 : 58), weight: .black))
                .tracking(1)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .minimumScaleFactor(0.6)
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.8), radius: 12, y: 2)
                .accessibilityLabel(item.name)
                .accessibilityAddTraits(.isHeader)
        case .none:
            EmptyView()
        }
    }
}
