import Foundation

public struct ApplePlaybackProgress: Codable, Equatable, Sendable {
    public static let completionFraction = 0.95
    public static let completionRemainingSeconds = 30.0

    public let position: Double
    public let duration: Double
    public let updatedAt: Date

    public init(position: Double, duration: Double, updatedAt: Date = .now) {
        self.position = position
        self.duration = duration
        self.updatedAt = updatedAt
    }

    public var resumePosition: Double? {
        guard duration > 0, position >= 15, !isComplete else { return nil }
        return position
    }

    public var isComplete: Bool {
        guard duration.isFinite, position.isFinite, duration > 0, position >= 0 else { return false }
        let clampedPosition = min(position, duration)
        return clampedPosition >= duration * Self.completionFraction
            || duration - clampedPosition <= Self.completionRemainingSeconds
    }
}

@MainActor
public final class ApplePlaybackStore {
    private let defaults: UserDefaults
    private let key = "openstream.playback.progress.v1"

    /// In-memory copy of the progress map. UserDefaults stays the backing
    /// store (write-through), but reads and each per-tick save no longer
    /// decode + re-encode the whole dictionary. `nil` means not yet loaded.
    private var cache: [String: ApplePlaybackProgress]?

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func progress(for mediaID: String) -> ApplePlaybackProgress? {
        guard let storageKey = ApplePlaybackIdentity.storageKey(for: mediaID) else { return nil }
        return entries()[storageKey]
    }

    public func progress(for url: URL) -> ApplePlaybackProgress? {
        entries()[ApplePlaybackIdentity.storageKey(for: url)]
    }

    public func save(mediaID: String, position: Double, duration: Double) {
        guard let storageKey = ApplePlaybackIdentity.storageKey(for: mediaID) else { return }
        save(storageKey: storageKey, position: position, duration: duration)
    }

    public func save(url: URL, position: Double, duration: Double) {
        save(storageKey: ApplePlaybackIdentity.storageKey(for: url), position: position, duration: duration)
    }

    public func clear(mediaID: String) {
        guard let storageKey = ApplePlaybackIdentity.storageKey(for: mediaID) else { return }
        clear(storageKey: storageKey)
    }

    public func clear(url: URL) {
        clear(storageKey: ApplePlaybackIdentity.storageKey(for: url))
    }

    private func save(storageKey: String, position: Double, duration: Double) {
        guard position.isFinite, position >= 0, duration.isFinite, duration > 0 else { return }
        var current = entries()
        let progress = ApplePlaybackProgress(position: min(position, duration), duration: duration)
        if progress.isComplete {
            current.removeValue(forKey: storageKey)
        } else {
            current[storageKey] = progress
        }
        persist(current)
    }

    private func clear(storageKey: String) {
        var current = entries()
        current.removeValue(forKey: storageKey)
        persist(current)
    }

    private func entries() -> [String: ApplePlaybackProgress] {
        if let cache { return cache }
        let loaded: [String: ApplePlaybackProgress]
        if let data = defaults.data(forKey: key) {
            let decoded = (try? JSONDecoder().decode([String: ApplePlaybackProgress].self, from: data)) ?? [:]
            var normalized: [String: ApplePlaybackProgress] = [:]
            for (mediaID, progress) in decoded {
                if let storageKey = ApplePlaybackIdentity.storageKey(for: mediaID) {
                    normalized[storageKey] = progress
                }
            }
            loaded = normalized
            if loaded.keys.sorted() != decoded.keys.sorted() {
                defaults.set(try? JSONEncoder().encode(loaded), forKey: key)
            }
        } else {
            loaded = [:]
        }
        cache = loaded
        return loaded
    }

    private func persist(_ entries: [String: ApplePlaybackProgress]) {
        cache = entries
        defaults.set(try? JSONEncoder().encode(entries), forKey: key)
    }
}
