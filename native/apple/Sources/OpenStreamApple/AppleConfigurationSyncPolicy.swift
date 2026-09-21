import Foundation

/// Where iCloud configuration sync is the viewer's choice, and where it simply
/// runs.
public enum AppleConfigurationSyncMode: Sendable, Equatable {
    /// iPhone, iPad, Mac, Vision Pro: the Backup screen's "Sync with iCloud"
    /// switch decides, and the device publishes its own changes.
    case viewerChoice
    /// Apple TV: always on, never publishes. A focus-driven remote has nowhere
    /// sensible to put that switch, and the owner asked for the television to
    /// "sync with iCloud to sync the settings and setup from iOS" without being
    /// set up at all — the way Apple's own tvOS apps quietly inherit their
    /// iCloud settings. Read-only, so a stray change on the television can
    /// never overwrite the phone's configuration.
    case automaticReadOnly
}

public enum AppleConfigurationSyncPolicy: Sendable {
    public static let current: AppleConfigurationSyncMode = {
        #if os(tvOS)
        .automaticReadOnly
        #else
        .viewerChoice
        #endif
    }()

    /// True where sync runs whether or not anyone asked for it.
    public static var isAlwaysOn: Bool { current == .automaticReadOnly }

    /// Is sync on? `automaticReadOnly` ignores the stored preference, which on
    /// the Apple TV is never written because nothing there can write it.
    public static func isEnabled(storedPreference: Bool, mode: AppleConfigurationSyncMode = current) -> Bool {
        mode == .automaticReadOnly || storedPreference
    }

    /// May this device publish its own configuration to iCloud?
    public static func publishesChanges(mode: AppleConfigurationSyncMode = current) -> Bool {
        mode != .automaticReadOnly
    }

    /// May the viewer be offered the switch at all? Drives nothing on its own —
    /// the Backup screen is already `#if !os(tvOS)` — but keeps the answer in
    /// one place rather than in a platform check next to each caller.
    public static func offersToggle(mode: AppleConfigurationSyncMode = current) -> Bool {
        mode == .viewerChoice
    }
}

/// The slice of `NSUbiquitousKeyValueStore` the configuration sync uses.
///
/// A protocol only so the apply path can be tested: the simulators on this Mac
/// have no iCloud account, and `NSUbiquitousKeyValueStore.default` silently
/// drops writes without one, so a real round trip cannot be exercised here.
public protocol AppleCloudKeyValueStore: AnyObject {
    func data(forKey key: String) -> Data?
    func set(_ value: Data?, forKey key: String)
    @discardableResult func synchronize() -> Bool
}

extension NSUbiquitousKeyValueStore: AppleCloudKeyValueStore {}

/// What the sync should do with whatever the key-value store currently holds.
///
/// Pulled out of `AppleConfigurationController.readCloud` so the rule the
/// Apple TV depends on — apply a snapshot that is newer than the one this
/// device last applied, ignore anything else — can be tested without an iCloud
/// account. See `AppleConfigurationSyncTests`.
public enum AppleCloudConfigurationRead: Equatable, Sendable {
    /// A valid snapshot, newer than this device's, ready to apply.
    case apply(AppleConfigurationSnapshot)
    /// Nothing has ever been published — iCloud is off, or signed out, or the
    /// account simply has no OpenStream configuration yet.
    case nothingStored
    /// The account's snapshot is the one already applied here, or older.
    case notNewer

    public var traceDescription: String {
        switch self {
        case .apply(let snapshot): return "apply \(snapshot.sources.count) sources"
        case .nothingStored: return "nothing stored"
        case .notNewer: return "not newer"
        }
    }

    /// Throws `AppleConfigurationError.tooLarge` for an oversized payload and
    /// whatever decoding or validation reports for a corrupt one, so the caller
    /// surfaces the same message it always has.
    public static func decide(data: Data?, localSavedAt: Date?) throws -> AppleCloudConfigurationRead {
        guard let data else { return .nothingStored }
        guard data.count <= AppleConfigurationSnapshot.maximumCloudBytes else {
            throw AppleConfigurationError.tooLarge
        }
        let snapshot = try JSONDecoder().decode(AppleConfigurationSnapshot.self, from: data)
        try snapshot.validate()
        guard snapshot.savedAt > (localSavedAt ?? .distantPast) else { return .notNewer }
        return .apply(snapshot)
    }
}
