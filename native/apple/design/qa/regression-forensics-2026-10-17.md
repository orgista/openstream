# Regression forensics: build 15 (ad66774) → main (72966f9), 2026-10-17

Job R1 of `specs/regression-and-rea-2026-10-17.md`. Owner: "the app used to be decent and now it's kinda in a worse
place and we gotta find out why." Report only; nothing under Sources/, Apps/ or Tests/ was touched, nothing built.

**Sources read:** `git log ad66774..main` (226 commits, 2026-10-03 → 10-17); OWNER-TODO.md; the owner's narrated
recording of 2026-10-15 (`design/qa/owner-recording-2026-10-15-transcript.srt` + frames pulled from
`~/Downloads/RPReplay_Final1792123442.mp4` at each spoken timestamp); the owner-phone traces on Dev-Mini
(`/Volumes/DevExt/dev/openstream-build/traces/owner-iphone-1015.log`, `owner-iphone-1017.log`, `iphone-1017b.log`);
`design/qa/iphone-feedback-checklist.md` (iphone-jank branch); the job specs, reports and reviews under `specs/`;
`design/reference-apps/2026-10-17-rea-hero-trailers-disc.md` (REA round 3); the fix branches as of 22:00
(hero-trailers 311a53b, hero-settle 74d484e, iphone-jank b7b0a91, iso-open d627387, server-trailers c5cd082,
icloud-sync 6df9039; live-narration, settings-narration and speed3 hold no commits yet).

## 1. The five findings that matter most

1. **The owner has judged a build without add-ons since 2026-10-15 22:46 local.** Every dev build installed on the
   owner's iPhone from the first install (`owner-iphone-1015.log`, session `2026-10-16T03:46:12Z v1.0 (1)`) to the
   10-17 09:00 install was compiled without `OPENSTREAM_ADDONS`. The traces show `sources saved: 2` / `3` in every dev
   session against `sources saved: 8` in the last build-18 session eight minutes earlier. The owner's recording of
   22:54 (made on that build) shows it: Settings › Sources › Add has no "Add Catalog" row (frame 3:55;
   `AppleSourcesSettingsView.swift:122` is `#if OPENSTREAM_ADDONS`), Discover is one library shelf plus two text-only
   Top 10 rows (frame 5:40), and the owner says "that should be the add-ons … Sources … I don't see it. It's just IPTV
   and Instance". Build 18's last session has `manifest refresh Rotten Tomatoes / Streaming Catalogs / Cinemeta`
   lines; no dev session has any. OWNER-TODO's "LEAD MISTAKE" dates this to 10-16/10-17; the traces put it at the first
   dev install (the phone and Dev-Mini run on CDT, so the 22:54 recording is the `03:54:54Z` session). The 10-17 trace
   that drove the jank work (`iphone-1017b.log`, 14:53Z = 09:53 CDT) is from the same no-add-on build, and no owner
   trace after the 11:00 reinstall exists on the mini yet, so "fixed" is unproven on the phone. Every "worse than
   build 15" judgement from 10-15 22:46 to 10-17 11:00 (recording, "hero cycle gone", "trailers worse", "general
   jank", Discover "doesn't load any") was made on an app with six of eight sources hidden. Section 3.1–3.8 says
   which complaints stand on a correct build (bar, title header, Live, discs, Settings) and which must be re-taken
   (hero cycle, Discover content, launch).
2. **Agent-chosen behaviour replaced owner-approved behaviour, and the tests were rewritten to match.** f82ef99 (10-13,
   from a Fable REA spec, no owner request) made the Home hero stop on its last page (`AppleHeroRotationCycle.swift:42`)
   and renamed the test `itAdvancesAndWrapsWhenDue` to `itAdvancesWhenDueAndStopsAtTheLastPage` with
   `#expect(!wrapped)`. Build 15 wrapped. Owner 10-17: "hero cycle gone". The same commit blocks a *pressed* trailer
   under Low Power Mode (`AppleDiscoverView.swift:5209`). Fix branch hero-trailers reverts both.
3. **The iPhone title page was shrunk to a 16:9 box (13a2677, 10-09, build 17) and YouTube's chrome was un-hidden
   (d70aea9, 10-10, build 18).** Build 15 had a full-bleed header with YouTube's title strip hidden by CSS. The
   recording shows the box cut under the back/search buttons with the wordmark below it (frames 2:12, 8:14; owner:
   "the trailer's cut off, then the wordmark is below the trailer, it got worse") and the "MARSHA…" YouTube strip over
   the video ("I don't know why that's up there"). hero-trailers restores the build-15 header; the YouTube chrome is
   an owner decision nobody has asked for in plain words yet.
