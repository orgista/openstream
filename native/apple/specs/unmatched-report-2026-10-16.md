Here's where things stand: the code, unit tests, serial suite and all six builds are done and passing. The E2E runs on iOS and Apple TV are still to do. The simulator lock on Dev-Mini has been held since 13:45 by another session's iPhone recording job, and I can't tell when it will finish. A watcher will start the scoped E2E as soon as the lock frees up, with a fallback check at 15:05.

**Built so far:**
- **Unmatched shelf:** a new "Unmatched" shelf on the Library page, shown only when at least one title has a cached "no match". Titles where the provider was unreachable or a key was missing don't count. Tapping a title opens the existing match sheet, and picking a result moves it off the shelf straight away with its art.
- **Title page menu:** the menu item now reads "Change Metadata" for matched titles and "Match" for unmatched ones. A manually matched title also gets "Use Automatic Match", which removes the manual correction and brings the automatic match back. If the title never matched, it goes back to the Unmatched shelf.
- **Code:** the new file is `AppleLibraryUnmatched.swift`, plus small changes to the matcher, the library store, the match sheet and its menu, and the Library page.
- **Research page:** `design/reference-apps/2026-10-15-unmatched.md` covers the reference apps. Plex calls the sheet "Match" for unmatched items and "Fix Match" otherwise. Infuse uses "Edit Metadata". None of Plex, Infuse or Jellyfin has a multi-select fix. The page also lists an Infuse-style "no online match" choice as not built; delete that line if you don't want it there.
- **Not built:** the optional multi-select.

**Gates run:**
- **Serial Swift suite:** 3451 tests in 428 suites pass, including 4 new tests for who belongs on the shelf and for the revert.
- **iOS and tvOS Debug builds:** both succeed, and the build log shows all six edited source files recompiled.
- **Release builds without add-ons:** iOS, tvOS, visionOS and macOS all succeed.
- **Anti-slop pass:** one fix. The revert was swallowing a failed file removal; it now writes the failure to the trace.
- **Zero-byte Swift file check:** clean.

**Waiting on the lock:**
- New E2E test `testUnmatchedShelfMatchesAndReverts` for iOS and tvOS: open the shelf, match "Quiet Harbor Home Video" to Stub Movie Two, check it leaves the shelf, then use "Use Automatic Match" and check it comes back.
- The existing Library and title-page tests on both platforms, and the screenshots.

**Risk to watch:** a known note in the tvOS tests says `typeText` fails on the Search screen's search field. My tvOS test types into the match sheet's field through the system keyboard instead, so it may need adjusting after the first run. The E2E fixture is two empty video files in `Apps/TestPlans/Stubs/library-unmatched/`, plus stub catalog answers so the lookup records a real "no match". Nothing is committed.

The E2E runs on iOS and Apple TV still haven't run. Dev-Mini's simulator lock has been held since 13:45 by another session's iPhone recording job. Another lane's visionOS/iPad check is queued behind it, and I can't estimate when either will finish.

A watcher is polling the lock and will start my E2E runs as soon as it's free. It gives up after about 20 minutes, and a separate check at 15:05 looks again. If the queue is still ahead of me then, I'll set another check-in rather than queue blindly.

Everything that doesn't need a simulator is done and passing. That covers the code, the unit tests, the full serial Swift suite (3451 tests), the iOS and tvOS Debug builds, and the four Release builds without add-ons.

What's left is the scoped E2E: the new `testUnmatchedShelfMatchesAndReverts` test plus the existing Library and title-page tests, on iOS and Apple TV. That run also produces the screenshots of the Unmatched shelf on iPhone and Apple TV. The tvOS test may need a tweak after its first run, because it types into the match sheet through the system keyboard.

I still can't run the E2E for the Unmatched shelf. Dev-Mini's simulator lock is still held by the iPhone recording job that took it at 13:45.

Three other jobs are already queued for the lock, ahead of anything I'd start:
- another lane's visionOS/iPad check (eight builds plus two E2E runs, likely well over an hour)
- a Plex job
- a script that moves simulators

There's no basis for an ETA. I won't queue my run blindly; I'll check again at 15:36, and the watcher will tell me sooner if the lock frees first.

Everything else stands as reported: the code, unit tests, full serial Swift suite and all six builds pass, and nothing is committed. The iOS and Apple TV E2E runs and the screenshots are still to do.

Still waiting: at 15:22 the simulator lock was still held by the 13:45 recording job, so the iOS and Apple TV E2E runs haven't started. My next check is at 15:36. Nothing else has changed: all non-simulator gates pass and nothing is committed.

