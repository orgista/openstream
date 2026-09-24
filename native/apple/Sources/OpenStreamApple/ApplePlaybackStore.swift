import Foundation

public struct ApplePlaybackProgress: Codable, Equatable, Sendable {
    public static let completionFraction = 0.95
    public static let completionRemainingSeconds = 30.0

    public let position: Double
    public let duration: Double
    public let updatedAt: Date
    /// Which part of the title this position belongs to: the episode's media
    /// id for a series, the resolved id for a film, `nil` for a local file.
    /// A series keeps one entry under the show — that is what Continue
    /// Watching lists — so without this a viewer who finished episode 1 and
    /// opened episode 2 would be dropped 40 minutes into it.
    public let partID: String?

    public init(position: Double, duration: Double, updatedAt: Date = .now, partID: String? = nil) {
        self.position = position
        self.duration = duration
        self.updatedAt = updatedAt
        self.partID = partID
    }

    public var resumePosition: Double? {
        guard duration > 0, position >= 15, !isComplete else { return nil }
        return position
    }

    /// The resume point for `partID`, or nil when the stored position belongs
    /// to a different episode. Entries saved before this field existed carry
    /// no part and only resume something that also names none.
    public func resumePosition(for partID: String?) -> Double? {
        guard self.partID == partID else { return nil }
        return resumePosition
    }

    public var isComplete: Bool {
        guard duration.isFinite, position.isFinite, duration > 0, position >= 0 else { return false }
        let clampedPosition = min(position, duration)
        return clampedPosition >= duration * Self.completionFraction
            || duration - clampedPosition <= Self.completionRemainingSeconds
    }
}

/// Where a title starts when the viewer presses Play: the position the store
/// holds for that exact part, or nil to start at the beginning. One place, so
/// every play path in the detail page agrees — they all passed `nil` before,
/// which is why a Continue Watching title restarted from zero (owner
/// 2026-09-14: "continue watching does not actually have placement of where
/// you left off").
@MainActor
public enum AppleDetailResume {
    public static func position(
        mediaID: String,
        partID: String?,
        store: ApplePlaybackStore = ApplePlaybackStore()
    ) -> Double? {
        store.progress(for: mediaID)?.resumePosition(for: partID)
    }

