import Foundation
import Observation

public enum AppleSourceKind: String, Codable, CaseIterable, Sendable {
    case library
    case stremio
    case youtube
    case liveTV
    case nas

    public var title: String {
        switch self {
        case .library: "Library"
        case .stremio: "Add-on"
        case .youtube: "YouTube"
        case .liveTV: "Live TV"
        case .nas: "Network share"
        }
    }
}

public enum AppleIPTVSourceType: String, Codable, CaseIterable, Sendable {
    case m3u
    case xtream

    public var title: String {
        switch self {
        case .m3u: "M3U Playlist"
        case .xtream: "Xtream Account"
        }
    }
}

public struct AppleSource: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var kind: AppleSourceKind
    public var name: String
    public var url: URL
    public var isEnabled: Bool
    public let addedAt: Date
    public var manifestID: String?
    public var version: String?
    public var resources: [String]
    public var catalogs: [AppleStremioCatalog]
    public var logoURL: URL?
    public var iptvType: AppleIPTVSourceType?
    public var username: String?
    public var password: String?
    public var bookmarkData: Data?

    public init(
        id: UUID = UUID(),
        kind: AppleSourceKind,
        name: String,
        url: URL,
        isEnabled: Bool = true,
        addedAt: Date = .now,
        manifestID: String? = nil,
        version: String? = nil,
        resources: [String] = [],
        catalogs: [AppleStremioCatalog] = [],
        logoURL: URL? = nil,
        iptvType: AppleIPTVSourceType? = nil,
        username: String? = nil,
        password: String? = nil,
        bookmarkData: Data? = nil
    ) {
        self.id = id
        self.kind = kind
        self.name = name
        self.url = url
        self.isEnabled = isEnabled
        self.addedAt = addedAt
        self.manifestID = manifestID
        self.version = version
        self.resources = resources
        self.catalogs = catalogs
        self.logoURL = logoURL
        self.iptvType = iptvType
        self.username = username
        self.password = password
        self.bookmarkData = bookmarkData
    }

    public var transportURL: URL {
        guard kind == .stremio, url.lastPathComponent.lowercased() == "manifest.json" else { return url }
        return url.deletingLastPathComponent()
    }

    private enum CodingKeys: String, CodingKey {
        case id, kind, name, url, isEnabled, addedAt, manifestID, version, resources, catalogs
        case logoURL, iptvType, username, password, bookmarkData
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        kind = try container.decode(AppleSourceKind.self, forKey: .kind)
        name = try container.decode(String.self, forKey: .name)
        url = try container.decode(URL.self, forKey: .url)
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        addedAt = try container.decodeIfPresent(Date.self, forKey: .addedAt) ?? .distantPast
        manifestID = try container.decodeIfPresent(String.self, forKey: .manifestID)
        version = try container.decodeIfPresent(String.self, forKey: .version)
        resources = try container.decodeIfPresent([String].self, forKey: .resources) ?? []
        catalogs = try container.decodeIfPresent([AppleStremioCatalog].self, forKey: .catalogs) ?? []
        logoURL = try container.decodeIfPresent(URL.self, forKey: .logoURL)
        iptvType = try container.decodeIfPresent(AppleIPTVSourceType.self, forKey: .iptvType)
        username = try container.decodeIfPresent(String.self, forKey: .username)
        password = try container.decodeIfPresent(String.self, forKey: .password)
        bookmarkData = try container.decodeIfPresent(Data.self, forKey: .bookmarkData)
    }
}

public enum AppleManifestURLPolicy {
    public enum Error: Swift.Error, Equatable, LocalizedError, Sendable {
        case empty
        case missingScheme
        case insecureHTTP
        case unsupportedScheme(String)
        case invalidURL
        case missingHost
        case credentialsNotAllowed
        case queryNotAllowed
        case fragmentNotAllowed
        case wrongJSONDocument(String)

        public var errorDescription: String? {
            switch self {
            case .empty:
                "Enter a manifest URL."
            case .missingScheme:
                "Add https:// to the beginning."
            case .insecureHTTP:
                "Use the add-on's HTTPS manifest URL."
            case .unsupportedScheme(let scheme):
                "\(scheme) URLs are not supported."
            case .invalidURL:
                "This URL is not valid."
            case .missingHost:
                "This URL is missing a host."
            case .credentialsNotAllowed:
                "URLs containing a username or password are not supported."
            case .queryNotAllowed:
                "URL query options are not supported."
            case .fragmentNotAllowed:
                "URL fragments are not supported."
            case .wrongJSONDocument(let filename):
                "\(filename) is not a manifest.json file."
            }
        }
    }

