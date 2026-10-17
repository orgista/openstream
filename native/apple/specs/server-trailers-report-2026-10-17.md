Both are running: the reviewer is reading the diff, and the watcher wakes me when the main Dev-Mini lock frees, probably in 1.5 to 2 hours. Nothing is committed. I'll continue when either reports back.

The main-lane job is queued behind the iPad E2E. The reviewer is still running. Waiting for either to report.

The suite is waiting on another lane's build job (started 03:11). I'll pick it up when it reports.

The gate rebuild and my E2E/DevTV job are both queued. Watchers will notify me when each finishes.

All eight builds pass again with the review fixes. My E2E/DevTV job is still retrying for the main lock, which keeps going to the pass1 lane's jobs (one since 03:41). The earlier watcher will notify me when the tvOS stage finishes.

Waiting on the iOS E2E and DevTV stages.

## Done
- **Server trailer clients** — `AppleServerTrailer.swift` (new) — Plex `library/metadata/<rk>/extras` (trailers only, best bitrate, file URL with the token, or Plex's HLS transcoder for MKV); Jellyfin `Items/<id>/LocalTrailers?userId=` and Emby `Users/<u>/Items/<id>/LocalTrailers`. An MP4/MOV plays as the stored file; anything else gets the server's own conversion through PlaybackInfo, as normal playback does. Titles not from a server are found by IMDb/TMDB id, else title + year. `AppleTrailerSourcePolicy`: server first; YouTube only after the server lookup says no; the Apple TV never gets YouTube.
- **Lookup store** — `AppleServerTrailerStore.swift` (new) — gets its sessions from the media-server library reload. Answers are kept 10 minutes in memory only. A server that doesn't answer is not cached as "no trailer". The trace shows title + outcome, never a URL.
- **Apple TV + Vision Pro hero** — `AppleServerTrailerView.swift` (new), `AppleHomeBillboard.swift`, `AppleHomeTVHeroCarousel.swift` — the server trailer plays muted, aspect-filled with no bars, after the still has loaded (same `AppleHeroTrailerGate` as iOS). It fades in once frames flow, and a watchdog gives up on a stalled stream. The tvOS carousel holds while the trailer plays and moves on after it ends. iPhone, iPad and Mac heroes are unchanged (YouTube).
- **Title page "Trailer" button** on tvOS, iPhone, iPad/Vision and Mac rows (`AppleDiscoverView.swift`, new `.trailer` focus target in `AppleTVDetailMetrics.swift`). It plays full screen with sound: a cover on iPhone/Apple TV/Vision Pro, an in-window overlay on the Mac (Esc/close).
- **Top Shelf `previewVideoURL`** — `AppleTopShelfTrailerFiles.swift` (new), `AppleTopShelfSnapshot.swift`, `AppleTopShelfPublisher.swift`, `OpenStreamRootView.swift`, `TopShelfProvider.swift`:
  - Server URLs carry tokens, so each hero page's trailer file is downloaded into the group's Caches/topshelf-trailers (≤250 MB each, ≤1 GB total, files named from the title only).
  - The snapshot carries only that file name (`shelfVideo`); the extension sets `previewVideoURL` to the file.
  - Downloads run apart from the publish and are added to the snapshot when they land.
  - `AppleTopShelfTrailerPolicy` still rejects tokenized and YouTube URLs.
- **Tests** — `AppleServerTrailerTests.swift`: 19 tests. Plex fixtures are real responses from the owner's Plex with ids scrubbed. The Jellyfin fixture follows 10.10's documented shape (no Jellyfin credential was available).
- **E2E fixture** — `serve.py` now serves a `/jf` Jellyfin fixture, and the new `testDiscoverHeroPlaysServerTrailer` uses it. Also added: an opt-in device test, `testServerTrailersWithRealServers` (runs only with `OPENSTREAM_REAL_SOURCES=1`).

## Not done / unclear
- **No real-server device check.** Neither DevTV nor DevPlus has a Plex or Jellyfin source: the "owner setup" there is the DevPlus backup (8 sources, 0 media servers). The DevTV run paged through 11 hero pages and found no trailer, because there was no server to ask (screenshot below). I didn't sign the app into your Plex with the server's own token, and didn't add a fixture server to DevTV, because sources sync through iCloud. **Owner: add Plex/Rill on DevTV, or OK either option?**
- Top Shelf playing a saved *file* as `previewVideoURL` on hardware is unproven; it needs that real-server run.
- Top Shelf trailers cover hero pages only, not Continue Watching pages.
- **Change on ServerPlus to undo:** I added two test trailers to jellyfin-demo (`Sintel (2010)/trailers/Sintel Trailer.mp4`, `Big Buck Bunny (2008)/trailers/Big Buck Bunny Trailer.mkv`). Remove them when done.

## Gates run
- code-anti-slop pass → removed 1 dead path (an unused `chain` policy, replaced by the one the hero uses) and 1 tautological test assertion. 7 bugs from an independent review were fixed: saved-file deletion on failed lookups, stalled-stream hold, stale-item failure, publish-cancelled downloads, full-screen startup timeout, stuck on-screen flag, cancelled-as-nil.
- `swift test --no-parallel` → pass 3483 tests / 435 suites.
- xcodebuild AppStore iOS/tvOS/visionOS/macOS × Debug/Release (no add-ons) → all 8 BUILD SUCCEEDED. Every edited file was recompiled (grep ≥1; TopShelfProvider=1 on tvOS).
- E2E-tvOS (sim F2107E8F, scoped) → 6/6 pass, including the new server-trailer hero test, hero paging, title-page icon row and Top Shelf.
- E2E-iOS (scoped) → 2 pass; 3 skipped by their own preconditions (`OPENSTREAM_TEST_HERO_TITLE` unset, no playable YouTube trailer in the stubs).
- DevTV (Debug, signed) → build OK; real-server test failed for the reason above; the Top Shelf test passed.
- zero-byte check → clean.

## Diff
12 modified files (+395/−40), 4 new sources, 1 new test file, 3 fixtures, `design/2026-10-17-server-trailers/`:
- `e2e-tvos-hero-server-trailer.png` — fixture trailer playing full-bleed behind the Stub Movie One copy.
- `devtv-hero-no-server-sources.png`

## Notes for the reviewer
- `ApplePlexClient.swift:201,203,248`: `clientIdentifier`, `platformName` and `performRequest` went from private to internal, for the new extension file.
- Plex Pass trailers redirect to a signed `internetvideoarchive.net` URL with a query string. That's why Top Shelf uses downloaded files rather than relaxing the no-query rule.
- DevTV is left with this lane's Debug build installed; OfficePlus was not touched.
- Nothing is committed.
