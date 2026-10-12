# Plex lessons 3–4: progress sync that converges, reliable remote progress (2026-10-12)

Source: design/reference-apps/2026-10-11-plex-lessons-for-openstream.md, ranked change list items 3 and 4 (areas 4,
10). Follows 36da38c and 5d89c35. Claude picked these under the keep-building rule; they touch saved user state, so
be conservative. Read native/apple/AGENTS.md and the report.

3. Reconcile progress, completion and reset during iCloud/backup sync: timestamped terminal events (completed,
   reset/unwatched, removed-from-CW) so older partial progress never resurrects a completed or reset title, while a
   later real rewatch still wins. Existing stores/format must keep reading old data (migration with defaults; never
   drop existing progress). Tests: old backup restored over newer state, offline device rejoining, completion then
   rewind, rewatch, unwatch, cloud trimming — all converge deterministically without erasing newer activity.
4. Deliver remote progress to Jellyfin/Plex/Emby reliably: an ordered, coalesced per-item outbox with bounded retry
   and backoff, persisted across relaunch; stop/scrobble failures retried, not dropped; back-to-back episodes keep
   order and final state; no duplicate play counts; never overwrite newer local progress with a stale server offset.
   Tests with a fake server client (no network).

Out: items 7–12, UI changes/new UI text. Rules: as specs/todo-finish-2026-10-09.md "Rules", except **do not commit**
(the lead commits). Dev-Mini via scripts/mini.sh + buildlock.sh; full Swift suite green >= 3095 plus new tests (touch
edited files first; run serially if captions tests time out in parallel); iOS + tvOS builds. Never print server URLs,
tokens or user names. No uploads, no git stash/checkout/reset, don't touch native/google-tv or
AppleSMBRangeServer.swift. One OWNER-TODO.md Done line per item with evidence. End with done / not done / next, and
list every persisted format you changed with its migration.
