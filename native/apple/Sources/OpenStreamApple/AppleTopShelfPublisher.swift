import Foundation

/// Observes `AppleCatalogStore.sections` and `AppleMediaIndexStore.records`
/// and republishes the Top Shelf snapshot whenever either changes, so
/// "Top Picks" stays in sync with the first catalog shelf the same way
/// Continue Watching stays in sync with playback progress. Whoever owns
/// those two store instances (currently `OpenStreamRootView`) should call
/// `publish` from a `.task`/`.onChange` for each.
@MainActor
public final class AppleTopShelfPublisher {
    public static let shared = AppleTopShelfPublisher()

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
        enabled: Bool,
        playbackStore: ApplePlaybackStore = ApplePlaybackStore()
    ) async {
        let digest = Self.digest(records: records, sections: sections, sources: sources, enabled: enabled)
        guard digest != lastDigest else { return }
        lastDigest = digest
        var watchedAt: [String: Date] = [:]
        for record in records where (record.progress ?? 0) > 0 {
            if let updatedAt = playbackStore.progress(for: record.id)?.updatedAt { watchedAt[record.id] = updatedAt }
        }
        try? await writer.write(records: records, sections: sections, sources: sources,
                                watchedAt: watchedAt, enabled: enabled)
    }

    private static func digest(
        records: [AppleMediaRecord],
        sections: [AppleCatalogSection],
        sources: [AppleSource],
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
        return ApplePlaybackIdentity.digest(for: [
            enabled ? "1" : "0", recordsKey, topPicksKey, shelvesKey, sourcesKey,
        ].joined(separator: "\u{1f}"))
    }
}
