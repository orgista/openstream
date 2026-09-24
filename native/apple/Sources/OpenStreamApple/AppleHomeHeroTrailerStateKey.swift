import SwiftUI

/// What the hero's inline trailer is doing, so the iPhone hero's cycle can
/// hold the page while it plays with the sound on
/// (`AppleHeroRotation.cycleIsPaused`).
struct AppleHomeHeroTrailerStateKey: PreferenceKey {
    struct Value: Equatable {
        var isPlaying = false
        var isMuted = true
        /// Started by the Play Trailer button rather than autoplay.
        var isRequested = false
    }

    static let defaultValue = Value()

    static func reduce(value: inout Value, nextValue: () -> Value) {
        let next = nextValue()
        if next.isPlaying { value = next }
    }
}
