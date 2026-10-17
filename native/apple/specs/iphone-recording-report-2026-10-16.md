E2E is at 27 passed with 2 failures; the background watcher will notify me when it finishes.

Main's rerun of the two failing E2E tests is running; I'll continue when it reports.

Waiting for the testCrawlPlayers rerun on this branch.

Main's second testCrawlPlayers run is in progress.

## Done
- **3 "Open Season 3" parsed as the show "Open"**: reproduced on main. The library trace showed `Open.Season.3.2010…` and `Open.Season.2.2008…` as `kind=show "Open"`, and `Open.Season.2006…` as the film "Open". Fixed in `AppleLibraryTitleParser.swift`:
  - In a file name, "Season N" followed by a year, with no episode token, is now part of a film title.
  - A folder with the same shape is skipped only when the file name has it too, so other season folders still work.
  - "Season 2006" (a year) no longer cuts the title.
  - Parser version is now 3, so earlier cached misses get retried.
  - After: all 4 files are movies ("Open Season 3" 2010, "Open Season 2" 2008, "Open Season" 2006, "Open Season Scared Silly").
- **2 Top 10 art**: on main the art does arrive now, but the rows only appear after ~13 s on every launch, because the whole Netflix file is downloaded every time. Fixed:
  - `AppleNetflixTop10.swift`: one shared client keeps the parsed week on disk and asks Netflix at most once a day, using the file's ETag (a 304 reuses the saved week). After: rows with art by ~4.5 s.
  - New `AppleTop10ArtworkStore.swift`: TMDB search by title and type, exact name or original name, newest release wins; kept on disk per title, misses retried after a day.
  - Cards read the saved match on their first frame. The owner-setup sim has no TMDB key, so the TMDB path is covered by unit tests only.
- **4 Live**: reproduced on main: the "IPTV · Importing · 0 channels · Zero KB · Cancel" card sat over the saved lineup. "No channels" did not show first; main already fixed that. Fixed:
  - `AppleIPTV.swift` + Live and Channel Manager: refreshing a lineup that is already on screen no longer shows the import card.
  - The card hides its count line while nothing has been counted.
  - A provider timeout under the saved lineup gets one quiet retry after 30 s (seen in the trace at 50.6 s).
  - Channel Manager now says "Can't reach IPTV." in grey instead of the long red setup advice.
- **6 YouTube overlays**: reproduced on main: the title strip, link, "More videos", logo and pause glyph showed from 5.8 to 9.1 s. Fixed in `AppleTrailerRevealPolicy.swift`:
  - On iPhone, iPad and Vision Pro the artwork stays up until 4.5 s of the trailer has played, then the trailer shows. Cap 12 s.
  - Nothing of YouTube's is hidden or cropped (the terms rule from round 3 still holds).
  - After: artwork until 8.2 s, then a clean trailer.
- **Episode row jump**: the ~28 pt came from a "Downloading…" text line (plus its 12 pt spacing) inserted above the episodes. Removed it from both footers in `AppleDiscoverView.swift`. The round Download button now shows a progress ring instead (`AppleTitlePageSections.swift`).
- **5 Blu-ray ISO**: already fixed on main. The title page shows only Play; added a test for a 27.8 GB share ISO.
- **7 "oStream 749 ms" capsule**: it is iOS's own Hang Detection HUD (Settings › Developer), not our code. It reports real main-thread hangs in our app, so there is nothing of ours to remove; the hang itself is not traced yet.

## Not done / unclear
- **1 Launch**: on main, on the iOS 18.6 sim, the cover lifts at 1.35 s and rows draw at 2.2 s, not 4 s. Drawing the saved rows before the index load got rows at 1.34 s. But the billboard then locked onto a pick made before Continue Watching was known: "Brand New Day · Play" instead of "Homecoming · Resume". I reverted it; it needs the billboard to accept a late Continue Watching pick. The owner should decide.
- **7**: the 540–763 ms hang (after the full-screen trailer, and on Settings › Sources) still needs a hang trace.
- **Not run**: E2E on the iOS 18.6 sim (this tree's `run-e2e.py` only targets the iOS 27 sim). DevPlus check (no Apple Development identity on the mini). Release builds for tvOS, visionOS and macOS (I touched no code inside `#if OPENSTREAM_ADDONS`).
- **Unresolved E2E failure**: `testCrawlPlayers` failed twice on this branch and passed twice on main. After "scrubber to 10 %" it read 6 s and 9 s against a >10 s threshold; main read 12 s and 15 s at the same step. I believe it is flaky, since no player code changed, but it is not proven.

## Gates run
- code-anti-slop pass → nothing removed; the new comments are "why" notes (diff reviewed).
- `swift test --no-parallel` → pass 3453/428 (final, after the last changes). One earlier parallel run had a 60 s timeout in `AppleMacCaptionsSelectionTests` (Mac captions, not touched here).
- xcodebuild OpenStream iOS Debug (iOS 18.6 sim) → recompiled all 12 edited files. AppStore-iOS Release → BUILD SUCCEEDED; Top10Store, Top10Lookup and DiscoverView recompiled.
- E2E-iOS (iOS 27 sim) → 39 passed, 2 failed, 104 skipped:
  - `testCrawlLive` (AirPlay button): also fails on main.
  - `testCrawlPlayers`: see above.
- zero-byte check → clean.

## Diff
15 files changed, 327 insertions(+), 109 deletions(-); new files `AppleTop10ArtworkStore.swift` and `AppleTop10ArtworkStoreTests.swift`. Before/after screenshots for items 2, 4 and 6, plus the HUD frame from the recording, are in `design/2026-10-16-iphone-recording/` (item 3's evidence is the library trace quoted above). Nothing committed.

## Notes for the reviewer
- `AppleLibraryTitleParser.swift:40-50`: the Open Season files get new group ids, so any watch history saved under the old "Open" groups won't carry over.
- `AppleMediaSourceViews.swift`, `scheduleQuietRetry`: the retry runs `reload()` again, which may re-select the channel; worth a look on a device.
- `AppleTrailerRevealPolicy.swift`: Vision Pro now uses the same 4.5 s wait. The Codex Vision Pro lane may notice the change.
- The iOS 18.6 sim (7530ECB2) is left with this branch's Debug build installed and no test data added. Mini scratch is deleted, sims are shut down and the lock is released.
