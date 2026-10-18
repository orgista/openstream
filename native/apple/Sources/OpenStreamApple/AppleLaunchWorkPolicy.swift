import Foundation

public enum AppleLaunchWorkPolicy: Sendable {
    public static let backgroundPriority: TaskPriority = .utility

    /// Work that can wait (the Top 10 charts, the Top Shelf snapshot) starts this long after the process did, so it
    /// does not compete with the first frame, the first rows and the hero's art (F8: rows within 2 s on the phone).
    public static let launchWindow: Duration = .seconds(2)

    /// How much of the launch window is left `processAge` into the process.
    public static func remainingLaunchWindow(processAge: Duration?) -> Duration {
        guard let processAge else { return .zero }
        return max(.zero, launchWindow - processAge)
    }

    public static func scanDelay(hasPersistedIndex: Bool) -> Duration {
        return hasPersistedIndex ? .seconds(1) : .zero
    }

    public static func shouldRescan(published: Bool, sourceDigest: String, now: Date, defaults: UserDefaults = .standard) -> Bool {
        guard published else { return true }
        let dict = defaults.dictionary(forKey: "openstream.library.lastScan.v1") as? [String: TimeInterval]
        if let timestamp = dict?[sourceDigest] {
            let lastScan = Date(timeIntervalSince1970: timestamp)
            let age = now.timeIntervalSince(lastScan)
            // A scan stamped in the future (the clock moved back) is not
            // fresh: rescan rather than trust it until the clock catches up
            // (a second of slack for the round trip through the stored Double).
            if age >= -1, age <= 600 {
                appleTrace("library scan skipped: index is \(Int(age)) s old")
                return false
            }
        }
        return true
    }
    
    public static func recordScan(sourceDigest: String, date: Date, defaults: UserDefaults = .standard) {
        var dict = defaults.dictionary(forKey: "openstream.library.lastScan.v1") as? [String: TimeInterval] ?? [:]
        dict[sourceDigest] = date.timeIntervalSince1970
        defaults.set(dict, forKey: "openstream.library.lastScan.v1")
    }
}