    public static func normalize(_ value: String) throws -> URL {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw Error.empty }
        guard let schemeSeparator = trimmed.range(of: "://"), schemeSeparator.lowerBound != trimmed.startIndex else {
            throw Error.missingScheme
        }
        guard var components = URLComponents(string: trimmed) else { throw Error.invalidURL }

        let scheme = components.scheme?.lowercased()
        if scheme == "http" { throw Error.insecureHTTP }
        guard scheme == "https" else { throw Error.unsupportedScheme(scheme ?? "Unknown") }
        guard let host = components.host, !host.isEmpty else { throw Error.missingHost }
        guard components.user == nil, components.password == nil else { throw Error.credentialsNotAllowed }
        guard components.query == nil else { throw Error.queryNotAllowed }
        guard components.fragment == nil else { throw Error.fragmentNotAllowed }

        let filename = components.path.split(separator: "/").last.map(String.init)
        if let filename,
           filename.lowercased().hasSuffix(".json"),
           filename.lowercased() != "manifest.json" {
            throw Error.wrongJSONDocument(filename)
        }

        components.scheme = "https"
        components.host = host.lowercased()
        if components.port == 443 { components.port = nil }
        if filename?.lowercased() != "manifest.json" {
            let basePath = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            components.path = basePath.isEmpty ? "/manifest.json" : "/\(basePath)/manifest.json"
        }

        guard let normalized = components.url else { throw Error.invalidURL }
        return normalized
    }
}

public struct AppleStremioCatalog: Codable, Equatable, Sendable {
    public let type: String
    public let id: String
    public let name: String?
    public let requiresInput: Bool
    public let supportsSearch: Bool

    public init(
        type: String,
        id: String,
        name: String? = nil,
        requiresInput: Bool = false,
        supportsSearch: Bool = false
    ) {
        self.type = String(type.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().prefix(40))
        self.id = String(id.trimmingCharacters(in: .whitespacesAndNewlines).prefix(200))
        self.name = name?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nonEmptyAppleSourceString
            .map { String($0.prefix(100)) }
        self.requiresInput = requiresInput
        self.supportsSearch = supportsSearch
    }

    private enum CodingKeys: String, CodingKey {
        case type, id, name, extra, requiresInput, supportsSearch
    }

    private struct Extra: Decodable {
        let name: String?
        let isRequired: Bool

        private enum CodingKeys: String, CodingKey { case name, isRequired }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            name = try? container.decode(String.self, forKey: .name)
            isRequired = (try? container.decode(Bool.self, forKey: .isRequired)) ?? false
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        let id = try container.decode(String.self, forKey: .id)
        let extras = (try? container.decode(
            AppleManifestLossyList<Extra>.self,
            forKey: .extra
        ))?.values ?? []
        self.init(
            type: type,
            id: id,
            name: try? container.decode(String.self, forKey: .name),
            requiresInput: ((try? container.decode(Bool.self, forKey: .requiresInput)) ?? false)
                || extras.contains(where: \.isRequired),
            supportsSearch: ((try? container.decode(Bool.self, forKey: .supportsSearch)) ?? false)
                || extras.contains { $0.name?.trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased() == "search" }
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(name, forKey: .name)
        try container.encode(requiresInput, forKey: .requiresInput)
        try container.encode(supportsSearch, forKey: .supportsSearch)
    }
}

public struct AppleStremioManifest: Decodable, Equatable, Sendable {
    public static let maximumCatalogs = 12

    public let id: String
    public let name: String
    public let version: String?
    public let logoURL: URL?
    public let resources: [String]
    public let catalogs: [AppleStremioCatalog]

    public init(
        id: String,
        name: String,
        version: String? = nil,
        logoURL: URL? = nil,
        resources: [String] = [],
        catalogs: [AppleStremioCatalog] = []
    ) {
        self.id = String(id.trimmingCharacters(in: .whitespacesAndNewlines).prefix(200))
        self.name = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(100))
        self.version = version?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nonEmptyAppleSourceString
            .map { String($0.prefix(40)) }
        self.logoURL = Self.sanitizeLogoURL(logoURL)
        self.resources = Self.sanitizeResources(resources)
        self.catalogs = Self.sanitizeCatalogs(catalogs)
    }

    private enum CodingKeys: String, CodingKey { case id, name, version, logo, icon, resources, catalogs }
    private enum ManifestResource: Decodable {
        case name(String)

        private enum CodingKeys: String, CodingKey { case name }

