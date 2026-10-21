# Front page speed (2026-10-21)

Owner (2026-10-20): "front loading page, a little bit slow maybe we aren't caching enough."

## What we know
hero-unify (0634992) kept the caches and measured on DevPlus (iPhone 16e, three samples a mode): hero art at a median of
1445→1504 ms "cold" and 1509→1534 ms "warm". A warm launch is no faster than a cold one, so the hero is waiting on
something that the disk and memory caches do not cover: a network round trip, a serial chain of awaits, a main-thread
job, or a gate that holds the stage until another load finishes. Find that and remove it. Do not add another cache
until the trace shows a cache miss.

## Job
1. Trace the whole path, from process start to the hero art and from there to the first full screen of rows, on a warm
   launch (the app ran a minute ago, all caches populated). Use the app's own trace lines and launch marks
   (`OPENSTREAM_TRACE` / the launch marks from 00870b2), adding temporary marks where a gap is unexplained, plus an
   Instruments Time Profiler or os_signpost run on DevPlus if the marks don't settle it. Write the timeline: each step,
   its start and end, and what it awaits (the network, disk, the main actor, another task).
2. Name the critical path to the hero and the one or two biggest avoidable waits on it. Usual suspects, to check and
   not to assume: Discover waiting for a fresh recommendations/Top 10/TMDB answer before showing the cached one; source
   or iCloud/CloudKit sync gating the first render; the hero stage waiting for the identity-plus-details round trip
   (hero-unify review item 6, wordmark seeding); decode on the main thread; a fixed delay or animation hold.
3. Fix them: show cached answers first and revalidate in the background (stale-while-revalidate), start independent
   loads in parallel, move decoding off the main thread. Keep the look the owner accepted (hero-unify) exactly.
4. Proof: the same warm and cold traces before and after, three samples a mode, on DevPlus. Target: a warm hero in
   ≤ 600 ms after the first frame, and a cold one no slower than today. Report the medians and the per-step timeline.

## Rules
- Phone first; don't regress tvOS, Mac or visionOS (iOS and tvOS builds must pass).
- Dev-Mini only: `scripts/mini.sh` with `OPENSTREAM_MINI_DEST='~/Developer/openstream-build/lanes/front-load'`. Heavy
  work goes through `~/Developer/bin/buildlock.sh` (sims and devices) or `buildlock-compile.sh` (compile only), which
  are FIFO. Another gate is running on the owner sim; queue, never kill. Keep > 12 GB free on the mini's disk.
- DevPlus (iPhone 16e) is the measuring device. Never install on the owner's iPhone "Anthony" or on OfficePlus.
- Owner sim (iOS 18.6, 7530ECB2-CE38-4BC6-B7E6-D4B3BEDDF48D): only through
  `/Volumes/DevExt/dev/openstream-build/batch-1018a/protected.py <sim> <cmd…>`.
- No commits, stash, checkout or reset. Never print secrets or tokens.
- Gates: serial `swift test` (compile lane); iOS and tvOS builds; testCrawlDiscover, AppleiOSStubSmokeUITests and
  testB8DiscoverJank (hero drawn ≤ 2) on iOS 18.6; code-anti-slop on the diff; no zero-byte Swift files.
- Report: the timeline, the cause (file:line), the change, before/after medians, the gates, and screenshots of the
  landing page so the look is unchanged.

## Round 2 (lead, 11:35): review findings to resolve before merge
A Claude API review (Sonnet) of your diff said "fix first". For EACH item: prove it is not a problem (cite code +
a test) or fix it with a test. The full review text follows.
Must-do:
- (1) My List tapped before `mediaIndex.load()` finishes on the cached-hero path: show from code + a unit test that
  upsert/setFavorite on an unloaded index cannot replace the saved index file (or gate the toggle on load).
- (3) Revert the `buildRecommendations` ranker/history changes that are not needed for the speed fix, OR add a
  golden test proving Continue Watching/picks are identical to before for unmatched video/channel records with progress
  and for duplicate history. The spec asked for stale-while-revalidate only.
- (4) Release build: build iOS Release (no add-ons) and confirm the new traces compile there.
- (2) Report a cache-MISS launch on DevPlus (empty discover cache, and one launch after changing progress) — 3 samples.
- (5)(6)(7) Answer each with code citations; fix if real (stuck skeleton, concurrent load/sync, hero swap after revalidation).
Same rules and gates as above.

### Review text
VERDICT: fix first

Findings (line numbers are approximate, taken from the hunk headers):

