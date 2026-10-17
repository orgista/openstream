The avp-ipad job is still early (16:29), so the DevTV run is roughly 45–90 minutes away; the background watcher will wake me when the lock frees.

My run is queued behind the avp-ipad job (lock held since 17:21). I'll pick it up when the background task finishes.

The DevTV run is queued behind the unmatched E2E job. I'll report when it finishes.

The run is queued or running on DevTV (r3); I'll review its screenshots when it completes.

The r4 build and run are going in the background; I'll check the result when it finishes.

The DevTV run is retrying on the lock in the background (up to 5 attempts). I'll pick up the screenshots when it lands.

Run r5 is queued; waiting on its result.

Run r6 is queued; I'll check its screenshots when it finishes.

DevTV run r7 with the moved wordmark is queued; I'll check it when it completes.

The E2E-tvOS test is queued; I'll write the report once it finishes.

## Done
- **Wordmark**: the tvOS app now draws a 1920×1080 JPEG for each carousel page: the hero's backdrop, cropped to fill, with its trimmed wordmark bottom-left over a light corner scrim (no scrim when there's no wordmark). The files go in the app group's `Library/Caches/topshelf-art`. There's at most one per page (≤12), and unused files are deleted on each publish and when the setting is turned off. If a wordmark doesn't load, the page gets the plain backdrop under its own file name, so the next publish tries the wordmark again. — `Sources/OpenStreamApple/AppleTopShelfArtwork.swift` (new), `AppleTopShelfSnapshot.swift`, `Apps/OpenStreamTopShelf/TopShelfProvider.swift` (uses the local file if it exists, else the remote backdrop)
- **Hero sync**: Discover on tvOS gives its hero pages (with the billboard's textless backdrop and wordmark) to `AppleTopShelfHeroFeed`. The root view republishes when they change, and the snapshot gains a `heroes` field. The carousel shows heroes in order, then Continue Watching; resume heroes are labelled "Continue Watching". Before Home has drawn, it falls back to Continue Watching then Top Picks as before. — `AppleDiscoverView.swift`, `OpenStreamRootView.swift`, `AppleTopShelfPublisher.swift`, snapshot builder and its mirror in the extension
- **Trailers hook**: new `previewVideoURL` field. `AppleTopShelfTrailerPolicy` only accepts a direct https `.mp4`/`.m4v`/`.mov`/`.m3u8` with no query string, never YouTube. Nothing fills it yet.
- **Swipe up for full screen**: on DevTV, Up from the focused oStream icon goes full screen and Right pages through (5 pages). The `.details` style, page count and image size were fine. The one real problem was that the full-screen paging chevron (mid-height, left) covered the wordmark. I moved the wordmark into the band at 600–740 px from the top, which clears the chevron and still shows above the app row when collapsed. Screenshots in `design/2026-10-16-topshelf2/` (devtv-1-shelf-wordmark, devtv-2-full-screen, devtv-3-next-page).
- **UI test runs on hardware**: Home is pressed twice, because DevTV's TV button opens the TV app first. Focus is read from snapshots. "Stub Movie" is only expected when stubs are in use. New assertions check that Up removes the swipe-up prompt and Right shows "page N of M". — `AppleTVTopShelfUITests.swift`

## Not done / unclear
- I couldn't reproduce the owner's "swipe doesn't work" on DevTV. On the old build the extension served remote CDN backdrops, which may have been slow on OfficePlus; now it serves local files. That's my guess, not something I proved.
- DevTV's Top Picks shelf has no backdrops, which is why the pre-hero fallback showed only 2 pages.
- In full screen, the system drew no title or details text in my screenshots, only the picture, paging chevrons and page dots.

## Gates run
- Anti-slop pass: changed 1 thing (typed the extension's page tuples instead of `Optional("…")` wrapping). No dead code or debug prints left. The extension repeats a small https check because it can't import the package.
- swift test (serial, `--no-parallel`): pass, 3452 tests in 428 suites (run before and after the last change); Top Shelf filter 26/5.
- xcodebuild tvOS Debug, tvOS Release (no add-ons) and iOS Debug: BUILD SUCCEEDED, and the recompile grep was ≥1 for all 6 edited files (iOS: the 5 shared files).
- DevTV (signed Release + add-ons build, real sources): Top Shelf UI test passed (r7) with the full-screen and paging assertions.
- E2E-tvOS simulator (`run-e2e.py`): `AppleTVTopShelfUITests` passed (carousel true, "Stub Movie" matched); the Top Shelf files were confirmed recompiled.
- Zero-byte check: clean.

## Diff
```
 M Apps/OpenStreamTVUITests/AppleTVTopShelfUITests.swift      | 39
 M Apps/OpenStreamTopShelf/TopShelfProvider.swift             | 38
 M Sources/OpenStreamApple/AppleDiscoverView.swift            | 13
 M Sources/OpenStreamApple/AppleTopShelfPublisher.swift       |  7
 M Sources/OpenStreamApple/AppleTopShelfSnapshot.swift        | 191
 M Sources/OpenStreamApple/OpenStreamRootView.swift           |  2
?? Sources/OpenStreamApple/AppleTopShelfArtwork.swift
?? Tests/OpenStreamAppleTests/AppleTopShelfArtworkTests.swift
?? design/2026-10-16-topshelf2/   (3 DevTV screenshots)
?? specs/topshelf2-2026-10-16.md  (was already there)
 6 files changed, 252 insertions(+), 38 deletions(-)
```
Not committed.

## Notes for the reviewer
- `AppleTopShelfSnapshotWriter.write` is now `async`, and drawing only happens on tvOS (`defaultArtwork`). A publish that gets cancelled throws `CancellationError`; the publisher ignores it quietly, because a newer publish replaces it.
- Wordmark placement was measured on the DevTV screenshots and lives in `AppleTopShelfArtworkLayout` (`wordmarkBottom`, `wordmarkBox`). Its `version` constant forces a redraw when the layout changes.
- The pictures are a little soft on 4K: one 1920 file is used at both 1x and 2x.
- The scrim is a light radial fade (55% black at the bottom-left corner). The spec asked for it, but the owner's no-scrim rule should be confirmed.
- DevTV now has this lane's Release + add-ons build installed (the test installed it) and was last left on the home screen. OfficePlus was not touched.
- The lock was busy most of the session. The DevTV harness is at `/Volumes/DevExt/dev/openstream-build/topshelf2/devtv.sh` (`build` / `run <label>`). Its build folders (`topshelf2-dd-*`, `topshelf2-spm`, `topshelf2/dd-devtv`) were left for re-runs. Dev-Mini is down to about 19 GB free, and disk-guard is warning about it.
