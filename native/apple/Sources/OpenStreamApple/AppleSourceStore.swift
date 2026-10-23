import Foundation
import Observation

public enum AppleSourceKind: String, Codable, CaseIterable, Sendable {
    case library
    case liveTV
    case nas
    case mediaServer

    public var title: String {
        switch self {
        case .library: "Library"
        case .liveTV: "Live TV"
        case .nas: "Network share"
        case .mediaServer: "Media Server"
        }
    }
}

public enum AppleIPTVSourceType: String, Codable, CaseIterable, Sendable {
    case m3u
    case xtream

    public var title: String {
        switch self {
        case .m3u: "M3U Playlist"
        case .xtream: "Provider Login"
        }
    }
}

public struct AppleIPTVCredentials: Codable, Equatable, Sendable {
    public let username: String
    public let password: String

    public init(username: String, password: String) {
        self.username = username
        self.password = password
    }
}

enum AppleDiagnosticRedactor {
    private static let urlPattern = try! NSRegularExpression(
        pattern: #"(?i)\b(?:https?|smb)://[^\s\"'<>]+"#
    )
    private static let bodyPattern = try! NSRegularExpression(
        pattern: #"(?i)\b(body|requestBody|responseBody)\s*[:=]\s*.*$"#
    )
    private static let credentialPattern = try! NSRegularExpression(
        pattern: #"(?i)\b(password|passwd|pwd|username|user|token|cookie|authorization)\b\s*[\"']?\s*[:=]\s*[\"']?[^,\s;&}\]]+"#
    )
    /// Xtream stream paths without a scheme: `host/live/<user>/<pass>/1.ts`.
    private static let xtreamPathPattern = try! NSRegularExpression(
        pattern: #"(?i)/(live|movie|series)/[^/\s\"'<>]+/[^/\s\"'<>]+/"#
    )
    private static let bearerPattern = try! NSRegularExpression(
        pattern: #"(?i)\bBearer\s+[^\s,;\"'}\]]+"#
    )

    static func redact(_ value: String) -> String {
        var redacted = replace(urlPattern, in: value, with: "[REDACTED URL]")
        redacted = replace(xtreamPathPattern, in: redacted, with: "/$1/[REDACTED]/[REDACTED]/")
        redacted = replace(bearerPattern, in: redacted, with: "Bearer [REDACTED]")
        redacted = replace(bodyPattern, in: redacted, with: "$1=[REDACTED]")
        return replace(credentialPattern, in: redacted, with: "$1=[REDACTED]")
    }

    /// An error for a trace line: its localized text, redacted. `\(error)`
    /// would carry `NSErrorFailingURLStringKey`, i.e. the stream URL.
    static func describe(_ error: any Error) -> String {
        redact(error.localizedDescription)
    }

    private static func replace(
        _ expression: NSRegularExpression,
        in value: String,
        with template: String
    ) -> String {
        expression.stringByReplacingMatches(
            in: value,
            range: NSRange(value.startIndex..., in: value),
            withTemplate: template
        )
    }
}

