# Speed round 2: close the gaps to Plex (DevTV numbers 2026-10-16) + REA actions 5–12

Evidence: design/reference-apps/2026-10-16-plex-vs-openstream-devtv.md (Plex vs us, same harness, DevTV) and
design/reference-apps/2026-10-16-speed-and-metadata-rea.md. Start AFTER the iphone-recording branch is merged
(it changes the title parser and caches the Netflix Top 10 on disk). DevTV only for devices; OfficePlus never tested.

## Fix, in this order, with before/after on DevTV (same AppleTVPlexCompareUITests harness)
1. Title parser at launch: 14 s CPU in the first 7 s; ≈0.9 s rebuilding regular expressions on every call. Compile
   each regex once (static), memoize parse results by path, and parse off the main actor before first paint.
2. Netflix Top 10 parse (≈1.5 s CPU at launch, again at 64 s and 120 s): parse once per downloaded week, keep the
   parsed rows on disk (the recording branch caches the file; make sure the parse is cached too) and never re-parse
   on a timer.
3. Credential scrubbing ≈0.6 s at launch: scrub once at write time, not on every read.
4. Library tab: page is on screen at 43 ms but the old page is removed only at 1.16 s → find what holds the old
   page (transition, heavy body, synchronous work) and make the switch finish < 300 ms p90.
5. Play start: in all 6 plays the first connection drops immediately and a retry starts ~1 s later; one resume took
   10.4 s because the starting segment never reached the player. Find the cause in the engine/AVIO path (connection
   reuse, range request, HLS segment producer) and fix; target Play → first frame < 2 s for files on the share.
6. REA actions 5–9: show any cached size of an image first, colour placeholders (BlurHash from Jellyfin/Plex,
   average colour for TMDB art), server-sized images (Jellyfin maxWidth + tag; Plex transcode sizes), decoded
   thumbnail disk cache, prefetch the next row.
Targets on DevTV: cold launch → first focused element ≤ Plex (2.4 s), library page drawn ≤ 3.0 s, Play → first frame
≤ 2 s (files) / ≤ 3 s resume. Scoped gates: serial swift, tvOS/iOS builds, E2E-tvOS + E2E-iOS for touched areas,
DevTV harness before/after table. code-anti-slop. No commits. Report per AGENTS.md §7.
