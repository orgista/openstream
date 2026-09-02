import Darwin
import Foundation
import Network

public enum AppleWebManagementServerError: Error, Equatable, LocalizedError, Sendable {
    case localNetworkUnavailable
    case invalidConfiguration
    case listenerFailed(String)
    case invalidListenerPort
    case invalidSessionURL

    public var errorDescription: String? {
        switch self {
        case .localNetworkUnavailable:
            "Connect this device to a local network first."
        case .invalidConfiguration:
            "The Web Management session configuration is invalid."
        case .listenerFailed(let detail):
            detail.isEmpty ? "Web Management could not start." : "Web Management could not start: \(detail)"
        case .invalidListenerPort:
            "Web Management could not reserve a local port."
        case .invalidSessionURL:
            "Web Management could not create its local URL."
        }
    }
}

public enum AppleWebManagementServerStopReason: Equatable, Sendable {
    case stopped
    case expired
    case completed
    case failed(String)
}

@MainActor
public final class AppleWebManagementServer {
    public nonisolated static let defaultPort: UInt16 = 11_470
    public nonisolated static let defaultSessionDuration: TimeInterval = 10 * 60
    public nonisolated static let bonjourServiceType = "_openstream._tcp"

    public struct Configuration: Sendable {
        public let preferredPort: UInt16
        public let sessionDuration: TimeInterval
        public let advertisesBonjour: Bool
        fileprivate let hostProvider: @Sendable () -> String?

        public init(
            preferredPort: UInt16 = AppleWebManagementServer.defaultPort,
            sessionDuration: TimeInterval = AppleWebManagementServer.defaultSessionDuration,
            advertisesBonjour: Bool = true
        ) {
            self.preferredPort = preferredPort
            self.sessionDuration = sessionDuration
            self.advertisesBonjour = advertisesBonjour
            hostProvider = { AppleWebManagementNetwork.localIPv4Address() }
        }

        init(
            preferredPort: UInt16,
            sessionDuration: TimeInterval,
            advertisesBonjour: Bool,
            advertisedHost: String
        ) {
            self.preferredPort = preferredPort
            self.sessionDuration = sessionDuration
            self.advertisesBonjour = advertisesBonjour
            hostProvider = { advertisedHost }
        }
    }

    public private(set) var session: AppleWebManagementSession?
    public var onStop: (@MainActor @Sendable (AppleWebManagementServerStopReason) -> Void)?

    private let configuration: Configuration
    private let manifestClient: AppleManifestClient
    private let networkQueue = DispatchQueue(label: "com.orgista.openstream.web-management", qos: .userInitiated)

    private var listener: NWListener?
    private var bonjourService: NetService?
    private var sourceStore: AppleSourceStore?
    private var expiryTask: Task<Void, Never>?
    private var connectionTasks: [ObjectIdentifier: Task<Void, Never>] = [:]
    private var connections: [ObjectIdentifier: NWConnection] = [:]
    private var generation = UUID()
    private var isCompleting = false

    public init(
        configuration: Configuration = Configuration(),
        manifestClient: AppleManifestClient = AppleManifestClient()
    ) {
        self.configuration = configuration
        self.manifestClient = manifestClient
    }

