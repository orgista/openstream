# Apple TV app behaviours from REA → OpenStream (2026-10-13)

Source: `verification-artifacts/rea-mac-tv-2026-10-12/report.md` (Fable REA of the Mac TV app; read §1–§6 and the
ranked list). Implement behaviours in our own code, in our own words. Never copy Apple code, strings or assets.
Read native/apple/AGENTS.md first. Owner: Apple TV app is the reference for the main GUI and heroes; our design is
approved, so change behaviour and timing, not the look (no new chrome, no explainer text).

## Do (ranked list numbers)
1. Hero auto-advance: about 5 s per image item, advance about 1 s after a hero video ends, no timer while video plays,
   stop on the last item (no wrap unless we already wrap by owner decision; check FEEDBACK/OWNER-TODO), pause while
   covered, off-screen, backgrounded or after play. Reconcile with our existing dwell (229cabe "dwell starts on
   display"); keep whichever owner decision is recorded if it conflicts, and report the conflict.
2. Watched threshold by runtime band instead of one percentage (short / episode / feature lengths); use it for
   Continue Watching removal and next-episode substitution (AppleCompletionPolicy). Keep migration safe: no change to
   stored data, only the rule; unit tests at each band edge.
3. Post-play: up-next card no earlier than ~20 s before the end, 15 s countdown, auto-play chain capped at 3 episodes
   or 2 hours without interaction ("Are you still watching" style stop). Only if our player has a post-play surface
   today; else report what is missing.
4. Reduce Motion, Low Power Mode and the system auto-play-video preference stop hero/background video and trailers.
5. Dedup: an item shown in any of the previous 3 rows is dropped from the next row; no repeats inside a row.
   Reconcile with Netflix 9 diversity (ab56568).
7. Continue Watching merge: new entries append, newer timestamp replaces in place, refresh ~0.5 s after Mark
   Watched / Remove.
9. Focus/scroll: debounce focus-driven work 0.1–0.3 s, skip artwork loads during fast scroll, prefetch about 20 items
   ahead.
Skip 6, 8 and 10 for now (artwork model and hero motion change the approved look; 10 is done in 2c1b8c0).

## Rules
- Each item: smallest change, unit tests for the policy, one commit-sized chunk, notes per item.
- Gate before heavy work; `scripts/mini.sh`; simulator builds use `-derivedDataPath $HOME/Developer/sim-dd-internal`.
- After all items: serial Swift suite, E2E-tvOS on sim F2107E8F and E2E-iOS on the iPhone 18 Pro sim via
  `Tests/Fixtures/run-e2e.py` (expected baseline: tvOS 20/0, iOS 39/2 with AirPlay + Messages known).
- No commits (the lead commits). Clean up after yourself (workspace AGENTS.md). When stuck on a design question,
  ask Muse via the ServerPlus queue is NOT available to you; write the question in your report instead.

## Report
Done / Not done / Gates, per item: what changed (file:line), the rule chosen, tests, and any owner-decision conflict.
