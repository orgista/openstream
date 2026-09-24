import SwiftUI

public enum AppleDesignTokens {
    
    // MARK: - Colors
    public static let background = Color.black
    public static let surface = Color(white: 0.11) // #1C1C1E
    public static let textPrimary = Color.white
    public static let textSecondary = Color.white.opacity(0.6)
    public static let brandAccent = Color(red: 1.0, green: 0.2, blue: 0.4) // #FF3366
    /// Channel health dots only: reachable but not playable, and offline.
    public static let healthAmber = Color(red: 1.0, green: 0.7, blue: 0.0) // #FFB300
    public static let healthRed = Color(red: 1.0, green: 0.27, blue: 0.23) // #FF453A

    #if os(visionOS)
    public static let minimumActionSize: CGFloat = 60
    #else
    public static let minimumActionSize: CGFloat = 44
    #endif
    /// The dark translucent circle behind a title page's back chevron, as the
    /// Apple TV app draws it; the tap target around it stays 44 pt.
    public static let backButtonCircleSide: CGFloat = 36

    /// The owner's "no scroll indicators" rule.
    ///
    /// `.never` on macOS, not `.hidden`. The two are not the same thing:
    /// `.hidden` asks the platform to hide the indicators but lets it show
    /// them anyway, and macOS does — with "Show scroll bars: Always" set, or
    /// simply as legacy scrollbars, which is what put a 1 px light track down
    /// the right edge of every settings pane (measured rgb(52,52,52) against
    /// the rgb(40,40,40) ground, 2026-09-21). `.never` is the only value that
    /// holds on this platform.
    #if os(visionOS) || os(macOS)
    public static var scrollIndicatorVisibility: ScrollIndicatorVisibility { .never }
    #else
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
        // No width cap. Wrapping the list in a fixed frame stops it being the
        // scroll view the navigation bar tracks, and the bar then keeps the
        // large title expanded while the list lays its own content out from the
        // top of that frame — which is why "RADARR" was drawn *underneath*
        // "Radarr & Sonarr" on the phone (measured 2026-09-17). The same cap was
        // also what centred the list in a 560 pt column on iPad while the large
        // title stayed flush left. tvOS moved off 560 for the same reason: it is
        // a phone column, and a phone does not need it.
        content
            .listStyle(.insetGrouped)
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
            // No `.brandSwitch` here: Apple TV draws a Toggle as a row with an
            // "On"/"Off" label rather than a switch, and the accent tint painted
            // the row *text* pink (seen on the Privacy pane, 2026-09-17).
        #elseif os(macOS)
        // This branch is the whole macOS Settings bug, and it is one bug, not
        // six (macOS sweep, 2026-09-21: About, Privacy, Backup, Metadata,
        // Storage, Watch Providers, Trakt, Add Catalog and Web Management all
        // failed, and they fail here).
        //
        // A macOS `Form` defaults to `.columns`: a grid that right-aligns
        // every label into a narrow centre column, draws a `NavigationLink` as
        // a bordered capsule button rather than a row with a chevron, and —
        // having no scroll view of its own — reports an *intrinsic* height. The
        // two `maxWidth` frames below cap the width and pass the height
        // proposal straight through, so the form stayed as short as its own
        // rows and SwiftUI placed that short block in a tall window from the
        // bottom up. A Trakt pane is two fields tall: at the 900x450 default it
        // sat entirely below the window edge and read as a blank page.
        //
        // `.grouped` is the style Apple's own macOS settings panes use — a
        // scrollable, top-anchored inset list whose navigation rows carry
        // chevrons — and it fills the height it is given, which is what fixes
        // the placement and the presentation together. Measured before and
        // after with an offscreen render: `.columns` reported 176 pt of height
        // for the root form at both 900x450 and 1280x860; `.grouped` reported
        // the full window and laid its first row 22 pt from the top.
        //
        // `maxHeight: .infinity` is set explicitly even though `.grouped`
        // expands on its own, because this modifier is also applied to the
        // `List`-based panes (Sources, Third-Party Notices) and to
        // `ScrollView`s, and the same "no height proposal" fault put those in
        // the middle of the window.
        content
            .formStyle(.grouped)
            .scrollIndicators(AppleDesignTokens.scrollIndicatorVisibility)
            // A `List`-based pane paints a ground two shades darker than the
            // window's, which drew the 720 pt column as a visible strip
            // (rgb(30,30,30) on rgb(40,40,40), measured 2026-09-21). Hiding it
            // puts every pane on the one window ground; a grouped `Form` keeps
            // its own row boxes either way, so nothing is lost.
            .scrollContentBackground(.hidden)
            .frame(maxWidth: AppleMacChromeMetrics.settingsColumnWidth, maxHeight: .infinity)
            .frame(maxWidth: .infinity)
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
        #elseif os(iOS)
        // Inline, like Apple's own Settings: every pushed pane there ("General",
        // "About", "Storage") carries an inline title, and only the root keeps a
        // large one. Ours kept the large title on pushed panes, and the first
        // section header was being drawn across it — "APPLE SERVICES" ghosting
        // through the white letters of "Privacy" on every pane with a header
        // (measured 2026-09-17).
        content
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
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
    /// The tab's own symbol over the title, as Search's empty state has its
    /// magnifying glass; without it Library and Live read as a bare line of
    /// text in the middle of a black page.
    public let systemImage: String?
    public let actionTitle: String?
    public let action: (() -> Void)?