    @discardableResult
    public func start(sourceStore: AppleSourceStore) async throws -> AppleWebManagementSession {
        tearDown(reason: nil)

        guard configuration.sessionDuration > 0, configuration.sessionDuration.isFinite else {
            throw AppleWebManagementServerError.invalidConfiguration
        }
        guard let host = configuration.hostProvider(), AppleWebManagementProtocol.isAllowedClient(host: host) else {
            throw AppleWebManagementServerError.localNetworkUnavailable
        }

        self.sourceStore = sourceStore
        generation = UUID()

        let activeListener: NWListener
        do {
            activeListener = try await startReadyListener(port: configuration.preferredPort)
        } catch {
            guard configuration.preferredPort != 0 else {
                self.sourceStore = nil
                throw AppleWebManagementServerError.listenerFailed(error.localizedDescription)
            }
            do {
                activeListener = try await startReadyListener(port: 0)
            } catch {
                self.sourceStore = nil
                throw AppleWebManagementServerError.listenerFailed(error.localizedDescription)
            }
        }

        guard let port = activeListener.port?.rawValue else {
            activeListener.cancel()
            self.sourceStore = nil
            throw AppleWebManagementServerError.invalidListenerPort
        }

        let token = AppleWebManagementProtocol.makeToken()
        let expiresAt = Date().addingTimeInterval(configuration.sessionDuration)
        guard let tokenURL = Self.makeURL(host: host, port: port, path: "/openstream", token: token),
              let friendlyURL = Self.makeURL(host: host, port: port, path: "/", token: nil) else {
            activeListener.cancel()
            self.sourceStore = nil
            throw AppleWebManagementServerError.invalidSessionURL
        }

        let activeSession = AppleWebManagementSession(
            url: tokenURL,
            friendlyURL: friendlyURL,
            expiresAt: expiresAt,
            token: token
        )
        listener = activeListener
        session = activeSession
        publishBonjourIfRequested(port: port)
        installRuntimeStateHandler(for: activeListener)
        scheduleExpiry(after: configuration.sessionDuration)
        return activeSession
    }

    public func stop() {
        tearDown(reason: .stopped)
    }

    public func dispose() {
        stop()
    }

    private func startReadyListener(port: UInt16) async throws -> NWListener {
        let tcp = NWProtocolTCP.Options()
        tcp.noDelay = true
        tcp.connectionTimeout = 8
        let parameters = NWParameters(tls: nil, tcp: tcp)
        parameters.includePeerToPeer = true

        let endpointPort = port == 0 ? NWEndpoint.Port.any : NWEndpoint.Port(rawValue: port)!
        let candidate = try NWListener(using: parameters, on: endpointPort)
        candidate.newConnectionLimit = 8
        candidate.newConnectionHandler = { [weak self] connection in
            Task { @MainActor [weak self] in
                self?.accept(connection)
            }
        }
        listener = candidate
        do {
            try await waitUntilReady(candidate)
            return candidate
        } catch {
            if listener === candidate { listener = nil }
            candidate.stateUpdateHandler = nil
            candidate.cancel()
            throw error
        }
    }

