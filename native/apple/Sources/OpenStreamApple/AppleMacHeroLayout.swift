import CoreGraphics

/// Where the Mac's Discover hero draws, after the Apple TV app on the Mac and
/// the Figma "MacOS-OpenStream" frame (owner 2026-09-23: "make sure the bigger
/// apple tv style hero is on the macOS version as well"): art edge to edge
/// across the content, from the top of the Discover area under the toolbar,
/// `min(680, 75 % of the width)` tall and never more than 75 % of the window,
/// so the first row still peeks; the copy bottom-left in a 480 pt column; the
/// page dots bottom-centre; a round mute button top-right.
///
/// Pure, so the gate can check it without a window.
public struct AppleMacHeroLayout: Equatable, Sendable {
    /// The Discover content's width and the window's height.
    public var contentWidth: CGFloat
    public var windowHeight: CGFloat
    /// What the toolbar takes off the top (the scroll view's top content inset).
    public var topInset: CGFloat

    public init(contentWidth: CGFloat = 0, windowHeight: CGFloat = 0, topInset: CGFloat = 0) {
        self.contentWidth = contentWidth
        self.windowHeight = windowHeight
        self.topInset = topInset
    }

    public static let maximumHeight: CGFloat = 680
    public static let widthFraction: CGFloat = 0.75
    public static let windowFraction: CGFloat = 0.75
    /// Before the window has been measured, and never less than this.
    public static let minimumHeight: CGFloat = 360

    /// The copy column's inset from the leading edge: 24 pt in a narrow
    /// window, growing with the width to 48 pt by 1600 pt.
    public static let minimumHorizontalPadding: CGFloat = 24
    public static let maximumHorizontalPadding: CGFloat = 48
    public static let bottomPadding: CGFloat = 40
    public static let copyMaxWidth: CGFloat = 480
    public static let descriptionMaxWidth: CGFloat = 340
    /// Below this hero height the synopsis is left out rather than crowding
    /// the title and buttons.
    public static let descriptionMinimumHeight: CGFloat = 480

    public static let dotsBottomInset: CGFloat = 16
    public static let muteSide: CGFloat = 36
    public static let muteTopInset: CGFloat = 16
    public static let muteTrailingInset: CGFloat = 24
    public static let listButtonSide: CGFloat = 40
    /// One decode of the still at this size serves every window size, so a
    /// live resize never reloads it.
    public static let stillPixelDimension = 2_560
    /// The wordmark's slot. Fixed rather than scaled with the window for the
    /// same reason: the trimmed logo decodes at its slot's size.
    public static let wordmarkSize = CGSize(width: 400, height: 130)
    /// Discover's rows start 16 pt below the toolbar (`padding(.vertical)`);
    /// the hero is pulled up past that too.
    public static let stackTopPadding: CGFloat = 16

    /// The hero's full height, from the top of the Discover area.
    public var height: CGFloat {
        guard contentWidth > 0 else { return Self.minimumHeight }
        var target = min(Self.maximumHeight, contentWidth * Self.widthFraction)
        if windowHeight > 0 { target = min(target, windowHeight * Self.windowFraction) }
        return max(target, Self.minimumHeight)
    }

    public var horizontalPadding: CGFloat {
        let t = min(max((contentWidth - 900) / 700, 0), 1)
        return Self.minimumHorizontalPadding + (Self.maximumHorizontalPadding - Self.minimumHorizontalPadding) * t
    }

    /// The black-weight name drawn when there is no wordmark: 6 % of the
    /// width, between 36 and 72 pt.
    public var titleFontSize: CGFloat {
        min(max(contentWidth * 0.06, 36), 72)
    }

    public var showsDescription: Bool { height >= Self.descriptionMinimumHeight }

    /// How far the hero is pulled up so its art starts under the toolbar.
    public var topOverlap: CGFloat { topInset + Self.stackTopPadding }
}

/// The Mac hero's two fades, as the Figma draws them: black 85 % on the left
/// to clear at 70 % of the width, and black 90 % at the bottom to clear at
/// 40 % of the height (owner: "Follow the Figma" for gradients).
public enum AppleMacHeroFade {
    public struct Stop: Equatable, Sendable {
        public let location: CGFloat
        public let opacity: Double
    }

    /// Leading edge to trailing edge.
    public static let leading: [Stop] = [
        Stop(location: 0, opacity: 0.85),
        Stop(location: 0.3, opacity: 0.85),
        Stop(location: 0.7, opacity: 0),
    ]

    /// Bottom edge upwards.
    public static let bottom: [Stop] = [
        Stop(location: 0, opacity: 0.9),
        Stop(location: 0.4, opacity: 0),
    ]
}

/// The Mac hero's page dots, as the Figma draws them: 7 pt dots 8 pt apart,
/// the active page a 22 pt capsule that fills with the cycle's timer.
public enum AppleMacHeroPageDots {
    public static let activeWidth: CGFloat = 22
    public static let dotSize: CGFloat = 7
    public static let spacing: CGFloat = 8
    /// Each dot's click target, taller and wider than the dot.
    public static let hitSize: CGFloat = 20
    public static let inactiveOpacity: Double = 0.35

    public static func size(position: Int, index: Int, count: Int) -> CGSize {
        guard count > 0, (0 ..< count).contains(position) else { return .zero }
        return CGSize(width: position == index ? activeWidth : dotSize, height: dotSize)
    }
}

/// Turns a trackpad's horizontal two-finger swipe over the Mac hero into one
/// page change per gesture. Vertical scrolling is left to the page, and the
/// momentum that follows a swipe never turns a second page.
public struct AppleMacHeroSwipe: Equatable, Sendable {
    /// Horizontal travel, in points, that turns the page.
    public static let threshold: CGFloat = 60

    private var travel: CGFloat = 0
    private var fired = false

    public init() {}

    /// A new gesture started (the scroll phase began).
    public mutating func begin() {
        travel = 0
        fired = false
    }

    /// One scroll event's deltas. Returns +1 for the next page (content moving
    /// left, as a swipe to the left does), -1 for the previous, or nil.
    public mutating func scroll(deltaX: CGFloat, deltaY: CGFloat) -> Int? {
        guard !fired, abs(deltaX) > abs(deltaY) else { return nil }
        travel += deltaX
        guard abs(travel) >= Self.threshold else { return nil }
        fired = true
        return travel < 0 ? 1 : -1
    }
}
