import Foundation

public struct ApplePlaybackProgress: Codable, Equatable, Sendable {
    public static let completionFraction = AppleCompletionPolicy.fraction
    public static let completionRemainingSeconds = AppleCompletionPolicy.remainingSeconds

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
        AppleCompletionPolicy.isComplete(position: position, duration: duration)
    }
}

/// Monotonic per-title barriers. Keep each kind independently: a later row
/// removal must not discard the completion/reset that blocks stale resumes.
public struct ApplePlaybackTerminalEvents: Codable, Equatable, Sendable {
    public var completedAt: Date?
    public var resetAt: Date?
    public var removedAt: Date?
    public var playedAt: Date?

    public init(completedAt: Date? = nil, resetAt: Date? = nil, removedAt: Date? = nil, playedAt: Date? = nil) {
        self.completedAt = completedAt
        self.resetAt = resetAt
        self.removedAt = removedAt
        self.playedAt = playedAt
    }

    var progressBarrier: Date? { [completedAt, resetAt].compactMap { $0 }.max() }

    func merging(_ other: Self) -> Self {
        Self(completedAt: [completedAt, other.completedAt].compactMap { $0 }.max(),
             resetAt: [resetAt, other.resetAt].compactMap { $0 }.max(),
             removedAt: [removedAt, other.removedAt].compactMap { $0 }.max(),
             playedAt: [playedAt, other.playedAt].compactMap { $0 }.max())
    }
}

/// Shared by local restore and cloud merge; equal clocks must yield the same
/// result regardless of device or restore order.
enum ApplePlaybackConvergence {
    static func freshest(_ a: ApplePlaybackProgress, _ b: ApplePlaybackProgress) -> ApplePlaybackProgress {
        if a.updatedAt != b.updatedAt { return a.updatedAt > b.updatedAt ? a : b }
        if a.isComplete != b.isComplete { return a.isComplete ? a : b }
        if a.position != b.position { return a.position > b.position ? a : b }
        if a.duration != b.duration { return a.duration > b.duration ? a : b }
        if a.partID == nil { return b.partID == nil ? a : b }
        if b.partID == nil { return a }
        return (a.partID ?? "") >= (b.partID ?? "") ? a : b
    }

    static func terminals(_ explicit: [String: ApplePlaybackTerminalEvents],
                          watched: [String: Date], unwatched: [String: Date],
                          removals: [String: Date], activity: [String: ApplePlaybackProgress]) -> [String: ApplePlaybackTerminalEvents] {
        var result = explicit
        func add(_ key: String, _ event: ApplePlaybackTerminalEvents) {
            result[key] = (result[key] ?? .init()).merging(event)
        }
        for (key, date) in watched { add(key, .init(completedAt: date)) }
        for (key, date) in unwatched { add(key, .init(resetAt: date)) }
        for (key, date) in removals { add(key, .init(removedAt: date)) }
        for (key, progress) in activity where progress.isComplete { add(key, .init(completedAt: progress.updatedAt)) }
        // Retain every title's playback clock even when the ordinary cloud
        // resume/activity lists trim its offset.
        for (key, progress) in activity { add(key, .init(playedAt: progress.updatedAt)) }
        return result
    }

    static func history(_ history: AppleWatchedHistory, terminals: [String: ApplePlaybackTerminalEvents]) -> AppleWatchedHistory {
        var result = history
        // Only upgrade known watched identities: show-level completion
        // barriers must not turn a finished episode into a watched show.
        for key in history.watched.keys {
            if let date = terminals[key]?.completedAt { result.merge(watched: [key: date], tombstones: [:]) }
        }
        result.merge(watched: [:], tombstones: terminals.compactMapValues(\.resetAt))
        return result
    }

