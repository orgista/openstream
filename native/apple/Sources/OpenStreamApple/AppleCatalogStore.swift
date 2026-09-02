import Foundation
import Observation

public enum AppleCatalogDiscoveryPolicy {
    public static let defaultMaximumCatalogs = 8
    public static let hardMaximumCatalogs = 12
    public static let maximumConcurrentRequests = 4
    public static let maximumTotalRequests = 48
    public static let maximumItemsPerCatalog = 100
    public static let cacheFreshness: TimeInterval = 6 * 60 * 60

    public static func catalogs(
        for source: AppleSource,
        maximumCatalogs: Int = defaultMaximumCatalogs
    ) -> [AppleStremioCatalog] {
        guard source.kind == .stremio,
              source.isEnabled,
              source.resources.contains(where: { $0.caseInsensitiveCompare("catalog") == .orderedSame }) else {
            return []
        }
        let limit = min(max(maximumCatalogs, 0), hardMaximumCatalogs)
        guard limit > 0 else { return [] }
        var seen = Set<String>()
        var result: [AppleStremioCatalog] = []
        for catalog in source.catalogs {
            let key = "\(catalog.type):\(catalog.id)"
            guard !catalog.requiresInput,
                  ["movie", "series"].contains(catalog.type),
                  !catalog.id.isEmpty,
                  seen.insert(key).inserted else {
                continue
            }
            result.append(catalog)
            if result.count == limit { break }
        }
        return result
    }

    public static func sourceConfigurationID(for source: AppleSource) -> String {
        let value = [
            source.manifestID ?? "",
            source.version ?? "",
            source.transportURL.absoluteString,
        ].joined(separator: "\u{1f}")
        return ApplePlaybackIdentity.digest(for: value)
    }
}

public struct AppleCatalogItem: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public let mediaID: String
    public let type: String
    public let name: String
    public let posterURL: URL?
    public let backgroundURL: URL?
    public let summary: String?
    public let releaseInfo: String?
    public let rating: Double?

    public init(
        mediaID: String,
        type: String,
        name: String,
        posterURL: URL? = nil,
        backgroundURL: URL? = nil,
        summary: String? = nil,
        releaseInfo: String? = nil,
        rating: Double? = nil
    ) {
        let normalizedType = String(type.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().prefix(40))
        let normalizedMediaID = String(mediaID.trimmingCharacters(in: .whitespacesAndNewlines).prefix(300))
        id = "\(normalizedType):\(normalizedMediaID)"
        self.mediaID = normalizedMediaID
        self.type = normalizedType
        self.name = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(200))
        self.posterURL = posterURL
        self.backgroundURL = backgroundURL
        self.summary = summary?.trimmedAndLimited(to: 4_000)
        self.releaseInfo = releaseInfo?.trimmedAndLimited(to: 100)
        self.rating = rating.flatMap { $0.isFinite && (0 ... 10).contains($0) ? $0 : nil }
    }

    public func withMediaID(_ mediaID: String) -> AppleCatalogItem {
        AppleCatalogItem(
            mediaID: mediaID,
            type: type,
            name: name,
            posterURL: posterURL,
            backgroundURL: backgroundURL,
            summary: summary,
            releaseInfo: releaseInfo,
            rating: rating
        )
    }
}

public struct AppleCatalogSection: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public let sourceID: AppleSource.ID
    public let sourceName: String
    public let sourceConfigurationID: String
    public let catalog: AppleStremioCatalog
    public let items: [AppleCatalogItem]

    public init(source: AppleSource, catalog: AppleStremioCatalog, items: [AppleCatalogItem]) {
        id = "\(source.id.uuidString):\(catalog.type):\(catalog.id)"
        sourceID = source.id
        sourceName = String(source.name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(100))
        sourceConfigurationID = AppleCatalogDiscoveryPolicy.sourceConfigurationID(for: source)
        self.catalog = catalog
        self.items = Array(items.prefix(AppleCatalogDiscoveryPolicy.maximumItemsPerCatalog))
    }

    private enum CodingKeys: String, CodingKey {
        case id, sourceID, sourceName, sourceConfigurationID, catalog, items
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        sourceID = try container.decode(AppleSource.ID.self, forKey: .sourceID)
        sourceName = String(try container.decode(String.self, forKey: .sourceName).prefix(100))
        sourceConfigurationID = try container.decodeIfPresent(String.self, forKey: .sourceConfigurationID) ?? ""
        catalog = try container.decode(AppleStremioCatalog.self, forKey: .catalog)
        items = Array((try container.decode([AppleCatalogItem].self, forKey: .items))
            .prefix(AppleCatalogDiscoveryPolicy.maximumItemsPerCatalog))
    }
}

