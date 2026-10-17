## Done
- **Fix 1: handed the trailer wrap and startup timeout back to the hero-trailers branch.** Files: `AppleHomeBillboard.swift`, `AppleHeroRotationCycle.swift`, `AppleHeroTrailerGateTests.swift`, `AppleHomePhoneHeroTests.swift`. I reverse-applied this lane's own diff to those four files, so they now match HEAD. That removes the `.task(id: "startup:…")` block, the `dueDate` guard and its doc comment, and both test renames.
- **Fix 2: the 60 pt height slack now applies only on iOS.** File: `AppleDiscoverHeroLayoutReader.swift:8-20`. The enum is renamed `AppleDiscoverViewport` → `AppleHomePageViewport` at both call sites (`AppleDiscoverView.swift:398`, `AppleMediaSourceViews.swift:3361`). `barSlack` is 60 on iOS and 0 elsewhere, so Mac and visionOS windows take every resize. `settled` gained a `barSlack:` parameter that defaults to the platform value, so the iOS behaviour stays testable in the macOS SwiftPM gate: `theBarsDoNotResizeTheHomePage` passes 60 explicitly. A new `#if !os(iOS)` test, `aWindowTakesEveryResize`, checks the real default.
- **Fix 3: removed the one-line helper and its test.** Files: `AppleHeroPortraitArt.swift`, `AppleHeroPortraitArtTests.swift`, `AppleHomePhoneHero.swift:46-52`. `drawsTitle(_:videoIsShowing:)` and its test are gone. The view's own property is now `videoIsShowing ? true : showsTitle`, and the titled-poster comment is kept.

## Not done / unclear
- **Hero cycle wrap and 8 s trailer timeout:** this lane no longer has them, by design. The hero-trailers branch has to land them.
- **iPad Stage Manager:** iPad is iOS, so a height-only resize under 60 pt there still keeps the old height. The review allowed this ("iOS-only").

## Gates run
- **code-anti-slop pass:** removed 1 public one-line helper and 1 tautological test. Replaced a hand-passed `barSlack: 0` test with one that checks the real platform default. No leftover comments or dead paths.
- **swift test --no-parallel** (compile lane, `iphone-jank-spm`): pass, 3479 tests in 431 suites, both before and after the final test edit.
- **xcodebuild** (compile lane, Debug, generic destinations):
  - iOS app plus UI tests: BUILD and TEST BUILD SUCCEEDED. All 7 touched files recompiled (grep count 1 each).
  - macOS, visionOS, tvOS: BUILD SUCCEEDED. `AppleDiscoverHeroLayoutReader`, `AppleDiscoverView`, `AppleMediaSourceViews` and `AppleHomeBillboard` recompiled on each.
- **Jank capture** (`testB8DiscoverJank`, iOS 18.6 sim `7530ECB2`): test rc=0, **hero drawn: 2**, hero cycle page: 3, trailer start: 4. The "discover body" count is 0 because that trace came from the earlier lane's temporary instrumented build; no source emits it now.
- **E2E-iOS** (`73E49263`, iOS 27): 8 selected, 6 passed, 0 failed, 2 skipped. Passed: testCrawlDiscover, testCrawlLibrary, testBillboardPlayStartsWithoutFailure, testLegacyDiscoverNavigationAndPlayerAccessibilityIsolation, testPlayerCoverRoundTripInLandscapeKeepsTheDiscoverStackAlive, and AppleiOSStubSmokeUITests/testDiscoverRowOpensATitleFromStubsAndComesBack. The two hero-title tests skipped because `OPENSTREAM_TEST_HERO_TITLE` isn't set.
- **zero-byte check:** clean.
- **Lock wait:** the sim lock first timed out after 20 min behind the avp iPad job, then ran at 16:31.

## Diff
```
 M Apps/OpenStreamiOSUITests/AppleUXCaptureUITests.swift
 M Sources/OpenStreamApple/AppleDiscoverView.swift
 M Sources/OpenStreamApple/AppleHomePhoneHero.swift
 M Sources/OpenStreamApple/AppleHomePhoneHeroCarousel.swift
 M Sources/OpenStreamApple/AppleHomePhoneHeroLayout.swift
 M Sources/OpenStreamApple/AppleMediaSourceViews.swift
 M Tests/OpenStreamAppleTests/AppleHeroPortraitArtTests.swift
?? Sources/OpenStreamApple/AppleDiscoverHeroLayoutReader.swift
?? design/qa/iphone-feedback-checklist.md, specs/iphone-jank-{,report-,review-}2026-10-17.md
 7 files changed, 122 insertions(+), 59 deletions(-)
```

## Notes for the reviewer
- `AppleDiscoverHeroLayoutReader.swift:16`: the default argument is `Self.barSlack`, so it can't be read as the parameter shadowing itself.
- `aWindowTakesEveryResize` sits inside `#if !os(iOS)`, so it would never run in an iOS test host. That's intentional.
- **Mini cleanup:**
  - Deleted the internal `sim-dd-iphone-jank-fix`, the DevExt `dd-fix-*` folders, and the `/tmp` scripts and fixtures. Internal disk is at 20 GB free.
  - The capture output stays in `DevExt/…/iphone-jank/out/fix-iPhone15ProMaxiOS18-1632/`. The `mv` there printed a harmless chown warning.
  - The 18.6 sim `7530ECB2` is still booted because hero-trailers' `ht-e2e2.sh` now holds the lock and uses it. I left it alone.
