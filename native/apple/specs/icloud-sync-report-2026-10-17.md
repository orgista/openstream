The compile lock passed from the other lane's test run to another job (`serv…`, started 10:04), so my gate is still queued. The background watcher will wake me when the lock frees. Then I'll run the scoped sync tests, the full gate and iOS/tvOS builds.

## Done
- **Why the counts differ (not a sync bug)**: the owner's iPhone runs build (1) with no add-ons, so its 6 add-ons are hidden but still stored and still synced. 3 visible on the iPhone plus 6 add-ons is the 9 OfficePlus shows. The traces show sync working between them: the iPhone removed a media server at 04:23Z on 10-16 and OfficePlus dropped it at its next launch about 30 s later; the iPhone re-added one at about 04:50Z and OfficePlus had 9 again at 04:57Z.
- **1. Which copy wins** — `AppleConfigurationSyncPolicy.swift`, `AppleConfigurationController.swift`
  - The winner is decided by the publishing device's own clock (`savedAt`). A phone whose clock is behind could stamp an edit earlier than the copy it had already applied, and every other device then read it as "not newer".
  - New `editStamp(after:)`: an edit is always stamped just after the copy it was made from.
  - A send no longer replaces a newer iCloud copy this device hasn't applied yet.
  - The Apple TV keeps the imported copy's own date after an import, instead of stamping the time of the import.
- **2. Deletions**
  - Before, a receiver replaced its source list on every read, which dropped sources that only that device had (an Apple TV's own). It now merges, and sources leave only through their deletion record (tombstone).
  - Before, a deletion made offline was sent with the old date, so devices that had applied that copy kept the deleted source. It now gets a fresh stamp.
- **3. Media servers and passwords**
  - tvOS never receives another device's iCloud Keychain items (Apple's documented limit). That is why OfficePlus sat at "waiting=4" from 10-13 until Set Up from iPhone delivered the passwords.
  - On tvOS the status now reads "N need sign-in", the pointless retry loop is off, and a "Set Up from iPhone" button shows while sources wait.
  - Separately, a library scan or source check alone no longer counts as an edit. The iPhone had been re-sending its whole setup after every scan.
- **4. Apple TV receive path**
  - Coming back to the front now refreshes iCloud first, then reads.
  - The iCloud Sync section under Settings › Sources gets a "Resume iCloud Sync" button while the device is held. Restore from iCloud now applies what iCloud holds even if this device stamped a later date (DevTV's case).
  - Debug launch flag `-OpenStreamResumeICloudSync YES` does the same at launch (`AppleDebugBackupRestore.swift`).
- **Same Apple ID**: confirmed for the iPhone, OfficePlus and DevTV from the traces, without reading any address. DevTV and OfficePlus both applied the iPhone's iCloud copies, and that iCloud store is per account.

## Not done / unclear
- **Device check**: not done. DevTV was held by another lane's job (server-trailers, main lock taken 10:23) right after the speed3 perf run, and there's no Apple Development identity on the mini for my own device build. To do it: install a Debug build on DevTV, launch it with `-OpenStreamResumeICloudSync YES`, and compare its Sources count with OfficePlus (add-ons included) rather than with the iPhone.
- **Owner's iPhone and DevPlus**: not touched.
- **E2E sync tests**: not run. The simulators have no iCloud account, so the controller-level tests with a fake iCloud store are the proof.

## Gates run
- code-anti-slop pass → made 1 new helper private, rewrote 1 comment that overclaimed; no dead code.
- swift test (scoped sync and backup suites) → pass 79/79 (7 suites), including 8 new tests.
- swift test (full) → 3480/3483. The 3 failures are `AppleMacCaptionsSelectionTests` time limits under load from another lane; that suite passes alone (7/7, 0.47 s).
- I didn't run the "before" gate, but by reading the old code each new test fails without its fix.
- xcodebuild OpenStream tvOS / iOS (generic simulator, compile only) → BUILD SUCCEEDED; all 5 edited source files recompiled in both logs.
- zero-byte check → clean.

## Diff
```
 M Sources/OpenStreamApple/AppleConfigurationController.swift
 M Sources/OpenStreamApple/AppleConfigurationSyncPolicy.swift
 M Sources/OpenStreamApple/AppleDebugBackupRestore.swift
 M Sources/OpenStreamApple/AppleSettingsViews.swift
 M Sources/OpenStreamApple/AppleSourcesSettingsView.swift
 M Tests/OpenStreamAppleTests/AppleBackupRestoreTests.swift
 M Tests/OpenStreamAppleTests/AppleConfigurationSyncTests.swift
?? specs/icloud-sync-2026-10-17.md (pre-existing)
 7 files changed, 262 insertions(+), 21 deletions(-)
```

## Notes for the reviewer
- **Behaviour change**: a backup imported on an Apple TV is now replaced by a newer iCloud copy at the next read; before, it stayed until the phone's next edit. The Debug restore hold still protects DevTV measurements.
- **Edits made at the same time on two devices**: if another device sent a newer copy before this one applied it, this device's setting edits lose (last copy wins). Its sources and deletions still go out after the merge. See the write guard in `AppleConfigurationController.swift` `writeNow`.
- **Builds not run**: tvOS Release builds and the no-add-ons Release check. Nothing changed under `#if OPENSTREAM_ADDONS`, and the new Debug code has no `#else`.
- **Build scratch**: kept separate from the other lanes, at `/Volumes/DevExt/dev/openstream-build/icloud-sync-spm` and `icloud-sync-dd-{tvOS,iOS}`.

Source on the tvOS keychain limit: [Apple Developer Forums: Is iCloud Keychain available on tvOS?](https://developer.apple.com/forums/thread/18480), [kSecAttrSynchronizable](https://developer.apple.com/documentation/security/ksecattrsynchronizable.md)
