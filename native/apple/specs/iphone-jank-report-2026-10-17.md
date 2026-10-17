## Done
- **Checklist** — `design/qa/iphone-feedback-checklist.md` — 65 rows from OWNER-TODO, the 10-15/10-16 iPhone specs and today's messages. The mini's feedback log has one entry, which is Apple TV only. Counts: **3 fixed, 1 partly fixed, 6 verified on iOS 18.6, 1 still broken (ISO, owned by iso-open), 12 need the owner, 42 not checked on iOS 18 here**.
- **Hero relayouts on the iPhone (§1)** — new `AppleDiscoverHeroLayoutReader.swift`, plus `AppleHomePhoneHeroLayout.swift`, `AppleDiscoverView.swift:317`, `AppleMediaSourceViews.swift`. Two causes:
  - The bar readings wrote state on the Discover view on every frame the iOS 18 bar collapsed or expanded, and the iPad reading did the same on iPhone. They now live in a small modifier, so Discover only redraws when the drawn layout changes.
  - The tab bar's 82.67 ↔ 83 pt flicker counted as a new layout, which redrew the hero with identical values.
  - The page size now ignores the bar's 18 pt. Library had the same unsettled reader and uses the new one too.
  - Before vs after on the 18.6 sim, same script: `hero drawn` 8 → 2; Discover body runs 82 → 41 (about 30 → 1 during the drags).
- **Hero cycle gone** — `AppleHeroRotationCycle.swift:43` — the cycle wraps from the last page again, as build 15 did and as REA round 3's #1 recommends. f82ef99 had made it stop after page 5. The new `hero cycle` trace lines show pages moving on both sims.
- **A hero trailer that never appears holds the page forever** — `AppleHomeBillboard.swift:678` — an autoplay trailer not on screen within 15 s now drops back to the still, which frees the cycle (REA #2).
- **No title while a titled poster's trailer plays** — `AppleHomePhoneHero.swift`, `AppleHeroPortraitArt.drawsTitle` — reproduced on the 18.6 sim with Spider-Man; the name now shows while the video covers the poster.
- **Capture test** — `AppleUXCaptureUITests.testB8DiscoverJank` plus `dev-mini:/Volumes/DevExt/dev/openstream-build/iphone-jank/jank.sh` record video at 10 fps and count trace lines.

## Not done / unclear
- **Owner's iPhone** — it showed as unavailable (not connected or locked) all session, so nothing was installed and no trace was pulled. DevPlus wasn't used either.
- **Trailer decisions for the owner (from REA round 3)** — YouTube's overlay (d70aea9), the 16:9 title-page box (13a2677), the 4.5 s reveal hold, and 12 s vs 5 s hero pages. I recorded these and didn't change them. I also left out letting a pressed trailer play under Low Power Mode (REA #9).
- **The owner's phone has started no hero trailer since build 17** — Low Power Mode or "Auto-Play Video Previews" being off would explain it; worth asking.
- **The rest of the app wasn't walked on iOS 18.6** — 42 rows remain "not checked".

## Gates run
- code-anti-slop pass → removed 0 comments, 0 dead paths; the old measuring state and helper were deleted, not kept.
- `swift test --no-parallel` → **3479 tests in 431 suites pass**. Parallel runs flaked on unrelated timing and web-server tests while the mini's load was 20–80; those pass on their own.
- xcodebuild:
  - iOS sim: recompiled all 9 edited files, confirmed by grep.
  - tvOS and visionOS: BUILD SUCCEEDED, shared files recompiled.
  - E2E-iOS on iOS 27: 41/42, the only failure `testCrawlLive` (AirPlay, known).
  - E2E-iOS on iOS 18.6: 41/43, failures `testCrawlLive` and the Messages share bubble, both listed as known in the ios18-e2e report. No new failures.
- zero-byte check → clean.

## Diff
```
 M Apps/OpenStreamiOSUITests/AppleUXCaptureUITests.swift      | 33 +
 M Sources/OpenStreamApple/AppleDiscoverView.swift            | 46 +-------
 M Sources/OpenStreamApple/AppleHeroPortraitArt.swift         |  8 +
 M Sources/OpenStreamApple/AppleHeroRotationCycle.swift       |  6 +-
 M Sources/OpenStreamApple/AppleHomeBillboard.swift           | 11 +
 M Sources/OpenStreamApple/AppleHomePhoneHero.swift           | 11 +-
 M Sources/OpenStreamApple/AppleHomePhoneHeroCarousel.swift   |  3 +
 M Sources/OpenStreamApple/AppleHomePhoneHeroLayout.swift     | 14 +-
 M Sources/OpenStreamApple/AppleMediaSourceViews.swift        | 14 +--
 M Tests/…/AppleHeroPortraitArtTests.swift                    | 53 +
 M Tests/…/AppleHeroTrailerGateTests.swift                    |  7 +-
 M Tests/…/AppleHomePhoneHeroTests.swift                      |  8 +-
?? Sources/OpenStreamApple/AppleDiscoverHeroLayoutReader.swift
?? design/qa/iphone-feedback-checklist.md
```
12 files changed, 147 insertions(+), 67 deletions(-). Nothing committed.

## Notes for the reviewer
- **Apple TV:** the wrap also changes the Apple TV hero, which shares the same cycle code. Build 15 wrapped there too.
- **Page size:** `AppleDiscoverViewport.barSlack` (60 pt) ignores height-only changes smaller than that. A small vertical Stage Manager resize on iPad keeps the old height until the next larger change.
- **Sim not reproducing the bug:** the simulator usually reports whole-point insets, so the tab-bar part of the bug only showed in one probe run. `theOwnersIOS18SessionDrawsTheHeroAtMostTwice` replays the owner's real readings and fails on the old code.
- **18.6 sim state:** my generic builds lost the app-group container on the 18.6 sim (7530ECB2). An entitled reinstall recreated it. Its data was snapshotted to the mini's internal disk around E2E, restored, and the snapshot deleted. The sim now has this lane's Debug build installed.
- **Cleanup:** my DerivedData and SwiftPM scratch folders on the mini are deleted (disk is back to 29 GB free); evidence stays in `iphone-jank/out/`.
