#if os(iOS)
import SwiftUI

struct ApplePhoneTitlePageChrome: ViewModifier {
    let title: String
    let heroIsOffscreen: Bool
    let topInset: CGFloat
    let onBack: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let barHeight = AppleDesignTokens.minimumActionSize
    private let horizontalInset: CGFloat = 16

    func body(content: Content) -> some View {
        content
            .navigationBarBackButtonHidden(true)
            .toolbar(.hidden, for: .navigationBar)
            .overlay(alignment: .top) {
                LinearGradient(colors: [.black.opacity(0.65), .clear], startPoint: .top, endPoint: .bottom)
                    .frame(height: topInset + barHeight)
                    .offset(y: -topInset)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            .overlay(alignment: .top) {
                HStack {
                    backButton
                    Spacer(minLength: 0)
                }
                .overlay {
                    // Opacity, not a conditional: inserting the title re-laid out
                    // the page and the hero reader flipped `heroIsOffscreen` back,
                    // which looped layout (batch-1018g gate hang on iOS 18.6). The
                    // identifier is withheld while hidden so accessibility and the
                    // UI tests see no compact title at rest.
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .padding(.horizontal, barHeight + horizontalInset)
                        .opacity(heroIsOffscreen ? 1 : 0)
                        .accessibilityHidden(!heroIsOffscreen)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier(heroIsOffscreen ? "detail.compact-title" : "")
                        .allowsHitTesting(false)
                }
                .frame(height: barHeight)
                .padding(.horizontal, horizontalInset)
                .background {
                    Rectangle()
                        .fill(.bar)
                        .opacity(heroIsOffscreen ? 1 : 0)
                        .ignoresSafeArea(edges: .top)
                }
                .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: heroIsOffscreen)
            }
    }

    @ViewBuilder
    private var backButton: some View {
        if #available(iOS 26, *) {
            backControl
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                // The glass style sizes itself to the glyph (26.67 pt measured on
                // iOS 27); the 44 pt minimum and the identifier go on the styled
                // button so XCTest and fingers both find a 44 pt control (row 30).
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Circle())
                .accessibilityIdentifier("detail.back")
        } else {
            backControl.appleTitleBarButtonBacking()
        }
    }

    private var backControl: some View {
        Button(action: onBack) {
            Image(systemName: "chevron.left")
                .font(.body.weight(.semibold))
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .accessibilityLabel("Back")
        .foregroundStyle(.white)
        .keyboardShortcut("[", modifiers: .command)
        .accessibilityIdentifier("detail.back")
    }
}
#endif
