import Foundation
import os

/// Which in-progress titles Continue Watching lists, in what order, and what
/// each one opens — one rule for Discover's row and the Top Shelf snapshot.
///
/// Discover used to list a record only when a loaded shelf still carried its
/// exact item, so a title the viewer was part-way into vanished from the row
/// once its add-on stopped featuring it, while the Top Shelf — which never
/// checked — kept showing it (N51 finding, N52). Both now resolve a record
/// the way Search does (`AppleCatalogSearchLookup`, N51 #7): the record id,
/// then the listed item any of its merged sources names, then a title page
/// rebuilt from its IMDb id when its add-on is enabled. What still cannot
/// open is hidden everywhere, and why is logged once.
enum AppleContinueWatchingResolver {
    /// How many titles a Continue Watching row shows.
    static let maximumCount = 12

    enum Resolution: Equatable, Sendable {
        /// A loaded shelf lists the title, by the record id or by one of its
        /// merged sources.
        case listed(AppleCatalogSearchMatch)
        /// No shelf lists it; its title page is rebuilt from the IMDb id.
        case rebuilt(AppleCatalogSearchMatch)
        /// A library file, server title or channel. These open their own
        /// pages: Library's Continue Watching and the Top Shelf list them,
        /// Discover's catalog row does not.
        case notCatalog
        /// A catalog title nothing can open.
        case unavailable(Reason)

        var match: AppleCatalogSearchMatch? {
            switch self {
            case .listed(let match), .rebuilt(let match): match
            case .notCatalog, .unavailable: nil
            }
        }

        var isAvailable: Bool {
            if case .unavailable = self { false } else { true }
        }
    }

    enum Reason: String, Equatable, Sendable {
        /// Every add-on the record came from is removed or disabled.
        case sourceUnavailable = "its add-on is removed or disabled"
        /// Its add-on is enabled, but no loaded shelf lists the title and the
        /// record has no IMDb id to rebuild a title page from.
        case unlistedWithoutIMDbID = "no loaded shelf lists it and it has no IMDb id"
    }

    struct Entry: Equatable, Sendable {
        let record: AppleMediaRecord
        let resolution: Resolution
    }

    /// Records the viewer is part-way into, most recently watched first.
    static func inProgress(
        _ records: [AppleMediaRecord],
        watchedAt: (AppleMediaRecord) -> Date
    ) -> [AppleMediaRecord] {
        let unfinished = records.filter {
            ($0.progress ?? 0) > 0 && ($0.progress ?? 1) < ApplePlaybackProgress.completionFraction
        }
        let dates = Dictionary(unfinished.map { ($0.id, watchedAt($0)) }, uniquingKeysWith: max)
        return unfinished.sorted { lhs, rhs in
            let lhsDate = dates[lhs.id] ?? .distantPast
            let rhsDate = dates[rhs.id] ?? .distantPast
            return lhsDate == rhsDate ? lhs.id < rhs.id : lhsDate > rhsDate
        }
    }

    static func resolve(_ record: AppleMediaRecord, in lookups: [AppleCatalogSearchLookup]) -> Resolution {
        if let match = lookups.lazy.compactMap({ $0.match(for: record) }).first {
            return .listed(match)
        }
        if let match = lookups.lazy.compactMap({ $0.rebuiltMatch(for: record) }).first {
            return .rebuilt(match)
        }
        guard !AppleCatalogSearchLookup.listsUnmatched(record) else { return .notCatalog }
        return lookups.contains { $0.hasActiveCatalogSource(for: record) }
            ? .unavailable(.unlistedWithoutIMDbID)
            : .unavailable(.sourceUnavailable)
    }

    /// `records` resolved in order. Two records that open the same title
    /// keep only the more recent one, so a row never shows a title twice.
    static func entries(
        _ records: [AppleMediaRecord],
        in lookups: [AppleCatalogSearchLookup]
    ) -> [Entry] {
        var seenItemIDs = Set<String>()
        return records.compactMap { record in
            let resolution = resolve(record, in: lookups)
            if let match = resolution.match {
                guard seenItemIDs.insert(match.item.id).inserted else { return nil }
            }
            return Entry(record: record, resolution: resolution)
        }
    }

    private static let logger = Logger(subsystem: "com.orgista.openstream", category: "continue-watching")
    private static let loggedHidden = OSAllocatedUnfairLock(initialState: Set<String>())

    /// Logs each hidden record once per launch, with the reason — never the
    /// title, which is the viewer's own history.
    static func logHidden(_ entries: [Entry]) {
        for entry in entries {
            guard case .unavailable(let reason) = entry.resolution else { continue }
            let key = "\(entry.record.id)|\(reason.rawValue)"
            guard loggedHidden.withLock({ $0.insert(key).inserted }) else { continue }
            logger.notice(
                "hidden record \(entry.record.id.prefix(12), privacy: .public): \(reason.rawValue, privacy: .public)"
            )
        }
    }
}
