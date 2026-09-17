import SwiftUI

public enum AppleDesignTokens {
    
    // MARK: - Colors
    public static let background = Color.black
    public static let surface = Color(white: 0.11) // #1C1C1E
    public static let textPrimary = Color.white
    public static let textSecondary = Color.white.opacity(0.6)
    public static let brandAccent = Color(red: 1.0, green: 0.2, blue: 0.4) // #FF3366
    
    #if os(visionOS)
    public static let minimumActionSize: CGFloat = 60
    public static var scrollIndicatorVisibility: ScrollIndicatorVisibility { .never }
    #else
    public static let minimumActionSize: CGFloat = 44
    public static var scrollIndicatorVisibility: ScrollIndicatorVisibility { .hidden }
    #endif

    // MARK: - Spacing & Corner Radii
    public static let spacingSmall: CGFloat = 8
    public static let spacingMedium: CGFloat = 16
    public static let spacingLarge: CGFloat = 24
    public static let spacingExtraLarge: CGFloat = 32
    
    public static let cornerRadiusCard: CGFloat = 12
    public static let cornerRadiusModal: CGFloat = 16
    
    // MARK: - Card Sizes
    public static let cardSizePhone = CGSize(width: 100, height: 150)
    public static let cardSizeTablet = CGSize(width: 150, height: 225)
    public static let cardSizeTV = CGSize(width: 300, height: 450)
    
    // MARK: - Typography
    public static let fontLargeTitle = Font.system(size: 34, weight: .bold)
    public static let fontTitle1 = Font.system(size: 28, weight: .bold)
    public static let fontTitle2 = Font.system(size: 22, weight: .bold)
    public static let fontHeadline = Font.system(size: 17, weight: .semibold)
    public static let fontBody = Font.system(size: 17, weight: .regular)
    public static let fontSubheadline = Font.system(size: 15, weight: .regular)
    public static let fontCaption = Font.system(size: 12, weight: .medium)
}

public struct PrimaryPillButtonStyle: ButtonStyle {
    public init() {}
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AppleDesignTokens.fontHeadline)
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            #if os(visionOS)
            .frame(minWidth: 60, minHeight: 60)
            .hoverEffect(.highlight)
            #endif
            .background(Color.white)
            .foregroundColor(.black)
            .clipShape(Capsule())
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
    }
}

public struct SecondaryPillButtonStyle: ButtonStyle {
    public init() {}
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AppleDesignTokens.fontHeadline)
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            #if os(visionOS)
            .frame(minWidth: 60, minHeight: 60)
            .hoverEffect(.highlight)
            #endif
            .background(Color(white: 0.2))
            .foregroundColor(.white)
            .clipShape(Capsule())
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
    }
}

/// Settings and setup content keeps the compact iPhone form treatment while
/// staying readable on iPad landscape instead of stretching edge to edge.
public struct AppleSettingsContentModifier: ViewModifier {
    public init() {}

    public func body(content: Content) -> some View {
        #if os(visionOS)
        content
            .environment(\.defaultMinListRowHeight, 60)
            .controlSize(.large)
            .scrollIndicators(AppleDesignTokens.scrollIndicatorVisibility)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        #elseif os(iOS)
        content
            .listStyle(.insetGrouped)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        #elseif os(tvOS)
        // 560 pt is a phone column. Centred on a 1920 pt television it left the
        // page title stranded at the safe inset while the rows floated in the
        // middle, and it wrapped ordinary values mid-word ("opensubtitles-
        // v3.strem.io", "Sep 13, 2026 at 10:49 PM"). The form column is the one
        // the tvOS settings metrics already define, left-aligned under the
        // title like the Add Live TV form (owner review 2026-09-14).
        content
            .frame(maxWidth: AppleTVSettingsMetrics.standard.formColumnWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            // The root view no longer tints tvOS white (rework plan task 3);
            // toggles and text buttons inside settings forms keep an explicit
            // white here so nothing in a form reads as the default blue.
            .tint(.white)
        #else
        content
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        #endif
    }
}

public extension View {
    func appleSettingsContent() -> some View {
        modifier(AppleSettingsContentModifier())
    }
}

/// Titles every settings page. On tvOS a `.navigationTitle` is drawn over the
/// page and only insets the scroll view's *content*, so the first row sits
/// under the title and the rest scroll up behind it; a `TVPageHeader`
/// (Title 3, 48 pt, at the 80 pt safe-zone inset) is placed above the rows
/// instead, so content always begins below it (owner bug U1).
public struct AppleSettingsPageTitleModifier: ViewModifier {
    private let title: String

