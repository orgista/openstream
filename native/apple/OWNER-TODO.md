# OpenStream — owner to-do list

Every piece of feedback the owner gives goes here the moment it arrives, as a checkbox, before any
work starts. Ticked only when it is merged into main **and** installed on the devices; the commit
goes on the line. A request that has been asked for before is marked **(asked again)** so it is
never dropped a second time. Detail and evidence stay in `FEEDBACK.md`; this file is the list.

## Open

- [ ] **Apple TV regression on the overnight code (2026-10-01 morning):** fixes committed 2026-10-01 (gate 2519/303).
      Done, checked on the sim: 3 dead IPTV panel (error + Retry by ~9 s, was ~21 s), 5 Clear Cache label, 6 search
      exact title first (stale half-typed results re-ranked), Show Captions opens on the checked value, My Channels
      spinner. Done, unit-tested only (needs a real-stream check on the Apple TV): 1 captions stay above the
      scrubber/Next card on widescreen, 2 stock player advances at the end (+ Apple's "Next Episode" button in the
      last 20 s), Resume label. 4 long series: every episode loads (Goede Tijden 7,333, was 1,000) and a soap with
      nothing watched opens on its latest season (unit-tested; check Goede Tijden on the Apple TV).
- [ ] **iOS 18.6 iPhone regression (b4d4793, 2026-10-01):** no hang (5 titles incl. General Hospital S64), Resume,
      next episode, no tab-switch replay, English-only captions, Live error ~9 s, configure-first, 0 crashes. Open:
      FIXED (sim-checked on iOS 18.6): hero Play Trailer over the preview gets sound; title-page art comes back
      (the art itself failed to load — now tries the next image); hero shows Play only when something plays; a
      swipe pages the hero; "£" → "♪" in subtitles; General Hospital 1963 first; VoiceOver no longer reads icon
      names. Still: "A Different World" search lists the 2026 show above 1987.
      Minor: title page flashes between auto-advanced episodes; CW time left uses the stream's length (director's cut).
- [ ] **iPad regression of today's fixes (2026-10-01):** 10/11 pass (Resume, latest season, next episode, captions,
      IPTV error ~9 s, configure-first, Remove from CW, rotation, search, 0 crashes). Open:
      1. FIXED (sim-checked on iPad): switching tabs back to a title page no longer starts playback by itself
         (it replayed ~2 s later; series played a wrong episode and wiped Resume). Likely in builds since 09-25.
      2. Question: after Remove from Continue Watching the title page still says Resume (progress kept). Intended?
- [ ] **Apple TV check of 630db1d (2026-10-01):** pass: Goede Tijden opens on Season 37, stock player advances to the
      next episode, widescreen captions clear the scrubber, SNL 1975 first, Clear Cache readable, 0 crashes.
      Fixed in 5298e1c (unit-tested, not yet re-checked on the sim): Resume… shows however the title was opened;
      tvOS "Configure this add-on first." is plain text; stock player shows the real title (not "2023"); with
      Player = Native, MP4 sources come before MKV for the next episode; seeded sims no longer get the test catalogs
      (AIOMetadata is seeded on purpose in Debug/TestFlight). Still open:
      3. FIXED e8b60ec (sim-checked): stock player froze after a seek (AVPlayer stuck waiting with media buffered);
         it now plays what's buffered after 4 s.
      5. FIXED (sim-checked): Resume… now shows on Apple TV (the button was hard-coded "Play"); the player shows
         2015, not "2023"; on the stock player MP4 sources go first and MKVs are skipped instead of ~100 black-
         spinner retries. When every stream fails there is now a "Playback Unavailable" alert;
         on Native it offers "Try OpenStream Player" for that one play (sim-checked). DECIDE above still stands:
         switch automatically instead of asking?
