import Foundation
import Testing
@testable import OpenStreamApple

@Test func arrEndpointPolicyAllowsHTTPSAndPrivateLiteralHTTPOnly() throws {
    #expect(AppleArrEndpointPolicy.isAllowed("https://radarr.example"))
    #expect(AppleArrEndpointPolicy.isAllowed("https://radarr.example/openstream/"))
    #expect(AppleArrEndpointPolicy.isAllowed("http://192.168.1.20:7878"))
    #expect(AppleArrEndpointPolicy.isAllowed("http://10.0.0.20:8989"))
    #expect(AppleArrEndpointPolicy.isAllowed("http://[fd00::20]:7878"))
    #expect(!AppleArrEndpointPolicy.isAllowed("http://radarr.example"))
    #expect(!AppleArrEndpointPolicy.isAllowed("http://8.8.8.8:7878"))
    #expect(!AppleArrEndpointPolicy.isAllowed("ftp://192.168.1.20"))
    #expect(!AppleArrEndpointPolicy.isAllowed("https://user:pass@radarr.example"))
    #expect(!AppleArrEndpointPolicy.isAllowed("https://radarr.example?apikey=secret"))
    #expect(!AppleArrEndpointPolicy.isAllowed("https://radarr.example/#status"))

    #expect(try AppleArrEndpointPolicy.normalize(" https://radarr.example/openstream/ ").absoluteString ==
        "https://radarr.example/openstream")
}

@Test func arrClientUsesNativeStatusEndpointAndAPIKeyHeader() async throws {
    let client = AppleArrClient { request in
        #expect(request.httpMethod == "GET")
        #expect(request.url?.absoluteString == "https://radarr.example/openstream/api/v3/system/status")
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
        #expect(request.value(forHTTPHeaderField: "X-Api-Key") == "radarr-secret")
        #expect(request.value(forHTTPHeaderField: "User-Agent") == "OpenStream/1.0 Apple")
        #expect(request.timeoutInterval == 15)

        let data = Data(#"{"appName":"Radarr","version":"5.7.0","instanceName":"Movies"}"#.utf8)
        return (
            data,
            HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        )
    }

    let status = try await client.test(
        kind: .radarr,
        baseURL: "https://radarr.example/openstream/",
        apiKey: "  radarr-secret  "
    )

    #expect(status == AppleArrStatus(appName: "Radarr", version: "5.7.0", instanceName: "Movies"))
}

@Test func arrClientUsesSonarrStatusEndpointAndBoundsDisplayedFields() async throws {
    let client = AppleArrClient { request in
        #expect(request.url?.path == "/api/v3/system/status")
        let payload = """
        {
          "appName": "",
          "version": "\(String(repeating: "1", count: 60))",
          "instanceName": "\(String(repeating: "S", count: 100))"
        }
        """
        return (
            Data(payload.utf8),
            HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        )
    }

    let status = try await client.test(
        kind: .sonarr,
        baseURL: "https://sonarr.example",
        apiKey: "sonarr-secret"
    )

    #expect(status.appName == "Sonarr")
    #expect(status.version.count == 40)
    #expect(status.instanceName.count == 80)
}

@Test func arrClientRejectsInvalidEndpointAndHeaderValueBeforeLoading() async {
    let client = AppleArrClient { _ in
        Issue.record("The loader must not run for invalid connection settings.")
        throw URLError(.badURL)
    }

    await #expect(throws: AppleArrClientError.invalidEndpoint) {
        try await client.test(kind: .radarr, baseURL: "http://public.example:7878", apiKey: "secret")
    }
    await #expect(throws: AppleArrClientError.invalidAPIKey) {
        try await client.test(kind: .sonarr, baseURL: "https://sonarr.example", apiKey: "secret\nheader")
    }
    #expect(!AppleArrClient.isValidAPIKey("secret\rheader"))
    #expect(!AppleArrClient.isValidAPIKey(""))
}

@Test func arrClientRejectsRedirectsAndChangedResponseOrigins() async {
    let redirected = AppleArrClient { request in
        (
            Data(),
            HTTPURLResponse(
                url: request.url!,
                statusCode: 302,
                httpVersion: nil,
                headerFields: ["Location": "https://other.example/api/v3/system/status"]
            )!
        )
    }
    await #expect(throws: AppleArrClientError.redirected) {
        try await redirected.test(kind: .radarr, baseURL: "https://radarr.example", apiKey: "secret")
    }

    let changedOrigin = AppleArrClient { _ in
        let url = URL(string: "https://other.example/api/v3/system/status")!
        return (
            Data(#"{"appName":"Radarr"}"#.utf8),
            HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
        )
    }
    await #expect(throws: AppleArrClientError.redirected) {
        try await changedOrigin.test(kind: .radarr, baseURL: "https://radarr.example", apiKey: "secret")
    }
}

@Test func arrClientRejectsOversizedFailedAndMalformedResponses() async {
    let oversized = AppleArrClient { request in
        (
            Data(repeating: 0, count: AppleArrClient.maximumResponseBytes + 1),
            HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        )
    }
    await #expect(throws: AppleArrClientError.responseTooLarge) {
        try await oversized.test(kind: .radarr, baseURL: "https://radarr.example", apiKey: "secret")
    }

    let failed = AppleArrClient { request in
        (
            Data(),
            HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!
        )
    }
    await #expect(throws: AppleArrClientError.requestFailed(401)) {
        try await failed.test(kind: .sonarr, baseURL: "https://sonarr.example", apiKey: "secret")
    }

    let malformed = AppleArrClient { request in
        (
            Data("[]".utf8),
            HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        )
    }
    await #expect(throws: AppleArrClientError.invalidResponse) {
        try await malformed.test(kind: .sonarr, baseURL: "https://sonarr.example", apiKey: "secret")
    }
}
