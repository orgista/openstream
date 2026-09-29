import Foundation
import Observation
import SwiftUI

@MainActor
@Observable
final class AppleConfigurationController {
    private(set) var syncEnabled: Bool
    private(set) var result: String?
    private(set) var isBusy = false
    let sources: AppleSourceStore
    private let settings: AppleSettingsStore
    private let mediaIndex: AppleMediaIndexStore
    private let defaults: UserDefaults
    private let cloud: AppleCloudKeyValueStore
    private let backupKeys: any AppleBackupKeyStoring
    private var pendingWrite: Task<Void, Never>?
    private var keychainRetry: Task<Void, Never>?
    /// Whether this device has had any source since launch. See
    /// `AppleConfigurationSyncPolicy.mayPublish`.
    private var heldSources = false
    private var lastContent: Data?
    private var applying = false
    private var started = false
    private static let cloudKey = "openstream.configuration.v1"
    private static let savedAtKey = "openstream.backup.savedAt.v1"

    init(sources: AppleSourceStore, settings: AppleSettingsStore, mediaIndex: AppleMediaIndexStore,
         defaults: UserDefaults = .standard, cloud: AppleCloudKeyValueStore = NSUbiquitousKeyValueStore.default,
         backupKeys: any AppleBackupKeyStoring = AppleICloudBackupKeychain()) {
        self.sources = sources
        self.settings = settings
        self.mediaIndex = mediaIndex
        self.defaults = defaults
        self.cloud = cloud
        self.backupKeys = backupKeys
        // The Apple TV has no switch to read, so the policy answers for it:
        // always on, and read-only. See `AppleConfigurationSyncPolicy`.
        AppleKeychainStore.adoptDefaultSyncPreference()
        syncEnabled = AppleConfigurationSyncPolicy.isEnabled(
            storedPreference: AppleConfigurationSyncPolicy.storedPreference(in: defaults)
        )
    }

    func start() async {
        guard !started else { return }
        await mediaIndex.load()
        started = true
        heldSources = !sources.sources.isEmpty
        lastContent = try? contentFingerprint()
        // A device that syncs without ever being asked still has to move its
        // existing credentials into the synchronizing keychain. They were
        // written ThisDeviceOnly, and a synchronizable query does not find a
        // ThisDeviceOnly item — the Apple TV would have looked signed out of
        // every source it had already signed in to. Runs once: the migration
        // writes the preference it reads.
        if AppleConfigurationSyncPolicy.isAlwaysOn,
           !defaults.bool(forKey: AppleKeychainStore.syncPreferenceKey) {
            do {
                try AppleKeychainStore.setSynchronizationEnabled(true)
                appleTrace("configuration sync: migrated the keychain to synchronizing")
            } catch {
                appleTrace("configuration sync: keychain migration failed, reading local credentials only")
            }
        }
        appleTrace("configuration sync start: enabled=\(syncEnabled) publishes=\(AppleConfigurationSyncPolicy.publishesChanges())")
        if syncEnabled {
            cloud.synchronize()
            await readCloud(fillingEmptyLocal: true)
        }
    }

    /// No Sources' "Restore from iCloud". Turns sync on if the viewer had
    /// turned it off, then pulls what iCloud holds into the empty device.
    func restoreFromCloud() async {
        // After Reset OpenStream this tap is what lets iCloud back in.
        defaults.removeObject(forKey: AppleDeviceReset.cloudRestoreHeldKey)
        if !syncEnabled { await setSyncEnabled(true) }
        guard syncEnabled else { return }
        cloud.synchronize()
        await readCloud(fillingEmptyLocal: true)
    }

    /// A full backup, sign-ins included, always sealed: with this Apple
    /// Account's iCloud Keychain backup key, or with `passphrase` when one is
    /// given (for a device on another Apple Account). Throws
    /// `backupKeyUnavailable` when there is no passphrase and no key can be kept.
    func export(passphrase: String) async throws -> Data {
        isBusy = true
        defer { isBusy = false }
        let snapshot = try capture()
        var secrets = try sources.configurationSecrets()
        secrets.settingsCredentials = try settings.configurationCredentials()
        secrets.privateSettings = try settings.configurationValues().filter {
            AppleSettingsStore.configurationURLKeys.contains($0.key)
        }
        let payload = AppleBackupEnvelope.Payload(snapshot: snapshot, secrets: secrets)
        let data = passphrase.isEmpty
            ? try AppleBackupEnvelope.seal(payload, key: backupKeys.exportKey())
            : try await AppleBackupEnvelope.sealData(payload, passphrase: passphrase)
        appleTrace("backup export: \(snapshot.sources.count) sources, secrets=included")
        return data
    }