public enum AppleStremioCatalogError: Swift.Error, Equatable, LocalizedError, Sendable {
    case invalidSource
    case nonHTTPResponse
    case insecureRedirect
    case requestFailed(Int)
    case responseTooLarge
    case invalidCatalog

    public var errorDescription: String? {
        switch self {
        case .invalidSource: "The source does not expose this catalog."
        case .nonHTTPResponse: "The catalog returned an invalid response."
        case .insecureRedirect: "The catalog redirected to an insecure address."
        case .requestFailed(let status): "The catalog request failed with HTTP \(status)."
        case .responseTooLarge: "The catalog response is too large."
        case .invalidCatalog: "The catalog response is invalid."
        }
    }
}

public struct AppleStremioCatalogClient: Sendable {
    public typealias Loader = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    private static let maximumResponseBytes = 2_000_000
    private let loader: Loader

    public init(loader: @escaping Loader = AppleStremioCatalogClient.liveLoader) {
        self.loader = loader
    }

    public func load(source: AppleSource, catalog: AppleStremioCatalog) async throws -> [AppleCatalogItem] {
        guard source.kind == .stremio,
              source.isEnabled,
              source.resources.contains(where: { $0.caseInsensitiveCompare("catalog") == .orderedSame }),
              !catalog.requiresInput,
              ["movie", "series"].contains(catalog.type),
              !catalog.id.isEmpty,
              source.catalogs.contains(where: { $0.type == catalog.type && $0.id == catalog.id }) else {
            throw AppleStremioCatalogError.invalidSource
        }
        let url = try Self.endpoint(source: source, catalog: catalog)
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("OpenStream/1.0 Apple", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await loader(request)
        guard let http = response as? HTTPURLResponse else { throw AppleStremioCatalogError.nonHTTPResponse }
        guard http.url?.scheme?.lowercased() == "https" else { throw AppleStremioCatalogError.insecureRedirect }
        guard (200 ... 299).contains(http.statusCode) else {
            throw AppleStremioCatalogError.requestFailed(http.statusCode)
        }
        guard data.count <= Self.maximumResponseBytes else { throw AppleStremioCatalogError.responseTooLarge }
        guard let payload = try? JSONDecoder().decode(CatalogPayload.self, from: data) else {
            throw AppleStremioCatalogError.invalidCatalog
        }

        var seen = Set<String>()
        var items: [AppleCatalogItem] = []
        items.reserveCapacity(min(payload.metas.count, AppleCatalogDiscoveryPolicy.maximumItemsPerCatalog))
        for meta in payload.metas {
            let mediaID = meta.id.trimmingCharacters(in: .whitespacesAndNewlines)
            let name = meta.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let type = (meta.type?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmptyCatalogString ?? catalog.type)
                .lowercased()
            let identity = "\(type):\(mediaID)"
            guard ["movie", "series"].contains(type),
                  !mediaID.isEmpty,
                  !name.isEmpty,
                  seen.insert(identity).inserted else {
                continue
            }
            items.append(AppleCatalogItem(
                mediaID: mediaID,
                type: type,
                name: name,
                posterURL: webURL(meta.poster),
                backgroundURL: webURL(meta.background),
                summary: meta.description,
                releaseInfo: meta.releaseInfo,
                rating: meta.rating
            ))
            if items.count == AppleCatalogDiscoveryPolicy.maximumItemsPerCatalog { break }
        }
        return items
    }

    public static func endpoint(source: AppleSource, catalog: AppleStremioCatalog) throws -> URL {
        let base = source.transportURL
        guard ["movie", "series"].contains(catalog.type),
              !catalog.id.isEmpty,
              base.scheme?.lowercased() == "https",
              base.host?.isEmpty == false,
              var components = URLComponents(url: base, resolvingAgainstBaseURL: false),
              components.query == nil,
              components.fragment == nil else {
            throw AppleStremioCatalogError.invalidSource
        }

        let encodedType = encodePathSegment(catalog.type)
        let encodedID = encodePathSegment(catalog.id)
        guard !encodedType.isEmpty, !encodedID.isEmpty else { throw AppleStremioCatalogError.invalidSource }
        var path = components.percentEncodedPath
        if !path.hasSuffix("/") { path += "/" }
        components.percentEncodedPath = "\(path)catalog/\(encodedType)/\(encodedID).json"
        guard let url = components.url else { throw AppleStremioCatalogError.invalidSource }
        return url
    }

    public static func liveLoader(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await AppleBoundedHTTPDataLoader.load(request, maximumBytes: maximumResponseBytes)
        } catch AppleBoundedHTTPError.responseTooLarge {
            throw AppleStremioCatalogError.responseTooLarge
        }
    }

