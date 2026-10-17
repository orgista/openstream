import Foundation
import Network

public enum AppleSMBRangeServerError: Error, LocalizedError, Sendable {
    case listenerUnavailable
    case invalidMedia

    public var errorDescription: String? {
        switch self {
        case .listenerUnavailable: "oStream couldn’t start its private SMB playback bridge."
        case .invalidMedia: "The selected SMB file is no longer available."
        }
    }
}

/// A loopback-only HTTP byte-range bridge for AVPlayer. The random token is a
/// short-lived capability; SMB credentials and paths never appear in logs or
/// in a public network response.
public actor AppleSMBRangeServer {
    public static let shared = AppleSMBRangeServer()

    private struct Session: Sendable {
        let sourceURL: URL
        let credentials: AppleSMBCredentials
        let sizeBytes: UInt64
        let modifiedAt: Date?
        let expiresAt: Date

        /// The file as the block cache knows it: a file replaced at the same
        /// path and size is another file.
        var cacheFile: String {
            "\(sourceURL.absoluteString)#\(sizeBytes)#\(modifiedAt?.timeIntervalSince1970 ?? 0)"
        }
    }

    private let client: any AppleNetworkShareClient
    private let readTimeout: Duration
    private let addedLatency: Duration
    private let usesBlockCache: Bool
    private var blockCache = AppleSMBBlockCache()
    private var readStats: [String: AppleSMBReadStats] = [:]
    private struct ConnectionJob {
        let connection: NWConnection
        let task: Task<Void, Never>
        var token: String?
        var responseStarted = false
    }
    private var connectionJobs: [UUID: ConnectionJob] = [:]
    private var sessions: [String: Session] = [:]
    private var listener: NWListener?
    private var listenerError: (any Error)?
    private var listenerIsReady = false

    public init(
        client: any AppleNetworkShareClient = AppleSMBClient(),
        readTimeout: Duration = .seconds(30),
        addedLatency: Duration = AppleSMBRangeServer.launchArgumentLatency(),
        usesBlockCache: Bool = AppleSMBRangeServer.launchArgumentUsesBlockCache()
    ) {
        self.client = client
        self.readTimeout = max(readTimeout, .milliseconds(1))
        self.addedLatency = addedLatency
        self.usesBlockCache = usesBlockCache
    }

    /// `-OpenStreamSMBTestLatencyMs 40`: a pause before every SMB read, so a
    /// device on a fast LAN can stand in for a slow Wi-Fi path. Launch
    /// arguments only, never a stored setting.
    public static func launchArgumentLatency() -> Duration {
        let value = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)["OpenStreamSMBTestLatencyMs"]
        let milliseconds = (value as? String).flatMap(Int.init) ?? (value as? Int) ?? 0
        return .milliseconds(min(max(milliseconds, 0), 500))
    }

    /// `-OpenStreamSMBBlockCache NO`: the bridge as it was before the disc
    /// block cache, for before/after measurements.
    public static func launchArgumentUsesBlockCache() -> Bool {
        let value = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)["OpenStreamSMBBlockCache"]
        return (value as? String).map { $0.uppercased() != "NO" } ?? true
    }

    /// Bytes the bridge has sent for `playbackURL` so far; 0 for a URL it did
    /// not issue. A disc image's start shows its progress here while the
    /// engine reads the disc structure and reports nothing else.
    func bytesServed(playbackURL: URL) -> UInt64 {
        Self.token(of: playbackURL).flatMap { readStats[$0]?.bytesServed } ?? 0
    }

    func readStats(playbackURL: URL) -> AppleSMBReadStats? {
        Self.token(of: playbackURL).flatMap { readStats[$0] }
    }

    public func playbackURL(
        sourceURL: URL,
        credentials: AppleSMBCredentials,
        sizeBytes: Int64,
        modifiedAt: Date? = nil,
        lifetime: TimeInterval = 4 * 60 * 60
    ) async throws -> URL {
        guard sourceURL.scheme?.lowercased() == "smb", sizeBytes > 0 else {
            throw AppleSMBRangeServerError.invalidMedia
        }
        let port = try await ensureListener()
        sessions = sessions.filter { $0.value.expiresAt > .now }
        readStats = readStats.filter { sessions[$0.key] != nil }
        guard sessions.count < 32 else { throw AppleSMBRangeServerError.listenerUnavailable }
        let token = Self.token()
        sessions[token] = Session(
            sourceURL: sourceURL,
            credentials: credentials,
            sizeBytes: UInt64(sizeBytes),
            modifiedAt: modifiedAt,
            expiresAt: .now.addingTimeInterval(min(max(lifetime, 60), 24 * 60 * 60))
        )
        let filename = sourceURL.lastPathComponent.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
            ?? "media"
        return URL(string: "http://127.0.0.1:\(port)/media/\(token)/\(filename)")!
    }

    public func revoke(playbackURL: URL) async {
        guard let token = Self.token(of: playbackURL) else { return }
        if let stats = readStats.removeValue(forKey: token), stats.requests > 0 {
            AppleInteractionTrace.record(.network, "smb bridge \(playbackURL.lastPathComponent.suffix(48)): \(stats.traceLine)")
        }
        sessions.removeValue(forKey: token)
        cancelConnections(token: token)
        if sessions.isEmpty {
            cancelConnections()
            await client.closeAll()
        }
        stopListenerIfIdle()
    }

    public func removeAllSessions() async {
        sessions.removeAll()
        readStats.removeAll()
        blockCache.removeAll()
        cancelConnections()
        await client.closeAll()
        stopListenerIfIdle()
    }

    func diagnostics() -> (sessionCount: Int, listenerActive: Bool, connectionCount: Int) {
        (sessions.count, listener != nil, connectionJobs.count)
    }

    private func ensureListener() async throws -> UInt16 {
        if listenerIsReady, let port = listener?.port?.rawValue { return port }
        if listener == nil {
            listenerError = nil
            listenerIsReady = false
            let parameters = NWParameters.tcp
            parameters.requiredInterfaceType = .loopback
            parameters.allowLocalEndpointReuse = true
            let listener = try NWListener(using: parameters, on: .any)
            listener.service = nil
            listener.stateUpdateHandler = { [weak self] state in
                if case .ready = state {
                    Task { await self?.recordListenerReady() }
                } else if case .failed(let error) = state {
                    Task { await self?.recordListenerError(error) }
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                Task { await self?.startConnection(connection) }
            }
            listener.start(queue: DispatchQueue(label: "com.orgista.openstream.smb-range"))
            self.listener = listener
        }

        for _ in 0 ..< 100 {
            if listenerError != nil { throw AppleSMBRangeServerError.listenerUnavailable }
            if listenerIsReady, let port = listener?.port?.rawValue { return port }
            try await Task.sleep(for: .milliseconds(20))
        }
        throw AppleSMBRangeServerError.listenerUnavailable
    }

    private func recordListenerReady() { listenerIsReady = true }

    private func recordListenerError(_ error: any Error) {
        listenerError = error
        listenerIsReady = false
        listener?.cancel()
        listener = nil
    }

    private func stopListenerIfIdle() {
        guard sessions.isEmpty else { return }
        listener?.cancel()
        listener = nil
        listenerError = nil
        listenerIsReady = false
    }

    private func startConnection(_ connection: NWConnection) {
        let id = UUID()
        let task = Task { [weak self] in
            guard let self else { connection.cancel(); return }
            await self.accept(connection, id: id)
        }
        connectionJobs[id] = ConnectionJob(connection: connection, task: task)
    }

    private func cancelConnections(token: String? = nil) {
        let ids = connectionJobs.compactMap { id, job in token == nil || job.token == token ? id : nil }
        for id in ids {
            guard let job = connectionJobs.removeValue(forKey: id) else { continue }
            job.task.cancel()
            job.connection.cancel()
        }
    }

    private func accept(_ connection: NWConnection, id: UUID) async {
        defer {
            connectionJobs.removeValue(forKey: id)
            connection.cancel()
        }
        guard Self.isLoopback(connection.endpoint) else {
            connection.cancel()
            return
        }
        connection.start(queue: DispatchQueue(label: "com.orgista.openstream.smb-range.connection"))
        let timeout = Task {
            try? await Task.sleep(for: .seconds(10))
            if !Task.isCancelled { connection.cancel() }
        }
        do {
            let request = try await receiveRequest(connection)
            timeout.cancel()
            try await respond(to: request, connection: connection, id: id)
        } catch {
            timeout.cancel()
            if !Task.isCancelled, connectionJobs[id]?.responseStarted != true { try? await send(
                Data("HTTP/1.1 400 Bad Request\r\nConnection: close\r\nContent-Length: 0\r\n\r\n".utf8),
                connection: connection,
                final: true
            ) }
        }
        timeout.cancel()
        connection.cancel()
    }

    private func respond(to request: String, connection: NWConnection, id: UUID) async throws {
        let lines = request.components(separatedBy: "\r\n")
        let requestParts = lines.first?.split(separator: " ") ?? []
        guard requestParts.count >= 2 else { throw AppleSMBRangeServerError.invalidMedia }
        let method = String(requestParts[0]).uppercased()
        guard method == "GET" || method == "HEAD" else { throw AppleSMBRangeServerError.invalidMedia }
        let path = String(requestParts[1])
        let pieces = path.split(separator: "/")
        guard pieces.count >= 3, pieces[0] == "media" else { throw AppleSMBRangeServerError.invalidMedia }
        let token = String(pieces[1])
        guard let session = sessions[token], session.expiresAt > .now else {
            connectionJobs[id]?.responseStarted = true
            try await send(
                Data("HTTP/1.1 404 Not Found\r\nConnection: close\r\nContent-Length: 0\r\n\r\n".utf8),
                connection: connection,
                final: true
            )
            return
        }
        connectionJobs[id]?.token = token
        readStats[token, default: AppleSMBReadStats()].requests += 1

        let rangeHeader = lines.first { $0.lowercased().hasPrefix("range:") }
        let requestedRange = rangeHeader.flatMap { Self.parseRange($0, size: session.sizeBytes) }
        if rangeHeader != nil, requestedRange == nil {
            connectionJobs[id]?.responseStarted = true
            let response = "HTTP/1.1 416 Range Not Satisfiable\r\n" +
                "Accept-Ranges: bytes\r\n" +
                "Content-Range: bytes */\(session.sizeBytes)\r\n" +
                "Content-Length: 0\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n"
            try await send(Data(response.utf8), connection: connection, final: true)
            return
        }
        let range = requestedRange ?? 0 ..< session.sizeBytes
        let partial = requestedRange != nil
        let contentLength = range.upperBound - range.lowerBound
        let contentType = Self.contentType(for: session.sourceURL.pathExtension)
        var headers = "HTTP/1.1 \(partial ? "206 Partial Content" : "200 OK")\r\n"
        headers += "Accept-Ranges: bytes\r\n"
        headers += "Content-Type: \(contentType)\r\n"
        headers += "Content-Length: \(contentLength)\r\n"
        if partial {
            headers += "Content-Range: bytes \(range.lowerBound)-\(range.upperBound - 1)/\(session.sizeBytes)\r\n"
        }
        headers += "Cache-Control: no-store\r\nConnection: close\r\n\r\n"
        connectionJobs[id]?.responseStarted = true
        try await send(Data(headers.utf8), connection: connection, final: method == "HEAD" || contentLength == 0)
        guard method == "GET", contentLength > 0 else { return }

        var offset = range.lowerBound
        let chunkSize: UInt64 = 4 * 1_024 * 1_024
        let cached = usesBlockCache && AppleSMBBlockCache.caches(path: session.sourceURL.path, request: range)
        while offset < range.upperBound {
            try Task.checkCancellation()
            let end = min(offset + chunkSize, range.upperBound)
            let data = cached
                ? try await cachedRead(session: session, token: token, range: offset ..< end)
                : try await measuredRead(session: session, token: token, range: offset ..< end)
            guard !data.isEmpty else { throw AppleSMBRangeServerError.invalidMedia }
            let remaining = Int(range.upperBound - offset)
            let bounded = data.count > remaining ? Data(data.prefix(remaining)) : data
            offset += UInt64(bounded.count)
            try await send(bounded, connection: connection, final: offset >= range.upperBound)
            readStats[token]?.bytesServed += UInt64(bounded.count)
        }
    }

    /// `range` assembled from whole cached blocks (`AppleSMBBlockCache`),
    /// reading the missing ones.
    private func cachedRead(session: Session, token: String, range: Range<UInt64>) async throws -> Data {
        var data = Data(capacity: Int(range.count))
        for index in AppleSMBBlockCache.blockIndices(for: range) {
            let key = AppleSMBBlockCache.Key(file: session.cacheFile, index: index)
            let block: Data
            if let hit = blockCache.block(for: key) {
                block = hit
                readStats[token]?.cacheHits += 1
            } else {
                block = try await measuredRead(session: session, token: token,
                    range: AppleSMBBlockCache.byteRange(ofBlock: index, fileSize: session.sizeBytes))
                guard !block.isEmpty else { break }
                blockCache.store(block, for: key)
            }
            let part = AppleSMBBlockCache.slice(block, index: index, of: range)
            guard !part.isEmpty else { break }
            data.append(part)
        }
        return data
    }

    private func measuredRead(session: Session, token: String, range: Range<UInt64>) async throws -> Data {
        let started = ContinuousClock.now
        if addedLatency > .zero { try await Task.sleep(for: addedLatency) }
        let data = try await read(session: session, range: range)
        readStats[token]?.recordSMBRead(bytes: data.count, milliseconds: Int(started.duration(to: .now) / .milliseconds(1)))
        return data
    }

    private func read(session: Session, range: Range<UInt64>) async throws -> Data {
        try Task.checkCancellation()
        return try await withThrowingTaskGroup(of: Data.self) { group in
            defer { group.cancelAll() }
            group.addTask { [client] in
                try await client.read(url: session.sourceURL, credentials: session.credentials, range: range)
            }
            group.addTask { [readTimeout] in
                try await Task.sleep(for: readTimeout)
                throw URLError(.timedOut)
            }
            guard let data = try await group.next() else { throw CancellationError() }
            return data
        }
    }

    private func receiveRequest(_ connection: NWConnection) async throws -> String {
        var data = Data()
        while data.count < 65_536 {
            let chunk = try await receive(connection)
            data.append(chunk)
            if data.range(of: Data("\r\n\r\n".utf8)) != nil { break }
            if chunk.isEmpty { break }
        }
        guard data.range(of: Data("\r\n\r\n".utf8)) != nil,
              let value = String(data: data, encoding: .utf8) else {
            throw AppleSMBRangeServerError.invalidMedia
        }
        return value
    }

    private func receive(_ connection: NWConnection) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { data, _, _, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: data ?? Data()) }
            }
        }
    }

    private func send(_ data: Data, connection: NWConnection, final: Bool) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            connection.send(content: data, contentContext: .defaultMessage, isComplete: final, completion: .contentProcessed {
                if let error = $0 { continuation.resume(throwing: error) }
                else { continuation.resume() }
            })
        }
    }

    static func parseRange(_ line: String, size: UInt64) -> Range<UInt64>? {
        guard size > 0,
              let value = line.split(separator: ":", maxSplits: 1).last?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              value.lowercased().hasPrefix("bytes=") else { return nil }
        let raw = value.dropFirst(6)
        guard !raw.contains(",") else { return nil }
        let bounds = raw.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        guard bounds.count == 2 else { return nil }
        if bounds[0].isEmpty, let suffix = UInt64(bounds[1]), suffix > 0 {
            let length = min(suffix, size)
            return (size - length) ..< size
        }
        guard let start = UInt64(bounds[0]), start < size else { return nil }
        let inclusiveEnd = bounds[1].isEmpty ? size - 1 : min(UInt64(bounds[1]) ?? (size - 1), size - 1)
        guard inclusiveEnd >= start else { return nil }
        return start ..< (inclusiveEnd + 1)
    }

    private static func token(of playbackURL: URL) -> String? {
        let pieces = playbackURL.path.split(separator: "/")
        guard pieces.count >= 2, pieces[0] == "media" else { return nil }
        return String(pieces[1])
    }

    private static func isLoopback(_ endpoint: NWEndpoint) -> Bool {
        guard case .hostPort(let host, _) = endpoint else { return false }
        let value = String(describing: host).lowercased()
        return value == "127.0.0.1" || value == "::1" || value == "localhost"
    }

    private static func contentType(for fileExtension: String) -> String {
        switch fileExtension.lowercased() {
        case "mp4", "m4v": "video/mp4"
        case "mov": "video/quicktime"
        case "ts", "m2ts": "video/mp2t"
        case "webm": "video/webm"
        case "mkv": "video/x-matroska"
        default: "application/octet-stream"
        }
    }

    private static func token() -> String {
        var bytes = [UInt8](repeating: 0, count: 24)
        for index in bytes.indices { bytes[index] = UInt8.random(in: .min ... .max) }
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
