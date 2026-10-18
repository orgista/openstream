# iPhone feedback checklist (owner's 15 Pro Max, iOS 18)

Spec `specs/iphone-jank-2026-10-17.md`. One row per iPhone/iOS item the owner reported since build 16, plus the open ones from
before it and today's messages. Sources: `OWNER-TODO.md`, `specs/iphone-recording-1015-2026-10-16.md` (+ report/review),
`specs/iphone-ios18-discs-2026-10-15.md` (+ report/review/gates), the Dev-Mini owner feedback log (one entry, Apple TV
Top Shelf only, left out), and the owner's messages of 2026-10-17. Hashes are HEAD's (several in OWNER-TODO were rebased).

**Status on iOS 18:** `verified` = seen working on the iOS 18.6 sim 7530ECB2 (owner's imported setup) in this lane;
`fixed` = changed in this lane, seen working on 18.6, iOS 27 E2E unchanged; `broken` = reproduced as still wrong; `not checked` = the
docs' claim only, not exercised on iOS 18 here; `owner` = needs the owner's phone, data or decision.

**Evidence root:** `dev-mini:/Volumes/DevExt/dev/openstream-build/iphone-jank/out/<label>-<sim>-<HHMM>/`
(`run.mp4`, `frames/` at 10 fps, `trace.log`, `counts.txt`, `marks.txt`, PNGs). Capture: `jank.sh run <label> <udid>`
beside it, driving `AppleUXCaptureUITests/testB8DiscoverJank`. `base` = main 72966f9, `after` = this lane.

## Today's items (2026-10-17)

| # | Item | Where reported | iOS 18 status | Evidence |
|---|---|---|---|---|
| 1 | ISOs fail to play (disc read 17 s, then the 20 s startup timeout) | owner 10-17; trace iphone-1017b.log; OWNER-TODO 2b | broken, recorded only (job iso-open owns it) | iphone-1017b.log session 14:53Z |
| 2 | Hero cycle gone | owner 10-17 | fixed: the cycle wraps from the last page again (f82ef99 stopped it after page 5, about 48 s on the owner's phone, where no hero trailer has started since build 17). A playing hero trailer still holds its page until it ends (build 15 did too); a trailer that never comes on screen now lets go after 15 s | unit tests `itAdvancesWhenDueAndWrapsFromTheLastPage`, `theLastPageWrapsToTheFirstAfterItsTrailer`; `hero cycle` trace lines (new) in after-iPhone15ProMaxiOS18-1118 and after-iPhone18Pro-1143 |
| 3 | Title-page trailers worse than build 15 (ad66774) | owner 10-17 | owner (decisions), before-state recorded | `design/reference-apps/2026-10-17-rea-hero-trailers-disc.md` §4 |
| 4 | General jank, "app has gotten overall worse" | owner 10-17 | partly fixed: Discover's whole body no longer re-runs on every frame the iOS 18 bar collapses or expands; Library had the same reader. Other screens not walked (see 62) | probe runs base-iPhone15ProMaxiOS18-1109 vs after-iPhone15ProMaxiOS18-1111 (`discover body` 82 → 41 over the same script; about 30 → 1 during the four drags) |
| 5 | Discover hero relayouts on the phone: top inset 97↔115, `hero drawn` 12× in 3 s | trace iphone-1017b.log (jank spec §1) | fixed: the readings stay in `AppleDiscoverHeroLayoutReader`; a sub-point tab bar change (82.67 ↔ 83 pt) no longer redraws the hero; the page size ignores the bar's 18 pt | replay test `theOwnersIOS18SessionDrawsTheHeroAtMostTwice`; base-iPhone15ProMaxiOS18-1109 `hero drawn` 8 (6 identical-looking redraws at 44.9–45.2 s) vs after-*-1111/-1118 `hero drawn` 2; frames/ at 10 fps |

## Hero, Discover, Library

| # | Item | Where reported | iOS 18 status | Evidence |
|---|---|---|---|---|
| 6 | Hero shows "Movie · …" and Resume but no title | ios18-gates notes | fixed: a titled poster card's trailer covers the poster, so the hero draws the name while the video is up | before: after-iPhone15ProMaxiOS18-1049/after-jank-01-after-30s.png (Spider-Man trailer, no name); after: after-iPhone15ProMaxiOS18-1118/after-jank-01-after-30s.png (wordmark over the trailer); test `aTitledPostersTrailerBringsTheNameBack` |
| 7 | iPhone hero lost trailers / full-screen look ("my fave feature") | OWNER-TODO:156 | verified on sim (trailers start at 3.7 s); owner's phone traced no `hero trailer start` since build 17: check Low Power / Auto-Play Video Previews | after-iPhone15ProMaxiOS18-1118/trace.log (`hero trailer start` at 3.7 s, 4 pages) |
| 8 | Hero cut off, off centre, too zoomed | OWNER-TODO:307 (item 6) | verified (poster card and still pages) | after-*/after-jank-00-rest.png, -08-swipe.png |
| 9 | Library hero has the same crop problem | OWNER-TODO:341 (item 19) | not checked | |
| 10 | See-through top bar over the hero on iOS 18 | OWNER-TODO:117 | owner (decide from screenshots) | after-*/after-jank-00-rest.png |
| 11 | Nav icons and large title unreadable on bright art | OWNER-TODO:820 | not checked (at risk: bar is transparent since f299aff) | |
| 12 | Billboard locks a pick before Continue Watching is known | recording report "Not done" 1; OWNER-TODO 2e a | not checked (open) | |
| 13 | Top 10 cards with no artwork | recording #2 | not checked | |
| 14 | Top 10 rows take about 13 s | recording report | not checked | |
| 15 | Launch: about 4 s black screen with a faint spinner | recording #1 | owner (not reproduced on sim; speed lanes own it) | |
| 16 | Hangs of 0.5–0.75 s ("oStream 540 ms" capsule) after the full-screen trailer and on Settings › Sources | recording #7; OWNER-TODO 2e b | not checked | |
| 17 | "Open Season 3" shown as a show | recording #3 | not checked | |
| 18 | Top Picks duplicates; Continue Watching order; next episode | OWNER-TODO:621 | owner (needs watch history) | |
| 19 | "Provider's movies unavailable" should name the provider | item 18 | not checked | |
| 20 | Metadata fails often | OWNER-TODO:128 | not checked | |

## Title page and trailers

| # | Item | Where reported | iOS 18 status | Evidence |
|---|---|---|---|---|
| 21 | Trailer reveal late (about 6 s after it is picked; art held to 4.5 s of media, e63f693) | owner 10-17 via #3; trace 10-17 | owner (trade-off with #24) | REA round 3 §4 |
| 22 | iPhone title page trailer is a small 16:9 box (13a2677) instead of build 15's full-bleed header | REA round 3 §4 | owner (REA recommends undoing) | REA round 3 §4 |
| 23 | Build 16: trailer flashes then disappears; tapping another trailer doesn't play it | OWNER-TODO:448 | not checked | |
| 24 | YouTube UI over trailers (title strip, logo, More videos) | recording #6 | owner (d70aea9 left it visible for YouTube's terms) | REA round 3 §4 |
| 25 | Trailer "startup timed out" (Matilda, 15 s) | iphone-1017b.log:1286 | not checked | |
| 26 | Trailers have no audio / no mute control | items 2–3 | not checked | |
| 27 | Glitchy trailer start (flash, art jump) | item 4 | not checked | |
| 28 | Paused trailer shows a triple-circle glyph | item 5 | not checked | |
| 29 | Title trailer keeps playing under a disc load | ios18-discs spec | not checked | |
| 30 | Title page back/search buttons have no round backgrounds on iOS 18 | ios18-report | not checked | |
| 31 | Cast faces cut off in circles | item 1 | not checked | |
| 32 | Episode row jumps about 28 pt when a download starts | recording spec; ios18-e2e report | iOS 27: E2E `testDownloadStartsWithoutAskingForASource`, `testCrawlDetailAndEpisodes` pass (no y check of its own); iOS 18.6: E2E passes (`e2e-ios18-summary.txt`) | |
| 33 | Double loading spinner when opening content | OWNER-TODO:128 | owner ("which device/tap?") | |
| 34 | Title open slow; page fills slowly | OWNER-TODO:128 | not checked (speed lanes) | |

## Player, ISO, discs

| # | Item | Where reported | iOS 18 status | Evidence |
|---|---|---|---|---|
| 35 | Disc Play: silent black wait of 12–14 s | ios18-discs spec | not checked (iso-open) | |
| 36 | No way to close the player during the disc-read spinner | ios18-gates notes | not checked (iso-open) | |
| 37 | Disc picks the wrong title (Airbender played clip 00125) | ios18-discs spec | not checked (iso-open; REA §3 tie-breaks) | |
| 38 | Blu-ray ISO still offers Play Disc / Skip to Movie | recording #5 | not checked | |
| 39 | Real DVD menus on iOS; test every ISO | OWNER-TODO:162 | not checked (iso-open) | |
| 40 | Matilda captions wrong (PGS) | OWNER-TODO:162 | not checked | |
| 41 | "Did not return a compatible source" | OWNER-TODO:914 | not checked | |

## Live

| # | Item | Where reported | iOS 18 status | Evidence |
|---|---|---|---|---|
| 42 | "Importing · 0 channels" toast repeats | recording #4 | not checked | |
| 43 | "No channels" shown first | recording #4 | not checked | |
| 44 | Provider timeouts shown loudly; "Can't reach IPTV" | recording #4 | not checked | |
| 45 | Live doesn't play with the owner's config (0 of 5 channels) | OWNER-TODO:402 | owner (needs the provider) | |
| 46 | "Can't reach" dialog looks off | OWNER-TODO:906 | not checked | |
| 47 | Error says "stream limit" for an IP block | item 20 | not checked | |
| 48 | Live player a cut-off box; nothing shows which channel is on | item 7 | iOS 27: `testLiveTappedStatesArePhotographed` passes; `testCrawlLive` fails on AirPlay (known) and a Live clock that did not settle; iOS 18.6: E2E passes (`e2e-ios18-summary.txt`) | |
| 49 | Category bar floats and jumps on scroll | item 8 | iOS 27: verified by E2E (`testLiveLayoutIsStable`); iOS 18.6 E2E: E2E passes (`e2e-ios18-summary.txt`) | |
| 50 | Live title and search waste space | item 9 | not checked | |
| 51 | Translucent tab bar over the guide | item 10 | not checked | |
| 52 | Where is pay-per-view? | item 11 | not checked | |
| 53 | Full-screen Live chrome (X, Channels/Last Channel, progress bar, icons) | items 12–15 | not checked | |
| 54 | Swiping home stops Live (PiP) | OWNER-TODO:860 | not checked | |

## Settings, sources, sync

| # | Item | Where reported | iOS 18 status | Evidence |
|---|---|---|---|---|
| 55 | Remove "Export Working M3U" | item 16 | not checked | |
| 56 | Can't find QR Set Up / Send Setup | item 17 | not checked | |
| 57 | Rill / Jellyfin: "The server's reply made no sense" | ios18-discs spec; OWNER-TODO:281 | not checked | |
| 58 | Several folders from one share | OWNER-TODO:168 | not checked | |
| 59 | iCloud sync looks broken | OWNER-TODO:437 | owner (two devices) | |
| 60 | QR setup iPhone → TV/iPad | OWNER-TODO:427 | owner (two devices) | |

## Older iOS 18 leftovers and pending calls

| # | Item | Where reported | iOS 18 status | Evidence |
|---|---|---|---|---|
| 61 | Six E2E tests failed on iOS 18.6 (Save sheet, widget, episode download, stub row, landscape tab bar, player options) | OWNER-TODO 2c; ios18-e2e spec | iOS 27: 41/42 pass (`testCrawlLive`: AirPlay, known since f82ef99's gate); Save sheet, widget, episode download, landscape tab bar pass. iOS 18.6: 41/43 pass; Save sheet, widget, episode download, landscape tab bar, player options pass; the two left are the known 18.6 ones (`testCrawlLive` AirPlay, Messages share bubble) | `dev-mini:…/iphone-jank/e2e-ios27-summary.txt`, `e2e-ios18-summary.txt` |
| 62 | "iOS 18 build is worse, a ton of issues" (full 18 vs 27 walk never done) | OWNER-TODO:25 | not checked (this lane covered Discover only) | |
| 63 | "A Different World" search order; title page flashes between auto-advanced episodes; CW time left uses stream length | OWNER-TODO:570-576 | not checked | |
| 64 | 09-30 UX leftovers (See All posters, Add Service list, "Metadata Is Off", number pad Done, clearing a rating, no-backdrop title, Top 10 pop-in) | OWNER-TODO:595-605 | not checked | |
| 65 | Pending owner calls: PiP/AirPlay in the player, Refresh, Share, long-press menus, Start from Beginning | OWNER-TODO:612, :491 | owner | |

## Summary

65 rows. Fixed in this lane and verified on the iOS 18.6 sim, iOS 27 E2E unchanged: 3 (rows 2, 5, 6); partly fixed: 1 (row 4).
Verified on iOS 18.6 (sim capture or E2E): 6 (rows 7, 8, 32, 48, 49, 61). Still broken, owned elsewhere: 1 (row 1, ISO
open, job iso-open). Owner decision, device or data: 12. Not checked on iOS 18 in this lane: 42.

Not done: the owner's iPhone (00008130…) was unavailable (not connected or locked) all session, so nothing was
installed and no trace was pulled; DevPlus was not used. The rest of the app (title page, player, Live, Settings) still
needs the same 10 fps walk on iOS 18.6 (row 62).

## Narrated recording — Job B (2026-10-17)

| Time | Owner's words | Change / status | Evidence |
|---|---|---|---|
| 1:48 | “this gets cut off, can't see the full poster” | Already fixed in batch-1017b; signed baseline on the owner iOS 18.6 setup shows the full Airbender poster. | `../2026-10-17-settings-narration/108.png`, `ios18-before-library.png`, `ios18-after-library-top.png` |
| 2:47 | “there's not enough categories in library, it just says movies” | Movies/Shows retained; provider genres now survive matching and cached matches backfill without losing artwork or added dates. Full serial package gate: 3,553 tests / 443 suites. | `../2026-10-17-settings-narration/167.png`, `ios18-after-library-genres.png` (Thriller shelf) |
| 2:59 | “I shouldn't be able to tap recently added here … I didn't ask for this” | Recently Added is a plain shelf heading. | `../2026-10-17-settings-narration/179.png`, `ios18-after-library.png` |
| 3:34 | “I could only add still one folder … I need two folders, which is movies and TV” | Root cause: Add Folder was only on the Sources list (frame 235); on the share's own page (frame 214) the only way to TV was the Folder row, whose edit replaces the folder, so picking TV turned Movies into TV instead of adding it. That page now has an Add Folder row (no glyph, like its section) that adds TV beside Movies; mocked Movies → TV preservation test passes. | `../2026-10-17-settings-narration/214.png`, `ios18-after-share-details.png`, `ios18-after-share-folder-browser.png` (opened, nothing added) |
| 3:55–4:20 | “one transfer, then … transfer to, or transfer from”; “open camera, point at another device … remove that” | One Transfer entry with To/From on iPhone, iPad and Mac; camera alerts and duplicate entries removed. Transfer To scans the other device's Transfer From code in the app (VisionKit, else AVFoundation), with the Share Link field as the fallback below it. The scanner stays hidden until the app's Info.plist has a camera usage description (owner/lead to add; agents may not edit Info.plist keys). Apple TV only receives: its Transfer opens the receiver, and first-run keeps Transfer from iPhone. | `../2026-10-17-settings-narration/235.png`, `260.png`, `ios18-after-settings-transfer.png`, `ios18-after-transfer-directions.png`, `ios18-after-transfer-to.png`, `ios18-after-transfer-from.png` |
| 4:28 | “the API key there” | TMDB/OMDb fields moved to Advanced. | `../2026-10-17-settings-narration/268.png`, `ios18-after-metadata-default.png`, `ios18-after-metadata-advanced.png` |
| 5:40 | “these shouldn't be default, these top tens. That should be the add-ons” | Default is already off in batch-1017b; opt-in and persistence regression test passes. The owner simulator has a saved ON preference, which is preserved. | `../2026-10-17-settings-narration/340.png`, `ios18-after-top-ten.png` (owner's saved ON) |
| 6:26 | “This button could use word 2, the test connection” | Media server action shortened to Test; VoiceOver still says Test Connection. | `../2026-10-17-settings-narration/386.png`, `ios18-after-add-media-server.png` |

Build verification (2026-10-18): serial package gate 3,553 tests / 443 suites; iOS app + UI tests and tvOS Debug build. After screenshots: this branch's build on the owner's iOS 18.6 simulator (owner app and data put back and hash-checked afterwards); the walk only opens Add Folder's browser and adds nothing. Earlier: no-add-ons Release iOS/tvOS/visionOS/macOS and SDK floors passed; the standard parallel gate failed 10 issues in unchanged chapter/caption tests.