    /// What the import sheet can show before Import: the snapshot when the
    /// file is readable now, whether it wants a passphrase, or why it cannot
    /// be opened on this device.
    func inspectBackup(_ data: Data) throws -> AppleBackupPreview {
        guard data.count <= 10_000_000 else { throw AppleConfigurationError.tooLarge }
        if let envelope = AppleBackupEnvelope.header(of: data) {
            switch envelope.mode {
            case .passphrase:
                return AppleBackupPreview(snapshot: nil, needsPassphrase: true, failure: nil)
            case .iCloudKey:
                do {
                    let payload = try envelope.open(key: try? backupKeys.existingKey(), passphrase: "")
                    return AppleBackupPreview(snapshot: payload.snapshot, needsPassphrase: false, failure: nil)
                } catch let error as AppleConfigurationError {
                    return AppleBackupPreview(snapshot: nil, needsPassphrase: false, failure: error)
                }
            }
        }
        let file = try AppleConfigurationFile.inspect(data)
        return AppleBackupPreview(snapshot: file.snapshot, needsPassphrase: file.isEncrypted, failure: nil)
    }

    func restore(_ data: Data, passphrase: String) async throws {
        isBusy = true
        defer { isBusy = false }
        let decoded: (snapshot: AppleConfigurationSnapshot, secrets: AppleConfigurationSecrets?)
        if let envelope = AppleBackupEnvelope.header(of: data) {
            let key = envelope.mode == .iCloudKey ? try? backupKeys.existingKey() : nil
            let payload = try await envelope.openData(key: key, passphrase: passphrase)
            decoded = (payload.snapshot, payload.secrets)
        } else {
            decoded = try await AppleConfigurationFile.importData(data, passphrase: passphrase)
        }
        try await apply(decoded.snapshot, secrets: decoded.secrets)
        let ids = Set(decoded.snapshot.sources.map(\.id))
        let waiting = sources.sources.filter { ids.contains($0.id) && $0.needsSignIn }.count
        appleTrace("backup import: \(ids.count - waiting) restored, \(waiting) need sign-in")
        // A deliberate file restore is a new local edit, regardless of the file's date.
        defaults.set(Date.now, forKey: Self.savedAtKey)
        lastContent = try contentFingerprint()
        if syncEnabled { scheduleWrite() }
        result = "Configuration imported"
    }

    func setSyncEnabled(_ enabled: Bool) async {
        // Nothing on the Apple TV can reach this, but if anything ever did,
        // the television's answer is not the viewer's to change.
        guard AppleConfigurationSyncPolicy.offersToggle(), enabled != syncEnabled else { return }
        do {
            try AppleKeychainStore.setSynchronizationEnabled(enabled)
            syncEnabled = enabled
            pendingWrite?.cancel()
            if enabled {
                cloud.synchronize()
                await readCloud()
                scheduleWrite()
            }
            result = enabled ? "iCloud sync on" : "iCloud sync off"
        } catch { result = "Could not update Keychain sync" }
    }

    func localChanged() {
        guard started, !applying else { return }
        if !sources.sources.isEmpty { heldSources = true }
        do {
            let content = try contentFingerprint()
            guard content != lastContent else { return }
            lastContent = content
            // A reader never stamps a local edit. `savedAt` is how `readCloud`
            // decides whether the cloud snapshot is newer than this device's
            // configuration; on the Apple TV it means "the snapshot I last
            // applied", so a setting nudged with the remote cannot leave the
            // television permanently ahead of the phone and stop it syncing.
            guard AppleConfigurationSyncPolicy.publishesChanges() else { return }
            defaults.set(Date.now, forKey: Self.savedAtKey)
            if syncEnabled { scheduleWrite() }
        } catch { result = "Could not prepare configuration" }
    }