    private func waitUntilReady(_ candidate: NWListener) async throws {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                let gate = AppleWebManagementListenerStartupGate(continuation: continuation)
                candidate.stateUpdateHandler = { state in
                    gate.receive(state)
                }
                candidate.start(queue: networkQueue)
            }
        } onCancel: {
            candidate.cancel()
        }
    }

    private func installRuntimeStateHandler(for activeListener: NWListener) {
        activeListener.stateUpdateHandler = { [weak self, weak activeListener] state in
            guard case .failed(let error) = state else { return }
            Task { @MainActor [weak self, weak activeListener] in
                guard let self, let activeListener, self.listener === activeListener else { return }
                self.tearDown(reason: .failed(error.debugDescription))
            }
        }
    }

    private func scheduleExpiry(after duration: TimeInterval) {
        expiryTask?.cancel()
        let nanoseconds = UInt64(min(duration * 1_000_000_000, Double(UInt64.max)))
        expiryTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: nanoseconds)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            self?.tearDown(reason: .expired)
        }
    }

    /// Bonjour is deliberately independent of listener readiness. Numeric
    /// LAN access and the QR code remain usable when service registration is
    /// denied or unavailable on the current network.
    private func publishBonjourIfRequested(port: UInt16) {
        bonjourService?.stop()
        bonjourService = nil
        guard configuration.advertisesBonjour else { return }

        let service = NetService(
            domain: "local.",
            type: Self.bonjourServiceType + ".",
            name: "OpenStream",
            port: Int32(port)
        )
        service.includesPeerToPeer = true
        bonjourService = service
        service.publish()
    }

    private func accept(_ connection: NWConnection) {
        guard listener != nil, session != nil else {
            connection.cancel()
            return
        }

        let id = ObjectIdentifier(connection)
        let acceptedGeneration = generation
        connections[id] = connection
        let task = Task { @MainActor [weak self] in
            guard let self else {
                connection.cancel()
                return
            }
            await self.serve(connection, id: id, generation: acceptedGeneration)
        }
        connectionTasks[id] = task
    }

    private func serve(_ connection: NWConnection, id: ObjectIdentifier, generation acceptedGeneration: UUID) async {
        let timeout = Task { @MainActor in
            do {
                try await Task.sleep(nanoseconds: 8_000_000_000)
            } catch {
                return
            }
            if !Task.isCancelled { connection.cancel() }
        }
        defer {
            timeout.cancel()
            connection.cancel()
            connections.removeValue(forKey: id)
            connectionTasks.removeValue(forKey: id)
        }

        connection.start(queue: networkQueue)

        guard let remoteHost = Self.host(from: connection.endpoint),
              AppleWebManagementProtocol.isAllowedClient(host: remoteHost) else {
            timeout.cancel()
            await send(.plain(403, "Forbidden", "This page is available only on the local network."), to: connection)
            return
        }

        do {
            let request = try await AppleWebManagementHTTPReader.read(from: connection)
            timeout.cancel()
            guard generation == acceptedGeneration, let activeSession = session else { return }
            let result = await response(for: request, session: activeSession)
            await send(result.response, to: connection)
            if result.stopAfterSending, generation == acceptedGeneration {
                tearDown(reason: .completed)
            }
        } catch AppleWebManagementHTTPReadError.tooLarge {
            timeout.cancel()
            await send(.plain(413, "Payload Too Large", "The request is too large."), to: connection)
        } catch AppleWebManagementHTTPReadError.malformed {
            timeout.cancel()
            await send(.plain(400, "Bad Request", "Malformed request."), to: connection)
        } catch {
            // A closed or timed-out local connection needs no response.
        }
    }

    private func response(
        for request: AppleWebManagementHTTPRequest,
        session activeSession: AppleWebManagementSession
    ) async -> (response: AppleWebManagementHTTPResponse, stopAfterSending: Bool) {
        guard request.path == "/" || request.path == "/openstream" else {
            return (.plain(404, "Not Found", "Not found."), false)
        }

        if !AppleWebManagementProtocol.isValidRequestSource(
            origin: request.headers["origin"],
            referer: request.headers["referer"],
            session: activeSession
        ) {
            return (.plain(403, "Forbidden", "Cross-origin request rejected."), false)
        }

        switch request.method {
        case "GET":
            let maxAge = max(1, Int(activeSession.expiresAt.timeIntervalSinceNow.rounded(.down)))
            let cookie = "openstream_token=\(activeSession.token); Max-Age=\(maxAge); SameSite=Strict; HttpOnly; Path=/"
            return (
                .html(200, "OK", AppleWebManagementPage.setup(token: activeSession.token), headers: [
                    "Set-Cookie": cookie,
                ]),
                false
            )

        case "POST":
            guard !isCompleting else {
                return (.plain(403, "Forbidden", "This session is already adding a source."), false)
            }
            let form = AppleWebManagementProtocol.parseForm(request.body)
            guard AppleWebManagementProtocol.hasValidToken(
                form: form,
                headers: request.headers,
                query: request.query,
                session: activeSession
            ) else {
                return (.plain(403, "Forbidden", "Invalid or missing session token."), false)
            }

            let manifest = form["manifest"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            isCompleting = true
            do {
                guard let sourceStore else {
                    isCompleting = false
                    return (.plain(400, "Bad Request", "The session is no longer active."), false)
                }
                let source = try await sourceStore.addStremio(manifestValue: manifest, client: manifestClient)
                guard !Task.isCancelled, self.session?.token == activeSession.token else {
                    isCompleting = false
                    return (.plain(400, "Bad Request", "The session is no longer active."), false)
                }
                return (.html(200, "OK", AppleWebManagementPage.success(sourceName: source.name)), true)
            } catch {
                isCompleting = false
                let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                return (
                    .html(
                        400,
                        "Bad Request",
                        AppleWebManagementPage.setup(token: activeSession.token, manifest: manifest, error: message)
                    ),
                    false
                )
            }

        default:
            return (
                .plain(405, "Method Not Allowed", "Use GET or POST.", headers: ["Allow": "GET, POST"]),
                false
            )
        }
    }

    private func send(_ response: AppleWebManagementHTTPResponse, to connection: NWConnection) async {
        let data = response.serialized()
        await withCheckedContinuation { continuation in
            connection.send(content: data, completion: .contentProcessed { _ in
                continuation.resume()
            })
        }
    }

    private func tearDown(reason: AppleWebManagementServerStopReason?) {
        let wasActive = listener != nil || session != nil
        generation = UUID()
        isCompleting = false

        expiryTask?.cancel()
        expiryTask = nil

        let activeListener = listener
        listener = nil
        activeListener?.stateUpdateHandler = nil
        activeListener?.cancel()

        bonjourService?.stop()
        bonjourService = nil

        let tasks = Array(connectionTasks.values)
        connectionTasks.removeAll()
        tasks.forEach { $0.cancel() }

        let activeConnections = Array(connections.values)
        connections.removeAll()
        activeConnections.forEach { $0.cancel() }

        sourceStore = nil
        session = nil
        if wasActive, let reason { onStop?(reason) }
    }

    private static func makeURL(host: String, port: UInt16, path: String, token: String?) -> URL? {
        var components = URLComponents()
        components.scheme = "http"
        components.host = host
        components.port = Int(port)
        components.path = path
        if let token {
            components.queryItems = [URLQueryItem(name: "token", value: token)]
        }
        return components.url
    }

    private static func host(from endpoint: NWEndpoint) -> String? {
        guard case .hostPort(let host, _) = endpoint else { return nil }
        switch host {
        case .name(let name, _):
            return name
        case .ipv4(let address):
            return address.debugDescription
        case .ipv6(let address):
            return address.debugDescription
        @unknown default:
            return nil
        }
    }
}