The iOS and Apple TV E2E runs for the Unmatched shelf still haven't started. The recording job that blocked them has finished. At 15:34, though, another lane's visionOS/iPad check took the simulator lock. That check runs a full test suite, eight builds and three E2E runs, so I expect it to finish around 16:50–17:05.

A watcher will tell me the moment the lock is free. A fallback check is set for 16:37. A script that moves simulators is also waiting for the lock, so I'll check the queue again before starting anything heavy. Nothing else has changed: all non-simulator checks pass and nothing is committed.

The iOS and Apple TV E2E runs for the Unmatched shelf still haven't started. The visionOS/iPad check ended at 15:37. At 15:38 your simulator move (all simulators to the external drive) took the lock. It's copying 45 GB and should take about 15 minutes, and a Plex trial job is queued after it.

My next check is at 15:59. If the lock is free then, I'll start the scoped E2E runs. The move also changes where the simulators live. If it rolls back or a device fails its boot test, I'll report that rather than run E2E on a broken simulator.

The iOS and Apple TV E2E runs for the Unmatched shelf still haven't started.

- **Your simulator move failed and rolled back.** Its boot test failed with a "permission denied" error while deleting a simulator's data. The simulators are back on the internal disk. My two E2E simulators, the iPhone 18 Pro and Apple TV 4K, are intact and shut down. The move log is at `/Volumes/DevExt/dev/move-sims.log` on the mini.
- **The lock is held by the Plex-vs-OpenStream measurement on DevTV.** It started at 15:48, and I estimate it finishes around 16:30.
- **The visionOS/iPad check is queued again behind it** and needs about 75–90 minutes once it starts. If it gets the lock first, my E2E would slip to about 18:00.

A watcher will tell me the moment the lock is free, and I'll check again at 16:31. Everything else still passes and nothing is committed.

The iOS and Apple TV E2E runs for the Unmatched shelf still haven't started. The Plex measurement released the simulator lock at 16:26, but the visionOS/iPad check took it straight away. It should run until about 17:40–17:55, and nothing else is queued, so my runs are next.

A watcher will start them as soon as the lock frees, and I'll also check at 17:27. Everything else still passes and nothing is committed.

The iOS and Apple TV E2E runs for the Unmatched shelf still haven't started. Since 17:21 the simulator lock has been held by the last step of the visionOS/iPad check: an iPad E2E run, on what may be the first of three passes. I expect it to finish around 17:45–18:00, and nothing else is queued.

A watcher will start my runs when the lock frees, and I'll also check at 18:07. Everything else still passes and nothing is committed.

The E2E runs for the Unmatched shelf still haven't started. The visionOS/iPad check has held the simulator lock since 17:21 with a full iPad E2E run. It's still making progress: 61 tests have started and it's now on the Settings crawl tests. I can't tell how many tests are left, so I don't have a finish time. Nothing else is queued, so my runs go next.

A watcher will start them as soon as the lock frees, and there's a fallback check at 18:38. Everything else still passes and nothing is committed.

That notice was from the older watcher timing out. At 18:26 the lock is still held by the iPad E2E run that started at 17:21. The newer watcher is still running, and the 18:38 check is still set. My E2E runs still haven't started; everything else still passes and nothing is committed.

The iOS and Apple TV E2E runs for the Unmatched shelf still haven't started.

- **What's holding the simulator lock:** the visionOS/iPad check's full iPad E2E run, which started at 17:21. It's about 126 of roughly 150 tests in, and 17 have failed so far (those are that lane's own tests).
- **Queued ahead of me:** a Top Shelf test job on DevTV.
- **Estimate:** my runs should start around 19:15–19:30.

A watcher will start them as soon as the lock frees, and there's a fallback check at 19:26. Everything else still passes and nothing is committed.

My E2E run got the lock at 18:42 and is running: build, then iOS, then tvOS, on the persistent E2E simulators. I'll get a notice when it finishes, and then I'll read the results, pull the screenshots, and fix anything that fails. The tvOS typing step is the most likely to need work.

The first full E2E run finished, with mixed results.

- **Existing tests:** all 7 Library and title-page tests pass. On iOS that's the Discover-to-title smoke test, the Library crawl, back-after-scrolling, and no dead buttons on the title page. On tvOS it's the smoke test, the Library hero wordmark, and title-page focus.
- **My new Unmatched test:** it failed on both iOS and tvOS. The app ran and listed both fixture files, but the Unmatched shelf never appeared.

