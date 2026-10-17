#if DEBUG
import Foundation

/// `-OpenStreamRestoreBackup <path> -OpenStreamRestorePassphraseFile <path>`:
/// imports a passphrase backup through Backup & Sync's own restore, so a test
/// device (DevTV has no file picker) gets the owner's setup and library.
/// Paths are relative to the app's home (container). Debug builds only. Both
/// files are read and deleted in `App.init`.
///
/// The device is then held out of iCloud the way Reset holds it, so another
/// device's configuration does not replace the restored one mid-measurement;
/// Restore from iCloud lets iCloud back in.
@MainActor
public enum AppleDebugBackupRestore {
    static let backupKey = "OpenStreamRestoreBackup"
    static let passphraseKey = "OpenStreamRestorePassphraseFile"
    private static var pending: (data: Data, passphrase: String)?

    public static func captureIfRequested(defaults: UserDefaults = .standard, fileManager: FileManager = .default) {
        guard let path = defaults.string(forKey: backupKey), !path.isEmpty else { return }
        let home = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        let backup = URL(fileURLWithPath: path, relativeTo: home)
        let passFile = defaults.string(forKey: passphraseKey).map { URL(fileURLWithPath: $0, relativeTo: home) }
        defer {
            try? fileManager.removeItem(at: backup)
            if let passFile { try? fileManager.removeItem(at: passFile) }
        }
        guard let data = try? Data(contentsOf: backup) else {
            appleTrace("backup restore hook: cannot read \(backup.lastPathComponent)")
            return
        }
        let passphrase = passFile.flatMap { try? String(contentsOf: $0, encoding: .utf8) }?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        pending = (data, passphrase)
    }

    /// `-OpenStreamResumeICloudSync YES`: lets a device the hook below held
    /// back into iCloud at launch, as Restore from iCloud does.
    static let resumeKey = "OpenStreamResumeICloudSync"

    static func resumeICloudIfRequested(controller: AppleConfigurationController, defaults: UserDefaults = .standard) async {
        guard defaults.bool(forKey: resumeKey) else { return }
        appleTrace("backup restore hook: resuming iCloud sync")
        await controller.restoreFromCloud()
    }

    static func restorePendingIfNeeded(controller: AppleConfigurationController, defaults: UserDefaults = .standard) async {
        guard let pending else { return }
        self.pending = nil
        defaults.set(true, forKey: AppleDeviceReset.cloudRestoreHeldKey)
        do {
            try await controller.restore(pending.data, passphrase: pending.passphrase)
        } catch {
            appleTraceFailure("backup restore hook: \(appleErrorLabel(error))")
        }
    }
}
#endif
