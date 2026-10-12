import SwiftUI

struct AppleDiscoverLoadingRail: View {
    let landscape: Bool
    let rowStyle: AppleDiscoverRowStyle?

    private var cardWidth: CGFloat {
        #if os(tvOS)
        landscape ? 480 : 230
        #else
        landscape ? (rowStyle?.stillWidth ?? 260) : (rowStyle?.posterWidth ?? 150)
        #endif
    }

    private var headingHeight: CGFloat {
        #if os(tvOS)
        46
        #else
        29
        #endif
    }

    var body: some View {
        AppleMediaShelf(title: "", header: AnyView(
            RoundedRectangle(cornerRadius: 4)
                .fill(AppleDesignTokens.surface)
                .frame(width: cardWidth, height: headingHeight)
        )) {
            ForEach(0..<8) { _ in
                VStack(alignment: .leading, spacing: 8) {
                    RoundedRectangle(cornerRadius: rowStyle == nil ? 18 : 12)
                        .fill(AppleDesignTokens.surface)
                        .frame(width: cardWidth, height: cardWidth * (landscape ? 9 / 16 : 1.5))
                    #if os(tvOS)
                    if landscape {
                        Rectangle().fill(AppleDesignTokens.surface).frame(width: cardWidth * 0.65, height: 29)
                    }
                    #else
                    Rectangle().fill(AppleDesignTokens.surface).frame(width: cardWidth * 0.65, height: 20)
                    #endif
                }
            }
        }
    }
}
