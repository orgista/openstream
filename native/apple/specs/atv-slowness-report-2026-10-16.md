Status: DevTV now has the owner's setup (472 titles). Base build measurements are running; the after build follows in the same queue. I'll pick up when they finish.

Status: unit gate is green (3,425 tests, 425 suites). The DevTV after-build, launches, profiled walk and both simulator E2E runs are queued on the mini. Next check at about 01:35.

Status: E2E-tvOS passed (20/20, all edited files recompiled). E2E-iOS is still running. A second round of fixes, from the DevTV profile, is ready to test:
- lazy index load
- string-based disc check
- revision fingerprints for playback state
- indexed Top 10 title matching

It's queued to sync once E2E-iOS ends.

E2E-iOS is still running. Two failures so far (`testCrawlLive` AirPlay/clock, `testCrawlPlayers` skip position), both listed as known flakes in the flaky-e2e spec. The round-2 measurements start after it.

Round-2 unit gate: 3,425 tests ran; 3 in `AppleMacCaptionsSelectionTests` failed (real-asset playback, two hit the 60 s limit). They passed in round 1. I'll rerun that suite alone after the DevTV runs to tell a flake from a regression. Next check at about 03:20.

Round 3: unit gate green (3,426 tests in 425 suites). The captions failure didn't repeat, and the suite passed twice in isolation. DevTV measurements are running, then the final E2E pair. Next check at about 03:54.

Round 3 results are in: DevTV Home first frame 200 ms, library on screen at 2.4 s (was 5.9 s), in-app tab switch max 67 ms (was 433 ms). E2E-tvOS passed 20/20. Waiting on the last E2E-iOS run before the report.

E2E-iOS has about 18 tests left. Checking back around 05:06, then writing the report.

## Done
- **DevTV given the owner's setup** — `Sources/OpenStreamApple/AppleDebugBackupRestore.swift` (new), `Apps/Shared/OpenStreamApps.swift`, `AppleConfigurationController.swift` — a Debug-only launch hook (`-OpenStreamRestoreBackup` and `-OpenStreamRestorePassphraseFile`) imports the owner's DevPlus backup through Backup & Sync's own `restore()`. Result on DevTV: 8 sources restored, 1,472 files on ServerPlus, 472 titles. The hook deletes both files from the container (checked). It also sets the same "held from iCloud" flag Reset uses: the earlier run's DevTV numbers were taken on an empty library because iCloud sync replaced the seeded sources after 185 s.
- **Playback state reads on tvOS** — `ApplePlaybackBlobStorage.swift`, `ApplePlaybackStore.swift`, `AppleIdentityAliasStore.swift` — on Apple TV every read went to NSUserDefaults, and each query copied and compared 7 stored blobs. Reads now come from a copy, dropped whenever any default changes, and the check is a single revision number.
- **Index loads off the main thread** — `AppleMediaIndex.swift` — the repository now reads and scrubs its file on the first actor call, not in `init`. `init` ran on the main thread from the root view's `@State`: 250 ms on DevTV.
- **Catalog indexing** — `AppleMediaIndex.swift`, `AppleDiscoverView.swift` — `replaceCatalogs` writes all add-ons in one file write instead of one per add-on (~1.4 s of CPU at launch). An unchanged record set no longer notifies observers.
- **Library publish** — `AppleLocalLibraryStore.swift`, `AppleLibraryShelves.swift`:
  - The snapshot is read and decoded off the main thread.
  - The library publishes before episode candidates are computed.
  - The title-parse memo is warmed off the main thread.
  - Merges that change nothing no longer redraw.
- **Discover and Top Shelf** — `AppleCatalogSearchLookup.swift`, `AppleDiscPlayback.swift`, `OpenStreamRootView.swift`:
  - Top 10 title matching uses an index by type and title.
  - The disc check is plain string work.
  - Top Shelf publishes are coalesced (500 ms).