    static func reconciled(_ progress: [String: ApplePlaybackProgress], terminals: [String: ApplePlaybackTerminalEvents]) -> [String: ApplePlaybackProgress] {
        progress.filter { key, value in
            let part = value.partID.flatMap(ApplePlaybackIdentity.storageKey(for:))
            let barrier = [terminals[key]?.progressBarrier, value.partID.flatMap { terminals[$0]?.progressBarrier },
                part.flatMap { terminals[$0]?.progressBarrier }].compactMap { $0 }.max()
            if barrier.map({ value.updatedAt <= $0 }) == true { return false }
            if terminals[key]?.playedAt.map({ value.updatedAt < $0 }) == true { return false }
            return true
        }
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
    private let key: String

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
    private let watchedKey: String
    private let unwatchedKey: String
    private var watchedCache: [String: Date]?
    private var watchedCachedData: Data?
    private var unwatchedCache: [String: Date]?
    private var unwatchedCachedData: Data?
    /// The newest this many finished titles are kept.
    nonisolated public static let watchedHistoryLimit = 5_000
    /// Titles the viewer took off Continue Watching, and when. The progress
    /// stays; the row leaves the title out until it is played again.
    private let continueWatchingRemovedKey: String
    private var removedCache: [String: Date]?
    private var removedCachedData: Data?
    /// The newest this many removals are kept.
    nonisolated public static let continueWatchingRemovalLimit = 500

    public let namespace: String

    public init(defaults: UserDefaults = .standard, namespace: String = AppleTasteNamespace.local) {
        self.defaults = defaults
        self.namespace = namespace
        key = AppleTasteNamespace.key("openstream.playback.progress.v1", namespace: namespace)
        watchedKey = AppleTasteNamespace.key("openstream.playback.watched.v1", namespace: namespace)
        unwatchedKey = AppleTasteNamespace.key("openstream.playback.unwatched.v1", namespace: namespace)
        continueWatchingRemovedKey = AppleTasteNamespace.key("openstream.playback.continueWatchingRemoved.v1", namespace: namespace)
        terminalKey = AppleTasteNamespace.key("openstream.playback.terminals.v1", namespace: namespace)
        activityKey = AppleTasteNamespace.key("openstream.playback.activity.v1", namespace: namespace)
        episodesKey = AppleTasteNamespace.key("openstream.playback.availableEpisodes.v1", namespace: namespace)
        migrateLegacyPlaybackStateIfNeeded()
    }

    private let terminalKey: String

    private let activityKey: String
    private let episodesKey: String

    private var activityData: Data?
    private var activityCache: [String: ApplePlaybackProgress]?

    private func rawActivities() -> [String: ApplePlaybackProgress] {
        let data = defaults.data(forKey: activityKey)
        if let activityCache, data == activityData { return activityCache }
        let values = data.flatMap { try? JSONDecoder().decode([String: ApplePlaybackProgress].self, from: $0) } ?? [:]
        activityData = data
        activityCache = values
        return values
    }

    func activities() -> [String: ApplePlaybackProgress] {
        let terminals = configurationPlaybackTerminals()
        return rawActivities().filter { key, value in
            let part = value.partID.flatMap(ApplePlaybackIdentity.storageKey(for:))
            let reset = [terminals[key]?.resetAt, part.flatMap { terminals[$0]?.resetAt }].compactMap { $0 }.max()
            if reset.map({ value.updatedAt <= $0 }) == true { return false }
            return terminals[key]?.playedAt.map({ value.updatedAt >= $0 }) ?? true
        }
    }

    public func lastActivity(for mediaID: String) -> ApplePlaybackProgress? {
        guard let key = ApplePlaybackIdentity.storageKey(for: mediaID) else { return nil }
        let saved = entries()[key]
        let activity = activities()[key].map { value in saved.map { ApplePlaybackConvergence.freshest(value, $0) } ?? value } ?? saved
        guard let activity else { return nil }
        let partKey = activity.partID.flatMap(ApplePlaybackIdentity.storageKey(for:))
        let terminals = configurationPlaybackTerminals()
        let reset = [terminals[key]?.resetAt, partKey.flatMap { terminals[$0]?.resetAt }].compactMap { $0 }.max()
        if reset.map({ activity.updatedAt <= $0 }) == true { return nil }
        if terminals[key]?.playedAt.map({ activity.updatedAt < $0 }) == true { return nil }
        return activity
    }

    func availableEpisodes() async -> [String: [AppleStremioEpisode]] {
        await Self.decodeEpisodes(defaults.data(forKey: episodesKey))
    }

    @concurrent nonisolated private static func decodeEpisodes(_ data: Data?) async -> [String: [AppleStremioEpisode]] {
        data.flatMap { try? JSONDecoder().decode([String: [AppleStremioEpisode]].self, from: $0) } ?? [:]
    }

    @concurrent nonisolated private static func updatedEpisodes(_ data: Data?, episodes: [AppleStremioEpisode], key: String) async -> Data? {
        var values = await decodeEpisodes(data)
        values[key] = episodes.map { AppleStremioEpisode(id: $0.id, title: "", season: $0.season,
            episode: $0.episode, releaseInfo: $0.releaseInfo) }
        return try? JSONEncoder().encode(values)
    }

    func recordEpisodes(_ episodes: [AppleStremioEpisode], mediaID: String) async {
        guard let key = ApplePlaybackIdentity.storageKey(for: mediaID) else { return }
        // Retry if another title arrived while encoding off the main actor.
        while !Task.isCancelled {
            let previous = defaults.data(forKey: episodesKey)
            let data = await Self.updatedEpisodes(previous, episodes: episodes, key: key)
            guard previous == defaults.data(forKey: episodesKey) else { continue }
            if data != previous {
                defaults.set(data, forKey: episodesKey)
                ApplePlaybackProgressFeed.shared.storeDidChange()
            }
            return
        }
    }

    /// Saved entries for library adapters; avoids scanning every provider title on each save.
    func savedProgress() -> [String: ApplePlaybackProgress] { entries() }

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
        let tombstones = storedWatchedTombstones()
        let terminals = configurationPlaybackTerminals()
        let all = entries().merging(activities().filter { key, value in
            value.partID == nil || value.partID.flatMap(ApplePlaybackIdentity.storageKey(for:)) == key
        }, uniquingKeysWith: ApplePlaybackConvergence.freshest)
        return Set(mediaIDs.filter { mediaID in
            guard let storageKey = ApplePlaybackIdentity.storageKey(for: mediaID) else { return false }
            #if DEBUG
            if AppleWatchedHistoryFixture.isSeeded(mediaID: mediaID, storageKey: storageKey) { return true }
            #endif
            if tombstones[storageKey] != nil { return false }
            if let reset = terminals[storageKey]?.resetAt {
                let completion = [watched[storageKey], all[storageKey].flatMap { $0.isComplete ? $0.updatedAt : nil }]
                    .compactMap { $0 }.max()
                if completion.map({ $0 <= reset }) ?? true { return false }
            }
            return watched[storageKey] != nil || all[storageKey]?.isComplete == true
        })
    }

