import Foundation

/// Private routing metadata for shelf titles outside the persistent media index.
public actor AppleTopShelfRouteStore {
    public static let shared = AppleTopShelfRouteStore()
    static let filename = "topshelf-routes-v1.json"
    nonisolated static var defaultURL: URL {
        AppleStorageLocation.applicationSupport.appending(path: "OpenStream", directoryHint: .isDirectory)
            .appending(path: filename)
    }
    private let fileURL: URL
    private var lastSavedRecords: [AppleMediaRecord]?

    public init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? Self.defaultURL
    }

    func save(records: [AppleMediaRecord], sources: [AppleSource], enabled: Bool) throws {
        try Task.checkCancellation()
        guard enabled else {
            try Self.removeFile(at: fileURL)
            lastSavedRecords = nil
            return
        }
        var seen = Set<String>()
        let privateIDs = Set(records.filter(\.isPrivate).map(\.id))
        var routes: [AppleMediaRecord] = []
        for record in records {
            if routes.count == AppleContinueWatchingResolver.maximumCount { break }
            guard !privateIDs.contains(record.id), AppleCatalogSearchMatch.mediaServer(record, sources: sources) != nil,
                  seen.insert(record.id).inserted else { continue }
            var result = record
            result.progress = nil
            result.artworkURL = AppleSystemArtworkPolicy.publicURL(record.artworkURL)
            result.backdropURL = AppleSystemArtworkPolicy.publicURL(record.backdropURL)
            result.availability = record.availability.filter { route in
                sources.contains { $0.id == route.instanceID && $0.isEnabled && $0.kind == .mediaServer }
            }
            routes.append(result)
        }
        if let previous = lastSavedRecords, previous.count == routes.count,
           zip(previous, routes).allSatisfy({ $0.hasSameContent(as: $1) }),
           FileManager.default.fileExists(atPath: fileURL.path) { return }
        let data = try AppleCachedCredentialPolicy.metadata(JSONEncoder().encode(routes))
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        #if os(iOS) || os(tvOS) || os(visionOS)
        try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUnlessOpen])
        #else
        try data.write(to: fileURL, options: .atomic)
        #endif
        lastSavedRecords = routes
    }

    nonisolated static func removeFile(at url: URL) throws {
        do { try FileManager.default.removeItem(at: url) }
        catch let error as CocoaError where error.code == .fileNoSuchFile { return }
    }

    func records() -> [AppleMediaRecord] {
        guard let data = try? Data(contentsOf: fileURL),
              let records = try? JSONDecoder().decode([AppleMediaRecord].self, from: data) else { return [] }
        return Array(records.prefix(AppleContinueWatchingResolver.maximumCount))
    }

    func record(id: String) -> AppleMediaRecord? { records().first { $0.id == id } }
}