    /// `fillingEmptyLocal`: apply a snapshot with sources to a device that has
    /// none even when it is not newer (launch, iCloud's own change, Restore).
    func readCloud(fillingEmptyLocal: Bool = false) async {
        defer { scheduleKeychainRetry() }
        guard started, syncEnabled, !applying else {
            appleTrace("configuration sync read skipped: started=\(started) enabled=\(syncEnabled) applying=\(applying)")
            return
        }
        guard !cloudRestoreHeld else {
            appleTrace("configuration sync read held: reset, waiting for Restore from iCloud")
            return
        }
        do {
            applying = true
            try sources.refreshConfigurationKeychain()
            try settings.restoreConfigurationCredentials([:])
            applying = false
            let decision = try AppleCloudConfigurationRead.decide(
                data: cloud.data(forKey: Self.cloudKey),
                localSavedAt: defaults.object(forKey: Self.savedAtKey) as? Date,
                localIsEmpty: fillingEmptyLocal && sources.sources.isEmpty
            )
            guard case .apply(let snapshot) = decision else {
                appleTrace("configuration sync read: \(decision.traceDescription)")
                return
            }
            pendingWrite?.cancel()
            try await apply(snapshot, secrets: nil, mergeSources: false)
            defaults.set(snapshot.savedAt, forKey: Self.savedAtKey)
            lastContent = try contentFingerprint()
            if !sources.sources.isEmpty { heldSources = true }
            appleTrace("configuration sync applied: \(snapshot.sources.count) sources from iCloud")
            result = "Synced with iCloud"
        } catch { applying = false; result = "Could not restore iCloud configuration" }
    }

    func setResult(_ value: String) { result = value }

    /// A restored source waits signed out for credentials iCloud Keychain has
    /// not delivered yet. Becoming active and iCloud's own changes look again
    /// (`readCloud`); this also looks a few times on its own, because the
    /// keychain can arrive with neither.
    private func scheduleKeychainRetry() {
        guard syncEnabled, keychainRetry == nil, hasSourcesAwaitingKeychain else { return }
        keychainRetry = Task { [weak self] in
            for delay in AppleConfigurationSyncPolicy.keychainRetryDelays {
                do { try await Task.sleep(for: delay) } catch { return }
                guard let self else { return }
                guard self.syncEnabled, self.hasSourcesAwaitingKeychain else { break }
                guard !self.applying else { continue }
                self.applying = true
                do { try self.sources.refreshConfigurationKeychain() }
                catch { appleTrace("configuration sync: keychain look failed") }
                self.applying = false
                if !self.hasSourcesAwaitingKeychain { appleTrace("configuration sync: restored sources signed in from iCloud Keychain") }
            }
            self?.keychainRetry = nil
        }
    }

    private var hasSourcesAwaitingKeychain: Bool {
        sources.sources.contains { $0.needsSignIn && $0.kind != .library }
    }

    private func capture(savedAt: Date? = nil) throws -> AppleConfigurationSnapshot {
        var values = try settings.configurationValues()
        for key in AppleSettingsStore.configurationURLKeys {
            guard let data = values[key], let text = try AppleSettingsStore.configurationValue(data) as? String,
                  let url = URL(string: text), !text.isEmpty else { continue }
            let address = AppleConfigurationSnapshot.publicAddress(url).absoluteString
            values[key] = try PropertyListSerialization.data(fromPropertyList: [address], format: .binary, options: 0)
        }
        return AppleConfigurationSnapshot(
            savedAt: savedAt ?? (defaults.object(forKey: Self.savedAtKey) as? Date ?? .now),
            sources: sources.sources, settings: values,
            playbackProgress: ApplePlaybackStore(defaults: defaults).configurationProgress(),
            watchedHistory: ApplePlaybackStore(defaults: defaults).configurationWatchedHistory(),
            watchedTombstones: ApplePlaybackStore(defaults: defaults).configurationWatchedTombstones(),
            watchlist: mediaIndex.records.filter(\.isFavorite),
            ratings: AppleTitleRatingStore(defaults: defaults).allRatings.mapValues(\.rawValue))
    }

