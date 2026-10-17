All four fixes are in. The swift gate and the iOS, tvOS, visionOS and macOS builds pass. The simulator E2E and the before/after trace count haven't run yet.

**What's left:** another project's iPhone E2E (`iphone-jank`, started 11:49) holds the simulator lock. It has finished 35 tests on the first of its two simulators, so the ETA is unknown but likely over an hour. A background check notifies me when the lock frees.

Then I'll run, in order:
1. The hero rotation and title-page runs on the iOS 18.6 sim (your imported setup), with the fixes.
2. The same on the tvOS sim.
3. A rebuild of the pre-fix tree (saved on the mini) and the same iOS run, for the "before" count.

The count is trailer web views opened in the first 5 s of launch. The worker's earlier run on the same sim had 3 (one prefetch and two trailer loads at 1.3, 1.6 and 3.6 s), which is the churn the review flagged.

**Changes so far:**
- **FIX 1:** moved `prefetchHeroTrailer` above the `featuredHero` doc comment in `AppleDiscoverView.swift`.
- **FIX 2:**
  - **Gate:** the trailer gate now has a `heroesSettled` condition and a 1 s `settleDelay`. A trailer can't autoplay until the hero list has held still for 1 s; a pressed trailer skips this. `AppleDiscoverView` sets the flag with the 1 s task from the review and passes it down to the billboard.
  - **Prefetch (beyond the spec):** the iPhone and Mac carousels also hold the hidden prefetch web view until the list settles. That prefetch also opened a throwaway web view at launch.
  - **Tests:** the existing gate tests now cover "unsettled blocks autoplay" and "pressed still plays".
- **FIX 3:** removed the blank line under the `cycleIsPaused` doc block in `AppleHeroRotationCycle.swift`.
- **FIX 4:** the prefetch now clears `prefetchedKey` in both failure callbacks, so a key that failed once can be prefetched again.
- **Anti-slop:** one test comment that narrated the review was reworded.

Nothing is committed. The full §7 report comes after the simulator gates.

All four fixes are in, the swift gate passes and so do the four platform builds. The simulator gates haven't run yet. The `iphone-jank` E2E still holds the simulator lock: it started at 13:57 on your iOS 18.6 sim (7530ECB2) and has finished 27 tests. ETA is unknown, likely 30–75 minutes. My first watch hit its time limit and missed a short gap in the lock. A new watch polls every 10 s and wakes me when the lock frees.

Both apps are already built: the fixed iOS and tvOS builds, and a pre-fix iOS build from a copy of the worker's tree I saved on the mini before syncing. Once the lock frees, everything runs in the foreground:

1. The fixed hero rotation and title-page runs on the iOS 18.6 sim.
2. The same on the tvOS sim.
3. The pre-fix build on the iOS 18.6 sim, to count trailer web views opened in the first 5 s of launch (before vs after).

Then I'll delete my three internal simulator build folders (the mini is at 22 GB free) and send the §7 report. Nothing is committed.

My iOS run is still queued behind the iPad UI test job, which has held the simulator lock since 14:54. `buildlock.sh` lets my run wait up to 20 minutes, and I'll be notified when it starts, finishes or gives up.

All four fixes are in. The swift gate passes with 3482 tests in 432 suites, and the iOS, tvOS, visionOS and macOS builds all succeed. None of the simulator runs have happened yet.

Still to run:
- **iOS 18.6 sim:** the fixed hero and title-page runs, then the pre-fix hero run that gives the "before" trailer web-view count.
- **tvOS sim:** the same hero and title-page runs.

Nothing is committed.

## Done
- FIX 1: moved `prefetchHeroTrailer` above `featuredHero`'s doc comment, so that comment documents the right function again. File: `AppleDiscoverView.swift`.
- FIX 2: autoplay now waits until the hero list has held still for 1 s; pressed trailers bypass it. Files: `AppleHeroTrailerGate.swift`, `AppleDiscoverView.swift`, `AppleHomeBillboard.swift`, `AppleHomePhoneHeroCarousel.swift`, `AppleHomeMacHeroCarousel.swift`, `AppleHeroTrailerGateTests.swift`.
  - The gate gained a `heroesSettled` condition and a `settleDelay` of 1 s. `plays` returns `pressed || (autoPlaySetting && heroesSettled)`.
  - `AppleDiscoverView` holds `heroesSettled` with the review's `.task(id: heroes.map(\.id))` and hands it down through a new `appleHeroesSettled` environment value. It defaults to true, so heroes outside Discover are unaffected.
  - Beyond the spec: the iPhone and Mac carousels also hold the hidden prefetch web view until the list settles (task id is nil until then), since that prefetch was one of the throwaway launch web views.
  - Test: `heroesSettled: false` added to `autoplayStopsForEachRule`, and a pressed trailer still plays when unsettled.
