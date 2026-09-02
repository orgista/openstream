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

    private static func endpoint(source: AppleSource, mediaID: String) throws -> URL {
        let cleanID = mediaID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanID.isEmpty, cleanID.utf8.count <= 512,
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
        let suffix = "meta/series/\(encodedSegment(cleanID)).json"
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
