Review done. Verdict and findings below.

**Verdict: FIX** (3 items, then SHIP). Diff matches the spec otherwise. Every called API exists with the labels used, traces and the snapshot carry titles and hashed file names only, fixtures hold fake ids and the fake tokens `plex-token`/`jf-token`, and the zero-byte check is clean.

**FIX**

1. `Sources/OpenStreamApple/AppleTopShelfSnapshot.swift:532` (opt-out branch) and `AppleTopShelfTrailerFiles.swift:139`. Turning Top Shelf off deletes `topshelf-trailers` but never cancels the running download task in `AppleTopShelfTrailerDownloads`. `fetchMissing` line 74 recreates the directory and line 85 saves the file, so a trailer lands on disk after the user opted out. Fix: add `func cancel() { running?.task.cancel(); running = nil }` to the actor and call `await trailerDownloads.cancel()` inside the `guard enabled else` block before the `removeItem` calls.

2. `Sources/OpenStreamApple/AppleServerTrailerView.swift:66`. The muted hero calls `player.play()` without taking the trailer audio session. The YouTube hero does (`AppleHomeBillboard.swift:784`, `prepareTrailerAudio(pressed:)` sets `.ambient`). With the category left at `.playback` by the last title played, or the default solo-ambient, a muted AVPlayer still activates the session and stops Music or another app's audio on Apple TV and Vision Pro. Fix: in `AppleServerTrailerStage.task(id:)` line 199, `guard ApplePlaybackSessionPolicy.prepareTrailerAudio(pressed: !muted) else { return }` before `playback.start`.

3. `Sources/OpenStreamApple/AppleServerTrailer.swift:113`. The title+year fallback ignores ids that disagree. A candidate carrying a different IMDb or TMDB id than the query still matches on name and year (same-title, same-year films such as two 2022 "Pinocchio"s), and its trailer is cached for 10 minutes. Fix: in `best`, after the id passes, filter candidates to those whose `imdbID` is nil or equals the query's, and likewise `tmdbID`, before the title+year compare. Add one case to the test at `AppleServerTrailerTests.swift:180`: same title and year, conflicting IMDb id, expect nil.

**Checked and clean**

- Tokens: Plex and Jellyfin URLs stay in `AppleServerTrailer.url` in memory. Store trace prints outcome and title. Top Shelf file name is SHA-256 of the media id, snapshot carries only `shelfVideo`, extension reads a bare name with a video extension. Plex `isServerPath` rejects foreign hosts, `..` and keys carrying their own credential.
- Budget: 250 MB per file checked before and after download, 1 GB total counted across saved plus new. Over-budget saved files drop out of `wanted` and are deleted. Downloads are tvOS-only (`defaultTrailerFiles` is nil elsewhere), so cellular and battery do not apply. Source removal bumps the store revision, the next plan has no missing files and cancels the running set.
- AVPlayer: `stop()` pauses, removes time and item observers, nils the player, and runs on disappear, on cover, on scene inactive and when the gate drops. Watchdog ends a stalled stream after 15 s so the carousel never holds a frozen frame. Carousel pauses on `isPlaying` and advances 1 s after the end through `videoEnded`.
- Requests: Plex extras, `hubs/search?includeGuids=1`, universal HLS transcode with token. Jellyfin `Items/<id>/LocalTrailers?userId=`, Emby `Users/<u>/Items/<id>/LocalTrailers`, `Videos/<id>/stream.<ext>?static=true` or PlaybackInfo conversion. All shapes correct.
- Owner UI: muted autoplay, `resizeAspectFill` with clipping, no scrim, no explainer text, no new tab bar or coloured labels. Buttons read "Trailer" with the `film` symbol in each platform's existing row style.

**Notes, no change required**

- A saved shelf trailer for a page stays after its source is removed until the page leaves the carousel. The file holds no token. The worker documented this as intentional at `AppleTopShelfTrailerFiles.swift:11`; owner's call.
- `Items/<id>/LocalTrailers` needs Jellyfin 10.9 or later. Older servers return 404, which counts as "no answer" and is re-asked each time, never cached.
- `AppleServerTrailer.swift:293` swallows a PlaybackInfo error with `try?` and caches "none" for 10 minutes. Low impact.
- Anti-slop: diff is clean of narration and dead paths. `AppleTopShelfTrailerDownloads.finish()` exists only for tests. The `print` in the UI test matches that file's existing style.
