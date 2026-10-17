import Foundation
import OSLog

/// Observes `AppleCatalogStore.sections` and `AppleMediaIndexStore.records`
/// and republishes the Top Shelf snapshot whenever either changes, so
/// "Top Picks" stays in sync with the first catalog shelf the same way
/// Continue Watching stays in sync with playback progress. Whoever owns
/// those two store instances (currently `OpenStreamRootView`) should call
/// `publish` from a `.task`/`.onChange` for each.
@MainActor
public final class AppleTopShelfPublisher {
    public static let shared = AppleTopShelfPublisher()
    private static let logger = Logger(subsystem: "com.orgista.openstream.topshelf", category: "publisher")

    private let writer: AppleTopShelfSnapshotWriter
    private var lastDigest: String?

    public init(writer: AppleTopShelfSnapshotWriter = .shared) {
        self.writer = writer
    }

    /// Cheap no-op when nothing relevant changed since the last publish; the
    /// actual file write happens on `AppleTopShelfSnapshotWriter`, off the
    /// main actor.
    ///
    /// `sources` decide which Continue Watching titles can open, exactly as
    /// Discover's row decides it, and playback progress supplies the
    /// most-recent-first order (N52).
    public func publish(
        records: [AppleMediaRecord],
        sections: [AppleCatalogSection],
        sources: [AppleSource],
        heroes: [AppleTopShelfHero] = [],
        enabled: Bool,
        playbackStore: ApplePlaybackStore = ApplePlaybackStore()
    ) async {
        var watchedAt: [String: Date] = [:]
        var savedProgress: [String: ApplePlaybackProgress] = [:]
        var activity: [String: ApplePlaybackProgress] = [:]
        var successorAvailable = Set<String>()
        var removals: [String: Date] = [:]
        let episodesByKey = await playbackStore.availableEpisodes()
        let completionProgress = playbackStore.completionProgress()
        for record in records {
            if let latest = playbackStore.lastActivity(for: record.id) { activity[record.id] = latest }
            if playbackStore.isRemovedFromContinueWatching(mediaID: record.id) { removals[record.id] = .distantFuture }
            if record.kind == .series, let key = ApplePlaybackIdentity.storageKey(for: record.id) {
                let episodes = episodesByKey[key] ?? []
                if !episodes.isEmpty, AppleCompletionPolicy.successor(after: activity[record.id]?.partID, episodes: episodes,
                    completedIDs: playbackStore.completedMediaIDs(among: episodes.map(\.id), progress: completionProgress)) != nil {
                    successorAvailable.insert(record.id)
                }
            }
            guard let saved = playbackStore.progress(for: record.id) else { continue }
            watchedAt[record.id] = saved.updatedAt
            savedProgress[record.id] = saved
        }
        let digest = Self.digest(records: records, sections: sections, sources: sources,
                                 savedProgress: savedProgress, enabled: enabled)
            + "|activity:\(ApplePlaybackProgressFeed.shared.revision)|successors:\(successorAvailable.sorted())|removed:\(removals.keys.sorted())"
            + "|heroes:" + heroes.map { "\($0.item.id)#\($0.backdropURL?.absoluteString ?? "")#\($0.wordmarkURL?.absoluteString ?? "")" }
                .joined(separator: ",")
        let live = AppleLiveSystemChannels.shared
        let sourceIDs = Set(sources.filter { $0.kind == .liveTV && $0.isEnabled }.map(\.id))
        let favorites = AppleLiveSystemChannels.supported(live.favorites, sourceIDs: sourceIDs)
        let recents = AppleLiveSystemChannels.supported(live.recents, sourceIDs: sourceIDs)
        let liveDigest = ApplePlaybackIdentity.digest(for: String(decoding: (try? JSONEncoder().encode([favorites, recents])) ?? Data(), as: UTF8.self))
        let combinedDigest = digest + liveDigest
        let snapshotExists = enabled ? await writer.snapshotExists() : true
        guard combinedDigest != lastDigest || !snapshotExists else { return }
        do {
            try await writer.write(records: records, sections: sections, sources: sources,
                                   watchedAt: watchedAt, savedProgress: savedProgress, activity: activity,
                                   successorAvailable: successorAvailable, removedAt: removals,
                                   favoriteChannels: favorites, recentChannels: recents, heroes: heroes, enabled: enabled)
            // Only a completed write/removal may suppress the next identical publish.
            lastDigest = combinedDigest
        } catch is CancellationError {
            // A newer publish replaced this one.
        } catch {
            let failure: String
            if error is AppleTopShelfSnapshotWriter.WriteError {
                failure = "Top Shelf snapshot publish failed: no app-group container"
            } else {
                // Error descriptions can include paths or payloads; codes are enough to diagnose I/O.
                let error = error as NSError
                failure = "Top Shelf snapshot \(enabled ? "write" : "removal") failed: \(error.domain) code=\(error.code)"
            }
            AppleInteractionTrace.record(.failure, failure)
            Self.logger.error("\(failure, privacy: .public)")
        }
    }

    private static func digest(
        records: [AppleMediaRecord],
        sections: [AppleCatalogSection],
        sources: [AppleSource],
        savedProgress: [String: ApplePlaybackProgress] = [:],
        enabled: Bool
    ) -> String {
        let recordsKey = records
            // The saved backdrop is the tile's art once a title leaves the shelves
            // (review of 0627624).
            .map { "\($0.id)|\($0.isFavorite)|\($0.progress ?? -1)|\($0.lastVerified.timeIntervalSince1970)|\($0.backdropURL?.absoluteString ?? "")" }
            .joined(separator: ",")
        let topPicksKey = sections.first(where: { !$0.items.isEmpty })?
            .items.prefix(10).map(\.id).joined(separator: ",") ?? ""
        // Continue Watching takes its backdrops from any shelf, so a catalog
        // arriving after the records has to publish again.
        let shelvesKey = sections.map { "\($0.id)#\($0.items.count)" }.joined(separator: ",")
        // Enabling or removing an add-on changes what Continue Watching can open.
        let sourcesKey = sources.map { "\($0.id.uuidString)#\($0.isEnabled)#\($0.kind)" }.joined(separator: ",")
        // The bars and the order follow the playback store, which moves between index syncs
        // (review of 2b1f930).
        let progressKey = savedProgress.sorted { $0.key < $1.key }
            .map { "\($0.key)|\($0.value.position)|\($0.value.duration)|\($0.value.partID ?? "")|\($0.value.updatedAt.timeIntervalSince1970)" }
            .joined(separator: ",")
        return ApplePlaybackIdentity.digest(for: [
            enabled ? "1" : "0", recordsKey, topPicksKey, shelvesKey, sourcesKey, progressKey,
        ].joined(separator: "\u{1f}"))
    }
}
