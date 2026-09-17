import SwiftUI

/// Primary action button for OpenStream: a white fill with a black label,
/// matching the launch screen, the store assets, and the web portal button.
///
/// It replaces `.borderedProminent`, which — under the app's white brand tint —
/// renders a white label on the white fill (the unreadable "white on white"
/// the owner reported on the Live tab's Open Settings button). The brand is
/// monochrome, so the accent is white and the primary button inverts to keep
/// contrast; nothing in the app reads as the iOS default blue.
public struct AppleBrandPrimaryButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        StyledBody(configuration: configuration)
    }

    private struct StyledBody: View {
        @Environment(\.isFocused) private var isFocused
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        let configuration: ButtonStyleConfiguration

        var body: some View {
            configuration.label
                .font(.body.weight(.semibold))
                .foregroundStyle(.black)
                .padding(.horizontal, 18)
                .padding(.vertical, 11)
                .frame(minHeight: AppleDesignTokens.minimumActionSize)
                .background(.white, in: .capsule)
                .overlay {
                    Capsule()
                        .stroke(.white.opacity(isFocused ? 0.95 : 0), lineWidth: 4)
                        .padding(-7)
                }
                .shadow(color: .white.opacity(isFocused ? 0.42 : 0), radius: 16)
                .scaleEffect(reduceMotion ? 1 : (isFocused ? 1.06 : 1))
                .opacity(configuration.isPressed ? 0.7 : 1)
                .contentShape(.capsule)
                .appleVisionHover()
                .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: isFocused)
        }
    }
}

public extension ButtonStyle where Self == AppleBrandPrimaryButtonStyle {
    static var brandPrimary: AppleBrandPrimaryButtonStyle { AppleBrandPrimaryButtonStyle() }
}

/// Secondary actions keep a dark translucent surface and white label so the
/// app's monochrome tint cannot produce white-on-white controls on tvOS.
public struct AppleBrandSecondaryButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        StyledBody(configuration: configuration)
    }

    private struct StyledBody: View {
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.isFocused) private var isFocused
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        let configuration: ButtonStyleConfiguration

        var body: some View {
            configuration.label
                .font(.body.weight(.semibold))
                .foregroundStyle(.white.opacity(isEnabled ? 1 : 0.48))
                .padding(.horizontal, 18)
                .padding(.vertical, 11)
                .frame(minHeight: AppleDesignTokens.minimumActionSize)
                .background(
                    isFocused ? Color(white: 0.28) : Color(white: 0.14),
                    in: .capsule
                )
                .overlay {
                    Capsule()
                        .stroke(.white.opacity(isFocused ? 0.96 : 0.34), lineWidth: isFocused ? 4 : 1)
                        .padding(isFocused ? -7 : 0)
                }
                .shadow(color: .white.opacity(isFocused ? 0.34 : 0), radius: 14)
                .scaleEffect(reduceMotion ? 1 : (isFocused ? 1.06 : 1))
                .opacity(configuration.isPressed ? 0.72 : 1)
                .contentShape(.capsule)
                .appleVisionHover()
                .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: isFocused)
        }
    }
}

public extension ButtonStyle where Self == AppleBrandSecondaryButtonStyle {
    static var brandSecondary: AppleBrandSecondaryButtonStyle { AppleBrandSecondaryButtonStyle() }
}

/// Keeps the system tvOS focus fill readable for controls that use the
/// platform's row treatment. tvOS applies the light focus surface outside the
/// button label, while the app's global white tint otherwise leaves labels and
/// SF Symbol icons white on white.
public struct AppleTVReadableFocusModifier: ViewModifier {
    public init() {}

    public func body(content: Content) -> some View {
        // Stock tvOS list rows already lift and brighten on focus; no inner
        // button chrome (a bordered white capsule read as a box in a box).
        content
    }
}

public struct AppleTVNavigationLabel: View {
    private let title: String
    /// Nil for a row in a pane whose other rows carry no glyph: the Playback
    /// pane had five value rows without one and two navigation rows with one,
    /// which read as an accident (review 2026-09-14, U6).
    private let systemImage: String?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// The icon slot has to grow with the type: an SF Symbol scales with
    /// Dynamic Type, so a fixed slot is overrun by its own glyph at
    /// accessibility sizes and the symbol lands on top of the title.
    @ScaledMetric(relativeTo: .body) private var iconSlot: CGFloat =
        AppleTVNavigationLabel.compactIconSlotWidth

    public init(_ title: String, systemImage: String? = nil) {
        self.title = title
        self.systemImage = systemImage
    }

    public var body: some View {
        #if os(tvOS)
        // A stock `Label` in a tvOS list sizes its icon column to the font, so
        // wide symbols (folder.badge.plus, dot.radiowaves.left.and.right,
        // network) run straight into the title. A fixed slot keeps every
        // glyph clear of the text and starts all titles on the same column.
        HStack(spacing: AppleTVNavigationLabel.iconSpacing) {
            if let systemImage {
                Image(systemName: systemImage)
                    .foregroundStyle(.primary)
                    .frame(width: AppleTVNavigationLabel.iconSlotWidth)
                    .accessibilityHidden(true)
            }
            Text(title)
        }
        .accessibilityElement(children: .combine)
        #else
        if let systemImage {
            if AppleTVNavigationLabel.usesFixedIconColumn(for: dynamicTypeSize) {
                // A stock `Label` re-flows at accessibility sizes and lets the
                // wrapped line escape the title column: "Channel Manager" put
                // "Manager" on a second line starting at the row's leading
                // edge, underneath the glyph. The fixed slot is the same thing
                // the tvOS branch above does, and for the same reason.
                HStack(alignment: .firstTextBaseline,
                       spacing: AppleTVNavigationLabel.iconSpacing) {
                    Image(systemName: systemImage)
                        .foregroundStyle(.primary)
                        .frame(width: iconSlot, alignment: .leading)
                        .accessibilityHidden(true)
                    Text(title)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .accessibilityElement(children: .combine)
            } else {
                Label {
                    Text(title)
                } icon: {
                    Image(systemName: systemImage)
                        .foregroundStyle(.primary)
                }
            }
        } else {
            Text(title)
        }
        #endif
    }

    /// Whether to take the icon column over from `Label`.
    ///
    /// Only at accessibility sizes: at ordinary sizes the stock label is
    /// correct and matches every other iOS settings screen, so it is left
    /// alone.
    public static func usesFixedIconColumn(for size: DynamicTypeSize) -> Bool {
        size.isAccessibilitySize
    }

    /// Widest tvOS body-size symbol in the settings rows is ~42 pt.
    public static let iconSlotWidth: CGFloat = 48
    public static let iconSpacing: CGFloat = 12
    /// The phone's glyphs are drawn at body size, not tvOS's, so the slot that
    /// keeps titles on one column there is far wider than this needs.
    public static let compactIconSlotWidth: CGFloat = 30
}

public extension View {
    func appleTVReadableFocus() -> some View {
        modifier(AppleTVReadableFocusModifier())
    }
}
