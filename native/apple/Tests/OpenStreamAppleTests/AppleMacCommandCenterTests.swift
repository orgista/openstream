import Foundation
import Testing
@testable import OpenStreamApple

/// The Mac menu bar's model.
///
/// The app shipped with no `.commands` block at all: an empty View menu, no
/// ⌘, and not one `keyboardShortcut` anywhere in `Sources/`. These cover the
/// parts of the replacement that are values rather than views — which is most
/// of it, deliberately, so the menu itself stays a thin declaration.
@Suite("Mac command centre")
@MainActor
struct AppleMacCommandCenterTests {
    @Test("Tab items take ⌘1 … ⌘4 in menu order, with no number used twice")
    func tabShortcutsAreUniqueAndOrdered() {
        let characters = AppleMacTabTarget.allCases.map(\.shortcutCharacter)
        #expect(characters == ["1", "2", "3", "4"])
        #expect(Set(characters).count == AppleMacTabTarget.allCases.count)
    }

    @Test("Every menu tab target maps to a real tab, and back")
    func tabTargetsRoundTrip() {
        for target in AppleMacTabTarget.allCases {
            let tab = OpenStreamTab(macTarget: target)
            #expect(AppleMacTabTarget(tab: tab) == target)
        }
    }

    /// Search is a tab on Apple TV only; on macOS it is a page pushed from
    /// Discover and has its own ⌘F item, so it must never turn up as a View
    /// menu row.
    @Test("The tvOS-only Search tab has no menu item")
    func searchTabHasNoMenuTarget() {
        #expect(AppleMacTabTarget(tab: .search) == nil)
    }

    /// N54: the toolbar's Refresh had no key equivalent and no menu item.
    /// View ▸ Refresh ⌘R is live exactly where the toolbar has the button.
    @Test("Refresh is live on Discover and Library only", arguments: AppleMacTabTarget.allCases)
    func refreshFollowsTheToolbar(tab: AppleMacTabTarget) {
        let centre = AppleMacCommandCenter()
        #expect(centre.canRefresh == false)
        centre.selectedTab = tab
        #expect(centre.canRefresh == [.discover, .library].contains(tab))
    }

    @Test("Refresh names the selected tab and bumps its own revision")
    func refreshTargetsTheSelectedTab() {
        let centre = AppleMacCommandCenter()
        centre.selectedTab = .library
        centre.requestRefresh()
        #expect(centre.refreshTarget == .library)
        #expect(centre.refreshRevision == 1)
        #expect(centre.revision == 0)
        centre.selectedTab = .settings
        centre.requestRefresh()
        #expect(centre.refreshRevision == 1)
        #expect(centre.refreshTarget == .library)
    }

    @Test("Refresh steps aside while a player covers the window")
    func refreshIsOffUnderThePlayer() {
        let centre = AppleMacCommandCenter()
        centre.selectedTab = .discover
        centre.isPlayerOnStage = true
        #expect(centre.canRefresh == false)
        centre.requestRefresh()
        #expect(centre.refreshRevision == 0)
    }

    @Test("Sending a command bumps the revision the root view watches")
    func sendingBumpsRevision() {
        let centre = AppleMacCommandCenter()
        #expect(centre.command == nil)
        centre.send(.selectTab(.library))
        #expect(centre.command == .selectTab(.library))
        #expect(centre.revision == 1)
        centre.send(.openSearch)
        #expect(centre.command == .openSearch)
        #expect(centre.revision == 2)
    }

    /// The Controls menu is disabled whenever this is false, and a disabled
    /// menu item does not claim its key equivalent — which is the only reason
    /// a bare space bar can be the play/pause key without breaking every text
    /// field in the app.
    @Test("Playback commands are inert until a player installs its controls")
    func playbackCommandsAreInertWithoutAPlayer() {
        let centre = AppleMacCommandCenter()
        #expect(centre.canControlPlayback == false)
        // Must not trap, and must not do anything.
        centre.perform(.togglePlayPause)
        centre.perform(.skipForward)
        centre.perform(.skipBackward)
    }

    @Test("Each Controls item runs its own closure")
    func playbackCommandsRouteToTheRightClosure() {
        let centre = AppleMacCommandCenter()
        let calls = Calls()
        centre.install(AppleMacPlaybackControls(
            togglePlayPause: { calls.record("toggle") },
            skipForward: { calls.record("forward") },
            skipBackward: { calls.record("backward") }
        ))
        #expect(centre.canControlPlayback)
        centre.perform(.skipBackward)
        centre.perform(.togglePlayPause)
        centre.perform(.skipForward)
        #expect(calls.names == ["backward", "toggle", "forward"])
    }

    /// Two players can overlap for a frame while one is dismissed over the
    /// other. An unconditional clear would leave the Controls menu dead for
    /// the player that is actually on screen.
    @Test("Removing a stale installation leaves the live one alone")
    func removingAStaleInstallationIsANoOp() {
        let centre = AppleMacCommandCenter()
        let stale = UUID()
        let live = UUID()
        let calls = Calls()
        centre.install(AppleMacPlaybackControls(id: live, togglePlayPause: { calls.record("live") },
                                                skipForward: {}, skipBackward: {}))
        centre.remove(id: stale)
        #expect(centre.canControlPlayback)
        centre.perform(.togglePlayPause)
        #expect(calls.names == ["live"])
        centre.remove(id: live)
        #expect(centre.canControlPlayback == false)
    }

    @Test("Selecting a tab whose toggle is off is a disabled item, not a redirect")
    func unavailableTabsAreReportedRatherThanRedirected() {
        let centre = AppleMacCommandCenter()
        #expect(centre.availableTabs == Set(AppleMacTabTarget.allCases))
        let visible = OpenStreamTabVisibility.visibleTabs(discover: true, library: true, live: false)
        centre.availableTabs = Set(visible.compactMap(AppleMacTabTarget.init(tab:)))
        #expect(centre.availableTabs == [.discover, .library, .settings])
        #expect(centre.availableTabs.contains(.live) == false)
    }

    @MainActor
    private final class Calls {
        private(set) var names: [String] = []
        func record(_ name: String) { names.append(name) }
    }
}