        init(from decoder: Decoder) throws {
            if let value = try? decoder.singleValueContainer().decode(String.self) {
                self = .name(value)
                return
            }
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self = .name(try container.decode(String.self, forKey: .name))
        }

        var value: String {
            switch self { case .name(let value): value }
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decode(String.self, forKey: .id)
        let name = try container.decode(String.self, forKey: .name)
        let version = try? container.decode(String.self, forKey: .version)
        let logo = (try? container.decode(URL.self, forKey: .logo))
            ?? (try? container.decode(URL.self, forKey: .icon))

        let decodedResources = (try? container.decode(
            AppleManifestLossyList<ManifestResource>.self,
            forKey: .resources
        ))?.values.map(\.value) ?? []
        let decodedCatalogs = (try? container.decode(
            AppleManifestLossyList<AppleStremioCatalog>.self,
            forKey: .catalogs
        ))?.values ?? []
        self.init(
            id: id,
            name: name,
            version: version,
            logoURL: logo,
            resources: decodedResources,
            catalogs: decodedCatalogs
        )
    }

    private static func sanitizeLogoURL(_ value: URL?) -> URL? {
        guard let value,
              let components = URLComponents(url: value, resolvingAgainstBaseURL: false),
              let scheme = components.scheme?.lowercased(),
              // Add-on manifest logos are decorative icons; many community
              // add-ons serve them over http. ATS already permits arbitrary
              // loads, so https-only was needlessly nulling real logos and
              // leaving puzzle-piece placeholders in the sources list.
              scheme == "https" || scheme == "http",
              components.host?.isEmpty == false,
              components.user == nil,
              components.password == nil else { return nil }
        return components.url
    }

    private static func sanitizeResources(_ resources: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for value in resources {
            let cleaned = String(value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().prefix(64))
            guard !cleaned.isEmpty, seen.insert(cleaned).inserted else { continue }
            result.append(cleaned)
            if result.count == 32 { break }
        }
        return result
    }

    private static func sanitizeCatalogs(_ catalogs: [AppleStremioCatalog]) -> [AppleStremioCatalog] {
        var seen = Set<String>()
        var result: [AppleStremioCatalog] = []
        for value in catalogs {
            let catalog = AppleStremioCatalog(
                type: value.type,
                id: value.id,
                name: value.name,
                requiresInput: value.requiresInput,
                supportsSearch: value.supportsSearch
            )
            let key = "\(catalog.type):\(catalog.id)"
            guard ["movie", "series"].contains(catalog.type),
                  !catalog.id.isEmpty,
                  seen.insert(key).inserted else {
                continue
            }
            result.append(catalog)
            if result.count == maximumCatalogs { break }
        }
        return result
    }
}

private struct AppleManifestLossyList<Value: Decodable>: Decodable {
    let values: [Value]

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        var result: [Value] = []
        var inspected = 0
        while !container.isAtEnd, inspected < 64 {
            inspected += 1
            let entry = try container.superDecoder()
            if let value = try? Value(from: entry) { result.append(value) }
        }
        values = result
    }
}

enum AppleBoundedHTTPError: Swift.Error {
    case responseTooLarge
}

enum AppleBoundedHTTPDataLoader {
    static func load(
        _ request: URLRequest,
        maximumBytes: Int,
        session: URLSession = .shared
    ) async throws -> (Data, URLResponse) {
        let (bytes, response) = try await session.bytes(for: request)
        if response.expectedContentLength > Int64(maximumBytes) {
            throw AppleBoundedHTTPError.responseTooLarge
        }

        var data = Data()
        if response.expectedContentLength > 0 {
            data.reserveCapacity(min(Int(response.expectedContentLength), maximumBytes))
        }
        for try await byte in bytes {
            guard data.count < maximumBytes else { throw AppleBoundedHTTPError.responseTooLarge }
            data.append(byte)
        }
        return (data, response)
    }
}

public enum AppleManifestClientError: Swift.Error, Equatable, LocalizedError, Sendable {
    case nonHTTPResponse
    case insecureRedirect
    case requestFailed(Int)
    case responseTooLarge
    case invalidManifest

    public var errorDescription: String? {
        switch self {
        case .nonHTTPResponse: "The add-on returned an invalid response."
        case .insecureRedirect: "The add-on redirected to an insecure address."
        case .requestFailed(let status): "The manifest request failed with HTTP \(status)."
        case .responseTooLarge: "The manifest is too large."
        case .invalidManifest: "The response is not a valid Stremio manifest."
        }
    }
}

