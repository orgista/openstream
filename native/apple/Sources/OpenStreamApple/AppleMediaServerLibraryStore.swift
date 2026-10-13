import Foundation
import Observation

public struct AppleMediaServerItemReference: Equatable, Hashable, Sendable {
    public let sourceID: UUID
    public let itemID: String

    public static let prefix = "ms:"

    public var mediaID: String {
        "ms:\(sourceID.uuidString.lowercased()):\(itemID)"
    }

    public static func parse(_ mediaID: String) -> AppleMediaServerItemReference? {
        guard mediaID.hasPrefix(AppleMediaServerItemReference.prefix) else { return nil }
        let remainder = mediaID.dropFirst(AppleMediaServerItemReference.prefix.count)
        let parts = remainder.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2 else { return nil }
        guard let sourceID = UUID(uuidString: String(parts[0])), !parts[1].isEmpty else { return nil }
        return AppleMediaServerItemReference(sourceID: sourceID, itemID: String(parts[1]))
    }
}

@MainActor
@Observable
public final class AppleMediaServerLibraryStore {
    public struct Shelf: Identifiable, Equatable, Sendable, Codable {
        public let id: String
        public let title: String
        public let sourceID: UUID
        public let items: [AppleCatalogItem]
        
        public init(id: String, title: String, sourceID: UUID, items: [AppleCatalogItem]) {
            self.id = id
            self.title = title
            self.sourceID = sourceID
            self.items = items
        }
    }

    public private(set) var contentRevision: UInt64 = 0
    public private(set) var shelves: [Shelf] = [] { didSet { contentRevision &+= 1 } }
    public private(set) var continueWatching: [AppleCatalogItem] = [] { didSet { contentRevision &+= 1 } }
    public private(set) var isLoading = false
    public private(set) var failures: [UUID: String] = [:]
    public private(set) var lastLoadedAt: Date?
    
    private var plexIndex: [AppleMediaServerItemReference: ApplePlexItem] = [:]
    private var index: [AppleMediaServerItemReference: AppleMediaServerItem] = [:]
    private var sourceIndex: [UUID: AppleSource] = [:]
    private var sessionIndex: [UUID: AppleMediaServerSession] = [:]
    
    private enum HubRequest: Sendable, Equatable {
        case plex(key: String, nextUp: Bool)
        case nextUp(parentID: String)
        case genre(parentID: String, name: String, type: AppleMediaServerItemType)
    }
    private struct HubState: Sendable, Equatable {
        let request: HubRequest
        var offset: Int
        var total: Int
        var exhausted = false
        var refreshedAt = Date()
    }
    private var hubStates: [String: HubState] = [:]
    private var hubDefinitions: [String: Shelf] = [:]
    private var shelfOrder: [String] = []
    private var loadingHubs: Set<String> = []
    private var hubRevisions: [String: UInt64] = [:]

    public func canLoadMore(shelfID: String) -> Bool {
        guard let state = hubStates[shelfID], let shelf = shelves.first(where: { $0.id == shelfID }) else { return false }
        return !state.exhausted && state.offset < state.total && shelf.items.count < AppleCatalogPaging.maximumItems
    }

    public func loadMore(shelfID: String) async {
        guard canLoadMore(shelfID: shelfID) else { return }
        await updateHub(shelfID: shelfID, replacing: false)
    }

    public func refresh(shelfID: String) async {
        // Refresh wins over an older page request; the request revision prevents that page committing later.
        hubRevisions[shelfID, default: 0] &+= 1
        loadingHubs.remove(shelfID)
        await updateHub(shelfID: shelfID, replacing: true)
    }

    public func refreshIfNeeded(shelfID: String, now: Date = .now) async {
        guard let state = hubStates[shelfID], now.timeIntervalSince(state.refreshedAt) >= 60 else { return }
        await refresh(shelfID: shelfID)
    }

    /// A delivered terminal event can change its own rows and the server's next-episode hub.
    internal func refreshAffectedHubs(reference: AppleMediaServerItemReference) async {
        let episodic = index[reference]?.type == .episode || plexIndex[reference]?.type == .episode
        let affected = shelfOrder.compactMap { hubDefinitions[$0] }.filter { shelf in
            guard shelf.sourceID == reference.sourceID, let state = hubStates[shelf.id] else { return false }
            let isNextUp: Bool
            switch state.request {
            case .nextUp: isNextUp = episodic
            case .plex(_, let nextUp): isNextUp = episodic && nextUp
            case .genre: isNextUp = false
            }
            return isNextUp || shelves.first(where: { $0.id == shelf.id })?.items.contains { $0.mediaID == reference.mediaID } == true
        }.map(\.id)
        for id in affected { await refresh(shelfID: id) }
    }

    private func updateHub(shelfID: String, replacing: Bool) async {
        guard !loadingHubs.contains(shelfID), let state = hubStates[shelfID],
              let shelf = hubDefinitions[shelfID],
              let source = sourceIndex[shelf.sourceID], source.isEnabled,
              let session = sessionIndex[shelf.sourceID] else { return }
        let requestGeneration = generation
        let revision = hubRevisions[shelfID, default: 0]
        loadingHubs.insert(shelfID)
        defer { if generation == requestGeneration, hubRevisions[shelfID, default: 0] == revision { loadingHubs.remove(shelfID) } }
        let start = replacing ? 0 : state.offset
        do {
            let items: [AppleCatalogItem]
            let rawCount: Int
            let total: Int
            var rawItems: [AppleMediaServerItem] = []
            var plexItems: [ApplePlexItem] = []
            switch state.request {
            case .plex(let key, _):
                let page = try await plexClient.hubItems(session: session, key: key, start: start, size: 20)
                plexItems = page.items
                rawCount = page.items.count
                total = page.totalSize
                items = page.items.filter { Self.isEligible($0) }.map { catalogItem($0, source: source, session: session) }
            case .nextUp(let parentID):
                let page = try await client.nextUp(session: session, parentID: parentID, startIndex: start)
                rawItems = page.items
                rawCount = page.items.count
                total = page.totalRecordCount
                items = page.items.filter { Self.isEligible($0) }.map { catalogItem($0, source: source, session: session) }
            case .genre(let parentID, let name, let type):
                let page = try await client.items(session: session, parentID: parentID, includeTypes: [type], startIndex: start, limit: 20, genres: [name])
                rawItems = page.items
                rawCount = page.items.count
                total = page.totalRecordCount
                items = page.items.filter { Self.isEligible($0) }.map { catalogItem($0, source: source, session: session) }
            }
            guard !Task.isCancelled, generation == requestGeneration,
                  hubRevisions[shelfID, default: 0] == revision, hubStates[shelfID] != nil,
                  sessionIndex[shelf.sourceID] == session else { return }
            let position = shelves.firstIndex(where: { $0.id == shelfID })
            // A successful empty refresh revokes the old row's eligibility. Other rows remain the fallback.
            guard !items.isEmpty else {
                if replacing {
                    if let position { shelves.remove(at: position) }
                    hubStates[shelfID]?.offset = 0
                    hubStates[shelfID]?.total = total
                    hubStates[shelfID]?.exhausted = true
                    hubStates[shelfID]?.refreshedAt = Date()
                    persist()
                } else {
                    hubStates[shelfID]?.exhausted = true
                    hubStates[shelfID]?.refreshedAt = Date()
                }
                return
            }
            let existing = position.map { shelves[$0].items } ?? []
            let merged = AppleCatalogPaging.merge(replacing ? [] : existing,
                page: AppleCatalogPage(items: items, receivedCount: rawCount), pageSize: 1)
            let updated = Shelf(id: shelf.id, title: shelf.title, sourceID: shelf.sourceID, items: merged.items)
            if let position { shelves[position] = updated }
            else {
                let preceding = Set(shelfOrder.prefix { $0 != shelfID })
                let insertion = shelves.filter { preceding.contains($0.id) }.count
                shelves.insert(updated, at: insertion)
            }
            var nextState = state
            nextState.offset = start + rawCount
            nextState.total = total
            nextState.exhausted = merged.isExhausted || nextState.offset >= total
            nextState.refreshedAt = Date()
            hubStates[shelfID] = nextState
            for item in rawItems { index[.init(sourceID: shelf.sourceID, itemID: item.id)] = item }
            for item in plexItems { plexIndex[.init(sourceID: shelf.sourceID, itemID: item.ratingKey)] = item }
            persist()
        } catch {
            // Optional discovery hubs are never a source connection error.
            if !Task.isCancelled, generation == requestGeneration, hubRevisions[shelfID, default: 0] == revision {
                hubStates[shelfID]?.refreshedAt = Date()
            }
        }
    }

