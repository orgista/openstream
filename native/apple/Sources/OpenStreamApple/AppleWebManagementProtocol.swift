import Darwin
import Foundation

public struct AppleWebManagementSession: Equatable, Sendable {
    public let url: URL
    public let friendlyURL: URL
    public let expiresAt: Date
    public let token: String

    public init(url: URL, friendlyURL: URL, expiresAt: Date, token: String) {
        self.url = url
        self.friendlyURL = friendlyURL
        self.expiresAt = expiresAt
        self.token = token
    }

    public var isExpired: Bool { expiresAt <= .now }
}

public enum AppleWebManagementProtocol {
    public static func makeToken() -> String {
        var generator = SystemRandomNumberGenerator()
        let alphabet = Array("0123456789abcdef".utf8)
        var encoded = [UInt8]()
        encoded.reserveCapacity(32)

        for _ in 0 ..< 16 {
            let byte = UInt8.random(in: .min ... .max, using: &generator)
            encoded.append(alphabet[Int(byte >> 4)])
            encoded.append(alphabet[Int(byte & 0x0f)])
        }

        return String(decoding: encoded, as: UTF8.self)
    }

    public static func parseForm(_ body: String) -> [String: String] {
        body.split(separator: "&", omittingEmptySubsequences: false).reduce(into: [:]) { result, rawPair in
            let pair = String(rawPair)
            guard let separator = pair.firstIndex(of: "=") else { return }
            let rawKey = String(pair[..<separator])
            let rawValue = String(pair[pair.index(after: separator)...])
            guard let key = formDecode(rawKey), let value = formDecode(rawValue) else { return }
            result[key] = value
        }
    }

    public static func isAllowedClient(host: String) -> Bool {
        var normalized = host.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.hasPrefix("[") && normalized.hasSuffix("]") {
            normalized.removeFirst()
            normalized.removeLast()
        }
        normalized = normalized.split(separator: "%", maxSplits: 1).first.map(String.init)?.lowercased() ?? ""
        if normalized == "localhost" { return true }
        if normalized.hasPrefix("::ffff:") {
            return isAllowedClient(host: String(normalized.dropFirst("::ffff:".count)))
        }
        let components = normalized.split(separator: ".", omittingEmptySubsequences: false)
        if components.count == 4 {
            let octets = components.compactMap { UInt8($0) }
            guard octets.count == components.count else { return false }
            return switch (octets[0], octets[1]) {
            case (10, _), (127, _), (192, 168), (169, 254): true
            case (172, 16 ... 31): true
            default: false
            }
        }

        var address = in6_addr()
        let parsed = normalized.withCString { inet_pton(AF_INET6, $0, &address) }
        guard parsed == 1 else { return false }
        return withUnsafeBytes(of: &address) { bytes in
            let loopback = bytes.dropLast().allSatisfy { $0 == 0 } && bytes.last == 1
            let linkLocal = bytes[0] == 0xfe && (bytes[1] & 0xc0) == 0x80
            let uniqueLocal = (bytes[0] & 0xfe) == 0xfc
            return loopback || linkLocal || uniqueLocal
        }
    }

    public static func isValidOrigin(_ value: String?, session: AppleWebManagementSession) -> Bool {
        guard let value else { return true }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        guard trimmed.lowercased() != "null", let origin = URLComponents(string: trimmed) else { return false }
        guard let scheme = origin.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return false }
        guard origin.user == nil, origin.password == nil else { return false }
        guard let host = origin.host?.lowercased() else { return false }

        let sessionHost = session.url.host?.lowercased()
        let friendlyHost = session.friendlyURL.host?.lowercased()
        // Accept the session host, loopback, any private-LAN client (the
        // existing LAN contract), and — the fix — the mDNS name the app itself
        // advertises: a desktop browser resolving `openstream.local` sends that
        // as its Origin, and the IP-only check was rejecting it (the reported
        // "cross-origin request rejected"). Any *.local host is LAN-only by
        // definition. The session-port match still gates every case.
        let hostAllowed = host == sessionHost || host == friendlyHost || host == "localhost" ||
            host == "127.0.0.1" || host.hasSuffix(".local") || isAllowedClient(host: host)
        guard hostAllowed else { return false }

        let originPort = origin.port ?? (scheme == "https" ? 443 : 80)
        let sessionPort = session.url.port ?? 80
        return originPort == sessionPort
    }

    /// Browsers normally send `Origin` for a form POST, but QR scanners and
    /// privacy browsers can intentionally expose an opaque `null` origin or
    /// suppress it. Prefer a concrete Origin, fall back to Referer, and let the
    /// unguessable one-use session token authenticate opaque submissions.
    public static func isValidRequestSource(
        origin: String?,
        referer: String?,
        session: AppleWebManagementSession
    ) -> Bool {
        if let origin = meaningfulBrowserSource(origin) {
            if origin.caseInsensitiveCompare("null") != .orderedSame {
                return isValidOrigin(origin, session: session)
            }
        }
        if let referer = meaningfulBrowserSource(referer) {
            if referer.caseInsensitiveCompare("about:blank") != .orderedSame,
               referer.caseInsensitiveCompare("null") != .orderedSame {
                return isValidOrigin(referer, session: session)
            }
        }
        return true
    }

    public static func hasValidToken(
        form: [String: String],
        headers: [String: String],
        query: [String: String],
        session: AppleWebManagementSession
    ) -> Bool {
        let normalizedHeaders = Dictionary(uniqueKeysWithValues: headers.map { ($0.key.lowercased(), $0.value) })
        let cookie = normalizedHeaders["cookie"].flatMap(cookieToken)
        let candidate = form["token"] ?? query["token"] ?? normalizedHeaders["x-setup-token"] ?? cookie
        guard let candidate else { return false }
        return constantTimeEqual(candidate, session.token)
    }

    private static func formDecode(_ value: String) -> String? {
        value.replacingOccurrences(of: "+", with: " ").removingPercentEncoding
    }

    private static func meaningfulBrowserSource(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func cookieToken(_ value: String) -> String? {
        value.split(separator: ";").lazy.compactMap { pair -> String? in
            let value = pair.trimmingCharacters(in: .whitespaces)
            guard let separator = value.firstIndex(of: "=") else { return nil }
            guard value[..<separator].lowercased() == "openstream_token" else { return nil }
            return String(value[value.index(after: separator)...]).trimmingCharacters(in: .whitespaces)
        }.first
    }

    private static func constantTimeEqual(_ lhs: String, _ rhs: String) -> Bool {
        let left = Array(lhs.utf8)
        let right = Array(rhs.utf8)
        guard left.count == right.count else { return false }
        return zip(left, right).reduce(UInt8.zero) { $0 | ($1.0 ^ $1.1) } == 0
    }
}