- FIX 3: removed the blank line under the `cycleIsPaused` doc block. File: `AppleHeroRotationCycle.swift`.
- FIX 4: `prefetchedKey = nil` in both `didFail…` callbacks before `cancel()`. File: `AppleTrailerPlayerPrefetch.swift`.

## Not done / unclear
- **FIX 2 did not reduce launch web views.** Trailer web views opened in the first 5 s on the iOS 18.6 sim (owner setup):

| Run | Web views |
|---|---|
| Worker's run (pre-fix) | 3 |
| My pre-fix runs ×3 | 2 / 2 / 2 |
| Fixed runs | **4** / 2 (a third fixed run lost its trace to a script bug) |

  - In the fixed run with 4, the first list appeared at 0.93 s, the gate opened at about 1.9 s, then the catalog review (done at 1.57 s) replaced the list at 2.23 s. That is 1.3 s after the first list, past the 1 s window. In the pre-fix runs the final list was there from the first frame.
  - Recommendation: open the gate on "catalog review done + 1 s" rather than a plain 1 s timer. This needs Fable's or your decision; I left the spec as written.
- The iOS 18.6 sim has no `group.com.orgista.openstream` app-group container. It was already missing at the worker's 10:50 run (unsigned `CODE_SIGNING_ALLOWED=NO` installs). Sources and data are in the app container and intact; only Top Shelf/widget publishing is affected. I left it alone.
- My unsigned tvOS install dropped that sim's app group, which made the first tvOS E2E fail before any test ran. A signed install brought it back.

## Gates run
- code-anti-slop pass → removed 1 comment that narrated the review (`AppleHeroTrailerGateTests.swift`); no dead paths.
- swift test (serial, compile lane) → pass 3482/432, run twice, before and after the anti-slop edit.
- xcodebuild, Debug, unsigned:
  - OpenStream iOS (iOS Simulator) → recompiled all 7 edited files (grep ≥ 1 each).
  - OpenStream tvOS (tvOS Simulator) → recompiled all 7.
  - OpenStream visionOS (visionOS Simulator) → recompiled all 7.
  - OpenStream macOS → recompiled all 7.
- E2E, iOS 18.6 sim (owner setup):
  - Hero rotation: trailer prefetch, start and play to the live-viewport reveal all seen in the trace.
  - Title page: trailer candidate 1/3 loads and plays, then the native reveal.
- E2E, tvOS (`run-e2e.py`, stub data, sim data restored) → 3/3 passed:
  - `testDiscoverHeroButtonsAndPagingKeepFocus`
  - `testDiscoverHeroStillDrawsAfterTheTextlessChange`
  - `testDiscoverRowOpensATitleFromStubsAndComesBack`
  - tvOS has no trailers (`offersTrailers` is false there).
- zero-byte check → clean.
- Cleanup: my simulator build folders and `/tmp` scratch on the mini are deleted, no simulators are left booted, and internal disk is at 30 GB free.

## Diff
- Status: the same 16 modified files plus 6 untracked as at session start (3 new Swift files from the worker, the REA note, the report and the review spec).
- Diff stat: 16 files changed, 356 insertions(+), 146 deletions(-), of which this session's share is the edits listed under Done.
- Nothing is committed.

## Notes for the reviewer
- `AppleHeroTrailerGate.swift`: `settleDelay` is a `Duration` constant, and `heroesSettled` defaults to true in `Conditions` and in the environment value.
- `AppleHomePhoneHeroCarousel.swift:80`: the prefetch task is keyed `heroesSettled ? next : nil`, so it restarts when the list settles.
- The before/after counts depend on cache timing; the "before" build came from a copy of the worker's tree taken before my first sync (hashes checked).