    public init(title: String) {
        self.title = title
    }

    public func body(content: Content) -> some View {
        #if os(tvOS)
        VStack(alignment: .leading, spacing: 0) {
            TVPageHeader(title: title)
            content
        }
        #else
        content
            .navigationTitle(title)
        #endif
    }
}

public extension View {
    /// Titles a page that lays its own content out, without the settings
    /// column width.
    /// Every settings page routes its title through here, so tracing it once
    /// traces all of them — no page can be added later and silently go
    /// unrecorded.
    func appleSettingsPageTitle(_ title: String) -> some View {
        modifier(AppleSettingsPageTitleModifier(title: title))
            .appleTraceScreen("settings/\(title)")
    }

    /// Applies the settings layout and the page title together, so no settings
    /// page can reintroduce the tvOS title overlap.
    func appleSettingsPage(_ title: String) -> some View {
        appleSettingsContent()
            .appleSettingsPageTitle(title)
    }
}

/// The intentionally minimal empty state used when a source-backed tab has no
/// content. It contains one title and one action, with no explanatory copy.
public struct AppleSourceEmptyState: View {
    public let title: String
    public let actionTitle: String
    public let action: () -> Void

    public init(title: String, actionTitle: String, action: @escaping () -> Void) {
        self.title = title
        self.actionTitle = actionTitle
        self.action = action
    }

    public var body: some View {
        VStack(spacing: 16) {
            Text(title)
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)
            Button(actionTitle, action: action)
                .buttonStyle(.brandPrimary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(16)
    }
}

/// What a source-backed tab shows while its sources are still being read: one
/// centred spinner, no copy. The Library scan takes seconds over SMB, and the
/// tab has to look like it is working during them.
public struct AppleSourceLoadingState: View {
    public init() {}

    public var body: some View {
        ProgressView()
            .progressViewStyle(.circular)
            .tint(.white)
            .controlSize(.large)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(16)
            .accessibilityLabel("Loading")
    }
}

public extension View {
    /// Centres a placeholder in the scroll viewport instead of in its own box.
    ///
    /// Inside a scroll view the stack is vertically unbounded, so the
    /// `maxHeight: .infinity` these placeholders carry resolves to their own
    /// intrinsic height — a spinner becomes a speck clipped into the leading
    /// safe-area corner, which is all the Library tab drew for the first
    /// seconds after a cold launch (owner: "GUI with no content needs work",
    /// 2026-09-15). `size` is the enclosing scroll view's measured size.
    func appleCentredInViewport(_ size: CGSize) -> some View {
        frame(maxWidth: .infinity)
            .frame(minHeight: max(0, size.height - 32))
    }
}
// Done / hooks needed:
// - Codex to adopt `AppleDesignTokens`, `PrimaryPillButtonStyle`, and `SecondaryPillButtonStyle` in UI components

public extension View {
    @ViewBuilder
    func appleVisionHover() -> some View {
        #if os(visionOS)
        self.hoverEffect(.highlight)
        #else
        self
        #endif
    }
}

public extension View {
    @ViewBuilder
    func appleVisionActionTarget() -> some View {
        #if os(visionOS)
        self.frame(minWidth: 60, minHeight: 60)
            .contentShape(.rect(cornerRadius: 12))
            .hoverEffect(.highlight)
        #else
        self
        #endif
    }
}
