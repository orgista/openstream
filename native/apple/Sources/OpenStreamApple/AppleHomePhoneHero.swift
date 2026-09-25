import SwiftUI

/// Discover's hero on an iPhone in portrait, after the Apple TV app's (owner
/// 2026-09-22 with two reference screenshots, and the Figma "iOS-OpenStream"
/// frame): art edge to edge from the top of the screen, under the large
/// title, to 73 % of its height (`AppleHomePhoneHeroLayout`), fading to black
/// at the bottom; then, centred and anchored to the bottom of the art, an
/// optional "New Season" capsule, the wordmark (or, until and unless it draws,
/// the name in black-weight capitals), "TV Show · Thriller · Drama" with the rating, and the buttons,
/// with the carousel's page dots under them. iPad, landscape and every other
/// platform keep `AppleFeaturedHero`.
///
/// The copy is laid out in the flow, not overlaid: at the accessibility text
/// sizes it grows the hero downwards past the art rather than clipping the
/// buttons, and the fade has already reached black by then.
struct AppleHomePhoneHero<Actions: View>: View {
    let item: AppleCatalogItem
    /// From the top edge of the screen: the hero is drawn pulled up under the
    /// navigation bar by `AppleHomePhoneHeroLayout.topOverlap`.
    let artHeight: CGFloat
    /// Where the copy has faded out, from the top of the screen:
    /// `AppleHomePhoneHeroLayout.topInset`.
    let copyFadeLine: CGFloat
    let wordmark: URL?
    let badge: AppleHeroBadge?
    /// The still and the inline trailer, from `AppleHomeBillboard`.
    let stage: AnyView
    /// The still's luminance, once measured (`AppleHeroLuminanceCache`).
    var artLuminance: AppleHeroLuminanceMap? = nil
    let onOpenDetails: () -> Void
    @ViewBuilder var actions: Actions

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .largeTitle) private var titleSize: CGFloat = 48
    @State private var copyHidden = false
    @State private var artWidth: CGFloat = 0
    /// A trailer is on screen over the still, whose tone then no longer applies.
    @State private var videoIsShowing = false

    private var scrim: AppleHeroScrim {
        let region = AppleHeroCopyRegion.phone(width: artWidth, artHeight: artHeight)
        let reading = artLuminance?.reading(region: region, in: CGSize(width: artWidth, height: artHeight))
        return .phone(tone: videoIsShowing ? .unknown : AppleHeroArtTone(reading: reading))
    }

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
                .appleHeroCopyShadow(scrim.copyShadow)
                .animation(.easeInOut(duration: 0.3), value: scrim.copyShadow)
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
        // Faded out is gone: no taps and no VoiceOver on buttons nobody can
        // see. The action runs only when the copy crosses the fade line, so
        // scrolling still costs no per-frame state change.
        .allowsHitTesting(!copyHidden)
        .accessibilityHidden(copyHidden)
        .onGeometryChange(for: Bool.self) { [copyFadeLine, space = Self.coordinateSpaceName] proxy in
            AppleHomePhoneHeroLayout.copyIsHidden(
                copyTop: proxy.frame(in: .scrollView).minY,
                restingTop: proxy.frame(in: .named(space)).minY,
                fadeLine: copyFadeLine)
        } action: { hidden in
            copyHidden = hidden
        }
        // Read from the copy's own place in the scroll view, so scrolling
        // costs no state change and no body pass. The hero starts at the top
        // edge of the screen, so where the copy sits inside it is where it
        // rests on screen before any scroll.
        .visualEffect { [copyFadeLine, space = Self.coordinateSpaceName] content, proxy in
            content.opacity(AppleHomePhoneHeroLayout.copyOpacity(
                copyTop: proxy.frame(in: .scrollView).minY,
                restingTop: proxy.frame(in: .named(space)).minY,
                fadeLine: copyFadeLine))
        }
        .padding(.horizontal, 20)
        // Room for the carousel's page dots, which sit over the art.
        .padding(.bottom, AppleHomePhoneHeroLayout.copyBottomInset)
        .frame(maxWidth: .infinity)
        .frame(minHeight: artHeight, alignment: .bottom)
        .background(alignment: .top) {
            stage
                .frame(maxWidth: .infinity)
                .frame(height: artHeight)
                .clipped()
                .onPreferenceChange(AppleHomeHeroTrailerStateKey.self) { state in
                    videoIsShowing = state.isOnScreen
                }
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { artWidth = $0 }
                .overlay {
                    AppleHomePhoneHeroFade(scrim: scrim)
                        .allowsHitTesting(false)
                        .animation(.easeInOut(duration: 0.4), value: scrim)
                }
        }
        .background(Color.black)
        .coordinateSpace(.named(Self.coordinateSpaceName))
        .accessibilityElement(children: .contain)
    }

    private static var coordinateSpaceName: String { "AppleHomePhoneHero" }

    /// The wordmark when it has drawn, otherwise the name in black-weight
    /// capitals — while it loads, when it fails, when there is none, and over
    /// any art (`AppleHeroTitlePolicy`). The page never shows no title.
    private var title: some View {
        AppleHeroTitleLockup(pageID: item.id, wordmark: wordmark, alignment: .center) { url, onLoadResult in
            AppleTrimmedTitleLogo(url: url, alignment: .center, onLoadResult: onLoadResult)
                .frame(maxWidth: 280)
                .frame(height: dynamicTypeSize.isAccessibilitySize ? 120 : 96)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(item.name)
                .accessibilityAddTraits(.isHeader)
        } name: {
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
        }
    }
}