    nonisolated private static func isEligible(_ item: ApplePlexItem) -> Bool {
        [.movie, .show, .episode].contains(item.type) && !item.ratingKey.isEmpty && !item.title.isEmpty
    }
    nonisolated private static func isEligible(_ item: AppleMediaServerItem) -> Bool {
        [.movie, .series, .episode].contains(item.type) && !item.id.isEmpty && !item.name.isEmpty
    }

    private struct CachedDetail: Sendable {
        let detail: AppleMediaServerDetail
        let fetchedAt: Date
    }
    private var detailCache: [AppleMediaServerItemReference: CachedDetail] = [:]
    
    public struct AppleMediaServerPlaybackTicket: Sendable {
        let session: AppleMediaServerSession
        let mediaSourceID: String
        let playSessionID: String?
        let playbackID = UUID()
    }

    private var activeTickets: [String: AppleMediaServerPlaybackTicket] = [:]
    private var stoppedSessions: Set<String> = []

    private let client: AppleMediaServerClient
    private let plexClient: ApplePlexClient
    internal var automaticallyDeliversRemoteProgress = true
    private let outbox: AppleRemoteProgressOutbox
    private var deliveryTask: Task<Void, Never>?
    private var generation: Int = 0
    
    public init(client: AppleMediaServerClient = AppleMediaServerClient(), plexClient: ApplePlexClient = ApplePlexClient(), progressDefaults: UserDefaults = .standard) {
        self.client = client
        self.plexClient = plexClient
        self.outbox = AppleRemoteProgressOutbox(defaults: progressDefaults)
    }
    
    public func plexItem(for reference: AppleMediaServerItemReference) -> ApplePlexItem? {
        plexIndex[reference]
    }
    
    public func item(for reference: AppleMediaServerItemReference) -> AppleMediaServerItem? {
        index[reference]
    }
    
    /// Keep the freshest local or server resume fraction on the shelf record.
    public func continueWatchingRecord(for catalogItem: AppleCatalogItem, source: AppleSource,
                                      store localStore: ApplePlaybackStore = ApplePlaybackStore()) -> AppleMediaRecord {
        var record = AppleMediaIngestion.catalogRecord(instanceID: source.id, item: catalogItem)
        let server = playbackState(for: catalogItem.mediaID)
        if !Self.prefersServer(server?.data, localUpdatedAt: localStore.localPlaybackUpdatedAt(mediaID: catalogItem.mediaID)) {
            record.progress = localStore.progress(for: catalogItem.mediaID).map { $0.duration > 0 ? min($0.position / $0.duration, 1) : 0 } ?? 0
            return record
        }
        guard let server, let data = server.data, !data.played,
              let duration = server.duration, duration.isFinite, duration > 0,
              data.positionSeconds.isFinite, data.positionSeconds > 0 else {
            record.progress = 0
            return record
        }
        record.progress = min(data.positionSeconds / duration, 1)
        return record
    }

    private func playbackState(for mediaID: String) -> (data: AppleMediaServerItem.UserData?, duration: Double?)? {
        guard let reference = AppleMediaServerItemReference.parse(mediaID) else { return nil }
        if let plex = plexIndex[reference] {
            return (Self.playbackData(for: plex), plex.durationSeconds)
        }
        guard let item = index[reference] else { return nil }
        return (item.userData, item.runtimeSeconds)
    }

    private static func playbackData(for plex: ApplePlexItem) -> AppleMediaServerItem.UserData {
        .init(positionSeconds: plex.viewOffsetSeconds ?? 0, played: (plex.viewCount ?? 0) > 0,
              playCount: plex.viewCount ?? 0, lastPlayedDate: plex.lastViewedAt)
    }

    /// A newer server completion hides a stale local row without rewriting its saved state.
    public func shouldIncludeInContinueWatching(mediaID: String, store: ApplePlaybackStore) -> Bool {
        let server = playbackState(for: mediaID)
        if Self.prefersServer(server?.data, localUpdatedAt: store.localPlaybackUpdatedAt(mediaID: mediaID)) {
            guard let data = server?.data else { return true }
            if data.played { return false }
            if let duration = server?.duration,
               AppleCompletionPolicy.isComplete(position: data.positionSeconds, duration: duration) { return false }
            return true
        }
        return !store.isRemovedFromContinueWatching(mediaID: mediaID)
            && (!store.hasLocalPlaybackState(mediaID: mediaID) || store.progress(for: mediaID)?.resumePosition != nil)
    }

    public func source(for reference: AppleMediaServerItemReference) -> AppleSource? {
        sourceIndex[reference.sourceID]
    }
    
