import SwiftUI

struct AppleTop10RankNumeral: View {
    let rank: Int
    @ScaledMetric(relativeTo: .largeTitle) private var numeralSize = 120.0

    var body: some View {
        Canvas { context, size in
            let text = Text("\(rank)").font(.system(size: numeralSize, weight: .black, design: .rounded))
            let glyph = context.resolve(text.foregroundStyle(.primary))
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            context.drawLayer { outline in
                for x in -1...1 {
                    for y in -1...1 where x != 0 || y != 0 {
                        outline.draw(glyph, at: CGPoint(x: center.x + CGFloat(x) * 2, y: center.y + CGFloat(y) * 2))
                    }
                }
                outline.blendMode = .destinationOut
                outline.draw(glyph, at: center)
            }
        }
        .frame(width: numeralSize * (rank == 10 ? 1.25 : 0.72), height: numeralSize * 1.3)
        .accessibilityHidden(true)
    }
}
