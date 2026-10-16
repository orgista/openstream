import Foundation
import Observation
import SwiftUI

/// Shared discovery and playback identity for Folder, SMB and downloaded files.
@MainActor @Observable
final class AppleLocalLibraryStore {
    static let shared = AppleLocalLibraryStore()
    #if DEBUG
    /// False under the Library titles fixture (`AppleLibraryTitlesDebugView`):
    /// a fixture scan must never replace the real library's snapshot or its
    /// last-scan stamp, which live in the same container.
    static var persistsScanResults = true
    #else
    static let persistsScanResults = true
    #endif
    static let downloadsID = UUID(uuidString: "EB7EF704-5724-4CEB-88B9-2860E474BD70")!
    private(set) var groups: [AppleLibrarySeries] = []
    private(set) var sources: [AppleSource] = []
    private(set) var metadata: [String: AppleCatalogItem] = [:]
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private(set) var progress: [String: ApplePlaybackProgress] = [:]
    private var offlineIDs: [String: String] = [:]
    private var episodesByGroup: [String: [AppleStremioEpisode]] = [:]

    private let metadataResolver: AppleLibraryMetadataResolver
    private let injectedPlaybackStore: ApplePlaybackStore?
    private var playbackStore: ApplePlaybackStore { injectedPlaybackStore ?? ApplePlaybackStore() }
    @ObservationIgnored private var recordedIdentityFileIDs: Set<String> = []

    init(resolver: AppleLibraryMetadataResolver = .shared, playbackStore: ApplePlaybackStore? = nil,
         groups: [AppleLibrarySeries] = [], sources: [AppleSource] = [], offlineIDs: [String: String] = [:], versionCacheURL: URL? = nil) {
        metadataResolver = resolver
        injectedPlaybackStore = playbackStore
        self.groups = groups
        self.sources = sources
        self.offlineIDs = offlineIDs
        self.mediaVersionCache = versionCacheURL.map { AppleMediaVersionCache(url: $0) } ?? .shared
    }

