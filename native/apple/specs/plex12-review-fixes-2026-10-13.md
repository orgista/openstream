# Fix Fable's Plex 12 review findings (Codex, 2026-10-13)

Source: `verification-artifacts/fable-review-plex12-2026-10-13.md` (findings 1–8). Read AGENTS.md (workspace +
native/apple) first, including "Clean up after yourself" and the gate.

Fix 1–5, 7 and 8, each the smallest change with a test that fails before and passes after. Finding 6 (SD/HD/FHD
variants), lead's decision: when several lineup channels normalize to the same name AND all would resolve to the same
single guide entry, keep name matching for all of them (variants of one channel share a guide); only refuse when they
would resolve to different guide entries. For 2 (unsharded evidence file), keep the on-disk format readable by the
previous build or fall back cleanly. For 5, require matching normalized names when both sides carry a tvg-id.
Never lose manual assignments, favorites, recents or hidden channels.

Gates: `scripts/mini.sh` under buildlock; serial swift test (baseline 3240/402, all green); iOS + tvOS builds with
`-derivedDataPath $HOME/Developer/sim-dd-internal`; E2E-tvOS and E2E-iOS via `Tests/Fixtures/run-e2e.py` (baseline
20/0 and 40/1 AirPlay). No commits. Report: per finding file:line, test, pass/fail; gates.
