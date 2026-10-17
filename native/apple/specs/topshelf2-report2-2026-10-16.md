The sims and DevTV are queued behind the iPad E2E run that has held the main lock since 21:35. I don't know when it ends, so I'm assuming about 20–60 minutes. The compile-lane builds are queued behind another lane's build that started at 22:34. Both are `nohup` jobs on the mini, and I'll be notified when each finishes.

That notification came from the old watcher on the build job I stopped; I've closed it. Both real jobs are still waiting on the mini (`bvos011ue` for the builds, `bj06xbg7v` for the E2E and DevTV runs).

## Done
- **FIX 1, an empty hero list now clears the Top Shelf.** The tvOS `.onChange(of: topShelfHeroes(heroes), initial: true)` moved off `AppleHomeHeroCarousel` (only built when `!heroes.isEmpty`) onto the `body`'s outer `Group`, which is always on screen. Removing or disabling the last source now sends `update([])` to `AppleTopShelfHeroFeed.shared`. File: `Sources/OpenStreamApple/AppleDiscoverView.swift:626`.
- **FIX 2, no fixed sleeps after Up and Right in the Top Shelf test.** New `waitForHomeScreen(_:timeout:)` reads `homeScreenTexts()` every 0.5 s for up to 8 s. The full-screen check also requires a non-empty read, because a failed snapshot returns `[]`, which would otherwise count as "swipe-up prompt gone". The two Home sleeps stay. File: `Apps/OpenStreamTVUITests/AppleTVTopShelfUITests.swift:93-104,127`.
- **FIX 3, `public` dropped where nothing outside the module uses it.** `AppleTopShelfArtworkLayout` (the enum, `canvas` and `fileName`), `AppleTopShelfTrailerPolicy` and its `previewVideoURL`, and `AppleTopShelfHero.init`. `AppleTopShelfArtworkStore` and `defaultArtwork` stay public. Files: `AppleTopShelfArtwork.swift`, `AppleTopShelfSnapshot.swift`.
- **The TMDB empty-search stubs are unchanged**, per your decision.
## Not done / unclear
- The 55% corner scrim under the wordmark is still there. It conflicts with the "no scrims over artwork" rule and still needs the owner's OK (reviewer's note, not a FIX item).
## Gates run
- **Anti-slop pass:** nothing to remove. The diff adds two comments, both explaining why: why the feed sits on the Group, and why an empty read doesn't count.
- **`swift test --no-parallel` (compile lane):** passed, 3452 tests in 428 suites.
- **xcodebuild (compile lane), all BUILD SUCCEEDED:**
  - tvOS Sim Debug and iOS Sim Debug.
  - tvOS and iOS Release with `CODE_SIGNING_ALLOWED=NO` and no add-ons.
  - The recompile grep was 1 for `AppleDiscoverView`, `AppleTopShelfArtwork` and `AppleTopShelfSnapshot` in all four.
- **E2E-tvOS sim (`run-e2e.py`), 3/3 passed:**
  - `AppleTVTopShelfUITests` (carousel true, "Stub Movie" matched).
  - `AppleTVStubSmokeUITests/testDiscoverRowOpensATitleFromStubsAndComesBack`.
  - `AppleTVFocusUITests/testDiscoverHeroStillDrawsAfterTheTextlessChange`.
  - The test build recompiled the test file and all three source files.
- **E2E-iOS sim:** `AppleiOSStubSmokeUITests/testDiscoverRowOpensATitleFromStubsAndComesBack` passed, and all three source files recompiled.
- **DevTV (signed Release with add-ons, real sources), run r8:**
  - TEST BUILD SUCCEEDED, and all 7 Top Shelf files recompiled.
  - The Top Shelf UI test passed: focus reached oStream and the shelf showed as the full-screen carousel.
  - The new waits passed: Up removed the swipe-up prompt and Right showed a "page …" string.
  - OfficePlus was not touched.
- **Zero-byte check:** clean.
## Diff
```
 M Apps/OpenStreamTVUITests/AppleTVTopShelfUITests.swift
 M Apps/OpenStreamTopShelf/TopShelfProvider.swift
 M Sources/OpenStreamApple/AppleDiscoverView.swift
 M Sources/OpenStreamApple/AppleTopShelfPublisher.swift
 M Sources/OpenStreamApple/AppleTopShelfSnapshot.swift
 M Sources/OpenStreamApple/OpenStreamRootView.swift
?? Sources/OpenStreamApple/AppleTopShelfArtwork.swift
?? Tests/OpenStreamAppleTests/AppleTopShelfArtworkTests.swift
?? design/2026-10-16-topshelf2/  specs/topshelf2-{2026-10-16,report-2026-10-16,review-2026-10-16}.md
 6 files changed, 267 insertions(+), 38 deletions(-)   (whole lane; this pass ≈ +30/−15)
```
## Notes for the reviewer
- `AppleDiscoverView.swift:626`: the feed now also fires while Discover shows its empty or loading state. `heroes` comes from `recommendations`, so it is `[]` there and the shelf clears. That is the intended behaviour; spot-check that a slow first load doesn't briefly publish `[]` over a good snapshot written on an earlier launch.
- **Full-screen check in the Top Shelf test:** the review asked for `!contains(prompt)`. I also require a non-empty read, both in the wait and in the `XCTAssertFalse`, so a failed snapshot can't pass it.
- **Not committed.** I opened no sims or windows myself. The `run-e2e.py` runs booted the E2E sims under the build lock, and `tidy-gui.sh` runs when the lock is released.
- **Cleanup on the mini:** I removed my `/tmp` scripts, logs and E2E scratch. The lane's build folders under `/Volumes/DevExt/dev/openstream-build/topshelf2*` stay for re-runs, plus a new `topshelf2-dd-ios-release` I added.
- **DevTV after the run:** it is left with this lane's build installed, and another lane (speed2) was using it after my run.