    @concurrent nonisolated private static func episodeCandidates(groups: [AppleLibrarySeries], sources: [AppleSource],
        offlineIDs: [String: String]) async -> [String: [AppleStremioEpisode]] {
        let sourcesByID = Dictionary(sources.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
        return Dictionary(uniqueKeysWithValues: groups.filter { $0.parsed.kind == .show }.map { group in
            let episodes = group.items.filter { AppleLibraryParseMemo.parse($0).role == .feature }.map { file in
                let parsed = AppleLibraryParseMemo.parse(file)
                let id = offlineIDs[file.id] ?? sourcesByID[file.sourceID].map {
                    AppleMediaIngestion.libraryRecord(source: $0, item: file).id
                } ?? file.id
                return AppleStremioEpisode(id: id, title: "", season: parsed.episodeNumbers.isEmpty ? nil : parsed.season,
                    episode: parsed.episodeNumbers.last, releaseInfo: parsed.airDate)
            }
            return (group.id, episodes)
        })
    }
    private(set) var staleSourceIDs: Set<UUID> = []
    private(set) var lastSuccessfulScanBySource: [UUID: Date] = [:]
    private(set) var lastScan: Date?
    
    /// The last scan's groups, kept to the active sources; nil without a
    /// readable snapshot. Off the main actor: reading and decoding ~1,500
    /// files held Home's first second on an Apple TV 4K (2026-10-16).
    @concurrent nonisolated private static func persistedGroups(activeSourceIDs: Set<UUID>) async -> [AppleLibrarySeries]? {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("OpenStream")
        guard let data = try? Data(contentsOf: caches.appendingPathComponent("LibraryGroups-v1.json")),
              let snapshots = try? JSONDecoder().decode([AppleLibraryGroupSnapshot].self, from: data) else { return nil }
        return snapshots.compactMap { snapshot in
            let activeItems = snapshot.items.filter { activeSourceIDs.contains($0.sourceID) }
            guard !activeItems.isEmpty else { return nil }
            let parsed = AppleLibraryTitle(title: snapshot.title, year: snapshot.year, season: nil, episode: nil, kind: snapshot.kind)
            let items = activeItems.map { AppleLibraryItem(sourceID: $0.sourceID, name: $0.name, url: $0.url, relativePath: $0.relativePath, sizeBytes: $0.sizeBytes, addedAt: $0.addedAt) }
            return AppleLibrarySeries(id: snapshot.id, parsed: parsed, items: items)
        }
    }

    struct AppleLibraryGroupSnapshot: Codable {
        let id: String
        let title: String
        let year: Int?
        let kind: AppleLibraryTitle.Kind
        struct Item: Codable {
            let id: String
            let sourceID: UUID
            let name: String
            let url: URL
            let relativePath: String
            let sizeBytes: Int64
            let addedAt: Date
        }
        let items: [Item]
    }

    /// Reset OpenStream: the saved index is gone, so is this copy.
    func discardAfterReset() {
        groups = []
        sources = []
        metadata = [:]
        isLoading = false
        errorMessage = nil
        progress = [:]
        offlineIDs = [:]
        recordedIdentityFileIDs = []
        versionItemIDs = [:]
        episodesByGroup = [:]
        lastScan = nil
        staleSourceIDs = []
        lastSuccessfulScanBySource = [:]
        contentDidChange()
    }

    func publishPersistedIndex(activeSources: [AppleSource]) async -> Bool {
        guard let realGroups = await Self.persistedGroups(activeSourceIDs: Set(activeSources.map(\.id))) else {
            appleTrace("library persisted index unusable: no snapshot found")
            return false
        }
        guard !realGroups.isEmpty else {
            appleTrace("library persisted index unusable: empty after filtering")
            return false
        }
        let publishedCount = realGroups.count
        
        // Known matches go out with the groups: published bare, the Library
        // hero drew one title and then rebuilt with another page first when
        // the scan merged the same cache ~6 s later.
        let cached = await metadataResolver.cachedMetadata(for: realGroups)
        self.sources = activeSources
        self.groups = realGroups
        metadata.merge(cached) { _, persisted in persisted }
        contentDidChange()
        appleTrace("library published from persisted index: \(publishedCount) titles, \(cached.count) cached matches")
        // Episode lists and Continue Watching's next-episode check redraw
        // when these land; parsing every show file first held all the titles
        // back ~1.5 s on an Apple TV 4K (2026-10-16).
        let episodes = await Self.episodeCandidates(groups: realGroups, sources: activeSources, offlineIDs: [:])
        guard !Task.isCancelled else { return true }
        episodesByGroup = episodes
        await recordAllIdentityAliases()
        return true
    }
    /// Bumped whenever `groups` or `metadata` changes, so `sortedCache` knows
    /// when its answer is stale. `@Observable` forbids property observers, so
    /// every mutation site calls `contentDidChange()` by hand.
    private(set) var contentRevision = 0
    @ObservationIgnored private var sortedCache: [AppleLibrarySort: (revision: Int, value: [AppleLibrarySeries])] = [:]

    private func contentDidChange() {
        contentRevision &+= 1
        sortedCache.removeAll(keepingCapacity: true)
        publishDiscKeys()
    }

    /// Groups holding a disc image (`AppleDiscImagePolicy`), worked out once
    /// per scan rather than on every metadata change.
    @ObservationIgnored private var discGroupIDs: Set<String> = []
    @ObservationIgnored private var discGroupSignature = -1

    /// The catalog keys whose posters carry the disc badge: each disc
    /// group's own card and the title it resolved to, so Discover, Search and
    /// Library all mark it.
    private func publishDiscKeys() {
        let signature = groups.count &+ groups.reduce(0) { $0 &+ $1.items.count }
        if signature != discGroupSignature {
            discGroupSignature = signature
            discGroupIDs = Set(groups.filter { $0.items.contains(where: AppleDiscImagePolicy.isDiscImage) }.map(\.id))
        }
        var keys = Set<String>()
        for group in groups where discGroupIDs.contains(group.id) {
            let item = catalogItem(for: group)
            keys.insert(item.id)
            keys.insert(AppleDiscCatalog.matchKey(item))
        }
        AppleDiscCatalog.shared.replaceKeys(keys)
    }

    /// The disc file among a title's files, if any.
    func discFile(in files: [AppleLibraryItem]) -> AppleLibraryItem? {
        files.first(where: AppleDiscImagePolicy.isDiscImage)
    }

    /// What a local file is, read once per file: the engine's probe for the
    /// format badges, and for a disc image the titles on it. Only files on
    /// this device (a folder or a download), never a share: no network.
    @ObservationIgnored private var inspections: [String: AppleLocalFileInspection] = [:]

    func inspection(for file: AppleLibraryItem) async -> AppleLocalFileInspection? {
        if let cached = inspections[file.id] { return cached }
        guard file.url.isFileURL, let source = sources.first(where: { $0.id == file.sourceID }),
              source.kind == .library else { return nil }
        let root = file.sourceID == Self.downloadsID ? nil : try? AppleLibraryBookmark.resolve(source)
        let url = file.url
        let isDisc = AppleDiscImagePolicy.isDiscImage(file)
        let result = await Task.detached(priority: .utility) { () -> AppleLocalFileInspection in
            let access = root.map { AppleSecurityScopedAccess(url: $0) }
            defer { withExtendedLifetime(access) {} }
            return AppleLocalFileInspection.inspect(url: url, isDisc: isDisc)
        }.value
        inspections[file.id] = result
        if !result.discTitles.isEmpty { AppleDiscCatalog.shared.record(result.discTitles, for: url) }
        if let format = result.discFormat { AppleDiscCatalog.shared.record(format, for: url) }
        appleTrace("local inspect \(url.lastPathComponent.suffix(40)): badges=\(result.badges.map(\.title)) discTitles=\(result.discTitles.count)")
        return result
    }

    static func matches(_ lhs: AppleCatalogItem, _ rhs: AppleCatalogItem) -> Bool {
        guard lhs.type == rhs.type else { return false }
        if lhs.mediaID.hasPrefix("tt"), rhs.mediaID.hasPrefix("tt") { return lhs.mediaID == rhs.mediaID }
        return normalized(lhs.name) == normalized(rhs.name)
            && String((lhs.releaseInfo ?? "").prefix(4)) == String((rhs.releaseInfo ?? "").prefix(4))
    }
    private static func normalized(_ title: String) -> String {
        title.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .components(separatedBy: CharacterSet.alphanumerics.inverted).joined()
    }
    func catalogItem(for group: AppleLibrarySeries) -> AppleCatalogItem {
        metadata[group.id] ?? AppleCatalogItem(mediaID: "local-" + ApplePlaybackIdentity.digest(for: group.id),
            type: group.parsed.kind == .show ? "series" : "movie", name: group.parsed.title,
            releaseInfo: group.parsed.year.map(String.init))
    }
    /// `matches(_:_:)` against every group, answered from `matchIndex()`.
    func matchingGroups(_ item: AppleCatalogItem) -> [AppleLibrarySeries] {
        let index = matchIndex()
        let byName = index.byName[Self.nameKey(item)] ?? []
        guard item.mediaID.hasPrefix("tt") else { return byName.map { groups[$0] } }
        // An IMDb id on both sides decides alone; a group without one still matches by name.
        let positions = Set(index.byIMDb["\(item.type):\(item.mediaID)"] ?? [])
            .union(byName.filter { !index.hasIMDb[$0] })
        return positions.sorted().map { groups[$0] }
    }

    private struct MatchIndex {
        let revision: Int
        var byIMDb: [String: [Int]] = [:]
        var byName: [String: [Int]] = [:]
        var hasIMDb: [Bool] = []
    }
    @ObservationIgnored private var matchIndexCache: MatchIndex?

    /// Group positions by IMDb id and by folded name and year, once per
    /// content change. The billboard asks on every redraw, and folding every
    /// title's name there took ~200 ms per pass on an Apple TV 4K (2026-10-15).
    private func matchIndex() -> MatchIndex {
        // Read so the caller's view observes both; the cache key alone is not enough.
        _ = groups
        _ = metadata
        if let matchIndexCache, matchIndexCache.revision == contentRevision { return matchIndexCache }
        var index = MatchIndex(revision: contentRevision)
        for (position, group) in groups.enumerated() {
            let item = catalogItem(for: group)
            let hasIMDb = item.mediaID.hasPrefix("tt")
            index.hasIMDb.append(hasIMDb)
            if hasIMDb { index.byIMDb["\(item.type):\(item.mediaID)", default: []].append(position) }
            index.byName[Self.nameKey(item), default: []].append(position)
        }
        matchIndexCache = index
        return index
    }

    private static func nameKey(_ item: AppleCatalogItem) -> String {
        "\(item.type):\(normalized(item.name)):\((item.releaseInfo ?? "").prefix(4))"
    }
    /// Discover reads this several times per redraw; kept until the content changes, like `sorted(_:)`.
    var resolvedGroups: [AppleLibrarySeries] {
        let ordered = sorted(.added)
        if let resolvedCache, resolvedCache.revision == contentRevision { return resolvedCache.value }
        var seen = Set<String>()
        let value = ordered.filter {
            guard let item = metadata[$0.id] else { return false }
            let key = item.mediaID.hasPrefix("tt") ? item.mediaID : "\(item.type):\(Self.normalized(item.name)):\(item.releaseInfo ?? "")"
            return seen.insert(key).inserted
        }
        resolvedCache = (contentRevision, value)
        return value
    }
    @ObservationIgnored private var resolvedCache: (revision: Int, value: [AppleLibrarySeries])?
    var featured: AppleLibrarySeries? { featuredCandidates.first }

    /// The billboard rotates through these rather than pinning the newest
    /// title, so Library does not open on the same film every time.
    var featuredCandidates: [AppleLibrarySeries] {
        AppleHeroRotation.candidates(
            sorted(.added).filter { $0.parsed.kind == .movie && metadata[$0.id]?.backgroundURL != nil },
            id: \.id
        )
    }
    /// One card per film. Files whose names differ ("Tony.2026.1080p",
    /// "Tony 4K") land in separate groups but resolve to one IMDb title —
    /// N32 #13 drew "Tony" twice. The first in display order stays; the rest
    /// are still found by `matchingGroups`, so the title page lists every
    /// file under Other Sources.
    nonisolated static func collapsingVersions(_ decorated: [(group: AppleLibrarySeries, item: AppleCatalogItem)]) -> [AppleLibrarySeries] {
        var seen = Set<String>()
        return decorated.compactMap { group, item in
            guard group.parsed.kind == .movie, item.mediaID.hasPrefix("tt"),
                  let sourceID = group.items.first?.sourceID else { return group }
            return seen.insert("\(sourceID):\(item.mediaID)").inserted ? group : nil
        }
    }
    /// Decorate once, sort, undecorate — and remember the answer until the
    /// content changes.
    ///
    /// The comparator used to call `catalogItem(for:)` on *both* sides of
    /// every comparison, and a metadata miss there constructs an item and
    /// digests the group id: ~29,000 of those for the owner's 1,397-file
    /// library, on a sort that `AppleLibraryView` asks for five to eight
    /// times per body pass. That is why Library stayed blank for seven
    /// seconds after its scan had already finished at 2.5s, and why scrolling
    /// it crawled (owner, 2026-09-15). Decorating drops it to one call per
    /// group; the memo drops repeat passes to nothing.
    ///
    /// The memo is not observed, so a hit reads `groups` and `metadata` first:
    /// a shelf whose body reads only this still redraws when the scan or a
    /// title's metadata lands.
    func sorted(_ sort: AppleLibrarySort) -> [AppleLibrarySeries] {
        _ = groups
        _ = metadata
        if let cached = sortedCache[sort], cached.revision == contentRevision { return cached.value }
        let decorated = groups.map { (group: $0, item: catalogItem(for: $0)) }
        let ordered = decorated.sorted {
            if sort == .added, $0.group.addedAt != $1.group.addedAt { return $0.group.addedAt > $1.group.addedAt }
            if sort == .year, $0.item.releaseInfo != $1.item.releaseInfo {
                return ($0.item.releaseInfo ?? "") > ($1.item.releaseInfo ?? "")
            }
            return $0.item.name == $1.item.name
                ? $0.group.id < $1.group.id
                : $0.item.name.localizedStandardCompare($1.item.name) == .orderedAscending
        }
        let value = Self.collapsingVersions(ordered)
        sortedCache[sort] = (contentRevision, value)
        return value
    }
    var continueWatching: [AppleLibrarySeries] {
        let store = playbackStore
        let eligible = groups.compactMap { group -> (AppleLibrarySeries, Date)? in
            let files = group.items
            let latest = files.compactMap { file -> (AppleLibraryItem, ApplePlaybackProgress)? in
                store.lastActivity(for: playbackID(file)).map { (file, $0) }
            }.max { $0.1.updatedAt < $1.1.updatedAt }
            guard let (file, activity) = latest else { return nil }
            let successor: Bool
            if group.parsed.kind == .show && activity.isComplete {
                let episodes = episodesByGroup[group.id] ?? []
                successor = AppleCompletionPolicy.successor(after: playbackID(file), episodes: episodes,
                    completedIDs: store.completedMediaIDs(among: episodes.map(\.id))) != nil
            } else { successor = false }
            guard AppleCompletionPolicy.includes(saved: store.progress(for: playbackID(file)), activity: activity,
                successorAvailable: successor, removedAt: store.isRemovedFromContinueWatching(mediaID: playbackID(file)) ? .distantFuture : nil) else { return nil }
            return (group, activity.updatedAt)
        }
        var seen = Set<String>()
        return eligible.sorted { $0.1 > $1.1 }.compactMap { group, _ in
            let identity: String
            if group.parsed.role == .feature, let file = group.items.first, let canonical = versionItemIDs[file.id] {
                identity = group.parsed.kind == .show ? "series:" + (metadata[group.id]?.mediaID ?? group.id) : canonical
            } else { identity = group.id }
            return seen.insert(identity).inserted ? group : nil
        }
    }
    func refreshProgress() {
        let store = playbackStore
        var values: [String: ApplePlaybackProgress] = [:]
        for group in groups {
            for file in group.items {
                if let value = store.progress(for: playbackID(file)), value.resumePosition != nil,
                   value.updatedAt > (values[group.id]?.updatedAt ?? .distantPast) { values[group.id] = value }
            }
        }
        if values != progress { progress = values }
    }
    func playbackID(_ file: AppleLibraryItem) -> String {
        if let id = offlineIDs[file.id] { return id }
        guard let source = sources.first(where: { $0.id == file.sourceID }) else { return file.id }
        return AppleMediaIngestion.libraryRecord(source: source, item: file).id
    }
    func resolve(_ group: AppleLibrarySeries, sourceStore: AppleSourceStore, settings: AppleSettingsStore, refresh: Bool = false) async {
        if refresh { recordedIdentityFileIDs.subtract(group.items.map(\.id)) }
        guard let file = group.items.first else { return }
        if !refresh, metadata[group.id] != nil,
           !(await metadataResolver.needsRevalidation(file, sources: sourceStore.sources,
                tmdbKey: settings.tmdbAPIKey, omdbKey: settings.omdbAPIKey)) {
            playbackStore.recordIdentityAliases(await recordIdentityAliases(for: group, resolvedMediaID: metadata[group.id]?.mediaID))
            return
        }
        do {
            let value = try await metadataResolver.resolve(file, sources: sourceStore.sources,
                tmdbKey: settings.tmdbAPIKey, omdbKey: settings.omdbAPIKey, refresh: refresh)
            guard !Task.isCancelled else { return }
            if metadata[group.id] != value {
                metadata[group.id] = value
                recordedIdentityFileIDs.subtract(group.items.map(\.id))
                contentDidChange()
            }
        } catch {
            // A cancelled or failed lookup leaves the currently published metadata intact.
        }
        playbackStore.recordIdentityAliases(await recordIdentityAliases(for: group, resolvedMediaID: metadata[group.id]?.mediaID))
    }

    /// Every title's aliases in one alias-table write and one version-cache write.
    func recordAllIdentityAliases() async {
        await AppleLibraryParseMemo.warm(groups.flatMap(\.items))
        var entries: [(classID: String, mediaIDs: [String])] = []
        await mediaVersionCache.recordInOneWrite {
            for group in groups {
                entries += await recordIdentityAliases(for: group, resolvedMediaID: metadata[group.id]?.mediaID)
            }
        }
        playbackStore.recordIdentityAliases(entries)
    }

    private func recordIdentityAliases(for group: AppleLibrarySeries, resolvedMediaID: String?) async
        -> [(classID: String, mediaIDs: [String])] {
        let pending = group.items.filter { !recordedIdentityFileIDs.contains($0.id) && offlineIDs[$0.id] == nil }
        guard let first = pending.first else { return [] }
        let match = await metadataResolver.strongMatchIDs(for: first)
        var entries: [(classID: String, mediaIDs: [String])] = []
        var legacySeen = Set<String>()
        let rowIDs: Set<String> = group.parsed.kind == .show
            ? resolvedMediaID.map { id in Set(Self.episodes(group: group, mediaID: id, enriched: []).map(\.id)) } ?? [] : []
        for (index, file) in group.items.enumerated() {
            let parsed = AppleLibraryParseMemo.parse(file)
            let legacy = resolvedMediaID.map { "\($0):\(parsed.season ?? 1):\(parsed.episode ?? index + 1)" }
            let firstLegacy = legacy.map { legacySeen.insert($0).inserted } ?? false
            // Recheck after the actor hop; weak/missing evidence is also deduped.
            guard offlineIDs[file.id] == nil, recordedIdentityFileIDs.insert(file.id).inserted,
                  parsed.role == .feature, file.sizeBytes > 0 else { continue }
            if let match,
               let title = AppleLogicalItemKey.title(kind: match.kind, imdb: match.imdb, tmdb: match.tmdb) {
                let base: String
                if let date = parsed.airDate { base = title + ":d" + date }
                else if parsed.kind == .show, parsed.episodeNumbers.isEmpty { base = playbackID(file) }
                else { base = title }
                if let classID = AppleLogicalItemKey.localFileClass(titleKey: base, season: parsed.season,
                    episode: parsed.episodeNumbers.first, sizeBytes: file.sizeBytes) {
                    entries.append((classID: classID, mediaIDs: [playbackID(file)]))
                }
                if let season = parsed.season, let episode = parsed.episodeNumbers.first {
                    versionItemIDs[file.id] = AppleLogicalItemKey.episode(seriesKey: base, season: season, episode: episode)
                } else { versionItemIDs[file.id] = base }

            }
            let current = Self.fileEpisodeID(file)
            if firstLegacy, let legacy, rowIDs.contains(current) {
                entries.append((classID: AppleLogicalItemKey.legacyEpisodeClass(fileEpisodeID: current),
                    mediaIDs: [current, legacy]))
            }
        }
        var migrated = Set<String>()
        for file in group.items {
            guard let itemID = versionItemIDs[file.id], migrated.insert(itemID).inserted else { continue }
            let versions = mediaVersions(for: file, recordAliases: false)
            let references = Set(versions.flatMap(\.parts).map(\.reference))
            let files = groups.flatMap(\.items).filter { references.contains($0.id) }
            entries.append((classID: itemID, mediaIDs: [itemID] + files.map(playbackID)))
            if group.parsed.kind == .movie {
                let catalog = catalogItem(for: group)
                entries.append((classID: itemID, mediaIDs: [itemID] + AppleTitleProgressIdentity.candidates(
                    item: catalog, sourceID: file.sourceID, resolvedMediaID: resolvedMediaID)))
            }
        }
        return entries
    }

    func reload(sourceStore: AppleSourceStore, mediaIndex: AppleMediaIndexStore, settings: AppleSettingsStore) async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        sources = sourceStore.sources.filter { $0.isEnabled && ($0.kind == .library || $0.kind == .nas) }
        var files: [AppleLibraryItem] = []
        var errors: [String] = []
        var pendingIndexWrites: [(source: AppleSource, items: [AppleLibraryItem], status: AppleLibraryScanStatus)] = []
        for source in sources {
            do {
                let result: AppleLibraryScanResult
                if source.kind == .nas {
                    let credentials = try sourceStore.networkCredentials(for: source) ?? AppleSMBCredentials(username: "", password: "")
                    result = try await AppleSMBNetworkLibraryScanner(client: AppleSMBClient()).scan(source: source, credentials: credentials)
                } else { result = await AppleLibraryScanner().scanResult(source: source) }
                guard !Task.isCancelled else {
                    staleSourceIDs.insert(source.id)
                    try? await mediaIndex.replace(instanceID: source.id, with: [], scanStatus: .failed)
                    return
                }
                guard result.status != .failed else { throw AppleLibrarySourceError.unavailable }
                let previous = groups.flatMap(\.items).filter { $0.sourceID == source.id }
                let scanned = result.retaining(previous)
                if result.status == .complete { staleSourceIDs.remove(source.id) }
                else { staleSourceIDs.insert(source.id) }
                let dated = try await metadataResolver.datedItems(scanned, sourceID: source.id)
                appleTrace("library scanned \"\(source.name)\": \(scanned.count) files")
                files += dated
                sourceStore.recordValidationSuccess(id: source.id, summary: "Connected · \(scanned.count) playable files",
                    discoveredItemCount: scanned.count, capabilities: ["Browse", "Playback", "Seeking"])
                pendingIndexWrites.append((source, result.status == .complete ? dated : result.items, result.status))
            } catch is CancellationError {
                staleSourceIDs.insert(source.id)
                try? await mediaIndex.replace(instanceID: source.id, with: [], scanStatus: .failed)
                return
            }
            catch {
                appleTraceFailure("library scan \"\(source.name)\" failed: \(error.localizedDescription)")
                files += groups.flatMap(\.items).filter { $0.sourceID == source.id }
                staleSourceIDs.insert(source.id)
                pendingIndexWrites.append((source, [], .failed))
                errors.append("\(source.name): \(error.localizedDescription)")
                sourceStore.recordValidationFailure(id: source.id, summary: error.localizedDescription)
            }
        }
        appleTrace("library scans done, \(files.count) files")
        let downloads = await AppleOfflineMediaStore().allRecords()
        appleTrace("library downloads read: \(downloads.count)")
        var newOfflineIDs: [String: String] = [:]
        var newMetadata: [String: AppleCatalogItem] = [:]
        if !downloads.isEmpty {
            sources.append(AppleSource(id: Self.downloadsID, kind: .library, name: "Downloads", url: downloads[0].localURL.deletingLastPathComponent()))
            for record in downloads {
                let indexed = mediaIndex.record(matchingMediaID: record.mediaID)
                let filename = [record.title ?? indexed?.title ?? record.localURL.deletingPathExtension().lastPathComponent,
                    indexed?.year.map(String.init), record.subtitle].compactMap { $0 }.joined(separator: " ")
                let file = AppleLibraryItem(sourceID: Self.downloadsID, name: filename,
                    url: record.localURL, relativePath: record.localURL.lastPathComponent, sizeBytes: 0, addedAt: record.storedAt)
                files.append(file)
                newOfflineIDs[file.id] = record.mediaID
                // Download record ids are index identities, not necessarily IMDb ids.
                let group = AppleLibrarySeries.groups([file])[0]
                newMetadata[group.id] = AppleCatalogItem(mediaID: indexed?.canonicalID ?? "local-" + ApplePlaybackIdentity.digest(for: record.mediaID),
                    type: group.parsed.kind == .show ? "series" : "movie", name: indexed?.title ?? record.title ?? group.parsed.title,
                    posterURL: record.artworkURL, summary: indexed?.summary, releaseInfo: (indexed?.year ?? group.parsed.year).map(String.init))
            }
        }
        let snapshot = files
        let regrouped = await Task.detached { AppleLibrarySeries.groups(snapshot) }.value
        // A rescan that finds the titles already published must not redraw
        // Library and Discover. (Groups from the persisted index carry fewer
        // parse fields, so the first scan after it still publishes.)
        let unchanged = regrouped == groups && newOfflineIDs == offlineIDs
            && newMetadata.allSatisfy { metadata[$0.key] != nil }
        if !unchanged {
            groups = regrouped
            offlineIDs = newOfflineIDs
            episodesByGroup = await Self.episodeCandidates(groups: groups, sources: sources, offlineIDs: newOfflineIDs)
            metadata.merge(newMetadata) { current, _ in current }
            contentDidChange()
        }
        appleTrace("library grouped: \(groups.count) titles\(unchanged ? ", unchanged" : "")")
        // Everything the shelves need is in `groups` now, so the tab can draw.
        //
        // The media index feeds search and Discover matching, not the
        // Library's own shelves, but writing its 1,397 records took 1.9s and
        // used to run inside the scan loop — between the scan finishing and
        // the grouping that actually produces the rows. The tab therefore held
        // a spinner for nearly three seconds after it already had the files
        // (measured 2026-09-15). The write still happens, just no longer in
        // front of the picture.
        for (source, items, status) in pendingIndexWrites {
            do {
                try await mediaIndex.replace(instanceID: source.id, with: AppleMediaIngestion.libraryRecords(source: source, items: items), scanStatus: status)
            } catch is CancellationError { return }
            catch {
                // This device's own storage, not the source: the shelves are
                // already drawn from `groups`, and the next scan writes the
                // index again. Nothing for the viewer to read or fix (build
                // 17 showed Apple TV's raw "You don't have permission to save
                // the file …" under the NAS), so it goes to the trace only.
                appleTraceFailure("library index write failed: \(appleErrorLabel(error))")
            }
        }
        appleTrace("library index written")
        #if DEBUG
        // `defaults write com.orgista.openstream OpenStreamLibraryTitleDump -bool YES`
        // prints what each file parsed to, so a card showing a number can be
        // traced back to the name on disk without opening the share.
        if UserDefaults.standard.bool(forKey: "OpenStreamLibraryTitleDump") {
            for group in groups {
                let parsed = group.parsed
                print("[OpenStream] title raw=\(group.items.first?.relativePath ?? "?") -> \(parsed.title) kind=\(parsed.kind.rawValue) year=\(parsed.year.map(String.init) ?? "-")")
            }
        }
        // `defaults write com.orgista.openstream OpenStreamLibraryTitleFilter
        // -string 1992` traces just the titles containing that text. The full
        // dump above goes to the console and is 1397 lines long, which neither
        // fits the trace's ring buffer nor answers a question about one card.
        if let needle = UserDefaults.standard.string(forKey: "OpenStreamLibraryTitleFilter")?.lowercased(),
           !needle.isEmpty {
            for group in groups where
                (group.items.first?.relativePath ?? "").lowercased().contains(needle)
                || group.parsed.title.lowercased().contains(needle) {
                let parsed = group.parsed
                appleTrace(
                    "library title raw=\"\(group.items.first?.relativePath ?? "?")\" → "
                    + "\"\(parsed.title)\" kind=\(parsed.kind.rawValue) "
                    + "year=\(parsed.year.map(String.init) ?? "-") groupID=\(group.id)"
                )
            }
        }
        #endif
        errorMessage = errors.isEmpty ? nil : errors.joined(separator: "\n")
        let cached = await metadataResolver.cachedMetadata(for: groups)
        let merged = metadata.merging(cached) { _, persisted in persisted }
        if merged != metadata {
            metadata = merged
            contentDidChange()
        }
        appleTrace("library cached metadata merged: \(cached.count)")
        refreshProgress()
        appleTrace("library progress refreshed")
        await recordAllIdentityAliases()
        refreshProgress()
        // Bound eager work. Visible cards resolve the rest on demand.
        for group in sorted(.added).filter({ $0.parsed.kind != .other }).prefix(24) {
            guard !Task.isCancelled else { return }
            await resolve(group, sourceStore: sourceStore, settings: settings)
        }
        appleTrace("library eager metadata resolved")
        let completedSources = pendingIndexWrites.filter { $0.status == .complete }
        for entry in completedSources { lastSuccessfulScanBySource[entry.source.id] = .now }
        if pendingIndexWrites.allSatisfy({ $0.status == .complete }) { lastScan = .now }
        let sourceDigest = ApplePlaybackIdentity.digest(for: sources.map(\.id.uuidString).sorted().joined(separator: ","))
        
        let snapshots = groups.map { group in
            AppleLibraryGroupSnapshot(
                id: group.id,
                title: group.parsed.title,
                year: group.parsed.year,
                kind: group.parsed.kind,
                items: group.items.map { AppleLibraryGroupSnapshot.Item(id: $0.id, sourceID: $0.sourceID, name: $0.name, url: $0.url, relativePath: $0.relativePath, sizeBytes: $0.sizeBytes, addedAt: $0.addedAt) }
            )
        }
        guard Self.persistsScanResults else { return }
        if let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first {
            let dir = caches.appendingPathComponent("OpenStream")
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: nil)
            let url = dir.appendingPathComponent("LibraryGroups-v1.json")
            if let data = try? JSONEncoder().encode(snapshots) {
                try? data.write(to: url, options: .atomic)
            }
        }
        
