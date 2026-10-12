# Verify the 2026-10-12 polish batches on device + tvOS sim (no code changes)

Commits since build 18: 1e91143 (Netflix 1–4: Top Picks inputs, dedup, off-render ranking), 229cabe (Apple TV hero:
one fade, dwell starts on display, Continue Watching see-all), ab56568 (Netflix 7/9/10: varied picks, artwork per
purpose, sized TMDB art), 36da38c (Plex 1–2: safe scans, completion policy). Read native/apple/AGENTS.md first.

Do (Dev-Mini only, through scripts/mini.sh + buildlock.sh, sims muted with -OpenStreamMuteAudio YES):
1. Debug build of current main on the iPhone 16e DevPlus (install with `devicectl device install` — see
   DELIVERIES.md b18 notes) with the owner's existing config on the phone (do not wipe it), and on the Apple TV sim
   B251C620… seeded with scripts/seed-sim.sh (remove the seed afterwards).
2. On each: Discover cold launch → hero appears (time it), rotates, art not dimmed beyond the bottom fade, copy
   readable; Top Picks present, no duplicate titles across Top Picks and the hero; Continue Watching order sane and a
   finished episode shows its next episode (if the data allows), "see all" appears only when capped and opens the
   full list; landscape cards show wide art, no poster-in-frame where a backdrop exists; images sharp, no flicker or
   double load (check the trace log `Library/Caches/openstream-trace.log`); Library tab still lists NAS/local titles
   and a scan does not drop titles. Scroll Discover on tvOS for 30 s — note any hitch.
3. Use the `mobile` MCP element list first, screenshots for visual checks. Save screenshots to
   verification-artifacts/polish-2026-10-12/ (gitignored).

Report (AGENTS.md §7 format): pass / fail per check with evidence; any regression with path:line guess. Do not fix
code, do not commit, do not edit markdown. No uploads, no secrets in output (no URLs with tokens).