1. **AppleDiscoverView.swift ~1541 `toggleHeroInList` (also the tile and hero `isInList` fallbacks ~1354, ~1534).** The cached hero now draws before `mediaIndex.load()` finishes. A My List tap in that window finds `mediaIndex.record(id:)` nil, calls `upsert(value.record)`, then `setFavorite`, on an index that has not loaded.
   - Failure scenario: if `upsert` or `setFavorite` persists the in-memory set, the saved index file is replaced by one record. That is data loss on exactly the warm-launch path this change creates.
   - Fix: make `toggleHeroInList` `await mediaIndex.load()` first, or disable it until the index is loaded. Add a test that upserts into an unloaded index and checks the file.
   - To check: `AppleMediaIndex.upsert` and `setFavorite` when called before `load`.

2. **Proof does not cover the cache-miss path (FEEDBACK/GUI-AUDIT, `.task` ~568-590).** "Cold" here still has the disk caches, so the cache hit is measured. Any change to watch state, ratings or the index file changes the fingerprint, and `.fresh` expires. A launch after playback that was never re-stored therefore misses.
   - On a miss, `loadedCache` is still set only after `synchronizePlaybackProgress()`, and `rebuildRecommendations` returns until then. A slow iCloud sync still gates the first hero. The new `progress synchronized` trace was added but its value is not reported.
   - Fix: report cold-miss timings (empty `discover-v1` entry, plus a launch after changing progress). If the sync is slow, do not gate `loadedCache` on it.
   - To check: the `.fresh` TTL of `AppleMetadataDiskCache`.

3. **AppleDiscoverView.swift ~749-1015, `buildRecommendations` rewrite. This is scope creep with a behavior change.**
   - Records of kind `.video` or `.channel` without a lookup match no longer reach `inProgress`. Before, all records did.
   - Movie and series records are no longer double-counted in `historyValues`, and the order changed.
   - The spec asked for stale-while-revalidate, not a ranker change. `cachedRecommendationsIgnoreDuplicateAndNonCatalogHistory` compares overlapping input to single input, but never against the old output. It would pass if the old duplicate handling were already equivalent.
   - Fix: split this out, or add a golden test with an unmatched video/channel that has progress, asserting the old and new Continue Watching results are the same.

4. **AppleDiscoverView.swift ~575, Release builds.** `appleTrace(... AppleLaunchMarks.milliseconds ...)` and `ContinuousClock` are outside `#if DEBUG`, while the neighbouring marks are inside it.
   - Failure scenario: if `AppleLaunchMarks` or `appleTrace` is debug-only, the Release build breaks. The reported gates look like Debug builds.
   - Fix: wrap the trace in `#if DEBUG` or confirm the symbols exist in Release, and run a Release build.

5. **AppleDiscoverView.swift ~249, `recommendationsRevision == nil` in the skeleton condition.** If `rebuildRecommendations` returns early or fails (`guard loadedCache`, the `catch`, a cancelled launch wait) before a revision is set, and the source set is never empty, the placeholder stays up forever.
   - Fix: confirm that every non-cancelled exit sets a revision. Otherwise key the skeleton on "no result yet and still loading".

6. **AppleDiscoverView.swift ~375, Continue Watching sheet task.** It now runs its own `mediaIndex.load()` and `synchronizePlaybackProgress()` and sets `loadedCache = true`, concurrently with the main `.task`.
   - Failure scenario: the main task then skips its `if !loadedCache { ... }` block, including any work after the DEBUG mark. Two concurrent syncs may also race.
   - To check: that `load` and `synchronizePlaybackProgress` are idempotent and reentrant, and what else lives in that block.

7. **Hero swap on revalidation.** `recommendations` is replaced by the fresh result once the launch window ends. If hero order or selection is not deterministic for the same inputs, the cached hero visibly changes seconds later, which breaks "look unchanged".
   - The B8 count of 1 is for a run where the fingerprint matched. Add a check that the fresh rebuild gives the same heroes as the restored ones.

