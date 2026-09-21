#if os(macOS)
import SwiftUI

extension ApplePlaybackCoordinator {
    /// This session's answers to the Mac Controls menu.
    ///
    /// Closures rather than a reference to the coordinator, because the menu is
    /// built once for the whole app and there is one coordinator per playback
    /// session. Weakly captured: the menu outlives the player, and a strong
    /// capture here would keep a finished session's engine alive.
    func macPlaybackControls(id: UUID) -> AppleMacPlaybackControls {
        AppleMacPlaybackControls(
            id: id,
            togglePlayPause: { [weak self] in
                guard let self else { return }
                // Resolved against what is happening now, the same way an
                // AirPods stem press is (`AppleRemoteCommandPolicy`), so one
                // key does both jobs instead of being a third action.
                if phase == .playing { userPause() } else { userPlay() }
            },
            skipForward: { [weak self] in self?.macSkip(by: AppleRemoteCommand.skipInterval) },
            skipBackward: { [weak self] in self?.macSkip(by: -AppleRemoteCommand.skipInterval) }
        )
    }

    private func macSkip(by offset: Double) {
        let destination = AppleRemoteCommandPolicy.destination(
            from: engine.position,
            offset: offset,
            duration: engine.duration
        )
        Task { await userSeek(to: destination) }
    }
}

extension View {
    /// Lends the Mac Controls menu to this player for as long as it is on
    /// screen.
    ///
    /// The menu items are disabled while nothing is installed, and a disabled
    /// menu item does not claim its key equivalent — which is the only reason
    /// the bare space bar can be the play/pause key without making it
    /// impossible to type a space into a text field anywhere else in the app.
    func appleMacPlaybackCommands(_ coordinator: ApplePlaybackCoordinator) -> some View {
        modifier(AppleMacPlaybackCommandsModifier(coordinator: coordinator))
    }
}

private struct AppleMacPlaybackCommandsModifier: ViewModifier {
    let coordinator: ApplePlaybackCoordinator
    /// Identifies this installation so a player being dismissed over another
    /// one cannot clear the menu the visible player just claimed.
    @State private var id = UUID()

    func body(content: Content) -> some View {
        content
            .onAppear {
                AppleMacCommandCenter.shared.install(coordinator.macPlaybackControls(id: id))
            }
            .onDisappear {
                AppleMacCommandCenter.shared.remove(id: id)
            }
    }
}
#endif