public struct AppleManifestClient: Sendable {
    public typealias Loader = @Sendable (URL) async throws -> (Data, URLResponse)
    public typealias Sleeper = @Sendable (Duration) async throws -> Void

    private let loader: Loader
    private let sleeper: Sleeper

    public init(
        loader: @escaping Loader = AppleManifestClient.liveLoader,
        sleeper: @escaping Sleeper = AppleManifestClient.liveSleeper
    ) {
        self.loader = loader
        self.sleeper = sleeper
    }

    public func load(_ value: String) async throws -> (URL, AppleStremioManifest) {
        let url = try AppleManifestURLPolicy.normalize(value)
        var lastTransportError: (any Swift.Error)?

        for attempt in 0 ..< 4 {
            let data: Data
            let response: URLResponse
            do {
                (data, response) = try await loader(url)
            } catch is CancellationError {
                throw CancellationError()
            } catch AppleManifestClientError.responseTooLarge {
                throw AppleManifestClientError.responseTooLarge
            } catch {
                lastTransportError = error
                guard attempt < 3 else { throw error }
                try await sleeper(backoff(for: attempt))
                continue
            }

            guard let http = response as? HTTPURLResponse else { throw AppleManifestClientError.nonHTTPResponse }
            guard http.url?.scheme?.lowercased() == "https" else { throw AppleManifestClientError.insecureRedirect }
            if isRetryable(http.statusCode), attempt < 3 {
                try await sleeper(backoff(for: attempt))
                continue
            }
            guard (200 ... 299).contains(http.statusCode) else {
                throw AppleManifestClientError.requestFailed(http.statusCode)
            }
            return try decodedManifest(data, from: url)
        }

        if let lastTransportError { throw lastTransportError }
        throw AppleManifestClientError.invalidManifest
    }

    private func decodedManifest(_ data: Data, from url: URL) throws -> (URL, AppleStremioManifest) {
        guard data.count <= 2_000_000 else { throw AppleManifestClientError.responseTooLarge }
        guard let manifest = try? JSONDecoder().decode(AppleStremioManifest.self, from: data),
              !manifest.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !manifest.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AppleManifestClientError.invalidManifest
        }
        return (url, manifest)
    }

    private func isRetryable(_ status: Int) -> Bool {
        status == 408 || status == 429 || (500 ... 599).contains(status)
    }

    private func backoff(for attempt: Int) -> Duration {
        switch attempt {
        case 0: .milliseconds(250)
        case 1: .milliseconds(500)
        default: .seconds(1)
        }
    }

    public static func liveLoader(_ url: URL) async throws -> (Data, URLResponse) {
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("OpenStream/1.0 Apple", forHTTPHeaderField: "User-Agent")
        do {
            return try await AppleBoundedHTTPDataLoader.load(request, maximumBytes: 2_000_000)
        } catch AppleBoundedHTTPError.responseTooLarge {
            throw AppleManifestClientError.responseTooLarge
        }
    }

    public static func liveSleeper(_ duration: Duration) async throws {
        try await Task.sleep(for: duration)
    }
}

@MainActor
@Observable
public final class AppleSourceStore {
    public private(set) var sources: [AppleSource]

    private let defaults: UserDefaults
    private let storageKey: String

    public init(defaults: UserDefaults = .standard, storageKey: String = "openstream.sources.v1") {
        self.defaults = defaults
        self.storageKey = storageKey
        if let data = defaults.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([AppleSource].self, from: data) {
            sources = decoded.sorted { $0.addedAt < $1.addedAt }
        } else {
            sources = []
        }
    }

    @discardableResult
    public func addStremio(manifestURL: URL, name: String) throws -> AppleSource {
        let normalizedURL = try AppleManifestURLPolicy.normalize(manifestURL.absoluteString)
        let cleanName = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(100))
        let displayName = cleanName.isEmpty ? (normalizedURL.host ?? "Add-on") : cleanName

        if let index = sources.firstIndex(where: { $0.kind == .stremio && $0.url == normalizedURL }) {
            sources[index].name = displayName
            sources[index].isEnabled = true
            persist()
            return sources[index]
        }

