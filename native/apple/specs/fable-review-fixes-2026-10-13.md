# Fix the Fable review findings (2026-10-13)

Source: `verification-artifacts/fable-review-2026-10-12.md` (15 findings, ranked). Read it and native/apple/AGENTS.md.

## Rules
- For each finding: first confirm it in the code (or with a failing unit test). If it is not real, say why and skip.
- Fix confirmed ones with the smallest change and a regression test. Owner data safety first: no change may lose or
  rewrite stored progress, watched history, terminals, outbox or match records; migrations must be read-compatible.
- #1 (Application Support on Apple TV) and #2 (artwork flash + 200 ms delay) are HIGH: do them first.
- #3–#8 MEDIUM: fix each confirmed one. #9–#15 LOW: fix when the fix is small and safe; else note why not.
- Gate before heavy work, `scripts/mini.sh`, simulator builds with `-derivedDataPath $HOME/Developer/sim-dd-internal`.
  Mac mini disk is tight (~16 GB free): delete your own scratch as you go.
- After all fixes: serial Swift suite, E2E-tvOS (sim F2107E8F) and E2E-iOS (iPhone 18 Pro sim) via
  `Tests/Fixtures/run-e2e.py` (baseline tvOS 20/0, iOS 40/1 AirPlay known).
- No commits (lead commits). Clean up after yourself (workspace AGENTS.md).

## Report
Per finding: confirmed? / fixed (file:line, test) / skipped (why). Then Gates, Diff stat.