    public func isWatched(mediaID: String) -> Bool {
        !completedMediaIDs(among: [mediaID]).isEmpty
    }

    /// "Mark as Watched": records `mediaID` as finished now.
    public func markWatched(mediaID: String, at date: Date = .now) {
        guard let storageKey = ApplePlaybackIdentity.storageKey(for: mediaID) else { return }
        var history = AppleWatchedHistory(watched: watchedEntries(), tombstones: storedWatchedTombstones())
        history.merge(watched: [storageKey: date], tombstones: [:])
        #if DEBUG
        AppleWatchedHistoryFixture.unwatched.remove(storageKey)
        #endif
        recordTerminal(storageKey, .init(completedAt: date))
        persistWatched(history.watched, tombstones: history.tombstones)
        reconcileStoredProgress()
    }

    /// "Mark as Unwatched": records a reset event that supersedes older
    /// resume/activity, including copies later restored from another device.
    public func markUnwatched(mediaID: String, at date: Date = .now) {
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
        var history = AppleWatchedHistory(watched: watched, tombstones: storedWatchedTombstones())
        history.merge(watched: [:], tombstones: [storageKey: date])
        recordTerminal(storageKey, .init(resetAt: date))
        persistWatched(history.watched, tombstones: history.tombstones)
        reconcileStoredProgress()
        var progress = entries()
        if progress[storageKey]?.isComplete == true {
            progress.removeValue(forKey: storageKey)
            persist(progress)
        }
    }

