# Rebase three parked branches onto main (2026-10-19)

Three reviewed-and-committed branches could not be merged into batch-1018b because they conflict with newer main:
- unit-determinism dcdae27 (AppleClock/ManualClock; the unit suite deterministic in parallel and serial)
- gui-r4a ebd4f31 (tvOS hero cycle/crossfade + title-page clean-up, round 4 S3)
- live-r4 4606aaf (wrap-around zapping restored, coalescer races fixed, iOS pending-channel banner)
Conflict seen first: unit-determinism vs batch-1018b in Sources/OpenStreamApple/AppleChannelHealthProbe.swift and
Tests/OpenStreamAppleTests/AppleChannelHealthTests.swift.

Task, in this worktree (branch rebase-parked from main b8ed703), one branch at a time, each as its own commit-sized
change (do NOT commit; keep the three changes separable: apply branch A, run its gate, record; then B; then C):
1. `git diff <merge-base> <branch> | git apply --3way` (or cherry-pick the diff by hand where --3way leaves
   markers); resolve conflicts preserving BOTH the branch's intent and main's newer behaviour. Never drop a main
   change to make a branch apply. If a conflict is a real design clash, stop that branch and report it.
2. After each branch: `swift test --no-parallel` (compile lane) full count; iOS + tvOS builds; for live-r4 the
   iOS 18.6 owner-sim Live tests (testCrawlLive) once; for gui-r4a the tvOS E2E once (F2107E8F…); for
   unit-determinism the suite twice, parallel and serial.
3. Rules: specs/stabilize-2026-10-18.md (no new behaviour beyond the branches; shared views must not change other
   platforms; no test loosened). Builds/tests/sims only on Dev-Mini via scripts/mini.sh
   (`OPENSTREAM_MINI_DEST='~/Developer/openstream-build/lanes/rebase-parked'`); FIFO locks, never kill other jobs
   (an owner build and another lane may be running). code-anti-slop on the final diff. Zero-byte check. No commits.
Report per branch: conflicts resolved (file:line + how), gate counts and log paths, `git diff --stat` for that
branch's hunks.
