# Make the E2E plans runnable: fixtures + stale tests (2026-10-12)

Context: the sim runs in `verification-artifacts/e2e-2026-10-12/sim-ios-tests.json` and `sim-tvos-tests.json`
(iOS 18/23/57, tvOS 4/16/16) found no app bug. Every failure is a missing fixture or a stale test. Fix the test
side so the E2E-iOS and E2E-tvOS plans pass on simulators. Read AGENTS.md first.

## Rules
- Edit only test code, test plans and fixtures (`Apps/*UITests`, `Apps/TestPlans`, `Tests/Fixtures`), plus
  Debug-only routing (`#if DEBUG`) if a Debug route needs a fixture-aware fallback. No Release code changes. If a
  failure turns out to be a real app bug, stop and report it with evidence; don't fix the app.
- Never weaken a test to pass: keep what each test asserts, fix how it gets there (fixtures, scrolling, locators).
  A test whose premise the owner removed (Live has no navigation title, owner item 9) gets updated to the current
  design, with a comment naming the decision.
- No real hostnames, LAN addresses, credentials or owner data in fixtures (they ship in the public source export).
  Use `fixture.example` style hosts served by the stub network.
- Do not commit. The lead reviews and commits.
- Dev-Mini only, via `scripts/mini.sh` / `buildlock.sh`; gate first (AGENTS.md). Simulator builds use
  `-derivedDataPath $HOME/Developer/sim-dd-internal` (DevExt builds hang in dyld on a simulator).
  Snapshot and restore sim app + app-group data as before. Mute audio.

## Work
1. Stub catalog: make the saved stub source and the checked-in fixture agree (`films.json` vs `top.json`).
2. Add a series fixture (one show, 2 seasons, a few episodes, stills/artwork placeholders from the stub server) so
   the detail/episodes/download/player Debug routes (`AppleDiscoverView.swift:1462` picks a series) find an item.
3. Add a stub IPTV source: a tiny M3U + XMLTV served by the stub network, with a channel named CBS, so the Live,
   guide and channel tests have their lineup without `OPENSTREAM_TEST_M3U`.
4. A searchable catalog fixture with the title the search test expects (or change the test to a fixture title).
5. Seed one in-progress Continue Watching item for the widget and Top Shelf tests (Debug seeding path, not
   by playing to completion).
6. A local/NAS library fixture for the Library hero test if a stub path exists; else report what's needed.
7. Stale tests: Settings tests scroll to their rows before waiting; the crawler scrolls a control fully clear of
   the tab bar before tapping and accepts "Refresh" with identical content (no visible change needed when the
   reload completes); Discover crawler checks hittability after scrolling; Messages share test locator.
8. Re-run both plans on sims (iOS sim + tvOS sim F2107E8F-87F4-4685-9C91-84B56D78EC6F), then the serial Swift suite.

## Report
Done / Not done / Gates, per-test before→after table, the diff stat, and anything that looked like an app bug.
Save results to `verification-artifacts/e2e-2026-10-12/fixtures-*.json`.
