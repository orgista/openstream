# Fix the Fable review findings of 2026-10-13 (Codex)

Source: `verification-artifacts/fable-review-2026-10-13.md` (findings 1–7). Read native/apple/AGENTS.md and the workspace
AGENTS.md ("Clean up after yourself", the gate) first.

## Do
Fix all seven findings, each the smallest change with a unit test that fails before and passes after:
1. Media-server Continue Watching resume date = when it was watched (server viewedAt/lastViewedAt), not the snapshot time.
2. Xtream VOD/series resumes eligible for the hero again.
3. Playback trace: write the words the SHIP-CHECKLIST §6 line looks for (requested / matched), and give the Native
   engine's HLS source range from the variant's VIDEO-RANGE when known; adjust the checklist line if the trace wording
   is the better fix. Keep `dynamicRangeMatched=unverified` honest.
4. Top Shelf snapshot in group Caches: republish after a purge (re-check the file exists before the digest guard skips).
5. Turning Top Shelf off also removes the legacy top-level `topshelf-v1.json`.
6. Replace the tautological assertion in `resumePrecedenceAndQuotas` with a real one.
7. Reuse one `DateFormatter` (static) in the recommendation pass.
Keep the owner's decisions (12 s hero timing, Netflix 8 Mix, no new labels, no explainer text).

## Gates
Gate check first; `scripts/mini.sh` under buildlock: serial swift test (baseline 3223 tests / 401 suites, all green),
iOS + tvOS app builds. Simulator builds use `-derivedDataPath $HOME/Developer/sim-dd-internal`.
No commits (the lead commits). Close what you open.

## Report
Per finding: changed file:line, the test, pass/fail. Then the gate results.
