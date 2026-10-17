Still waiting on the before build and Codex; I'll continue when either reports.

Waiting on the test run.

Still waiting on the rerun.

While those run, the remaining gates are queued in my head: the full serial `swift test`, an iOS build, and E2E-tvOS/iOS for the touched areas. Waiting for the current jobs.

Already handled; still waiting on the after build and the before measurement.

Waiting for the before measurement to finish.

Full serial tests and the before measurement are both running. Waiting.

Waiting for the after measurement.

Waiting.

Still running; the other monitor is armed.

Waiting on the profile.

Waiting for the device lock to free up.

Still queued behind the other lanes.

Waiting on E2E.

## Speed round 2: tvOS/iOS builds, the full test suite and E2E pass; launch, tab-switch and resume targets not met

The DevTV comparison is between this branch's base (`HEAD`) and this tree. Both were Release builds with add-ons, run with the same `AppleTVPlexCompareUITests` harness. Nothing is committed.

**Before/after on DevTV** (median; launch rounds 2–10, 5 walks)

| Step | Before | After | Plex | Target |
|---|---|---|---|---|
| Cold launch → first focused element | 3234 ms | 3327 ms | ~2370 ms | ≤ 2.4 s ✗ |
| Launch → screen still | 4603 ms (p90 5177) | 4339 ms (p90 4476) | ~3150 ms | — |
| Library tab: first change / drawn | 2712 / 4123 ms | 1685 / 3587 ms | 1465 / 2991 ms | drawn ≤ 3.0 s ✗ |
| Old tab page removed (app trace) | 1166 ms | 1114 ms | — | < 300 ms ✗ |
| Play → picture ready, fresh start | 2.1–2.7 s | 1.1 s | — | ≤ 2 s ✓ |
| Play → picture ready, resume | 3.9 s | 2.7–3.1 s | — | ≤ 3 s ~ |
| Play → app "first frame" event | 2.9–3.7 s (one 10.0 s) | 2.0–4.4 s (three 8.9–9.3 s) | — | — |
| Dropped first share connection | 5 of 5 plays | 0 of 5 | — | — |
| Launch CPU: parser total / on main | 2766 / 152 ms¹ | 968 / 16 ms | — | — |
| Launch CPU: Top 10 parse | 766 ms¹ | 3 ms | — | — |

¹ From the 16:28 profile of the older main build. I didn't profile this branch's base before replacing it on DevTV.

## Done
- **1. Title parser** — `AppleLibraryTitleParser.swift`, `AppleMediaIndex.swift`, `AppleLocalLibraryStore.swift` — every pattern is compiled once, and parse results are remembered per name and folder inside the parser, so every caller benefits (the old `AppleLibraryParseMemo` wrapper is gone). Swift's string regex search and ICU don't match the same way, so each call keeps the engine it used before: old and new parsers agree on all 3,085 test names and paths. The first pass is 2.2× faster.
- **2. Netflix Top 10** — `AppleNetflixTop10.swift` — two calls at once now share one download, and rows for other countries are skipped from the raw bytes. The week was already cached on disk by the recording branch.
- **3. Credential scrubbing** — `AppleMediaServerBackgroundDownloads.swift`, `AppleMediaIndex.swift`, `AppleMediaServerLibraryStore.swift` — files written through the scrub get a `credentialScrub` version mark. Readers trust marked files, older ones are scrubbed once and rewritten, and the verdict for each URL is cached. Reads no longer appear in the profile.
- **4. Library tab** — `AppleLocalLibraryStore.swift` — record ids are cached per source and path. Building a full record for every file on each Library body pass was ~180 ms of the switch.
- **5. Play start** — `AppleNetworkShare.swift` — this was the root cause of the dropped connection. While the share was still opening, a second read failed straight away. Play reads the start and the end of the file at once, so the bridge dropped the player's first connection and the engine waited ~1 s to retry. The second read now waits for the opening connection.
- **6. Images (REA actions 5–8, plus next-row prefetch)** — `AppleRemoteImage.swift`, `AppleArtworkDiskCache.swift`, `AppleArtworkPrefetchPolicy.swift`, `AppleDiscoverView.swift`, `AppleMediaServerLibraryStore.swift`, new `AppleArtworkProgressiveCacheTests.swift` (9 tests). Codex wrote this, offloaded per the usage board; I reviewed and changed it.
  - Image sizes snap to buckets, and a larger already-decoded copy of the same image shows at once.
  - A solid average-colour placeholder replaces the flat fill.
  - Display-size copies are saved on disk.
  - Jellyfin backdrops are capped at 1920 px and keep their tag.
  - The current and next row are prefetched and decoded, with no wait for posters on first paint.

