import SwiftUI

struct AppleMediaShelf<Content: View>: View {
    let title: String
    /// Optional control on the header line's trailing end (the Library's
    /// Sort menu on tvOS), so nothing has to float over the billboard.
    var accessory: AnyView? = nil
    var onOpen: (() -> Void)? = nil
    var headingIdentifier: String = ""
    @ViewBuilder var content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: titleSpacing) {
            HStack(alignment: .center) {
                if let onOpen {
                    Button(action: onOpen) {
                        HStack(spacing: 8) {
                            Text(title).font(titleFont)
                            Image(systemName: "chevron.right")
                                .font(.headline.bold())
                        }
                        .multilineTextAlignment(.leading)
                        .frame(minHeight: 44, alignment: .leading)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.primary)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier(headingIdentifier)
                } else {
                    Text(title).font(titleFont).accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier(headingIdentifier)
                }
                if let accessory {
                    Spacer(minLength: 16)
                    accessory
                }
            }
            .padding(.horizontal, horizontalInset)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: cardGap, content: content)
                    .padding(.horizontal, horizontalInset).padding(.vertical, verticalBleed)
            }.scrollIndicators(AppleDesignTokens.scrollIndicatorVisibility)
        }.appleCatalogFocusSection()
    }

    // tvOS retains its safe-area gutter and room for the focus lift.
    #if os(tvOS)
    private var titleFont: Font { .title.bold() }
    private var titleSpacing: CGFloat { AppleTVBillboardMetrics.rowTitleSpacing }
    private var horizontalInset: CGFloat { AppleTVBillboardMetrics.rowHorizontalInset }
    private var cardGap: CGFloat { AppleTVBillboardMetrics.cardGap }
    private var verticalBleed: CGFloat { AppleTVBillboardMetrics.rowVerticalBleed }
    #else
    private var titleFont: Font { .title.bold() }
    private var titleSpacing: CGFloat { 12 }
    private var horizontalInset: CGFloat { 16 }
    private var cardGap: CGFloat { 8 }
    private var verticalBleed: CGFloat { 4 }
    #endif
}

struct AppleFeaturedHero<Actions: View>: View {
    let item: AppleCatalogItem
    let viewportSize: CGSize
    /// The title's wordmark, when the preview-assets cache has one. Every
    /// platform's hero uses it: the lockup over the art is the shape the owner
    /// asked for on the iPad as well as the Apple TV (2026-09-18 references).
    var wordmark: URL? = nil
    /// How many heroes the screen rotates through, and which is showing. One
    /// (or fewer) draws no indicator: there is nothing to cycle to.
    var rotationCount: Int = 0
    var rotationIndex: Int = 0
    /// What fills the art frame. Discover passes a stage that can swap the
    /// still for an inline trailer; Library passes nothing and gets the still.
    /// Either way the frame, the one fade and the copy block are the same.
    var stage: AnyView? = nil
    @ViewBuilder var actions: Actions
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    var body: some View {
        #if os(tvOS)
        AppleTVBillboard(item: item, wordmark: wordmark, rotationCount: rotationCount,
                         rotationIndex: rotationIndex, stage: stage) { actions }
        #else
        legacyHero
        #endif
    }

