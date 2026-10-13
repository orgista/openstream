# Fable deep review: OpenStream commits of 2026-10-12

Review every commit on main from `1e91143` through `HEAD` (git log 1e91143^..HEAD) in native/apple: the Netflix /
Apple TV / Plex polish queue, the e2e fixes, Top Shelf, Reset, the Live Pause fix, focus titles and the test fixtures.
Read native/apple/AGENTS.md first.

## Rules
- Read-only: no edits, no builds, no commits. Read the code around each change, not only the diff.
- Report only real defects: crashes, data loss, wrong behaviour, races/main-actor stalls, migrations that can lose
  owner data (playback progress, terminals, outbox, watched history), Release builds pulling in Debug-only code,
  accessibility regressions, tests that no longer assert what they claim. No style nits.
- Each finding: file:line, the commit, a concrete failure scenario (inputs → wrong result), severity, suggested fix in
  one or two sentences. Rank most severe first. Say "no findings" for an area you checked and found clean.

Write the report to `native/apple/verification-artifacts/fable-review-2026-10-12.md`.
