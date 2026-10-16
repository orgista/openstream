The swift test gate is next in line, behind atv-slowness's tvOS E2E, which has held the lock since 03:38. How long that run takes is unknown, so I'm using 20 minutes. Progress events will wake me, with a fallback check at 04:14.

Re-armed the progress watch; still waiting for the lock.

The first 20-minute lock wait timed out while atv-slowness's E2E was still running. Retry 2 is now queued.

atv-slowness took the lock again at 03:45 for an iOS E2E run, which should take until about 04:25. My swift test is queued right behind it.

Still queued behind atv-slowness's iOS E2E. A watcher will notify me when the next progress line lands.

Still waiting on the lock. I'll be notified on the next progress line.

atv-slowness's iOS E2E is still running (since 03:45, about 40 minutes so far). My second lock wait timed out and the third is queued. Still waiting.

atv-slowness's iOS E2E has finished 34 of about 40 tests, so it should free the lock within about 10 minutes. My swift test is next in the queue.

The iOS 27 sim build is running; I'll be notified when it finishes.

The iOS 27 E2E is running; I'll be notified when it ends.

The iOS 27 E2E is still running.

The test fix is synced to the mini, so the iOS 18.6 E2E will use it. Once the pipeline finishes, I'll rerun that one test on iOS 27.

The anti-slop pass found nothing to change. My two test edits are each one line plus a short comment that says why. Waiting for the owner build.

The second pipeline is waiting behind atv-slowness's unit gate (started 05:56). A watcher will notify me when the 18.6 E2E finishes.

The baseline harness is ready. Waiting for the 18.6 E2E to finish.

The iOS 27 rerun of the fixed tests is running.

The baseline run on unmodified HEAD (6 tests on 18.6) is queued. I'll be notified when it finishes.

## Done
- **All five gates ran.** App code is unchanged. Two UI-test waits broke because the earlier iOS spinner change (`player.connecting`, previously drawn on tvOS only) now shows before the failure alert. Both are fixed in `Apps/OpenStreamiOSUITests/AppleiOSUITests.swift`:
  - `testLegacyDiscoverNavigationAndPlayerAccessibilityIsolation`: waits up to 30 s for the "Playback Failed" alert before closing it (`:544`).
  - `coverRoundTrip`: `connecting` no longer counts as the player's way out (`:1908`). Before that change, iOS never drew the spinner, so this is exactly what the test checked before.
- **Owner's iPhone build** (Release + add-ons, `owner-build.sh`, iPhone 15 Pro Max `00008130…`) is at `/Volumes/DevExt/dev/openstream-build/iphone-ios18/dd-device/Build/Products/Release-iphoneos/OpenStream iOS.app`. It includes the hero fixes. Not installed.
- **Screenshots** are in `/Volumes/DevExt/dev/openstream-build/iphone-ios18/shots/`: `discover-ios18.6-top.png` and `discover-ios18.6-scrolled.png` (scrolled with the app's `-OpenStreamDiscoverScrollY` hook). At the top, the hero runs edge to edge under a transparent bar. Scrolled, the bar is the stock blurred bar with an inline "Discover" title.

## Not done / unclear
- **iOS 18.6 E2E has 5 failures that are already on unmodified HEAD 031ecc2.** I reran them there and each failed the same way, so this branch didn't cause them:
  - `testConfigurationExportsThroughTheSaveSheetAndImportsBack`: no Save button in the save sheet.
  - `testContinueWatchingWidgetCanBePlacedOnTheHomeScreen`: keyboard focus.
  - `testCrawlDetailAndEpisodes`: `detail.episode.download` can't be tapped.
  - `testDiscoverRowOpensATitleFromStubsAndComesBack`: "stub catalog row never drew".
  - `testLandscapeHidesTheTabBarAndPortraitBringsItBack`.
  - `testCrawlPlayers` also failed identically on HEAD, with "player.options / player.captions refuses a touch".
  - This was the first E2E-iOS run on 18.6 that I could find any record of. These need their own task.
- **The 18.6 sim was missing OpenStream's app-group container,** because the earlier run installed a build made with `CODE_SIGNING_ALLOWED=NO`. Installing the ad-hoc signed build fixed it. The baseline run then left the HEAD (031ecc2) Debug build installed there; the owner's data on that sim was restored.
- **The mobile MCP can't drive the 18.6 sim:** its helper app was removed from the sim. I used `simctl` instead.

## Gates run
- code-anti-slop pass → removed 0. My diff is 2 test lines plus 2 comments that say why.
- swift test (`--scratch-path …/iphone-ios18/spm`):
  - Pass 1 failed with 5 issues. These were `AppleManifestRefreshTests` "Refreshing an add-on saved without skip…" (4 issues) and the known `AppleLiveZappingTests.supersededLiveProbe…`.
  - **Pass 2 was a clean full pass: 3439 tests in 426 suites.**
- xcodebuild OpenStream iOS Debug, iOS 27 sim 73E49263 (`~/Developer/sim-dd-iphone18`) → succeeded, all 9 edited Sources files recompiled (1 each).
- xcodebuild OpenStream iOS Debug, iOS 18.6 sim 7530ECB2 → succeeded as an 8 s no-op with 0 recompiles. Both sims share one Debug-iphonesimulator product, built just before.
- E2E-iOS on iOS 27: 37 passed, 4 failed, 104 skipped. The failures were `testCrawlLive` (AirPlay, known), `testCrawlPlayers` (skip, known) and the two tests fixed above. A rerun with the fixes passed 3/3, including `…DiscoverStackAlive`.
- E2E-iOS on iOS 18.6, with the fixes: 34 passed, 8 failed, 103 skipped. The failures were the 6 HEAD-baseline tests above plus `testCrawlLive` and the Messages bubble (known). The fixed tests passed 3/3.
- Owner build xcodebuild Release + add-ons → succeeded, all 9 files recompiled. `sdk-floor-check.sh` exit 0.
- zero-byte check → clean.

## Diff
```
 M AGENTS.md (driver's, not mine)   M Apps/OpenStreamiOSUITests/AppleiOSUITests.swift (this run, +4/-3)
 M Sources/OpenStreamApple/{AppleAddMediaServerView,AppleAlignedTabTitle,AppleDevSourcesImport,AppleDiscoverView,
   AppleHomePhoneHeroLayout,AppleLocalLibraryStore,AppleMediaPlaybackView,AppleMediaServerClient,OpenStreamRootView}.swift
 M Tests/OpenStreamAppleTests/{AppleHeroPortraitArtTests,AppleMediaServerTests}.swift
?? specs/iphone-ios18-discs-2026-10-15.md  specs/iphone-ios18-report-2026-10-16.md
 13 files changed, 324 insertions(+), 49 deletions(-)
```

## Notes for the reviewer
- `AppleMediaPlaybackView.swift:286-310`: on iOS, nothing can close the player while the pre-route spinner is up, and that wait lasts 12–14 s on a disc read. The black screen it replaced had no close either, so this isn't a regression. It is likely the next thing the owner hits.
- In the 18.6 top screenshot, the hero shows "Movie" and Resume but no title above them. This may be the title logo still loading 15 s after launch; worth checking.
- `AppleManifestRefreshTests` failed only in pass 1. That pass included the cold build, so a timing cause is likely. The full run straight after was clean.
- Run scripts are on the mini in `/Volumes/DevExt/dev/openstream-build/iphone-ios18/` (`gates.sh`, `gates2.sh`, `ios18-e2e.py`), logs in `gates/`. The baseline tree, its DerivedData and my E2E scratch folders in `/tmp` are deleted. No sim is booted. Nothing was committed and OfficePlus was not touched.
