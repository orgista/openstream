# Fable: adversarial check of Plex 7/8 Stage A + build spec (2026-10-13)

Read `design/plex-7-8-design-2026-10-13.md` (your design) and native/apple/AGENTS.md. Read-only on code.

1. Attack Stage A (identity alias table and logical ids, no behaviour change): for every user-state key in §1.2,
   prove by reading the code (file:line) that it survives Stage A unchanged on iOS, tvOS (defaults-backed playback
   storage, see `ApplePlaybackBlobStorage.swift`) and macOS, including iCloud sync/export-import of the config backup
   and older builds reading the same data after a downgrade. List every hole found and fix the design text.
2. Then write `specs/plex-7-8-stageA-build-2026-10-13.md`: a Codex build spec for Stage A only — exact files, types,
   the migration order, unit tests (names + what each asserts), the gate (serial swift test baseline 3223/401, iOS +
   tvOS builds via scripts/mini.sh), "no commits", and a rollback note. Stage A must need none of the owner questions
   in §7.
Write only those two files. No builds, no commits.
