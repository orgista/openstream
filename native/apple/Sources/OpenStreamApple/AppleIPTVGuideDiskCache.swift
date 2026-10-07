import Foundation

/// Parsed guide data, partitioned by source and configuration digest. No URLs or credentials are stored.
public actor AppleIPTVGuideDiskCache {
    public static let shared = AppleIPTVGuideDiskCache()
    public static let maximumProgrammes = 500_000
    private let directory: URL?

    public init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("oStream/LiveGuide", isDirectory: true)
    }

    public struct Snapshot: Codable, Sendable {
        public let programmes: [AppleIPTVProgramme]
        public let channelNames: [String: String]
        public var fetchedAt: Date? = nil
        public var eTag: String? = nil
        public var lastModified: String? = nil
        public var contentDigest: String? = nil
        /// Older snapshots contain mapped channels; new XMLTV snapshots retain provider channels.
        public var isRawXMLTV: Bool? = nil
    }

    public func programmes(key: String, now: Date = .now) -> [AppleIPTVProgramme] {
        snapshot(key: key, now: now).programmes
    }

    public func snapshot(key: String, now: Date = .now) -> Snapshot {
        let empty = Snapshot(programmes: [], channelNames: [:])
        guard let url = fileURL(key),
              let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 96 * 1024 * 1024,
              let data = try? Data(contentsOf: url),
              let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) else { return empty }
        if snapshot.isRawXMLTV == true { return snapshot }
        let valid = snapshot.programmes.filter { $0.end > now && $0.end > $0.start }
        if valid.isEmpty { try? FileManager.default.removeItem(at: url) }
        return Snapshot(programmes: Array(valid.prefix(Self.maximumProgrammes)), channelNames: snapshot.channelNames,
            fetchedAt: snapshot.fetchedAt, eTag: snapshot.eTag, lastModified: snapshot.lastModified,
            contentDigest: snapshot.contentDigest, isRawXMLTV: snapshot.isRawXMLTV)
    }

    public func store(_ programmes: [AppleIPTVProgramme], key: String, channelNames: [String: String] = [:],
                      fetchedAt: Date? = nil, eTag: String? = nil, lastModified: String? = nil,
                      contentDigest: String? = nil, isRawXMLTV: Bool? = nil) {
        guard let directory, let url = fileURL(key), (!programmes.isEmpty || isRawXMLTV == true),
              let data = try? JSONEncoder().encode(Snapshot(programmes: Array(programmes.prefix(Self.maximumProgrammes)), channelNames: channelNames,
                  fetchedAt: fetchedAt, eTag: eTag, lastModified: lastModified,
                  contentDigest: contentDigest, isRawXMLTV: isRawXMLTV)) else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }

    private func fileURL(_ key: String) -> URL? {
        directory?.appendingPathComponent(ApplePlaybackIdentity.digest(for: key) + ".json")
    }
}
