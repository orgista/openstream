import Foundation
import Testing
import Darwin
@testable import OpenStreamApple

@Test func webManagementTokenAndTrustRulesMatchTheLANContract() throws {
    let tokens = Set((0 ..< 32).map { _ in AppleWebManagementProtocol.makeToken() })
    #expect(tokens.count == 32)
    #expect(tokens.allSatisfy { token in
        token.count == 32 && token.utf8.allSatisfy { byte in
            (48 ... 57).contains(byte) || (97 ... 102).contains(byte)
        }
    })

    let token = try #require(tokens.first)
    let session = AppleWebManagementSession(
        url: URL(string: "http://192.168.1.20:11470/openstream?token=\(token)")!,
        friendlyURL: URL(string: "http://192.168.1.20:11470/")!,
        expiresAt: .now.addingTimeInterval(600),
        token: token
    )

    #expect(AppleWebManagementProtocol.isAllowedClient(host: "127.0.0.1"))
    #expect(AppleWebManagementProtocol.isAllowedClient(host: "169.254.8.9"))
    #expect(AppleWebManagementProtocol.isAllowedClient(host: "[fe80::2%en0]"))
    #expect(AppleWebManagementProtocol.isAllowedClient(host: "fd00::2"))
    #expect(!AppleWebManagementProtocol.isAllowedClient(host: "8.8.8.8"))
    #expect(!AppleWebManagementProtocol.isAllowedClient(host: "192.168.bad.1.2"))
    #expect(!AppleWebManagementProtocol.isAllowedClient(host: "fdrive.example"))
    #expect(!AppleWebManagementProtocol.isAllowedClient(host: "fc-malicious.example"))
    #expect(!AppleWebManagementProtocol.isAllowedClient(host: "fe80:not-an-address"))
    #expect(AppleWebManagementProtocol.isValidOrigin("http://192.168.1.44:11470/page", session: session))
    #expect(!AppleWebManagementProtocol.isValidOrigin("http://192.168.1.44:8080/page", session: session))
    #expect(!AppleWebManagementProtocol.isValidOrigin("https://evil.example", session: session))
    // Desktop browsers resolving the advertised mDNS name send it as Origin;
    // a *.local host on the session port must be accepted (regression: the
    // IP-only check produced "cross-origin request rejected").
    #expect(AppleWebManagementProtocol.isValidOrigin("http://openstream.local:11470/", session: session))
    #expect(!AppleWebManagementProtocol.isValidOrigin("http://openstream.local:8080/", session: session))
    #expect(AppleWebManagementProtocol.isValidRequestSource(
        origin: "null",
        referer: nil,
        session: session
    ))
    #expect(AppleWebManagementProtocol.isValidRequestSource(
        origin: nil,
        referer: "about:blank",
        session: session
    ))
    #expect(!AppleWebManagementProtocol.isValidRequestSource(
        origin: "https://evil.example",
        referer: "http://192.168.1.20:11470/openstream",
        session: session
    ))

    #expect(!AppleWebManagementProtocol.hasValidToken(
        form: ["token": "wrong"],
        headers: ["X-Setup-Token": token],
        query: ["token": token],
        session: session
    ))
    #expect(AppleWebManagementProtocol.hasValidToken(
        form: [:],
        headers: ["X-Setup-Token": "wrong", "Cookie": "openstream_token=wrong"],
        query: ["token": token],
        session: session
    ))
    #expect(AppleWebManagementProtocol.hasValidToken(
        form: [:],
        headers: ["X-Setup-Token": token, "Cookie": "openstream_token=wrong"],
        query: [:],
        session: session
    ))
    #expect(AppleWebManagementProtocol.hasValidToken(
        form: [:],
        headers: ["Cookie": "other=x; openstream_token=\(token)"],
        query: [:],
        session: session
    ))
}

@Test func webManagementPageIsLeanAndEscapesSubmittedValues() {
    let page = AppleWebManagementPage.setup(
        token: "abc123",
        manifest: "\"><script>alert(1)</script>",
        error: "No <unsafe> source"
    )

    #expect(page.contains("WEB MANAGEMENT"))
    #expect(page.contains("Add a source"))
    #expect(page.contains("&lt;script&gt;"))
    #expect(page.contains("No &lt;unsafe&gt; source"))
    #expect(!page.contains("<script>"))
    #expect(!page.contains("Example:"))
    #expect(!page.contains("You can close"))
}

