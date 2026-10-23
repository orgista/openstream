import Foundation

/// Which in-progress titles Continue Watching lists and in what order — one
/// rule for Discover's row and the Top Shelf snapshot.
enum AppleContinueWatchingResolver {
    static let refreshDelay: Duration = .milliseconds(500)

    /// Incoming membership is authoritative; ordering is stable across refreshes.
    static func merge<Value, Stamp: Comparable>(_ current: [Value], incoming: [Value],
        id: (Value) -> String, timestamp: (Value) -> Stamp) -> [Value] {
        let incomingIDs = Set(incoming.map(id))
        var seen = Set<String>()
        var result = current.filter { incomingIDs.contains(id($0)) && seen.insert(id($0)).inserted }
        var positions = Dictionary(result.enumerated().map { (id($0.element), $0.offset) },
            uniquingKeysWith: { first, _ in first })
        for value in incoming {
            let key = id(value)
            if let index = positions[key] {
                if timestamp(value) > timestamp(result[index]) { result[index] = value }
            } else {
                positions[key] = result.count
                result.append(value)
            }
        }
        return result
    }

    /// How many titles a Continue Watching row shows.
    static let maximumCount = 12

    static func rail<Value>(_ entries: [Value]) -> [Value] {
        Array(entries.prefix(maximumCount))
    }

    static func hasFullList(count: Int) -> Bool { count > maximumCount }

    /// Records the viewer is part-way into, most recently watched first.
    ///
    /// Completed series activity stays only while an available successor exists.
    /// Resume deletion does not delete that activity; exhausted series leave.
    static func inProgress(
        _ records: [AppleMediaRecord],
        saved: (AppleMediaRecord) -> ApplePlaybackProgress? = { _ in nil },
        activity: (AppleMediaRecord) -> ApplePlaybackProgress? = { _ in nil },
        successorAvailable: (AppleMediaRecord) -> Bool = { _ in false },
        removedAt: (AppleMediaRecord) -> Date? = { _ in nil },
        watchedAt: (AppleMediaRecord) -> Date
    ) -> [AppleMediaRecord] {
        let unfinished = records.filter {
            let value = saved($0)
            let latest = activity($0) ?? value
            if latest != nil {
                return AppleCompletionPolicy.includes(saved: value, activity: latest,
                    successorAvailable: $0.kind == .series && successorAvailable($0), removedAt: removedAt($0))
            }
            return !AppleContinueWatchingRemovalPolicy.isRemoved(removedAt: removedAt($0), lastPlayedAt: nil)
                && ($0.progress ?? 0) > 0 && ($0.progress ?? 1) < ApplePlaybackProgress.completionFraction
        }
        let dates = Dictionary(unfinished.map { ($0.id, watchedAt($0)) }, uniquingKeysWith: max)
        return unfinished.sorted { lhs, rhs in
            let lhsDate = dates[lhs.id] ?? .distantPast
            let rhsDate = dates[rhs.id] ?? .distantPast
            return lhsDate == rhsDate ? lhs.id < rhs.id : lhsDate > rhsDate
        }
    }

    static func isUpNext(_ record: AppleMediaRecord, saved: ApplePlaybackProgress?,
                         successorAvailable: Bool = false) -> Bool {
        record.kind == .series && AppleCompletionPolicy.includes(saved: nil, activity: saved,
            successorAvailable: successorAvailable, removedAt: nil)
    }

    /// How far along a Continue Watching card's bar is, 0...1, or nil for
    /// none. One rule for Discover's row (both styles) and the Top Shelf.
    ///
    /// A series keeps one saved position, under the show, and names the
    /// episode in `partID`; that is the episode Resume plays
    /// (`AppleTitlePagePolicy.heroEpisode`), so the bar is that episode's,
    /// read from the store. The record's own `progress` is only a copy made
    /// at the last index sync, and a series entry that names no episode, or
    /// a finished one, resumes nothing: Play starts the next episode from the
    /// beginning, so there is no bar. A film is unchanged: its saved
    /// position, else the record's copy.
    static func progress(isSeries: Bool, saved: ApplePlaybackProgress?, recordProgress: Double?) -> Double? {
        guard let saved else {
            return isSeries ? nil : recordProgress.map { min(max($0, 0), 1) }
        }
        if saved.isComplete { return nil }
        if isSeries, saved.partID == nil || saved.resumePosition == nil { return nil }
        return AppleWatchProgress.fraction(position: saved.position, duration: saved.duration)
    }

    /// Server catalog records are resolvable; the enabled server supplies their page.
    static func isOpenable(_ record: AppleMediaRecord, sources: [AppleSource]) -> Bool {
        AppleCatalogSearchStore.listsUnmatched(record)
            || AppleCatalogSearchMatch.mediaServer(record, sources: sources) != nil
            || record.availability.contains { route in
                route.capability == .resolvable && route.mediaServerItemID == nil
                    && sources.contains { $0.id == route.instanceID && $0.isEnabled && !$0.needsSignIn && $0.kind == .mediaServer }
            }
    }
}
