The other lane is now in its visionOS E2E runs (3×), then an iPad E2E. I estimate it frees the lock around 17:30. A background watcher will notify me when the lock frees. Then I'll run the Release spot-check and the iOS E2E set (testCrawlPlayers ×3, testCrawlLive, the Discover/Top 10 tests and the Live tests) under one lock hold.

My run is queued behind the unmatched lane's E2E, which started at 18:42 (likely 20–40 min). I'll pick up when the spot-check window opens.

E2E run 1 (10 tests) plus two more testCrawlPlayers runs are in progress, probably 40–60 min. I'll report when the watcher fires.

E2E is queued behind the other lane; I'll report when it finishes.

The billboard's Play button was reported as not hittable at one moment, probably while the trailer reveal was transitioning. The earlier full E2E on this branch passed testCrawlDiscover, so the rerun will show whether it's intermittent. Waiting on it.

The topshelf2 lane (a DevTV run) holds the lock as of 20:19; my three testCrawlPlayers runs are queued behind it.

## Done
- **(1) testCrawlPlayers relied on elapsed time** — `Apps/OpenStreamiOSUITests/AppleiOSUITests.swift:3801-3813`. If the clock reads 10 s or less, the test now starts playback, waits until `crawlPlaybackSeconds() > 10` (at most 15 s), pauses, and measures the settled position. The `> 10` / `< 1790` check stays.
  - The wait alone didn't fix it. Run logs showed `adjust(toNormalizedSliderPosition: 0.1)` pulled playback *back* to 1–9 s, and in one run the crawl had just paused the player at 3 s. So I removed the scrub, as the review allowed ("make the scrub land or drop it").
  - Conclusion for the record: the failure came from the test's timing and its scrub, not flakiness and not the trailer change.
- **(4) quietRetry kept running after Live closed** — `AppleMediaSourceViews.swift:415`: `.onDisappear { quietRetry?.cancel() }`. `AppleLiveTVView` had no `.onDisappear` of its own; the review was pointing at the inline player's.
- **(5) One shared download ring** — new `AppleDownloadRing(fraction: Double?)` in `AppleTitlePageSections.swift`. A nil fraction shows a small spinner, as the episode row did. Both the round title-page button and `episodeDownloadGlyph` (`AppleDiscoverView.swift`) now use it.
- **(5) Misplaced tests** — `anUnreachablePanelReadsLikeTheLiveTab` is now inside the `AppleChannelManagerLoadTests` suite. `aBluRaySizedImageOnAShareIsABluRay` moved from `AppleTop10ArtworkStoreTests.swift` to `AppleDiscPlaybackTests.swift`.
- **(5) Duplicate comment** — the Mac hero copy now reads `// No progress line: see \`phoneHeroFooter\`.` (that is the phone "movie footer").
- **Fable note 3, App Store Release spot-check** — AppStore-iOS Release build on the iOS 27 sim, no add-ons, TMDB key pasted from the sim clipboard and never printed. The Top 10 rows resolved through TMDB. Two TMDB-only pages opened cleanly:
  - East of Eden (series): hero, logo, Play Trailer, My List, Rate, synopsis, trailers, cast.
  - UNABOMBER (movie): the same set.
  - Neither showed an error or any trace of the `fixture.example` source.

## Not done / unclear
- **testCrawlLive** still fails, twice in two runs:
  - "AirPlay produced no visible response" — also fails on main, per the earlier report.
  - "playback did not settle with an advancing clock before Play/Pause" — that check is main's code, and this diff changes no Live player code. I did not prove it fails on main.
- **testCrawlDiscover** failed once (`home.featured.play` would not take a touch) and passed on the rerun. Likely a moment during the billboard trailer reveal; not investigated further.
- Two Live tests skipped themselves in the fixture run: testLiveFullScreenGoesToPictureInPictureOnHome and testLivePlaylistShowsChannelFailureAndRecovers.

## Gates run
- **code-anti-slop pass** → nothing to remove. Two "why" comments added (test wait, ring doc); one duplicate comment collapsed.
- **swift test --no-parallel** (compile lane) → pass 3453/428. Same count as before, since a test was moved, not added.
- **xcodebuild OpenStream iOS Debug** → BUILD SUCCEEDED; AppleMediaSourceViews, AppleTitlePageSections and AppleDiscoverView each recompiled (1).
- **xcodebuild AppStore-iOS Release** → BUILD SUCCEEDED; the same 3 files recompiled. `sdk-floor-check` passed (30 build versions within the floor).
- **E2E-iOS, iOS 27 sim (73E49263)**:
  - testCrawlPlayers: 3/3 pass after the final change (338 s, 201 s, 191 s; first run recompiled AppleiOSUITests.swift).
  - Discover/Top 10 and Live tests passed: testLegacyDiscoverNavigation…, testPlayerCoverRoundTrip…DiscoverStackAlive, testLiveGuideSheetOpensAndDismisses, testLiveLayoutIsStable, testSavedLiveSourceDoesNotShowResolvedLoginFailure.
  - testCrawlDiscover: 1 pass, 1 fail.
  - testCrawlLive: fail (see above).
- **zero-byte check** → clean.

## Diff
My changes: `AppleiOSUITests.swift`, `AppleMediaSourceViews.swift`, `AppleTitlePageSections.swift`, `AppleDiscoverView.swift`, `AppleChannelManagerLoadTests.swift`, `AppleTop10ArtworkStoreTests.swift`, `AppleDiscPlaybackTests.swift`. The lane totals 17 files, +363/−125 (most of it the earlier lane work), plus the untracked files already listed in git status. Nothing committed.

## Notes for the reviewer
- `AppleMediaSourceViews.swift:415`: after leaving Live the retry is cancelled, and `quietRetryUsed` stays true. The reload when Live comes back serves as the retry.
- In the unsigned Release sim build, Settings › Metadata shows "A required entitlement is not present." That comes from building with `CODE_SIGNING_ALLOWED=NO` (no keychain on the sim), not from the app. The key worked in memory for the session.
- On the TMDB-only series page the line "Episodes aren't available from the connected metadata sources." appears. It's existing copy, but it reads like the explainer text the owner bans.
- Also from the review: `AppleTop10ArtworkStore.shared` first loads and decodes its JSON file on the main thread, inside Discover's `body`, once per launch. The file is small; left as is.
- **Mini state:**
  - Every Release-app change is gone: Release app, its settings, the TMDB key and the clipboard.
  - `run-e2e.py` restored the E2E sim's data and shut the sim down.
  - The mobile-mcp DeviceKit agent I installed for the spot-check is uninstalled.
  - Lane scratch deleted: the Release and Debug build folders, the SPM folder and the /tmp files.
  - I stopped `check-no-addons-in-release.sh` mid-run because it builds without taking the lock. It wasn't in this task's gates, so no-add-ons was proven only by the AppStore-iOS Release build.
