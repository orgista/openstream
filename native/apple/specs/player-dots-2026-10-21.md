# Owner feedback 2026-10-21 21:15: Apple TV double spinner; iOS player has two "•••" menus

Owner, verbatim: "apple tv still has double loading circles not tried on office plus as soon as content loads there is
two and on iOS there is two "dots" in the player one always there for sleep settings (iOS) and another to enable
subtiles can't these dots be merged so that static menu dots aren't there"
(Owner UI rules, AGENTS.md §4: no double spinners; controls auto-hide; one captions control; stock Apple look.)

## 1. tvOS: two loading indicators at once "as soon as content loads"
Reproduce on the tvOS sim F2107E8F (stub fixtures) and on DevTV (never OfficePlus): capture screenshots every ~250 ms
from launch through Discover/hero/rows loading, opening a title page, and starting playback. Find every moment two
progress indicators are on screen together (e.g. a screen-level spinner plus a row/hero/player spinner, or the app's
spinner plus AVPlayer's own). Keep exactly one per screen (the one at the place the user is looking), remove or
suppress the other. Add a UI test that counts visible activity indicators during load (≤ 1).

## 2. iOS player: merge the two "•••" menus; nothing static
Today the iPhone player shows one ellipsis menu that is ALWAYS visible (sleep timer/settings) and another for
subtitles. Make it one: a single "•••" (or the Apple TV app's equivalent) that holds sleep timer + playback options,
alongside the ONE captions control, all inside the auto-hiding control layer — nothing stays on screen once controls
hide. Measure the Apple TV app's iPhone player first (openstream-reference-patterns skill; DevPlus) for which controls
sit where, and match it. Same check on iPad and in Live full screen. UI tests: controls hidden → no menu button
hittable; controls shown → exactly one "•••" and one captions control.

## Rules
Dev-Mini only (`scripts/mini.sh`, `OPENSTREAM_MINI_DEST='~/Developer/openstream-build/lanes/player-dots'`); your OWN
simulator DerivedData `~/Developer/sim-dd-player-dots` (never the shared sim-dd-internal); sims/devices via
`~/Developer/bin/buildlock.sh`, compile via `buildlock-compile.sh` (FIFO; others share the mini — queue, never kill).
Owner sims (7530ECB2, and now 8939801C, 57B18C7A, 2E61439B are getting owner data) only via
`/Volumes/DevExt/dev/openstream-build/batch-1018a/protected.py`. Never Anthony/OfficePlus. Keep internal disk > 15 GB.
No commits. Gates: serial swift test; iOS + tvOS Debug, iOS Release; testCrawlPlayers, player UI tests on 18.6 (via
protected.py), tvOS player/Discover UI tests; code-anti-slop; zero-byte. Report per AGENTS.md §7 with before/after.
