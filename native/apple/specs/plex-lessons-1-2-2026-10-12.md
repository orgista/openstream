# Plex lessons 1–2: safe scans, one completion policy (2026-10-12)

Source: design/reference-apps/2026-10-11-plex-lessons-for-openstream.md, "ranked change list" items 1 and 2 and
their areas (1, 4, 9) in "Findings". Owner: "Plex … the longest in the game, so what can we learn from them as far as
how our app works." Claude picked these under the keep-building rule. Read native/apple/AGENTS.md and the report.

1. Safe scans that retain offline content (areas 1, 9): a scan produces a complete / partial / failed result per
   source scope; only a complete scope may delete records; partial and failed keep what was there (marked stale, still
   listed); unreachable roots and denied child folders never delete; bounded SMB traversal with cancellation; a
   per-source "last successful scan" stamp. Meet the report's acceptance list with pure tests (fixtures, no network):
   >5,000 local files, >10,000 SMB entries (synthetic), denied child, unreachable root, cancellation, and a genuinely
   deleted file that is removed after a complete scan.
2. One completion policy (area 4): provider watched flags stay authoritative; local completion, last activity,
   next-episode (successor) availability and Continue Watching suppression become one explicit policy type used by
   Continue Watching / Up Next. Acceptance from the report: a completed episode save still offers the available next
   episode; no progress bar resumes a completed episode; a finished series leaves CW; tests for each.

Out: items 3–12, UI changes, any new UI text. Do not touch AppleSMBRangeServer.swift.
Rules: as specs/todo-finish-2026-10-09.md "Rules", except **do not commit** (the lead commits). Dev-Mini via
scripts/mini.sh + buildlock.sh; full Swift suite green >= 3068 plus new tests (touch edited files first); build tvOS
and iOS; nothing heavy on the main actor. No uploads, no secrets, no git stash/checkout/reset, don't touch
native/google-tv. One OWNER-TODO.md Done line per item with evidence. End with done / not done / next.