    /// "Remove from Continue Watching": leaves the progress and the watched
    /// history alone, and hides the title from the row until it is played
    /// again (a later progress save).
    public func removeFromContinueWatching(mediaID: String, at date: Date = .now) {
        guard let storageKey = ApplePlaybackIdentity.storageKey(for: mediaID) else { return }
        recordTerminal(storageKey, .init(removedAt: date))
        var removed = continueWatchingRemovals()
        removed[storageKey] = max(removed[storageKey] ?? .distantPast, date)
        persistRemovals(removed)
    }

    /// Whether the viewer took `mediaID` off Continue Watching and has not
    /// played it since.
    public func isRemovedFromContinueWatching(mediaID: String) -> Bool {
        guard let storageKey = ApplePlaybackIdentity.storageKey(for: mediaID) else { return false }
        return AppleContinueWatchingRemovalPolicy.isRemoved(
            removedAt: configurationPlaybackTerminals()[storageKey]?.removedAt,
            lastPlayedAt: [activities()[storageKey]?.updatedAt, entries()[storageKey]?.updatedAt,
                configurationPlaybackTerminals()[storageKey]?.playedAt].compactMap { $0 }.max())
    }

    public func progress(for url: URL) -> ApplePlaybackProgress? {
        entries()[ApplePlaybackIdentity.storageKey(for: url)]
    }

    public func save(mediaID: String, position: Double, duration: Double, partID: String? = nil) {
        guard let storageKey = ApplePlaybackIdentity.storageKey(for: mediaID) else { return }
        AppleInteractionTrace.record(.playback,
            "progress save key=\(storageKey) pos=\(Int(position.isFinite ? position : -1)) dur=\(Int(duration.isFinite ? duration : -1)) part=\(partID ?? "-")")
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
        // A save that names no episode never replaces a series' episode
        // progress (a stray play of the whole show wiped S1E2's Resume).
        guard AppleSeriesProgressGuard.mayOverwrite(existing: current[storageKey], with: partID) else {
            AppleInteractionTrace.record(.playback, "progress save dropped key=\(storageKey): no episode over episode progress")
            return
        }
        let progress = ApplePlaybackProgress(position: min(position, duration), duration: duration, partID: partID)
        var activity = activities()
        activity[storageKey] = progress
        if activity.count > Self.watchedHistoryLimit {
            let barriers = ApplePlaybackConvergence.terminals(configurationPlaybackTerminals(), watched: [:], unwatched: [:],
                removals: [:], activity: activity)
            defaults.set(try? JSONEncoder().encode(barriers), forKey: terminalKey)
            activity = Dictionary(uniqueKeysWithValues: activity.sorted { $0.value.updatedAt == $1.value.updatedAt ? $0.key < $1.key : $0.value.updatedAt > $1.value.updatedAt }
                .prefix(Self.watchedHistoryLimit).map { ($0.key, $0.value) })
        }
        activityCache = activity
        activityData = try? JSONEncoder().encode(activity)
        defaults.set(activityData, forKey: activityKey)
        recordTerminal(storageKey, .init(playedAt: progress.updatedAt))
        if progress.isComplete {
            recordTerminal(storageKey, .init(completedAt: progress.updatedAt))
            current.removeValue(forKey: storageKey)
            // A series keeps its entry under the show and names the episode
            // in `partID`; the episode is what was finished, not the show.
            let finishedKey = partID.flatMap(ApplePlaybackIdentity.storageKey(for:)) ?? storageKey
            var history = AppleWatchedHistory(watched: watchedEntries(), tombstones: storedWatchedTombstones())
            // The last half-minute saves "complete" several times; one
            // record per viewing is enough.
            if history.watched[finishedKey].map({ progress.updatedAt.timeIntervalSince($0) > 600 }) ?? true {
                history.merge(watched: [finishedKey: progress.updatedAt], tombstones: [:])
                persistWatched(history.watched, tombstones: history.tombstones, notify: false)
            }
        } else {
            current[storageKey] = progress
        }
        // Playing it again brings a removed title back to Continue Watching.
        var removed = continueWatchingRemovals()
        if removed.removeValue(forKey: storageKey) != nil { persistRemovals(removed, notify: false) }
        persist(current)
    }