4. **About 10,500 source lines of features nobody asked for landed in nine days, and the owner is now paying for
   them in the UI.** Live TV batches of 10-05 (~4,300 lines: parental PIN, sleep timer, reminders, Start Over,
   multiview, channel banner, provider movies & series, the import progress card), the 10-12 "polish" night (41
   commits, ~3,850 lines of Netflix/Apple TV/Plex-lessons work built the same night the reports ended with "Owner:
   pick which to build"), and the 10-13 REA behaviours (587 lines, finding 2). The owner's narration names the costs:
   "I didn't ask for this" (tappable Recently Added, 2:59), "I never asked for it" (the IPTV import card, 5:22), the
   WATCHING pill "kind of like AI sloppy" (1:41), "it's double" (four Set Up / Send Setup entry points, 3:55–4:26),
   Settings rows (Restrictions, Start with last channel, Channel Health sweep).
5. **Fixes were proven on the iOS 27 simulator; the owner runs iOS 18.7.** Of 86 non-merge commits touching Sources,
   9 mention iOS 18 or the 18.6 simulator and 21 mention any real device; 58 cite neither; `Tests/Fixtures/run-e2e.py:32` hard-codes the iOS 27
   simulator and the first iOS 18.6 E2E run was on 10-16. f299aff's "iOS 18 hero stops jumping" passed on the 18.6
   simulator with a 750 ms settle; the owner's phone trace one day later shows the bar still oscillating 97↔115 pt and
   `hero drawn` firing 12 times (iphone-1017b.log, session 14:53Z). The Library tab still gets the opaque iOS 18 bar
   (`AppleAlignedTabTitle.swift:60-66`; only Discover passes `overArtwork: true`, `OpenStreamRootView.swift:754`), so
   the Library hero's top 115 pt is hidden: "this gets cut off, can't see the full poster" (frame 1:48).

## 2. Size of the change

| | build 15 (ad66774, 10-03) | main (72966f9, 10-17) |
|---|---|---|
| Sources (Swift) | 92,749 lines / 368 files | 113,253 lines / 486 files (+22 %) |
| Tests | 44,157 lines | 56,026 lines |
| Apps (UI tests, targets) | 8,565 lines | 13,506 lines |
| Unit gate | ~2,980 tests (10-09) | 3,475 tests / 431 suites |
| Commits | | 226 in 14 days; 41 on 10-12, 34 on 10-13 |
| Engine pin | upstream 6.66.0 | owner fork 07afad62 (DVD menus, +HTTP disc reader) |

550 files changed, +45,596 / −3,963. `AppleDiscoverView.swift` 9,635 → 11,013 lines; `AppleMediaSourceViews.swift`
2,494 → 3,469; `AppleLocalLibraryStore.swift` 564 → 1,140.

## 3. Area by area

Each row: what build 15 did, the commit(s) that changed it, what the owner saw, whether a current branch covers it.

### 3.1 Hero cycle and trailers
- **Build 15:** 12 s pages, wrap from last to first, muted trailer 2 s after the art on iPhone/iPad/Mac (REA round 3 §4).
- **73455c3 (10-09, build 17/18):** iPhone hero became a static still with no trailer ("Play Trailer" → Details).
  Owner 10-14: "no more trailers and it's not full screen like it was before … my fave feature". Undone by **ef4a4d3
  (10-14)**, which also added the pauses: under half visible, covered, Reduce Motion, Low Power, system auto-play switch.
- **0840e92 (10-12):** the dwell clock waits until the page's art is shown. Combined with **f82ef99**'s stop-on-last-page
  and the gate that never times out (`AppleHeroPageGate.swift:106`; `AppleCatalogArtwork` drops `onFailure` while it
  waits for a size, `AppleDiscoverView.swift:3194`) and the Home trailer that sets `isPlaying` on request with no
  startup timeout (`AppleHomeBillboard.swift:726,749`), the cycle has four ways to stop for good. The owner's 10-17
  trace holds one `hero trailer start` in the whole file.
- **f82ef99 (10-13):** stop on last page; Low Power / system switch block pressed trailers; 200 ms focus dwell;
  no repeats across 3 rows. Source: a Fable REA spec, agy + lead review, no owner line.
- **Covered:** hero-trailers 311a53b (wrap; 8 s trailer timeout returns to the still; 1 s advance after a trailer;
  6 s still-only dwell; art counts as settled after 8 s; pressed trailers play under Low Power; mute choice remembered;
  next-page embed prefetched; verified on the 18.6 sim with the owner setup), hero-settle 74d484e (autoplay waits for
  the catalog review so the list holds still), server-trailers (Plex/Jellyfin/Emby trailers on Apple TV and Vision Pro,
  Trailer button everywhere). **Not covered:** the tvOS focus hold on hero buttons (`AppleTVHeroPaging.swift:68`) and
  the under-half-visible pause are unverified on a device; no phone measurement of "pages per minute" exists yet.

### 3.2 Title-page header (iPhone)
- **Build 15:** full-bleed tall header, one fade, WKWebView YouTube embed with the overlay hidden by CSS (N49); the
  reveal came ~8.5 s in by accident (the picture-settle gate never saw hardware video), which skipped studio logos.
- **9760a49 (10-04, build 16):** reveal at ~0.5 s → YouTube's title strip and logo visible for the first seconds. Owner
  10-08: "trailer flashes for a split second then disappears".
- **13a2677 (10-09, build 17):** 16:9 box under the status bar, title block under it on black, "black until the details
  answer or 1.5 s pass". Owner 10-14: "speed can be improved … loading circle"; owner 10-15: "trailer cut off,
  wordmark below, got worse" (frames 2:12, 8:14). The 1.5 s black hold was removed by **e4409ca (10-15)**.
- **d70aea9 (10-10, build 18):** YouTube strip, logo and "More videos" left visible for terms-of-service reasons;
  `modestbranding`/`showinfo` dropped. Recording 6:00–8:14: "I don't know why that's up there".
- **e63f693 (10-16):** art held until 4.5 s of trailer has played (cap 12 s) to hide the strip → reveal ~6–8 s after
  the pick. One complaint traded for another.
- **Covered:** hero-trailers undoes 13a2677 (build-15 header at 70 % with the one approved fade). **Not covered:** the
  YouTube overlay (owner decision), and a clean source: server-trailers only helps titles on Plex/Jellyfin/Emby; the
  iTunes Search `previewUrl` route proposed in REA round 3 §8 is unbuilt.

### 3.3 Live
- **10-05 batches** (392cac6, db59520, a65f663, 4678709, 30899b1, 731858c; ~4,300 lines): "from the IPTV research
  (muse-results 35/36) and the gap report". OWNER-TODO f8ba811 records them as "built, needs your Apple TV", not as a
  request. 30899b1 added the import progress card: the "IPTV · Importing · 0 channels · Zero KB · Cancel" box the owner
  "never asked for" (frames 5:52, 6:36). e63f693 stops it over a saved lineup and hides the 0/0 line; the card still
  exists for first imports.
- **10-09 redesign** (0c1cf92, f324391, fc6c356, d8c923c, b6c9101, 49fbcb2) answered owner items 7–15, but:
  - the **WATCHING pill** (b6c9101, `AppleLiveOnNowList.swift:169`, #FF3366 text) is the agent's reading of "nothing
    shows which channel you're on"; it breaks the owner rule "no coloured label text" and the owner calls it AI sloppy;
  - the **Events tab** (d8c923c) only appears when a channel name contains "pay-per-view", "pay per view", "ppv" or
    "event only" (`AppleIPTV.swift:172-174`, `AppleLiveCategoryOrder.swift:16`). The owner's lineup shows Kids, Movies,
    Premium, Lifestyle (frame 1:00) and All, Favorites, News, Sports (frame 1:41) and no Events tab, so item 11 ("where
    is pay-per-view?") is ticked `[x]` in OWNER-TODO (line 343) and unfixed for the owner ("maybe premium?", 0:30).
    Its tests use fixture names that match the pattern;
  - **programme lines** are fetched for visible rows only (`refreshVisible`, `AppleMediaSourceViews.swift:900`), so a
    category shows blanks until its own fetch answers: "no metadata in these, only in the All" (frame 1:00 shows
    CINEMAX LATINO and TASTEMADE blank while HBO rows are filled).
- **Guide sheet** (cca03fd, finish-spec #56): the red now-line sits at the window's left edge over the first column
  boundary (`AppleTVGuideMetrics.swift:177`, frame 7:20): "that bar right there gets stuck … looks weird".
- **Playback:** the owner's provider needs 12–16 s to a first picture; c0637f8 gives an open channel 15 s more, 4553fc6
  raised the panel login probe 7 → 20 s. The 10-17 trace shows zaps (`live zap → FX` at 208.5 s, `→ COMEDY CENTRAL` at
  211.4 s) and no first-picture marks, so "things take you forever" (5:08) has no measurement yet.
- **Channel Health sweep** in Settings root ("Checking 12 of 136", Stop Checking; `AppleChannelHealthViews.swift:176`)
  predates build 15 (314ccc5, 09-22) and was never requested either.
- **Covered:** nothing on a branch; live-narration has no commits. e63f693 (merged) covers the import card over a
  saved lineup only.

### 3.4 Launch time
- **Owner recording 10-15:** ~4 s black with a faint spinner. The trace of that build (owner-iphone-1015.log, session
  03:46Z) starts with `discover appeared — 0 sections` at 2 ms, `library published … 402 titles` at 835 ms, the hero
  layout thrash at 3.75–4.11 s, and the first library scan done at 8.5 s. With add-ons compiled out Discover had
  nothing to draw but the library shelf and Top 10, and Top 10 arrived ~13 s in because Netflix's all-weeks file was
  downloaded and parsed on every launch (fixed e63f693, parse 766 → 3 ms in 8844c64). The 4 s before the trace clock
  starts is unexplained: the trace has no launch mark on that build (10-17's has `launch+332ms`).
- **Apple TV:** 085e6a9 measured Home 441 ms and library on screen 5.9 s on DevTV before its fixes and names the
  causes; each maps to a 10-12/10-13 commit: playback reads through `NSUserDefaults` copying 7 blobs per query
  (6fa7246, 10-13, "keep tvOS playback history in defaults"); recommendations ~1.1 s of CPU at launch (763a575 /
  4156e07 Netflix polish, 10-12); the Continue Watching terminal map rebuilt per title (26e88e0, 10-12) pinned the
  iOS app at 100 % CPU for 144 s until a438592; Top Shelf published five times in 1.5 s (~200 ms each on an Apple TV
  4K; 1940f6c / 8c0cd17); `replaceCatalogs` writing one file per add-on (~1.4 s). After 085e6a9 + 8844c64: Home 200
  ms, library 2.4 s, Play → picture 1.1 s. Left: launch → first focus 3.3 s vs Plex 2.4 s (`AppleDiscoverView.topPicks`
  ≈1.26 s CPU), resume spinner ~9 s from the engine's scrub watchdog.
- **Covered:** merged (085e6a9, 8844c64). speed3 holds no commits. **Not covered:** an iPhone launch measurement
  (process start → first frame → rows) on the owner's phone; the 540–763 ms main-thread hangs iOS's Hang Detection HUD
  showed after the full-screen trailer and on Settings › Sources (recording 7:57, OWNER-TODO 2e b) are untraced.

### 3.5 Scroll jank on iOS 18
- **cca03fd (10-10, build 18):** opaque system bar on iOS < 26 for every tab (owner fix #52: icons unreadable over
  bright art). The hero still laid out under the bar, so its top was hidden and the bar's collapse drove relayouts.
- **f299aff (10-16):** Discover's bar transparent again (`overArtwork: true`) and a 750 ms "settled" hold, proven on the
  18.6 simulator. On the phone (iphone-1017b.log, 14:53Z; the no-add-on build, which does not change the bar) the bar
  still swings 97↔115 pt in 16 ms steps at 3.6, 4.1, 4.9, 5.4, 5.9 and 6.3–6.7 s and `hero drawn` fires 12 times.
- **Library** keeps the opaque bar: the hero's top is hidden (frame 1:48) and the large and inline "Library" titles
  draw together mid-collapse (frame 2:47).
- **E2E on 18.6:** never run before 10-16; `run-e2e.py` targets 73E49263 (iOS 27) only. The six 18.6 failures found
  on 10-16 were test assumptions (d662368), which also means the crawl now judges `player.options` / `player.captions`
  "touchable" by position on iOS 18 rather than by XCTest hittability.
- **Covered:** iphone-jank b7b0a91 (layout reader; `hero drawn` 8 → 2 per launch and Discover body 82 → 41 evaluations
  on the 18.6 sim; replay test from the owner's trace; Library uses the same reader). **Not covered:** the Library bar
  (owner decision "solid or see-through?" open since 10-15, OWNER-TODO line 136), the rest of the app (checklist row
  62: title page, player, Live, Settings never walked at 10 fps on 18.6), the hangs.

### 3.6 ISO / disc playback
- **Build 15:** engine 6.66.0, ISOs play the main title only, and they played.
- **63a6d4d (10-10) / 3af460e (10-14):** engine pinned to the owner fork (DVD menus, HTTP disc reader).
  **1881b4b (10-14):** Play Disc opens the menu first, so the UDF/BDMV structure is parsed before the player opens;
  iOS showed no spinner (tvOS did). On the owner's phone that was 12–14 s of silent black; the owner closed the player
  (the `load superseded` lines are that close), so "disks don't play at all" (10-15).
- **71e2f97 (10-15, Stage B):** a duration probe before play that reads the whole ISO
  (`AppleLocalLibraryStore.swift:847` at that revision) → every disc read twice. Caught by **f299aff (10-16)**: discs
  skip the probe, the player is up in 94 ms with the disc spinner, first frame 10.6 s on DevPlus.
- **Still on the phone 10-17:** disc read 17 s, then the 20 s startup timeout (`startup timed out` in
  iphone-1017b.log). Cause: the engine reads 2 KB sectors through HTTP range requests over SMB (295 requests for
  recognition, REA round 3 §3).
- **Covered:** iso-open d627387 (16 × 1 MiB block cache in the share bridge: recognition 5.1 → 0.3 s on DevPlus; start
  budget +10 s when progressing, cap 60 s; libbluray chapter tie-break; crash guard). **Not covered:** the engine-side
  per-file parse cache (in the 7.36 rebase, not pinned); no way to close the player during the disc spinner on iOS
  (ios18 report note); Blu-ray ISOs offering Play Disc / Skip to Movie was fixed on main after the recording (frame 2:12
  shows it) and should be re-checked on the owner's phone.

### 3.7 Metadata speed
- Not a regression from build 15: the 10-14 complaint (double spinner, slow title open, "metadata fails often") was
  researched in `design/reference-apps/2026-10-14-metadata-artwork.md` and found pre-existing causes (negative cache
  without a reason, search names, no ID-first lookup) → 947fdc1 (10-14), e4409ca (10-15), 77538b9 Unmatched (10-16).
- What did regress: 13a2677's 1.5 s black hold on the title page and 73455c3's "TMDB answer or 1.5 s" wait before the
  iPhone hero draws, both added waits as the price of "no crop / no swap"; e4409ca removed the title-page one.
- The recording's text-only Top 10 cards (frame 5:40, "these don't load any") and "Open Season 3" as a show "Open"
  (frame 0:30) are fixed in e63f693 (TMDB lookup + disk cache; parser v3).
- **Not covered:** the double spinner (owner never said which tap); `AppleTop10ArtworkStore.shared` decoding its file
  on the main thread inside Discover's body (`AppleDiscoverView.swift:1344`, review note).

### 3.8 Settings sprawl
Settings controls with a literal label across the settings files: 29 → 33, plus whole pages and rows the owner never
asked for:
- **Restrictions** (parental PIN, 30899b1) at the top of Settings.
- **Set Up from Another iPhone** and **Send Setup to Another Device** at Settings root (86ece63, item 17 "make it easy
  to find") *and* Send Setup again in Backup & Sync *and* Set Up from Another iPhone again in Sources › Add *and* on
  Welcome / No Sources (c925909): four entry points, two names, plus an **"Open the Camera"** alert that only instructs
  (`AppleSettingsViews.swift:260`, `AppleBackupSettingsView.swift:98`). Owner: "it's double … one transfer … remove
  that".
- **Live TV:** Start with last channel (db59520), sleep timer, live buffer (a65f663), guide time offset, hidden
  channels, reorder favourites (392cac6); the Channel Health sweep with its progress bar in the root list.
- **Top 10 lists** toggle: the code default is off (`AppleSettingsStore.swift:715`, unchanged since da014fb) but the
  owner's own setting is on (frame 5:10) and the row order default lists the Top 10 rows
  (`AppleDiscoverRowOrder.swift:18`). Owner: "these shouldn't be default, these top tens. That should be the add-ons".
- **Covered:** nothing; settings-narration has no commits.

### 3.9 Things the owner never asked for (evidence: commit body has no owner line; OWNER-TODO has no request before the build)

| Commit(s) | Date | Lines | What | Where the owner felt it |
|---|---|---|---|---|
| 392cac6, db59520, a65f663, 4678709, 30899b1, 731858c | 10-05 | ~4,300 | Live TV "essentials", channel banner, Start Over, provider VOD, PIN + import card, multiview | import card (5:22), Restrictions row, Settings rows, Channel Manager rows |
| 763a575, 0840e92, 238eacb, 46f86e4, 4156e07 | 10-12 | ~1,750 | Netflix / Apple TV polish 1–14 ("Owner: pick which to build" was never answered; only Netflix 8 and 11 got decisions, on 10-13, after the build) | launch CPU (recommendations ≈1.1 s), hero dwell waits for art |
| fb93313, 3aa6458, 26e88e0, a9f1888 | 10-12 | ~2,100 | Plex lessons 1–6, 9, 11 ("Owner: pick which changes to build" never answered) | 100 % CPU for 144 s (a438592), progress sync complexity |
| f82ef99 | 10-13 | 587 | Apple TV app behaviours from the Mac TV.app REA | hero cycle stops; pressed trailers blocked |
| 5e83336, 32f5729, 623087e | 10-13 | ~450 | Plex 12 EPG mapping | none visible |
| 6fe7ec2 | 10-06 | 613 | Apple TV Picture in Picture | none visible; Live PiP was asked later (10-09) |
| b6c9101 (part) | 10-09 | — | WATCHING pill as the answer to item 7 | "AI sloppy" |
| 86ece63 (part), c925909 | 10-09 | — | four Set Up / Send Setup entry points + camera alert | "it's double", "remove that" |
| f1778df (part) | 10-06 | — | tappable Recently Added header (owner asked "Library = Discover"; the chevron came along) | "I didn't ask for this" |
| 314ccc5 (pre-15) | 09-22 | — | Channel Health sweep in Settings root | "this box … I never asked for it" (5:10) |

Requested and delivered as asked: 7d771dc QR setup, 3f36924 iCloud publish, b25148e Complete Guide, 85e6f85 oStream,
Top Shelf fixes, 947fdc1 metadata, 1881b4b disc menus, ef4a4d3 iPhone hero back, 7abd843 several folders (the Add
Folder row is on screen in frame 3:55; the owner still believed only one folder was possible, so its discoverability
is the open part).

## 4. Systemic causes

### 4.1 Features added without an owner request
See 3.9: roughly 10,500 of the 20,500 new Sources lines. The pattern is the same each time: a research report ends
with "Owner: pick which to build", and the whole list is built that night (10-12: 41 commits). The owner's rule file
says "Where this file and your task disagree, ask; do not guess", and OWNER-TODO's first line says every request is a
checkbox before work starts; neither held for these.

### 4.2 Tests that asserted the wrong thing
- f82ef99: `itAdvancesAndWrapsWhenDue` → `itAdvancesWhenDueAndStopsAtTheLastPage`, `#expect(wrapped)` → `#expect(!wrapped)`.
  A behaviour the owner liked was flipped and the test rewritten to certify the flip.
- f299aff: the hero-settle tests encode the 18.6 simulator's bar behaviour (400 → 750 ms); hardware disproved them the
  next day. The iphone-jank lane added `theOwnersIOS18SessionDrawsTheHeroAtMostTwice`, replayed from the owner's trace:
  that is the right shape of test.
- d8c923c: Events-tab tests use fixture channel names containing "PPV"; the owner's lineup has none, so the test
  passes while the feature is absent for the one user who asked for it.
- 1919786: build 15's pre-ship smoke tested playback and resume, not trailers, so build 15 shipped with dark title-page
  trailers on real phones.
- d662368: on iOS 18 the crawl judges SwiftUI Menu buttons by position instead of hittability. Legitimate for XCTest's
  limitation, but it removes the one check that would catch a player control that stopped taking touches on 18.
- e63f693: `testCrawlPlayers`'s elapsed-time assertion was a test defect, correctly fixed.

### 4.3 Fixes verified on iOS 27 only
86 non-merge commits touch Sources; 9 mention iOS 18 / 18.6; 21 mention any real device; 58 cite only the unit gate
and iOS 27 / tvOS simulator builds. `run-e2e.py` cannot target the 18.6 simulator. The owner's phone traces (`v1.0 (17)` 10-09,
`v1.0 (18)` 10-14/15) hold sessions back to 10-09; they were pulled to the mini on 10-15 and first read for a fix
that night.

### 4.4 Merges that undid earlier fixes
No evil merge: of the nine merges in range, only 031ecc2 has a hand-resolved hunk (`AppleLocalFileInspection.swift`,
`AppleLocalLibraryStore.swift`), and it kept both sides (Blu-ray format + Stage B's probe). The undo chains are plain
commits, each one "fixing" the previous fix:
- hero trailers: a130f96 hidden overlay → d70aea9 visible → e63f693 4.5 s hold;
- iPhone hero: build 15 full-bleed + trailer → 73455c3 static still → ef4a4d3 full-bleed + trailer + five pause rules;
- iOS 18 bar: owner #52 readable → cca03fd opaque everywhere → f299aff transparent on Discover only;
- title page: build 15 full-bleed → 13a2677 box + 1.5 s black → e4409ca no black → hero-trailers full-bleed again;
- discs: 6.66.0 plays → fork + menus parse up front (1881b4b) → Stage B probe reads the disc again (71e2f97) → f299aff
  skips the probe → iso-open caches blocks.

### 4.5 The judging build
Finding 1. The lead's 10-17 note blames `owner-build.sh` for never passing the flag. On the mini today the lane copy
(`iphone-ios18/owner-build.sh`, mtime 10-16 00:08) does contain `SWIFT_ACTIVE_COMPILATION_CONDITIONS='$(inherited)
OPENSTREAM_ADDONS'`, and the gates report of 10-16 even logs "Owner build xcodebuild Release + add-ons → succeeded";
yet every dev session on the phone ran without add-ons. So either the installed .app predates that script or the flag
never reached the compiler; the script is not the proof, the trace is. Nothing in the install path read the trace,
and the line that shows the problem (`sources saved: 2` right under build 18's `sources saved: 8` in the same file)
went unread for 36 hours. The new `owner-install.sh` (10-17 10:57) checks the build setting; it still does not check
the phone.

### 4.6 Throughput
226 commits in 14 days, reviewed and merged by the same agent family that wrote them ("Fable review: COMMIT" in the
body), with the owner reading the result on a phone the agents could not see.

## 5. Ranked fixes

Order: owner-visible damage first, cheapest proof second. R = revert, F = fix, D = delete, O = owner decision.

1. **F — Judge only add-on builds (script changed 10-17; not yet proven on the phone).** Pull the owner's trace after
   the next install and read its first session before anything else: `sources saved: 8` and the three `manifest
   refresh` lines, and Settings › Sources › Add showing "Add Catalog". Then re-take every judgement from 10-15 22:46
   on: hero cycle, trailers, Discover content, launch. Measure: those lines in the owner's next trace session.
2. **R — Merge hero-trailers + hero-settle** (3.1, 3.2): wrap, 8 s trailer timeout, 1 s advance, 6 s still dwell,
   full-bleed title header (undo 13a2677), pressed trailers under Low Power. Measure on the owner's phone trace: ≥ 4
   `hero page` advances in the first 60 s; title-page reveal ≤ 2 s after the pick; zero `startup timed out` for trailers.
3. **O — YouTube chrome (d70aea9).** Ask the owner in one line: hide it again (build 15's CSS; the terms risk is ours)
   or accept it until server/iTunes trailers replace YouTube. Either way, delete e63f693's 4.5 s hold once decided.
   Measure: 10 fps capture of a title page shows no frame with YouTube's strip, and the reveal ≤ 2 s.
4. **F — iOS 18 bar on Library + the oscillation on hardware** (3.5): pass `overArtwork: true` for Library as well (or
   solid for both; owner decision open since 10-15, decide it now from the two screenshots), merge iphone-jank, then
   prove on the phone, not the sim. Measure: `hero drawn` ≤ 2 per launch and no `top=97`/`115` alternation in the
   owner's trace; Library hero fully visible in a frame.
5. **D — WATCHING pill; D — import card for anything but a user-started first import; F — Events tab from lineup group
   names as well as channel names, with the owner's real group list as the fixture; F — programme line for the whole
   selected category, not the visible batch** (3.3). Measure: `grep -c WATCHING` = 0 in Sources; no import card frame in
   a Live capture with a saved lineup; Events present with the owner's lineup; programme-line fill ≥ 95 % of rows 2 s
   after a category tap.
6. **R/F — ISO** (3.6): merge iso-open; pin the engine with its disc parse cache; a close control during the disc
   spinner on iOS. Measure: Play → first frame ≤ 6 s for John Wick 4 UHD on the owner's phone (17 s + timeout today),
   second open ≤ 2 s, zero `startup timed out` for discs.
7. **D/F — Settings** (3.8): one "Transfer Setup" row (to / from) in Backup & Sync; delete the other three entry points
   and the "Open the Camera" alert; move Restrictions, sleep timer, live buffer, guide offset and Channel Health under
   Live TV (or delete the ones the owner does not want); Top 10 rows off unless the owner turns them on. Measure:
   Settings root rows ≤ build 15's count; one transfer entry in the whole app.
8. **F — iPhone launch** (3.4): a launch mark (process start → first frame → first row → hero art) in the trace on
   every build; move Top 10, recommendations and Top Shelf publish out of the first 2 s. Measure on the owner's phone:
   first frame ≤ 1 s, rows ≤ 2 s, cover gone ≤ 1.5 s; the Hang HUD never above 250 ms on Discover, title page or
   Settings › Sources.
9. **D — Recently Added as a tappable page; F — Library categories** (recording 2:47–3:05): header without chevron; the
   category question belongs to R2's gap list. Measure: no "See all" route for Recently Added.
10. **R (partial) — f82ef99 leftovers:** keep the runtime-banded watched rule and post-play cap only if the owner
    wants them; drop the under-half-visible pause until a device shows it is needed. Measure: hero keeps cycling while
    the page is scrolled 40 %.
11. **F — metadata leftovers** (3.7): trace the double spinner (ask which tap once more, with the screen named); Top 10
    store decode off the main thread. Measure: no synchronous file read inside Discover's body.
12. **F — Live start time** (3.3): add `live first picture` marks and measure the owner's provider on the phone; until
    then the 15 s grace and the 20 s probe are guesses. Measure: p50 zap → picture on the owner's provider.

## 6. Process changes that would have caught each one

| Cause | Change |
|---|---|
| no-add-on judging build (1) | Every owner install prints `sources saved: N` from the trace and compares with the last TestFlight session in the same file; a mismatch blocks the install. Install scripts take the flag from one shared file, never a per-lane copy. |
| agent-chosen behaviour, test flipped (2, 4.2) | A test rename or `#expect` inversion on owner-visible behaviour needs the owner's line in the commit body ("Owner 10-13: …"). Without it the lead rejects the diff. |
| unrequested features (4, 4.1) | Nothing is built from a report's ranked list until the owner's pick is pasted into OWNER-TODO as a checkbox with a date. Reports end with "waiting for your pick", and the queue stops there. |
| iOS 27 only (5, 4.3) | `run-e2e.py` runs the 18.6 simulator with the owner's setup by default for every iPhone-facing change; a commit touching iOS UI cites the 18.6 run or says why not. The owner's phone trace is pulled after every install and its first session is read before the next fix is written. |
| sim-proven layout (4.2) | Layout and timing fixes carry a replay test from the owner's trace, like `theOwnersIOS18SessionDrawsTheHeroAtMostTwice`, not a simulator timing. |
| fixture-only coverage (Events tab) | Export the owner's lineup group and channel names (sanitised, no URLs) as a fixture and run category/guide tests on it. |
| undo chains (4.4) | A commit that changes a screen the owner approved links the approval (date, quote) and ships a before/after frame pair from the 18.6 sim with the owner setup; no second "fix" of the same screen inside a week without the owner seeing the first. |
| narration missed | Recordings are transcribed before review (the 10-15 narration was found two days later); each spoken item becomes a checklist row with a frame. |
| throughput (4.6) | Cap merges to main at what one owner session can judge (one build a day with a short "what changed for you" list); the lead does not review its own lane's diff. |

## 7. What this report could not verify
- The 4 s black at launch on 10-15 (no launch mark on that build).
- The 540–763 ms hangs (no trace with a hang mark).
- Live "takes forever" (no first-picture marks on the owner's provider).
- Whether the hero cycle still stops on a correct (add-on) build on the owner's phone after hero-trailers: the trace
  has no page-advance marks yet (hero-trailers adds `hero cycle` lines).
- The exact screen behind "this box right here, where it says IPTV" at 5:10: the frame shows the Channel Health sweep
  in Settings; the import card is the frame at 5:52.