    public init(title: String, systemImage: String? = nil, actionTitle: String, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.actionTitle = actionTitle
        self.action = action
    }

    /// Title only. For a dead end an action cannot open: a button that runs and
    /// leaves the screen exactly as it was reads as a broken button.
    public init(title: String) {
        self.title = title
        self.systemImage = nil
        self.actionTitle = nil
        self.action = nil
    }

    public var body: some View {
        VStack(spacing: 16) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.largeTitle)
                    .imageScale(.large)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            Text(title)
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.brandPrimary)
            }
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
    /// Tells a pointer or a gaze that this thing can be clicked.
    ///
    /// Was `appleVisionHover()` and visionOS-only. macOS had no affordance of
    /// any kind: every poster, pill and shelf card kept the plain arrow
    /// cursor, so on the Mac nothing on Discover read as clickable until it
    /// was clicked (macOS sweep, 2026-09-21). `hoverEffect` does not exist on
    /// macOS; the Mac's own signal for the same thing is the link cursor.
    @ViewBuilder
    func appleHoverAffordance() -> some View {
        #if os(visionOS)
        self.hoverEffect(.highlight)
        #elseif os(macOS)
        self.pointerStyle(.link)
        #else
        self
        #endif
    }
}

public extension View {
    /// Draws a `Menu` as the bare label it was written as.
    ///
    /// A macOS `Menu` defaults to a bordered pull-down button with a menu
    /// indicator beside it, so every glyph menu in this app was drawn as a
    /// grey capsule with a chevron: the player's ellipsis, SharePlay and
    /// captions buttons, and — worst of it — Rate on the title page, whose
    /// icon-over-label was also flattened side by side inside 155 pt of
    /// chrome around a 44 pt action (measured 2026-09-21). Every other
    /// platform draws these as the plain glyph they are, and
    /// `.buttonStyle(.plain)` is what restores that here; the borderless
    /// *menu* style drops the border but still lays the label out
    /// horizontally.
    @ViewBuilder
    func appleBareMenu() -> some View {
        #if os(macOS)
        self.buttonStyle(.plain).menuIndicator(.hidden)
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

/// How long a control has to look busy for the press to have visibly happened.
///
/// A Refresh over a playlist already on disk, or a retry that fails on a
/// simulator with no network, is finished inside one frame: the spinner is put
/// up and taken down between two displays and the viewer sees a control that
/// did nothing (button crawl, 2026-09-19). The same floor UIKit's refresh
/// control keeps for its own animation is kept here, in one place, so every
/// busy control in the app agrees on it.
public enum AppleProgressVisibility {
    public static let minimum: Duration = .milliseconds(600)

    /// What is left of the floor after work that took `elapsed` — zero once
    /// the work itself has been on screen long enough.
    public static func remaining(after elapsed: Duration) -> Duration {
        elapsed >= minimum ? .zero : minimum - elapsed
    }

    /// The pause a caller should take before it stops looking busy.
    public static func remaining(since start: ContinuousClock.Instant,
                                 now: ContinuousClock.Instant = .now) -> Duration {
        remaining(after: start.duration(to: now))
    }
}