    private func clear(storageKey: String) {
        recordTerminal(storageKey, .init(resetAt: .now))
        var activity = activities()
        activity.removeValue(forKey: storageKey)
        activityCache = activity
        activityData = try? JSONEncoder().encode(activity)
        defaults.set(activityData, forKey: activityKey)
        var current = entries()
        current.removeValue(forKey: storageKey)
        persist(current)
    }

    private func entries() -> [String: ApplePlaybackProgress] {
        // One read of the stored blob: it is compared, decoded and kept from
        // the same value (it was read three times on a miss, N47).
        let storedData = defaults.data(forKey: key)
        if let cache, cachedData == storedData { return cache }
        let loaded: [String: ApplePlaybackProgress]
        var keptData = storedData
        if let data = storedData {
            let decoded = (try? JSONDecoder().decode([String: ApplePlaybackProgress].self, from: data)) ?? [:]
            var normalized: [String: ApplePlaybackProgress] = [:]
            for (mediaID, progress) in decoded {
                if let storageKey = ApplePlaybackIdentity.storageKey(for: mediaID) {
                    normalized[storageKey] = progress
                }
            }
            loaded = normalized
            if loaded.keys.sorted() != decoded.keys.sorted() {
                let rewritten = try? JSONEncoder().encode(loaded)
                defaults.set(rewritten, forKey: key)
                keptData = rewritten
            }
        } else {
            loaded = [:]
        }
        cache = loaded
        cachedData = keptData
        return loaded
    }

    private func watchedEntries() -> [String: Date] {
        #if DEBUG
        if AppleWatchedHistoryFixture.isEnabled { return AppleWatchedHistoryFixture.memory }
        #endif
        return storedWatchedHistory().watched
    }

    private func persistWatched(_ entries: [String: Date], tombstones: [String: Date] = [:], notify: Bool = true) {
        #if DEBUG
        if AppleWatchedHistoryFixture.isEnabled {
            AppleWatchedHistoryFixture.memory = Self.boundedWatchedHistory(entries)
            if notify { ApplePlaybackProgressFeed.shared.storeDidChange() }
            return
        }
        #endif
        persistStoredWatched(AppleWatchedHistory(watched: entries, tombstones: tombstones), notify: notify)
    }

    private func storedWatchedEntries() -> [String: Date] {
        let storedData = defaults.data(forKey: watchedKey)
        if let watchedCache, watchedCachedData == storedData { return watchedCache }
        let decoded = storedData.flatMap { try? JSONDecoder().decode([String: Date].self, from: $0) } ?? [:]
        watchedCache = decoded
        watchedCachedData = storedData
        return decoded
    }

    private func storedWatchedTombstones() -> [String: Date] {
        let storedData = defaults.data(forKey: unwatchedKey)
        if let unwatchedCache, unwatchedCachedData == storedData { return unwatchedCache }
        let decoded = storedData.flatMap { try? JSONDecoder().decode([String: Date].self, from: $0) } ?? [:]
        unwatchedCache = decoded
        unwatchedCachedData = storedData
        return decoded
    }

    private func storedWatchedHistory() -> AppleWatchedHistory {
        AppleWatchedHistory(watched: storedWatchedEntries(), tombstones: storedWatchedTombstones())
    }