    #if !os(tvOS)
    private var legacyHero: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 0) {
                    art
                        .frame(maxWidth: .infinity)
                        .frame(height: AppleFeaturedHeroMetrics.accessibilityArtHeight)
                        .clipped()

                    VStack(alignment: .leading, spacing: 14) {
                        Text(item.name)
                            .font(.title2.bold())
                            .fixedSize(horizontal: false, vertical: true)
                            .shadow(color: .black.opacity(0.6), radius: 6, y: 1)
                            .accessibilityAddTraits(.isHeader)
                        if let summary = item.summary, !summary.isEmpty {
                            Text(summary)
                                .foregroundStyle(.secondary)
                                .lineLimit(AppleHeroSummaryLineLimit.lines(for: dynamicTypeSize))
                                .fixedSize(horizontal: false, vertical: true)
                                .shadow(color: .black.opacity(0.6), radius: 6, y: 1)
                        }
                        actions
                        pageIndicator
                    }
                    .padding(20)
                }
                .background(Color(white: 0.10))
            } else {
                // The copy is an overlay on the art, not a sibling in a ZStack:
                // an overlay is offered its host's size and can never widen it.
                art
                    .frame(maxWidth: .infinity)
                    .frame(height: featuredHeight)
                    .clipped()
                    // The same single bottom-to-black fade the owner approved
                    // for the Apple TV billboard (X2), for the same reason: a
                    // 6 pt text shadow is not enough over bright busy art, and
                    // "Remarkably Bright Creatures" over a lit aquarium was
                    // unreadable on iPad (2026-09-15). One fade, nowhere else.
                    .overlay {
                        LinearGradient(
                            colors: [.clear, .black.opacity(0.85)],
                            startPoint: .init(x: 0.5, y: AppleTVBillboardMetrics.fadeStartFraction),
                            endPoint: .bottom
                        )
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                    }
                    .overlay(alignment: .bottomLeading) {
                        VStack(alignment: .leading, spacing: 10) {
                            titleTreatment
                            if let metadataLine {
                                Text(metadataLine)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(.white.opacity(0.75))
                                    .lineLimit(1)
                                    .shadow(color: .black.opacity(0.6), radius: 6, y: 1)
                            }
                            if let summary = item.summary, !summary.isEmpty {
                                // White at 90 %, the same as the Apple TV
                                // billboard, not `.secondary`: a hierarchical
                                // grey over bright art disappears, and "TOXIC"
                                // sits on a white backdrop (2026-09-20). The one
                                // approved fade covers the bottom of the frame;
                                // nothing else may be dimmed, so the type
                                // carries it.
                                Text(summary)
                                    .foregroundStyle(.white.opacity(0.9))
                                    .lineLimit(2)
                                    .frame(maxWidth: min(700, copyColumnWidth), alignment: .leading)
                                    .shadow(color: .black.opacity(0.6), radius: 6, y: 1)
                            }
                            actions
                            pageIndicator
                        }
                        // Measured, not inferred. A `maxWidth` only clamps when
                        // the proposal is finite, and the copy column inside the
                        // hero was being sized against an unbounded proposal:
                        // the synopsis took its full 700 pt on a 393 pt iPhone
                        // and pushed Details past the right edge (2026-09-20).
                        // The hero's own width is known, so use it.
                        .frame(width: copyColumnWidth, alignment: .leading)
                        .padding(24)
                    }
            }
        }
        .clipShape(.rect(cornerRadius: 18))
        .accessibilityElement(children: .contain)
    }

    /// The inline trailer when Discover supplies one, otherwise the still.
    @ViewBuilder
    private var art: some View {
        if let stage {
            stage
        } else {
            AppleCatalogArtwork(url: item.backgroundURL ?? item.posterURL)
        }
    }

    /// The wordmark lockup when it has drawn, otherwise the name — never
    /// nothing, as on the Apple TV billboard (`AppleHeroTitlePolicy`).
    private var titleTreatment: some View {
        AppleHeroTitleLockup(pageID: item.id, wordmark: wordmark) { url, onLoadResult in
            // A definite height, not `maxHeight`: the wordmark is drawn inside
            // a GeometryReader, and in a scroll view an upper bound leaves the
            // height proposal unresolved, which collapsed the mark to a few
            // illegible points (2026-09-20).
            AppleTrimmedTitleLogo(url: url, alignment: .leading, onLoadResult: onLoadResult)
                // One view per wordmark: the logo view keeps its image while a
                // new URL loads, which left the last title's mark over the next
                // title's copy (iPad, 2026-09-22) — as on the Apple TV.
                .id(url)
                .frame(maxWidth: wordmarkWidth, alignment: .leading)
                .frame(height: wordmarkHeight)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(item.name)
                .accessibilityAddTraits(.isHeader)
        } name: {
            Text(item.name)
                .font(.largeTitle.bold())
                .lineLimit(2)
                .shadow(color: .black.opacity(0.6), radius: 6, y: 1)
                .accessibilityAddTraits(.isHeader)
        }
    }

    @ViewBuilder
    private var pageIndicator: some View {
        if rotationCount > 1 {
            AppleHomeHeroPageIndicator(count: rotationCount, index: rotationIndex)
                .padding(.top, 2)
        }
    }

    private var metadataLine: String? {
        AppleBillboardCopy.metadataLine(genres: item.genres, year: item.year, releaseInfo: item.releaseInfo)
    }

    private var wordmarkWidth: CGFloat {
        AppleFeaturedHeroMetrics.wordmarkSize(viewport: viewportSize).width
    }

    private var copyColumnWidth: CGFloat {
        AppleFeaturedHeroMetrics.copyColumnWidth(viewport: viewportSize)
    }

    private var wordmarkHeight: CGFloat {
        AppleFeaturedHeroMetrics.wordmarkSize(viewport: viewportSize).height
    }

    private var featuredHeight: CGFloat {
        AppleFeaturedHeroMetrics.artHeight(viewport: viewportSize)
    }
    #endif

}

struct AppleFeaturedActions: View {
    let viewportSize: CGSize
    /// Landscape on any device, so the phone keeps the fixed-size pills too.
    private var isLandscapeLayout: Bool {
        #if os(visionOS) || os(iOS)
        AppleDetailMetrics.isLandscapeLayout(viewport: viewportSize)
        #else
        false
        #endif
    }
    let onPlay: () -> Void
    let onDetails: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    var body: some View {
        #if os(tvOS)
        AppleTVBillboardActions(onPlay: onPlay, onDetails: onDetails)
        #else
        legacyBody
        #endif
    }

    #if !os(tvOS)
    @ViewBuilder
    private var legacyBody: some View {
        if isLandscapeLayout {
            HStack(spacing: AppleDetailMetrics.actionButtonGap) {
                Button(action: onPlay) {
                    AppleDetailActionButtonLabel(title: "Play", glyph: .systemImage("play.fill"), kind: .play,
                                                width: AppleDetailMetrics.landscapeIPadActionButtonWidth)
                }
                .accessibilityIdentifier("home.featured.play")
                Button(action: onDetails) {
                    AppleDetailActionButtonLabel(title: "Details", glyph: .systemImage("info.circle"), kind: .download,
                                                width: AppleDetailMetrics.landscapeIPadActionButtonWidth)
                }
                .accessibilityIdentifier("home.featured.details")
            }
            .buttonStyle(.plain)
        } else {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 12))
            : AnyLayout(HStackLayout(spacing: 12))
        // `nil` on the phone, where filling half the column is the right pill;
        // a fixed width on a tablet in portrait, where it was not.
        let buttonWidth = AppleDetailMetrics
            .featuredActionButtonWidth(portraitViewportWidth: viewportSize.width) ?? .infinity
        layout {
            Button(action: onPlay) {
                Label("Play", systemImage: "play.fill")
                    .frame(maxWidth: buttonWidth)
            }
            .buttonStyle(.brandPrimary)
            .accessibilityIdentifier("home.featured.play")

            Button(action: onDetails) {
                Label("Details", systemImage: "info.circle")
                    .frame(maxWidth: buttonWidth)
            }
            .buttonStyle(.brandSecondary)
            .accessibilityIdentifier("home.featured.details")
        }
        .controlSize(.large)
        .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    #endif

}