## Not done / unclear
- **Launch target (≤ 2.4 s)** — launch → first focus did not move. The CPU I removed was off the main thread. The biggest launch CPU left is `AppleDiscoverView.topPicks` (~1.26 s), which is outside this spec.
- **Tab switch < 300 ms** — the main-thread work is lighter, but the system tvOS tab transition holds the old page for ~1.1 s on every tab. I left the stock tab bar alone (owner rule).
- **Resume stall** — on a resume, the engine starts at the requested segment, the player asks for an earlier one, and the engine's 8 s "scrub landing" watchdog fires. The picture is up after ~3 s, but the app's "first frame" event, and so the spinner, waits ~9 s. This is inside AetherEngine, which I may not edit. The fix belongs to the engine owner.
- **Not implemented:** BlurHash, since the owner rule forbids gradients (solid colour only); Plex image sizes stay fixed.
- **Harness:** on both builds, all 10 walks lost the test runner right after Play (rc=65). Launch, tab and title numbers came through; play timings come from the app's own trace.
- **Missing doc:** `design/reference-apps/2026-10-16-plex-vs-openstream-devtv.md` isn't in any tree. I used the raw outputs in `plex-vs/out` instead.

## Gates run
- **code-anti-slop pass** → removed the pass-through `AppleLibraryParseMemo` and an unused prefetch overload. Changed four things in Codex's code that would have slowed loading: a disk read for the colour on every memory hit, up to 9 cache lookups per tile on every body pass, the display-copy encode delaying the image's return, and the disk-cache trim running inline. Also replaced its next-row lookup, which rebuilt every Discover rail for each section, with "next catalog section".
- **swift test, scoped** → pass 472/68. **Full `--no-parallel`** → pass 3463 tests in 429 suites.
- **xcodebuild AppStore-tvOS** (Release, add-ons, device, build-for-testing) → succeeded; all 11 edited source files confirmed recompiled.
- **xcodebuild OpenStream iOS** (simulator) → BUILD SUCCEEDED, 0 errors, edited files recompiled.
- **E2E-tvOS** → 5/5 passed (Discover-row stub smoke, Library hero, Discover hero, rapid shelf presses, Search tab). **E2E-iOS** stub smoke → 1 passed, 1 skipped by design.
- **zero-byte check** → clean.

## Diff
- 14 modified files (Sources and Tests) plus the existing harness change, and one new test file `AppleArtworkProgressiveCacheTests.swift`. 15 tracked files, +859/−188.

## Notes for the reviewer
- `AppleNetworkShare.swift:~624` — callers now share the task that opens the share. There is no unit test because `SMB2Manager` can't be injected; the DevTV trace shows 0 drops in 5 plays.
- `AppleMediaServerBackgroundDownloads.swift:~285` — a marked file skips the read-time scrub. Bump `version` whenever the scrub rules change.
- `AppleLibraryTitleParser.swift:~293` — `SharedRegex` is `@unchecked Sendable`, with the reason in a comment.
- `AppleRemoteImage.swift` — the display-copy JPEG/PNG and colour files are written at background priority and count toward the existing 512 MB cache budget.
- The after build is still in `/Volumes/DevExt/dev/openstream-build/speed2-perf/after/dd` for a re-run with `speed2.sh measure after`. I deleted the before build and my scratch files on the mini.
