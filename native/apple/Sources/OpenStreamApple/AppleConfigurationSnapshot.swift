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
    public var watchlist: [AppleMediaRecord]
    public var ratings: [String: Int]

    public init(savedAt: Date = .now, sources: [AppleSource] = [], settings: [String: Data] = [:],
                playbackProgress: [String: ApplePlaybackProgress] = [:],
                watchlist: [AppleMediaRecord] = [], ratings: [String: Int] = [:]) {
        formatVersion = 1
        self.savedAt = savedAt
        self.sources = sources.map(Self.portableSource)
        self.settings = settings
        self.playbackProgress = playbackProgress
        self.watchlist = watchlist.map { record in
            var copy = record
            copy.artworkURL = nil
            copy.availability = []
            return copy
        }
        self.ratings = ratings
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
        return result
    }

    public func cloudData() throws -> Data {
        try validate()
        var copy = self
        copy.sources = sources.map(Self.portableSource)
        let newest = playbackProgress.sorted {
            $0.value.updatedAt == $1.value.updatedAt ? $0.key < $1.key : $0.value.updatedAt > $1.value.updatedAt
        }.prefix(500)
        copy.playbackProgress = Dictionary(uniqueKeysWithValues: newest.map { ($0.key, $0.value) })
        var data = try Self.encoder.encode(copy)
        // Large episode identifiers can still exceed the quota with fewer than 500 entries.
        for entry in newest.reversed() where data.count > Self.maximumCloudBytes {
            copy.playbackProgress.removeValue(forKey: entry.key)
            data = try Self.encoder.encode(copy)
        }
        guard data.count <= Self.maximumCloudBytes else { throw AppleConfigurationError.tooLarge }
        return data
    }

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