    public func clear(sourceID: UUID) {
        for shelf in hubDefinitions.values.filter({ $0.sourceID == sourceID }) {
            hubStates.removeValue(forKey: shelf.id)
            hubDefinitions.removeValue(forKey: shelf.id)
            shelfOrder.removeAll { $0 == shelf.id }
            hubRevisions[shelf.id, default: 0] &+= 1
            loadingHubs.remove(shelf.id)
        }
        shelves.removeAll { $0.sourceID == sourceID }
        continueWatching.removeAll { AppleMediaServerItemReference.parse($0.mediaID)?.sourceID == sourceID }
        let keysToRemove = index.keys.filter { $0.sourceID == sourceID }
        for key in keysToRemove {
            index.removeValue(forKey: key)
        }
        let plexKeysToRemove = plexIndex.keys.filter { $0.sourceID == sourceID }
        for key in plexKeysToRemove {
            plexIndex.removeValue(forKey: key)
        }
        let cacheKeysToRemove = detailCache.keys.filter { $0.sourceID == sourceID }
        for key in cacheKeysToRemove {
            detailCache.removeValue(forKey: key)
        }
        sourceIndex.removeValue(forKey: sourceID)
        sessionIndex.removeValue(forKey: sourceID)
        failures.removeValue(forKey: sourceID)
        if sessionIndex.isEmpty {
            deliveryTask?.cancel()
            deliveryTask = nil
        }
        persist()
    }
    
    nonisolated public func catalogItem(_ item: ApplePlexItem, source: AppleSource, session: AppleMediaServerSession) -> AppleCatalogItem {
        let mappedType: String
        switch item.type {
        case .movie: mappedType = "movie"
        case .show, .season, .episode: mappedType = "series"
        default: mappedType = "movie"
        }
        
        let mediaID = AppleMediaServerItemReference(sourceID: source.id, itemID: item.ratingKey).mediaID
        
        let plexClient = ApplePlexClient()
        
        let posterURL: URL?
        if let thumb = item.thumbPath {
            posterURL = plexClient.imageURL(session: session, path: thumb, width: 600, height: 900)
        } else {
            posterURL = nil
        }
        
        let backgroundURL: URL?
        if let art = item.artPath {
            backgroundURL = plexClient.imageURL(session: session, path: art, width: 1920, height: 1080)
        } else {
            backgroundURL = nil
        }
        
        let releaseInfo: String?
        if let y = item.year {
            releaseInfo = String(y)
        } else {
            releaseInfo = nil
        }
        
        return AppleCatalogItem(
            mediaID: mediaID,
            type: mappedType,
            name: item.title,
            posterURL: posterURL,
            backgroundURL: backgroundURL,
            summary: item.summary,
            releaseInfo: releaseInfo,
            rating: nil, // Plex API in client didn't expose rating easily, so nil
            genres: nil, // and genres
            year: item.year
        )
    }

    nonisolated public func catalogItem(_ item: AppleMediaServerItem, source: AppleSource, session: AppleMediaServerSession) -> AppleCatalogItem {
        let mappedType: String
        switch item.type {
        case .movie: mappedType = "movie"
        case .series, .episode: mappedType = "series"
        default: mappedType = "movie"
        }
        
        let mediaID = AppleMediaServerItemReference(sourceID: source.id, itemID: item.id).mediaID
        
        let posterURL: URL?
        if let primaryTag = item.primaryImageTag {
            posterURL = try? client.imageURL(session: session, itemID: item.id, type: .primary, tag: primaryTag, maxWidth: 600)
        } else {
            posterURL = nil
        }
        
        let backgroundURL: URL?
        if let backdropTag = item.backdropImageTags.first {
            backgroundURL = try? client.imageURL(session: session, itemID: item.id, type: .backdrop, tag: backdropTag, maxWidth: nil)
        } else {
            backgroundURL = nil
        }
        
        let releaseInfo: String?
        if let y = item.year {
            releaseInfo = String(y)
        } else {
            releaseInfo = nil
        }
        
        return AppleCatalogItem(
            mediaID: mediaID,
            type: mappedType,
            name: item.name,
            posterURL: posterURL,
            backgroundURL: backgroundURL,
            summary: item.overview,
            releaseInfo: releaseInfo,
            rating: item.communityRating,
            genres: item.genres.isEmpty ? nil : item.genres,
            year: item.year
        )
    }
    
    /// Genre rails from the loaded library page: no extra requests and no invented categories.
    nonisolated static func genreShelves(items: [AppleCatalogItem], sourceID: UUID, libraryID: String) -> [Shelf] {
        let genres = Set(items.flatMap { $0.genres ?? [] }.filter { !$0.isEmpty }).sorted()
        return genres.compactMap { genre in
            let matches = items.filter { $0.genres?.contains(genre) == true }
            guard matches.count >= 2 else { return nil }
            return Shelf(id: "ms:\(sourceID.uuidString.lowercased()):\(libraryID):genre:\(genre)",
                         title: genre, sourceID: sourceID, items: matches)
        }
    }