    /// Only a series has parts. A film has one, so tying its position to the
    /// resolved media id would drop the resume point whenever metadata
    /// resolution answered differently between two launches.
    nonisolated public static func partID(type: String?, mediaID: String?) -> String? {
        type == "series" ? mediaID : nil
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
    private var cachedData: Data?

    /// What has been finished, keyed like the progress map, valued by when.
    /// A finished title leaves the progress map (that is how it leaves
    /// Continue Watching), so without this nothing remembered it: no episode
    /// ever showed its tick and "next episode" always meant the first one.
    /// Watching a finished episode again does not take it off this list.
    private let watchedKey = "openstream.playback.watched.v1"
    private var watchedCache: [String: Date]?
    private var watchedCachedData: Data?
    /// The newest this many finished titles are kept.
    nonisolated public static let watchedHistoryLimit = 5_000

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func progress(for mediaID: String) -> ApplePlaybackProgress? {
        guard let storageKey = ApplePlaybackIdentity.storageKey(for: mediaID) else { return nil }
        return entries()[storageKey]
    }

    /// The finished titles among `mediaIDs`, from one read of the watched
    /// history: callers that check a whole episode list during a redraw stay
    /// O(1) reads. A progress entry that is itself complete (one restored
    /// from an older backup) counts too.
    public func completedMediaIDs(among mediaIDs: [String]) -> Set<String> {
        let watched = watchedEntries()
        let all = entries()
        return Set(mediaIDs.filter { mediaID in
            guard let storageKey = ApplePlaybackIdentity.storageKey(for: mediaID) else { return false }
            #if DEBUG
            if AppleWatchedHistoryFixture.isSeeded(mediaID: mediaID, storageKey: storageKey) { return true }
            #endif
            return watched[storageKey] != nil || all[storageKey]?.isComplete == true
        })
    }

    public func isWatched(mediaID: String) -> Bool {
        !completedMediaIDs(among: [mediaID]).isEmpty
    }

    /// "Mark as Watched": records `mediaID` as finished now.
    public func markWatched(mediaID: String, at date: Date = .now) {
        guard let storageKey = ApplePlaybackIdentity.storageKey(for: mediaID) else { return }
        var current = watchedEntries()
        current[storageKey] = date
        #if DEBUG
        AppleWatchedHistoryFixture.unwatched.remove(storageKey)
        #endif
        persistWatched(current)
    }

    /// "Mark as Unwatched": forgets that `mediaID` was finished. A resumable
    /// position for it, if any, stays.
    public func markUnwatched(mediaID: String) {
        guard let storageKey = ApplePlaybackIdentity.storageKey(for: mediaID) else { return }
        var watched = watchedEntries()
        #if DEBUG
        if AppleWatchedHistoryFixture.isEnabled {
            AppleWatchedHistoryFixture.unwatched.insert(storageKey)
            watched.removeValue(forKey: storageKey)
            persistWatched(watched)
            return
        }
        #endif
        if watched.removeValue(forKey: storageKey) != nil { persistWatched(watched) }
        var progress = entries()
        if progress[storageKey]?.isComplete == true {
            progress.removeValue(forKey: storageKey)
            persist(progress)
        }
    }

    public func progress(for url: URL) -> ApplePlaybackProgress? {
        entries()[ApplePlaybackIdentity.storageKey(for: url)]
    }

    public func save(mediaID: String, position: Double, duration: Double, partID: String? = nil) {
        guard let storageKey = ApplePlaybackIdentity.storageKey(for: mediaID) else { return }
        save(storageKey: storageKey, position: position, duration: duration, partID: partID)
    }

    public func save(url: URL, position: Double, duration: Double, partID: String? = nil) {
        save(storageKey: ApplePlaybackIdentity.storageKey(for: url), position: position, duration: duration, partID: partID)
    }

    public func clear(mediaID: String) {
        guard let storageKey = ApplePlaybackIdentity.storageKey(for: mediaID) else { return }
        clear(storageKey: storageKey)
    }

    public func clear(url: URL) {
        clear(storageKey: ApplePlaybackIdentity.storageKey(for: url))
    }

    private func save(storageKey: String, position: Double, duration: Double, partID: String?) {
        guard position.isFinite, position >= 0, duration.isFinite, duration > 0 else { return }
        var current = entries()
        let progress = ApplePlaybackProgress(position: min(position, duration), duration: duration, partID: partID)
        if progress.isComplete {
            current.removeValue(forKey: storageKey)
            // A series keeps its entry under the show and names the episode
            // in `partID`; the episode is what was finished, not the show.
            let finishedKey = partID.flatMap(ApplePlaybackIdentity.storageKey(for:)) ?? storageKey
            var watched = watchedEntries()
            // The last half-minute saves "complete" several times; one
            // record per viewing is enough.
            if watched[finishedKey].map({ progress.updatedAt.timeIntervalSince($0) > 600 }) ?? true {
                watched[finishedKey] = progress.updatedAt
                persistWatched(watched, notify: false)
            }
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
        let storedData = defaults.data(forKey: key)
        if let cache, cachedData == storedData { return cache }
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
        cachedData = defaults.data(forKey: key)
        return loaded
    }

    private func watchedEntries() -> [String: Date] {
        #if DEBUG
        if AppleWatchedHistoryFixture.isEnabled { return AppleWatchedHistoryFixture.memory }
        #endif
        return storedWatchedEntries()
    }

    private func persistWatched(_ entries: [String: Date], notify: Bool = true) {
        #if DEBUG
        if AppleWatchedHistoryFixture.isEnabled {
            AppleWatchedHistoryFixture.memory = Self.boundedWatchedHistory(entries)
            if notify { ApplePlaybackProgressFeed.shared.storeDidChange() }
            return
        }
        #endif
        persistStoredWatched(entries, notify: notify)
    }

    private func storedWatchedEntries() -> [String: Date] {
        let storedData = defaults.data(forKey: watchedKey)
        if let watchedCache, watchedCachedData == storedData { return watchedCache }
        let decoded = storedData.flatMap { try? JSONDecoder().decode([String: Date].self, from: $0) } ?? [:]
        watchedCache = decoded
        watchedCachedData = storedData
        return decoded
    }

    private func persistStoredWatched(_ entries: [String: Date], notify: Bool) {
        let bounded = Self.boundedWatchedHistory(entries)
        watchedCache = bounded
        watchedCachedData = try? JSONEncoder().encode(bounded)
        defaults.set(watchedCachedData, forKey: watchedKey)
        if notify { ApplePlaybackProgressFeed.shared.storeDidChange() }
    }

    /// The newest `watchedHistoryLimit` entries; ties keep the lower key so
    /// the trim is stable.
    nonisolated static func boundedWatchedHistory(_ entries: [String: Date], limit: Int = watchedHistoryLimit) -> [String: Date] {
        guard entries.count > limit else { return entries }
        let newest = entries.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }.prefix(limit)
        return Dictionary(uniqueKeysWithValues: newest.map { ($0.key, $0.value) })
    }

    func configurationProgress() -> [String: ApplePlaybackProgress] { entries() }

    func restoreConfigurationProgress(_ entries: [String: ApplePlaybackProgress]) {
        persist(entries)
    }

    /// Backups and iCloud always read and write the stored history, never a
    /// review build's in-memory fixture.
    func configurationWatchedHistory() -> [String: Date] { storedWatchedEntries() }

    /// Merges a backup's or another device's watched history into this one:
    /// the union, and where both know a title the later finish wins. Nothing
    /// local is dropped, so an older backup never un-watches anything.
    func restoreConfigurationWatchedHistory(_ incoming: [String: Date]) {
        guard !incoming.isEmpty else { return }
        let current = storedWatchedEntries()
        var merged = current
        for (key, date) in incoming {
            guard let storageKey = ApplePlaybackIdentity.storageKey(for: key) else { continue }
            if let existing = merged[storageKey], existing >= date { continue }
            merged[storageKey] = date
        }
        guard merged != current else { return }
        persistStoredWatched(merged, notify: true)
    }

    private func persist(_ entries: [String: ApplePlaybackProgress]) {
        cache = entries
        cachedData = try? JSONEncoder().encode(entries)
        defaults.set(cachedData, forKey: key)
        ApplePlaybackProgressFeed.shared.storeDidChange()
    }
}

#if DEBUG
/// Review builds only: `-OpenStreamDebugWatchedFixture 1:1,1:2` marks those
/// season:episode numbers watched on whichever show is open, so a simulator
/// with no history can photograph the ticks, the Up Next button and the
/// episode menu without playing anything. While it is on, the watched
/// history lives in memory — nothing is read from or written to the store,
/// backups or iCloud.
@MainActor
enum AppleWatchedHistoryFixture {
    static let launchKey = "OpenStreamDebugWatchedFixture"
    static var memory: [String: Date] = [:]
    /// Seeded episodes the viewer has since marked as unwatched.
    static var unwatched: Set<String> = []

    private static let seeds: Set<String> = Set(
        (UserDefaults.standard.string(forKey: launchKey) ?? "")
            .split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    )

    static var isEnabled: Bool { !seeds.isEmpty }

    static func isSeeded(mediaID: String, storageKey: String) -> Bool {
        guard isEnabled, !unwatched.contains(storageKey),
              let identity = AppleStremioMetadataClient.episodeIdentity(mediaID) else { return false }
        return seeds.contains("\(identity.season):\(identity.episode)")
    }
}
#endif
