import Foundation
import Synchronization

/// Netflix Top 10 titles matched to TMDB titles with art, kept on disk so the next launch draws the
/// ranked rows with artwork from their first frame. Keyed by the chart's title, not its rank: a
/// title moves between ranks from week to week. A miss is asked again after a day.
///
/// The file is read by `load()`, on this actor, never by `init`: the first touch of `shared` is `cached(title:type:)`
/// inside Discover's body, on the main thread.
actor AppleTop10ArtworkStore {
    typealias Search = @Sendable (_ title: String, _ type: String, AppleTMDBConfiguration) async throws -> AppleCatalogItem?
    struct Record: Codable, Sendable {
        let item: AppleCatalogItem?
        let checkedAt: Date
    }

    static let shared = AppleTop10ArtworkStore()
    static let missRetry: TimeInterval = 86_400
    private static let capacity = 200

    private nonisolated let records: Mutex<[String: Record]>
    private let fileURL: URL
    private let search: Search
    private var inFlight: [String: Task<Result<AppleCatalogItem?, Error>, Never>] = [:]
    private var isLoaded = false

    init(fileURL: URL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appending(path: "OpenStream", directoryHint: .isDirectory).appending(path: "top10-artwork-v1.json"),
         search: @escaping Search = { try await AppleTMDBClient().top10Search(title: $0, type: $1, configuration: $2) }) {
        self.fileURL = fileURL
        self.search = search
        records = Mutex([:])
    }

    /// Reads the matches kept by an earlier launch; later calls do nothing.
    func load() {
        guard !isLoaded else { return }
        isLoaded = true
        guard let stored = (try? Data(contentsOf: fileURL))
            .flatMap({ try? JSONDecoder().decode([String: Record].self, from: $0) }) else { return }
        records.withLock { $0 = stored }
    }

    /// A metadata-only title opens its page with no source of its own, as a shared link does.
    nonisolated static func match(_ item: AppleCatalogItem) -> AppleCatalogSearchMatch {
        AppleCatalogSearchMatch(item: item, source: metadataSource)
    }

    private static let metadataSource = AppleSource(kind: .library, name: "oStream",
                                                    url: URL(string: "https://fixture.example/shared-link")!)

    nonisolated static func key(title: String, type: String) -> String {
        "\(type)|\(AppleTop10ArtworkLookup.chartKey(title))"
    }

    /// The title found on an earlier visit or launch, once `load()` has run; cheap enough to call while a view draws.
    nonisolated func cached(title: String, type: String) -> AppleCatalogItem? {
        records.withLock { $0[Self.key(title: title, type: type)]?.item }
    }

    func resolve(title: String, type: String, configuration: AppleTMDBConfiguration,
                 now: Date = .now) async -> AppleCatalogItem? {
        load()
        let key = Self.key(title: title, type: type)
        if let record = records.withLock({ $0[key] }),
           record.item != nil || now.timeIntervalSince(record.checkedAt) < Self.missRetry { return record.item }
        let task = inFlight[key] ?? Task { [search] in
            do { return .success(try await search(title, type, configuration)) } catch { return .failure(error) }
        }
        inFlight[key] = task
        let result = await task.value
        inFlight[key] = nil
        // A failed request (offline, timeout) is not an answer; only TMDB's answer is remembered.
        guard case .success(let item) = result else { return nil }
        let snapshot = records.withLock { values in
            values[key] = Record(item: item, checkedAt: now)
            if values.count > Self.capacity {
                for stale in values.sorted(by: { $0.value.checkedAt < $1.value.checkedAt })
                    .prefix(values.count - Self.capacity) { values[stale.key] = nil }
            }
            return values
        }
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(snapshot).write(to: fileURL, options: .atomic)
        return item
    }
}
