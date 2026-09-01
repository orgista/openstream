import Foundation

public struct AppleOfflineRecord: Codable, Equatable, Sendable {
    public let mediaID: String
    public let localURL: URL
    public let sourceExtension: String
    public let storedAt: Date

    public init(mediaID: String, localURL: URL, sourceExtension: String, storedAt: Date = .now) {
        self.mediaID = mediaID
        self.localURL = localURL
        self.sourceExtension = sourceExtension
        self.storedAt = storedAt
    }
}

public enum AppleOfflineStoreError: Error, Equatable {
    case emptyMediaID
    case adaptiveStreamRequiresAssetDownload
    case uncontainedSourceFileURL
    case sourceFileNotFound
}

/// App-private device-storage persistence shared by iPhone, iPad, Apple TV,
/// and Apple Vision Pro. Progressive files use URLSession; HLS is rejected
/// here so callers route it to AVAssetDownloadURLSession rather than saving a
/// playlist that would not actually work offline.
public actor AppleOfflineMediaStore {
    private let rootDirectory: URL
    private let manifestURL: URL
    private let fileManager: FileManager
    private let allowedDirectories: [URL]

    public init(
        rootDirectory: URL? = nil,
        fileManager: FileManager = .default,
        allowedDirectories: [URL]? = nil
    ) {
        self.fileManager = fileManager
        let applicationSupport = rootDirectory ?? fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!.appending(path: "OpenStream/Offline", directoryHint: .isDirectory)
        self.rootDirectory = applicationSupport
        self.manifestURL = applicationSupport.appending(path: "manifest.json")

        if let allowedDirectories {
            self.allowedDirectories = allowedDirectories
        } else {
            var defaults: [URL] = [
                applicationSupport,
                applicationSupport.deletingLastPathComponent(),
                fileManager.temporaryDirectory,
                URL(fileURLWithPath: NSTemporaryDirectory()),
            ]
            for searchPath in [FileManager.SearchPathDirectory.documentDirectory, .cachesDirectory, .applicationSupportDirectory, .downloadsDirectory] {
                defaults.append(contentsOf: fileManager.urls(for: searchPath, in: .userDomainMask))
            }
            if let customRoot = rootDirectory {
                defaults.append(customRoot)
                defaults.append(customRoot.deletingLastPathComponent())
            }
            self.allowedDirectories = defaults
        }
    }

    public func record(for mediaID: String) -> AppleOfflineRecord? {
        guard let record = loadManifest()[mediaID], fileManager.fileExists(atPath: record.localURL.path) else {
            return nil
        }
        return record
    }

    public func allRecords() -> [AppleOfflineRecord] {
        loadManifest().values
            .filter { fileManager.fileExists(atPath: $0.localURL.path) }
            .sorted { $0.storedAt > $1.storedAt }
    }

    public func isPathContained(_ url: URL) -> Bool {
        guard url.isFileURL else { return false }
        let canonicalPath = url.standardizedFileURL.resolvingSymlinksInPath().path
        guard !canonicalPath.isEmpty, canonicalPath != "/" else { return false }

        for allowed in allowedDirectories {
            let allowedPath = allowed.standardizedFileURL.resolvingSymlinksInPath().path
            guard !allowedPath.isEmpty, allowedPath != "/" else { continue }
            if canonicalPath == allowedPath {
                return true
            }
            let prefix = allowedPath.hasSuffix("/") ? allowedPath : allowedPath + "/"
            if canonicalPath.hasPrefix(prefix) {
                return true
            }
        }
        return false
    }

    @discardableResult
    public func makeAvailable(mediaID: String, sourceURL: URL) async throws -> AppleOfflineRecord {
        guard !mediaID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AppleOfflineStoreError.emptyMediaID
        }
        if sourceURL.pathExtension.lowercased() == "m3u8" {
            throw AppleOfflineStoreError.adaptiveStreamRequiresAssetDownload
        }

        try fileManager.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        let sourceExtension = sourceURL.pathExtension.isEmpty ? "media" : sourceURL.pathExtension.lowercased()
        let destination = rootDirectory.appending(path: "\(stableIdentifier(mediaID)).\(sourceExtension)")
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }

        if sourceURL.isFileURL {
            guard isPathContained(sourceURL) else {
                throw AppleOfflineStoreError.uncontainedSourceFileURL
            }
            let canonicalSource = sourceURL.standardizedFileURL.resolvingSymlinksInPath()
            guard fileManager.fileExists(atPath: canonicalSource.path) else {
                throw AppleOfflineStoreError.sourceFileNotFound
            }
            try fileManager.copyItem(at: canonicalSource, to: destination)
        } else {
            let (temporaryURL, _) = try await URLSession.shared.download(from: sourceURL)
            try fileManager.moveItem(at: temporaryURL, to: destination)
        }

        var manifest = loadManifest()
        let record = AppleOfflineRecord(
            mediaID: mediaID,
            localURL: destination,
            sourceExtension: sourceExtension
        )
        manifest[mediaID] = record
        try saveManifest(manifest)
        return record
    }

    public func remove(mediaID: String) throws {
        var manifest = loadManifest()
        if let record = manifest.removeValue(forKey: mediaID), fileManager.fileExists(atPath: record.localURL.path) {
            try fileManager.removeItem(at: record.localURL)
        }
        try saveManifest(manifest)
    }

    private func loadManifest() -> [String: AppleOfflineRecord] {
        guard let data = try? Data(contentsOf: manifestURL) else { return [:] }
        return (try? JSONDecoder().decode([String: AppleOfflineRecord].self, from: data)) ?? [:]
    }

    private func saveManifest(_ manifest: [String: AppleOfflineRecord]) throws {
        try fileManager.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(manifest)
        try data.write(to: manifestURL, options: .atomic)
    }

    private func stableIdentifier(_ value: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in value.utf8 {
            hash = (hash ^ UInt64(byte)) &* 1_099_511_628_211
        }
        return String(hash, radix: 16)
    }
}