public struct AppleSource: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var kind: AppleSourceKind
    public var name: String
    public var url: URL
    public var isEnabled: Bool
    public var needsSignIn: Bool = false
    public let addedAt: Date
    public var iptvType: AppleIPTVSourceType?
    public var epgURL: URL?
    public var credentialReference: String?
    public var transportReference: String?
    public var bookmarkData: Data?
    public var isManagedImports: Bool
    public var configurationRevision: Int
    public var lastValidatedAt: Date?
    public var validationSummary: String?
    public var lastValidationFailureAt: Date?
    public var validationFailureSummary: String?

    /// Failure history remains available, but a later success resolves its warning.
    public var hasCurrentValidationFailure: Bool {
        guard let failedAt = lastValidationFailureAt else { return false }
        return failedAt > (lastValidatedAt ?? .distantPast)
    }

    public var discoveredItemCount: Int?
    public var capabilities: [String]
    /// The readable Bonjour hostname for NAS sources. `url.host` remains the
    /// resolved numeric endpoint used by the SMB client.
    public var networkDisplayHost: String?

    public var serverKind: AppleMediaServerKind?

    // Decode-only bridge for v1 installs. AppleSourceStore immediately moves
    // these values to Keychain and they are never encoded again.
    var legacyUsername: String?
    var legacyPassword: String?

    public init(
        id: UUID = UUID(),
        kind: AppleSourceKind,
        name: String,
        url: URL,
        isEnabled: Bool = true,
        addedAt: Date = .now,
        iptvType: AppleIPTVSourceType? = nil,
        epgURL: URL? = nil,
        credentialReference: String? = nil,
        transportReference: String? = nil,
        bookmarkData: Data? = nil,
        isManagedImports: Bool = false,
        configurationRevision: Int = 1,
        lastValidatedAt: Date? = nil,
        validationSummary: String? = nil,
        lastValidationFailureAt: Date? = nil,
        validationFailureSummary: String? = nil,
        discoveredItemCount: Int? = nil,
        capabilities: [String] = [],
        networkDisplayHost: String? = nil,
        serverKind: AppleMediaServerKind? = nil
    ) {
        self.id = id
        self.kind = kind
        self.name = name
        self.url = url
        self.isEnabled = isEnabled
        self.addedAt = addedAt
        self.iptvType = iptvType
        self.epgURL = epgURL
        self.credentialReference = credentialReference
        self.transportReference = transportReference
        self.bookmarkData = bookmarkData
        self.isManagedImports = isManagedImports
        self.configurationRevision = max(configurationRevision, 1)
        self.lastValidatedAt = lastValidatedAt
        self.validationSummary = Self.cleanStatus(validationSummary)
        self.lastValidationFailureAt = lastValidationFailureAt
        self.validationFailureSummary = Self.cleanStatus(validationFailureSummary)
        self.discoveredItemCount = Self.cleanItemCount(discoveredItemCount)
        self.capabilities = Self.cleanCapabilities(capabilities)
        self.networkDisplayHost = Self.cleanNetworkDisplayHost(networkDisplayHost)
        self.serverKind = serverKind
        legacyUsername = nil
        legacyPassword = nil
    }

    private enum CodingKeys: String, CodingKey {
        case needsSignIn
        case id, kind, name, url, isEnabled, addedAt, isManagedImports
        case iptvType, epgURL, credentialReference, transportReference, username, password, bookmarkData
        case configurationRevision, lastValidatedAt, validationSummary
        case lastValidationFailureAt, validationFailureSummary, discoveredItemCount, capabilities, networkDisplayHost
        case serverKind
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        kind = try container.decode(AppleSourceKind.self, forKey: .kind)
        name = try container.decode(String.self, forKey: .name)
        url = try container.decode(URL.self, forKey: .url)
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        needsSignIn = try container.decodeIfPresent(Bool.self, forKey: .needsSignIn) ?? false
        addedAt = try container.decodeIfPresent(Date.self, forKey: .addedAt) ?? .distantPast
        iptvType = try container.decodeIfPresent(AppleIPTVSourceType.self, forKey: .iptvType)
        epgURL = try container.decodeIfPresent(URL.self, forKey: .epgURL)
        credentialReference = try container.decodeIfPresent(String.self, forKey: .credentialReference)
        transportReference = try container.decodeIfPresent(String.self, forKey: .transportReference)
        legacyUsername = try container.decodeIfPresent(String.self, forKey: .username)
        legacyPassword = try container.decodeIfPresent(String.self, forKey: .password)
        bookmarkData = try container.decodeIfPresent(Data.self, forKey: .bookmarkData)
        isManagedImports = try container.decodeIfPresent(Bool.self, forKey: .isManagedImports) ?? false
        configurationRevision = max(
            try container.decodeIfPresent(Int.self, forKey: .configurationRevision) ?? 1,
            1
        )
        lastValidatedAt = try container.decodeIfPresent(Date.self, forKey: .lastValidatedAt)
        validationSummary = Self.cleanStatus(try container.decodeIfPresent(String.self, forKey: .validationSummary))
        lastValidationFailureAt = try container.decodeIfPresent(Date.self, forKey: .lastValidationFailureAt)
        validationFailureSummary = Self.cleanStatus(
            try container.decodeIfPresent(String.self, forKey: .validationFailureSummary)
        )
        discoveredItemCount = Self.cleanItemCount(
            try container.decodeIfPresent(Int.self, forKey: .discoveredItemCount)
        )
        capabilities = Self.cleanCapabilities(
            try container.decodeIfPresent([String].self, forKey: .capabilities) ?? []
        )
        networkDisplayHost = Self.cleanNetworkDisplayHost(
            try container.decodeIfPresent(String.self, forKey: .networkDisplayHost)
        )
        serverKind = try container.decodeIfPresent(AppleMediaServerKind.self, forKey: .serverKind)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(kind, forKey: .kind)
        try container.encode(name, forKey: .name)
        try container.encode(url, forKey: .url)
        try container.encode(isEnabled, forKey: .isEnabled)
        if needsSignIn { try container.encode(true, forKey: .needsSignIn) }
        try container.encode(addedAt, forKey: .addedAt)
        try container.encodeIfPresent(iptvType, forKey: .iptvType)
        try container.encodeIfPresent(epgURL, forKey: .epgURL)
        try container.encodeIfPresent(credentialReference, forKey: .credentialReference)
        try container.encodeIfPresent(transportReference, forKey: .transportReference)
        try container.encodeIfPresent(bookmarkData, forKey: .bookmarkData)
        if isManagedImports { try container.encode(true, forKey: .isManagedImports) }
        try container.encode(configurationRevision, forKey: .configurationRevision)
        try container.encodeIfPresent(lastValidatedAt, forKey: .lastValidatedAt)
        try container.encodeIfPresent(validationSummary, forKey: .validationSummary)
        try container.encodeIfPresent(lastValidationFailureAt, forKey: .lastValidationFailureAt)
        try container.encodeIfPresent(validationFailureSummary, forKey: .validationFailureSummary)
        try container.encodeIfPresent(discoveredItemCount, forKey: .discoveredItemCount)
        try container.encode(capabilities, forKey: .capabilities)
        try container.encodeIfPresent(networkDisplayHost, forKey: .networkDisplayHost)
        try container.encodeIfPresent(serverKind, forKey: .serverKind)
    }

    private static func cleanStatus(_ value: String?) -> String? {
        value?
            .components(separatedBy: .controlCharacters)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nonEmptyAppleSourceString
            .map(AppleDiagnosticRedactor.redact)
            .map { String($0.prefix(200)) }
    }

    private static func cleanItemCount(_ value: Int?) -> Int? {
        value.map { min(max($0, 0), 1_000_000) }
    }

    private static func cleanNetworkDisplayHost(_ value: String?) -> String? {
        value?
            .components(separatedBy: .controlCharacters)
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nonEmptyAppleSourceString
            .map { String($0.prefix(256)) }
    }

    private static func cleanCapabilities(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.compactMap { value in
            let clean = value
                .components(separatedBy: .controlCharacters)
                .joined(separator: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !clean.isEmpty else { return nil }
            let bounded = String(clean.prefix(40))
            guard seen.insert(bounded.lowercased()).inserted else { return nil }
            return bounded
        }.prefix(16).map { $0 }
    }
}

/// A saved source of a kind this app no longer has: builds before 2026-10-22
/// could add a trailer channel (`youtube`) or a catalog source, which always
/// carried a `manifestID`. It is deleted with its Keychain entries wherever
/// it turns up (this device's list, an iCloud copy, a backup, a transfer),
/// its id is tombstoned so an older build stops sending it back, and it is
/// never kept or passed on. A kind a later build adds is not retired.
struct AppleRetiredSource: Equatable, Sendable {
    let id: UUID
    let keychainReferences: [String]

    /// `fields` is one source as stored.
    init?(fields: [String: Any]) {
        guard let kind = fields["kind"] as? String, AppleSourceKind(rawValue: kind) == nil,
              kind == "youtube" || fields["manifestID"] is String,
              let id = (fields["id"] as? String).flatMap(UUID.init(uuidString:)) else { return nil }
        self.id = id
        let reference = id.uuidString.lowercased()
        keychainReferences = [fields["credentialReference"] as? String, fields["transportReference"] as? String,
                              reference, "transport.\(reference)", "guide.\(reference)"].compactMap { $0 }
    }

    /// Caches the retired sources and the old chart rows filled in
    /// `Caches/OpenStream`: the shelf cache, the chart and its artwork.
    /// Cheap, so it runs on every launch.
    static func removeLeftoverFiles(fileManager: FileManager = .default) {
        guard let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first else { return }
        let folder = caches.appending(path: "OpenStream", directoryHint: .isDirectory)
        let names = (try? fileManager.contentsOfDirectory(atPath: folder.path)) ?? []
        for name in names where name == "catalogs-v2.json" || name == "top10-artwork-v1.json" || name.hasSuffix("-top10-v1.json") {
            try? fileManager.removeItem(at: folder.appending(path: name))
        }
    }
}

