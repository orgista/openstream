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
    private var pendingWrite: Task<Void, Never>?
    private var lastContent: Data?
    private var applying = false
    private var started = false
    private static let cloudKey = "openstream.configuration.v1"
    private static let savedAtKey = "openstream.backup.savedAt.v1"

    init(sources: AppleSourceStore, settings: AppleSettingsStore, mediaIndex: AppleMediaIndexStore,
         defaults: UserDefaults = .standard, cloud: AppleCloudKeyValueStore = NSUbiquitousKeyValueStore.default) {
        self.sources = sources
        self.settings = settings
        self.mediaIndex = mediaIndex
        self.defaults = defaults
        self.cloud = cloud
        // The Apple TV has no switch to read, so the policy answers for it:
        // always on, and read-only. See `AppleConfigurationSyncPolicy`.
        syncEnabled = AppleConfigurationSyncPolicy.isEnabled(
            storedPreference: defaults.bool(forKey: AppleKeychainStore.syncPreferenceKey)
        )
    }

    func start() async {
        guard !started else { return }
        await mediaIndex.load()
        started = true
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
            await readCloud()
        }
    }

    func export(passphrase: String) async throws -> Data {
        isBusy = true
        defer { isBusy = false }
        let snapshot = try capture()
        var secrets = AppleConfigurationSecrets()
        if !passphrase.isEmpty {
            secrets = try sources.configurationSecrets()
            secrets.settingsCredentials = try settings.configurationCredentials()
            secrets.privateSettings = try settings.configurationValues().filter {
                AppleSettingsStore.configurationURLKeys.contains($0.key)
            }
        }
        return try await AppleConfigurationFile.exportData(snapshot: snapshot, secrets: secrets, passphrase: passphrase)
    }

    func restore(_ data: Data, passphrase: String) async throws {
        isBusy = true
        defer { isBusy = false }
        let decoded = try await AppleConfigurationFile.importData(data, passphrase: passphrase)
        try await apply(decoded.snapshot, secrets: decoded.secrets)
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

    func readCloud() async {
        guard started, syncEnabled, !applying else {
            appleTrace("configuration sync read skipped: started=\(started) enabled=\(syncEnabled) applying=\(applying)")
            return
        }
        do {
            applying = true
            try sources.refreshConfigurationKeychain()
            try settings.restoreConfigurationCredentials([:])
            applying = false
            let decision = try AppleCloudConfigurationRead.decide(
                data: cloud.data(forKey: Self.cloudKey),
                localSavedAt: defaults.object(forKey: Self.savedAtKey) as? Date
            )
            guard case .apply(let snapshot) = decision else {
                appleTrace("configuration sync read: \(decision.traceDescription)")
                return
            }
            pendingWrite?.cancel()
            try await apply(snapshot, secrets: nil, mergeSources: false)
            defaults.set(snapshot.savedAt, forKey: Self.savedAtKey)
            lastContent = try contentFingerprint()
            appleTrace("configuration sync applied: \(snapshot.sources.count) sources from iCloud")
            result = "Synced with iCloud"
        } catch { applying = false; result = "Could not restore iCloud configuration" }
    }

    func setResult(_ value: String) { result = value }

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
        try settings.restoreConfiguration(snapshot.settings.merging(values) { _, incoming in incoming })
        if let secrets { try settings.restoreConfigurationCredentials(secrets.settingsCredentials) }
        ApplePlaybackStore(defaults: defaults).restoreConfigurationProgress(snapshot.playbackProgress)
        ApplePlaybackStore(defaults: defaults).restoreConfigurationWatchedHistory(
            snapshot.watchedHistory, tombstones: snapshot.watchedTombstones)
        AppleTitleRatingStore(defaults: defaults).restoreConfigurationRatings(snapshot.ratings)
        try await mediaIndex.restoreConfigurationWatchlist(snapshot.watchlist)
    }

    private func scheduleWrite() {
        guard AppleConfigurationSyncPolicy.publishesChanges() else { return }
        pendingWrite?.cancel()
        pendingWrite = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(2)) }
            catch { return }
            guard let self, self.syncEnabled, !Task.isCancelled else { return }
            do {
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
                Task { await controller?.readCloud() }
            }
            .onChange(of: mediaIndex.records.filter(\.isFavorite)) { _, _ in controller?.localChanged() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await controller?.readCloud() } }
            }
    }
}