- **Kept from the earlier run, reviewed and kept:** billboard match index, shared decoded playback/alias state, parse memo, harness (`AppleTVPerfWalkUITests`, launch offset in the trace, `mini.sh` destination).

**DevTV (owner library, Release add-ons build; p50/p90; XCUITest numbers include ≈280 ms of XCUITest's own time)**

| | before | after |
|---|---|---|
| Process start → Home frame | 441 / 454 ms | 200 / 217 ms |
| → hero art | 2,430 / 2,577 ms | 1,660 / 2,173 ms |
| → library shown (persisted index) | 5,926 / 6,207 ms | 2,380 / 2,409 ms |
| Tab switch, in-app (`tab →` → on screen) | 26 / 35 ms, max 433 | 24 / 35 ms, max 67 |
| Tab switch, XCUITest | 353 / 684 ms, max 1,281 | 351 / 508 ms, max 571 |
| Focus move, XCUITest | 344 / 355 ms | 348 / 358 ms |
| Title open, XCUITest | 1,384 / 1,440 ms | 1,416 / 1,418 ms |
| Rescan with a valid index | skipped | skipped |

## Not done / unclear
- **Library still appears at 2.4 s, not under 2 s.** Home itself is usable at 0.2 s. The remaining time is background CPU contention at launch: recommendations ≈1.1 s, Top 10 parse ≈0.8 s, first-time title parse.
- **Focus under 100 ms can't be measured from XCUITest** (≈280 ms of its own time). The in-app trace has no focus marks yet.
- **"E2E-tvOS on DevTV":** `run-e2e.py` only runs on simulators, and a stubbed run would wipe the restored setup. The device pass was the real-library walk (10 rounds of tabs, shelf focus, 5 title opens) plus 10 cold launches. Settings rows were excluded: the owner's Settings PIN prompt captures focus.
- **The rescan regroup guard isn't proven on device.** Every rescan seen was the first after a persisted publish, which always republishes.
- **Play → first frame wasn't measured.**

## Gates run
- code-anti-slop pass → removed 1 dead method (store `replaceCatalog`), 1 duplicate comment and 1 blank line; corrected 1 wrong comment; added a reason to the one `nonisolated(unsafe)`.
- swift test (serial, own scratch path) → pass 3,426 tests / 425 suites. Round 2 had 3 `AppleMacCaptionsSelectionTests` failures under load; the suite passed alone twice (7/7) and in the final full run.
- xcodebuild AppStore-tvOS Release, DevTV → recompiled all 11 edited files (grep 1 each). E2E builds recompiled the 9 tracked files on tvOS and iOS sims.
- E2E-tvOS sim → 20 passed / 0 failed. E2E-iOS sim → 40 passed / 1 failed: `testCrawlLive` AirPlay, listed as flaky in `specs/flaky-e2e-2026-10-15.md`.
- zero-byte check → clean

## Diff
23 files changed, 597 insertions(+), 261 deletions(-); new: `AppleDebugBackupRestore.swift`, `AppleTVPerfWalkUITests.swift`, `ApplePlaybackStoreSharedStateTests.swift`.

## Notes for the reviewer
- **DevTV is left on the owner's setup with iCloud held**; "Restore from iCloud" undoes the hold. OfficePlus was not touched. I killed this lane's orphaned E2E-iOS process left by the earlier stopped run.
- **`ApplePlaybackBlobStorage.revision`** relies on `UserDefaults.didChangeNotification` being posted synchronously; `defaultsBackedReadsSeeEveryWriteAtOnce` checks that.
- **`AppleLocalLibraryStore.publishPersistedIndex`**: episodes now arrive about 1.5 s after the titles, so Library's Continue Watching next-episode row can appear a moment late.
- **`AppleMediaIndexRepository`**: a corrupt file is now quarantined on the first call, not in `init` (one test adjusted).
- Harness and data on the mini: `/Volumes/DevExt/dev/openstream-build/atv-slowness` (`perf.sh restore|launches|walk|walkprof`, traces in `out/`).