- [ ] **iPad re-run (v2, 2026-10-01 morning):** 6 of the 9 iPad bugs from 09-30 fixed; next episode, SNL 1975,
      chapters, subtitle More… + encodings, resume after kill, rotation all pass. New / still open:
      1. HIGH: "Watch on <service>" never shows when an IPTV or SMB source exists (hasPlaybackRoute counts them,
         though they can't play catalog titles).
      2. HIGH: debrid placeholder clips ("Debrid failed to split torrent… only rar") play as the episode and
         auto-advance through the season; SNL then drops out of Continue Watching.
      3. Live tab waits ~35 s on one unreachable IPTV panel before showing other playlists.
      4. Still open: Hail Mary title page text instead of logo; title-page margins 40/16; Settings not split in
         landscape; text fields with only placeholders (no labels).
      UX: player icons vanish over bright video; subtitle cue drawn 3× over the Next Episode card; title name doesn't
      scale at accessibility sizes; live stall shows a frozen frame + Play icon; duplicate Paramount+/Peacock tiers.
- [ ] **iPhone 27 re-run (v2, 2026-10-01 dawn):** most fixes since 09-30 hold (chapters, Quality, Also available on,
      watch-link spam gone, row names, metadata on after seed, Stranger Things #1, audio labels + checkmark, subtitle
      More…, menus stay open, long series open fast, encrypted backup). Still broken / new:
      1. P0: Next Episode countdown ends → player closes, the next episode never plays (2/2); Continue Watching
         doesn't show the next episode.
      2. SNL S1E1/E2 still play "Saturday Night Live U K … 2026" — demotion misses "U K".
      3. Sidecar subtitles: Windows-1251 (Russian) mojibake; UTF-16 (Portuguese) shows nothing.
      4. AX-XXXL Dynamic Type: hero/title header collide with the nav bar, Play clipped, scrubber squeezed.
      5. Add Service row only tappable on its label; its top-10 list is still odd; Subtitle Languages first row under
         the nav bar; truncated-file failure shows raw engine text; Live error ".." with no Retry; search results
         still show "AIOMetadata  | ElfHosted"; Quality sheet has no Done.
- [ ] **P0 iOS 18: app freezes when opening a title from Discover** (2026-10-01, iOS 18.6 sim, 3/3; hero or poster
      tap; main thread 100% in the navigation push layout, app frame AppleCatalogItemDetailView.phoneHero).
      Search → title works. Old iOS 18 crash: 0 crashes now.
- [ ] Watch on Netflix opened tv.apple.com when the Netflix app/id was missing — a fallback must stay on the
      labelled service (Netflix search), not jump to Apple TV.
- [ ] iOS 18 UX: nav icons + large "Discover" title unreadable on bright hero art (no glass on iOS 18); Streaming
      Services "Add Service" only tappable on its label; full-screen player not modal for VoiceOver; a search
      deep link with a title page open lands under it.
- [ ] **tvOS verification of 4fd1ac5 (2026-10-01 early):** toggles/Retry readable ✅, cue placement ✅, field outlines ✅,
      audio labels ✅. Still broken: **every Settings Picker on tvOS opens an empty page** (Package, Live view,
      Playback › Player; Menu there quits to Home) — pre-existing; Skip Intro still not reachable with Down; Top 10
      "Wonka's" tile blank (TMDB+Cinemeta share an IMDb id → merge hides the TMDB record from the Top 10 artwork
      match); subtitle/audio menus keep the old checkmark after picking from More…/another track; Channel Manager
      error row draws an empty capsule; captions "off" still auto-selects English on some launches; a sparse-cue
      subtitle shows nothing after a mid-stream switch; UI test testFullSubtitleMenuSelectsSpanish needs updating.
- [ ] **Full-test bugs (Apple TV tvOS 27, v2 plan, 2026-10-01 overnight):**
      1. HIGH: focused toggle rows (Settings › Sources › add-on, catalog toggles) and the "Playback Failed" Retry
         button show no label — white text on the white focus pill.
      2. Opening Rate on a title page drops focus back to Play (B22 regression).
      3. Subtitle menu has no "More…" — non-preferred languages (Spanish) unreachable.
      4. Audio menu shows raw labels ("ENG (ac3) (eng)") and no checkmark on the playing track.
      5. Search "stranger things": the 2013 movie ranks first, twice (Cinemeta + TMDB not merged); 2016 series 3rd.
      6. Truncated file reports "format OpenStream cannot play" instead of an incomplete/network error.
      7. Skip Intro appears but Down from the video never reaches it.
      8. Channel Manager: Package page blank and My Channels spinner endless when the IPTV panel is down.
      9. Local playlists/channel health stored in Application Support — check tvOS purge safety (Swiftfin's #1 issue).
      UX: subtitle cue drawn on the scrubber line; tvOS form fields have no outline and an invisible placeholder;
      Live search "Clear Search" is red; weak focus in the guide; Top 10 "Wonka's" tile blank.
- [ ] **Streaming services must be useful, not just a label** (2026-09-30): when no add-on/source can play a title,
      Play becomes "Watch on <service>" (menu if several of the viewer's services have it), and it must open the
      TITLE in that app, not just the app. Plan: TMDB/JustWatch providers for availability; per-service title IDs
      from Wikidata (Netflix/Disney+/Hulu/Prime/Max/Apple TV by IMDb id) → universal links; fallback = service
      search for the title. tvOS deep links are limited (search/TV app fallback). Overnight: verify which links work.
      **Owner decision 2026-09-30: use Wikidata** for the per-service title IDs.
- [ ] **Test every public Stremio add-on (FMHY + r/StremioAddons + community catalogue)** (2026-09-30) — list, a
      headless harness using the app's own add-on code (manifest/catalog/meta/stream/subtitles), then in-app
      spot checks of flagged + top 20; harness kept for every release.
      **First sweep 2026-09-30 (17d6a4e): 594 probed, 0 crashes.** App fixes found: only movie/series catalogs used
      (78 add-ons show nothing: tv/anime/channel types); 2 MB catalog limit rejects TMDB's 12 MB shelf; catalog items
      without a name dropped (poster-only tiles in Stremio); meta requires an exact id match (Stravo mx→tt) and rejects
      redirects; 12-catalog cap hides catalogs; manifests with no resources accepted (unconfigured AIO Metadata);
      AppleAddonURLSecretPolicy flags 14 public add-ons as secret; 100-item shelves; one subtitle track per language.
- [ ] **Crash reported: the stravio.site add-on crashes the app** (2026-09-30, tester report).
- [ ] **Full-test bugs (iPad iOS 27, 2026-09-30):**
      1. HIGH: after Search → open result → Play, the player's controls/tap area are squeezed into the top 458 pt
         (keyboard height left over); rotating fixes it.
      2. Audio & Subtitles menu closes itself after 2-3 s (auto-hide of the controls closes it).
      3. "Also available on" never appears on iPad with Metadata on + Apple TV/Netflix added (no provider trace).
      4. Hail Mary title page shows text while its Discover hero shows the logo.
      UX: player controls vanish over bright video (no shadow), small 44 pt buttons on a big screen; Settings is one
      stretched list in landscape (no split view); Library hero ~200 pt with the logo touching the edge; title-page
      margins 40 vs 16 pt; duplicate raw audio labels "ENG (eac3) (eng)"; Radarr profile shows raw `7 = "…"`; import
      sheet pushed into the tab bar by the keyboard; unlabeled Search field, key fields and Radarr/Sonarr fields.
- [ ] **Full-test bugs (iPhone iOS 27, 2026-09-30; details in the test report):**
      1. Wrong show plays: SNL S1E1 (1975) plays "Saturday Night Live UK" — stream candidates not filtered by title/year.
      2. Chapters found by the engine (16 for Top Gun: Maverick) never appear in the player/scrubber; Quality item does nothing.
      3. Watch link retries "publish failed — not paired" every 250 ms forever (1,433 lines/25 min).
      4. Library shows "No Videos" when the share refuses access — show the error instead.
      5. Dev seed applies the TMDB key but leaves Use Metadata APIs off.
      UX: portrait title-hero trailer is a blurry crop; See All has no posters; search ranks the 2016 Stranger Things
      3rd; Add Service top 10 is odd (JustWatch TV, Amazon Video; no HBO Max/Paramount+/Peacock); "Metadata Is Off"
      dead end; number pad has no Done; subtitle menu check indent; raw add-on names in row headers
      ("AIOMetadata  | ElfHosted"); Top 10 row pops in above Airing Today; can't clear a rating; Subtitle Languages
      first row under the nav bar; no-backdrop title is a big black area.
- [ ] **Reset: a total wipe of the app on this device** (2026-09-29) — everything incl. downloads; the last step is
      holding the final button for 5 seconds. Owner: device-only; tell the viewer iCloud data must be deleted manually.
- [ ] **Rework the Live GUI — "still not great", wants something better and fresh** (2026-09-29). Start with design
      directions for the owner to pick from before building.
- [ ] **Test fixture: auto-import the owner's sources into every simulator/app for testing** (2026-09-29) — one private
      file on this Mac (never in the repo or OSArchive) + a Debug-only import-at-launch hook + a seed script.
      `scripts/dev-sources.py` (interactive; can pull every add-on from the Stremio account) writes
      ~/Developer/openstream-build/signing/dev-sources.json. Still to build: the app hook + scripts/seed-sim.sh.
- [ ] **Import Backup leaves every source "Needs Sign-In"** (2026-09-29, iOS 18 sim). The file was exported without a
      passphrase, which silently drops all credentials AND the addon URL paths, so even public addons (Cinemeta,
      OpenSubtitles) arrive broken. Fix: public addons keep working without a passphrase; exporting makes the
      passphrase choice explicit; Needs Sign-In rows are tappable to fix.
      **Owner direction 2026-09-29:** the backup always contains everything (passwords included), encrypted so only
      OpenStream on their own devices can read it (key in iCloud Keychain; passphrase only for another Apple Account),
      and restores with no Needs Sign-In. Also: the Enabled toggle on imported sources can't be turned on — fix.
- [ ] **Hero title logos (word art) not showing — plain text title instead** (2026-09-29, iOS 18 sim screenshot:
      "JEOPARDY!" in bold text over the backdrop).
- [ ] **Play Trailer tap turns sound on** (owner decision 2026-09-28: yes). Autoplaying hero trailers stay muted;
      an explicit Play Trailer press unmutes.
- [ ] **Streaming services: keep the quiet "Also available on …" line only (owner chose option a), but make it
      easier to spot** — no Play replacement, no service rows.
- [ ] **Subtitles menu still lists every language instead of defaulting to English (asked again)**
      (2026-09-28, build 14). The earlier fix (FEEDBACK.md "A picked language was not the only option")
      only filters strictly when a language was explicitly picked; with device defaults and no exact match it
      still falls back to every track. English should be the default and the only entry.
- [ ] **Streaming services setting: an "Add" menu instead of the long list, top 10 by popularity only**
      (2026-09-28). Owner also asks what turning one on does — toggling Netflix on showed no visible difference.
- [ ] **When a trailer ends it should go back to the movie art** (2026-09-28, owner) — today it stays on the
      finished video.
- [ ] **iPhone crash: UINavigationBar layout assertion** (TestFlight crashes on builds 10 and 12, iOS 18.7, 4 of 4
      readable reports; one tester comment "Search"). Owner shared another crash on build 14 today — not yet
      in App Store Connect; read it when it appears.
      **Build 14 crash read 2026-09-29** (AMKnSe6teuQS5qAin8cixtU, iPhone 15 Pro Max iOS 18.7.8, "Just scrolling the
      app"): same assertion, reached from a layout pass while scrolling Discover, with loadTop10 running. 305af48
      (not in build 14) removes the Discover Refresh item flip; hardening the scroll-driven hero layout too.
      **Root cause found 2026-09-30:** tapping the tab you're already on rebuilds that tab's navigation stack
      (`.id` bump), which iOS 18 rejects — 24/24 crashes on the iOS 18 sim, build 14 AND main. 305af48 did not fix
      it. Fix in progress: pop to root without rebuilding; deep links too.
- [ ] **iCloud sync / backup on a new device (asked again)** (2026-09-28, iPad, build 14): a fresh iPad with no
      sources gets nothing from iCloud, so there's no content, and there's no visible backup/import to
      bring the setup over. Make iCloud sync switchable on and working on a fresh install, and make
      backup/import easy to find from the empty state. **Fix committed 66e2d46** (sync on by default, fresh
      device pulls, keychain retry, Restore/Import buttons on No Sources) — tick once installed (build 15).
- [ ] **iOS trailers don't play** (2026-09-28, build 14). Failures are silent by design; asked the owner whether
      Auto-Play Video Previews is on and whether Play Trailer on a title page fails too.
- [ ] **iOS Live TV subtitles are out of sync — they appear too late** (2026-09-28, build 14; they show up now).
      **Fix committed 1f3f9f0** (cues follow the on-screen frame, not the scrub clock) — tick once installed.
- [ ] **Apple Intelligence** (2026-09-28): owner asks where it could help when available. Ideas to propose.
- [ ] **Remove a specific title from Continue Watching** (2026-09-28; clarified 2026-09-29: per title like Netflix,
      not hiding the whole row). Progress is kept; it comes back if played again.
- [ ] **Discover Rows reorder is hard to use** (2026-09-28, Mac screenshot): the list of ↑/↓ chevrons
      works but isn't friendly for long moves (about 25 rows). Make it drag-and-drop (or similar) on
      every platform, keeping a non-drag way for Apple TV and accessibility.

## Waiting on an owner decision

- [ ] **YouTube attribution.** The trailer frame CSS (N49) hides YouTube's title, channel and link;
      the fast iPhone/iPad trailer start (a130f96) relies on it. YouTube's API terms may require
      showing it. Keep it, or go back to the fixed wait on iPhone/iPad?
- [ ] **Trailers with the title burned in.** Some trailers open on their own title card, so on the Mac
      hero a faint second wordmark shows behind ours (N57). Keep those trailers, or skip them?
- [ ] **Apple TV row headers** are 76 pt, about twice the Apple TV app's 38 pt. Shrink to match?
- [ ] **"Remove the gradient"** — the screenshot was lost (2026-09-25). Which gradient? Retake it.
- [ ] **iPhone tab bar shrinking on scroll** — allow it (the system behaviour), or keep it fixed?
- [ ] **Receipt check (N39 F1).** The app tells TestFlight builds apart (to turn tracing on) with
      Apple's deprecated receipt URL, the last build warning. Its replacement is async and can put an
      App Store sign-in prompt on the Mac. Keep the deprecated check (recommended), or switch?
- [ ] **ServerPlus 3090:** passed a full overnight bench test on Windows (2026-09-27, 350 W, 0 errors), so it may
      be the DEG1/OCuLink path at 3090 power. The server runs a 2080 Ti for now (11 GB: the 27B local
      model is slow). Next: capped run on the server (200 W + locked clocks), or a new dock, or return it.

## Done

- [x] **Refresh spinner too big / poor UX** — the refresh arrow now stays the same size and turns
      while the tab reloads (iPhone, iPad, Mac, Vision Pro) — e4b8dee, installed 2026-09-26.
- [x] Crash report pasted 2026-09-26: **PosterBoard** (Apple's own screensaver process) in the Apple
      TV simulator, 01:09. Not OpenStream; it crashed inside Apple's framework while loading screensaver
      posters. No app change.
- [x] Narrow Mac windows: no decision needed any more. Since N62 the trailer covers the hero at
      every width; checked 2026-09-26 at 900 and 1100 pt wide on main ab12598, no black strip.
- [x] **Remove the "New Episode" pill** (asked several times) — gone from every hero (iPhone,
      iPad, Mac, Apple TV) and from the title pages ("New Season" / "New Episode Every …" too) —
      c9010e7, installed 08:45; Apple TV Dark Matter hero checked without it.
- [x] Discover row order is a setting (Settings → Discover Rows); Featured Movies / Shows can move
      above Your Library — 74a479e (N67).
- [x] If a streaming service (e.g. TorBox) is down, fall back to the next best one — 74a479e (N68).
- [x] Mac trailer no longer letterboxed in the hero — e92c9eb (N62).
- [x] Wordmark first; the text title only if the wordmark fails for 5 s (no swap/shift) — e92c9eb,
      7c6328d, 1ba00a9 (N62–N64).
- [x] Clicking a trailer on the Mac title page plays it; the trailer autoplays there — 28f7fb7,
      d3e116a, d513f8e (N69–N70).
- [x] Trailers reveal fast on iPhone/iPad — a130f96 (N75).
- [x] Apple TV white-on-white dialogs (Discover Rows, SharePlay source, Download Options) readable;
      destructive rows red — a2381dc, e60e277, 02d3e0e, abd9754 (N71–N74).
