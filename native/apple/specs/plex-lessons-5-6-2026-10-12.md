# Plex lessons 5–6: owned filename parsing, durable match corrections (2026-10-12)

Source: design/reference-apps/2026-10-11-plex-lessons-for-openstream.md, ranked change list items 5 and 6 (areas 2,
3). Follows 36da38c (items 1–2). Claude picked these under the keep-building rule. Read native/apple/AGENTS.md and
the report.

5. Filename/folder parsing as an owned policy with uncertainty: episode ranges (S01E01-E02), air-date episodes,
   extras roles (trailer/featurette/behind the scenes/deleted scenes/sample), multipart (cd1/part1) vs alternate
   versions (1080p/4K/edition) — parts chain, versions stay alternatives; a confidence value; ambiguous playable files
   stay listed and are never assigned a guessed episode from copy order. Fixture tests for every named format.
6. Match evidence and manual correction that survive rescans: explicit IDs and the chosen candidate are stored per
   library title, a manual override wins over automatic matching after a rescan or cache-version change, progress
   is kept. Tests: duplicate titles, year mismatch, wrong first match corrected, cache-version change.
   No new UI in this step unless a correction entry point already exists; if none exists, add the store/policy only
   and note it.

Out: items 3, 4, 7–12. Item ids (AppleLibraryItem.id = sourceID:relativePath) must not change. Rules: as
specs/todo-finish-2026-10-09.md "Rules", except **do not commit** (the lead commits). Dev-Mini via scripts/mini.sh +
buildlock.sh; full Swift suite green >= 3082 plus new tests (touch edited files first); iOS + tvOS builds. No uploads,
no secrets, no git stash/checkout/reset, don't touch native/google-tv or AppleSMBRangeServer.swift. One OWNER-TODO.md
Done line per item with evidence. End with done / not done / next.