The likely cause is a mistake in my test, not the feature:
- My test dropped the launch argument that resets the app on launch, which the other stub tests use.
- Without it, a TMDB/OMDb key or a stale lookup cache left on the simulator turns the lookup into an "outage" instead of a "no match". Outages are deliberately kept off the Unmatched shelf.
- A new unit test runs the same stub files through the real matcher with no keys, and both titles do come out as "no match". So the feature logic behaves correctly.

I've added the reset to both new tests. The Top Shelf DevTV job now holds the simulator lock (since 18:54). As soon as it's free I'll re-run only the two Unmatched tests and collect the screenshots. If the tvOS keyboard step is a problem, it will show up then.

The re-run of the two Unmatched tests (iOS and tvOS) is queued behind the visionOS/iPad check, which took the simulator lock again at 19:01. It starts on its own when the lock frees, so I don't have to race for it again. When it finishes I'll pull the screenshots and write the final report. Nothing is committed.

The re-run of the two Unmatched tests didn't happen: the test runner stopped before testing because OpenStream is no longer installed on the iPhone E2E simulator. It was installed when my run started at 18:42, so something removed it in the next twenty minutes. The visionOS/iPad gate that took the lock at 19:01 and ended within about 2 minutes is a possible cause, but I can't confirm it. The Apple TV simulator still has the app, and the runner stopped before changing anything.

I've re-queued the run behind the Top Shelf DevTV job, which took the lock at 19:03. When it gets the lock, it first reinstalls my 18:44 build of the app on the iPhone simulator, which is the same step every E2E run does anyway. It then shuts that simulator down and runs the two Unmatched tests on iOS and Apple TV. If the lock's 20-minute wait expires, it tries again, up to 9 times. I'll report the results and screenshots when it finishes. Nothing is committed.

My re-run of the two Unmatched tests hasn't started yet. Three jobs are ahead of it for the simulator lock:

- **iPhone-recording lane (has the lock since 19:11):** a scoped iOS E2E run.
- **Top Shelf DevTV job:** queued.
- **visionOS/iPad check:** queued.

That lane also explains why the app disappeared from the iPhone test simulator: it swaps its own builds onto that simulator for Release spot-checks.

My run is queued behind them and retries if its wait times out. When it starts, it puts the app back on the iPhone simulator, runs both tests on iOS and Apple TV, and saves the screenshots. I'll get a notice when it finishes, with a fallback check at 20:27. Nothing is committed.

The second run of the two Unmatched tests also failed on iOS and Apple TV, in about 65 seconds each, the same way as before. That means the reset-on-launch fix I tried last time wasn't the cause.

I think the real problem is in my tests. The Library page builds its shelves lazily, so a shelf that's off screen doesn't exist for the test until it scrolls into view. The Unmatched shelf sits below Movies and Recently Added, and the screen recording showed those two filling the whole iPhone screen. My tests waited for the Unmatched tile to exist before scrolling, so they would never find it. I haven't confirmed this, because the runner only keeps the library scan lines from the app's trace. Those show both files scanned and grouped on both platforms, and nothing about the lookups.

Changes for the next run:
- **iOS test:** waits for the Library to load, then swipes down to the Unmatched shelf.
- **Apple TV test:** moves focus down the page to the Unmatched shelf instead of waiting for the tile to exist.
- **App trace:** the store's two existing trace lines now include how many titles had no match.
- **E2E runner:** `run-e2e.py` now also saves stub misses and library match lines. If the shelf is still missing, I'll see why without another blind run.

The re-run is queued behind the simulator lock and retries if its wait expires. It reinstalls the app on the iPhone simulator if it's missing again. I'll report the results and screenshots when it finishes. Nothing is committed.

The third E2E run also failed, but the new trace lines found the actual cause, and it's in the test fixtures.

**Cause:** the E2E simulators keep a TMDB key, because the reset keeps keychain items shared with your other devices. So the app also asks TMDB about the two fixture titles. TMDB had no stub answer, so the app recorded the misses as an outage instead of "no match", and outages are deliberately kept off the Unmatched shelf. The trace showed "no match: 0" on both platforms. The scrolling fix from last time did work: the tests now fail at about 25 seconds instead of timing out at 60.

**Fix:**
- Added stub answers with no results for TMDB movie search and TV search, under `Apps/TestPlans/Stubs/api.themoviedb.org/`.
- The fixture unit test now runs with a TMDB key set, so it goes through the same lookup as the app on the simulators. It passes, along with the matching-fix suite (36 tests).

