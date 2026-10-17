**Verdict: FIX** (small items; the design is sound and the testCrawlPlayers failure is not caused by the trailer change).

**1. testCrawlPlayers — trailer ruled out; cause is the test's clock assertion plus a faster app**
- The trailer cannot touch the main player. On the title page, `titlePageIsCovered` (AppleDiscoverView.swift:3426) swaps the whole page for `Color.clear` the moment the player presents, so the trailer WKWebView is torn down. The Discover billboard likewise drops its web view when covered (`shouldPreview`, AppleHomeBillboard.swift:601). The reveal rule only decides when the art lifts; the web view plays underneath in both versions, and the 15 s startup timeout still exceeds the new 12 s cap, so nothing stalls or gets killed.
- The step that fails does not scrub. The fixture movie is 1800 s (run-e2e.py:437), so 10 % would read ~180 s. Main reads 12–15 s and the branch 6–9 s: both are just the paused playback clock. The assertion `observed > 10` (AppleiOSUITests.swift:3813) therefore passes only if playback ran more than 10 s before the crawl reached the skip buttons.
- Why the branch gets there sooner: on main every launch streams and parses Netflix's all-weeks TSV through `URLSession.shared` (the network stub only wraps the bounded loader, AppleNetworkStub.swift:30), about 13 s of CPU and network under the crawl. On the branch it is read from disk after the first run. The crawl snapshots run faster and the skip step arrives ~6 s earlier. (The mini's iOS run logs were already cleaned, so this is from code, not a trace.)
- Fix (test, not this diff): AppleiOSUITests.swift:3807 — make the scrub land or drop it: simplest, before pausing, wait until `crawlPlaybackSeconds() > 10` (poll ≤15 s), then pause and measure. Record in the report that the failure is the test's elapsed-time dependence, not "flaky".

**2. Parser v3** — rules match the spec. File-only trigger (`stem`), folder filtered only when the file carries the shape, year after "Season" no longer a season (`\d{1,3}\b`), version 3 is compared in AppleLibraryMetadataResolver.swift:72 so cached misses retry. Tests cover `Show.Season.3.1080p` folder, `Show Season 3 (2010)` folder with a plain file, and the episode-token case. No fix.

**3. Top 10 cache, ETag, TMDB store** — correct: 304 keeps the week and refreshes `fetchedAt`; errors fall back to the stored week with `isStale` after 30 h; country mismatch ignored; failed TMDB requests are not remembered; capacity 200. Two notes, no code change required:
- `AppleTop10ArtworkStore.shared` is first touched inside Discover's `body` (AppleDiscoverView.swift:1344): its init reads and decodes the JSON file on the main thread once. Small file; acceptable, but note it in the report.
- Top 10 cards with a TMDB-only match open through the `fixture.example` "oStream" library source in App Store builds (AppleTop10ArtworkStore.swift:37). That was the shared-link path before; spot-check one such title page in a no-add-ons Release build.

**4. IPTV import card and quiet retry**
- Card suppression is right: Live announces only when `cached[source.id]` is empty, Channel Manager only when nothing is listed; the count line hides at 0/0.
- FIX: AppleMediaSourceViews.swift:778 — `quietRetry` is never cancelled when the Live view goes away; after 30 s it calls `reload()` on a dead view. Cancel it in the view's existing `.onDisappear`, or drive it from a `.task(id: quietRetryGeneration)` so SwiftUI cancels it.
- `startFirstChannelIfNeeded` is guarded by `selectedChannel == nil` (line 791), so the retry does not re-select. OK.

**5. Slop**
- FIX: AppleTitlePageSections.swift:782-789 duplicates the episode ring at AppleDiscoverView.swift:6131-6136 (same stroke 2.5, 0.25 track, trim, -90°). Extract one small `AppleDownloadRing(fraction:)` view and use it in both places.
- FIX: AppleChannelManagerLoadTests.swift:28 — the new test is a free `@Test func` outside the file's `AppleChannelManagerLoadTests` suite. Move it inside.
- FIX: AppleTop10ArtworkStoreTests.swift `aBluRaySizedImageOnAShareIsABluRay` belongs in AppleDiscPlaybackTests.swift, not the artwork store suite.
- FIX: AppleDiscoverView.swift:10057 and :10771 carry the same two-line comment verbatim. Keep the first, make the second "see the movie footer".
- Removed identifier `detail.download.progress` has no remaining references in tests or sources. OK.
- Trailer policy comments and tests are "why" notes and match N70/N75. OK. Report gates (3453/428 unit, Release AppStore-iOS build) stand.