    private static func encodePathSegment(_ value: String) -> String {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
    }

    private func webURL(_ value: String?) -> URL? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              value.utf8.count <= 2_048,
              let url = URL(string: value),
              let scheme = url.scheme?.lowercased(),
              ["https", "http"].contains(scheme),
              url.host?.isEmpty == false else {
            return nil
        }
        return url
    }

    private struct CatalogPayload: Decodable {
        let metas: [Meta]

        private enum CodingKeys: String, CodingKey { case metas }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            metas = try container.decode(MetaList.self, forKey: .metas).values
        }

        private struct MetaList: Decodable {
            let values: [Meta]

            init(from decoder: Decoder) throws {
                var container = try decoder.unkeyedContainer()
                var result: [Meta] = []
                var inspected = 0
                while !container.isAtEnd,
                      inspected < 400,
                      result.count < AppleCatalogDiscoveryPolicy.maximumItemsPerCatalog * 2 {
                    inspected += 1
                    let entry = try container.superDecoder()
                    if let value = try? Meta(from: entry) { result.append(value) }
                }
                values = result
            }
        }
    }

    private struct Meta: Decodable {
        let id: String
        let type: String?
        let name: String
        let poster: String?
        let background: String?
        let description: String?
        let releaseInfo: String?
        let rating: Double?

        private enum CodingKeys: String, CodingKey {
            case id, type, name, poster, background, description, releaseInfo, imdbRating
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(String.self, forKey: .id)
            type = try? container.decode(String.self, forKey: .type)
            name = try container.decode(String.self, forKey: .name)
            poster = try? container.decode(String.self, forKey: .poster)
            background = try? container.decode(String.self, forKey: .background)
            description = try? container.decode(String.self, forKey: .description)
            releaseInfo = try? container.decode(String.self, forKey: .releaseInfo)
            if let value = try? container.decode(Double.self, forKey: .imdbRating) {
                rating = value.isFinite ? value : nil
            } else if let string = try? container.decode(String.self, forKey: .imdbRating) {
                rating = Double(string.trimmingCharacters(in: .whitespacesAndNewlines))
            } else {
                rating = nil
            }
        }
    }
}

public struct AppleCatalogCacheSnapshot: Equatable, Sendable {
    public let sections: [AppleCatalogSection]
    public let updatedAt: Date
    public let isFresh: Bool
}

public actor AppleCatalogCache {
    private struct StoredCache: Codable {
        let updatedAt: Date
        let sections: [AppleCatalogSection]
        let isComplete: Bool?
    }

    private static let maximumCacheBytes = 10_000_000

    private let fileURL: URL
    private let fileManager: FileManager

    public init(fileURL: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.fileURL = fileURL ?? fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appending(path: "OpenStream", directoryHint: .isDirectory)
            .appending(path: "catalogs-v2.json")
    }

    public func load(
        sources: [AppleSource],
        maximumCatalogs: Int = AppleCatalogDiscoveryPolicy.defaultMaximumCatalogs,
        now: Date = .now
    ) -> AppleCatalogCacheSnapshot? {
        guard let attributes = try? fileManager.attributesOfItem(atPath: fileURL.path),
              let size = attributes[.size] as? NSNumber,
              size.intValue <= Self.maximumCacheBytes,
              let data = try? Data(contentsOf: fileURL),
              let stored = try? JSONDecoder().decode(StoredCache.self, from: data) else {
            return nil
        }

        let configured = sources.reduce(into: [AppleSource.ID: AppleSource]()) { $0[$1.id] = $1 }
        var seenSections = Set<String>()
        let filtered = stored.sections.compactMap { section -> AppleCatalogSection? in
            guard let source = configured[section.sourceID],
                  section.sourceConfigurationID == AppleCatalogDiscoveryPolicy.sourceConfigurationID(for: source),
                  let catalog = AppleCatalogDiscoveryPolicy.catalogs(
                      for: source,
                      maximumCatalogs: maximumCatalogs
                  ).first(where: {
                      $0.type == section.catalog.type && $0.id == section.catalog.id
                  }),
                  seenSections.insert("\(section.sourceID):\(section.catalog.type):\(section.catalog.id)").inserted else {
                return nil
            }
            return AppleCatalogSection(source: source, catalog: catalog, items: section.items)
        }
        let age = now.timeIntervalSince(stored.updatedAt)
        return AppleCatalogCacheSnapshot(
            sections: filtered,
            updatedAt: stored.updatedAt,
            isFresh: (stored.isComplete ?? true)
                && filtered.contains(where: { !$0.items.isEmpty })
                && age >= 0
                && age < AppleCatalogDiscoveryPolicy.cacheFreshness
        )
    }

    public func save(
        _ sections: [AppleCatalogSection],
        isComplete: Bool = true,
        now: Date = .now
    ) throws {
        try fileManager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(StoredCache(
            updatedAt: now,
            sections: sections,
            isComplete: isComplete
        ))
        guard data.count <= Self.maximumCacheBytes else { return }
        try data.write(to: fileURL, options: [.atomic])
        var excludedURL = fileURL
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? excludedURL.setResourceValues(values)
    }

    public func clear() throws {
        guard fileManager.fileExists(atPath: fileURL.path) else { return }
        try fileManager.removeItem(at: fileURL)
    }
}

