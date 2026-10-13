import SwiftUI

/// A moving shelf defers new work until focus/scroll has settled.
enum AppleArtworkLoadingPolicy {
    static let dwell: Duration = .milliseconds(200)
    static func shouldPause(isScrolling: Bool, focusSettled: Bool) -> Bool {
        isScrolling || !focusSettled
    }
}

private struct AppleArtworkLoadsPausedKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var appleArtworkLoadsPaused: Bool {
        get { self[AppleArtworkLoadsPausedKey.self] }
        set { self[AppleArtworkLoadsPausedKey.self] = newValue }
    }
}
