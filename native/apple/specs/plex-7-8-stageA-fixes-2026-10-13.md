# Plex 7/8 Stage A: review fixes (2026-10-13)

The Stage A diff is uncommitted in the tree (files listed in the Stage A report). Fix every item in
`verification-artifacts/fable-review-stageA-2026-10-13.md` before the lead commits. Read native/apple/AGENTS.md first.
Another job's ISO/caption files (AppleDisc*, AppleSubtitleCueLayer, AetherPlaybackEngine, AppleVideoFitting, run-e2e.py,
UI tests) may be uncommitted too: do not touch or revert them.

## Fix
1. Defect 1: resolve `strongMatchIDs` once per group; batch `record` API on the alias store (apply all unions in
   memory, persist once); `reload` flushes once after the loop and runs the pass after `contentDidChange()` /
   `refreshProgress()`. Add weak/missing-match files to the per-launch dedupe set.
2. Defect 2: `lastActivity(for:)` builds a small map from `[key] + eventKeys` instead of copying the terminals map.
3. Defect 3: `completedEpisodeIDs` stays pure (no writes); record `le:` pairs from `recordIdentityAliases(for:)` with
   the show's resolved id passed in (batched with fix 1). Keep the parity test by recording the pair in the test.
4. Defect 4: a positional `le:` member may belong to only one class; skip it if `classID(of:)` already places it in a
   different `le:` class (trace once). Add a test: two copies of one episode + rename stay separate.
5. Lower-severity: drop invalid members per class instead of discarding the table; singleton-class tombstone parity
   (`keys.count == 1, tombstones[storageKey] != nil → false`); treat an empty id as nil in AppleLogicalItemKey.

## Gates
Serial Swift suite (expect ≥ 3295 passing, 0 failing), tvOS + iOS xcodebuild, E2E-tvOS 20/0 and E2E-iOS 40/1 (AirPlay)
via `Tests/Fixtures/run-e2e.py`, simulator builds with `-derivedDataPath $HOME/Developer/sim-dd-internal`, through
`scripts/mini.sh`/buildlock. No commits. Report Done / Not done / Gates with file:line per fix.
