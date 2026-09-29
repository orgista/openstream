# OpenStream — owner to-do list

Every piece of feedback the owner gives goes here the moment it arrives, as a checkbox, before any
work starts. Ticked only when it is merged into main **and** installed on the devices; the commit
goes on the line. A request that has been asked for before is marked **(asked again)** so it is
never dropped a second time. Detail and evidence stay in `FEEDBACK.md`; this file is the list.

## Open

- [ ] **Reset: delete every source, setting and saved data in one step** (2026-09-29) — for starting fresh / testing.
- [ ] **Rework the Live GUI — "still not great", wants something better and fresh** (2026-09-29). Start with design
      directions for the owner to pick from before building.
- [ ] **Test fixture: auto-import the owner's sources into every simulator/app for testing** (2026-09-29) — one private
      file on this Mac (never in the repo or OSArchive) + a Debug-only import-at-launch hook + a seed script.
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
- [ ] **Let "Continue Watching" be removed/hidden** from Discover (2026-09-28). Today it's the one row that
      can't be hidden in Settings → Discover Rows.
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