    private func persistStoredWatched(_ history: AppleWatchedHistory, notify: Bool) {
        let barriers = ApplePlaybackConvergence.terminals(configurationPlaybackTerminals(), watched: history.watched,
            unwatched: history.tombstones, removals: [:], activity: [:])
        defaults.set(try? JSONEncoder().encode(barriers), forKey: terminalKey)
        let bounded = ApplePlaybackConvergence.history(history, terminals: barriers).newest(Self.watchedHistoryLimit)
        watchedCache = bounded.watched
        watchedCachedData = try? JSONEncoder().encode(bounded.watched)
        unwatchedCache = bounded.tombstones
        unwatchedCachedData = try? JSONEncoder().encode(bounded.tombstones)
        defaults.set(watchedCachedData, forKey: watchedKey)
        defaults.set(unwatchedCachedData, forKey: unwatchedKey)
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

    func configurationContinueWatchingRemovals() -> [String: Date] {
        configurationPlaybackTerminals().compactMapValues { event in
            guard let removed = event.removedAt,
                  AppleContinueWatchingRemovalPolicy.isRemoved(removedAt: removed, lastPlayedAt: event.playedAt) else { return nil }
            return removed
        }
    }

    /// Merges a backup's or another device's removals into this one: the
    /// newest removal per title wins.
    func restoreConfigurationContinueWatchingRemovals(_ incoming: [String: Date]) {
        guard !incoming.isEmpty else { return }
        var normalized: [String: Date] = [:]
        for (key, date) in incoming {
            guard let storageKey = ApplePlaybackIdentity.storageKey(for: key) else { continue }
            normalized[storageKey] = max(normalized[storageKey] ?? date, date)
        }
        restoreConfigurationPlaybackTerminals(ApplePlaybackConvergence.terminals([:], watched: [:], unwatched: [:],
            removals: normalized, activity: [:]))
        let current = continueWatchingRemovals()
        let merged = AppleContinueWatchingRemovalPolicy.merged(current, normalized)
        guard merged != current else { return }
        persistRemovals(merged)
    }

    private func continueWatchingRemovals() -> [String: Date] {
        let storedData = defaults.data(forKey: continueWatchingRemovedKey)
        if let removedCache, removedCachedData == storedData { return removedCache }
        let decoded = storedData.flatMap { try? JSONDecoder().decode([String: Date].self, from: $0) } ?? [:]
        removedCache = decoded
        removedCachedData = storedData
        return decoded
    }

    private func persistRemovals(_ removals: [String: Date], notify: Bool = true) {
        let terminals = ApplePlaybackConvergence.terminals(configurationPlaybackTerminals(), watched: [:], unwatched: [:],
            removals: removals, activity: [:])
        defaults.set(try? JSONEncoder().encode(terminals), forKey: terminalKey)
        let bounded = Self.boundedWatchedHistory(removals, limit: Self.continueWatchingRemovalLimit)
        removedCache = bounded
        removedCachedData = bounded.isEmpty ? nil : try? JSONEncoder().encode(bounded)
        if let removedCachedData { defaults.set(removedCachedData, forKey: continueWatchingRemovedKey) }
        else { defaults.removeObject(forKey: continueWatchingRemovedKey) }
        if notify { ApplePlaybackProgressFeed.shared.storeDidChange() }
    }

    /// Merges a backup's or another device's resume positions into this one:
    /// per title the freshest `updatedAt` wins, so a snapshot written before
    /// this device's last play never winds it back (V6).
    func restoreConfigurationProgress(_ incoming: [String: ApplePlaybackProgress]) {
        var normalized: [String: ApplePlaybackProgress] = [:]
        for (key, value) in incoming {
            guard let storageKey = ApplePlaybackIdentity.storageKey(for: key) else { continue }
            normalized[storageKey] = normalized[storageKey].map { ApplePlaybackConvergence.freshest($0, value) } ?? value
        }
        // Preserve complete legacy entries as activity before their resume is removed.
        let completions = normalized.filter { $0.value.isComplete }
        restoreConfigurationPlaybackActivity(completions)
        var watched: [String: Date] = [:]
        for (key, value) in completions {
            let finished = value.partID.flatMap(ApplePlaybackIdentity.storageKey(for:)) ?? key
            watched[finished] = max(watched[finished] ?? .distantPast, value.updatedAt)
        }
        restoreConfigurationWatchedHistory(watched)
        persist(ApplePlaybackConvergence.reconciled(entries().merging(normalized, uniquingKeysWith: ApplePlaybackConvergence.freshest),
            terminals: configurationPlaybackTerminals()))
    }

    /// Backups and iCloud always read and write the stored history, never a
    /// review build's in-memory fixture.
    func configurationWatchedHistory() -> [String: Date] {
        let history = storedWatchedHistory()
        return ApplePlaybackConvergence.history(history, terminals: configurationPlaybackTerminals()).watched
    }

    func configurationWatchedTombstones() -> [String: Date] { storedWatchedHistory().tombstones }

    /// Merges a backup's or another device's watched history into this one:
    /// the newest event per title wins, including un-watch events.
    func restoreConfigurationWatchedHistory(_ incoming: [String: Date], tombstones: [String: Date] = [:]) {
        guard !incoming.isEmpty || !tombstones.isEmpty else { return }
        let current = storedWatchedHistory()
        var normalized = AppleWatchedHistory()
        for (key, date) in incoming {
            guard let storageKey = ApplePlaybackIdentity.storageKey(for: key) else { continue }
            normalized.merge(watched: [storageKey: date], tombstones: [:])
        }
        for (key, date) in tombstones {
            guard let storageKey = ApplePlaybackIdentity.storageKey(for: key) else { continue }
            normalized.merge(watched: [:], tombstones: [storageKey: date])
        }
        var merged = current
        merged.merge(watched: normalized.watched, tombstones: normalized.tombstones)
        restoreConfigurationPlaybackTerminals(ApplePlaybackConvergence.terminals([:], watched: normalized.watched,
            unwatched: normalized.tombstones, removals: [:], activity: [:]))
        guard merged.watched != current.watched || merged.tombstones != current.tombstones else { return }
        persistStoredWatched(merged, notify: true)
    }

    /// The additive terminal key is also the migration marker. Preserve a
    /// legacy completed episode's part/activity before reconciling its resume,
    /// and do this once so constructing stores during rendering stays cheap.
    private func migrateLegacyPlaybackStateIfNeeded() {
        guard defaults.data(forKey: terminalKey) == nil else { return }
        let progress = entries()
        var activity: [String: ApplePlaybackProgress] = [:]
        for (key, value) in rawActivities() {
            guard let key = ApplePlaybackIdentity.storageKey(for: key) else { continue }
            activity[key] = activity[key].map { ApplePlaybackConvergence.freshest($0, value) } ?? value
        }
        func dates(_ values: [String: Date]) -> [String: Date] {
            var normalized: [String: Date] = [:]
            for (key, date) in values {
                guard let key = ApplePlaybackIdentity.storageKey(for: key) else { continue }
                normalized[key] = max(normalized[key] ?? .distantPast, date)
            }
            return normalized
        }
        var history = AppleWatchedHistory(watched: dates(storedWatchedEntries()), tombstones: dates(storedWatchedTombstones()))
        for (key, value) in progress where value.isComplete {
            activity[key] = activity[key].map { ApplePlaybackConvergence.freshest($0, value) } ?? value
            let finished = value.partID.flatMap(ApplePlaybackIdentity.storageKey(for:)) ?? key
            history.merge(watched: [finished: value.updatedAt], tombstones: [:])
        }
        let terminals = ApplePlaybackConvergence.terminals([:], watched: history.watched, unwatched: history.tombstones,
            removals: dates(continueWatchingRemovals()), activity: activity.merging(progress, uniquingKeysWith: ApplePlaybackConvergence.freshest))
        defaults.set(try? JSONEncoder().encode(terminals), forKey: terminalKey)
        // Fresh installs need only the marker; leave absent legacy blobs absent.
        guard !progress.isEmpty || !activity.isEmpty || !history.watched.isEmpty || !history.tombstones.isEmpty else { return }
        activityCache = activity
        activityData = try? JSONEncoder().encode(activity)
        defaults.set(activityData, forKey: activityKey)
        persistStoredWatched(history, notify: false)
        let reconciled = ApplePlaybackConvergence.reconciled(progress, terminals: terminals)
        cache = reconciled
        cachedData = try? JSONEncoder().encode(reconciled)
        defaults.set(cachedData, forKey: key)
    }

    func configurationPlaybackActivity() -> [String: ApplePlaybackProgress] { activities() }

    func configurationPlaybackTerminals() -> [String: ApplePlaybackTerminalEvents] {
        let explicit = defaults.data(forKey: terminalKey).flatMap {
            try? JSONDecoder().decode([String: ApplePlaybackTerminalEvents].self, from: $0)
        } ?? [:]
        return ApplePlaybackConvergence.terminals(explicit, watched: storedWatchedEntries(),
            unwatched: storedWatchedTombstones(), removals: continueWatchingRemovals(),
            activity: rawActivities().merging(entries(), uniquingKeysWith: ApplePlaybackConvergence.freshest))
    }

    func hasLocalPlaybackState(mediaID: String) -> Bool {
        guard let key = ApplePlaybackIdentity.storageKey(for: mediaID) else { return false }
        return entries()[key] != nil || activities()[key] != nil || configurationPlaybackTerminals()[key] != nil
    }

    private func recordTerminal(_ key: String, _ event: ApplePlaybackTerminalEvents) {
        var values = configurationPlaybackTerminals()
        values[key] = (values[key] ?? .init()).merging(event)
        defaults.set(try? JSONEncoder().encode(values), forKey: terminalKey)
    }

    func restoreConfigurationPlaybackTerminals(_ incoming: [String: ApplePlaybackTerminalEvents]) {
        var values = configurationPlaybackTerminals()
        for (key, event) in incoming {
            guard let key = ApplePlaybackIdentity.storageKey(for: key) else { continue }
            values[key] = (values[key] ?? .init()).merging(event)
        }
        defaults.set(try? JSONEncoder().encode(values), forKey: terminalKey)
        reconcileStoredProgress()
    }

    func restoreConfigurationPlaybackActivity(_ incoming: [String: ApplePlaybackProgress]) {
        var values = activities()
        for (key, value) in incoming {
            guard let key = ApplePlaybackIdentity.storageKey(for: key) else { continue }
            values[key] = values[key].map { ApplePlaybackConvergence.freshest($0, value) } ?? value
        }
        // Materialize barriers before activity's ordinary size limit can retire them.
        restoreConfigurationPlaybackTerminals(ApplePlaybackConvergence.terminals([:], watched: [:], unwatched: [:], removals: [:], activity: values))
        values = Dictionary(uniqueKeysWithValues: values.sorted {
            $0.value.updatedAt == $1.value.updatedAt ? $0.key < $1.key : $0.value.updatedAt > $1.value.updatedAt
        }.prefix(Self.watchedHistoryLimit).map { ($0.key, $0.value) })
        activityCache = values
        activityData = try? JSONEncoder().encode(values)
        defaults.set(activityData, forKey: activityKey)
    }

    private func reconcileStoredProgress() {
        let current = entries()
        let reconciled = ApplePlaybackConvergence.reconciled(current, terminals: configurationPlaybackTerminals())
        if current != reconciled { persist(reconciled) }
    }

    private func persist(_ entries: [String: ApplePlaybackProgress]) {
        cache = entries
        cachedData = try? JSONEncoder().encode(entries)
        defaults.set(cachedData, forKey: key)
        ApplePlaybackProgressFeed.shared.storeDidChange()
    }
}

/// Continue Watching's "Remove" rule: a removed title stays off the row
/// until it is played after the removal. Progress and history are untouched.
enum AppleContinueWatchingRemovalPolicy {
    static func isRemoved(removedAt: Date?, lastPlayedAt: Date?) -> Bool {
        guard let removedAt else { return false }
        return (lastPlayedAt ?? .distantPast) <= removedAt
    }

    /// The newest removal per title, from two devices or a backup.
    static func merged(_ current: [String: Date], _ incoming: [String: Date]) -> [String: Date] {
        current.merging(incoming) { max($0, $1) }
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