**Side effect:** in every stub E2E run, a TMDB title search now comes back as "no results" instead of an outage. That affects other lanes' tests too, though their titles should still match through Cinemeta first, which is checked before TMDB.

The re-run of the two Unmatched tests is queued behind the simulator lock again. When it finishes I'll pull the screenshots and write the report. Nothing is committed.

The iOS screenshots look right:
- The Unmatched shelf appears under Recently Added.
- The sheet is titled "Match" and finds Stub Movie Two.
- After the pick, the title is listed as "Stub Movie Two" in Movies.
- The title page menu shows Change Metadata, Use Automatic Match and Quality.

One thing to note: when the after-match screenshot was taken, the new poster was still a grey placeholder (art was still loading from the stub). Now waiting for the tvOS re-run.

iOS is done: the Unmatched test passed end to end. The tvOS re-run hasn't started yet; it's waiting for the simulator lock.

Another lane has held the lock since 20:21, and a Top Shelf job and an iPhone-recording job are also queued for it. My job retries by itself when it gets the lock, and I've set a fallback check for 21:28. Nothing is committed.

The Apple TV Unmatched test got further this time but still failed. It now reaches the shelf (screenshot captured), opens the Match sheet, and types "Stub Movie Two" through the on-screen keyboard. It failed when moving down to Search. Search was highlighted on screen, but in tvOS forms the highlight goes to the row itself, not the Search button inside it. The row carries the label "Search" but not the test identifier I was checking for.

I've changed the test to find focused rows by their label:
- "Search" for the search button.
- A label containing "2024" for the result row, since the search field above it doesn't contain the year.
- "Use Automatic Match" for the title-page menu item.

The re-run is queued; another lane has held the simulator lock since 21:11, and my job keeps retrying until it gets in. iOS already passed the full flow, and nothing is committed.

The stub poster is a small solid grey PNG, so the grey tile is the matched art loading correctly. The matched title has swapped its text placeholder for its poster. Waiting for the Apple TV run to finish.

The feature now works on Apple TV as well as iPhone. The last tvOS run failed, but only on the test's final check. The screen recording shows "Quiet Harbor Home Video" back on the Unmatched shelf after "Use Automatic Match", with focus already on it. My test expected focus to land on the first tile, "Lantern Street Rehearsal", so it gave up.

I've changed that last step to accept focus on any Unmatched tile. A final run of both the iOS and Apple TV tests together is now running. When it finishes I'll write the report with the screenshots. Nothing is committed.

## Done
- **Unmatched shelf (spec 1)** — `AppleLibraryUnmatched.swift` (new), `AppleMediaSourceViews.swift`, `AppleLocalLibraryStore.swift`, `AppleLibraryMetadataResolver.swift` — the Library shows an "Unmatched" shelf only when at least one title's cached lookup says "no match". If the provider was unreachable or a key was missing, the title doesn't count. A matched or downloaded title has metadata, so it doesn't count either. Titles keep their filename title. The full list shows the file name under each title.
- **Match from the shelf (spec 2)** — `AppleLibraryUnmatched.swift`, `AppleLibraryFixMatchView.swift` — tapping a tile opens the existing Fix Match sheet. The sheet is titled "Match" for unmatched titles and "Change Metadata" for matched ones. Picking a result saves the existing manual correction, and the title leaves the shelf at once with its art.
- **Change Metadata / Use Automatic Match (spec 3)** — `AppleLibraryFixMatchMenuAction.swift`, `AppleLocalLibraryStore.swift` — the title-page menu says "Change Metadata" for matched titles and "Match" otherwise. "Use Automatic Match" appears only when there's a manual correction. It deletes the correction (the file's record and the shared record) and brings back the cached automatic match. A title that never matched goes back to Unmatched.
- **Research** — `design/reference-apps/2026-10-15-unmatched.md` — Infuse "Edit Metadata", Plex "Match"/"Fix Match"/"Unmatch", Jellyfin "Identify". Based on the existing REA notes plus read-only lookups; no code was copied.
- **Unit tests** — `AppleLibraryUnmatchedTests.swift`, 5 tests: who belongs on the shelf, only a real no-match counts, revert restores the automatic match, a reverted no-match goes back on the shelf, and the E2E fixture is cached as a no-match.
- **E2E** — `testUnmatchedShelfMatchesAndReverts` in the iOS and tvOS stub smoke tests. It opens the shelf, matches to Stub Movie Two, checks the title leaves the shelf, uses Use Automatic Match, and checks the title is back.
- **Fixtures and runner** — `Stubs/library-unmatched/` (two empty video files), Cinemeta stub search answers, and empty TMDB `search/movie` and `search/tv` answers. `run-e2e.py` now also saves stub misses and library match lines from the trace.

