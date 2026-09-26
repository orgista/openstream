import Foundation
import Testing
@testable import OpenStreamApple

/// Edge cases the base `AppleLaunchWorkPolicyTests` suite does not cover: the
/// exact 10-minute freshness boundary, a corrupted/clock-skewed defaults
/// entry, overwriting a previous scan, and an empty digest key.
@Suite("AppleLaunchWorkPolicy Tests — edge cases")
struct AppleLaunchWorkPolicyEdgeTests {

    @Test("shouldRescan is false exactly at the 10-minute boundary (age == 600s)")
    func testExactlyAtTheBoundaryCountsAsFresh() {
        let now = Date()
        let suiteName = "testExactlyAtTheBoundary.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let digest = "digest-boundary"
        AppleLaunchWorkPolicy.recordScan(sourceDigest: digest, date: now.addingTimeInterval(-600), defaults: defaults)
        #expect(AppleLaunchWorkPolicy.shouldRescan(published: true, sourceDigest: digest, now: now, defaults: defaults) == false)
    }

    @Test("shouldRescan is true just past the 10-minute boundary (age > 600s)")
    func testJustPastTheBoundaryTriggersRescan() {
        let now = Date()
        let suiteName = "testJustPastTheBoundary.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let digest = "digest-boundary"
        AppleLaunchWorkPolicy.recordScan(sourceDigest: digest, date: now.addingTimeInterval(-600.5), defaults: defaults)
        #expect(AppleLaunchWorkPolicy.shouldRescan(published: true, sourceDigest: digest, now: now, defaults: defaults) == true)
    }

    /// A recorded scan that is (incorrectly) later than `now` — e.g. clock
    /// skew — yields a negative age, which passes the `age <= 600` check and
    /// reports the index as fresh. Documenting current behaviour; this looks
    /// like a plausible edge-case bug worth a second look (see report).
    @Test("a scan timestamp in the future is treated as fresh, not rescanned")
    func testAFutureScanTimestampIsTreatedAsFresh() {
        let now = Date()
        let suiteName = "testAFutureScanTimestamp.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let digest = "digest-future"
        AppleLaunchWorkPolicy.recordScan(sourceDigest: digest, date: now.addingTimeInterval(3600), defaults: defaults)
        #expect(AppleLaunchWorkPolicy.shouldRescan(published: true, sourceDigest: digest, now: now, defaults: defaults) == false)
    }

    /// If the stored dictionary's values do not match `[String: TimeInterval]`
    /// (e.g. a schema change left stale, wrongly-typed data behind), the cast
    /// fails and the digest is treated as never scanned.
    @Test("a defaults entry with the wrong value type triggers a rescan")
    func testCorruptedDefaultsEntryTriggersRescan() {
        let now = Date()
        let suiteName = "testCorruptedDefaultsEntry.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let digest = "digest-corrupt"
        defaults.set([digest: "not-a-number"], forKey: "openstream.library.lastScan.v1")
        #expect(AppleLaunchWorkPolicy.shouldRescan(published: true, sourceDigest: digest, now: now, defaults: defaults) == true)
    }

    @Test("recordScan overwrites a previous timestamp for the same digest")
    func testRecordScanOverwritesThePreviousTimestamp() {
        let now = Date()
        let suiteName = "testRecordScanOverwrites.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let digest = "digest-overwrite"
        AppleLaunchWorkPolicy.recordScan(sourceDigest: digest, date: now.addingTimeInterval(-3600), defaults: defaults)
        #expect(AppleLaunchWorkPolicy.shouldRescan(published: true, sourceDigest: digest, now: now, defaults: defaults) == true)

        AppleLaunchWorkPolicy.recordScan(sourceDigest: digest, date: now, defaults: defaults)
        #expect(AppleLaunchWorkPolicy.shouldRescan(published: true, sourceDigest: digest, now: now, defaults: defaults) == false)
    }

    @Test("an empty source digest is a valid dictionary key like any other")
    func testEmptySourceDigestBehavesLikeAnyOtherKey() {
        let now = Date()
        let suiteName = "testEmptySourceDigest.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        AppleLaunchWorkPolicy.recordScan(sourceDigest: "", date: now, defaults: defaults)
        #expect(AppleLaunchWorkPolicy.shouldRescan(published: true, sourceDigest: "", now: now, defaults: defaults) == false)
        #expect(AppleLaunchWorkPolicy.shouldRescan(published: true, sourceDigest: "other", now: now, defaults: defaults) == true)
    }
}
