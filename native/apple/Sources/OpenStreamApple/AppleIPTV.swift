import Foundation

public struct AppleIPTVChannel: Identifiable, Equatable, Sendable {
    public let id: String
    public let sourceID: AppleSource.ID
    public let name: String
    public let group: String
    public let logoURL: URL?
    public let streamURL: URL
    public let userAgent: String?
    public let referer: String?

    public init(
        id: String,
        sourceID: AppleSource.ID,
        name: String,
        group: String = "",
        logoURL: URL? = nil,
        streamURL: URL,
        userAgent: String? = nil,
        referer: String? = nil
    ) {
        self.id = id
        self.sourceID = sourceID
        self.name = name
        self.group = group
        self.logoURL = logoURL
        self.streamURL = streamURL
        self.userAgent = userAgent
        self.referer = referer
    }

    /// HTTP headers to attach to the media request, from the playlist's
    /// `#EXTVLCOPT` User-Agent/Referer. Empty when the playlist declared none.
    public var playbackHeaders: [String: String] {
        var headers: [String: String] = [:]
        if let userAgent, !userAgent.isEmpty { headers["User-Agent"] = userAgent }
        if let referer, !referer.isEmpty { headers["Referer"] = referer }
        return headers
    }
}

public enum AppleIPTVError: Error, Equatable, LocalizedError, Sendable {
    case invalidEndpoint
    case invalidSource
    case missingCredentials
    case nonHTTPResponse
    case requestFailed(Int)
    case responseTooLarge
    case invalidPlaylist
    case noChannels

    public var errorDescription: String? {
        switch self {
        case .invalidEndpoint: "Enter an HTTP or HTTPS IPTV address."
        case .invalidSource: "This Live TV source is invalid."
        case .missingCredentials: "Username and password are required."
        case .nonHTTPResponse: "The IPTV server returned an invalid response."
        case .requestFailed(let status): "The IPTV request failed with HTTP \(status)."
        case .responseTooLarge: "The IPTV playlist is too large."
        case .invalidPlaylist: "The server did not return an M3U playlist."
        case .noChannels: "No playable channels were found."
        }
    }
}

public enum AppleIPTVEndpointPolicy {
    public static func normalize(_ value: String) throws -> URL {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              trimmed.utf8.count <= 8_192,
              var components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = components.host, !host.isEmpty,
              components.user == nil,
              components.password == nil,
              components.fragment == nil else {
            throw AppleIPTVError.invalidEndpoint
        }
        components.scheme = scheme
        components.host = host.lowercased()
        guard let url = components.url else { throw AppleIPTVError.invalidEndpoint }
        return url
    }

    public static func isPlayable(_ url: URL) -> Bool {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              components.host?.isEmpty == false,
              components.user == nil,
              components.password == nil else { return false }
        return true
    }
}

public struct AppleIPTVClient: Sendable {
    public typealias Loader = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    public static let maximumResponseBytes = 12_000_000
    public static let maximumChannels = 10_000

    private let loader: Loader

    public init(loader: @escaping Loader = AppleIPTVClient.liveLoader) {
        self.loader = loader
    }

    public func channels(source: AppleSource) async throws -> [AppleIPTVChannel] {
        guard source.kind == .liveTV, source.isEnabled, let type = source.iptvType else {
            throw AppleIPTVError.invalidSource
        }
        let endpoint: URL
        switch type {
        case .m3u:
            endpoint = try AppleIPTVEndpointPolicy.normalize(source.url.absoluteString)
        case .xtream:
            guard let username = source.username, !username.isEmpty,
                  let password = source.password, !password.isEmpty else {
                throw AppleIPTVError.missingCredentials
            }
            endpoint = try Self.xtreamPlaylistURL(
                baseURL: source.url,
                username: username,
                password: password
            )
        }

        var request = URLRequest(url: endpoint)
        request.timeoutInterval = 20
        request.setValue(
            "application/vnd.apple.mpegurl, application/x-mpegURL, audio/mpegurl, text/plain, */*",
            forHTTPHeaderField: "Accept"
        )
        request.setValue("OpenStream/1.0 Apple", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await loader(request)
        guard data.count <= Self.maximumResponseBytes,
              response.expectedContentLength <= Int64(Self.maximumResponseBytes) else {
            throw AppleIPTVError.responseTooLarge
        }
        guard let http = response as? HTTPURLResponse else { throw AppleIPTVError.nonHTTPResponse }
        guard (200 ... 299).contains(http.statusCode) else { throw AppleIPTVError.requestFailed(http.statusCode) }
        let finalURL = http.url ?? endpoint
        guard AppleIPTVEndpointPolicy.isPlayable(finalURL) else { throw AppleIPTVError.invalidEndpoint }
        let values = try Self.parseM3U(data, sourceID: source.id, baseURL: finalURL)
        guard !values.isEmpty else { throw AppleIPTVError.noChannels }
        return values
    }

    public static func parseM3U(
        _ data: Data,
        sourceID: AppleSource.ID,
        baseURL: URL
    ) throws -> [AppleIPTVChannel] {
        guard data.count <= maximumResponseBytes,
              let text = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .isoLatin1) else {
            throw data.count > maximumResponseBytes ? AppleIPTVError.responseTooLarge : AppleIPTVError.invalidPlaylist
        }
        let lines = text.components(separatedBy: .newlines)
        guard lines.contains(where: { $0.trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased().hasPrefix("#EXTM3U") }) else {
            throw AppleIPTVError.invalidPlaylist
        }

        var pending: PendingChannel?
        var userAgent: String?
        var referer: String?
        var seen = Set<String>()
        var channels: [AppleIPTVChannel] = []

        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }
            if line.uppercased().hasPrefix("#EXTINF:") {
                pending = PendingChannel(extinf: line)
                userAgent = nil
                referer = nil
                continue
            }
            if line.lowercased().hasPrefix("#extvlcopt:http-user-agent=") {
                userAgent = cleanHeader(String(line.dropFirst("#extvlcopt:http-user-agent=".count)))
                continue
            }
            if line.lowercased().hasPrefix("#extvlcopt:http-referrer=") ||
                line.lowercased().hasPrefix("#extvlcopt:http-referer=") {
                let separator = line.firstIndex(of: "=")
                referer = separator.flatMap { cleanHeader(String(line[line.index(after: $0)...])) }
                continue
            }
            guard !line.hasPrefix("#"), let details = pending else { continue }
            pending = nil
            guard let url = URL(string: line, relativeTo: baseURL)?.absoluteURL,
                  AppleIPTVEndpointPolicy.isPlayable(url),
                  seen.insert(url.absoluteString).inserted else { continue }

