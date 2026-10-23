# Discover fixes from the build-20 full verification (lead, 12:30) — Codex
Guardrails: no git state changes, no uploads, never print credentials/signing identifiers (never cat signing scripts, env.sh, ExportOptions, ~/.asc, owner-build.sh). Owner-data sims via protected.py only; DevPlus/DevTV allowed with state backup/restore as the live-cold job did; OfficePlus never. Heavy jobs via buildlock.sh / buildlock-compile.sh, FOREGROUND, never end your turn with a job running. Keep the mini internal disk >= 15 GB. Read AGENTS.md; code-anti-slop on your diff; openstream-reference-patterns + swiftui-pro skills. Evidence for the bugs: dev-mini /Volumes/DevExt/dev/openstream-build/fullverify-b20/ (REPORT.md, shots/, logs/). Bounded ~2.5 h. Report: Done / Not done / Gates run / Diff / Notes for the reviewer.
1. B1: Discover's Continue Watching must include in-progress network-share/local titles again (AppleDiscoverView.swift:615
   mergedContinueWatching(local: []); the local pass was deleted in 5b699d3 with the catalog lookup). Restore it without any
   add-on/catalog code: use the library/index + playback store. Same items Library shows, progress on the artwork. Test.
2. B2: iPhone Discover/Library hero shows the title wordmark when one exists (AppleDiscoverView.swift:1240 skips the
   upgraded logo; AppleHeroArtworkUpgrade.swift:56 never upgrades local-<digest> ids; :228 marks resolved too early).
   Owner bug 09-29: wordmark, not text, when available. Test + DevPlus screenshot.
3. B3: Discover search: library rows use library metadata (title, poster, kind), duplicates merged, every row opens the
   title page (AppleDiscoverView.swift:1625-1645, resultRow :1883). Tests + DevPlus "wick" screenshot.
4. B12: show metadata titles, not filename capitals ("72 HOURS") wherever the library record has a metadata title.
Gates: serial swift test; iOS + tvOS builds; iOS 18.6 Discover tests via protected.py; DevPlus screenshots of the fixes.

## Round 2 (lead, 14:15): API review says fix first. Uncommitted here. Bounded ~75 min.
Review: /private/tmp/claude-501/-Volumes-Files-Projects/openstream-lead/api-discover-fixes.txt (read it).
1. Revert the continue-watching timestamp line (keep continueWatchingUpdatedAt ?? lastVerified).
2. Search: filter groups by the query BEFORE building records (or cache per contentRevision); resolve each match once per
   result set; no per-keystroke whole-library work on main.
3. Search task id: query + a coalesced revision (no restart storm during a scan); no route redelivery/flicker.
4. listsUnmatched: delete if dead (with its tests) and confirm which rows can no longer appear — list them in the report.
5. Hero upgrade: validate item.imdbID; skip fuzzy filename search unless the item has a library metadata match; no
   second details call when librarySearch already returned the logo.
6. Phone hero fallback casing: test the text-fallback; say whether tvOS/Mac/Vision lockups match.
7. Confirm tmdbConfiguration honours metadataEnabled (metadata off → no TMDB calls) — test.
8. A policy/latch test for heroWordmarksResolved being set only after the lookup.
Gates: serial swift test; iOS + tvOS builds; iOS 18.6 Discover tests via protected.py; DevPlus re-shot of hero + search.