@MainActor
@Test func webManagementLoopbackServesAndPersistsOneManifest() async throws {
    let suiteName = "openstream-web-tests-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let sourceStore = AppleSourceStore(defaults: defaults)

    let manifestData = Data(#"""
    {
      "id":"org.example.loopback",
      "name":"Loopback Catalog",
      "version":"1.0.0",
      "resources":["catalog","stream"],
      "catalogs":[{"type":"movie","id":"popular"}]
    }
    """#.utf8)
    let manifestClient = AppleManifestClient { url in
        (manifestData, HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
    let configuration = AppleWebManagementServer.Configuration(
        preferredPort: 0,
        sessionDuration: 30,
        advertisesBonjour: false,
        advertisedHost: "127.0.0.1"
    )
    let server = AppleWebManagementServer(configuration: configuration, manifestClient: manifestClient)
    let activeSession = try await server.start(sourceStore: sourceStore)
    defer { server.stop() }

    #expect(activeSession.friendlyURL.host == "127.0.0.1")
    #expect(activeSession.friendlyURL.host != "openstream.local")
    #expect(activeSession.friendlyURL.path == "/")

    let notFound = try await response(for: request(url: activeSession.friendlyURL.appendingPathComponent("missing")))
    #expect(notFound.statusCode == 404)

    var methodRequest = request(url: activeSession.friendlyURL)
    methodRequest.httpMethod = "PUT"
    let methodResponse = try await response(for: methodRequest)
    #expect(methodResponse.statusCode == 405)

    var originRequest = request(url: activeSession.friendlyURL)
    originRequest.setValue("https://evil.example", forHTTPHeaderField: "Origin")
    let originResponse = try await response(for: originRequest)
    #expect(originResponse.statusCode == 403)

    var emptyPost = request(url: activeSession.friendlyURL)
    emptyPost.httpMethod = "POST"
    emptyPost.httpBody = Data()
    let emptyResponse = try await response(for: emptyPost)
    #expect(emptyResponse.statusCode == 413)

    let (pageData, pageResponse) = try await dataResponse(for: request(url: activeSession.friendlyURL))
    #expect(pageResponse.statusCode == 200)
    #expect(pageResponse.value(forHTTPHeaderField: "Set-Cookie")?.contains("SameSite=Strict") == true)
    #expect(pageResponse.value(forHTTPHeaderField: "Set-Cookie")?.contains("HttpOnly") == true)
    #expect(pageResponse.value(forHTTPHeaderField: "Content-Security-Policy")?.contains("default-src 'none'") == true)
    #expect(String(decoding: pageData, as: UTF8.self).contains("Add a source"))

    let manifest = "https://addon.example/manifest.json"
    var invalidPost = request(url: activeSession.friendlyURL)
    invalidPost.httpMethod = "POST"
    invalidPost.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
    invalidPost.httpBody = formBody(manifest: manifest, token: "wrong")
    #expect(try await response(for: invalidPost).statusCode == 403)

    var validPost = request(url: activeSession.friendlyURL)
    validPost.httpMethod = "POST"
    validPost.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
    validPost.httpBody = formBody(manifest: manifest, token: activeSession.token)
    let (successData, successResponse) = try await dataResponse(for: validPost)
    #expect(successResponse.statusCode == 200)
    #expect(String(decoding: successData, as: UTF8.self).contains("Loopback Catalog"))
    #expect(sourceStore.sources.count == 1)
    #expect(sourceStore.sources.first?.manifestID == "org.example.loopback")
    #expect(server.session == nil)
}

@MainActor
@Test func webManagementExpiresAndReleasesItsListener() async throws {
    let suiteName = "openstream-web-expiry-tests-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let sourceStore = AppleSourceStore(defaults: defaults)
    let configuration = AppleWebManagementServer.Configuration(
        preferredPort: 0,
        sessionDuration: 0.05,
        advertisesBonjour: false,
        advertisedHost: "127.0.0.1"
    )
    let server = AppleWebManagementServer(configuration: configuration)

    _ = try await server.start(sourceStore: sourceStore)
    try await Task.sleep(nanoseconds: 150_000_000)
    #expect(server.session == nil)
}

@MainActor
@Test func webManagementFallsBackWhenThePreferredPortIsOccupied() async throws {
    let (socketDescriptor, occupiedPort) = try occupiedLoopbackPort()
    defer { Darwin.close(socketDescriptor) }

    let suiteName = "openstream-web-fallback-tests-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let sourceStore = AppleSourceStore(defaults: defaults)
    let configuration = AppleWebManagementServer.Configuration(
        preferredPort: occupiedPort,
        sessionDuration: 30,
        advertisesBonjour: false,
        advertisedHost: "127.0.0.1"
    )
    let server = AppleWebManagementServer(configuration: configuration)
    defer { server.stop() }

    let activeSession = try await server.start(sourceStore: sourceStore)
    #expect(activeSession.url.port != Int(occupiedPort))
    #expect((activeSession.url.port ?? 0) > 0)
}

private func request(url: URL) -> URLRequest {
    var request = URLRequest(url: url)
    request.timeoutInterval = 5
    return request
}

private func formBody(manifest: String, token: String) -> Data {
    var components = URLComponents()
    components.queryItems = [
        URLQueryItem(name: "manifest", value: manifest),
        URLQueryItem(name: "token", value: token),
    ]
    return Data((components.percentEncodedQuery ?? "").utf8)
}

private func response(for request: URLRequest) async throws -> HTTPURLResponse {
    try await dataResponse(for: request).1
}

private func dataResponse(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.httpShouldSetCookies = false
    let session = URLSession(configuration: configuration)
    defer { session.invalidateAndCancel() }
    let (data, response) = try await session.data(for: request)
    return (data, try #require(response as? HTTPURLResponse))
}

private func occupiedLoopbackPort() throws -> (Int32, UInt16) {
    let descriptor = Darwin.socket(AF_INET, SOCK_STREAM, 0)
    guard descriptor >= 0 else { throw POSIXError(.ENFILE) }

    var address = sockaddr_in()
    address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
    address.sin_family = sa_family_t(AF_INET)
    address.sin_port = 0
    address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))

    let bindResult = withUnsafePointer(to: &address) { pointer in
        pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            Darwin.bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
        }
    }
    guard bindResult == 0, Darwin.listen(descriptor, 1) == 0 else {
        Darwin.close(descriptor)
        throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }

    var length = socklen_t(MemoryLayout<sockaddr_in>.size)
    let nameResult = withUnsafeMutablePointer(to: &address) { pointer in
        pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            Darwin.getsockname(descriptor, $0, &length)
        }
    }
    guard nameResult == 0 else {
        Darwin.close(descriptor)
        throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
    return (descriptor, UInt16(bigEndian: address.sin_port))
}