            let cleanName = details.name.isEmpty ? "Channel \(channels.count + 1)" : details.name
            let stableID = details.attributes["tvg-id"]?.nonEmptyIPTVString
                ?? ApplePlaybackIdentity.digest(for: url.absoluteString)
            channels.append(AppleIPTVChannel(
                id: "\(sourceID.uuidString):\(stableID)",
                sourceID: sourceID,
                name: String(cleanName.prefix(160)),
                group: String((details.attributes["group-title"] ?? "").prefix(120)),
                logoURL: safeArtworkURL(details.attributes["tvg-logo"]),
                streamURL: url,
                userAgent: userAgent,
                referer: referer
            ))
            if channels.count == maximumChannels { break }
        }
        return channels
    }

    public static func xtreamPlaylistURL(baseURL: URL, username: String, password: String) throws -> URL {
        let normalized = try AppleIPTVEndpointPolicy.normalize(baseURL.absoluteString)
        guard var components = URLComponents(url: normalized, resolvingAgainstBaseURL: false) else {
            throw AppleIPTVError.invalidEndpoint
        }
        let basePath = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        components.path = basePath.isEmpty ? "/get.php" : "/\(basePath)/get.php"
        components.queryItems = [
            URLQueryItem(name: "username", value: username),
            URLQueryItem(name: "password", value: password),
            URLQueryItem(name: "type", value: "m3u_plus"),
            URLQueryItem(name: "output", value: "m3u8"),
        ]
        guard let url = components.url else { throw AppleIPTVError.invalidEndpoint }
        return url
    }

    public static func liveLoader(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await AppleBoundedHTTPDataLoader.load(
                request,
                maximumBytes: maximumResponseBytes
            )
        } catch AppleBoundedHTTPError.responseTooLarge {
            throw AppleIPTVError.responseTooLarge
        }
    }

    private struct PendingChannel {
        let name: String
        let attributes: [String: String]

        init(extinf: String) {
            let comma = extinf.lastIndex(of: ",")
            name = comma.map { String(extinf[extinf.index(after: $0)...])
                .trimmingCharacters(in: .whitespacesAndNewlines) } ?? ""
            let metadata = comma.map { String(extinf[..<$0]) } ?? extinf
            attributes = parseAttributes(metadata)
        }
    }

    private static func parseAttributes(_ value: String) -> [String: String] {
        let pattern = #"([A-Za-z0-9_-]+)\s*=\s*\"([^\"]*)\""#
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return [:] }
        let range = NSRange(value.startIndex..., in: value)
        return expression.matches(in: value, range: range).reduce(into: [:]) { result, match in
            guard let keyRange = Range(match.range(at: 1), in: value),
                  let valueRange = Range(match.range(at: 2), in: value) else { return }
            result[String(value[keyRange]).lowercased()] = String(value[valueRange])
        }
    }

    private static func safeArtworkURL(_ value: String?) -> URL? {
        guard let value, let url = URL(string: value),
              let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http",
              url.host?.isEmpty == false,
              url.user == nil,
              url.password == nil else { return nil }
        return url
    }

    private static func cleanHeader(_ value: String) -> String? {
        let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty,
              clean.utf8.count <= 512,
              !clean.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else { return nil }
        return clean
    }
}

private extension String {
    var nonEmptyIPTVString: String? { isEmpty ? nil : self }
}