@MainActor
@Observable
public final class AppleCatalogStore {
    public private(set) var sections: [AppleCatalogSection] = []
    public private(set) var partialErrors: [String] = []
    public private(set) var isLoading = false

    private let client: AppleStremioCatalogClient
    private let cache: AppleCatalogCache
    private var refreshGeneration: UInt64 = 0
    private var cacheIsFresh = false
    private var cachedRequestIDs = Set<String>()
    private var activeRefreshTask: Task<[CatalogFetchResult], Never>?
    private var activeRefreshTaskGeneration: UInt64?

    public init(
        client: AppleStremioCatalogClient = AppleStremioCatalogClient(),
        cache: AppleCatalogCache = AppleCatalogCache()
    ) {
        self.client = client
        self.cache = cache
    }

    public func loadCachedSections(
        sources: [AppleSource],
        maximumCatalogs: Int = AppleCatalogDiscoveryPolicy.defaultMaximumCatalogs,
        now: Date = .now
    ) async {
        refreshGeneration &+= 1
        let generation = refreshGeneration
        await cancelActiveRefresh()
        guard refreshGeneration == generation, !Task.isCancelled else { return }
        guard let snapshot = await cache.load(
            sources: sources,
            maximumCatalogs: maximumCatalogs,
            now: now
        ),
              refreshGeneration == generation,
              !Task.isCancelled else {
            guard refreshGeneration == generation else { return }
            sections = []
            cacheIsFresh = false
            cachedRequestIDs = []
            isLoading = false
            return
        }
        sections = snapshot.sections
        cacheIsFresh = snapshot.isFresh
        cachedRequestIDs = Set(snapshot.sections.map(Self.requestID(for:)))
        isLoading = false
    }