private final class AppleWebManagementListenerStartupGate: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, any Error>?

    init(continuation: CheckedContinuation<Void, any Error>) {
        self.continuation = continuation
    }

    func receive(_ state: NWListener.State) {
        let result: Result<Void, any Error>?
        switch state {
        case .ready:
            result = .success(())
        case .failed(let error):
            result = .failure(error)
        case .cancelled:
            result = .failure(CancellationError())
        case .setup, .waiting:
            result = nil
        @unknown default:
            result = .failure(AppleWebManagementServerError.listenerFailed("Unknown listener state."))
        }
        guard let result else { return }

        lock.lock()
        let continuation = continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(with: result)
    }
}

private enum AppleWebManagementNetwork {
    private struct Candidate {
        let address: String
        let interface: String
    }

    static func localIPv4Address() -> String? {
        var firstAddress: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&firstAddress) == 0, let firstAddress else { return nil }
        defer { freeifaddrs(firstAddress) }

        var candidates: [Candidate] = []
        var cursor: UnsafeMutablePointer<ifaddrs>? = firstAddress
        while let interface = cursor?.pointee {
            defer { cursor = interface.ifa_next }
            guard let socketAddress = interface.ifa_addr,
                  socketAddress.pointee.sa_family == UInt8(AF_INET) else { continue }

            let flags = Int32(interface.ifa_flags)
            guard flags & IFF_UP != 0, flags & IFF_LOOPBACK == 0 else { continue }

            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let status = getnameinfo(
                socketAddress,
                socklen_t(socketAddress.pointee.sa_len),
                &host,
                socklen_t(host.count),
                nil,
                0,
                NI_NUMERICHOST
            )
            guard status == 0 else { continue }
            let address = host.withUnsafeBufferPointer { buffer in
                String(
                    decodingCString: UnsafeRawPointer(buffer.baseAddress!).assumingMemoryBound(to: UInt8.self),
                    as: UTF8.self
                )
            }
            guard AppleWebManagementProtocol.isAllowedClient(host: address), !address.hasPrefix("127.") else {
                continue
            }
            let interfaceName = String(
                decodingCString: UnsafeRawPointer(interface.ifa_name).assumingMemoryBound(to: UInt8.self),
                as: UTF8.self
            )
            // `en0` is Wi-Fi on Apple mobile/TV platforms; other `en*`
            // interfaces cover wired Ethernet. Carrier, VPN, bridge, and
            // peer-to-peer addresses are not usable setup destinations.
            guard interfaceName.hasPrefix("en") else { continue }
            candidates.append(Candidate(address: address, interface: interfaceName))
        }