    public func reload(sources: [AppleSource], session: @MainActor @Sendable (AppleSource) throws -> AppleMediaServerSession?) async {
        generation += 1
        loadingHubs.removeAll()
        let currentGeneration = generation
        isLoading = true
        
        var validSources: [(source: AppleSource, session: AppleMediaServerSession)] = []
        for source in sources where source.kind == .mediaServer && source.isEnabled {
            if let sess = try? session(source) {
                validSources.append((source, sess))
            }
        }
        
        struct RawShelf: Sendable {
            let id: String
            let title: String
            let sourceID: UUID
            let items: [AppleCatalogItem]
            let rawItems: [AppleMediaServerItem]
            var hub: HubState? = nil
        }
        
        struct SourceResult: Sendable {
            let sourceID: UUID
            let shelves: [RawShelf]
            let continueWatching: [AppleCatalogItem]
            let allRawItems: [AppleMediaServerItem]
            let allPlexItems: [ApplePlexItem]
            let source: AppleSource
            let error: String?
        }
        
        sessionIndex = Dictionary(uniqueKeysWithValues: validSources.map { ($0.source.id, $0.session) })
        // A disabled or signed-out source keeps its outbox. Only removal from
        // the complete source list is an explicit deletion of delivery state.
        outbox.retainSources(Set(sources.map(\.id)))
        if sessionIndex.isEmpty {
            deliveryTask?.cancel()
            deliveryTask = nil
        } else {
            scheduleRemoteDelivery()
        }

        let client = self.client
        let plexClient = self.plexClient
        let catalogMapper: @Sendable (AppleMediaServerItem, AppleSource, AppleMediaServerSession) -> AppleCatalogItem = self.catalogItem
        let plexCatalogMapper: @Sendable (ApplePlexItem, AppleSource, AppleMediaServerSession) -> AppleCatalogItem = self.catalogItem
        
        let results = await withTaskGroup(of: SourceResult.self) { group in
            for (source, sess) in validSources {
                group.addTask {
                    do {
                        var allRawItems: [AppleMediaServerItem] = []
                        var allPlexItems: [ApplePlexItem] = []
                        
                        if sess.kind == .plex {
                            let onDeckItems = try await plexClient.onDeck(session: sess)
                            let cwItems = onDeckItems.map { plexCatalogMapper($0, source, sess) }
                            allPlexItems.append(contentsOf: onDeckItems)
                            
                            let sections = try await plexClient.sections(session: sess)
                            var rawShelves: [RawShelf] = []
                            for section in sections {
                                guard section.type == .movie || section.type == .show else { continue }
                                let recent = try await plexClient.recentlyAdded(session: sess, sectionKey: section.key)
                                allPlexItems.append(contentsOf: recent)
                                
                                let shelfItems = recent.map { plexCatalogMapper($0, source, sess) }
                                rawShelves.append(RawShelf(
                                    id: "ms:\(source.id.uuidString.lowercased()):\(section.key):recent",
                                    title: "Recently added in \(section.title)",
                                    sourceID: source.id,
                                    items: shelfItems,
                                    rawItems: []
                                ))
                                let hubs = (try? await plexClient.homeHubs(session: sess, sectionKey: section.key)) ?? []
                                for hub in hubs where ["movie", "show", "episode"].contains(hub.type) && !hub.hubIdentifier.isEmpty {
                                    let eligible = hub.items.filter { Self.isEligible($0) }
                                    guard !hub.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                                          !rawShelves.contains(where: { $0.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == hub.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }) else { continue }
                                    allPlexItems += eligible
                                    let id = "ms:\(source.id.uuidString.lowercased()):\(section.key):hub:\(hub.hubIdentifier)"
                                    guard !rawShelves.contains(where: { $0.id == id }) else { continue }
                                    rawShelves.append(RawShelf(id: id, title: hub.title, sourceID: source.id,
                                        items: eligible.map { plexCatalogMapper($0, source, sess) }, rawItems: [],
                                        hub: HubState(request: .plex(key: hub.key, nextUp: hub.hubIdentifier.lowercased().contains("ondeck") || hub.hubIdentifier.lowercased().contains("nextup")), offset: hub.items.count, total: hub.totalSize)))
                                }
                            }
                            
                            return SourceResult(
                                sourceID: source.id,
                                shelves: rawShelves,
                                continueWatching: cwItems,
                                allRawItems: [],
                                allPlexItems: allPlexItems,
                                source: source,
                                error: nil
                            )
                        }
                        
                        let resumePage = try await client.resume(session: sess, limit: 20)
                        let cwItems = resumePage.items.map { catalogMapper($0, source, sess) }
                        allRawItems.append(contentsOf: resumePage.items)
                        
                        let libraries = try await client.libraries(session: sess)
                        var rawShelves: [RawShelf] = []
                        
                        for library in libraries {
                            guard library.collectionType == .movies || library.collectionType == .tvshows else { continue }
                            
                            let latestItems = try await client.latest(session: sess, parentID: library.id, limit: 20)
                            allRawItems.append(contentsOf: latestItems)
                            
                            let shelfItems = latestItems.map { catalogMapper($0, source, sess) }
                            rawShelves.append(RawShelf(
                                id: "ms:\(source.id.uuidString.lowercased()):\(library.id):latest",
                                title: "Latest in \(library.name)",
                                sourceID: source.id,
                                items: shelfItems,
                                rawItems: latestItems
                            ))
                            if library.collectionType == .tvshows,
                               let next = try? await client.nextUp(session: sess, parentID: library.id) {
                                allRawItems += next.items
                                rawShelves.append(RawShelf(id: "ms:\(source.id.uuidString.lowercased()):\(library.id):nextup",
                                    title: "Next up in \(library.name)", sourceID: source.id,
                                    items: next.items.filter { Self.isEligible($0) }.map { catalogMapper($0, source, sess) }, rawItems: next.items,
                                    hub: HubState(request: .nextUp(parentID: library.id), offset: next.items.count, total: next.totalRecordCount)))
                            }
                            for genre in Self.genreShelves(items: shelfItems, sourceID: source.id, libraryID: library.id) {
                                guard !rawShelves.contains(where: { $0.title.lowercased() == genre.title.lowercased() }) else { continue }
                                let type: AppleMediaServerItemType = library.collectionType == .movies ? .movie : .series
                                let page = try? await client.items(session: sess, parentID: library.id, includeTypes: [type], limit: 20, genres: [genre.title])
                                let eligible = page?.items.filter { Self.isEligible($0) } ?? []
                                allRawItems += eligible
                                rawShelves.append(RawShelf(id: genre.id, title: genre.title, sourceID: source.id,
                                    items: eligible.isEmpty ? genre.items : eligible.map { catalogMapper($0, source, sess) }, rawItems: eligible,
                                    hub: HubState(request: .genre(parentID: library.id, name: genre.title, type: type),
                                        offset: page?.items.count ?? 0, total: page?.totalRecordCount ?? 0)))
                            }
                        }
                        
                        return SourceResult(
                            sourceID: source.id,
                            shelves: rawShelves,
                            continueWatching: cwItems,
                            allRawItems: allRawItems,
                            allPlexItems: [],
                            source: source,
                            error: nil
                        )
                        
                    } catch {
                        let errorMsg: String
                        if let e = error as? AppleMediaServerError {
                            errorMsg = AppleMediaServerFormPolicy.message(for: e)
                        } else {
                            errorMsg = "An unexpected error occurred."
                        }
                        
                        return SourceResult(
                            sourceID: source.id,
                            shelves: [],
                            continueWatching: [],
                            allRawItems: [],
                            allPlexItems: [],
                            source: source,
                            error: errorMsg
                        )
                    }
                }
            }
            
            var collected: [SourceResult] = []
            for await res in group {
                collected.append(res)
            }
            return collected
        }
        
        guard currentGeneration == self.generation else { return }
        
        var nextShelves: [Shelf] = []
        var nextCW: [AppleCatalogItem] = []
        var cwSeen: Set<String> = []
        
        let sortedResults = results.sorted { a, b in
            let aIdx = validSources.firstIndex { $0.source.id == a.sourceID } ?? Int.max
            let bIdx = validSources.firstIndex { $0.source.id == b.sourceID } ?? Int.max
            return aIdx < bIdx
        }
        
        for res in sortedResults {
            if let error = res.error {
                self.failures[res.sourceID] = error
                nextShelves.append(contentsOf: self.shelves.filter { $0.sourceID == res.sourceID })
                nextCW.append(contentsOf: self.continueWatching.filter { AppleMediaServerItemReference.parse($0.mediaID)?.sourceID == res.sourceID })
            } else {
                self.failures.removeValue(forKey: res.sourceID)
                let oldIDs = hubDefinitions.values.filter { $0.sourceID == res.sourceID }.map(\.id)
                for id in oldIDs { hubStates.removeValue(forKey: id); hubDefinitions.removeValue(forKey: id) }
                for shelf in res.shelves {
                    if let hub = shelf.hub {
                        hubStates[shelf.id] = hub
                        hubDefinitions[shelf.id] = Shelf(id: shelf.id, title: shelf.title, sourceID: shelf.sourceID, items: [])
                    }
                }
                nextShelves.append(contentsOf: res.shelves.map { Shelf(id: $0.id, title: $0.title, sourceID: $0.sourceID, items: $0.items) })
                nextCW.append(contentsOf: res.continueWatching)
                
                self.sourceIndex[res.sourceID] = res.source
                if let sess = validSources.first(where: { $0.source.id == res.sourceID })?.session {
                    self.sessionIndex[res.sourceID] = sess
                }
                for item in res.allRawItems {
                    let ref = AppleMediaServerItemReference(sourceID: res.sourceID, itemID: item.id)
                    self.index[ref] = item
                }
                for item in res.allPlexItems {
                    let ref = AppleMediaServerItemReference(sourceID: res.sourceID, itemID: item.ratingKey)
                    self.plexIndex[ref] = item
                }
            }
        }
        
        var finalShelves: [Shelf] = []
        var finalCW: [AppleCatalogItem] = []
        
        for source in sources {
            if let res = sortedResults.first(where: { $0.sourceID == source.id }) {
                if res.error != nil {
                    finalShelves.append(contentsOf: self.shelves.filter { $0.sourceID == source.id })
                    finalCW.append(contentsOf: self.continueWatching.filter { AppleMediaServerItemReference.parse($0.mediaID)?.sourceID == source.id })
                } else {
                    finalShelves.append(contentsOf: res.shelves.map { Shelf(id: $0.id, title: $0.title, sourceID: $0.sourceID, items: $0.items) })
                    finalCW.append(contentsOf: res.continueWatching)
                }
            } else {
                finalShelves.append(contentsOf: self.shelves.filter { $0.sourceID == source.id })
                finalCW.append(contentsOf: self.continueWatching.filter { AppleMediaServerItemReference.parse($0.mediaID)?.sourceID == source.id })
            }
        }
        
        var dedupedCW: [AppleCatalogItem] = []
        for cw in finalCW {
            if !cwSeen.contains(cw.mediaID) {
                cwSeen.insert(cw.mediaID)
                dedupedCW.append(cw)
            }
        }
        
        let oldOrder = shelfOrder
        shelfOrder = sources.flatMap { source in
            if let result = sortedResults.first(where: { $0.sourceID == source.id }), result.error == nil {
                return result.shelves.map(\.id)
            }
            return oldOrder.filter { id in
                hubDefinitions[id]?.sourceID == source.id || finalShelves.contains { $0.id == id && $0.sourceID == source.id }
            }
        }
        self.shelves = finalShelves.filter { !($0.items.isEmpty && hubDefinitions[$0.id] != nil) }
        let liveSourceIDs = Set(sources.map(\.id))
        hubDefinitions = hubDefinitions.filter { liveSourceIDs.contains($0.value.sourceID) }
        hubStates = hubStates.filter { hubDefinitions[$0.key] != nil }
        let localStore = ApplePlaybackStore()
        self.continueWatching = dedupedCW.filter { item in
            shouldIncludeInContinueWatching(mediaID: item.mediaID, store: localStore)
        }
        self.lastLoadedAt = Date()
        self.isLoading = false
        
        persist()
    }
    
