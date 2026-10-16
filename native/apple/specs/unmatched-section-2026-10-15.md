# Library: Unmatched section + manual match (owner 2026-10-15)

Owner: "We should have an unmatched section where users can match manually see infuse (change metadata)".
Read native/apple/AGENTS.md first (§4.2 REA rules: look, never copy code/assets).

## Research first (short, into design/reference-apps/2026-10-15-unmatched.md)
How Infuse surfaces unmatched files and its "Change Metadata" / "Edit Metadata" flow (where it lives, search by
name/year, ID entry, choose result, artwork, revert to automatic), plus Plex "Fix Match" / "Unmatch" and Jellyfin
"Identify". Use the `rea` MCP on Infuse.app/Plex targets and their public docs.

## Build (stock look, no explainer text, every platform: iOS, iPadOS, macOS, tvOS, visionOS)
1. Library gets an "Unmatched" shelf/section (only when there is at least one): every file/group with no metadata
   match (negative cache: no-match), with the filename-derived title. Provider-unreachable entries don't count.
2. Each item opens the existing Fix Match flow (947fdc1 + "1917" fix): search by name/year or paste an ID, pick a
   result; the durable correction API stores it; the item leaves Unmatched immediately and gets its art.
3. Matched titles also get "Change Metadata" (same flow) and "Use Automatic Match" to revert a manual correction.
4. Optional, if small: multi-select in Unmatched to match several files (e.g. a split movie's parts) to one title.
Unit tests for the section's membership policy and revert.

## Gates
Serial Swift suite, iOS + tvOS builds with recompile greps, the four Release (no add-ons) builds, E2E-iOS and
E2E-tvOS (known: Live AirPlay), screenshots of the Unmatched section on iPhone and Apple TV with fixture files that
don't match. Everything through `scripts/mini.sh`/buildlock, foreground; simulator builds with
`-derivedDataPath $HOME/Developer/sim-dd-internal`. Don't touch files the running Stage B fix or flaky-e2e jobs
own until they're committed (check git status). No commits. Report per AGENTS.md §7.
