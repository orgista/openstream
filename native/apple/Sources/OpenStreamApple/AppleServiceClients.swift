import Foundation

public enum AppleArrKind: String, CaseIterable, Sendable {
    case radarr
    case sonarr

    public var displayName: String {
        switch self {
        case .radarr: "Radarr"
        case .sonarr: "Sonarr"
        }
    }
}

public enum AppleArrEndpointPolicy {
    public static func normalize(_ value: String) throws -> URL {
        guard value.utf8.count <= 2_048 else {
            throw AppleArrClientError.invalidEndpoint
        }
        do {
            return try AppleGatewayEndpointPolicy.normalize(value)
        } catch {
            throw AppleArrClientError.invalidEndpoint
        }
    }

    public static func isAllowed(_ value: String) -> Bool {
        (try? normalize(value)) != nil
    }
}

public struct AppleArrStatus: Equatable, Sendable {
    public let appName: String
    public let version: String
    public let instanceName: String

    public init(appName: String, version: String, instanceName: String) {
        self.appName = appName
        self.version = version
        self.instanceName = instanceName
    }
}

public enum AppleArrClientError: Swift.Error, Equatable, LocalizedError, Sendable {
    case invalidEndpoint
    case invalidAPIKey
    case nonHTTPResponse
    case redirected
    case responseTooLarge
    case requestFailed(Int)
    case invalidResponse

    public var errorDescription: String? {
        switch self {
        case .invalidEndpoint:
            "Use HTTPS, or HTTP with a private local IP address."
        case .invalidAPIKey:
            "Enter a valid API key."
        case .nonHTTPResponse:
            "The server returned an invalid response."
        case .redirected:
            "The server redirected the connection."
        case .responseTooLarge:
            "The server response is too large."
        case .requestFailed(let status):
            "Connection failed with HTTP \(status)."
        case .invalidResponse:
            "The server returned invalid status data."
        }
    }
}

public struct AppleArrClient: Sendable {
    public typealias Loader = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    public static let maximumResponseBytes = 512 * 1_024

    private let loader: Loader

    public init(loader: @escaping Loader = AppleArrClient.liveLoader) {
        self.loader = loader
    }

    public static func isValidAPIKey(_ value: String) -> Bool {
        let key = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return (1 ... 4_096).contains(key.utf8.count) &&
            key.unicodeScalars.allSatisfy { scalar in
                scalar.value >= 0x20 && scalar.value != 0x7F
            }
    }

    public func test(kind: AppleArrKind, baseURL: String, apiKey: String) async throws -> AppleArrStatus {
        let base = try AppleArrEndpointPolicy.normalize(baseURL)
        let key = try normalizedAPIKey(apiKey)
        let endpoint = base.appending(path: "api/v3/system/status")

        var request = URLRequest(url: endpoint)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(key, forHTTPHeaderField: "X-Api-Key")
        request.setValue("OpenStream/1.0 Apple", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await loader(request)
        guard data.count <= Self.maximumResponseBytes else {
            throw AppleArrClientError.responseTooLarge
        }
        guard let http = response as? HTTPURLResponse else {
            throw AppleArrClientError.nonHTTPResponse
        }
        if (300 ... 399).contains(http.statusCode) || http.url != endpoint {
            throw AppleArrClientError.redirected
        }
        if http.expectedContentLength > Int64(Self.maximumResponseBytes) {
            throw AppleArrClientError.responseTooLarge
        }
        guard (200 ... 299).contains(http.statusCode) else {
            throw AppleArrClientError.requestFailed(http.statusCode)
        }

        struct Payload: Decodable {
            let appName: String?
            let version: String?
            let instanceName: String?
        }

        guard let payload = try? JSONDecoder().decode(Payload.self, from: data) else {
            throw AppleArrClientError.invalidResponse
        }
        return AppleArrStatus(
            appName: bounded(payload.appName, limit: 80, fallback: kind.displayName),
            version: bounded(payload.version, limit: 40),
            instanceName: bounded(payload.instanceName, limit: 80)
        )
    }

    public static func liveLoader(_ request: URLRequest) async throws -> (Data, URLResponse) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.waitsForConnectivity = false
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 20

        let session = URLSession(
            configuration: configuration,
            delegate: AppleServiceRedirectRejectingDelegate(),
            delegateQueue: nil
        )
        defer { session.invalidateAndCancel() }

        let (bytes, response) = try await session.bytes(for: request)
        if response.expectedContentLength > Int64(maximumResponseBytes) {
            throw AppleArrClientError.responseTooLarge
        }

        var data = Data()
        if response.expectedContentLength > 0 {
            data.reserveCapacity(min(Int(response.expectedContentLength), maximumResponseBytes))
        }
        for try await byte in bytes {
            guard data.count < maximumResponseBytes else {
                throw AppleArrClientError.responseTooLarge
            }
            data.append(byte)
        }
        return (data, response)
    }

    private func normalizedAPIKey(_ value: String) throws -> String {
        let key = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.isValidAPIKey(key) else {
            throw AppleArrClientError.invalidAPIKey
        }
        return key
    }

    private func bounded(_ value: String?, limit: Int, fallback: String = "") -> String {
        let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !normalized.isEmpty else { return fallback }
        return String(normalized.prefix(limit))
    }
}

private final class AppleServiceRedirectRejectingDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}
