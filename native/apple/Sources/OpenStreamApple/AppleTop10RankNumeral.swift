import SwiftUI

struct AppleTop10RankNumeral: View {
    let rank: Int
    @ScaledMetric(relativeTo: .largeTitle) private var numeralSize = 72.0

    var body: some View {
        Text(rank, format: .number)
            .font(.system(size: numeralSize, weight: .black))
            .foregroundStyle(.gray)
            .fixedSize()
            .accessibilityHidden(true)
    }
}
