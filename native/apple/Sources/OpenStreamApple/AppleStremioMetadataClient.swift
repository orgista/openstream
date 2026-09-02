import Foundation

public struct AppleStremioEpisode: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let season: Int?
    public let episode: Int?

    public init(id: String, title: String, season: Int? = nil, episode: Int? = nil) {
        self.id = String(id.trimmingCharacters(in: .whitespacesAndNewlines).prefix(300))
        self.title = String(title.trimmingCharacters(in: .whitespacesAndNewlines).prefix(200))
        self.season = season
        self.episode = episode
    }

    public var displayTitle: String {
        let number: String? = if let season, let episode {
            "S\(season) E\(episode)"
        } else if let episode {
            "Episode \(episode)"
        } else {
            nil
        }
        if let number, !title.isEmpty { return "\(number) · \(title)" }
        return number ?? (title.isEmpty ? "Episode" : title)
    }
}

public struct AppleStremioMetadataClient: Sendable {
    public typealias Loader = @Sendable (URLRequest) async throws -> (Data, URLResponse)
    private let loader: Loader

    public init(loader: @escaping Loader = AppleStremioPlaybackClient.liveLoader) {
        self.loader = loader
    }

    public func episodes(source: AppleSource, mediaID: String) async throws -> [AppleStremioEpisode] {
        guard source.kind == .stremio, source.isEnabled else {
            throw AppleStremioPlaybackError.invalidSource
        }
        let endpoint = try Self.endpoint(source: source, mediaID: mediaID)
        var request = URLRequest(url: endpoint)
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("OpenStream/1.0 Apple", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await loader(request)
        guard data.count <= AppleStremioPlaybackClient.maximumResponseBytes else {
            throw AppleStremioPlaybackError.responseTooLarge
        }
        guard let http = response as? HTTPURLResponse else { throw AppleStremioPlaybackError.nonHTTPResponse }
        guard http.url?.scheme?.lowercased() == "https" else {
            throw AppleStremioPlaybackError.insecureRedirect
        }
        guard (200 ... 299).contains(http.statusCode) else {
            throw AppleStremioPlaybackError.requestFailed(http.statusCode)
        }
        guard let envelope = try? JSONDecoder().decode(Envelope.self, from: data) else {
            throw AppleStremioPlaybackError.invalidPayload
        }

        var seen = Set<String>()
        return envelope.meta.videos.compactMap { value in
            let id = value.id.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !id.isEmpty, seen.insert(id).inserted else { return nil }
            return AppleStremioEpisode(
                id: id,
                title: value.title ?? value.name ?? "",
                season: value.season?.boundedEpisodeNumber,
                episode: value.episode?.boundedEpisodeNumber
            )
        }
        .prefix(1_000)
        .map { $0 }
    }

    /// Catalog results and metadata are often supplied by different add-ons.
    /// Prefer the catalog source when it advertises `meta`, then fall back to
    /// every other enabled metadata provider until one returns episodes.
    public func episodes(
        sources: [AppleSource],
        preferredSourceID: AppleSource.ID? = nil,
        mediaID: String
    ) async throws -> [AppleStremioEpisode] {
        let eligible = sources.filter { source in
            source.kind == .stremio
                && source.isEnabled
                && source.resources.contains { $0.caseInsensitiveCompare("meta") == .orderedSame }
        }
        let candidates = eligible.filter { $0.id == preferredSourceID }
            + eligible.filter { $0.id != preferredSourceID }

        var lastError: (any Error)?
        for source in candidates {
            try Task.checkCancellation()
            do {
                let values = try await episodes(source: source, mediaID: mediaID)
                if !values.isEmpty { return values }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                lastError = error
            }
        }
        if let lastError { throw lastError }
        return []
    }

    /// Resolves a catalog item's canonical IMDB id (`tt…`) via a meta-capable
    /// add-on. Catalog add-ons like Rotten Tomatoes and Streaming Catalogs
    /// return items keyed by non-IMDB ids (tmdb/slug/prefixed), but stream
    /// add-ons like Torrentio only resolve IMDB ids — so the raw catalog id
    /// yields "no streams". This mirrors the Android client, which stores each
    /// item's id AS its resolved IMDB id. Returns nil when nothing maps.
    public func imdbIdentifier(
        sources: [AppleSource],
        preferredSourceID: AppleSource.ID? = nil,
        type: String,
        id: String
    ) async -> String? {
        // Already an IMDB id (movie `tt123`, or series episode `tt123:1:2`).
        if Self.isIMDBIdentifier(id) { return id }
        let eligible = sources.filter { source in
            source.kind == .stremio
                && source.isEnabled
                && source.resources.contains { $0.caseInsensitiveCompare("meta") == .orderedSame }
        }
        let candidates = eligible.filter { $0.id == preferredSourceID }
            + eligible.filter { $0.id != preferredSourceID }
        for source in candidates {
            if Task.isCancelled { return nil }
            if let resolved = try? await metaIMDBID(source: source, type: type, id: id) {
                return resolved
            }
        }
        return nil
    }

    /// True for `tt1234567` and series episode ids `tt1234567:1:2`.
    public static func isIMDBIdentifier(_ id: String) -> Bool {
        let head = id.split(separator: ":", maxSplits: 1).first.map(String.init) ?? id
        guard head.hasPrefix("tt"), head.count >= 7 else { return false }
        return head.dropFirst(2).allSatisfy(\.isNumber)
    }

    private func metaIMDBID(source: AppleSource, type: String, id: String) async throws -> String? {
        let endpoint = try Self.endpoint(source: source, type: type, mediaID: id)
        var request = URLRequest(url: endpoint)
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("OpenStream/1.0 Apple", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await loader(request)
        guard data.count <= AppleStremioPlaybackClient.maximumResponseBytes,
              let http = response as? HTTPURLResponse,
              http.url?.scheme?.lowercased() == "https",
              (200 ... 299).contains(http.statusCode),
              let envelope = try? JSONDecoder().decode(IMDBEnvelope.self, from: data) else {
            return nil
        }
        if let imdb = envelope.meta.imdbID?.trimmingCharacters(in: .whitespacesAndNewlines),
           Self.isIMDBIdentifier(imdb) {
            return imdb
        }
        let metaID = envelope.meta.id?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return Self.isIMDBIdentifier(metaID) ? metaID : nil
    }

    private static func endpoint(source: AppleSource, type: String = "series", mediaID: String) throws -> URL {
        let cleanID = mediaID.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanType = type.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !cleanID.isEmpty, cleanID.utf8.count <= 512,
              !cleanType.isEmpty, cleanType.utf8.count <= 64,
              var components = URLComponents(url: source.transportURL, resolvingAgainstBaseURL: false),
              components.scheme?.lowercased() == "https",
              components.host?.isEmpty == false,
              components.user == nil,
              components.password == nil,
              components.query == nil,
              components.fragment == nil else {
            throw AppleStremioPlaybackError.invalidMediaIdentity
        }
        let basePath = components.percentEncodedPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let suffix = "meta/\(encodedSegment(cleanType))/\(encodedSegment(cleanID)).json"
        components.percentEncodedPath = basePath.isEmpty ? "/\(suffix)" : "/\(basePath)/\(suffix)"
        guard let url = components.url else { throw AppleStremioPlaybackError.invalidSource }
        return url
    }

    private static func encodedSegment(_ value: String) -> String {
        value.utf8.map { byte in
            switch byte {
            case 48 ... 57, 65 ... 90, 97 ... 122, 45, 95, 126:
                String(UnicodeScalar(byte))
            default:
                String(format: "%%%02X", byte)
            }
        }.joined()
    }

    private struct Envelope: Decodable {
        let meta: Metadata
    }

    private struct IMDBEnvelope: Decodable {
        let meta: IMDBMeta
    }

    private struct IMDBMeta: Decodable {
        let id: String?
        let imdbID: String?
        private enum CodingKeys: String, CodingKey { case id, imdbID = "imdb_id" }
    }

    private struct Metadata: Decodable {
        let videos: [Video]

        private enum CodingKeys: String, CodingKey { case videos }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            videos = (try? container.decode([Video].self, forKey: .videos)) ?? []
        }
    }

    private struct Video: Decodable {
        let id: String
        let title: String?
        let name: String?
        let season: FlexibleInt?
        let episode: FlexibleInt?
    }

    private enum FlexibleInt: Decodable {
        case value(Int)

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let value = try? container.decode(Int.self) {
                self = .value(value)
            } else if let value = try? container.decode(String.self), let number = Int(value) {
                self = .value(number)
            } else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Expected an integer")
            }
        }

        var boundedEpisodeNumber: Int? {
            switch self {
            case .value(let value): (0 ... 100_000).contains(value) ? value : nil
            }
        }
    }
}
