import SwiftUI

/// Native menu content shared by the live player and decoded-surface route.
struct AppleLivePlaybackOptions: View {
    let onSleepTimer: () -> Void
    let onMultiview: (() -> Void)?
    let onCaptions: () -> Void

    var body: some View {
        Button("Sleep Timer", action: onSleepTimer)
        if let onMultiview {
            Button("Multiview", action: onMultiview)
                .accessibilityIdentifier("live.player.multiview")
        }
        Button("Captions", action: onCaptions)
    }
}
