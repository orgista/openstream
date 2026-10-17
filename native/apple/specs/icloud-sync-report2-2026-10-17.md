The diff is clean: one comment line and no dead paths, so nothing to remove. I'm still waiting for the main lock before the DevTV install; the watcher will wake me.

## Done
- **FIX 1: an unreadable newer copy no longer stops sending.** Changed `Sources/OpenStreamApple/AppleConfigurationController.swift:576-584`, using the reviewer's guard. `writeNow` now holds a send only when `AppleCloudConfigurationRead.decide` accepts the stored copy, meaning it is newer and would actually be applied. A copy that read rejects (too large, fails `validate()`, unsupported format) no longer blocks this device's sends.
- **Controller test.** Added `aNewerCopyThatCannotBeReadDoesNotHoldTheSend` in `Tests/OpenStreamAppleTests/AppleBackupRestoreTests.swift`. Setup: iCloud holds a copy an hour newer with `formatVersion` 2, which read rejects. The device then deletes a source locally and runs `syncNow()`. It checks that `publishedSnapshot` is the local copy: format 1, only the kept source, with the deletion record. I reverted the guard in the mini's synced copy only, and the test failed (3 expectations); with the fix it passes.

## Not done / unclear
- **DevTV device check: half done.** The Debug build (owner-build recipe, Debug, OWNER_DEST unset, this lane's source) succeeded with add-ons and DEBUG on, and **is installed on DevTV**. The first launch failed: `devicectl` needs `--` before the app arguments, and the fixed script is at `dev-mini:/tmp/icloud-devtv-launch.sh`. After that, other lanes held the main lock for over an hour (iso-open gates at 12:59, avp at 13:50, a second iphone-jank E2E at 13:57) and my queued run lost the lock each time. I stopped the queue and left nothing running. To finish: `ssh dev-mini '~/Developer/bin/buildlock.sh zsh /tmp/icloud-devtv-launch.sh'` (about 2 min), then count the applied sources in `/tmp/icloud-devtv-trace.log`.
- **OfficePlus side (read only, done):** its trace ends 2026-10-16 05:00Z. The last apply, at 04:57Z, was "applied: 9 sources from iCloud" (add-ons included), with "not newer" after that. **DevTV should show 9.** I deleted both trace copies from the mini.
- **Still open (not in FIX 1):** if a copy passes `decide` but `apply` then throws, it still holds sends. The reviewer's guard doesn't cover that case. Separately, a stored copy with duplicate source IDs still gets merged into the send, so `cloudData()` fails as it already did before this diff.

## Gates run
- code-anti-slop pass → removed 0; the diff is one guard condition and one comment line, no dead paths.
- swift test, scoped sync/backup suites → pass 81/81 (8 suites).
- swift test, full serial (`--no-parallel`) → pass 3484/431.
- xcodebuild OpenStream tvOS / iOS (generic simulator, compile lane) → BUILD SUCCEEDED; `AppleConfigurationController.swift` recompiled in both logs (grep count 1 each). The DevTV Debug device build also succeeded and recompiled it.
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
?? specs/icloud-sync-2026-10-17.md
?? specs/icloud-sync-report-2026-10-17.md
?? specs/icloud-sync-review-2026-10-17.md
 7 files changed, 289 insertions(+), 23 deletions(-)
```
(This lane's earlier work plus my roughly +5/−3 in the controller and +25 in the backup tests. Nothing committed.)

## Notes for the reviewer
- `AppleConfigurationController.swift:583`: `decide` decodes the payload a second time per send. Payloads are capped at 950 KB and sends are debounced, so I left it.
- The DevTV build used the owner recipe's signing overrides on the command line (Automatic, Apple Development, ASC key) without its `SWIFT_ACTIVE_COMPILATION_CONDITIONS` override, because Debug already defines add-ons and a command-line override could have dropped `DEBUG`. No signing files were edited. DerivedData is at `/Volumes/DevExt/dev/openstream-build/icloud-sync-dd-devtv`.
- Dev-Mini was down to 19–21 GB free during these runs (disk-guard warned).