    public func refresh(
        sources: [AppleSource],
        maximumCatalogs: Int = AppleCatalogDiscoveryPolicy.defaultMaximumCatalogs,
        force: Bool = false
    ) async {
        refreshGeneration &+= 1
        let generation = refreshGeneration
        var seenRequestIDs = Set<String>()
        var requests: [CatalogRequest] = []
        sourceLoop: for source in sources {
            for catalog in AppleCatalogDiscoveryPolicy.catalogs(for: source, maximumCatalogs: maximumCatalogs) {
                let request = CatalogRequest(source: source, catalog: catalog)
                if seenRequestIDs.insert(request.id).inserted { requests.append(request) }
                if requests.count == AppleCatalogDiscoveryPolicy.maximumTotalRequests { break sourceLoop }
            }
        }
        let requestIDs = Set(requests.map(\.id))

        await cancelActiveRefresh()
        guard refreshGeneration == generation, !Task.isCancelled else { return }

        if !force, cacheIsFresh, requestIDs == cachedRequestIDs {
            isLoading = false
            return
        }
        guard !requests.isEmpty else {
            sections = []
            partialErrors = []
            cacheIsFresh = false
            cachedRequestIDs = []
            isLoading = false
            try? await cache.save([])
            return
        }

        isLoading = true
        defer {
            if refreshGeneration == generation { isLoading = false }
        }
        let refreshTask = Task {
            await Self.fetch(
                requests: requests,
                client: client,
                maximumConcurrentRequests: AppleCatalogDiscoveryPolicy.maximumConcurrentRequests
            )
        }
        activeRefreshTask = refreshTask
        activeRefreshTaskGeneration = generation
        let results = await withTaskCancellationHandler {
            await refreshTask.value
        } onCancel: {
            refreshTask.cancel()
        }
        if activeRefreshTaskGeneration == generation {
            activeRefreshTask = nil
            activeRefreshTaskGeneration = nil
        }
        guard refreshGeneration == generation, !Task.isCancelled else { return }

        let existing = sections.reduce(into: [String: AppleCatalogSection]()) {
            $0[Self.requestID(for: $1)] = $1
        }
        let resultByID = results.reduce(into: [String: CatalogFetchResult]()) { $0[$1.id] = $1 }
        var updated: [AppleCatalogSection] = []
        var errors: [String] = []
        var successfulRequests = 0
        for request in requests {
            guard let result = resultByID[request.id] else { continue }
            switch result.outcome {
            case .success(let items):
                successfulRequests += 1
                updated.append(AppleCatalogSection(source: request.source, catalog: request.catalog, items: items))
            case .failure(let message):
                errors.append("\(request.source.name): \(message)")
                if let fallback = existing[request.id] { updated.append(fallback) }
            }
        }

        sections = updated
        partialErrors = errors
        cachedRequestIDs = Set(updated.map(Self.requestID(for:)))
        let isComplete = successfulRequests == requests.count
        cacheIsFresh = isComplete && updated.contains(where: { !$0.items.isEmpty })
        try? await cache.save(updated, isComplete: isComplete)
    }

    private func cancelActiveRefresh() async {
        guard let task = activeRefreshTask,
              let taskGeneration = activeRefreshTaskGeneration else {
            return
        }
        task.cancel()
        _ = await task.value
        if activeRefreshTaskGeneration == taskGeneration {
            activeRefreshTask = nil
            activeRefreshTaskGeneration = nil
        }
    }

    private static func fetch(
        requests: [CatalogRequest],
        client: AppleStremioCatalogClient,
        maximumConcurrentRequests: Int
    ) async -> [CatalogFetchResult] {
        let concurrency = min(max(maximumConcurrentRequests, 1), requests.count)
        return await withTaskGroup(of: CatalogFetchResult.self, returning: [CatalogFetchResult].self) { group in
            var nextIndex = 0
            func enqueue(_ index: Int) {
                let request = requests[index]
                group.addTask {
                    do {
                        let items = try await client.load(source: request.source, catalog: request.catalog)
                        return CatalogFetchResult(id: request.id, outcome: .success(items))
                    } catch is CancellationError {
                        return CatalogFetchResult(id: request.id, outcome: .failure("Cancelled"))
                    } catch {
                        return CatalogFetchResult(id: request.id, outcome: .failure(error.localizedDescription))
                    }
                }
            }

            while nextIndex < concurrency {
                enqueue(nextIndex)
                nextIndex += 1
            }

            var values: [CatalogFetchResult] = []
            while let result = await group.next() {
                values.append(result)
                if Task.isCancelled {
                    group.cancelAll()
                    continue
                }
                if nextIndex < requests.count {
                    enqueue(nextIndex)
                    nextIndex += 1
                }
            }
            return values
        }
    }

    private static func requestID(for section: AppleCatalogSection) -> String {
        "\(section.sourceID.uuidString):\(section.sourceConfigurationID):\(section.catalog.type):\(section.catalog.id)"
    }

    private struct CatalogRequest: Sendable {
        let source: AppleSource
        let catalog: AppleStremioCatalog
        var id: String {
            "\(source.id.uuidString):\(AppleCatalogDiscoveryPolicy.sourceConfigurationID(for: source)):\(catalog.type):\(catalog.id)"
        }
    }

    private struct CatalogFetchResult: Sendable {
        let id: String
        let outcome: Outcome

        enum Outcome: Sendable {
            case success([AppleCatalogItem])
            case failure(String)
        }
    }
}

private extension String {
    var nonEmptyCatalogString: String? { isEmpty ? nil : self }

    func trimmedAndLimited(to maximumCharacters: Int) -> String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : String(value.prefix(maximumCharacters))
    }
}
