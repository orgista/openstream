import Foundation

public enum AppleConfigurationError: Error, Equatable, LocalizedError {
    case unsupportedVersion, passphraseRequired, wrongPassphrase, invalidFile, tooLarge

    public var errorDescription: String? {
        switch self {
        case .unsupportedVersion: "Unsupported configuration version."
        case .passphraseRequired: "Passphrase required."
        case .wrongPassphrase: "Incorrect passphrase or damaged file."
        case .invalidFile: "Invalid configuration file."
        case .tooLarge: "Configuration exceeds the iCloud limit."
        }
    }
}

/// Portable configuration only. Device bookmarks and Keychain references never cross devices.
public struct AppleConfigurationSnapshot: Codable, Equatable, Sendable {
    public static let maximumCloudBytes = 950_000 // Reserve room for the KVS key and overhead.
    public let formatVersion: Int
    public var savedAt: Date
    public var sources: [AppleSource]
    public var settings: [String: Data]
    public var playbackProgress: [String: ApplePlaybackProgress]
    /// Finished titles and when, keyed like `playbackProgress`. Snapshots
    /// written before this existed have none and import as empty.
    public var watchedHistory: [String: Date]
    public var watchlist: [AppleMediaRecord]
    public var ratings: [String: Int]

    private enum CodingKeys: String, CodingKey {
        case formatVersion, savedAt, sources, settings, playbackProgress, watchedHistory, watchlist, ratings
    }

    public init(savedAt: Date = .now, sources: [AppleSource] = [], settings: [String: Data] = [:],
                playbackProgress: [String: ApplePlaybackProgress] = [:],
                watchedHistory: [String: Date] = [:],
                watchlist: [AppleMediaRecord] = [], ratings: [String: Int] = [:]) {
        formatVersion = 1
        self.savedAt = savedAt
        self.sources = sources.map(Self.portableSource)
        self.settings = settings
        self.playbackProgress = playbackProgress
        self.watchedHistory = watchedHistory
        self.watchlist = watchlist.map { record in
            var copy = record
            copy.artworkURL = nil
            copy.availability = []
            return copy
        }
        self.ratings = ratings
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        formatVersion = try container.decode(Int.self, forKey: .formatVersion)
        savedAt = try container.decode(Date.self, forKey: .savedAt)
        sources = try container.decode([AppleSource].self, forKey: .sources)
        settings = try container.decode([String: Data].self, forKey: .settings)
        playbackProgress = try container.decode([String: ApplePlaybackProgress].self, forKey: .playbackProgress)
        watchedHistory = try container.decodeIfPresent([String: Date].self, forKey: .watchedHistory) ?? [:]
        watchlist = try container.decode([AppleMediaRecord].self, forKey: .watchlist)
        ratings = try container.decode([String: Int].self, forKey: .ratings)
    }

    public func validate() throws {
        guard formatVersion == 1 else { throw AppleConfigurationError.unsupportedVersion }
        guard Set(sources.map(\.id)).count == sources.count,
              Set(watchlist.map(\.id)).count == watchlist.count else { throw AppleConfigurationError.invalidFile }
    }

    public func merging(_ incoming: Self) -> Self {
        var result = incoming
        var combined = sources
        for source in incoming.sources {
            if let index = combined.firstIndex(where: { $0.id == source.id }) { combined[index] = source }
            else { combined.append(source) }
        }
        result.sources = combined
        result.watchedHistory = watchedHistory.merging(incoming.watchedHistory) { max($0, $1) }
        return result
    }

    public func cloudData() throws -> Data {
        try validate()
        var copy = self
        copy.sources = sources.map(Self.portableSource)
        let newest = playbackProgress.sorted {
            $0.value.updatedAt == $1.value.updatedAt ? $0.key < $1.key : $0.value.updatedAt > $1.value.updatedAt
        }.prefix(Self.cloudEntryLimit)
        copy.playbackProgress = Dictionary(uniqueKeysWithValues: newest.map { ($0.key, $0.value) })
        let newestWatched = watchedHistory.sorted {
            $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value
        }.prefix(Self.cloudEntryLimit)
        copy.watchedHistory = Dictionary(uniqueKeysWithValues: newestWatched.map { ($0.key, $0.value) })
        var data = try Self.encoder.encode(copy)
        // Large episode identifiers can still exceed the quota with fewer
        // than 500 entries. The oldest entry of either list goes first.
        let progressEntries: [CloudTrimEntry] = newest.map { CloudTrimEntry(key: $0.key, date: $0.value.updatedAt, isWatched: false) }
        let watchedEntries: [CloudTrimEntry] = newestWatched.map { CloudTrimEntry(key: $0.key, date: $0.value, isWatched: true) }
        var oldestFirst = (progressEntries + watchedEntries).sorted(by: CloudTrimEntry.isOlder)[...]
        while data.count > Self.maximumCloudBytes, let entry = oldestFirst.popFirst() {
            if entry.isWatched { copy.watchedHistory.removeValue(forKey: entry.key) }
            else { copy.playbackProgress.removeValue(forKey: entry.key) }
            data = try Self.encoder.encode(copy)
        }
        guard data.count <= Self.maximumCloudBytes else { throw AppleConfigurationError.tooLarge }
        return data
    }

    private struct CloudTrimEntry {
        let key: String
        let date: Date
        let isWatched: Bool

        static func isOlder(_ lhs: Self, _ rhs: Self) -> Bool {
            lhs.date == rhs.date ? lhs.key > rhs.key : lhs.date < rhs.date
        }
    }

    /// Newest entries of each history the iCloud copy keeps.
    static let cloudEntryLimit = 500

    static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    static func publicAddress(_ url: URL) -> URL {
        guard var parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              ["https", "http", "smb"].contains(parts.scheme?.lowercased() ?? "") else {
            return URL(string: "https://source.invalid/")!
        }
        parts.user = nil
        parts.password = nil
        parts.query = nil
        parts.fragment = nil
        parts.path = "/"
        return parts.url ?? URL(string: "https://source.invalid/")!
    }

    static func portableSource(_ source: AppleSource) -> AppleSource {
        var copy = source
        copy.url = publicAddress(source.url)
        copy.needsSignIn = source.needsSignIn || source.credentialReference != nil
            || source.transportReference != nil || source.url != copy.url || source.epgURL != nil
        copy.credentialReference = nil
        copy.transportReference = nil
        copy.bookmarkData = nil
        copy.legacyUsername = nil
        copy.legacyPassword = nil
        copy.epgURL = nil
        copy.logoURL = nil
        copy.validationSummary = nil
        copy.validationFailureSummary = nil
        return copy
    }
}
