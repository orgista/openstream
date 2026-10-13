import SwiftUI
import Observation

/// A moving shelf defers new work until focus/scroll has settled.
enum AppleArtworkLoadingPolicy {
    static let dwell: Duration = .milliseconds(200)

    static func needsReload(loadedIdentity: String?, requestedIdentity: String, hasImage: Bool = true) -> Bool {
        !hasImage || loadedIdentity != requestedIdentity
    }
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

/// Holds the live environment pause independently of the image task's identity.
@MainActor @Observable
final class AppleArtworkLoadingGate {
    var isPaused = false

    func waitUntilReady(isCached: Bool) async throws {
        guard !isCached else { return }
        while isPaused {
            try await Task.sleep(for: .milliseconds(30))
        }
        try Task.checkCancellation()
    }
}
