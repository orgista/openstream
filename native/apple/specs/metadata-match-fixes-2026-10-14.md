# Metadata matching: ranked fixes 1–4 (owner 2026-10-14: "meta data fails often")

Source: `design/reference-apps/2026-10-14-metadata-artwork.md` (your own research; read the gap ledger G1–G7 and the
ranked list). Read native/apple/AGENTS.md first. Another job is finishing the iPhone hero (AppleHome*, AppleHero*,
AppleDiscoverView, AppleDiscoverLoadingContent): do not touch those files or revert anything.

## Do (one commit-sized chunk each, unit tests for every policy)
1. Rank 1 / G2: direct typed TMDB / IMDb / TVDB lookup (filename `{tmdb-…}`, `[imdbid-…]`, `tvdbid`, NFO-free) BEFORE
   text search, reusing `AppleTMDBClient` `/find` + ID details. Test: misleading title + correct ID resolves.
2. Rank 2 / G1+G3: filename/folder alternatives with provenance (try the parent folder `Title (Year)` when the
   filename fails), strip recognised release/staging prefixes (`ISO-STAGE-<n>-`, release-group tags like `sharphd-`)
   and edition noise; rank original/localised titles with an ambiguity margin; no-year same-name → prefer the folder
   year, else mark ambiguous rather than picking the first. Test every filename in the report's six misses plus
   negative look-alikes (a real title that starts with a number, e.g. "1917", "2001 A Space Odyssey").
3. Rank 3 / G4: negative cache entries store reason (no-match vs provider-unreachable vs config-missing), provider
   config + parser version; unreachable retries soon with backoff, no-match after a parser/config change
   immediately; positive entries revalidate after 7 days in normal use. Coalesce duplicate in-flight lookups (G5).
4. Rank 4 / G7: "Fix Match" in the title page's existing context/more menu (stock look, no explainer text): search by
   name/year or paste an ID, pick a result; uses the existing durable correction API. iOS, iPadOS, macOS, tvOS.
   Test: correction racing an in-flight automatic lookup wins.

## Gates
Serial Swift suite (≥ 3318 passing), iOS + tvOS builds with recompile greps, E2E-iOS 40/1 (AirPlay) and E2E-tvOS 20/0,
simulator builds with `-derivedDataPath $HOME/Developer/sim-dd-internal`, all through `scripts/mini.sh`/buildlock.
Proof: before/after match count over the e2e library fixtures (how many groups end with metadata). No commits.
Report per AGENTS.md §7.