        if pendingIndexWrites.allSatisfy({ $0.status == .complete }) {
            AppleLaunchWorkPolicy.recordScan(sourceDigest: sourceDigest, date: lastScan ?? Date())
        }
    }
    /// Persist before publishing; playback keys are untouched.
    func correctMatch(_ group: AppleLibrarySeries, candidate: AppleCatalogItem, provider: String,
                      explicitIDs: [String: String] = [:], resolver: AppleLibraryMetadataResolver = .shared) async throws {
        guard let file = group.items.first else { return }
        try await resolver.correctMatch(for: file, candidate: candidate,
            provider: provider, explicitIDs: explicitIDs)
        metadata[group.id] = candidate
        recordedIdentityFileIDs.subtract(group.items.map(\.id))
        contentDidChange()
    }

    nonisolated static func fileEpisodeID(_ file: AppleLibraryItem) -> String {
        "local-file-" + ApplePlaybackIdentity.digest(for: file.id)
    }

    nonisolated static func matchesEpisode(_ file: AppleLibraryItem, episode: AppleStremioEpisode) -> Bool {
        let parsed = AppleLibraryParseMemo.parse(file)
        if episode.id == fileEpisodeID(file) { return true }
        guard parsed.role == .feature else { return false }
        if let date = parsed.airDate { return episode.releaseInfo.map { String($0.prefix(10)) } == date }
        guard let season = parsed.season, let number = episode.episode else { return false }
        return season == episode.season && parsed.episodeNumbers.contains(number)
    }

    func localFiles(for item: AppleCatalogItem, group: AppleLibrarySeries? = nil, episode: AppleStremioEpisode? = nil) -> [AppleLibraryItem] {
        let matches = matchingGroups(item)
        let groups = matches.isEmpty ? group.map { [$0] } ?? [] : matches
        return groups.flatMap { group in
            group.items.compactMap { file -> AppleLibraryItem? in
                guard item.type == "series" else { return file }
                guard let episode else { return nil }
                return Self.matchesEpisode(file, episode: episode) ? file : nil
            }
        }.sorted {
            let firstPart = AppleLibraryParseMemo.parse($0).part ?? 1
            let secondPart = AppleLibraryParseMemo.parse($1).part ?? 1
            if firstPart != secondPart { return firstPart < secondPart }
            let lhs = AppleStremioCandidateRanking.resolution($0.name)
            let rhs = AppleStremioCandidateRanking.resolution($1.name)
            if lhs != rhs { return lhs > rhs }
            return $0.addedAt == $1.addedAt ? $0.id < $1.id : $0.addedAt > $1.addedAt
        }
    }
    func resumeEpisode(for item: AppleCatalogItem, group: AppleLibrarySeries?, episodes: [AppleStremioEpisode]) -> AppleStremioEpisode? {
        let matches = matchingGroups(item)
        let candidates = matches.isEmpty ? group.map { [$0] } ?? [] : matches
        let store = playbackStore
        return Self.resumeEpisode(in: candidates, episodes: episodes) { store.progress(for: self.playbackID($0)) }
    }
    static func resumeEpisode(in groups: [AppleLibrarySeries], episodes: [AppleStremioEpisode],
                              progress: (AppleLibraryItem) -> ApplePlaybackProgress?) -> AppleStremioEpisode? {
        var newest = Date.distantPast
        var selected: AppleStremioEpisode?
        for group in groups {
            for file in group.items {
                guard let value = progress(file), value.resumePosition != nil, value.updatedAt > newest else { continue }
                if let episode = episodes.first(where: { Self.matchesEpisode(file, episode: $0) }) {
                    selected = episode
                    newest = value.updatedAt
                }
            }
        }
        return selected
    }
    nonisolated static func visibleEpisodes(in season: Int?, from episodes: [AppleStremioEpisode]) -> [AppleStremioEpisode] {
        AppleStremioEpisodePolicy.episodes(in: season, from: episodes)
            + episodes.filter { $0.id.hasPrefix("local-file-") }
    }

    static func episodes(group: AppleLibrarySeries, mediaID: String, enriched: [AppleStremioEpisode]) -> [AppleStremioEpisode] {
        var seen = Set<String>()
        return group.items.flatMap { file -> [AppleStremioEpisode] in
            let parsed = AppleLibraryParseMemo.parse(file)
            if parsed.role == .feature, let season = parsed.season, !parsed.episodeNumbers.isEmpty {
                return parsed.episodeNumbers.compactMap { number in
                    let id = "\(mediaID):\(season):\(number)"
                    guard seen.insert(id).inserted else { return nil }
                    return enriched.first { $0.season == season && $0.episode == number }
                        ?? AppleStremioEpisode(id: id, title: "Episode \(number)", season: season, episode: number)
                }
            }
            if parsed.role == .feature, let date = parsed.airDate {
                let dated = enriched.filter { $0.releaseInfo.map { String($0.prefix(10)) } == date }
                if dated.count == 1, let episode = dated.first {
                    return seen.insert(episode.id).inserted ? [episode] : []
                }
            }
            // A playable filename row is deliberately not a guessed episode.
            return [AppleStremioEpisode(id: fileEpisodeID(file), title: file.name, releaseInfo: parsed.airDate)]
        }
    }

    /// Read the old positional episode key without rewriting watched history or
    /// changing the file identity. A reset on the current row takes precedence.
    static func completedEpisodeIDs(_ episodes: [AppleStremioEpisode], group: AppleLibrarySeries?,
                                    mediaID: String, store: ApplePlaybackStore) -> Set<String> {
        var completed = store.completedMediaIDs(among: episodes.map(\.id))
        guard let group else { return completed }
        let rowIDs = Set(episodes.map(\.id))
        var legacySeen = Set<String>()
        let aliases = group.items.enumerated().compactMap { index, file -> (String, String)? in
            let parsed = AppleLibraryParseMemo.parse(file)
            let legacy = "\(mediaID):\(parsed.season ?? 1):\(parsed.episode ?? index + 1)"
            // The old row builder deduplicated these keys. Do not borrow a
            // numbered episode's history for a filename row it had suppressed.
            guard legacySeen.insert(legacy).inserted else { return nil }
            let current = fileEpisodeID(file)
            guard rowIDs.contains(current), store.canReadLegacyEpisodeAlias(current: current, legacy: legacy) else { return nil }
            return (current, legacy)
        }
        guard !aliases.isEmpty else { return completed }
        let legacyCompleted = store.completedMediaIDs(among: aliases.map { $0.1 })
        let terminals = store.configurationPlaybackTerminals()
        let tombstones = store.configurationWatchedTombstones()
        let watched = store.configurationWatchedHistory()
        let progress = store.completionProgress()
        for (current, legacy) in aliases where !completed.contains(current) && legacyCompleted.contains(legacy) {
            guard let key = ApplePlaybackIdentity.storageKey(for: current),
                  let legacyKey = ApplePlaybackIdentity.storageKey(for: legacy) else { continue }
            let reset = [terminals[key]?.resetAt, tombstones[key]].compactMap { $0 }.max()
            let completedAt = [watched[legacyKey], progress[legacyKey].flatMap { $0.isComplete ? $0.updatedAt : nil }]
                .compactMap { $0 }.max()
            if let reset, completedAt.map({ $0 <= reset }) ?? true { continue }
            completed.insert(current)
        }
        return completed
    }

    /// Filename rows have no invented season/number, so the numbered episode
    /// policy excludes them. Keep their displayed order when selecting a row.
    static func nextFilenameEpisode(in episodes: [AppleStremioEpisode], completedIDs: Set<String>) -> AppleStremioEpisode? {
        let files = episodes.filter { $0.id.hasPrefix("local-file-") }
        return files.first { !completedIDs.contains($0.id) } ?? files.first
    }

    nonisolated static func format(_ file: AppleLibraryItem) -> String {
        let resolution = file.name.range(of: #"(?i)\b(?:\d{3,4}p|[48]K)\b"#, options: .regularExpression).map { String(file.name[$0]).uppercased() }
        return [resolution, file.url.pathExtension.uppercased()].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
    }
    func mediaVersions(for file: AppleLibraryItem, recordAliases: Bool = true) -> [AppleMediaVersion] {
        let parsed = AppleLibraryParseMemo.parse(file)
        guard let group = groups.first(where: { $0.items.contains(where: { $0.id == file.id }) }),
              parsed.role == .feature, offlineIDs[file.id] == nil else { return [] }
        // Episodes share a title page but never a playback timeline.
        let canonical = versionItemIDs[file.id]
        let matching = canonical.map { id in groups.filter { $0.items.contains { versionItemIDs[$0.id] == id } } } ?? [group]
        let candidates: [AppleLibraryItem]
        let fallback: String
        if canonical != nil {
            candidates = matching.flatMap(\.items).filter {
                let other = AppleLibraryParseMemo.parse($0)
                guard versionItemIDs[$0.id] == canonical else { return false }
                if parsed.kind == .show, parsed.episodeNumbers.isEmpty, parsed.airDate == nil { return $0.id == file.id }
                if let date = parsed.airDate { return other.airDate == date }
                return parsed.kind != .show || (other.season == parsed.season && other.episodeNumbers == parsed.episodeNumbers && other.airDate == parsed.airDate)
            }
            fallback = playbackID(file)
        } else if parsed.part != nil,
                  let stack = group.mediaVersions(itemID: "", playbackID: playbackID).first(where: { $0.parts.contains { $0.reference == file.id } }),
                  stack.parts.count > 1 {
            // An unmatched file keeps its own item (design §2, §5); only the
            // parts of one stack share a timeline.
            let references = Set(stack.parts.map(\.reference))
            candidates = group.items.filter { references.contains($0.id) }
            fallback = "li:local:" + ApplePlaybackIdentity.digest(for: group.id + ":" + stack.id)
        } else {
            candidates = [file]
            fallback = playbackID(file)
        }
        let itemID = canonical ?? fallback
        let subset = AppleLibrarySeries(id: group.id, parsed: group.parsed, items: candidates)
        var durations = inspections.compactMapValues(\.duration)
        for candidate in candidates {
            // Includes part lengths learned from playback when the probe failed.
            if let cached = mediaVersionCache.version(containing: candidate.id) {
                for part in cached.parts where durations[part.reference] == nil { durations[part.reference] = part.duration }
            }
        }
        let candidatesByVersion = subset.mediaVersions(itemID: itemID, playbackID: playbackID, durations: durations)
        let mappedVersions: [AppleMediaVersion] = candidatesByVersion.map { value -> AppleMediaVersion in
            var version = value
            // A previously verified stack remains a stack when a later scan loses a member.
            if let reference = value.parts.first?.reference, let cached = mediaVersionCache.version(containing: reference),
               cached.sourceID == value.sourceID, cached.parts.count > value.parts.count,
               Set(value.parts.map(\.reference)).isSubset(of: Set(cached.parts.map(\.reference))) {
                version = AppleMediaVersion(id: cached.id, itemID: itemID, sourceID: cached.sourceID,
                    label: cached.label, parts: cached.parts, providerVersionID: cached.providerVersionID)
                version.descriptors = cached.descriptors
                version.formatBadges = cached.formatBadges
            }
            if let reference = version.parts.first?.reference, let inspection = inspections[reference] {
                version.descriptors = inspection.descriptors
                version.formatBadges = AppleStreamFormatBadge.merged(probed: inspection.badges, named: version.formatBadges)
            } else if let cached = mediaVersionCache.versions[value.id] {
                version.descriptors = cached.descriptors
                version.formatBadges = AppleStreamFormatBadge.merged(probed: cached.formatBadges, named: version.formatBadges)
            }
            return version
        }
        let versions = mappedVersions.sorted { lhs, rhs in
            let leftQuality = lhs.quality
            let rightQuality = rhs.quality
            return leftQuality == rightQuality ? lhs.id < rhs.id : leftQuality > rightQuality
        }
        playbackStore.migrateVersionProgress(itemID: itemID, versions: Dictionary(uniqueKeysWithValues: versions.map { version in
            (version.id, version.parts.map { part in
                if let file = candidates.first(where: { $0.id == part.reference }) { return playbackID(file) }
                // Recompute the same Stage-A key even when this scan lost a known member.
                let prefix = version.sourceID.uuidString + ":"
                guard part.reference.hasPrefix(prefix) else { return "" }
                let path = String(part.reference.dropFirst(prefix.count))
                let file = AppleLibraryItem(sourceID: version.sourceID, name: URL(fileURLWithPath: path).lastPathComponent,
                    url: URL(fileURLWithPath: "/" + path), relativePath: path, sizeBytes: 0)
                return playbackID(file)
            })
        }), timelines: Dictionary(uniqueKeysWithValues: versions.map { ($0.id, $0) }), recordAliases: recordAliases)
        mediaVersionCache.record(versions)
        return versions
    }

    @ObservationIgnored private(set) var mediaVersionCache: AppleMediaVersionCache
    @ObservationIgnored private var versionItemIDs: [String: String] = [:]

    func presentation(for requestedFile: AppleLibraryItem, sourceStore: AppleSourceStore, settings: AppleSettingsStore,
                      fromBeginning: Bool = false, disc: AppleDiscPlaybackChoice? = nil,
                      explicitVersion: Bool = false, confirmedVersionID: String? = nil,
                      continuingPart: Bool = false, automaticFallback: Bool = false,
                      engineOverride: ApplePlaybackEngineKind? = nil) async throws -> AppleStremioPlayerPresentation {
        var file = requestedFile
        return try await presentation(attempting: &file, sourceStore: sourceStore, settings: settings,
            fromBeginning: fromBeginning, disc: disc, explicitVersion: explicitVersion, confirmedVersionID: confirmedVersionID,
            continuingPart: continuingPart, automaticFallback: automaticFallback, engineOverride: engineOverride)
    }

    /// `file` ends as the file actually tried: the version selection or the
    /// resume point may move off the requested one, and a failure names that file.
    func presentation(attempting file: inout AppleLibraryItem, sourceStore: AppleSourceStore, settings: AppleSettingsStore,
                      fromBeginning: Bool = false, disc: AppleDiscPlaybackChoice? = nil,
                      explicitVersion: Bool = false, confirmedVersionID: String? = nil,
                      continuingPart: Bool = false, automaticFallback: Bool = false,
                      engineOverride: ApplePlaybackEngineKind? = nil) async throws -> AppleStremioPlayerPresentation {
        try Task.checkCancellation()
        var versions = mediaVersions(for: file)
        let store = playbackStore
        let filesByID = Dictionary(groups.flatMap(\.items).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let available = versions.filter { $0.isAvailable(references: Set(filesByID.keys)) }
        if !continuingPart, let itemID = versions.first?.itemID {
            // The answered prompt plays the version it asked about; Play resumes the
            // copy played last. A pick or a fallback after a failure keeps its file.
            let selected = AppleVersionSelectionPolicy.select(available, confirmed: confirmedVersionID,
                lastPlayed: explicitVersion || automaticFallback ? nil : store.preferredVersion(itemID: itemID),
                requestedReference: file.id)
            // A stack keeps the part it was asked for; resume maps the position to a part below.
            if let selected, !selected.parts.contains(where: { $0.reference == file.id }),
               let reference = selected.parts.first?.reference, let selectedFile = filesByID[reference] { file = selectedFile }
        }
        guard let source = sources.first(where: { $0.id == file.sourceID }) else { throw AppleLibrarySourceError.unavailable }
        // Inspect each stack member once so offsets are never guessed from file sizes.
        if let version = versions.first(where: { $0.parts.contains(where: { $0.reference == file.id }) }) {
            guard version.isAvailable(references: Set(filesByID.keys)) else { throw AppleLibrarySourceError.unavailable }
            for part in version.parts where part.duration == nil {
                guard let member = filesByID[part.reference], inspections[member.id]?.duration == nil else { continue }
                if source.kind == .nas {
                    // A probe that cannot even start is a failed probe, never a failed play.
                    let credentials = (try? sourceStore.networkCredentials(for: source)) ?? AppleSMBCredentials(username: "", password: "")
                    if let url = try? await AppleSMBRangeServer.shared.playbackURL(sourceURL: member.url,
                        credentials: credentials, sizeBytes: member.sizeBytes) {
                        let result = await Task.detached(priority: .utility) {
                            AppleLocalFileInspection.inspect(url: url, isDisc: false)
                        }.value
                        try Task.checkCancellation()
                        inspections[member.id] = result
                    }
                    try Task.checkCancellation()
                } else { _ = await inspection(for: member) }
                // One unmeasured part is enough to fall back; skip probing the rest.
                if version.parts.count > 1, inspections[member.id]?.duration == nil { break }
            }
            try Task.checkCancellation()
            versions = mediaVersions(for: file)
        }
        let chosen = versions.first { $0.parts.contains { $0.reference == file.id } }
        // A stack whose parts could not be measured plays part by part, each
        // file on its own position, as it did before versions; never unavailable.
        let version = chosen.flatMap { $0.parts.count > 1 && $0.duration == nil ? nil : $0 }
        let itemID = version?.itemID ?? playbackID(file)
        let resolution = version == nil && chosen != nil
            ? AppleVersionResumePolicy.Resolution(position: store.fileProgress(for: itemID)?.resumePosition, needsConfirmation: false)
            : AppleVersionResumePolicy.resolve(
                own: version.flatMap { store.versionProgress(itemID: itemID, versionID: $0.id) },
                item: store.progress(for: itemID), duration: version?.duration)
        if !fromBeginning, !continuingPart, let version, confirmedVersionID != version.id,
           resolution.needsConfirmation, let position = resolution.position {
            throw AppleVersionResumeConfirmation(position: position, versionID: version.id)
        }
        var resume = fromBeginning || continuingPart ? nil : resolution.position
        if let version, let position = resume, let location = version.location(at: position),
           let reference = version.parts.first(where: { $0.ordinal == location.ordinal })?.reference,
           let resumedFile = groups.flatMap(\.items).first(where: { $0.id == reference }) {
            file = resumedFile
            resume = location.offset
        }
        let part = version?.parts.first { $0.reference == file.id }
        var hints = ApplePlaybackRequest.Hints(filename: file.name, libraryFileURL: file.url)
        // A Blu-ray has no menu to open (`AppleDiscFormat`): its main feature.
        hints.disc = AppleDiscImagePolicy.isDiscImage(file)
            ? AppleDiscPlaybackChoice(start: disc?.start ?? .menu, titleID: disc?.titleID,
                                      format: AppleDiscCatalog.shared.format(for: file))
            : nil
        hints.versionID = version?.id
        hints.playbackDecision = ApplePlaybackDecision.decide(inspections[file.id]?.descriptors ?? .init(container: file.url.pathExtension))
        hints.versionOffset = part.flatMap { version?.cumulativePosition(ordinal: $0.ordinal, offset: 0) } ?? 0
        hints.versionDuration = version?.duration
        let title = AppleLibraryParseMemo.parse(file).title
        let presentation: AppleStremioPlayerPresentation
        if source.kind == .nas {
            let credentials = try sourceStore.networkCredentials(for: source) ?? AppleSMBCredentials(username: "", password: "")
            let url = try await AppleSMBRangeServer.shared.playbackURL(sourceURL: file.url, credentials: credentials, sizeBytes: file.sizeBytes)
            try Task.checkCancellation()
            var request = AppleSMBPlaybackRequestFactory.make(source: source, item: file, playbackURL: url)
            request.mediaID = itemID
            request.resumePosition = resume
            request.hints = hints
            presentation = AppleStremioPlayerPresentation(request: request, settings: settings, engineOverride: engineOverride)
        } else {
            let root = file.sourceID == Self.downloadsID ? nil : try AppleLibraryBookmark.resolve(source)
            let access = root.map { AppleSecurityScopedAccess(url: $0) }
            defer { withExtendedLifetime(access) {} }
            let prepared = try await ApplePlaybackPreparer().prepareLibraryMedia(sourceURL: file.url, preferredEngine: engineOverride ?? settings.playbackEngine)
            try Task.checkCancellation()
            presentation = AppleStremioPlayerPresentation(request: ApplePlaybackRequest(url: prepared.url, headers: prepared.requestHeaders,
                resumePosition: resume, mediaID: itemID, title: title, sourceKind: .files, hints: hints), settings: settings, securityScopedURL: root, engineOverride: engineOverride)
        }
        let request = presentation.request
        // An unmeasured stack part saves its own (part, offset) and learns its length.
        let learnsDuration = version == nil && chosen != nil
        let reference = file.id
        let cache = mediaVersionCache
        presentation.coordinator.progressWriter = { position, duration in
            store.save(request: request, position: position, duration: duration)
            if learnsDuration { cache.learnDuration(duration, reference: reference) }
        }
        return presentation
    }

}

struct AppleLocalTitleShelf: View {
    let title: String
    let groups: [AppleLibrarySeries]
    let sourceStore: AppleSourceStore
    let mediaIndex: AppleMediaIndexStore
    let settings: AppleSettingsStore
    let openSettings: () -> Void
    /// The bar of the tab the shelf sits on, for the title pages it opens.
    let tabToolbar: AppleTabToolbarContext?
    var showsProgress = false
    var accessory: AnyView? = nil
    var previewLimit: Int? = nil
    var opensFullList = true
    @State private var library = AppleLocalLibraryStore.shared
    @FocusState private var focusedItemID: String?

    var body: some View {
        AppleHomeShelf(title: title, accessory: accessory, headingIdentifier: "library.shelf.\(title)", opensFullList: opensFullList) {
            ForEach(Array(groups.prefix(previewLimit ?? groups.count))) { group in
                tile(group).focused($focusedItemID, equals: group.id)
            }
        } destination: {
            List(groups) { group in
                NavigationLink {
                    AppleLocalTitleDestination(group: group, sourceStore: sourceStore, mediaIndex: mediaIndex,
                        settings: settings, openSettings: openSettings, tabToolbar: tabToolbar)
                } label: {
                    let item = library.catalogItem(for: group)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.name).font(.headline)
                        if let year = item.releaseInfo { Text(year).font(.caption).foregroundStyle(.secondary) }
                    }
                }
            }
                .navigationTitle(title)
                .scrollIndicators(.never)
                .task(id: groups.map(\.id)) { library.refreshProgress() }
        }
        .environment(\.appleTMDBConfiguration, settings.tmdbConfiguration)
        #if os(tvOS)
        .defaultFocus($focusedItemID, groups.first?.id)
        .task(id: focusedItemID) {
            guard let group = groups.first(where: { $0.id == focusedItemID }) else { return }
            try? await Task.sleep(for: AppleMetadataPrefetcher.focusDwell)
            guard !Task.isCancelled else { return }
            await library.resolve(group, sourceStore: sourceStore, settings: settings)
            let item = library.catalogItem(for: group)
            if let target = AppleMetadataPrefetcher.detailTarget(type: item.type, mediaID: item.mediaID) {
                await AppleMetadataPrefetcher.warmDetail(target, sources: sourceStore.sources,
                    preferredSourceID: group.items.first?.sourceID, configuration: settings.tmdbConfiguration)
            }
        }
        #endif
    }

    private func tile(_ group: AppleLibrarySeries) -> some View {
        AppleLocalLibraryTile(group: group, sourceStore: sourceStore, mediaIndex: mediaIndex,
            settings: settings, openSettings: openSettings, tabToolbar: tabToolbar, showsProgress: showsProgress)
    }

}

