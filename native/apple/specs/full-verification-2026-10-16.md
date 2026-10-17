# Full verification: every app, every function, before "ship 19" (owner 2026-10-16)

Owner: "after all builds are done todolist is empty we need to queue e2e all apps and all functions cause I keep
catching a ton of bugs and idk you failed to do that so we need more robust ux/ui testing and code testing".
Why we missed them: the E2E crawls prove a screen OPENS and an element EXISTS; they don't judge what the user SEES
(grey text-only Top 10 cards, YouTube overlays, "Open" shows, Play Disc on a Blu-ray, a 0-channel toast, a 4 s black
launch) or whether data is right. This pass fixes the method, not just the bugs.

Runs when OWNER-TODO's queue is empty (last item before the release-candidate run). Lead splits it into lanes.

## 1. Feature inventory (the test matrix)
Generate `design/qa/feature-matrix.md` from the code (every screen, button, menu, setting, source type, playback
path, extension) × platform (iPhone iOS 18 + 27, iPad, Apple TV, Vision Pro, Mac, Watch, Widgets, Top Shelf, Share
extension, iMessage app, Live Activity). Each cell: how it is tested (unit / E2E / device / visual) or "untested".
Every "untested" cell gets a test or a written reason.

## 2. Real-data runs, not just stubs
E2E with the owner's setup (DevPlus backup, DevTV restore hook) on: iOS 18.6 sim, iOS 27 sim, iPad sim, DevPlus,
DevTV, Vision Pro sim, Mac. Real ServerPlus share (472+ titles, ISOs, multi-part, shows), Jellyfin/Rill
(stream.gallardo.dev), Plex, IPTV with the owner's provider, add-ons. Stub runs stay for determinism.

## 3. "What the user sees" checks (new)
- Screenshot every screen state in the crawl (top, scrolled, focused, loading, error, empty) on every platform.
- A visual judge pass: Fable reviews each screenshot set against a checklist — no grey/text-only art cards where
  art should exist, no third-party overlays (YouTube UI), no placeholder titles ("Open"), no clipped/overlapping
  text, no double spinners, no blank screens > 1 s, no debug HUDs, correct buttons for the media type (Blu-ray: no
  Play Disc), wordmarks/heroes present, consistent spacing with the Apple TV app reference.
- Data assertions in E2E: Top 10 cards have artwork; Library shows have real titles; title pages have year,
  runtime, overview, art; Live list matches the import count; no toast loops.
- Timing budgets enforced in tests (from the trace): launch → first content < 1.5 s (DevPlus), tab switch < 300 ms,
  title open < 1 s, Play → first frame < 3 s (files) / < 12 s (UHD disc), no main-thread hitch > 250 ms.

## 4. Owner bug regression suite
Every owner-reported bug since build 16 (OWNER-TODO checked items + recordings) gets a named regression test.

## 5. Code testing
Coverage report per module (xccov); target: every Source file ≥ 1 test touching it; risky stores (playback
progress, library index, version cache, iCloud sync, setup import) ≥ 80% line coverage. Thread Sanitizer +
Address Sanitizer runs of the unit suite; strict concurrency warnings = 0 new.

## 6. Exploratory "user" crawl
A worker drives each app on a device/sim like a user for 30 min per platform with the mobile MCP (no script),
recording every oddity with a screenshot; findings → bugs → fixes → the regression suite.

Gate to ship: matrix has no unexplained untested cell; visual judge: zero P1; all regression tests green on every
platform; timing budgets met on DevPlus + DevTV; sanitizers clean. Then the release-candidate run, then "ship 19".