        return candidates.sorted { rank($0) < rank($1) }.first?.address
    }

    private static func rank(_ candidate: Candidate) -> Int {
        let interfaceRank: Int
        if candidate.interface == "en0" { interfaceRank = 0 }
        else { interfaceRank = 1 }
        let addressRank = candidate.address.hasPrefix("169.254.") ? 10 : 0
        return interfaceRank + addressRank
    }
}

enum AppleWebManagementHTTPReadError: Error {
    case malformed
    case tooLarge
}

struct AppleWebManagementHTTPRequest: Sendable {
    let method: String
    let target: String
    let path: String
    let query: [String: String]
    let headers: [String: String]
    let body: String
}

private enum AppleWebManagementHTTPReader {
    private static let headerTerminator = Data([13, 10, 13, 10])
    private static let maxRequestLineBytes = 2_048
    private static let maxHeaderLineBytes = 4_096
    private static let maxHeaderCount = 40
    private static let maxHeaderBytes = 16_384
    private static let maxBodyBytes = 8_192

    static func read(from connection: NWConnection) async throws -> AppleWebManagementHTTPRequest {
        var buffer = Data()
        var streamIsComplete = false

        while true {
            if let terminator = buffer.range(of: headerTerminator) {
                let headerData = buffer[..<terminator.lowerBound]
                guard headerData.count <= maxHeaderBytes else { throw AppleWebManagementHTTPReadError.tooLarge }
                let partial = try parseHead(Data(headerData))
                let bodyOffset = terminator.upperBound

                guard partial.method == "POST", partial.path == "/" || partial.path == "/openstream" else {
                    return partial.withBody("")
                }
                guard partial.headers["transfer-encoding"] == nil else {
                    throw AppleWebManagementHTTPReadError.malformed
                }
                guard let lengthValue = partial.headers["content-length"],
                      let contentLength = Int(lengthValue),
                      (1 ... maxBodyBytes).contains(contentLength) else {
                    throw AppleWebManagementHTTPReadError.tooLarge
                }

                let availableBodyBytes = buffer.count - bodyOffset
                if availableBodyBytes >= contentLength {
                    let bodyData = buffer[bodyOffset ..< bodyOffset + contentLength]
                    guard let body = String(data: bodyData, encoding: .utf8) else {
                        throw AppleWebManagementHTTPReadError.malformed
                    }
                    return partial.withBody(body)
                }
                guard buffer.count <= bodyOffset + maxBodyBytes else {
                    throw AppleWebManagementHTTPReadError.tooLarge
                }
            } else if buffer.count > maxHeaderBytes {
                throw AppleWebManagementHTTPReadError.tooLarge
            }

            if streamIsComplete { throw AppleWebManagementHTTPReadError.malformed }
            let (data, isComplete) = try await receive(from: connection)
            if let data, !data.isEmpty { buffer.append(data) }
            streamIsComplete = isComplete
            if data?.isEmpty != false, !isComplete {
                throw AppleWebManagementHTTPReadError.malformed
            }
        }
    }

