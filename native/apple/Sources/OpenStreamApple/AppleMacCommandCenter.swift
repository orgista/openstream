import Foundation
import Observation

/// What a Mac menu item asks the app to do.
///
/// The menu bar is declared in the app target, which reaches this package
/// through its public API and cannot see `OpenStreamTab`, so the tab a command
/// selects is named again as `AppleMacTabTarget`. The mapping back is
/// `OpenStreamTab(macTarget:)`, and it is tested: a View menu item that
/// selected a tab the bar does not currently show would be a dead command, and
/// the Live tab really can be switched off in Settings.
public enum AppleMacCommand: Equatable, Sendable {
    case selectTab(AppleMacTabTarget)
    case openSearch
    case togglePlayPause
    case skipForward
    case skipBackward
}

/// The four tabs a Mac menu item can select, in menu order.
public enum AppleMacTabTarget: String, CaseIterable, Sendable {
    case discover
    case library
    case live
    case settings

    public var title: String {
        switch self {
        case .discover: "Discover"
        case .library: "Library"
        case .live: "Live"
        case .settings: "Settings"
        }
    }

    /// ⌘1 … ⌘4, the numbering every Mac app with a fixed set of views uses.
    /// Derived from the case order rather than written out, so a fifth tab
    /// cannot be given a number that is already taken.
    public var shortcutCharacter: Character {
        let index = Self.allCases.firstIndex(of: self) ?? 0
        return Character(String(index + 1))
    }
}

/// How the player answers the Controls menu.
///
/// Values, not a reference to the coordinator: the menu is built once for the
/// whole app and there is one coordinator per playback session, so the player
/// hands over three closures while it is on screen and takes them back when it
/// leaves.
@MainActor
public struct AppleMacPlaybackControls {
    public let id: UUID
    let togglePlayPause: () -> Void
    let skipForward: () -> Void
    let skipBackward: () -> Void

    public init(
        id: UUID = UUID(),
        togglePlayPause: @escaping () -> Void,
        skipForward: @escaping () -> Void,
        skipBackward: @escaping () -> Void
    ) {
        self.id = id
        self.togglePlayPause = togglePlayPause
        self.skipForward = skipForward
        self.skipBackward = skipBackward
    }
}

/// The one place the Mac menu bar and the app's views meet.
///
/// The root view watches `revision` and acts on `command`; the player installs
/// and removes `playback`. Nothing else holds state, so a command that no view
/// is listening for is simply dropped rather than queued up to fire later.
@MainActor
@Observable
public final class AppleMacCommandCenter {
    public static let shared = AppleMacCommandCenter()

    public private(set) var command: AppleMacCommand?
    public private(set) var revision = 0

    /// Installed by the player while it is on screen, cleared when it leaves.
    ///
    /// This does two jobs, and the second one is the important one. A menu
    /// item's key equivalent is matched *before* the responder chain sees the
    /// key, so a live "Play/Pause ␣" item would make it impossible to type a
    /// space into any text field in the app — the manifest URL, a Trakt client
    /// id, a backup passphrase. A disabled menu item does not claim its key
    /// equivalent, so gating the Controls menu on this being non-nil is what
    /// lets the space bar be the play/pause key at all.
    public private(set) var playback: AppleMacPlaybackControls?

    /// Which View-menu tab items are live.
    ///
    /// Discover, Library and Live each have a toggle in Settings, so the bar
    /// does not always show all four. A menu item for a hidden tab that
    /// silently landed the viewer on a different one is worse than a greyed
    /// out item, which is the answer every Mac app gives for a view that is
    /// not available.
    public var availableTabs: Set<AppleMacTabTarget> = Set(AppleMacTabTarget.allCases)

    public init() {}

    /// Whether the Controls menu is live. The menu reads this directly.
    public var canControlPlayback: Bool { playback != nil }

    public func send(_ command: AppleMacCommand) {
        self.command = command
        revision &+= 1
    }

    public func install(_ controls: AppleMacPlaybackControls) {
        playback = controls
    }

    /// Removes the controls only if they are still the ones that were
    /// installed. Two players can overlap for a frame while one is dismissed
    /// over the other, and an unconditional clear would leave the menu dead
    /// for the player that is actually on screen.
    public func remove(id: UUID) {
        guard playback?.id == id else { return }
        playback = nil
    }

    public func perform(_ command: AppleMacCommand) {
        guard let playback else { return }
        switch command {
        case .togglePlayPause: playback.togglePlayPause()
        case .skipForward: playback.skipForward()
        case .skipBackward: playback.skipBackward()
        case .selectTab, .openSearch: break
        }
    }
}

extension OpenStreamTab {
    init(macTarget: AppleMacTabTarget) {
        switch macTarget {
        case .discover: self = .home
        case .library: self = .library
        case .live: self = .live
        case .settings: self = .settings
        }
    }
}

extension AppleMacTabTarget {
    /// Nil for the tvOS-only Search tab, which is never in a Mac menu — on
    /// macOS Search is a page pushed from Discover and has its own ⌘F item.
    init?(tab: OpenStreamTab) {
        switch tab {
        case .home: self = .discover
        case .library: self = .library
        case .live: self = .live
        case .settings: self = .settings
        case .search: return nil
        }
    }
}
