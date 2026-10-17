# Plex vs OpenStream on DevTV, same harness

Measured 2026-10-16 on **DevTV** (Apple TV 4K 2nd gen, A12, tvOS 27). OfficePlus was not touched.
- **OpenStream:** main 2f8604f, AppStore-tvOS Release with add-ons, the owner's library (472 titles from ServerPlus).
- **Plex:** com.plexapp.plex 2026.20.0, signed in, server ServerPlus. It opens on "Who's watching?"; the walk picks the first profile (cyberstreams, no PIN).
- **Harness:** `Apps/OpenStreamTVUITests/AppleTVPerfWalkUITests.swift`, class `AppleTVPlexCompareUITests`. Both apps run the same steps and the same waits, driven by the remote.
- **Runner and data:** `/Volumes/DevExt/dev/openstream-build/plex-vs/` on Dev-Mini (`plexvs.sh`, `q-full.sh`, logs in `out/`, screenshots in `shots/steps/`).

## How the numbers were taken
- **drawn:** the screen stopped changing. A 64×36 grey thumbnail of a full screenshot is polled until it holds still for 1.5 s (2 s at launch). The step ends at the last change. One poll takes 0.45–1.3 s, so these numbers are ±0.3 s. Screenshot cost does not depend on the app, so drawn times compare fairly.
- **interactive / shown / focus move:** XCUITest element queries. These do **not** cost the same in both apps. A focus query takes about 140 ms in OpenStream and about 330 ms in Plex, whose React Native element tree is much deeper. These numbers lean against Plex by roughly one query, about 0.2 s.
- **First video frame:** screenshots fail here.
  - Plex's frames never reach screenshots; the screen stays black.
  - OpenStream's dark opening scene reads as black.
  - Instead: OpenStream's own trace (`first frame`), and Plex Media Server's log on ServerPlus (the client's `timeline state=playing` report, which carries its own `playbackTime`).
- **Same file in both apps:** *Animals* (2026), the 4K Dolby Vision profile 8 HEVC MKV with EAC3 Atmos (13.09 GB) on ServerPlus. Both apps requested the same byte ranges of it. Plex chose Direct Play.
- **Rows:** Plex walks along Movies › Recommended › Recently Released Movies. OpenStream walks along Library › Movies (alphabetical).
- **Sample sizes:** 10 cold launches and 5 walks per app, alternating apps, 15:55–16:26 local.

## Results (p50 / p90, ms; from the remote press)

| Step | Plex | OpenStream | Who is ahead |
|---|---|---|---|
| 1a. Cold launch: `launch()` returns (XCUITest idle) | 1,258 / 1,276 | 2,122 / 2,506 | Plex +0.9 s |
| 1b. → first focused element (interactive) | 2,360 / 2,420 (profile picker) | 3,244 / 3,649 (Home) | Plex +0.9 s |
| 1c. → first screen fully drawn | 4,316 / 4,388 (picker) | 5,272 / 5,862 (Home with hero art and rows) | Plex +1.0 s |
| 1d. Plex only: profile picked → Home interactive / drawn | 2,420 / 2,683 · 3,160 / 3,432 | — (no picker) | OpenStream (no extra screen) |
| 2. Home → library page: first changed frame | 1,465 / 1,477 | 2,694 / 2,716 | **Plex +1.2 s** |
| 2. → visible posters drawn | 2,991 / 3,027 | 4,110 / 4,123 | **Plex +1.1 s** |
| 3. Focus move along a row (10 moves × 5 walks), XCUITest | 610 / 727, max 833 | 381 / 489, max 515 | About even after query cost (≈280 vs ≈240) |
| 4. Open title → play button shown | 2,487 / 2,499 | 1,353 / 1,370 | OpenStream +1.1 s |
| 4. → page drawn (art + metadata) | 3,217 / 3,224 | 2,209 / 2,225 | **OpenStream +1.0 s** |
| 5. Play → first video frame (same file) | **never: 5 of 5 stayed "buffering" for 50 s** | 2,750 from the start; 3,132 / 4,440 resuming (one resume took 10,362) | **OpenStream** |
| 6. Player → title page back / drawn | 1,477 / 1,495 · 2,219 / 2,228 | 1,420 / 1,470 · 2,316 / 2,379 | Even |
| 6. Title page → library page drawn | 1,385 / 1,408 | 1,475 / 1,497 | Even |

Every Plex play reached Direct Play and pulled 820–870 MB in about 50 s, about 135 Mbit/s over the router path (the server logs DevTV as `192.168.1.1 … WAN`). Each one reported `state buffering, progress 0` every 10 s until the walk stopped it.

OpenStream started the same file in 2.75 s from zero. The other four walks resumed from the progress the previous walk saved (21, 28, 35 and 41 s).

Screenshots of every step for both apps: `/Volumes/DevExt/dev/openstream-build/plex-vs/shots/steps/` (`<app>-<step>.jpeg`).

## The three biggest gaps where OpenStream is behind

### 1. Library tab: 1.1–1.2 s slower to change and to finish drawing
- **Screen:** OpenStream's first changed frame comes 2.7 s after the press, against 1.5 s for Plex. Posters are fully drawn at 4.1 s, against 3.0 s.
- **In-app trace (walk 4, `cmp-walk-os-trace.log`):** `tab → library` at 24,903 ms, `tab library on screen` +43 ms, hero still loaded +288 ms, but `screen discover gone` only at +1,162 ms. The app considers the page on screen a second or more before the outgoing page is removed and the frame lands.
- **Profile:** Time Profiler over a tab walk on DevTV (`out/cmp-walkprof.trace`, 2 rounds, symbolicated). The main thread is not the blocker: 600 ms of samples in the 3.2 s after the first `tab → library`, mostly `AppleMediaIngestion.libraryRecord`, `AppleMediaRecord.normalizedTitle` and `ApplePlaybackIdentity.digest(for:)`. The potential-hangs table shows 284 and 288 ms main-thread hangs at 35.7 and 38.3 s, at or just before the switch (the trace-to-profile time mapping is ±1 s). Background work is: the app burns about 1.9 cores during the switch, and about 1.0 core at the second switch 25 s later.

  | Window (s after launch) | All app threads | Biggest consumers |
  |---|---|---|
  | 38–42.7 (first Library switch) | 9.3 s of CPU in 4.7 s | `AppleLibraryTitleParser.clean`/`fileRole`/`parse` ≈2.4 s, `AppleNetflixTop10Parser.consume` ≈0.97 s, `NSRegularExpression.init` ≈0.87 s |
  | 64–67.2 (second switch) | 3.4 s in 3.2 s | `AppleNetflixTop10Parser.consume` 0.38 s |
  | 120–123 (idle on Discover) | 1.8 s in 3 s | `AppleNetflixTop10Parser.consume` 0.57 s |

  The library title parse is still running 40 s after launch. The Netflix Top 10 parse keeps returning (64 s, 120 s), and each time it competes with the frame and poster decode of the page being switched to. Plex does none of this on the device; its server does the work.

### 2. Cold launch: about 0.9–1.0 s later to an idle, interactive, fully drawn first screen
- **Screen:** XCUITest's "app is idle" comes 0.9 s later than Plex's, the first focus 0.9 s later, and the fully drawn Home 1.0 s later than Plex's first screen. Plex then spends 3.2 s more after the profile pick before its Home is drawn.
- **In-app trace (10 launches, `cmp-launch-os-trace.log`):** Home frame at about 0.7 s from process start. Hero still at 2.4–2.9 s, library shown at 2.7–3.1 s.
- **Time Profiler, launch (`out/cmp-prof-launch.trace`, symbolicated with the build's dSYM), all app threads, first 7 s:** about 14 s of CPU in 6.9 s: two cores' worth on DevTV's A12 (2 performance + 4 efficiency cores), all while the hero and posters load.

  | Work | CPU samples (ms) | Main thread? |
  |---|---|---|
  | `AppleLibraryTitleParser.clean` + `fileRole` + `parse` | ≈2,150 | partly (≈110 ms main, 5–10 s window) |
  | `NSRegularExpression.init(pattern:options:)` (a new regex per call) | ≈910 | ≈42 ms main |
  | `AppleNetflixTop10Parser.consume` + `AppleNetflixTop10Client.latestWeek` | ≈1,530 | no |
  | `AppleCachedCredentialPolicy.metadata` / `scrub` | ≈620 | no |
  | `AppleMediaRecord.normalizedTitle` | ≈390 | some |
  | `AppleRemoteImageDecoder.downsample` (the posters themselves) | ≈330 | no |

  On the main thread from 2.5 to 5 s: `ApplePlaybackIdentity.digest(for:)`, `AppleIdentityAliasStore.isEnabled`, `AppleDiscoverView.displayedRails`, `AppleCatalogShelfPolicy.deduplicatedRows`, `AppleTopShelfPublisher.digest` (746 ms of samples in 2.5 s).
- **What would close it:**
  - Compile the title-parser regexes once.
  - Run the Netflix Top 10 parse and the credential scrub after first paint, not alongside it.
  - Keep the poster decode ahead of them.

### 3. Play start: about 1 s lost to a dropped first connection on every play, and a slow resume path
OpenStream beats Plex outright here, since Plex never started this file. Against our own best case:
- **Dropped first connection:** in all 6 plays (`cmp-walk-os-trace.log`), the first reader connection to the local share proxy ends at once with `The network connection was lost`. The next connection starts about 1.0 s later (`pump conn start gen=2`), and `containerOpened` waits for it. Without that second, the start-from-zero play would be about 1.7 s.
- **Slow resume:** resuming at 28 s took 10.4 s. `seg7 never reached AVPlayer's timeline (nothing held at item 28.000s); rolling the composed axis…`. The other resumes took 3.1–4.4 s.

## Notes
- **Plex's start-up:** a native launch screen for about 1.3 s, then a React Native profile picker drawn at about 4.3 s. After the pick, Home shows grey placeholder cards first and posters about 0.7 s later. Its first screen needs no library work.
- **Side effects of the runs, both on DevTV only:**
  - The first Plex play showed the system prompt "Connect Plex to the Apple TV app"; the walk's Menu press answered **Don't Allow**. Undo: Settings › Apps › TV.
  - OpenStream now holds 49 s of progress on *Animals*. DevTV stays held from iCloud, so it doesn't sync.
  - Plex recorded no progress (it never played).
- **Harness limits:**
  - DevTV kills `testmanagerd` at its memory high-water mark when many 4K screenshots pile up during long Plex buffering (JetsamEvent 15:46). So each walk runs in its own `xcodebuild` session, and the Plex play step polls once a second.
  - Screenshots don't show Plex's video frames.