    private func contentFingerprint() throws -> Data {
        try AppleConfigurationSnapshot.encoder.encode(capture(savedAt: .distantPast))
    }

    private func apply(_ snapshot: AppleConfigurationSnapshot, secrets: AppleConfigurationSecrets?, mergeSources: Bool = true) async throws {
        try snapshot.validate()
        var values = snapshot.settings
        if let secrets {
            for (key, value) in secrets.privateSettings where AppleSettingsStore.configurationURLKeys.contains(key) {
                values[key] = value
            }
        } else if syncEnabled {
            values.merge(try settings.synchronizedConfigurationURLs()) { _, incoming in incoming }
        }
        // Validate settings before any store is changed.
        for (key, value) in values where AppleSettingsStore.configurationKeys.contains(key) {
            _ = try AppleSettingsStore.configurationValue(value)
        }
        applying = true
        defer { applying = false }
        try sources.restoreConfigurationSources(snapshot.sources, secrets: secrets, merge: mergeSources)
        sources.refreshRestoredManifests(ids: snapshot.sources.map(\.id))
        try settings.restoreConfiguration(snapshot.settings.merging(values) { _, incoming in incoming })
        if let secrets { try settings.restoreConfigurationCredentials(secrets.settingsCredentials) }
        ApplePlaybackStore(defaults: defaults).restoreConfigurationProgress(snapshot.playbackProgress)
        ApplePlaybackStore(defaults: defaults).restoreConfigurationWatchedHistory(
            snapshot.watchedHistory, tombstones: snapshot.watchedTombstones)
        AppleTitleRatingStore(defaults: defaults).restoreConfigurationRatings(snapshot.ratings)
        try await mediaIndex.restoreConfigurationWatchlist(snapshot.watchlist)
    }

    /// Reset OpenStream leaves this device out of iCloud, both ways, until
    /// the viewer taps Restore from iCloud: an empty device must not publish
    /// over the other devices' configuration, nor refill itself on its own.
    private var cloudRestoreHeld: Bool { defaults.bool(forKey: AppleDeviceReset.cloudRestoreHeldKey) }

    private func scheduleWrite() {
        guard AppleConfigurationSyncPolicy.publishesChanges(), !cloudRestoreHeld else { return }
        pendingWrite?.cancel()
        pendingWrite = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(2)) }
            catch { return }
            guard let self, self.syncEnabled, !Task.isCancelled else { return }
            do {
                let stored = self.cloud.data(forKey: Self.cloudKey)
                    .flatMap { try? JSONDecoder().decode(AppleConfigurationSnapshot.self, from: $0) }
                guard AppleConfigurationSyncPolicy.mayPublish(
                    localSourceCount: self.sources.sources.count, heldSourcesSinceLaunch: self.heldSources,
                    storedSourceCount: stored?.sources.count ?? 0) else {
                    appleTrace("configuration sync: kept iCloud's sources, this device has none yet")
                    return
                }
                let data = try self.capture().cloudData()
                try self.sources.prepareConfigurationKeychain()
                try self.settings.prepareConfigurationKeychain()
                self.cloud.set(data, forKey: Self.cloudKey)
                self.cloud.synchronize()
                self.result = "Configuration saved for iCloud"
            } catch { self.result = error.localizedDescription }
        }
    }
}


@MainActor
struct AppleConfigurationSync: ViewModifier {
    @Binding var controller: AppleConfigurationController?
    let sources: AppleSourceStore
    let settings: AppleSettingsStore
    let mediaIndex: AppleMediaIndexStore
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content
            .task {
                if controller == nil {
                    controller = AppleConfigurationController(sources: sources, settings: settings, mediaIndex: mediaIndex)
                }
                await controller?.start()
            }
            .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
                controller?.localChanged()
            }
            .onReceive(NotificationCenter.default.publisher(for: NSUbiquitousKeyValueStore.didChangeExternallyNotification)) { _ in
                Task { await controller?.readCloud(fillingEmptyLocal: true) }
            }
            .onChange(of: mediaIndex.records.filter(\.isFavorite)) { _, _ in controller?.localChanged() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await controller?.readCloud() } }
            }
    }
}