        let source = AppleSource(kind: .stremio, name: displayName, url: normalizedURL)
        sources.append(source)
        persist()
        return source
    }

    @discardableResult
    public func addStremio(manifestURL: URL, manifest: AppleStremioManifest) throws -> AppleSource {
        let normalizedURL = try AppleManifestURLPolicy.normalize(manifestURL.absoluteString)
        let cleanID = String(manifest.id.trimmingCharacters(in: .whitespacesAndNewlines).prefix(200))
        let cleanName = String(manifest.name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(100))
        let cleanVersion = manifest.version?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nonEmptyAppleSourceString
            .map { String($0.prefix(40)) }
        let cleanManifest = AppleStremioManifest(
            id: cleanID,
            name: cleanName,
            version: cleanVersion,
            logoURL: manifest.logoURL,
            resources: manifest.resources,
            catalogs: manifest.catalogs
        )
        guard !cleanID.isEmpty, !cleanName.isEmpty else { throw AppleManifestClientError.invalidManifest }

        if let index = sources.firstIndex(where: { $0.kind == .stremio && $0.manifestID == cleanID }) {
            let existing = sources[index]
            sources[index] = AppleSource(
                id: existing.id,
                kind: .stremio,
                name: cleanName,
                url: normalizedURL,
                isEnabled: true,
                addedAt: existing.addedAt,
                manifestID: cleanID,
                version: cleanVersion,
                resources: cleanManifest.resources,
                catalogs: cleanManifest.catalogs,
                logoURL: cleanManifest.logoURL
            )
            persist()
            return sources[index]
        }

        let source = AppleSource(
            kind: .stremio,
            name: cleanName,
            url: normalizedURL,
            manifestID: cleanID,
            version: cleanVersion,
            resources: cleanManifest.resources,
            catalogs: cleanManifest.catalogs,
            logoURL: cleanManifest.logoURL
        )
        sources.append(source)
        persist()
        return source
    }

    @discardableResult
    public func addStremio(
        manifestValue: String,
        client: AppleManifestClient = AppleManifestClient()
    ) async throws -> AppleSource {
        let (url, manifest) = try await client.load(manifestValue)
        try Task.checkCancellation()
        return try addStremio(manifestURL: url, manifest: manifest)
    }

    public func setEnabled(_ enabled: Bool, id: AppleSource.ID) {
        guard let index = sources.firstIndex(where: { $0.id == id }) else { return }
        sources[index].isEnabled = enabled
        persist()
    }

    @discardableResult
    public func addIPTV(
        name: String,
        type: AppleIPTVSourceType,
        endpoint: String,
        username: String = "",
        password: String = ""
    ) throws -> AppleSource {
        let url = try AppleIPTVEndpointPolicy.normalize(endpoint)
        let cleanName = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(100))
        let displayName = cleanName.isEmpty ? "My TV" : cleanName
        let cleanUsername = String(username.trimmingCharacters(in: .whitespacesAndNewlines).prefix(512))
        let cleanPassword = String(password.prefix(512))
        if type == .xtream, cleanUsername.isEmpty || cleanPassword.isEmpty {
            throw AppleIPTVError.missingCredentials
        }

        if let index = sources.firstIndex(where: { $0.kind == .liveTV }) {
            let existing = sources[index]
            sources[index] = AppleSource(
                id: existing.id,
                kind: .liveTV,
                name: displayName,
                url: url,
                isEnabled: true,
                addedAt: existing.addedAt,
                iptvType: type,
                username: cleanUsername.isEmpty ? nil : cleanUsername,
                password: cleanPassword.isEmpty ? nil : cleanPassword
            )
            persist()
            return sources[index]
        }

        let source = AppleSource(
            kind: .liveTV,
            name: displayName,
            url: url,
            iptvType: type,
            username: cleanUsername.isEmpty ? nil : cleanUsername,
            password: cleanPassword.isEmpty ? nil : cleanPassword
        )
        sources.append(source)
        persist()
        return source
    }

    @discardableResult
    public func addLibraryFolder(name: String, url: URL, bookmarkData: Data?) throws -> AppleSource {
        guard url.isFileURL else { throw AppleLibrarySourceError.invalidFolder }
        let cleanName = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(100))
        let displayName = cleanName.isEmpty ? url.lastPathComponent : cleanName
        if let index = sources.firstIndex(where: { $0.kind == .library && $0.url == url }) {
            sources[index].name = displayName
            sources[index].isEnabled = true
            sources[index].bookmarkData = bookmarkData
            persist()
            return sources[index]
        }
        let source = AppleSource(
            kind: .library,
            name: displayName,
            url: url,
            bookmarkData: bookmarkData
        )
        sources.append(source)
        persist()
        return source
    }

    public func remove(id: AppleSource.ID) {
        sources.removeAll { $0.id == id }
        persist()
    }

    private func persist() {
        defaults.set(try? JSONEncoder().encode(sources), forKey: storageKey)
    }
}

private extension String {
    var nonEmptyAppleSourceString: String? { isEmpty ? nil : self }
}
