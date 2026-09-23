import SwiftUI

/// The iPhone hero's one fade (the approved billboard fade, DESIGN-SPEC
/// 2026-09-22): the art stays clear through the top fifth, darkens under the
/// title, and is solid black from 65 % down, where the copy and the buttons sit.
struct AppleHomePhoneHeroFade: View {
    var body: some View {
        LinearGradient(
            stops: [
                .init(color: .clear, location: 0),
                .init(color: .clear, location: 0.18),
                .init(color: .black.opacity(0.55), location: 0.42),
                .init(color: .black, location: 0.65),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .accessibilityHidden(true)
    }
}