private struct AppleSourceLossyList {
    let values: [AppleSource]
    let retired: [AppleRetiredSource]

    init(data: Data) throws {
        guard let members = try JSONSerialization.jsonObject(with: data) as? [Any] else {
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Expected a source array"))
        }
        var result: [AppleSource] = []
        var retired: [AppleRetiredSource] = []
        for member in members.prefix(1_024) {
            guard JSONSerialization.isValidJSONObject(member),
                  let payload = try? JSONSerialization.data(withJSONObject: member) else {
                continue
            }
            if let value = try? JSONDecoder().decode(AppleSource.self, from: payload) {
                result.append(value)
            } else if let fields = member as? [String: Any], let source = AppleRetiredSource(fields: fields) {
                retired.append(source)
            }
        }
        values = result
        self.retired = retired
    }
}

@MainActor
@Observable
public final class AppleSourceStore {
    public private(set) var sources: [AppleSource] {
        didSet {
            let remaining = Set(sources.map(\.id))
            let available = Set(sources.filter { $0.isEnabled && !$0.needsSignIn }.map(\.id))
            if oldValue.contains(where: { !remaining.contains($0.id)
                || ($0.isEnabled && !$0.needsSignIn && !available.contains($0.id)) }) {
                do { try AppleTopShelfRouteStore.removeFile(at: topShelfRoutesURL) }
                catch { appleTraceFailure("top shelf route cache removal failed") }
            }
        }
    }
    public private(set) var sourceTombstones: [UUID: Date]
    public private(set) var credentialError: String?

    private let defaults: UserDefaults
    private let storageKey: String
    private let keychain: any AppleCredentialStoring
    private let managedImportsDirectory: URL
    private let topShelfRoutesURL: URL
    private var protectsStoredBlobWhenEmpty: Bool
    private var pendingCredentialCleanupReferences: [String]

    public init(
        defaults: UserDefaults = .standard,
        storageKey: String = "openstream.sources.v1",
        keychain: any AppleCredentialStoring = AppleKeychainStore(service: "com.orgista.openstream.instances"),
        documentsDirectory: URL? = nil,
        topShelfRoutesURL: URL? = nil
    ) {
        self.defaults = defaults
        self.storageKey = storageKey
        sourceTombstones = defaults.data(forKey: storageKey + ".tombstones")
            .flatMap { try? JSONDecoder().decode([UUID: Date].self, from: $0) } ?? [:]
        self.keychain = keychain
        self.topShelfRoutesURL = topShelfRoutesURL ?? AppleTopShelfRouteStore.defaultURL
        managedImportsDirectory = (documentsDirectory ?? AppleStorageLocation.documents)
            .appendingPathComponent("Imports", isDirectory: true).standardizedFileURL
        credentialError = nil
        pendingCredentialCleanupReferences = defaults.stringArray(
            forKey: storageKey + ".pending-keychain-removals"
        ) ?? []
        var retired: [AppleRetiredSource] = []
        if let data = defaults.data(forKey: storageKey) {
            if let decoded = try? AppleSourceLossyList(data: data) {
                sources = decoded.values.sorted { $0.addedAt < $1.addedAt }
                retired = decoded.retired
                protectsStoredBlobWhenEmpty = decoded.values.isEmpty && decoded.retired.isEmpty
                    && !Self.isEmptyStoredList(data)
            } else {
                sources = []
                protectsStoredBlobWhenEmpty = !Self.isEmptyStoredList(data)
            }
        } else {
            sources = []
            protectsStoredBlobWhenEmpty = false
        }
        if !sourceTombstones.isEmpty { mergeSourceTombstones([:]) }
        retryPendingCredentialCleanup()
        hydrateProtectedTransportURLs()
        hydrateGuideAddresses()
        migrateLegacyIPTVCredentials()
        relocateManagedImports()
        // After the migrations above, so the save that drops them is not
        // refused for a source still holding inline credentials.
        if !retired.isEmpty { deleteRetiredSources(retired) }
        AppleRetiredSource.removeLeftoverFiles()
    }

    public func setEnabled(_ enabled: Bool, id: AppleSource.ID) {
        guard let index = sources.firstIndex(where: { $0.id == id }) else { return }
        guard sources[index].isEnabled != enabled, !enabled || !sources[index].needsSignIn else { return }
        sources[index].isEnabled = enabled
        sources[index].configurationRevision = nextConfigurationRevision(sources[index].configurationRevision)
        persist()
    }

