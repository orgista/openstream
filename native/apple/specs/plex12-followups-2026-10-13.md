# Plex 12 follow-ups (Codex, 2026-10-13)
Fix every finding in `verification-artifacts/fable-review-2367a0a-2026-10-13.md` (the Xtream short-EPG refetch on
every zap when evidence is stale; delete the v1 evidence file after a successful v2 write; anything else it lists).
Smallest change + a test that fails before. Never lose manual assignments, favorites, recents or hidden channels.
Gates: serial swift test (baseline 3248/402), iOS + tvOS builds (`-derivedDataPath $HOME/Developer/sim-dd-internal`).
No commits. Report Done / Not done / Gates. Read AGENTS.md first; close what you open.