## Not done / unclear
- Multi-select matching (spec 4, optional): not built.
- Decision for you: the empty TMDB search stubs change every stub E2E run. A TMDB title search now comes back as "no match" instead of an outage, because the E2E simulators keep a TMDB key through the reset. Other lanes' titles still match through Cinemeta first, which runs before TMDB.
- Screenshots: `design/2026-10-16-unmatched/` (8 PNGs: shelf, match results, after match, and title menu, for iPhone and Apple TV).

## Gates run
- code-anti-slop pass → 1 fix: Use Automatic Match swallowed a failed delete; it now writes it to the trace. Kept one `sleep(2)` in the tvOS test while the system keyboard opens, because there's no known element to wait for.
- swift test --no-parallel → pass 3452 tests / 428 suites (re-run after the last source edit).
- Library/matching suites → pass (69 tests across 4 suites earlier, 36 across 2 after the fixture change).
- xcodebuild OpenStream iOS / tvOS (Debug) → recompiled all 6 edited source files; re-run after the last edit recompiled AppleLocalLibraryStore.swift on both.
- Release, no add-ons: iOS, tvOS, visionOS, macOS → BUILD SUCCEEDED. These ran before the last trace-line edit, which doesn't touch `#if OPENSTREAM_ADDONS`.
- E2E iOS → testUnmatchedShelfMatchesAndReverts pass; testDiscoverRowOpensATitleFromStubsAndComesBack, testCrawlLibrary, testTitlePageHasNoDeadButtons and testDetailBackAfterScrolling pass. The opt-in testTitlePageFillDistribution skipped as designed.
- E2E tvOS → testUnmatchedShelfMatchesAndReverts, testDiscoverRowOpensATitleFromStubsAndComesBack, testLibraryHeroDrawsItsWordmarkOverTheBackdrop and testTitlePageIconRowTakesFocus pass. Nothing ran on OfficePlus.
- zero-byte check → clean

## Diff
```
 M Apps/OpenStreamTVUITests/AppleTVStubSmokeUITests.swift   | 85 +
 M Apps/OpenStreamiOSUITests/AppleiOSStubSmokeUITests.swift | 68 +
 M Sources/OpenStreamApple/AppleLibraryFixMatchMenuAction.swift | 27 +-
 M Sources/OpenStreamApple/AppleLibraryFixMatchView.swift   | 11 +-
 M Sources/OpenStreamApple/AppleLibraryMetadataResolver.swift | 51 +-
 M Sources/OpenStreamApple/AppleLocalLibraryStore.swift     | 55 +-
 M Sources/OpenStreamApple/AppleMediaSourceViews.swift      |  4 +
 M Tests/Fixtures/run-e2e.py                                |  3 +
?? Sources/OpenStreamApple/AppleLibraryUnmatched.swift, Tests/OpenStreamAppleTests/AppleLibraryUnmatchedTests.swift
?? Apps/TestPlans/Stubs/{library-unmatched/, api.themoviedb.org/, fixture.example/catalog/movie/top/search=*.json ×3}
?? design/reference-apps/2026-10-15-unmatched.md, design/2026-10-16-unmatched/
```

## Notes for the reviewer
- `AppleLocalLibraryStore.correctMatch` takes a `resolver:` parameter (default `.shared`), but the new `useAutomaticMatch` uses the store's own resolver. They're the same in the app; the tests pass both explicitly.
- `removeManualMatch` deletes the shared record only if it's manual. If two files were manually matched to the same title, reverting one also removes the shared record the other might fall back to (that file's own record stays).
- The shelf only lists titles that have already been looked up. Titles past the first 24 show up once their card has been resolved.
- On tvOS, Form rows and menu items take focus as a cell that doesn't carry the test identifier. The tvOS test finds them by label or by the cell that contains the identifier (`AppleTVStubSmokeUITests.swift`, the focus helpers).
- Dev-Mini incidents:
  - Your simulator move (`/Volumes/DevExt/dev/move-sims.sh`) failed its boot test at about 15:50 and rolled back; the simulators are intact.
  - The iPhone-recording lane uninstalls the app from E2E-iOS (`73E49263…`). My runs reinstalled the Debug build before testing.
- Cleanup: removed my Release build folders, E2E scratch and exported attachments. Nothing is booted, and the Studio has no leftovers. Nothing committed.