    private static func parseHead(_ data: Data) throws -> PartialRequest {
        guard let text = String(data: data, encoding: .utf8) else {
            throw AppleWebManagementHTTPReadError.malformed
        }
        let lines = text.components(separatedBy: "\r\n")
        guard let requestLine = lines.first,
              !requestLine.isEmpty,
              requestLine.utf8.count <= maxRequestLineBytes else {
            throw AppleWebManagementHTTPReadError.tooLarge
        }

        let requestParts = requestLine.split(separator: " ", omittingEmptySubsequences: true)
        guard requestParts.count == 3,
              requestParts[2].hasPrefix("HTTP/1."),
              requestParts[1].first == "/" else {
            throw AppleWebManagementHTTPReadError.malformed
        }
        let method = String(requestParts[0])
        let target = String(requestParts[1])
        let targetParts = target.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
        let path = String(targetParts[0])
        let query = targetParts.count == 2 ? AppleWebManagementProtocol.parseForm(String(targetParts[1])) : [:]

        let headerLines = Array(lines.dropFirst())
        guard headerLines.count <= maxHeaderCount else { throw AppleWebManagementHTTPReadError.tooLarge }
        var headers: [String: String] = [:]
        for line in headerLines {
            guard !line.isEmpty, line.utf8.count <= maxHeaderLineBytes else {
                throw line.utf8.count > maxHeaderLineBytes
                    ? AppleWebManagementHTTPReadError.tooLarge
                    : AppleWebManagementHTTPReadError.malformed
            }
            guard let separator = line.firstIndex(of: ":"), separator != line.startIndex else {
                throw AppleWebManagementHTTPReadError.malformed
            }
            let name = String(line[..<separator]).lowercased()
            guard isValidHeaderName(name), headers[name] == nil else {
                throw AppleWebManagementHTTPReadError.malformed
            }
            headers[name] = String(line[line.index(after: separator)...])
                .trimmingCharacters(in: .whitespaces)
        }

        return PartialRequest(
            method: method,
            target: target,
            path: path,
            query: query,
            headers: headers
        )
    }

    private static func receive(from connection: NWConnection) async throws -> (Data?, Bool) {
        try await withCheckedThrowingContinuation { continuation in
            connection.receive(minimumIncompleteLength: 1, maximumLength: 4_096) { data, _, isComplete, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: (data, isComplete))
                }
            }
        }
    }

    private static func isValidHeaderName(_ name: String) -> Bool {
        !name.isEmpty && name.utf8.allSatisfy { byte in
            switch byte {
            case 48 ... 57, 65 ... 90, 97 ... 122:
                true
            case 33, 35 ... 39, 42, 43, 45, 46, 94, 95, 96, 124, 126:
                true
            default:
                false
            }
        }
    }

    private struct PartialRequest {
        let method: String
        let target: String
        let path: String
        let query: [String: String]
        let headers: [String: String]

        func withBody(_ body: String) -> AppleWebManagementHTTPRequest {
            AppleWebManagementHTTPRequest(
                method: method,
                target: target,
                path: path,
                query: query,
                headers: headers,
                body: body
            )
        }
    }
}

private struct AppleWebManagementHTTPResponse: Sendable {
    let code: Int
    let status: String
    let body: String
    let contentType: String
    let headers: [String: String]

    static func plain(
        _ code: Int,
        _ status: String,
        _ body: String,
        headers: [String: String] = [:]
    ) -> Self {
        Self(code: code, status: status, body: body, contentType: "text/plain; charset=utf-8", headers: headers)
    }

    static func html(
        _ code: Int,
        _ status: String,
        _ body: String,
        headers: [String: String] = [:]
    ) -> Self {
        Self(code: code, status: status, body: body, contentType: "text/html; charset=utf-8", headers: headers)
    }

    func serialized() -> Data {
        let bodyData = Data(body.utf8)
        var lines = [
            "HTTP/1.1 \(code) \(status)",
            "Content-Type: \(contentType)",
            "Content-Length: \(bodyData.count)",
            "Cache-Control: no-store",
            "Connection: close",
            "X-Content-Type-Options: nosniff",
            "X-Frame-Options: DENY",
            "Referrer-Policy: no-referrer",
            "Permissions-Policy: camera=(), microphone=(), geolocation=()",
            "Content-Security-Policy: default-src 'none'; style-src 'unsafe-inline'; form-action 'self'; base-uri 'none'; frame-ancestors 'none'",
        ]
        lines.append(contentsOf: headers.sorted(by: { $0.key < $1.key }).map { "\($0.key): \($0.value)" })
        var response = Data((lines.joined(separator: "\r\n") + "\r\n\r\n").utf8)
        response.append(bodyData)
        return response
    }
}
