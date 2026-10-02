// AppleChannelLineupPresets.swift
// OpenStreamApple
// Done / hooks needed: AppleChannelLineupPresets.match(channelName:in:) inside the Channel Manager's "Premier Guide" preset
import Foundation

public struct AppleChannelLineupEntry: Codable, Sendable, Equatable {
    public let number: Int
    public let name: String
    public let aliases: [String]
    public let category: String
    public let market: Market?

    public init(number: Int, name: String, aliases: [String], category: String, market: Market? = nil) {
        self.number = number
        self.name = name
        self.aliases = aliases
        self.category = category
        self.market = market
    }

    public enum Market: Codable, Sendable, Equatable {
        case network(String)
        case region(String)

        public init(from decoder: Decoder) throws {
            if let container = try? decoder.singleValueContainer(), let str = try? container.decode(String.self) {
                self = .region(str)
            } else if let container = try? decoder.container(keyedBy: CodingKeys.self), let network = try? container.decode(String.self, forKey: .network) {
                self = .network(network)
            } else {
                throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Invalid market"))
            }
        }

        public func encode(to encoder: Encoder) throws {
            switch self {
            case .region(let name):
                var container = encoder.singleValueContainer()
                try container.encode(name)
            case .network(let network):
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encode(network, forKey: .network)
            }
        }

        enum CodingKeys: String, CodingKey {
            case network
        }
    }
}

struct LineupFile: Codable, Sendable {
    let channels: [AppleChannelLineupEntry]
    let markets: [String: String]
}

/// The US channel lineup is a **test fixture, not a shipped resource**.
///
/// Owner, 2026-10-01 (App Store compliance audit B6): "nothing should be
/// built in — this is just testing". A Release build carries no lineup, so
/// channel names, numbers and logos come only from the viewer's own playlist
/// and EPG (`tvg-logo`, then initials). A Debug build — the simulators, the
/// unit tests, a developer's device — reads the fixture from the source tree
/// (`Tests/OpenStreamAppleTests/Fixtures/ChannelLineup/`) or from the file
/// `OPENSTREAM_CHANNEL_LINEUP` names, so the Premier Guide code paths stay
/// testable once IPTV is set up. Nothing is ever looked up in the app bundle.
public enum AppleChannelLineupPresets {
    /// The resource bundle the lineup must never be in (`Bundle.module` of
    /// the app library, not of a test target).
    static let resourceBundle = Bundle.module

    /// The fixture, relative to this file, in the source tree.
    static let debugFixtureURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Tests/OpenStreamAppleTests/Fixtures/ChannelLineup/premier-us-extended.json")

    /// Environment variable naming a lineup file to read instead of the fixture (Debug only).
    static let debugOverrideEnvironmentKey = "OPENSTREAM_CHANNEL_LINEUP"

    #if DEBUG
    static let isDebugBuild = true
    #else
    static let isDebugBuild = false
    #endif

    /// True when a lineup is loaded: Debug builds with the fixture in reach.
    /// Release is always false.
    public static var isAvailable: Bool { !((try? premierUS()) ?? []).isEmpty }

    private static let cachedFile: Result<LineupFile, any Error> = Result { try readFile(allowDebugFixture: isDebugBuild) }
    private static func loadFile() throws -> LineupFile { try cachedFile.get() }

    /// The lineup a build of this kind sees: empty for Release, the fixture
    /// (or the override file) for Debug. `allowDebugFixture` exists so a test
    /// can run the Release path from a Debug build.
    static func readFile(allowDebugFixture: Bool) throws -> LineupFile {
        guard allowDebugFixture else { return LineupFile(channels: [], markets: [:]) }
        let url: URL
        if let override = ProcessInfo.processInfo.environment[debugOverrideEnvironmentKey], !override.isEmpty {
            url = URL(fileURLWithPath: override)
        } else {
            url = debugFixtureURL
        }
        guard FileManager.default.fileExists(atPath: url.path) else { return LineupFile(channels: [], markets: [:]) }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(LineupFile.self, from: data)
    }

    static func lineup(allowDebugFixture: Bool) throws -> [AppleChannelLineupEntry] {
        try readFile(allowDebugFixture: allowDebugFixture).channels
    }

    /// The lineup entries, or `[]` when this build ships none (Release).
    public static func premierUS() throws -> [AppleChannelLineupEntry] {
        return try loadFile().channels
    }

    public static func match(channelName: String, in entries: [AppleChannelLineupEntry]) -> AppleChannelLineupEntry? {
        let normalizedSearch = normalize(name: channelName)
        for entry in entries {
            if normalize(name: entry.name) == normalizedSearch {
                return entry
            }
            if entry.aliases.contains(where: { normalize(name: $0) == normalizedSearch }) {
                return entry
            }
        }
        return nil
    }

    public static func localMatches(zip: String, entries: [AppleChannelLineupEntry]) -> [AppleChannelLineupEntry] {
        guard let file = try? loadFile() else { return [] }
        
        let prefix3 = String(zip.prefix(3))
        guard let marketName = file.markets[prefix3] else { return [] }
        
        return entries.filter { entry in
            switch entry.market {
            case .region(let region):
                return region == marketName
            case .network(_):
                return true
            case nil:
                return false
            }
        }
    }

    public static func matchesLocalChannel(name: String, zip: String, entries: [AppleChannelLineupEntry]) -> Bool {
        localMatches(zip: zip, entries: entries).contains { entry in
            if case .region = entry.market { return match(channelName: name, in: [entry]) != nil }
            return false
        }
    }

    static func normalize(name: String) -> String {
        var str = name.lowercased()
        if str.hasPrefix("us:") {
            str = String(str.dropFirst(3))
        }
        str = str.trimmingCharacters(in: .whitespaces)
        
        // Replace punctuation with spaces
        let punctuation = CharacterSet.punctuationCharacters
        str = String(str.unicodeScalars.map { punctuation.contains($0) ? Character(" ") : Character($0) })
        
        // Collapse spaces
        str = str.components(separatedBy: .whitespaces).filter { !$0.isEmpty }.joined(separator: " ")
        
        let removals = [" hd", " fhd", " 4k", " east", " west"]
        var changed = true
        while changed {
            changed = false
            for r in removals {
                if str.hasSuffix(r) {
                    str = String(str.dropLast(r.count))
                    str = str.trimmingCharacters(in: .whitespaces)
                    changed = true
                }
            }
        }
        return str
    }
}

struct AppleChannelLineupIndex: Sendable {
    private let entries: [String: AppleChannelLineupEntry]
    init(_ values: [AppleChannelLineupEntry]) {
        var result: [String: AppleChannelLineupEntry] = [:]
        for entry in values {
            for name in [entry.name] + entry.aliases {
                let normalized = AppleChannelLineupPresets.normalize(name: name)
                if result[normalized] == nil { result[normalized] = entry }
            }
        }
        entries = result
    }
    func match(_ name: String) -> AppleChannelLineupEntry? {
        entries[AppleChannelLineupPresets.normalize(name: name)]
    }
}
