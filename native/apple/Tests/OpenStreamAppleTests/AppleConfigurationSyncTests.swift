import Foundation
import Testing
@testable import OpenStreamApple

/// Apple TV: no switch, no Backup screen, no viewer action — it reads whatever
/// the phone has published and applies it.
///
/// Every test here is pure. The simulators on this Mac have no iCloud account
/// signed in, and `NSUbiquitousKeyValueStore` silently drops writes without
/// one, so a real two-device round trip cannot be exercised on this machine;
/// this suite is the proof that the decision either end of the store makes is
/// right. Same caveat as `AppleDevicePlaybackBeaconTests`.
@Suite("Configuration sync policy")
struct AppleConfigurationSyncTests {
    private let epoch = Date(timeIntervalSince1970: 1_800_000_000)

    private func source(id: UUID = UUID(), name: String = "Fixture") -> AppleSource {
        AppleSource(id: id, kind: .liveTV, name: name,
                    url: URL(string: "https://fixture.example/playlist")!)
    }

    private func cloudData(savedAt: Date, sources: [AppleSource]) throws -> Data {
        try AppleConfigurationSnapshot(savedAt: savedAt, sources: sources).cloudData()
    }

    // MARK: - Which devices sync, and which of them publish

    @Test func theAppleTVSyncsWithoutAStoredPreference() {
        #expect(AppleConfigurationSyncPolicy.isEnabled(storedPreference: false, mode: .automaticReadOnly))
        #expect(AppleConfigurationSyncPolicy.isEnabled(storedPreference: true, mode: .automaticReadOnly))
    }

    @Test func everywhereElseTheViewerDecides() {
        #expect(!AppleConfigurationSyncPolicy.isEnabled(storedPreference: false, mode: .viewerChoice))
        #expect(AppleConfigurationSyncPolicy.isEnabled(storedPreference: true, mode: .viewerChoice))
    }

    /// The television is a reader. A setting nudged with the remote must never
    /// be able to overwrite the configuration the phone published.
    @Test func theAppleTVNeverPublishes() {
        #expect(!AppleConfigurationSyncPolicy.publishesChanges(mode: .automaticReadOnly))
        #expect(AppleConfigurationSyncPolicy.publishesChanges(mode: .viewerChoice))
    }

    /// The switch-free mode is also the one that has to migrate the keychain
    /// on first launch, so the two answers must agree.
    @Test func alwaysOnMatchesTheReadOnlyMode() {
        #expect(AppleConfigurationSyncPolicy.isAlwaysOn == (AppleConfigurationSyncPolicy.current == .automaticReadOnly))
        #expect(AppleConfigurationSyncPolicy.isAlwaysOn != AppleConfigurationSyncPolicy.publishesChanges())
    }

    @Test func onlyTheViewerChoiceModeOffersASwitch() {
        #expect(!AppleConfigurationSyncPolicy.offersToggle(mode: .automaticReadOnly))
        #expect(AppleConfigurationSyncPolicy.offersToggle(mode: .viewerChoice))
    }

    @Test func thisPlatformPicksTheRightMode() {
        #if os(tvOS)
        #expect(AppleConfigurationSyncPolicy.current == .automaticReadOnly)
        #else
        #expect(AppleConfigurationSyncPolicy.current == .viewerChoice)
        #endif
    }

    // MARK: - What a launch, or an external change, does with the store

    /// The apply-on-launch and apply-on-change path, with the store's bytes
    /// seeded by hand. This is what `didChangeExternallyNotification` reaches.
    @Test func aNewerSnapshotIsApplied() throws {
        let data = try cloudData(savedAt: epoch, sources: [source(name: "From the iPhone")])
        let decision = try AppleCloudConfigurationRead.decide(
            data: data, localSavedAt: epoch.addingTimeInterval(-60))
        guard case .apply(let snapshot) = decision else {
            Issue.record("expected the newer snapshot to be applied, got \(decision)")
            return
        }
        #expect(snapshot.sources.map(\.name) == ["From the iPhone"])
        #expect(snapshot.savedAt == epoch)
    }

    /// A first launch on a television that has applied nothing yet.
    @Test func aFirstLaunchAppliesWhateverIsThere() throws {
        let data = try cloudData(savedAt: epoch, sources: [source()])
        #expect(try AppleCloudConfigurationRead.decide(data: data, localSavedAt: nil) != .notNewer)
    }

    /// The same notification fires repeatedly; re-applying the snapshot already
    /// in place would restore sources over whatever is on screen each time.
    @Test func theSnapshotAlreadyAppliedIsIgnored() throws {
        let data = try cloudData(savedAt: epoch, sources: [source()])
        #expect(try AppleCloudConfigurationRead.decide(data: data, localSavedAt: epoch) == .notNewer)
        #expect(try AppleCloudConfigurationRead.decide(
            data: data, localSavedAt: epoch.addingTimeInterval(1)) == .notNewer)
    }

    /// Signed out of iCloud, or an account that has never published: nothing
    /// stored, no crash, no sync — the same as before this existed.
    @Test func anEmptyStoreIsNotAnError() throws {
        #expect(try AppleCloudConfigurationRead.decide(data: nil, localSavedAt: nil) == .nothingStored)
        #expect(try AppleCloudConfigurationRead.decide(data: nil, localSavedAt: epoch) == .nothingStored)
    }

    @Test func anOversizedPayloadIsRejectedRatherThanDecoded() {
        let data = Data(repeating: 0x7B, count: AppleConfigurationSnapshot.maximumCloudBytes + 1)
        #expect(throws: AppleConfigurationError.tooLarge) {
            try AppleCloudConfigurationRead.decide(data: data, localSavedAt: nil)
        }
    }

    @Test func rubbishInTheStoreThrowsRatherThanApplying() {
        #expect(throws: (any Error).self) {
            try AppleCloudConfigurationRead.decide(data: Data("not a snapshot".utf8), localSavedAt: nil)
        }
    }

    // MARK: - The injectable store

    /// The controller talks to a protocol, so a fake can stand in for iCloud.
    @Test func aFakeStoreStandsInForICloud() throws {
        let store = FakeCloudStore()
        let data = try cloudData(savedAt: epoch, sources: [source(name: "Seeded")])
        store.set(data, forKey: "openstream.configuration.v1")
        #expect(store.synchronize())
        let decision = try AppleCloudConfigurationRead.decide(
            data: store.data(forKey: "openstream.configuration.v1"), localSavedAt: nil)
        guard case .apply(let snapshot) = decision else {
            Issue.record("expected the seeded snapshot to be applied, got \(decision)")
            return
        }
        #expect(snapshot.sources.map(\.name) == ["Seeded"])
    }
}

/// An in-memory `AppleCloudKeyValueStore`, so the read path can be exercised
/// without an iCloud account.
final class FakeCloudStore: AppleCloudKeyValueStore, @unchecked Sendable {
    private var storage: [String: Data] = [:]
    private(set) var synchronizeCount = 0

    func data(forKey key: String) -> Data? { storage[key] }

    func set(_ value: Data?, forKey key: String) { storage[key] = value }

    @discardableResult func synchronize() -> Bool {
        synchronizeCount += 1
        return true
    }
}
