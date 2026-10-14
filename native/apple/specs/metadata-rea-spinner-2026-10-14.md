# Metadata/artwork matching like Stremio, Plex, Jellyfin, Infuse + the double spinner (owner 2026-10-14)

Owner (build 18): "two loading circles if you click content … a loading circle on top of a loading circle … the speed
can be improved and the meta data fails often have no meta data we need a better catch/fix … see how stremio, plex,
jellyfin, infuse handle meta data art work as they often have the meta data correct". Read native/apple/AGENTS.md
(§4.2 REA rules) first.

## Part A — research (no app code edits)
How each app identifies a title and gets metadata + artwork, especially for messy local/network filenames:
filename parsing (year, SxxEyy, editions, release-group noise, folders, ISO/BDMV), NFO/sidecar files, embedded tags,
provider order (TMDB, TVDB, IMDb/OMDb, Fanart.tv, own servers), ID lookups vs text search, confidence/thresholds, retries,
caching, fallback art when nothing matches, manual "fix match", and what they show while loading.
- Stremio and Jellyfin are open source: read stremio-core / stremio-web and the Jellyfin server (naming parser
  `Emby.Naming`, providers, `ItemResolveArgs`), cloned under `/Volumes/DevExt/dev/rea/targets/src/` on Dev-Mini.
- Plex: the bundled web client + public docs (`rea` MCP, AGENTS.md §4.2). Infuse: `Localizable.strings`, symbols,
  public docs (Infuse ISO/naming guides). Never copy code; describe behaviour.
- Then read OUR pipeline (AppleLibraryMetadataResolver, AppleLocalLibraryStore, title parsing, TMDB client, artwork
  cache) and list concretely where we lose matches. Sample real failures: list our library's files that end with no
  metadata (use the e2e fixtures or the trace; do not upload anything).
Write `design/reference-apps/2026-10-14-metadata-artwork.md`: per-app behaviour + evidence location, our gaps, and a
ranked fix list (each tied to a finding, with expected effect).

## Part B — double spinner + slow title open (diagnosis only)
Find why opening a title shows a spinner on top of a spinner (current HEAD vs build 18 = dc5e24e) and what makes the
title page slow to show. Code reading + the interaction trace / an xctrace on the iOS sim is fine but ONLY after the
build lock is free (another job is testing); no app code edits. Add a section to the same design doc: cause with
path:line, the fix, and the timing budget (first frame, metadata, art).

No commits. Clean up. Report per AGENTS.md §7.