struct AppleLocalTitleDestination: View {
    let group: AppleLibrarySeries
    let sourceStore: AppleSourceStore
    let mediaIndex: AppleMediaIndexStore
    let settings: AppleSettingsStore
    let openSettings: () -> Void
    let tabToolbar: AppleTabToolbarContext?
    var autoPlay = false
    @State private var library = AppleLocalLibraryStore.shared
    @State private var showsFixMatch = false
    var body: some View {
        if let source = library.sources.first(where: { $0.id == group.items.first?.sourceID }) {
            AppleCatalogItemDetailView(item: library.catalogItem(for: group), source: source, mediaIndex: mediaIndex,
                playbackSources: sourceStore.sources, metadataConfiguration: settings.metadataEnabled ? try? AppleTMDBConfiguration(credential: settings.tmdbAPIKey) : nil,
                gatewayConfig: settings.gatewayEnabled ? try? AppleTranscodeGatewayConfig(baseURL: settings.gatewayURL,
                    sessionToken: settings.gatewayToken, isEnabled: true) : nil,
                playbackResolver: AppleStremioPlaybackResolver(), settings: settings,
                openSettings: openSettings, initialAutoPlay: autoPlay, localGroup: group, localSourceStore: sourceStore,
                tabToolbar: tabToolbar)
                .environment(\.appleLibraryFixMatch, { showsFixMatch = true })
                .sheet(isPresented: $showsFixMatch) {
                    AppleLibraryFixMatchView(group: group, sources: sourceStore.sources, settings: settings)
                }
        }
    }
}
