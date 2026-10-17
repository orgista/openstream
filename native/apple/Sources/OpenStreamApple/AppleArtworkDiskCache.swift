import Foundation
import CryptoKit

struct AppleArtworkColour: Equatable, Sendable {
    let red: UInt8
    let green: UInt8
    let blue: UInt8
}

/// Pure, testable policies for the artwork disk cache.
struct AppleArtworkDiskCachePolicy {
    static let version = "Artwork-v1"
    static let maximumBytes = 512 * 1024 * 1024

    /// A trim frees down to here, so the writes after it do not each walk the
    /// whole folder again.
    static func trimTarget(maximumBytes: Int) -> Int { maximumBytes / 8 * 7 }

    static func fileName(for url: URL, variant: String) -> String {
        let input = url.absoluteString.data(using: .utf8) ?? Data()
        let hash = SHA256.hash(data: input)
        let hex = hash.map { String(format: "%02x", $0) }.joined()
        return "\(hex)-\(variant).bin"
    }

    static func evictionOrder(_ entries: [(name: String, bytes: Int, modified: Date)], limit: Int) -> [String] {
        var currentTotal = entries.map { $0.bytes }.reduce(0, +)
        guard currentTotal > limit else { return [] }

        let sorted = entries.sorted { $0.modified < $1.modified }
        var toEvict: [String] = []

        for entry in sorted {
            toEvict.append(entry.name)
            currentTotal -= entry.bytes
            if currentTotal <= limit {
                break
            }
        }
        return toEvict
    }
}

/// A bounded, persistent cache for artwork (posters, backdrops, logos).
actor AppleArtworkDiskCache {
    static let shared: AppleArtworkDiskCache = {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let directory = caches.appendingPathComponent("OpenStream", isDirectory: true).appendingPathComponent(AppleArtworkDiskCachePolicy.version, isDirectory: true)
        return AppleArtworkDiskCache(directory: directory)
    }()

    private let directory: URL
    private let maximumBytes: Int
    private let fileManager = FileManager.default
    private var totalBytes: Int?
    private var trimScheduled = false

    init(directory: URL, maximumBytes: Int = AppleArtworkDiskCachePolicy.maximumBytes) {
        self.directory = directory
        self.maximumBytes = maximumBytes
    }

    func data(for url: URL, variant: String) -> Data? {
        let name = AppleArtworkDiskCachePolicy.fileName(for: url, variant: variant)
        let fileURL = directory.appendingPathComponent(name, isDirectory: false)
        guard let data = try? Data(contentsOf: fileURL) else { return nil }

        // Touch the modification date so eviction is LRU.
        try? fileManager.setAttributes([.modificationDate: Date()], ofItemAtPath: fileURL.path)
        return data
    }

    func colour(for url: URL) -> AppleArtworkColour? {
        guard let bytes = data(for: url, variant: "colour"), bytes.count == 3 else { return nil }
        let values = Array(bytes)
        return AppleArtworkColour(red: values[0], green: values[1], blue: values[2])
    }

    func storeColour(_ colour: AppleArtworkColour, for url: URL) {
        store(Data([colour.red, colour.green, colour.blue]), for: url, variant: "colour")
    }

    func contains(url: URL, variant: String) -> Bool {
        let name = AppleArtworkDiskCachePolicy.fileName(for: url, variant: variant)
        let fileURL = directory.appendingPathComponent(name, isDirectory: false)
        return fileManager.fileExists(atPath: fileURL.path)
    }

    func store(_ data: Data, for url: URL, variant: String) {
        let name = AppleArtworkDiskCachePolicy.fileName(for: url, variant: variant)
        let fileURL = directory.appendingPathComponent(name, isDirectory: false)
        let previousSize = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            // Atomic write
            try data.write(to: fileURL, options: .atomic)
            if let totalBytes { self.totalBytes = totalBytes - previousSize + data.count }
        } catch {
            // Ignore errors as requested
        }

        if totalBytes == nil {
            // The first write sizes the folder in the background, off the launch path.
            guard !trimScheduled else { return }
            trimScheduled = true
            Task.detached(priority: .background) { await self.trimIfNeeded() }
        } else if let totalBytes, totalBytes > maximumBytes {
            trimIfNeeded()
        }
    }

    func trimIfNeeded() {
        guard let urls = try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey]) else { return }

        var entries: [(name: String, bytes: Int, modified: Date)] = []
        for url in urls {
            guard let attrs = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]),
                  let size = attrs.fileSize,
                  let modified = attrs.contentModificationDate else { continue }
            entries.append((name: url.lastPathComponent, bytes: size, modified: modified))
        }

        totalBytes = entries.reduce(0) { $0 + $1.bytes }
        let toEvict = AppleArtworkDiskCachePolicy.evictionOrder(entries, limit: AppleArtworkDiskCachePolicy.trimTarget(maximumBytes: maximumBytes))
        for name in toEvict {
            let fileURL = directory.appendingPathComponent(name, isDirectory: false)
            do {
                try fileManager.removeItem(at: fileURL)
                totalBytes = (totalBytes ?? 0) - (entries.first { $0.name == name }?.bytes ?? 0)
            } catch {
                // A failed eviction remains counted toward the budget.
            }
        }
    }
}
