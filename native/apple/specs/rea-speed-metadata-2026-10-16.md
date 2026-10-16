# REA round 2: why Plex feels fast, and how the best apps get metadata right (owner 2026-10-16)

Owner: "We still might need REA on meta data and overall speed of apps I think we might be the slowest Plex is pretty
fast". Read first: design/reference-apps/2026-10-11-plex-backend.md, 2026-10-11-plex-lessons-for-openstream.md,
2026-10-14-metadata-artwork.md (do not repeat them; go deeper). Our own numbers: specs/atv-slowness-report-2026-10-16.md
(DevTV: Home 0.2 s, hero art 1.7 s, library 2.3 s, title open ≈1.1 s + XCUITest overhead) and
specs/iphone-recording-1015-2026-10-16.md (Top 10 without art, "Open Season 3" parsed as a show, 4 s black launch).

Tools: the `rea` MCP on Dev-Mini (targets in /Volumes/DevExt/dev/rea/targets: Plex.app, Plex Media Server.app,
Infuse.app, apk/), plus open source you may read: Jellyfin server + Swiftfin (Swift Jellyfin client), Kodi's
video filename rules, guessit (Python filename parser), Stremio Cinemeta. Rules: native/apple/AGENTS.md §4.2 and the
root AGENTS.md REA section: never copy code or assets, no DRM/sign-in bypass, never upload targets, notes only.
Read-only: edit nothing except the output file.

## Questions to answer, each with evidence (symbol/file names, request shapes, timings) and "what we should do"
1. **Speed:** what makes Plex/Infuse feel instant? Local database/cache of library + metadata (format, when it's
   read, before first frame?), image pipeline (server-side resized images, sizes requested per screen, memory/disk
   caches, prefetch, decode off main), list virtualization and paging, what loads at launch vs lazily, startup work
   ordering, placeholder strategy (never a blank/grey card), connection reuse.
2. **Metadata matching:** filename parsing rules (season/episode markers vs titles that contain "Season", years,
   editions, multi-part, "Open Season 3 (2010)"-type cases), lookup order (IDs in NFO/filenames → TMDB/TVDB/IMDb
   search with year → fuzzy), confidence thresholds, what they do with unmatched items, artwork choice (poster,
   backdrop, logo/wordmark, Top 10/chart art), caching and refresh policy.
3. **Top 10 / chart rows:** where Plex/Netflix/TV app get chart artwork; why ours shows text-only cards.
4. Compare each to OpenStream's current code (file:line) and rank changes by user-visible speed/quality gain per
   effort. Mark what needs the AetherEngine or a server vs app-only.
Output: design/reference-apps/2026-10-16-speed-and-metadata-rea.md (under 400 lines, ranked action list at top).
