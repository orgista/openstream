import SwiftUI

/// Static surface shapes occupy the same hero slot and rail gutters as content.
/// No timers or animation, including when Reduce Motion is enabled.
struct AppleDiscoverLoadingContent: View {
    let presentation: AppleHomePresentationPolicy.Hero
    let viewport: CGSize
    let phoneLayout: AppleHomePhoneHeroLayout
    let wideLayout: AppleMacHeroLayout
    let rowStyle: AppleDiscoverRowStyle?

    private var heroHeight: CGFloat {
        switch presentation {
        case .tv: AppleTVBillboardMetrics.artHeight
        case .phone: phoneLayout.artHeight
        case .mac, .pad: wideLayout.height
        case .rotating:
            #if os(tvOS)
            AppleTVBillboardMetrics.artHeight
            #else
            AppleFeaturedHeroMetrics.artHeight(viewport: viewport)
            #endif
        }
    }

    private var topOverlap: CGFloat {
        switch presentation {
        case .phone: phoneLayout.topOverlap
        case .mac, .pad: wideLayout.topOverlap
        default: 0
        }
    }

    private var bottomOverlap: CGFloat {
        switch presentation {
        case .tv: AppleTVBillboardMetrics.rowOverlap
        case .phone: AppleHomePhoneHeroLayout.trailingOverlap
        default: 0
        }
    }

    var body: some View {
        Rectangle()
            .fill(AppleDesignTokens.surface)
            .frame(maxWidth: .infinity)
            .frame(height: heroHeight)
            .padding(.top, -topOverlap)
            .padding(.bottom, -bottomOverlap)
            #if os(tvOS)
            .padding(.horizontal, -AppleTVChromeMetrics.horizontalSafeInset)
            #elseif !os(macOS)
            .padding(.horizontal, presentation == .rotating ? 16 : 0)
            #endif
        ForEach(0..<3) { index in
            AppleDiscoverLoadingRail(landscape: index == 0, rowStyle: rowStyle)
        }
    }
}
