The code edits are in, but no gate has run yet. The serial `swift test` is queued on the mini behind another chat's Release builds, which hold the compile lock (started 00:29; I don't know when they'll finish). I'll be notified when my run ends, and there's a check-in at 01:11 in case it hangs. After that come the iOS/tvOS Debug builds, then the E2E tests once the other project's iOS E2E run frees the main lock.

**Done so far (nothing committed):**
- **Required 1, disk cache** (`AppleArtworkDiskCache.swift`): a trim now frees the cache down to 7/8 of the limit, so the next few writes don't each scan the whole folder again. To make that testable, the cache's size limit can now be passed in when it is created (default 512 MB). New test `storeAfterTrimDoesNotTrimAgain`: with a 1,000-byte limit, the 11th file trims down to 8 files, and the 12th file doesn't trim again, leaving 9.
- **Required 2, one width rule** (`AppleDiscoverView.swift`): the tile width and height now come from one place on `AppleCatalogCard`, used by both the card and the shelf prefetch, so the two can't drift apart. New test `prefetchOfUnsizedArtworkMatchesTileBucket` covers the non-TMDB path: the prefetch size bucket matches the tile's at 3x, and it checks that the full-width promo card ignores the phone row style.
- **Optional 3**: added a one-line comment to each shared download/connect task saying it runs to the end even when a waiting caller is cancelled. Removed the two `try Task.checkCancellation()` calls in `AppleNetflixTop10.swift` that could no longer fire.
- **Optional 4**: removed the `nextRow(after:in:)` wrapper, inlined its one use at the call site and dropped its three `#expect`s.
- **Optional 5 skipped**: capping the first-load prefetch at 8 changes the speed-up that was measured on DevTV and adds a new number. It needs a DevPlus measurement first, not a quick edit.
- **Anti-slop pass**: nothing to remove. The new comments explain why, not what.

I'll send the full AGENTS.md §7 report, with test counts, recompile proof and the E2E results, once the gates finish.

The serial swift gate passed: 3465 tests in 429 suites. The iOS and tvOS Debug builds are now running on the compile lane, and I'll be notified when they finish. After that, the E2E tests run on the main lane, which another chat's iOS E2E run still holds.

The E2E run is queued on the mini behind another chat's iOS E2E run, which has held the main lock since 00:11. I'll be notified when mine finishes; the 01:11 check-in is still set as a fallback.

The serial swift gate (3465 tests in 429 suites) and the iOS/tvOS Debug builds have already passed. The E2E run is still waiting for the main lock: another chat's full iOS E2E has held it since 00:11 (60 minutes so far), and I can't tell when it will finish. My job on the mini retries automatically for up to about 4 hours. I'll be notified when it finishes, and I'll check again at 01:42.

## Done
- Required 1, disk cache trims to a low-water mark — `AppleArtworkDiskCache.swift` — a trim now frees down to 7/8 of the limit (`AppleArtworkDiskCachePolicy.trimTarget`), so the writes after it don't each scan the whole folder again. The size limit can be passed when the cache is created (default 512 MB) so the test can use a small one. New test `storeAfterTrimDoesNotTrimAgain`: with a 1,000-byte limit, the 11th file trims to 8 files and the 12th file leaves 9 without another trim. The old code would have trimmed again on the 12th.
- Required 2, one width rule — `AppleDiscoverView.swift` — added `AppleCatalogCard.width(sizing:rowStyle:scaledCardWidth:viewportWidth:regularWidth:)` and `height(sizing:width:)` as `nonisolated static`. The card's `cardWidth`/`cardHeight` and the shelf's `prefetchRequests` both use them; the shelf maps featured → `.portraitPromo`, ranked → `.ranked` and poster → `.catalog`. New test `prefetchOfUnsizedArtworkMatchesTileBucket` covers the non-TMDB path: the prefetch bucket equals the tile's `bucket(size:scale: 3)`, and the promo card ignores the phone row style (358 pt).
- Optional 3 — `AppleNetflixTop10.swift`, `AppleNetworkShare.swift` — added a comment to `inFlight` and `pendingConnections` saying the shared task runs to the end even when a waiting caller is cancelled. Removed the two `try Task.checkCancellation()` calls in `download(now:)` that could no longer fire.
- Optional 4 — `AppleArtworkPrefetchPolicy.swift`, `AppleDiscoverView.swift`, `AppleArtworkProgressiveCacheTests.swift` — removed `nextRow(after:in:)`, inlined the bounds check in `nextArtworkRow`, and dropped its three `#expect`s.
## Not done / unclear
- Optional 5 (limit the first-load prefetch to about 8 posters) — not a one-liner: it changes the speed-up measured on DevTV and adds a new number. It needs a memory measurement on DevPlus before anyone changes it.
## Gates run
- code-anti-slop pass → nothing to remove; the new comments explain why, not what.
- `swift test --no-parallel` (compile lane) → pass, 3465 tests in 429 suites (the worker's run had 3463; my net change adds 2 tests).
- xcodebuild OpenStream iOS Debug (simulator) → BUILD SUCCEEDED. All 5 edited source files recompiled: AppleArtworkDiskCache, AppleArtworkPrefetchPolicy, AppleDiscoverView, AppleNetflixTop10, AppleNetworkShare.
- xcodebuild OpenStream tvOS Debug (simulator) → BUILD SUCCEEDED, the same 5 files recompiled.
- E2E-iOS `AppleiOSStubSmokeUITests` → 1 passed (`testDiscoverRowOpensATitleFromStubsAndComesBack`), 1 skipped by design (`testTitlePageFillDistribution`).
- E2E-tvOS → 3/3 passed (`AppleTVStubSmokeUITests/testDiscoverRowOpensATitleFromStubsAndComesBack`, `AppleTVFocusUITests/testDiscoverHeroStillDrawsAfterTheTextlessChange`, `testDiscoverHeroButtonsAndPagingKeepFocus`).
- zero-byte check → clean.
## Diff
```
 M Apps/OpenStreamTVUITests/AppleTVPerfWalkUITests.swift   (worker's, untouched)
 M Sources/OpenStreamApple/AppleArtworkDiskCache.swift
 M Sources/OpenStreamApple/AppleArtworkPrefetchPolicy.swift
 M Sources/OpenStreamApple/AppleDiscoverView.swift
 M Sources/OpenStreamApple/AppleNetflixTop10.swift
 M Sources/OpenStreamApple/AppleNetworkShare.swift
 M (8 more worker files, untouched by this pass)
?? Tests/OpenStreamAppleTests/AppleArtworkProgressiveCacheTests.swift (edited)
 15 files changed, 875 insertions(+), 198 deletions(-)   (whole branch, not committed)
```
## Notes for the reviewer
- `AppleDiscoverView.swift` `prefetchRequests`: it passes `regularWidth: false`. That value only affects `.detailSuggestions` on iOS, which a shelf never prefetches.
- The row-style filter (`activeRowStyle(_:sizing:)`) now also applies to prefetch. Featured shelves already skipped the row style before, so the widths don't change.
- `AppleNetflixTop10.swift`: with the check in `catch` removed, a failed download now falls back to the saved Top 10 list even if the caller was cancelled. That's harmless, because the result is shared with other callers.
- The E2E runs waited about 80 min for another chat's full iOS E2E run. My scratch on the mini (`/tmp/speed2-fix-*`, the fixtures folder, `~/Developer/sim-dd-speed2-*`) is deleted. The iPad Pro sim still booted there belongs to that other job.
