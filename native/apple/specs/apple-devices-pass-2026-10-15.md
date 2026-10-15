# Apple devices pass, one device at a time; Vision Pro first (owner 2026-10-15)

Owner: "now that you have dev devices lets get openstream in tip top shape of apple devices branch it out and one at a
time you might have to do multiple passes and top focus is get the gui on AVP to feature parity or gui parity to ipad
or the 'best' device."

**Where:** branch `apple-devices`, worktree `Apps/OpenStream-lanes/apple-devices` (NOT the main tree; other workers edit
main). Every mini command: `OPENSTREAM_MINI_DEST='~/Developer/openstream-build/src-apple-devices/native/apple'
scripts/mini.sh '<cmd>'` so this tree never syncs over main's running build. Simulator builds use an internal
`-derivedDataPath $HOME/Developer/sim-dd-apple-devices`. The lead merges the branch to main after each reviewed pass.
Workers never commit.

**Devices (paired with Dev-Mini):** iPhone 16e DevPlus, Apple TV 4K DevTV (2nd gen, slow) and OfficePlus (3rd gen),
Vision Pro VP (sleeps unless worn: use the Vision Pro simulator `46B2DEDC…` for everything; the owner-worn pass is
prepared by the lead). Sims: iPad Pro 13" `8939801C…`, iPhone 18 Pro `73E49263…`, Apple TV `F2107E8F…`.

Order: **Vision Pro** (this pass) → Apple TV (DevTV speed) → iPhone → iPad → Mac → Watch. Each device gets passes until
the lead and owner call it done.

## Pass 1: Vision Pro GUI parity with iPad
iPad is the reference ("best" device). 177 `os(visionOS)` branches today, most in AppleDiscoverView (38),
AppleMediaPlaybackView (20), AppleSourcesSettingsView (16).
1. **Parity map first** (`design/visionos/2026-10-15-parity-map.md`): boot the iPad 13" sim and the Vision Pro sim one
   at a time, seed the same owner content (`scripts/seed-sim.sh`), and walk every screen on both: Home/Discover hero
   and rows, Library (all shelves, filters, sort), Live (guide, categories, multiview), Search, title page (hero, art,
   trailer, versions, episodes, cast, related), player (controls, menus, skip, next episode, PiP, docking), Settings
   (every page), Sources/Add Files/network shares/media servers, first run. For each: screenshot pair + one line
   (same / missing on AVP / worse on AVP / AVP-only). Use the `rea` MCP on Apple's TV app and Infuse for visionOS
   idioms (glass, ornaments, hover, window sizes); notes only, no copied code/assets.
2. **Fix in priority order:** missing features, then broken/blank, then layout (clipping, legibility on glass, hit
   targets ≥ 60 pt, hover effects), then polish. Native visionOS idioms over iPad copies (tab ornament, glass
   backgrounds, `.hoverEffect`, windows that resize well); same features and same data as iPad.
   Small commits-worth of change at a time, each with a test (unit or UI) and the screenshot pair redone.
3. **E2E-visionOS:** do `specs/visionos-e2e-2026-10-15.md` §1 alongside (the crawl locks in every parity fix).

## Gates (every round)
Serial Swift suite; visionOS + iPadOS + iOS + tvOS builds (recompile greps); E2E-visionOS 3 green; the four Release
(no add-ons) builds when touching anything near `OPENSTREAM_ADDONS`; no regression on iPad screenshots. Everything
through buildlock, foreground. Codex/agy run to 100% of the window (owner rule).

## Report
Per AGENTS.md §7: the parity map (before/after counts), fixes with screenshot pairs, what's left, gate output.
