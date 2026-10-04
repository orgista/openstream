#if os(iOS)
import UIKit

/// Pattern detection reads no pasteboard value and does not trigger a paste permission prompt.
enum AppleCopiedLinkDetection {
    @MainActor
    static func detect() async -> Bool {
        await withCheckedContinuation { continuation in
            UIPasteboard.general.detectPatterns(for: [\.probableWebURL], completionHandler: completion(continuation))
        }
    }

    // UIKit invokes this completion off the main actor. Creating it in a nonisolated
    // function avoids Swift 6 inheriting the view's actor and asserting at runtime.
    nonisolated private static func completion(_ continuation: CheckedContinuation<Bool, Never>)
        -> (Result<Set<PartialKeyPath<UIPasteboard.DetectedValues>>, any Error>) -> Void {
        { result in
            continuation.resume(returning: (try? result.get().contains(\.probableWebURL)) == true)
        }
    }
}
#endif