    @discardableResult
    public func addIPTV(
        name: String,
        type: AppleIPTVSourceType,
        endpoint: String,
        username: String = "",
        password: String = "",
        epgURL: String? = nil,
        lastValidatedAt: Date? = nil,
        validationSummary: String? = nil,
        discoveredItemCount: Int? = nil,
        capabilities: [String] = []
    ) throws -> AppleSource {
        let url = try AppleIPTVEndpointPolicy.normalize(endpoint)
        let cleanName = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(100))
        let displayName = cleanName.isEmpty ? "My TV" : cleanName
        let cleanUsername = String(username.trimmingCharacters(in: .whitespacesAndNewlines).prefix(512))
        let cleanPassword = String(password.prefix(512))
        let cleanEPGURL: URL?
        if let epgURL, !epgURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            cleanEPGURL = try AppleIPTVEndpointPolicy.normalize(epgURL)
        } else {
            cleanEPGURL = nil
        }
        let cleanValidationSummary = validationSummary?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nonEmptyAppleSourceString
            .map { String($0.prefix(200)) }
        if type == .xtream, cleanUsername.isEmpty || cleanPassword.isEmpty {
            throw AppleIPTVError.missingCredentials
        }

        if let index = sources.firstIndex(where: { candidate in
            guard candidate.kind == .liveTV, candidate.iptvType == type, candidate.url == url else { return false }
            return type == .m3u || (try? iptvCredentials(for: candidate))?.username == cleanUsername
        }) {
            let existing = sources[index]
            let reference = existing.id.uuidString.lowercased()
            try updateIPTVCredentials(
                type: type,
                reference: reference,
                username: cleanUsername,
                password: cleanPassword
            )
            if cleanEPGURL == nil { try? keychain.remove(Self.guideReference(existing.id)) }
            sources[index] = try securedTransportSource(AppleSource(
                id: existing.id,
                kind: .liveTV,
                name: displayName,
                url: url,
                isEnabled: true,
                addedAt: existing.addedAt,
                iptvType: type,
                epgURL: cleanEPGURL,
                credentialReference: type == .xtream ? reference : nil,
                transportReference: existing.transportReference,
                configurationRevision: nextConfigurationRevision(existing.configurationRevision),
                lastValidatedAt: lastValidatedAt,
                validationSummary: cleanValidationSummary,
                lastValidationFailureAt: existing.lastValidationFailureAt,
                validationFailureSummary: existing.validationFailureSummary,
                discoveredItemCount: discoveredItemCount,
                capabilities: capabilities
            ))
            persist()
            return sources[index]
        }

        let id = UUID()
        let reference = id.uuidString.lowercased()
        try updateIPTVCredentials(
            type: type,
            reference: reference,
            username: cleanUsername,
            password: cleanPassword
        )
        let source = try securedTransportSource(AppleSource(
            id: id,
            kind: .liveTV,
            name: displayName,
            url: url,
            iptvType: type,
            epgURL: cleanEPGURL,
            credentialReference: type == .xtream ? reference : nil,
            lastValidatedAt: lastValidatedAt,
            validationSummary: cleanValidationSummary,
            discoveredItemCount: discoveredItemCount,
            capabilities: capabilities
        ))
        sources.append(source)
        persist()
        return source
    }

    @discardableResult
    public func addLibraryFolder(name: String, url: URL, bookmarkData: Data?) throws -> AppleSource {
        guard url.isFileURL else { throw AppleLibrarySourceError.invalidFolder }
        let url = url.standardizedFileURL
        let isManagedImports = url == managedImportsDirectory
        let bookmarkData = isManagedImports ? nil : bookmarkData
        let cleanName = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(100))
        let displayName = cleanName.isEmpty ? url.lastPathComponent : cleanName
        if let index = sources.firstIndex(where: { $0.kind == .library && $0.url == url }) {
            sources[index].name = displayName
            sources[index].isEnabled = true
            sources[index].bookmarkData = bookmarkData
            sources[index].isManagedImports = isManagedImports
            sources[index].configurationRevision = nextConfigurationRevision(sources[index].configurationRevision)
            sources[index].lastValidatedAt = .now
            sources[index].validationSummary = "Folder access granted"
            sources[index].capabilities = ["Files", "Playback"]
            persist()
            return sources[index]
        }
        let source = AppleSource(
            kind: .library,
            name: displayName,
            url: url,
            bookmarkData: bookmarkData,
            isManagedImports: isManagedImports,
            lastValidatedAt: .now,
            validationSummary: "Folder access granted",
            capabilities: ["Files", "Playback"]
        )
        sources.append(source)
        persist()
        return source
    }

    @discardableResult
    public func addNetworkShare(
        name: String,
        host: String,
        port: Int = 445,
        share: String,
        path: String = "",
        username: String = "",
        password: String = "",
        domain: String = "",
        displayHost: String? = nil,
        lastValidatedAt: Date? = nil,
        validationSummary: String? = nil,
        discoveredItemCount: Int? = nil,
        capabilities: [String] = []
    ) throws -> AppleSource {
        let url = try AppleSMBEndpointPolicy.makeURL(host: host, port: port, share: share, path: path)
        let cleanName = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(100))
        let displayName = cleanName.isEmpty ? share : cleanName
        let cleanDisplayHost = (displayHost ?? host)
            .components(separatedBy: .controlCharacters)
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let boundedDisplayHost = cleanDisplayHost.isEmpty ? nil : String(cleanDisplayHost.prefix(256))
        let credentials = AppleSMBCredentials(
            username: String(username.trimmingCharacters(in: .whitespacesAndNewlines).prefix(512)),
            password: String(password.prefix(512)),
            domain: String(domain.trimmingCharacters(in: .whitespacesAndNewlines).prefix(256))
        )
        let cleanValidationSummary = validationSummary?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nonEmptyAppleSourceString
            .map { String($0.prefix(200)) }

        if let index = sources.firstIndex(where: { $0.kind == .nas && $0.url == url }) {
            let oldReference = sources[index].credentialReference
            let reference = try networkCredentialReference(
                server: .init(name: host, host: host, port: port, displayHost: displayHost), credentials: credentials,
                excluding: sources[index].id, preferred: sources[index].credentialReference ?? sources[index].id.uuidString.lowercased())
            try updateNetworkCredentials(credentials, reference: reference)
            sources[index].name = displayName
            sources[index].isEnabled = true
            sources[index].credentialReference = reference
            sources[index].networkDisplayHost = boundedDisplayHost
            sources[index].configurationRevision = nextConfigurationRevision(sources[index].configurationRevision)
            sources[index].lastValidatedAt = lastValidatedAt
            sources[index].validationSummary = cleanValidationSummary
            sources[index].discoveredItemCount = discoveredItemCount.map { min(max($0, 0), 1_000_000) }
            sources[index].capabilities = boundedCapabilities(capabilities)
            persist()
            retireNetworkCredential(oldReference, keeping: reference)
            return sources[index]
        }

        let id = UUID()
        let reference = try networkCredentialReference(
            server: .init(name: host, host: host, port: port, displayHost: displayHost), credentials: credentials,
            preferred: id.uuidString.lowercased())
        try updateNetworkCredentials(credentials, reference: reference)
        let source = AppleSource(
            id: id,
            kind: .nas,
            name: displayName,
            url: url,
            credentialReference: reference,
            lastValidatedAt: lastValidatedAt,
            validationSummary: cleanValidationSummary,
            discoveredItemCount: discoveredItemCount,
            capabilities: capabilities,
            networkDisplayHost: boundedDisplayHost
        )
        sources.append(source)
        persist()
        return source
    }

    /// Points an existing network share at a new server, folder or account,
    /// keeping its identity (and so its library and watch history).
    @discardableResult
    func updateNetworkShare(
        id: AppleSource.ID,
        name: String,
        host: String,
        port: Int,
        share: String,
        path: String,
        credentials: AppleSMBCredentials,
        displayHost: String?,
        validationSummary: String?
    ) throws -> AppleSource {
        guard let index = sources.firstIndex(where: { $0.id == id && $0.kind == .nas }) else {
            throw AppleSMBError.invalidShare
        }
        let url = try AppleSMBEndpointPolicy.makeURL(host: host, port: port, share: share, path: path)
        let cleanName = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(100))
        let cleanDisplayHost = (displayHost ?? host)
            .components(separatedBy: .controlCharacters)
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let oldReference = sources[index].credentialReference
        let cleanCredentials = AppleSMBCredentials(
            username: String(credentials.username.trimmingCharacters(in: .whitespacesAndNewlines).prefix(512)),
            password: String(credentials.password.prefix(512)),
            domain: String(credentials.domain.trimmingCharacters(in: .whitespacesAndNewlines).prefix(256)))
        let reference = try networkCredentialReference(
            server: .init(name: host, host: host, port: port, displayHost: displayHost), credentials: cleanCredentials,
            excluding: id, preferred: sources[index].credentialReference ?? id.uuidString.lowercased())
        try updateNetworkCredentials(cleanCredentials, reference: reference)
        sources[index].name = cleanName.isEmpty ? share : cleanName
        sources[index].url = url
        sources[index].isEnabled = true
        sources[index].credentialReference = reference
        sources[index].networkDisplayHost = cleanDisplayHost.isEmpty ? nil : String(cleanDisplayHost.prefix(256))
        sources[index].configurationRevision = nextConfigurationRevision(sources[index].configurationRevision)
        sources[index].lastValidatedAt = .now
        sources[index].validationSummary = validationSummary.flatMap(boundedStatus)
        persist()
        retireNetworkCredential(oldReference, keeping: reference)
        // Open playback sessions still carry the old address or account.
        Task { await AppleSMBRangeServer.shared.removeAllSessions() }
        return sources[index]
    }

    public func recordValidationSuccess(
        id: AppleSource.ID,
        summary: String,
        discoveredItemCount: Int? = nil,
        capabilities: [String]? = nil,
        at date: Date = .now
    ) {
        guard let index = sources.firstIndex(where: { $0.id == id }) else { return }
        sources[index].lastValidatedAt = date
        sources[index].validationSummary = boundedStatus(summary)
        sources[index].discoveredItemCount = discoveredItemCount.map { min(max($0, 0), 1_000_000) }
        if let capabilities {
            sources[index].capabilities = boundedCapabilities(capabilities)
        }
        persist()
    }

    public func recordValidationFailure(
        id: AppleSource.ID,
        summary: String,
        at date: Date = .now
    ) {
        guard let index = sources.firstIndex(where: { $0.id == id }) else { return }
        sources[index].lastValidationFailureAt = date
        sources[index].validationFailureSummary = boundedStatus(summary) ?? "Connection failed"
        persist()
    }

    @discardableResult
    public func remove(id: AppleSource.ID) -> Bool {
        guard let source = sources.first(where: { $0.id == id }) else {
            appleTrace("remove source \(id): not in the list")
            return false
        }
        appleTrace("remove source \"\(source.name)\" (\(source.kind))")
        let referenceID = source.id.uuidString.lowercased()
        let references = [source.credentialReference, source.transportReference, referenceID, "transport.\(referenceID)", "guide.\(referenceID)"].compactMap { $0 }
        pendingCredentialCleanupReferences.append(contentsOf: references)
        pendingCredentialCleanupReferences = Array(Set(pendingCredentialCleanupReferences)).sorted()
        persistPendingCredentialCleanup()
        sourceTombstones[id] = .now
        sources.removeAll { $0.id == id }
        persist()
        retryPendingCredentialCleanup()
        if source.kind == .nas {
            Task { await AppleSMBRangeServer.shared.removeAllSessions() }
        }
        return true
    }

    public func iptvCredentials(for source: AppleSource) throws -> AppleIPTVCredentials? {
        guard source.kind == .liveTV, source.iptvType == .xtream else { return nil }

        var references: [String] = []
        if let reference = source.credentialReference?.trimmingCharacters(in: .whitespacesAndNewlines),
           !reference.isEmpty,
           !references.contains(reference) {
            references.append(reference)
        }
        if let transportReference = source.transportReference?.trimmingCharacters(in: .whitespacesAndNewlines),
           !transportReference.isEmpty,
           !references.contains(transportReference) {
            references.append(transportReference)
        }
        let sourceReference = source.id.uuidString.lowercased()
        if !references.contains(sourceReference) {
            references.append(sourceReference)
        }

        var lastLookupError: (any Swift.Error)?
        for reference in references {
            do {
                guard let value = try keychain.string(for: reference),
                      let data = value.data(using: .utf8) else { continue }
                let credentials = try JSONDecoder().decode(AppleIPTVCredentials.self, from: data)
                if source.credentialReference != reference, let index = sources.firstIndex(where: { $0.id == source.id }) {
                    sources[index].credentialReference = reference
                    sources[index].legacyUsername = nil
                    sources[index].legacyPassword = nil
                    persist()
                }
                return credentials
            } catch is DecodingError {
                lastLookupError = AppleKeychainStoreError.invalidData
            } catch {
                lastLookupError = error
            }
        }

        let legacyUsername = source.legacyUsername?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let legacyPassword = source.legacyPassword?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !legacyUsername.isEmpty && !legacyPassword.isEmpty {
            let reference = source.credentialReference ?? sourceReference
            try updateIPTVCredentials(type: .xtream, reference: reference, username: legacyUsername, password: legacyPassword)
            if let index = sources.firstIndex(where: { $0.id == source.id }) {
                sources[index].credentialReference = reference
                sources[index].legacyUsername = nil
                sources[index].legacyPassword = nil
                persist()
            }
            return AppleIPTVCredentials(username: legacyUsername, password: legacyPassword)
        }

        if let lastLookupError { credentialError = lastLookupError.localizedDescription }
        return nil
    }

    public func networkCredentials(for source: AppleSource) throws -> AppleSMBCredentials? {
        guard source.kind == .nas,
              let reference = source.credentialReference,
              let value = try keychain.string(for: reference),
              let data = value.data(using: .utf8) else { return nil }
        return try JSONDecoder().decode(AppleSMBCredentials.self, from: data)
    }

    private func updateIPTVCredentials(
        type: AppleIPTVSourceType,
        reference: String,
        username: String,
        password: String
    ) throws {
        if type == .xtream {
            let credentials = AppleIPTVCredentials(username: username, password: password)
            let data = try JSONEncoder().encode(credentials)
            guard let value = String(data: data, encoding: .utf8) else {
                throw AppleKeychainStoreError.invalidData
            }
            try keychain.set(value, for: reference)
        } else {
            try keychain.remove(reference)
        }
        credentialError = nil
    }

    /// Folders on one server/account share a key. An account/server edit
    /// detaches when its old key is still used by another folder.
    private func networkCredentialReference(
        server: AppleNetworkShareServer,
        credentials: AppleSMBCredentials,
        excluding id: UUID? = nil,
        preferred: String? = nil
    ) throws -> String {
        for source in sources where source.id != id && AppleNetworkSharePolicy.sameServer(source, as: server) {
            // One unreadable sibling entry must not block this folder: it
            // just isn't a key to share.
            guard let reference = source.credentialReference,
                  let saved = try? networkCredentials(for: source),
                  saved.username == credentials.username, saved.domain == credentials.domain else { continue }
            return reference
        }
        if let preferred, !sources.contains(where: { $0.id != id && $0.credentialReference == preferred }) {
            return preferred
        }
        return UUID().uuidString.lowercased()
    }

    private func retireNetworkCredential(_ oldReference: String?, keeping reference: String) {
        guard let oldReference, oldReference != reference else { return }
        pendingCredentialCleanupReferences = Array(Set(pendingCredentialCleanupReferences + [oldReference])).sorted()
        persistPendingCredentialCleanup()
        retryPendingCredentialCleanup()
    }

    private func updateNetworkCredentials(_ credentials: AppleSMBCredentials, reference: String) throws {
        let stored = try keychain.string(for: reference)
            .flatMap { $0.data(using: .utf8) }
            .flatMap { try? JSONDecoder().decode(AppleSMBCredentials.self, from: $0) }
        if stored == credentials {
            credentialError = nil
            return
        }
        let data = try JSONEncoder().encode(credentials)
        guard let value = String(data: data, encoding: .utf8) else {
            throw AppleKeychainStoreError.invalidData
        }
        try keychain.set(value, for: reference)
        for index in sources.indices where sources[index].kind == .nas && sources[index].credentialReference == reference {
            sources[index].configurationRevision = nextConfigurationRevision(sources[index].configurationRevision)
        }
        credentialError = nil
    }

    public func addMediaServer(
        kind: AppleMediaServerKind,
        name: String,
        session: AppleMediaServerSession
    ) throws -> AppleSource {
        let cleanName = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(100))
        let displayName = cleanName.isEmpty ? kind.title : cleanName

        if let index = sources.firstIndex(where: { candidate in
            guard candidate.kind == .mediaServer, candidate.serverKind == kind else { return false }
            guard candidate.url.host?.lowercased() == session.baseURL.host?.lowercased() else { return false }
            guard candidate.url.port == session.baseURL.port else { return false }
            if candidate.needsSignIn { return true }
            return (try? mediaServerSession(for: candidate))?.userID == session.userID
        }) {
            let existing = sources[index]
            let reference = existing.id.uuidString.lowercased()
            try updateMediaServerCredentials(reference: reference, session: session)
            let updated = try securedTransportSource(AppleSource(
                id: existing.id,
                kind: .mediaServer,
                name: displayName,
                url: session.baseURL,
                isEnabled: existing.needsSignIn ? true : existing.isEnabled,
                addedAt: existing.addedAt,
                credentialReference: reference,
                transportReference: existing.transportReference,
                isManagedImports: existing.isManagedImports,
                configurationRevision: existing.configurationRevision,
                serverKind: kind
            ))
            sources[index] = updated
            persist()
            return updated
        }

        let newID = UUID()
        let reference = newID.uuidString.lowercased()
        try updateMediaServerCredentials(reference: reference, session: session)

        let newSource = try securedTransportSource(AppleSource(
            id: newID,
            kind: .mediaServer,
            name: displayName,
            url: session.baseURL,
            credentialReference: reference,
            serverKind: kind
        ))
        sources.insert(newSource, at: 0)
        persist()
        return newSource
    }

    public func mediaServerSession(for source: AppleSource) throws -> AppleMediaServerSession? {
        guard source.kind == .mediaServer else { return nil }
        guard let reference = source.credentialReference else { return nil }
        guard let value = try keychain.string(for: reference), let data = value.data(using: .utf8) else {
            return nil
        }
        return try JSONDecoder().decode(AppleMediaServerSession.self, from: data)
    }

    private func updateMediaServerCredentials(reference: String, session: AppleMediaServerSession) throws {
        let data = try JSONEncoder().encode(session)
        guard let value = String(data: data, encoding: .utf8) else {
            throw AppleKeychainStoreError.invalidData
        }
        try keychain.set(value, for: reference)
        credentialError = nil
    }

    private func boundedStatus(_ value: String) -> String? {
        value
            .components(separatedBy: .controlCharacters)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nonEmptyAppleSourceString
            .map(AppleDiagnosticRedactor.redact)
            .map { String($0.prefix(200)) }
    }

    private func boundedCapabilities(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.compactMap { value in
            let clean = value
                .components(separatedBy: .controlCharacters)
                .joined(separator: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !clean.isEmpty else { return nil }
            let bounded = String(clean.prefix(40))
            guard seen.insert(bounded.lowercased()).inserted else { return nil }
            return bounded
        }.prefix(16).map { $0 }
    }

    private func nextConfigurationRevision(_ current: Int) -> Int {
        current == .max ? 1 : max(current + 1, 1)
    }

    private func migrateLegacyIPTVCredentials() {
        var didMigrate = false
        for index in sources.indices {
            guard sources[index].kind == .liveTV,
                  sources[index].iptvType == .xtream,
                  let username = sources[index].legacyUsername,
                  !username.isEmpty,
                  let password = sources[index].legacyPassword,
                  !password.isEmpty else { continue }
            let reference = sources[index].credentialReference
                ?? sources[index].id.uuidString.lowercased()
            do {
                try updateIPTVCredentials(
                    type: .xtream,
                    reference: reference,
                    username: username,
                    password: password
                )
                sources[index].credentialReference = reference
                sources[index].legacyUsername = nil
                sources[index].legacyPassword = nil
                didMigrate = true
            } catch {
                credentialError = error.localizedDescription
            }
        }
        if didMigrate { persist() }
    }

    private func relocateManagedImports() {
        var changed = false
        for index in sources.indices where sources[index].kind == .library {
            let source = sources[index]
            let parts = source.url.standardizedFileURL.pathComponents
            // Older portal imports had no bookmark or ownership marker. Only
            // recognize the app-container Documents/Imports layout, never an
            // arbitrary external folder named Imports or a granted bookmark.
            let legacyImports = source.bookmarkData == nil && source.url.isFileURL
                && parts.count >= 7
                && Array(parts.suffix(6).prefix(3)) == ["Containers", "Data", "Application"]
                && UUID(uuidString: parts[parts.count - 3]) != nil
                && Array(parts.suffix(2)) == ["Documents", "Imports"]
            guard source.isManagedImports || legacyImports else { continue }
            guard source.url != managedImportsDirectory || !source.isManagedImports || source.bookmarkData != nil else { continue }
            sources[index].url = managedImportsDirectory
            sources[index].isManagedImports = true
            sources[index].bookmarkData = nil
            sources[index].configurationRevision = nextConfigurationRevision(source.configurationRevision)
            changed = true
        }
        if changed { persist() }
    }

    /// Drops retired sources from the stored list, queues their Keychain
    /// entries for removal and tombstones their ids, so a device on an older
    /// build deletes them too instead of sending them back through iCloud.
    private func deleteRetiredSources(_ retired: [AppleRetiredSource]) {
        pendingCredentialCleanupReferences = Array(Set(pendingCredentialCleanupReferences
            + retired.flatMap(\.keychainReferences))).sorted()
        retryPendingCredentialCleanup()
        for source in retired where sourceTombstones[source.id] == nil { sourceTombstones[source.id] = .now }
        persist()
        appleTrace("sources: deleted \(retired.count) retired")
    }

    func mergeSourceTombstones(_ incoming: [UUID: Date]) {
        let combined = sourceTombstones.merging(incoming) { max($0, $1) }
        for id in combined.keys where sources.contains(where: { $0.id == id }) { _ = remove(id: id) }
        sourceTombstones = combined
        persist()
    }

    func configurationSecrets() throws -> AppleConfigurationSecrets {
        var result = AppleConfigurationSecrets()
        for source in sources {
            if let reference = source.credentialReference {
                result.sourceCredentials[source.id] = try keychain.string(for: reference)
            }
            if !source.needsSignIn {
                result.sourceAddresses[source.id] = source.url
                result.guideAddresses[source.id] = source.epgURL
            }
        }
        return result
    }

    /// Restores `incoming` over (or, without `merge`, instead of) this
    /// device's sources. A source whose sign-in or address this device's
    /// keychain will not keep is not fatal: it keeps this device's copy when
    /// there is one, else arrives signed out for the viewer to sign in again.
    /// Returns how many sources that happened to.
    @discardableResult
    func restoreConfigurationSources(_ incoming: [AppleSource], secrets: AppleConfigurationSecrets?, merge: Bool = true) throws -> Int {
        var merged = merge ? sources : []
        var signedOut = 0
        for portable in incoming where sourceTombstones[portable.id] == nil {
            let restored: AppleSource
            let existing = sources.first { $0.id == portable.id }
            do {
                restored = try restoredConfigurationSource(portable, existing: existing, secrets: secrets)
            } catch {
                signedOut += 1
                appleTraceFailure("source restore: \(portable.kind.rawValue) kept signed out: \(appleErrorLabel(error))")
                if let existing {
                    restored = existing
                } else {
                    var fallback = AppleConfigurationSnapshot.portableSource(portable)
                    fallback.credentialReference = nil
                    fallback.transportReference = nil
                    fallback.needsSignIn = true
                    fallback.isEnabled = false
                    restored = fallback
                }
            }
            if let index = merged.firstIndex(where: { $0.id == restored.id }) { merged[index] = restored }
            else { merged.append(restored) }
        }
        sources = merged
        persist()
        return signedOut
    }

    private func restoredConfigurationSource(_ portable: AppleSource, existing: AppleSource?,
                                             secrets: AppleConfigurationSecrets?) throws -> AppleSource {
        var restored = AppleConfigurationSnapshot.portableSource(portable)
        if let existing, existing.kind == restored.kind,
           AppleConfigurationSnapshot.publicAddress(existing.url) == restored.url
            || AppleConfigurationSnapshot.portableSource(existing).url == restored.url {
            restored.bookmarkData = existing.bookmarkData
            restored.credentialReference = existing.credentialReference
            restored.transportReference = existing.transportReference
            restored.url = existing.url
            restored.epgURL = existing.epgURL
            restored.needsSignIn = existing.needsSignIn
        }
        if let address = secrets?.sourceAddresses[restored.id] {
            restored.url = address
            restored.epgURL = secrets?.guideAddresses[restored.id]
            restored.needsSignIn = false
        }
        if let value = secrets?.sourceCredentials[restored.id] {
            let reference = restored.id.uuidString.lowercased()
            try keychain.set(value, for: reference)
            restored.credentialReference = reference
        } else if AppleConfigurationSyncPolicy.isEnabled(storedPreference: AppleConfigurationSyncPolicy.storedPreference()), restored.kind != .library {
            // Stable accounts reconnect independently arriving iCloud Keychain items.
            let reference = restored.id.uuidString.lowercased()
            if try keychain.string(for: reference) != nil { restored.credentialReference = reference }
            let transport = "transport.\(reference)"
            if let address = try keychain.string(for: transport), let url = URL(string: address) {
                restored.url = url
                restored.transportReference = transport
                restored.epgURL = try keychain.string(for: "guide.\(reference)").flatMap(URL.init(string:))
                restored.needsSignIn = false
                if existing?.needsSignIn == true { restored.isEnabled = true }
            }
        }
        if restored.kind == .library || AppleLocalPlaylistStore.isLocal(restored.url) {
            restored.needsSignIn = existing == nil || existing?.needsSignIn == true
        }
        if (restored.kind == .mediaServer || restored.kind == .nas || restored.iptvType == .xtream), restored.credentialReference == nil {
            restored.needsSignIn = true
        }
        if restored.needsSignIn { restored.isEnabled = false }
        else { restored = try securedTransportSource(restored) }
        if let existing, existing.url != restored.url || existing.isEnabled != restored.isEnabled
            || existing.credentialReference != restored.credentialReference {
            restored.configurationRevision = nextConfigurationRevision(max(existing.configurationRevision, restored.configurationRevision))
        }
        return restored
    }

    func reconnectConfigurationFolder(id: UUID, url: URL, bookmark: Data?) {
        guard let index = sources.firstIndex(where: { $0.id == id }), sources[index].kind == .library else { return }
        sources[index].url = url
        sources[index].bookmarkData = bookmark
        sources[index].isManagedImports = false
        sources[index].needsSignIn = false
        sources[index].isEnabled = true
        persist()
    }

    func prepareConfigurationKeychain() throws {
        for source in sources where !source.needsSignIn && source.kind != .library && !AppleLocalPlaylistStore.isLocal(source.url) {
            let id = source.id.uuidString.lowercased()
            try keychain.set(source.url.absoluteString, for: "transport.\(id)")
            if let guide = source.epgURL { try keychain.set(guide.absoluteString, for: "guide.\(id)") }
            if let reference = source.credentialReference, reference != id,
               let credential = try keychain.string(for: reference) {
                try keychain.set(credential, for: id)
            }
        }
    }

    func refreshConfigurationKeychain() throws {
        let pending = sources.filter { $0.needsSignIn && $0.kind != .library }
        guard !pending.isEmpty else { return }
        try restoreConfigurationSources(pending, secrets: nil)
    }

    func restoreSourceSignIn(id: UUID, address: URL, username: String, password: String) throws {
        guard let index = sources.firstIndex(where: { $0.id == id }) else { return }
        var source = sources[index]
        let reference = id.uuidString.lowercased()
        if source.kind == .liveTV, source.iptvType == .xtream {
            try updateIPTVCredentials(type: .xtream, reference: reference, username: username, password: password)
            source.credentialReference = reference
        } else if source.kind == .nas {
            try updateNetworkCredentials(.init(username: username, password: password), reference: reference)
            source.credentialReference = reference
        }
        source.url = address
        source.needsSignIn = false
        source.isEnabled = true
        sources[index] = try securedTransportSource(source)
        persist()
    }

    private func securedTransportSource(_ source: AppleSource) throws -> AppleSource {
        guard Self.protectsTransportURL(source) else { return source }
        var secured = source
        let reference = source.transportReference ?? "transport.\(source.id.uuidString.lowercased())"
        try keychain.set(source.url.absoluteString, for: reference)
        secured.transportReference = reference
        return secured
    }

    private func hydrateProtectedTransportURLs() {
        var migrated = false
        for index in sources.indices where Self.protectsTransportURL(sources[index]) && !sources[index].needsSignIn {
            if let reference = sources[index].transportReference {
                do {
                    guard let stored = try keychain.string(for: reference),
                          let url = URL(string: stored),
                          url.scheme != nil else {
                        credentialError = "A saved source address is unavailable. Re-add that source."
                        continue
                    }
                    sources[index].url = url
                } catch {
                    credentialError = error.localizedDescription
                }
                continue
            }
            do {
                sources[index] = try securedTransportSource(sources[index])
                migrated = true
            } catch {
                credentialError = error.localizedDescription
            }
        }
        if migrated { persist() }
    }

    /// The guide (EPG) address can carry the provider password in its query,
    /// so it lives in the Keychain under `guide.<id>`, never in the defaults
    /// blob. Older blobs that still hold it are rewritten without it.
    private func hydrateGuideAddresses() {
        var storedInBlob = false
        for index in sources.indices where Self.protectsTransportURL(sources[index]) {
            if sources[index].epgURL != nil {
                storedInBlob = true
                continue
            }
            do {
                sources[index].epgURL = try keychain.string(for: Self.guideReference(sources[index].id))
                    .flatMap(URL.init(string:))
            } catch {
                credentialError = error.localizedDescription
            }
        }
        if storedInBlob { persist() }
    }

    static func guideReference(_ id: UUID) -> String {
        "guide.\(id.uuidString.lowercased())"
    }

    private func retryPendingCredentialCleanup() {
        guard !pendingCredentialCleanupReferences.isEmpty else { return }
        let activeReferences = Set(sources.flatMap { source in
            [source.credentialReference, source.transportReference].compactMap { $0 }
        })
        var failed: [String] = []
        for reference in pendingCredentialCleanupReferences {
            guard !activeReferences.contains(reference) else {
                failed.append(reference)
                continue
            }
            do {
                try keychain.remove(reference)
            } catch {
                failed.append(reference)
                credentialError = error.localizedDescription
            }
        }
        pendingCredentialCleanupReferences = failed
        persistPendingCredentialCleanup()
        if failed.isEmpty { credentialError = nil }
    }

    private func persistPendingCredentialCleanup() {
        let key = storageKey + ".pending-keychain-removals"
        if pendingCredentialCleanupReferences.isEmpty {
            defaults.removeObject(forKey: key)
        } else {
            defaults.set(pendingCredentialCleanupReferences, forKey: key)
        }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(sourceTombstones) { defaults.set(data, forKey: storageKey + ".tombstones") }
        // Each of these refusals is correct — they protect a stored list from
        // being replaced by an empty or credential-leaking one — but they are
        // also indistinguishable from a successful save until the next launch
        // shows the source gone. Say which one fired.
        guard !(protectsStoredBlobWhenEmpty && sources.isEmpty) else {
            appleTraceFailure("sources not saved: refusing to overwrite the stored list with an empty one")
            return
        }
        guard !sources.contains(where: { $0.legacyUsername != nil || $0.legacyPassword != nil }) else {
            appleTraceFailure("sources not saved: a source still holds legacy inline credentials")
            return
        }
        guard !sources.contains(where: {
            Self.protectsTransportURL($0) && !$0.needsSignIn && $0.transportReference == nil
        }) else {
            appleTraceFailure("sources not saved: a protected source has no transport reference")
            return
        }
        for source in sources where Self.protectsTransportURL(source) {
            guard let guide = source.epgURL?.absoluteString else { continue }
            let reference = Self.guideReference(source.id)
            do {
                if try keychain.string(for: reference) != guide { try keychain.set(guide, for: reference) }
            } catch {
                appleTraceFailure("sources not saved: a guide address could not be stored in the Keychain")
                return
            }
        }
        let persistedSources = sources.map { source -> AppleSource in
            guard Self.protectsTransportURL(source) else { return source }
            var sanitized = source
            sanitized.url = Self.sanitizedTransportURL(source)
            sanitized.epgURL = nil
            return sanitized
        }
        let members: [Any] = persistedSources.compactMap { source in
            guard let data = try? JSONEncoder().encode(source) else { return nil }
            return try? JSONSerialization.jsonObject(with: data)
        }
        guard let encoded = try? JSONSerialization.data(withJSONObject: members) else {
            appleTraceFailure("sources not saved: the list could not be encoded")
            return
        }
        defaults.set(encoded, forKey: storageKey)
        protectsStoredBlobWhenEmpty = false
        appleTrace("sources saved: \(sources.count)")
    }

    private static func protectsTransportURL(_ source: AppleSource) -> Bool {
        source.kind == .liveTV
    }

    private static func sanitizedTransportURL(_ source: AppleSource) -> URL {
        guard var components = URLComponents(url: source.url, resolvingAgainstBaseURL: false) else {
            return URL(string: "https://source.invalid/")!
        }
        components.user = nil
        components.password = nil
        components.query = nil
        components.fragment = nil
        components.path = "/"
        return components.url ?? URL(string: "https://source.invalid/")!
    }

    private static func isEmptyStoredList(_ data: Data) -> Bool {
        String(decoding: data, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines) == "[]"
    }
}

private extension String {
    var nonEmptyAppleSourceString: String? { isEmpty ? nil : self }
}
