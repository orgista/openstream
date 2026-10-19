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
                    // Only in the tree once the hero has scrolled away: an
                    // opacity-0 title still answers accessibility queries.
                    if heroIsOffscreen {
                        Text(title)
                            .font(.headline)
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .padding(.horizontal, barHeight + horizontalInset)
                            .transition(.opacity)
                            .accessibilityAddTraits(.isHeader)
                            .accessibilityIdentifier("detail.compact-title")
                            .allowsHitTesting(false)
                    }
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
        } else {
            backControl.appleTitleBarButtonBacking()
        }
    }

    private var backControl: some View {
        Button("Back", systemImage: "chevron.left", action: onBack)
            .labelStyle(.iconOnly)
            .foregroundStyle(.white)
            .keyboardShortcut("[", modifiers: .command)
            .accessibilityIdentifier("detail.back")
    }
}
#endif