    private struct PersistedState: Codable {
        let shelves: [Shelf]
        let continueWatching: [AppleCatalogItem]
        let lastLoadedAt: Date?
    }
    
    private func cacheURL() -> URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let dir = caches.appendingPathComponent("OpenStream")
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir.appendingPathComponent("MediaServers-v1.json")
    }
    
    private func persist() {
        let state = PersistedState(shelves: shelves, continueWatching: continueWatching, lastLoadedAt: lastLoadedAt)
        if let data = try? AppleCachedCredentialPolicy.metadata(JSONEncoder().encode(state)) {
            // Poster and stream URLs here carry X-Plex-Token / api_key.
            var url = cacheURL()
            try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try? url.setResourceValues(values)
        }
    }
    
    public func loadPersisted() {
        guard let data = try? Data(contentsOf: cacheURL()),
              let clean = try? AppleCachedCredentialPolicy.metadata(data),
              let state = try? JSONDecoder().decode(PersistedState.self, from: clean) else {
            return
        }
        self.shelves = state.shelves
        self.continueWatching = state.continueWatching
        self.lastLoadedAt = state.lastLoadedAt
        persist() // Strip tokens from older saved copies as soon as they are read.
    }
    
    public struct AppleMediaServerDetail: Equatable, Sendable {
        public let item: AppleMediaServerItem
        public let source: AppleSource
        public let session: AppleMediaServerSession
        public let seasons: [AppleMediaServerItem]
        public let episodesBySeason: [String: [AppleMediaServerItem]]
        
        public init(item: AppleMediaServerItem, source: AppleSource, session: AppleMediaServerSession, seasons: [AppleMediaServerItem], episodesBySeason: [String: [AppleMediaServerItem]]) {
            self.item = item
            self.source = source
            self.session = session
            self.seasons = seasons
            self.episodesBySeason = episodesBySeason
        }
    }

    private static func prefersServer(_ server: AppleMediaServerItem.UserData?, localUpdatedAt: Date?) -> Bool {
        guard server != nil else { return localUpdatedAt == nil }
        guard let localUpdatedAt else { return true }
        return server?.lastPlayedDate.map { $0 > localUpdatedAt } ?? false
    }

    public static func mergedResume(local: ApplePlaybackProgress?, server: AppleMediaServerItem.UserData?) -> Double? {
        if !prefersServer(server, localUpdatedAt: local?.updatedAt) { return local?.position }
        return server?.played == true ? nil : server?.positionSeconds
    }

    public static func resumePosition(for item: AppleMediaServerItem, local: ApplePlaybackProgress? = nil,
                                      localUpdatedAt: Date? = nil) -> Double? {
        if !prefersServer(item.userData, localUpdatedAt: localUpdatedAt ?? local?.updatedAt) { return local?.resumePosition }
        guard let position = item.userData?.positionSeconds,
              let duration = item.runtimeSeconds, duration > 0,
              position >= 15, item.userData?.played != true,
              !AppleCompletionPolicy.isComplete(position: position, duration: duration) else { return nil }
        return position
    }

    public func attach(to coordinator: ApplePlaybackCoordinator) {
        coordinator.remoteProgressSink = { [weak self] mediaID, position, duration, event in
            guard let self = self else { return }
            self.handleRemoteProgress(mediaID: mediaID, position: position, duration: duration, event: event)
        }
    }

    internal func handleRemoteProgress(mediaID: String, position: Double, duration: Double, event: ApplePlaybackCoordinator.RemoteProgressEvent) {
        guard let ref = AppleMediaServerItemReference.parse(mediaID),
              let ticket = activeTickets[mediaID], !stoppedSessions.contains(mediaID) else { return }
        
        let completed = event == .stopped && AppleCompletionPolicy.isComplete(position: position, duration: duration)
        let baseline = ticket.session.kind == .plex ? (plexIndex[ref]?.viewCount ?? 0) : (index[ref]?.userData?.playCount ?? 0)
        let pendingTarget = outbox.entries.filter { $0.sourceID == ref.sourceID && $0.itemID == ref.itemID }
            .compactMap(\.targetPlayCount).max() ?? baseline
        let completionTarget = completed ? max(baseline, pendingTarget, outbox.highestCompletionTarget(for: ref)) + 1 : nil
        if event == .stopped {
            // One stop per play: a second .stopped for the same request is ignored
            // until `playbackRequest` hands out a new ticket for this media id.
            if stoppedSessions.contains(mediaID) { return }
            stoppedSessions.insert(mediaID)
            applyStop(reference: ref, mediaID: mediaID, position: position, duration: duration)
        }
        
        let remoteEvent: AppleRemoteProgressOutbox.Event
        switch event {
        case .started: remoteEvent = .started
        case .progress: remoteEvent = .progress
        case .paused: remoteEvent = .paused
        case .stopped: remoteEvent = .stopped
        }
        var batch: [AppleRemoteProgressOutbox.Entry] = [.init(sourceID: ref.sourceID, itemID: ref.itemID,
            playbackID: ticket.playbackID, kind: ticket.session.kind,
            mediaSourceID: ticket.session.kind == .plex ? "" : ticket.mediaSourceID, playSessionID: ticket.playSessionID,
            event: remoteEvent, position: max(0, position), duration: max(0, duration), targetPlayCount: nil)]
        if event == .stopped, ticket.session.kind == .plex,
           AppleCompletionPolicy.isComplete(position: position, duration: duration) {
            batch.append(.init(sourceID: ref.sourceID, itemID: ref.itemID,
                playbackID: ticket.playbackID, kind: .plex, mediaSourceID: "",
                playSessionID: ticket.playSessionID, event: .scrobble, position: position,
                duration: duration, targetPlayCount: completionTarget))
        }
        outbox.enqueue(batch)
        scheduleRemoteDelivery()
    }

    private func scheduleRemoteDelivery() {
        guard automaticallyDeliversRemoteProgress, !outbox.isDelivering, !outbox.entries.isEmpty else { return }
        deliveryTask?.cancel()
        deliveryTask = Task { [weak self] in
            guard !Task.isCancelled, let self else { return }
            await self.flushRemoteProgress()
            self.deliveryTask = nil
            if let next = self.outbox.nextAttemptAt(availableSources: Set(self.sessionIndex.keys)) {
                let delay = max(0.05, next.timeIntervalSinceNow)
                self.deliveryTask = Task { [weak self] in
                    do { try await Task.sleep(for: .seconds(delay)) } catch { return }
                    guard let self else { return }
                    self.deliveryTask = nil
                    self.scheduleRemoteDelivery()
                }
            }
        }
    }

    internal func flushRemoteProgress(now: Date = .now) async {
        var affected: Set<AppleMediaServerItemReference> = []
        await outbox.drain(now: now, availableSources: Set(sessionIndex.keys)) { [self] entry in
            guard let session = sessionIndex[entry.sourceID] else { throw AppleMediaServerError.unreachable }
            var delivered = false
            defer {
                if delivered, entry.event == .stopped || entry.event == .scrobble {
                    affected.insert(.init(sourceID: entry.sourceID, itemID: entry.itemID))
                }
            }
            if entry.kind == .plex {
                let item = try await plexClient.item(session: session, ratingKey: entry.itemID)
                if entry.event == .scrobble {
                    // A timeout may mean PMS applied the increment but its response
                    // was lost. Inspect the count before every retry or relaunch.
                    if (item.viewCount ?? 0) < (entry.targetPlayCount ?? 1) {
                        try await plexClient.markPlayed(session: session, ratingKey: entry.itemID)
                    }
                } else {
                    if entry.event == .stopped {
                        let count = item.viewCount ?? 0
                        if let observed = entry.observedPlayCount {
                            if count > observed { delivered = true; return }
                        } else {
                            outbox.checkpointPlayCount(entryID: entry.id, count: count)
                        }
                    }
                    let state: ApplePlexClient.PlaybackState = entry.event == .stopped ? .stopped : entry.event == .paused ? .paused : .playing
                    try await plexClient.reportTimeline(session: session, item: item, state: state, positionSeconds: entry.position)
                }
            } else {
                switch entry.event {
                case .started:
                    try await client.reportPlaybackStart(session: session, itemID: entry.itemID, mediaSourceID: entry.mediaSourceID, playSessionID: entry.playSessionID, positionSeconds: entry.position)
                case .progress, .paused:
                    try await client.reportPlaybackProgress(session: session, itemID: entry.itemID, mediaSourceID: entry.mediaSourceID, playSessionID: entry.playSessionID, positionSeconds: entry.position, isPaused: entry.event == .paused)
                case .stopped:
                    let fresh = try await client.item(session: session, id: entry.itemID)
                    let count = fresh.userData?.playCount ?? 0
                    if let observed = entry.observedPlayCount {
                        if count > observed { delivered = true; return }
                    } else {
                        // Checkpoint the authoritative pre-stop count before the
                        // request. Partial stops can increment too on some servers.
                        outbox.checkpointPlayCount(entryID: entry.id, count: count)
                    }
                    try await client.reportPlaybackStopped(session: session, itemID: entry.itemID, mediaSourceID: entry.mediaSourceID, playSessionID: entry.playSessionID, positionSeconds: entry.position)
                case .scrobble: break
                }
            }
            delivered = true
        }
        for reference in affected { await refreshAffectedHubs(reference: reference) }
    }

    /// Mirrors a finished play into the in-memory item and the resume row at
    /// once, so Continue Watching is right before the server answers.
    private func applyStop(reference ref: AppleMediaServerItemReference, mediaID: String, position: Double, duration: Double) {
        guard let item = index[ref] else { return }
        let played = AppleCompletionPolicy.isComplete(position: position, duration: duration)
        let old = item.userData
        let newUserData = AppleMediaServerItem.UserData(
            positionSeconds: played ? 0 : position,
            played: played || (old?.played ?? false),
            isFavorite: old?.isFavorite ?? false,
            playCount: (old?.playCount ?? 0) + (played ? 1 : 0),
            lastPlayedDate: old?.lastPlayedDate
        )
        let newItem = item.withUserData(newUserData)
        index[ref] = newItem
        detailCache.removeValue(forKey: ref)
        continueWatching.removeAll(where: { $0.mediaID == mediaID })
        if !played, let source = sourceIndex[ref.sourceID], let sess = sessionIndex[ref.sourceID] {
            continueWatching.insert(catalogItem(newItem, source: source, session: sess), at: 0)
        }
        persist()
    }

    public func detail(for reference: AppleMediaServerItemReference) async throws -> AppleMediaServerDetail {
        if let cached = detailCache[reference], Date().timeIntervalSince(cached.fetchedAt) < 600 {
            return cached.detail
        }
        
        guard let source = sourceIndex[reference.sourceID],
              let session = sessionIndex[reference.sourceID] else {
            throw AppleMediaServerError.unsupported
        }
        
        if session.kind == .plex {
            let freshPlexItem = try await plexClient.item(session: session, ratingKey: reference.itemID)
            plexIndex[reference] = freshPlexItem
            
            var plexSeasons: [ApplePlexItem] = []
            var plexEpisodesBySeason: [String: [ApplePlexItem]] = [:]
            
            if freshPlexItem.type == .show {
                plexSeasons = try await plexClient.children(session: session, ratingKey: freshPlexItem.ratingKey)
                for season in plexSeasons {
                    let episodes = try await plexClient.children(session: session, ratingKey: season.ratingKey)
                    plexEpisodesBySeason[season.ratingKey] = episodes
                }
            }
            
            func toMediaServerItem(_ plex: ApplePlexItem) -> AppleMediaServerItem {
                let type: AppleMediaServerItemType
                switch plex.type {
                case .movie: type = .movie
                case .show: type = .series
                case .season: type = .season
                case .episode: type = .episode
                case .other: type = .other
                }
                
                var userData: AppleMediaServerItem.UserData?
                if plex.viewCount != nil || plex.viewOffsetSeconds != nil {
                    let viewOffset = plex.viewOffsetSeconds ?? 0
                    userData = AppleMediaServerItem.UserData(
                        positionSeconds: viewOffset,
                        played: (plex.viewCount ?? 0) > 0,
                        isFavorite: false,
                        playCount: plex.viewCount ?? 0,
                        lastPlayedDate: plex.lastViewedAt
                    )
                }
                
                return AppleMediaServerItem(
                    id: plex.ratingKey,
                    name: plex.title,
                    type: type,
                    year: plex.year,
                    overview: plex.summary,
                    runtimeSeconds: plex.durationSeconds,
                    seriesID: freshPlexItem.ratingKey,
                    seasonID: plex.parentRatingKey,
                    indexNumber: plex.index,
                    parentIndexNumber: plex.parentIndex,
                    userData: userData
                )
            }
            
            let freshItem = toMediaServerItem(freshPlexItem)
            index[reference] = freshItem
            
            var seasons: [AppleMediaServerItem] = []
            var episodesBySeason: [String: [AppleMediaServerItem]] = [:]
            
            for pSeason in plexSeasons {
                seasons.append(toMediaServerItem(pSeason))
                if let pEps = plexEpisodesBySeason[pSeason.ratingKey] {
                    episodesBySeason[pSeason.ratingKey] = pEps.map { toMediaServerItem($0) }
                }
            }
            
            let detail = AppleMediaServerDetail(item: freshItem, source: source, session: session, seasons: seasons, episodesBySeason: episodesBySeason)
            detailCache[reference] = CachedDetail(detail: detail, fetchedAt: Date())
            return detail
        }
        
        let freshItem = try await client.item(session: session, id: reference.itemID)
        index[reference] = freshItem
        
        var seasons: [AppleMediaServerItem] = []
        var episodesBySeason: [String: [AppleMediaServerItem]] = [:]
        
        if freshItem.type == .series || freshItem.type == .episode {
            let allSeasons = try await client.seasons(session: session, seriesID: reference.itemID)
            
            let episodes = await withTaskGroup(of: (String, [AppleMediaServerItem]).self) { group in
                for season in allSeasons {
                    group.addTask {
                        let eps = (try? await self.client.episodes(session: session, seriesID: reference.itemID, seasonID: season.id)) ?? []
                        return (season.id, eps)
                    }
                }
                var collected: [String: [AppleMediaServerItem]] = [:]
                for await res in group {
                    if !res.1.isEmpty {
                        collected[res.0] = res.1
                    }
                }
                return collected
            }
            
            for season in allSeasons {
                if let eps = episodes[season.id], !eps.isEmpty {
                    seasons.append(season)
                    episodesBySeason[season.id] = eps
                }
            }
        }
        
        let detail = AppleMediaServerDetail(item: freshItem, source: source, session: session, seasons: seasons, episodesBySeason: episodesBySeason)
        detailCache[reference] = CachedDetail(detail: detail, fetchedAt: Date())
        return detail
    }

    nonisolated static func offlinePlaybackRequest(record: AppleOfflineRecord, title: String, resumePosition: Double?) throws -> ApplePlaybackRequest {
        guard record.localURL.isFileURL else { throw AppleOfflineStoreError.uncontainedSourceFileURL }
        return ApplePlaybackRequest(url: record.localURL, headers: [:], isLive: false,
            resumePosition: resumePosition, autoplay: true, mediaID: record.mediaID,
            title: title, sourceName: "Downloads", sourceKind: .mediaServer,
            hints: .init(libraryFileURL: record.localURL))
    }

    public func downloadsAllowed(in detail: AppleMediaServerDetail) async throws -> Bool {
        if detail.session.kind == .plex { return try await plexClient.downloadsAllowed(session: detail.session) }
        return try await client.downloadsAllowed(session: detail.session)
    }

    func downloadPlan(reference: AppleMediaServerItemReference) async throws -> AppleOfflineDownloadPlan {
        let detail = try await detail(for: reference)
        let allowed = try await downloadsAllowed(in: detail)
        guard allowed else { throw AppleMediaServerError.downloadNotAllowed }
        let request: URLRequest
        if detail.session.kind == .plex {
            let fresh = try await plexClient.item(session: detail.session, ratingKey: reference.itemID)
            guard [.movie, .episode].contains(fresh.type), let part = fresh.parts.first else {
                throw AppleMediaServerError.unsupported
            }
            request = try plexClient.downloadRequest(session: detail.session, part: part, allowed: allowed)
        } else {
            guard [.movie, .episode].contains(detail.item.type) else { throw AppleMediaServerError.unsupported }
            request = try client.downloadRequest(session: detail.session, itemID: reference.itemID, allowed: allowed)
        }
        guard let url = request.url else { throw AppleMediaServerError.unreachable }
        return .init(sourceURL: url, requestHeaders: request.allHTTPHeaderFields ?? [:],
                     protectedCapabilityToRevoke: nil, usesBackgroundSession: true)
    }

    public func playbackRequest(for item: AppleMediaServerItem, in detail: AppleMediaServerDetail, resume: Bool) async throws -> ApplePlaybackRequest {
        if detail.session.kind == .plex {
            guard let plexItem = plexIndex[AppleMediaServerItemReference(sourceID: detail.source.id, itemID: item.id)] else {
                throw AppleMediaServerError.unsupported
            }
            guard let part = plexItem.parts.first else {
                throw AppleMediaServerError.unsupported
            }
            let url = plexClient.directPlayURL(session: detail.session, part: part)
            
            let mediaID = AppleMediaServerItemReference(sourceID: detail.source.id, itemID: item.id).mediaID
            stoppedSessions.remove(mediaID)
            activeTickets[mediaID] = AppleMediaServerPlaybackTicket(
                session: detail.session,
                mediaSourceID: part.key,
                playSessionID: nil
            )
            
            let position: Double?
            let localStore = ApplePlaybackStore()
            position = resume ? Self.resumePosition(for: item.withUserData(Self.playbackData(for: plexItem)),
                local: localStore.progress(for: mediaID),
                localUpdatedAt: localStore.localPlaybackUpdatedAt(mediaID: mediaID)) : nil

            let title: String
            if item.type == .episode {
                let sIdx = item.parentIndexNumber.map { String($0) } ?? "?"
                let eIdx = item.indexNumber.map { String($0) } ?? "?"
                let series = item.seriesName ?? detail.item.name
                title = "\(series) S\(sIdx)E\(eIdx)"
            } else {
                title = item.name
            }
            
            return ApplePlaybackRequest(
                url: url,
                headers: ["X-Plex-Token": detail.session.accessToken],
                isLive: false,
                resumePosition: position,
                autoplay: true,
                mediaID: mediaID,
                title: title,
                sourceName: detail.source.name,
                sourceKind: .mediaServer,
                hints: ApplePlaybackRequest.Hints()
            )
        }
        
        let info = try await client.playbackInfo(session: detail.session, itemID: item.id)
        
        guard let mediaSource = info.mediaSources.first(where: { $0.supportsDirectPlay || $0.supportsDirectStream }) else {
            throw AppleMediaServerError.unsupported
        }
        
        let container = mediaSource.container?.components(separatedBy: ",").first ?? mediaSource.container
        let url = try client.directStreamURL(
            session: detail.session,
            itemID: item.id,
            mediaSourceID: mediaSource.id,
            container: container
        )
        
        let mediaID = AppleMediaServerItemReference(sourceID: detail.source.id, itemID: item.id).mediaID
        stoppedSessions.remove(mediaID)
        activeTickets[mediaID] = AppleMediaServerPlaybackTicket(
            session: detail.session,
            mediaSourceID: mediaSource.id,
            playSessionID: info.playSessionID
        )

        let localStore = ApplePlaybackStore()
        let position = resume ? Self.resumePosition(for: item, local: localStore.progress(for: mediaID),
            localUpdatedAt: localStore.localPlaybackUpdatedAt(mediaID: mediaID)) : nil
        
        let title: String
        if item.type == .episode {
            let sIdx = item.parentIndexNumber.map { String($0) } ?? "?"
            let eIdx = item.indexNumber.map { String($0) } ?? "?"
            let sName = item.seriesName ?? detail.item.name
            title = "\(sName) · S\(sIdx)E\(eIdx) \(item.name)"
        } else {
            title = item.name
        }
        
        return ApplePlaybackRequest(
            url: url,
            headers: [:],
            isLive: false,
            resumePosition: position,
            autoplay: true,
            mediaID: mediaID,
            title: title,
            sourceName: detail.source.name,
            sourceKind: .mediaServer,
            hints: ApplePlaybackRequest.Hints()
        )
    }

    public func metadata(from detail: AppleMediaServerDetail) -> AppleTMDBDetails {
        let item = detail.item
        
        let posterURL: URL? = {
            if let tag = item.primaryImageTag {
                return try? client.imageURL(session: detail.session, itemID: item.id, type: .primary, tag: tag, maxWidth: 600)
            }
            return nil
        }()
        
        let backdropURL: URL? = {
            if let tag = item.backdropImageTags.first {
                return try? client.imageURL(session: detail.session, itemID: item.id, type: .backdrop, tag: tag, maxWidth: nil)
            }
            return nil
        }()
        
        let logoURL: URL? = {
            if let tag = item.logoImageTag {
                return try? client.imageURL(session: detail.session, itemID: item.id, type: .logo, tag: tag, maxWidth: 600)
            }
            return nil
        }()
        
        let runtimeMinutes = item.runtimeSeconds.map { Int($0 / 60) }
        let mappedType = (item.type == .series || item.type == .episode) ? "series" : "movie"
        
        return AppleTMDBDetails(
            mediaID: AppleMediaServerItemReference(sourceID: detail.source.id, itemID: item.id).mediaID,
            mediaType: mappedType,
            title: item.name,
            releaseInfo: item.year.map { String($0) },
            runtimeMinutes: runtimeMinutes,
            genres: item.genres,
            imdbRating: item.communityRating,
            year: item.year,
            overview: item.overview,
            posterURL: posterURL,
            backdropURL: backdropURL,
            logoURL: logoURL
        )
    }

    public func episodes(from detail: AppleMediaServerDetail) -> [AppleStremioEpisode] {
        var results: [AppleStremioEpisode] = []
        for season in detail.seasons {
            if let eps = detail.episodesBySeason[season.id] {
                for ep in eps {
                    let thumbURL: URL? = {
                        if let tag = ep.primaryImageTag {
                            return try? client.imageURL(session: detail.session, itemID: ep.id, type: .primary, tag: tag, maxWidth: 600)
                        }
                        return nil
                    }()
                    
                    results.append(AppleStremioEpisode(
                        id: ep.id, // the raw item id for playbackRequest
                        title: ep.name,
                        season: ep.parentIndexNumber,
                        episode: ep.indexNumber,
                        releaseInfo: ep.year.map { String($0) },
                        runtimeMinutes: ep.runtimeSeconds.map { Int($0 / 60) },
                        overview: ep.overview,
                        thumbnailURL: thumbURL
                    ))
                }
            }
        }
        return results
    }
}
