import Foundation
import Observation
import SwiftUI

@MainActor
@Observable
final class AppleConfigurationController {
    private(set) var syncEnabled: Bool
    private(set) var result: String?
    private(set) var isBusy = false
    /// What sync last did here; see `AppleConfigurationSyncStatus`.
    private(set) var status: AppleConfigurationSyncStatus
    private(set) var isSyncing = false
    let sources: AppleSourceStore
    private let settings: AppleSettingsStore
    private let mediaIndex: AppleMediaIndexStore
    private let defaults: UserDefaults
    private let lineupStore: AppleChannelLineupStore
    private let cloud: AppleCloudKeyValueStore
    private let backupKeys: any AppleBackupKeyStoring
    private var pendingWrite: Task<Void, Never>?
    private var pendingLocalChange: Task<Void, Never>?
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
         backupKeys: any AppleBackupKeyStoring = AppleICloudBackupKeychain(),
         lineupStore: AppleChannelLineupStore = .shared) {
        self.sources = sources
        self.settings = settings
        self.mediaIndex = mediaIndex
        self.defaults = defaults
        self.lineupStore = lineupStore
        self.cloud = cloud
        self.backupKeys = backupKeys
        // The Apple TV has no switch to read, so the policy answers for it:
        // always on, and read-only. See `AppleConfigurationSyncPolicy`.
        AppleKeychainStore.adoptDefaultSyncPreference()
        syncEnabled = AppleConfigurationSyncPolicy.isEnabled(
            storedPreference: AppleConfigurationSyncPolicy.storedPreference(in: defaults)
        )
        status = AppleConfigurationSyncStatus.load(from: defaults)
    }

    func start() async {
        guard !started else { return }
        await mediaIndex.load()
        started = true
        heldSources = !sources.sources.isEmpty || !sources.sourceTombstones.isEmpty
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
            publishIfNeeded()
        }
    }

    /// The app came to the front: read what iCloud holds, send this device's
    /// configuration if iCloud lacks it, and look again for sign-ins iCloud
    /// Keychain may have delivered since the retry schedule ended.
    func becameActive() async {
        if syncEnabled { cloud.synchronize() }
        await readCloud()
        retryKeychainNow()
        publishIfNeeded()
    }

    /// Backup & Sync's "Sync Now": read, then send if iCloud lacks this
    /// device's configuration. Same guards as launch.
    func syncNow() async {
        guard !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }
        appleTrace("configuration sync now: enabled=\(syncEnabled) publishes=\(AppleConfigurationSyncPolicy.publishesChanges())")
        guard syncEnabled else {
            result = "Turn on Sync with iCloud first"
            return
        }
        appleTrace("configuration sync now: reading")
        cloud.synchronize()
        await readCloud(fillingEmptyLocal: true)
        retryKeychainNow()
        appleTrace("configuration sync now: deciding whether to send")
        if publishIfNeeded(immediately: true) {
            appleTrace("configuration sync now: sent")
        } else {
            appleTrace("configuration sync now: nothing to send")
            if status.lastError == nil { result = "Up to date with iCloud" }
        }
    }

    /// No Sources' "Restore from iCloud". Turns sync on if the viewer had
    /// turned it off, then pulls what iCloud holds into the empty device.
    func restoreFromCloud() async {
        // After Reset OpenStream this tap is what lets iCloud back in, and
        // what iCloud holds is applied even if this device stamped later.
        defaults.removeObject(forKey: AppleDeviceReset.cloudRestoreHeldKey)
        defaults.removeObject(forKey: Self.savedAtKey)
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
        let payload = try fullPayload()
        let snapshot = payload.snapshot
        let data = passphrase.isEmpty
            ? try AppleBackupEnvelope.seal(payload, key: backupKeys.exportKey())
            : try await AppleBackupEnvelope.sealData(payload, passphrase: passphrase)
        appleTrace("backup export: \(snapshot.sources.count) sources, secrets=included")
        return data
    }

    /// Everything a full backup carries, sign-ins included.
    private func fullPayload() throws -> AppleBackupEnvelope.Payload {
        var secrets = try sources.configurationSecrets()
        secrets.settingsCredentials = try settings.configurationCredentials()
        return AppleBackupEnvelope.Payload(snapshot: try capture(), secrets: secrets)
    }

    /// Set Up from iPhone, sending side: the same content as a full backup.
    func setupTransferPayload(sender: String) throws -> AppleSetupTransferPayload {
        let payload = try fullPayload()
        appleTrace("setup send: prepared \(payload.snapshot.sources.count) sources")
        return AppleSetupTransferPayload(sender: sender, snapshot: payload.snapshot, secrets: payload.secrets)
    }

    /// Set Up from iPhone, receiving side: applied exactly like a backup
    /// import. Returns how many sources came over.
    @discardableResult
    func importSetupTransfer(_ payload: AppleSetupTransferPayload) async throws -> Int {
        isBusy = true
        defer { isBusy = false }
        try await apply(payload.snapshot, secrets: payload.secrets)
        try finishImport(payload.snapshot, trace: "setup import")
        result = "Setup imported"
        return payload.snapshot.sources.count
    }

    private func finishImport(_ snapshot: AppleConfigurationSnapshot, trace: String) throws {
        let ids = Set(snapshot.sources.map(\.id))
        let waiting = sources.sources.filter { ids.contains($0.id) && $0.needsSignIn }.count
        appleTrace("\(trace): \(ids.count - waiting) restored, \(waiting) need sign-in")
        // A deliberate file restore is a new local edit, regardless of the
        // file's date. A reader keeps the imported copy's own clock instead,
        // so the next copy the phone publishes still reads as newer.
        defaults.set(AppleConfigurationSyncPolicy.publishesChanges()
            ? AppleConfigurationSyncPolicy.editStamp(after: localSavedAt) : snapshot.savedAt,
            forKey: Self.savedAtKey)
        lastContent = try contentFingerprint()
        if syncEnabled { scheduleWrite() }
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
        try finishImport(decoded.snapshot, trace: "backup import")
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

    /// One playback save writes several defaults keys. Capture only after
    /// that burst settles, rather than encoding a snapshot for every key.
    @discardableResult
    func localChanged() -> Task<Void, Never>? {
        guard started, !applying else { return nil }
        pendingLocalChange?.cancel()
        let task = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(250)) }
            catch { return }
            guard let self, !Task.isCancelled else { return }
            self.pendingLocalChange = nil
            self.processLocalChange()
        }
        pendingLocalChange = task
        return task
    }

    private func processLocalChange() {
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
            defaults.set(AppleConfigurationSyncPolicy.editStamp(after: localSavedAt), forKey: Self.savedAtKey)
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
        // A queued local edit must stamp its configuration clock before a
        // cloud read decides whether an incoming setup is newer.
        if pendingLocalChange != nil {
            pendingLocalChange?.cancel()
            pendingLocalChange = nil
            processLocalChange()
        }
        do {
            applying = true
            try sources.refreshConfigurationKeychain()
            try settings.restoreConfigurationCredentials([:])
            applying = false
            let decision = try AppleCloudConfigurationRead.decide(
                data: cloud.data(forKey: Self.cloudKey),
                localSavedAt: localSavedAt,
                localIsEmpty: fillingEmptyLocal && sources.sources.isEmpty
            )
            guard case .apply(let snapshot) = decision else {
                appleTrace("configuration sync read: \(decision.traceDescription)")
                if decision == .notNewer {
                    // Settings and sources retain their existing snapshot rule;
                    // playback always reconciles its independent item clocks.
                    if let data = cloud.data(forKey: Self.cloudKey) {
                        let snapshot = try JSONDecoder().decode(AppleConfigurationSnapshot.self, from: data)
                        applying = true
                        restorePlayback(snapshot)
                        applying = false
                        lastContent = try contentFingerprint()
                        if await AppleConfigurationSyncPolicy.playbackContributionOffMain(try capture(), cloud: snapshot) { scheduleWrite() }
                    }
                    updateStatus { $0.recordingReceived(at: .now, sourceCount: self.sources.sources.count) }
                }
                return
            }
            pendingWrite?.cancel()
            try await apply(snapshot, secrets: nil)
            // Sources only this device has, or deletions iCloud has not seen,
            // are a local edit made after this copy: stamp them later than it,
            // or every device that applied it reads the next send as not newer.
            // A copy that still carried retired sources is written again without them.
            let contributesSources = sources.sourceTombstones != snapshot.sourceTombstones
                || !Set(sources.sources.map(\.id)).subtracting(snapshot.sources.map(\.id)).isEmpty
                || snapshot.retiredSourceCount > 0
            defaults.set(contributesSources && AppleConfigurationSyncPolicy.publishesChanges()
                ? AppleConfigurationSyncPolicy.editStamp(after: snapshot.savedAt) : snapshot.savedAt,
                forKey: Self.savedAtKey)
            lastContent = try contentFingerprint()
            let hasPlaybackContribution = await AppleConfigurationSyncPolicy.playbackContributionOffMain(try capture(), cloud: snapshot)
            if contributesSources || hasPlaybackContribution { scheduleWrite() }
            if !sources.sources.isEmpty || !sources.sourceTombstones.isEmpty { heldSources = true }
            appleTrace("configuration sync applied: \(snapshot.sources.count) sources from iCloud")
            updateStatus { $0.recordingReceived(at: .now, sourceCount: self.sources.sources.count) }
            result = "Synced with iCloud"
        } catch {
            applying = false
            result = "Could not restore iCloud configuration"
            updateStatus { $0.recordingError("Could not read the iCloud configuration") }
        }
    }

    func setResult(_ value: String) { result = value }

    private var localSavedAt: Date? { defaults.object(forKey: Self.savedAtKey) as? Date }

    /// A restored source waits signed out for credentials iCloud Keychain has
    /// not delivered yet. Becoming active and iCloud's own changes look again
    /// (`readCloud`); this also looks a few times on its own, because the
    /// keychain can arrive with neither.
    private func scheduleKeychainRetry() {
        guard syncEnabled, AppleConfigurationSyncPolicy.receivesICloudKeychain(), keychainRetry == nil,
              hasSourcesAwaitingKeychain else { return }
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
                self.recordKeychainWaiting()
                if !self.hasSourcesAwaitingKeychain { appleTrace("configuration sync: restored sources signed in from iCloud Keychain") }
            }
            self?.keychainRetry = nil
        }
    }

    private var hasSourcesAwaitingKeychain: Bool { sourcesAwaitingKeychain > 0 }

    private var sourcesAwaitingKeychain: Int {
        sources.sources.filter { $0.needsSignIn && $0.kind != .library }.count
    }

    /// Looks once, right now, for sign-ins iCloud Keychain delivered after the
    /// retry schedule gave up, then starts the schedule again if any are
    /// still missing.
    private func retryKeychainNow() {
        defer { recordKeychainWaiting() }
        guard started, syncEnabled, !applying, hasSourcesAwaitingKeychain else { return }
        applying = true
        do { try sources.refreshConfigurationKeychain() }
        catch { appleTrace("configuration sync: keychain look failed") }
        applying = false
        appleTrace("configuration sync: keychain look on activation, waiting=\(sourcesAwaitingKeychain)")
        scheduleKeychainRetry()
    }

    private func recordKeychainWaiting() {
        updateStatus { $0.recordingSources(self.sources.sources.count, waitingForKeychain: self.sourcesAwaitingKeychain) }
    }

    private func updateStatus(_ change: (AppleConfigurationSyncStatus) -> AppleConfigurationSyncStatus) {
        let updated = change(status)
        guard updated != status else { return }
        status = updated
        updated.save(to: defaults)
    }

    /// Sends this device's configuration when iCloud lacks it
    /// (`AppleConfigurationSyncPolicy.publishesWithoutEdit`). Returns whether
    /// a send was made (`immediately`) or scheduled.
    @discardableResult
    private func publishIfNeeded(immediately: Bool = false) -> Bool {
        guard started, !applying else { return false }
        let stored = cloud.data(forKey: Self.cloudKey)
        let cloudSnapshot: AppleConfigurationSnapshot?
        if let stored {
            guard let decoded = try? JSONDecoder().decode(AppleConfigurationSnapshot.self, from: stored) else {
                appleTrace("configuration sync: iCloud copy unreadable, not replacing it")
                return false
            }
            cloudSnapshot = decoded
        } else {
            cloudSnapshot = nil
        }
        guard let local = try? capture(savedAt: localSavedAt ?? .now),
              AppleConfigurationSyncPolicy.publishesWithoutEdit(
                syncEnabled: syncEnabled, restoreHeld: cloudRestoreHeld,
                local: local, localSavedAt: localSavedAt, cloud: cloudSnapshot) else { return false }
        appleTrace("configuration sync: iCloud \(cloudSnapshot == nil ? "has nothing" : "is behind"), sending \(local.sources.count) sources")
        // Stamp a device that was set up before anything stamped it, so its
        // own copy does not later read as newer than itself.
        if localSavedAt == nil { defaults.set(local.savedAt, forKey: Self.savedAtKey) }
        if immediately { return writeNow() }
        scheduleWrite()
        return true
    }

    private func capture(savedAt: Date? = nil) throws -> AppleConfigurationSnapshot {
        let values = try settings.configurationValues()
        let playback = ApplePlaybackStore(defaults: defaults)
        return AppleConfigurationSnapshot(
            savedAt: savedAt ?? (defaults.object(forKey: Self.savedAtKey) as? Date ?? .now),
            sources: sources.sources, sourceTombstones: sources.sourceTombstones, settings: values,
            playbackProgress: playback.configurationProgress(),
            watchedHistory: playback.configurationWatchedHistory(),
            watchedTombstones: playback.configurationWatchedTombstones(),
            watchlist: mediaIndex.records.filter(\.isFavorite),
            ratings: AppleTitleRatingStore(defaults: defaults).allRatings.mapValues(\.rawValue),
            continueWatchingRemovals: playback.configurationContinueWatchingRemovals(),
            playbackTerminals: playback.configurationPlaybackTerminals(),
            playbackActivity: playback.configurationPlaybackActivity(), lineup: lineupStore.data)
    }

    private func contentFingerprint() throws -> Data {
        var snapshot = try capture(savedAt: .distantPast)
        snapshot.sources = snapshot.sources.map(Self.withoutCheckResults)
        return try AppleConfigurationSnapshot.encoder.encode(snapshot)
    }

    /// Every library scan and source check rewrites these. On their own they
    /// are not an edit worth sending every other device a new setup for.
    private static func withoutCheckResults(_ source: AppleSource) -> AppleSource {
        var copy = source
        copy.lastValidatedAt = nil
        copy.lastValidationFailureAt = nil
        copy.discoveredItemCount = nil
        return copy
    }

    private func apply(_ snapshot: AppleConfigurationSnapshot, secrets: AppleConfigurationSecrets?) async throws {
        try traced("validate") { try snapshot.validate() }
        let values = snapshot.settings
        // Validate settings before any store is changed.
        try traced("settings check") {
            for (key, value) in values where AppleSettingsStore.configurationKeys.contains(key) {
                _ = try AppleSettingsStore.configurationValue(value)
            }
        }
        applying = true
        defer { applying = false }
        if let lineup = snapshot.lineup { try traced("lineup") { try lineupStore.importData(lineup) } }
        // Sources and settings are the setup; a failure there stops the import
        // before anything else changes. What follows is kept on a best-effort
        // basis: a part this device cannot keep is skipped and traced, so the
        // rest still arrives (build 17's Apple TV lost the whole setup to its
        // unwritable Application Support).
        // Merged, never replaced: a source leaves through its tombstone, so
        // one only this device has (an Apple TV's own) survives every read.
        sources.mergeSourceTombstones(snapshot.sourceTombstones)
        try traced("sources") {
            let signedOut = try sources.restoreConfigurationSources(snapshot.sources, secrets: secrets)
            if signedOut > 0 { appleTraceFailure("configuration apply: \(signedOut) sources kept signed out") }
        }
        try traced("settings") {
            try settings.restoreConfiguration(snapshot.settings.merging(values) { _, incoming in incoming })
        }
        if let secrets {
            do { try settings.restoreConfigurationCredentials(secrets.settingsCredentials) }
            catch { appleTraceFailure("configuration apply: skipped settings sign-ins: \(appleErrorLabel(error))") }
        }
        restorePlayback(snapshot)
        AppleTitleRatingStore(defaults: defaults).restoreConfigurationRatings(snapshot.ratings)
        do { try await mediaIndex.restoreConfigurationWatchlist(snapshot.watchlist) }
        catch { appleTraceFailure("configuration apply: skipped the watchlist: \(appleErrorLabel(error))") }
    }

    /// Runs one required step of `apply`, tracing which step failed and how.
    private func traced(_ step: String, _ body: () throws -> Void) throws {
        do { try body() }
        catch {
            appleTraceFailure("configuration apply: \(step) failed: \(appleErrorLabel(error))")
            throw error
        }
    }

    /// Reset OpenStream leaves this device out of iCloud, both ways, until
    /// the viewer taps Restore from iCloud: an empty device must not publish
    /// over the other devices' configuration, nor refill itself on its own.
    private var cloudRestoreHeld: Bool { defaults.bool(forKey: AppleDeviceReset.cloudRestoreHeldKey) }

    private func restorePlayback(_ snapshot: AppleConfigurationSnapshot) {
        let playback = ApplePlaybackStore(defaults: defaults)
        playback.restoreConfigurationPlaybackTerminals(snapshot.playbackTerminals)
        playback.restoreConfigurationPlaybackActivity(snapshot.playbackActivity)
        playback.restoreConfigurationProgress(snapshot.playbackProgress)
        playback.restoreConfigurationWatchedHistory(
            snapshot.watchedHistory, tombstones: snapshot.watchedTombstones)
        playback.restoreConfigurationContinueWatchingRemovals(
            snapshot.continueWatchingRemovals)
    }

    private func scheduleWrite() {
        guard AppleConfigurationSyncPolicy.publishesChanges(), !cloudRestoreHeld else { return }
        pendingWrite?.cancel()
        pendingWrite = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(2)) }
            catch { return }
            guard let self, self.syncEnabled, !Task.isCancelled else { return }
            // A background save keeps whatever the viewer last asked for on
            // screen ("Configuration imported" was replaced two seconds later).
            self.writeNow(announce: false)
        }
    }

    /// Writes the snapshot to iCloud now, unless `mayPublish` keeps iCloud's
    /// sources. Returns whether it wrote. `announce` shows the saved message.
    @discardableResult
    private func writeNow(announce: Bool = true) -> Bool {
        guard syncEnabled, AppleConfigurationSyncPolicy.publishesChanges(), !cloudRestoreHeld else { return false }
        pendingWrite?.cancel()
        do {
            let storedData = cloud.data(forKey: Self.cloudKey)
            let stored = storedData.flatMap { try? JSONDecoder().decode(AppleConfigurationSnapshot.self, from: $0) }
            // Another device's newer copy has not been applied here yet. Sent
            // now, this older one would replace its edits and carry an older
            // clock that devices which applied it ignore. The read on iCloud's
            // change notification applies it, then sends what this device adds.
            // A copy that read rejects is never applied, so it must not hold sends.
            if let stored, stored.savedAt > localSavedAt ?? .distantPast,
               (try? AppleCloudConfigurationRead.decide(data: storedData, localSavedAt: localSavedAt)) != nil {
                appleTrace("configuration sync: iCloud has a newer copy, reading it before sending")
                return false
            }
            guard AppleConfigurationSyncPolicy.mayPublish(
                localSourceCount: sources.sources.count, heldSourcesSinceLaunch: heldSources,
                storedSourceCount: stored?.sources.count ?? 0) else {
                appleTrace("configuration sync: kept iCloud's sources, this device has none yet")
                return false
            }
            let local = try capture()
            let data = try (stored.map { $0.merging(local) } ?? local).cloudData()
            try sources.prepareConfigurationKeychain()
            cloud.set(data, forKey: Self.cloudKey)
            cloud.synchronize()
            appleTrace("configuration sync: sent \(sources.sources.count) sources to iCloud")
            updateStatus { $0.recordingSent(at: .now, sourceCount: self.sources.sources.count) }
            if announce { result = "Configuration saved for iCloud" }
            return true
        } catch {
            result = error.localizedDescription
            updateStatus { $0.recordingError(error.localizedDescription) }
            return false
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
                #if DEBUG
                if let controller { await AppleDebugBackupRestore.restorePendingIfNeeded(controller: controller) }
                #endif
                await controller?.start()
                #if DEBUG
                if let controller { await AppleDebugBackupRestore.resumeICloudIfRequested(controller: controller) }
                #endif
            }
            .onReceive(NotificationCenter.default.publisher(for: AppleChannelLineupStore.didChange).receive(on: RunLoop.main)) { _ in
                controller?.localChanged()
            }
            .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
                controller?.localChanged()
            }
            .onReceive(NotificationCenter.default.publisher(for: NSUbiquitousKeyValueStore.didChangeExternallyNotification)) { _ in
                Task { await controller?.readCloud(fillingEmptyLocal: true) }
            }
            .onChange(of: mediaIndex.records.filter(\.isFavorite)) { _, _ in controller?.localChanged() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await controller?.becameActive() } }
            }
    }
}

/// What iCloud sync last did here, in one or two short lines: under the
/// Backup & Sync switch, and in the Apple TV's Sources pane.
struct AppleConfigurationSyncStatusLines: View {
    let status: AppleConfigurationSyncStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(status.activityLine { AppleConfigurationSyncStatus.time($0) })
            Text(status.detailLine)
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("backup.sync.status")
    }
}
