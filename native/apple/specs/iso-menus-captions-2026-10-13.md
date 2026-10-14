# PRIORITY: ISO playback with real disc menus on iOS (and every platform) + caption display (Codex, 2026-10-13)

Owner 2026-10-13: "prioritize the iso playback, we were supposed to have an iso playback with menus and it doesn't
work on iOS"; "test Matilda e2e, captions are off too ... we need to account for content like that"; "Test all the
isos". Decided 2026-10-01 (OWNER-TODO "ISO / disc images"): Play Disc opens the real DVD menu first (D2), Skip to Movie
plays the main title, Disc Menu button in the player (P1), disc symbol badge + spinner. Read AGENTS.md (workspace +
native/apple) first. Stock Apple look; no explainer text.

## Facts found by the lead
- The engine pin (`Package.resolved` AetherEngine 45d64e8a, fork at Dev-Mini
  `/Volumes/DevExt/dev/openstream-build/AetherEngine-fork`) HAS DVD menus: `Sources/AetherEngine/Disc/DVDMenu/*`,
  public API in `DVDMenuPublic.swift` (`LoadOptions.dvdStartMode = .menu`, `AetherEngine.dvdMenu` state with buttons
  and highlight, `DVDMenuDirection`, `DVDMenuKey`), docs `docs/dvd-menus.md` and `docs/api.md` "DVD menus".
- The app never uses it: `Sources/OpenStreamApple/AppleDiscPlayback.swift:18-23` maps `.menu` to the main title
  ("engine menu pending"); `grep dvdStartMode Sources` is empty.
- Test discs: `/Volumes/DevExt/engine-lab/corpus/dvd/menu-test.iso` and `menu-features.iso` (Dev-Mini). No other ISO
  was found on ServerPlus shares; also search the owner's library sources the e2e fixtures use and any `.iso`
  under `/Volumes/DevExt` and the e2e media folders, and list every ISO you tested.
- Matilda: `smb` ServerPlus `Media/movies/Matilda (1996)/Matilda.1996.UHD.BluRay.2160p.TrueHD.Atmos.7.1.DV.HEVC.REMUX-FraMeSToR.mkv`
  (HEVC DV, TrueHD Atmos + AC-3 + commentary, one English PGS track, not default, not forced).

## Do
1. **First reproduce on iOS** (iPhone sim, and DevPlus if the sim can't show it): load each ISO via a local library
   fixture; record what fails (error, black screen, main title only). Then tvOS sim and macOS. Root-cause before fixing.
2. Wire Play Disc → `dvdStartMode = .menu`; Skip to Movie → `.mainTitle`; Titles row → explicit title. Menu UI:
   iOS/iPadOS/visionOS tap on a button rect (frames normalized to the video rect) + highlight; tvOS remote arrows /
   select via `DVDMenuDirection` + activate; macOS arrows/click. Player "Disc Menu" control (P1) calls `dvdMenu(.root)`
   / `.title` and returns to the menu. Still menus and auto-action buttons per the engine docs. Discs without
   navigation fall back to main title. Update `AppleDiscPlaybackStart` and its trace lines (drop "pending").
3. Blu-ray ISOs: if the engine has no BD menu API, Play Disc plays the main title (BDTitleSelector) silently; report.
4. **Captions (Matilda + content like it):** play Matilda over SMB with captions Off and with English on, on iOS and
   tvOS. Off must show nothing; On must place and scale the PGS correctly on a 2160p DV picture in every aspect ratio /
   orientation (letterboxed 2.39:1 too), never cropped or off-screen, never drawn into the wrong rect after rotation.
   Repeat with corpus `subs/g-subs-pgs.mkv`, `ff-pgs-dts.m2ts`, `ff-vobsub-reddwarf.mkv`, `ff-largeres-vobsub.mkv`,
   `ff-multisub.mkv`, `g-subs-srt-ass.mkv`. Fix what is wrong (app overlay layout or engine rendering; if engine, make
   the change in the fork with its tests, report the fork commit separately; the lead pins it).
5. Tests: unit tests for the start-mode mapping, menu input mapping (direction/tap → engine calls) and caption rect
   math; E2E: add UI tests that open each test ISO with Play Disc, see the menu, select a button and reach playback,
   and Skip to Movie; a captions test (Off shows none, On shows a subtitle in-frame). Screenshots of each disc menu
   and each caption case on iPhone + Apple TV sims into `verification-artifacts/iso-menus-2026-10-13/`.

## Gates
Gate check; buildlock; serial swift test (current HEAD count, all green); iOS/tvOS/macOS builds (sim builds use
`-derivedDataPath $HOME/Developer/sim-dd-internal`); E2E-tvOS + E2E-iOS via `Tests/Fixtures/run-e2e.py` (baseline 20/0
and 40/1 AirPlay) plus the new tests. No commits (app or fork). Close what you open; shut sims down.

## Report
Repro results per ISO and platform (before), Done / Not done / Gates, per-ISO and per-caption-file result table
(after), file:line, screenshots, any fork change.
