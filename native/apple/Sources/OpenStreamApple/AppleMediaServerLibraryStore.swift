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

    public private(set) var shelves: [Shelf] = []
    public private(set) var continueWatching: [AppleCatalogItem] = []
    public private(set) var isLoading = false
    public private(set) var failures: [UUID: String] = [:]
    public private(set) var lastLoadedAt: Date?
    
    private var index: [AppleMediaServerItemReference: AppleMediaServerItem] = [:]
    private var sourceIndex: [UUID: AppleSource] = [:]
    
    private let client: AppleMediaServerClient
    private var generation: Int = 0
    
    public init(client: AppleMediaServerClient = AppleMediaServerClient()) {
        self.client = client
    }
    
    public func item(for reference: AppleMediaServerItemReference) -> AppleMediaServerItem? {
        index[reference]
    }
    
    public func source(for reference: AppleMediaServerItemReference) -> AppleSource? {
        sourceIndex[reference.sourceID]
    }
    
    public func clear(sourceID: UUID) {
        shelves.removeAll { $0.sourceID == sourceID }
        continueWatching.removeAll { AppleMediaServerItemReference.parse($0.mediaID)?.sourceID == sourceID }
        let keysToRemove = index.keys.filter { $0.sourceID == sourceID }
        for key in keysToRemove {
            index.removeValue(forKey: key)
        }
        sourceIndex.removeValue(forKey: sourceID)
        failures.removeValue(forKey: sourceID)
        persist()
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
    
    public func reload(sources: [AppleSource], session: @MainActor @Sendable (AppleSource) throws -> AppleMediaServerSession?) async {
        generation += 1
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
        }
        
        struct SourceResult: Sendable {
            let sourceID: UUID
            let shelves: [RawShelf]
            let continueWatching: [AppleCatalogItem]
            let allRawItems: [AppleMediaServerItem]
            let source: AppleSource
            let error: String?
        }
        
        let client = self.client
        let catalogMapper = self.catalogItem
        
        let results = await withTaskGroup(of: SourceResult.self) { group in
            for (source, sess) in validSources {
                group.addTask {
                    do {
                        var allRawItems: [AppleMediaServerItem] = []
                        
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
                        }
                        
                        return SourceResult(
                            sourceID: source.id,
                            shelves: rawShelves,
                            continueWatching: cwItems,
                            allRawItems: allRawItems,
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
                nextShelves.append(contentsOf: res.shelves.map { Shelf(id: $0.id, title: $0.title, sourceID: $0.sourceID, items: $0.items) })
                nextCW.append(contentsOf: res.continueWatching)
                
                self.sourceIndex[res.sourceID] = res.source
                for item in res.allRawItems {
                    let ref = AppleMediaServerItemReference(sourceID: res.sourceID, itemID: item.id)
                    self.index[ref] = item
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
        
        self.shelves = finalShelves
        self.continueWatching = dedupedCW
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
        if let data = try? JSONEncoder().encode(state) {
            try? data.write(to: cacheURL(), options: .atomic)
        }
    }
    
    public func loadPersisted() {
        guard let data = try? Data(contentsOf: cacheURL()),
              let state = try? JSONDecoder().decode(PersistedState.self, from: data) else {
            return
        }
        self.shelves = state.shelves
        self.continueWatching = state.continueWatching
        self.lastLoadedAt = state.lastLoadedAt
    }
}
