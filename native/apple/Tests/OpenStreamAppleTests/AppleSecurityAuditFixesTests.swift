import Foundation
import Testing
@testable import OpenStreamApple

private final class AuditCredentialStore: AppleCredentialStoring {
    var values: [String: String] = [:]

    func string(for account: String) throws -> String? { values[account] }
    func set(_ value: String, for account: String) throws { values[account] = value }
    func remove(_ account: String) throws { values.removeValue(forKey: account) }
}

@MainActor
@Suite struct AppleSecurityAuditFixesTests {
    private static let guide = "https://iptv.fixture.example/xmltv.php?username=fixture-user&password=fixture-password"

    private func makeDefaults() throws -> (UserDefaults, String) {
        let name = "AppleSecurityAuditFixesTests.\(UUID().uuidString)"
        return (try #require(UserDefaults(suiteName: name)), name)
    }

    private func blobText(_ defaults: UserDefaults) throws -> String {
        let data = try #require(defaults.data(forKey: "openstream.sources.v1"))
        return try #require(String(data: data, encoding: .utf8))
    }

    @Test func guideAddressLivesInKeychainNotInDefaults() throws {
        let (defaults, name) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let keychain = AuditCredentialStore()
        let store = AppleSourceStore(defaults: defaults, keychain: keychain)
        let source = try store.addIPTV(
            name: "TV", type: .xtream, endpoint: "https://iptv.fixture.example",
            username: "fixture-user", password: "fixture-password", epgURL: Self.guide)

        let text = try blobText(defaults)
        #expect(!text.contains("fixture-password"))
        #expect(!text.contains("xmltv"))
        #expect(!text.contains("epgURL"))
        #expect(keychain.values[AppleSourceStore.guideReference(source.id)] == Self.guide)

        let reloaded = AppleSourceStore(defaults: defaults, keychain: keychain)
        #expect(reloaded.sources.first?.epgURL?.absoluteString == Self.guide)
        #expect(try reloaded.configurationSecrets().guideAddresses[source.id]?.absoluteString == Self.guide)
    }

    @Test func savedBlobWithGuideAddressIsMigratedOnLoad() throws {
        let (defaults, name) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let keychain = AuditCredentialStore()
        let source = try AppleSourceStore(defaults: defaults, keychain: keychain).addIPTV(
            name: "TV", type: .xtream, endpoint: "https://iptv.fixture.example",
            username: "fixture-user", password: "fixture-password")
        // Rebuild the pre-fix blob: the guide address stored inline, nothing in the Keychain.
        let data = try #require(defaults.data(forKey: "openstream.sources.v1"))
        var members = try #require(try JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        members[0]["epgURL"] = Self.guide
        defaults.set(try JSONSerialization.data(withJSONObject: members), forKey: "openstream.sources.v1")
        #expect(try blobText(defaults).contains("fixture-password"))

        let migrated = AppleSourceStore(defaults: defaults, keychain: keychain)
        #expect(migrated.sources.first?.epgURL?.absoluteString == Self.guide)
        #expect(keychain.values[AppleSourceStore.guideReference(source.id)] == Self.guide)
        #expect(!(try blobText(defaults)).contains("fixture-password"))
        #expect(!(try blobText(defaults)).contains("epgURL"))
    }

    @Test func clearingGuideAddressRemovesKeychainEntry() throws {
        let (defaults, name) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let keychain = AuditCredentialStore()
        let store = AppleSourceStore(defaults: defaults, keychain: keychain)
        let source = try store.addIPTV(
            name: "TV", type: .xtream, endpoint: "https://iptv.fixture.example",
            username: "fixture-user", password: "fixture-password", epgURL: Self.guide)
        _ = try store.addIPTV(
            name: "TV", type: .xtream, endpoint: "https://iptv.fixture.example",
            username: "fixture-user", password: "fixture-password", epgURL: nil)

        #expect(keychain.values[AppleSourceStore.guideReference(source.id)] == nil)
        #expect(AppleSourceStore(defaults: defaults, keychain: keychain).sources.first?.epgURL == nil)
    }

    @Test func redactorCoversSchemelessXtreamPathsAndBearerTokens() {
        let line = "load iptv.fixture.example:8080/live/fixture-user/fixture-password/42.ts; Authorization: Bearer abc.def-123 done"
        let redacted = AppleDiagnosticsReport.redactLine(line)
        #expect(!redacted.contains("fixture-user"))
        #expect(!redacted.contains("fixture-password"))
        #expect(!redacted.contains("abc.def-123"))
        #expect(redacted.contains("/live/[REDACTED]/[REDACTED]/42.ts"))
        #expect(!AppleDiagnosticRedactor.redact("GET host/series/user-a/pass-b/1.mkv").contains("pass-b"))
    }

    @Test func errorDescriptionsInTracesCarryNoStreamURL() {
        let failing = "https://iptv.fixture.example/live/fixture-user/fixture-password/42.ts"
        let error = URLError(.timedOut, userInfo: [NSURLErrorFailingURLStringErrorKey: failing])
        #expect("\(error)".contains("fixture-password"))
        #expect(!AppleDiagnosticRedactor.describe(error).contains("fixture-password"))
    }

    @Test func gzipSubtitleInflationStopsAtTheCap() throws {
        func gzip(_ payload: Data) throws -> Data {
            let deflated = try (payload as NSData).compressed(using: .zlib) as Data
            return Data([0x1f, 0x8b, 0x08, 0, 0, 0, 0, 0, 0, 0xff]) + deflated + Data(repeating: 0, count: 8)
        }
        let small = Data("1\n00:00:01,000 --> 00:00:02,000\nHello\n".utf8)
        #expect(AppleSubtitleTextParser.decompressedIfNeeded(try gzip(small)) == small)

        let bomb = try gzip(Data(count: AppleSubtitleTextParser.maximumInflatedBytes + 1_000_000))
        #expect(bomb.count < 1_000_000)
        #expect(AppleSubtitleTextParser.decompressedIfNeeded(bomb) == bomb)
        #expect(AppleSubtitleTextParser.inflate(Data([0x01, 0x02, 0x03]), limit: 1_000) == nil)
    }
}