8. **Main-thread cost.** `recommendationWatchState` decodes progress, activity and ratings on the main actor before the cached hero can draw. The `Set(snapshot.records.lazy.filter(\.isFavorite)...)` in `r
[claude-api] reply cut at --max-tokens 8000
[claude-api] claude-sonnet-5-5 in=16985 out=8000 cache_w=0 cache_r=676 cost=$0.11404 month=$0.2156/$95

## Round 3 (lead, 14:05): second review
The re-review confirms round 1's items are fixed. Item 4 is already settled (your iOS Release build passed) and item 7
is harmless — leave them. Resolve, each with a test or a code citation:
- (1) The Continue Watching sheet must not flip the Discover-wide `loadedCache` (catalog not loaded yet → a thin
  result gets cached under a matching key). Give it its own readiness or await the catalog cache.
- (2) `loadCachedSections` now runs on every task start (tab re-appear, source change): prove it cannot replace newer
  in-memory sections, or guard it.
- (3) The post-write progress apply: skip it when nothing changed, so it neither costs an O(n) main-actor pass nor bumps
  the revision into a redundant rebuild that cancels the cache store.
- (6) Make `unloadedFavoriteWritesPreserveTheSavedIndex` (or a new test) cover the `toggleHeroInList` path itself, and
  add a cache-vs-fresh case where the catalog changed between them.
Re-run the same gates (serial swift test, iOS/tvOS Debug + iOS Release, the three 18.6 UI tests through protected.py) and
one DevPlus warm sample to show the speed held.

### Review text
VERDICT: fix first

Findings:
1. `AppleDiscoverView.swift:~380` (Continue Watching sheet `.task`) — the sheet sets `loadedCache = true` after only `mediaIndex.load()`. In the main task that flag also means "catalog cache loaded", and `rebuildRecommendations` is gated on it.
   - Failure: the user opens Continue Watching straight from the cached rail. The sheet rebuilds with `catalogStore.sections` still empty. `rebuildRecommendations` then stores that thin result under a key that matches the current watch state and index file. The next launch restores the degraded heroes and picks, which flash until the full rebuild replaces them. It also overwrites the good cache entry.
   - Fix: give the sheet its own "index ready" flag, or have it await `catalogStore.loadCachedSections` first. Do not flip the Discover-wide `loadedCache` from the sheet.

2. `AppleDiscoverView.swift:~573-585` (main `.task`) — `catalogStore.loadCachedSections` used to run once, inside `if !loadedCache`. It now runs on every task start, which includes each re-appearance of the tab and each source-configuration change.
   - Failure: switching back to Discover re-reads the disk cache. If `loadCachedSections` overwrites `sections`, newer in-memory sections are replaced by older cached ones until `refresh` finishes, so the hero or rows flicker.
   - Check: confirm `loadCachedSections` is a no-op when sections are already populated. If it is not, guard it with `!loadedCache` or `sections.isEmpty`.

3. `AppleMediaIndex.swift` (`beginSynchronizingPlaybackProgress`) — the projection runs `applyPlaybackProgress`, which copies all records and calls `setRecords`, twice on the main actor. The second run, after the write, repeats the same projection even when nothing changed. Round 1 asked for off-main work, and this does an O(n) pass on main per call plus the per-record `store.progress(for:)` loop.
   - Fix: skip the post-write apply when `progressByID` already equals what was projected, or when `generation` is stale and nothing else changed.
   - Check: whether `setRecords` bumps `revision` on an unchanged array. If it does, the post-write apply triggers an extra `recommendationRevision` change and a redundant rebuild. It would also cancel the cache-store step via `revision == recommendationRevision`.

4. `AppleDiscoverView.swift:~570-600` — the new `appleTrace(...)`, `appleTraceFailure(...)` and `AppleLaunchMarks.milliseconds` calls sit outside any `#if DEBUG`. `AppleLaunchClock.mark` is DEBUG-only.
   - Check: confirm these helpers exist in Release, and that their arguments are not evaluated eagerly. The `ContinuousClock` subtractions run on the launch path.
   - Check: the iOS and tvOS builds in the notes may have been Debug only. Run a Release build.

5. `AppleDiscoverRecommendationCache.swift` — the key covers watch state, ratings, index file size and mtime, and source configuration. It does not cover catalog section content, server shelves, relations or artwork, so a hit can show stale content.
   - The `loaded:` term in `recommendationRevision` forces a rebuild after first paint, which makes this acceptable.
   - Check: the fingerprint inputs (`configurationProgress()` etc.) must be built the same way at restore and in the snapshot. If they differ, the cache never hits. Only the DevPlus measurements show that it does.

6. `AppleHeroMixPolicyTests.swift` (`revalidationPreservesCachedHeroesAndRows`) — it compares restored output with the same function run on the same input, so it proves serialization round-trip only.
   - It does not check `isFavorite` after restore, or any case where the catalog changed between cache and fresh.
   - `unloadedFavoriteWritesPreserveTheSavedIndex` calls store APIs that this diff does not change. It does not cover the `toggleHeroInList` `await load()` fix.

7. `AppleMediaIndex.swift:~88` — the `AppleMediaRecord.init` fallback-string inlining is not part of the spec and not a round 1 item. It is behavior-preserving and has tests, so it is harmless but out of scope.

Round 1 items otherwise appear addressed:
- My List awaits `load()` before reading the favorite flag.
- Progress writes are chained and generation-guarded.
- The skeleton is gated on `isLoading`.
- The `matchingGroups` crash fix stores the snapshot in `MatchIndex`.
[claude-api] claude-sonnet-5-5 in=21574 out=8091 cache_w=0 cache_r=676 cost=$0.12413 month=$0.4646/$95
