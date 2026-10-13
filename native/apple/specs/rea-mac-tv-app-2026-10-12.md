# REA: how Apple's TV app builds its home screen (Mac TV.app + private frameworks), 2026-10-12

Owner: Apple TV app is the reference for OpenStream's main GUI and heroes. The tvOS app is FairPlay-encrypted (off
limits), but the Mac TV app and its frameworks ship unencrypted with macOS, and Mac apps are allowed `rea` targets
(workspace AGENTS.md "How other apps do it"; OpenStream rules in native/apple/AGENTS.md §4.2). Use the `rea` MCP (it
runs on Dev-Mini, which has macOS 27 with `/System/Applications/TV.app`). Private frameworks such as VideosUI,
TVAppServices and AppleMediaServices live in the dyld shared cache; extract what you need on Dev-Mini under
`/Volumes/DevExt/dev/rea/targets/` per the rea rules.

## Rules
- Read-only research. Never copy Apple code, strings, assets or layouts verbatim into OpenStream; describe behaviour
  and constants in your own words. No DRM, account or sign-in workarounds; no network calls to Apple services.
- Nothing leaves the machines (no uploads). Keep outputs out of the public repo: write the report to
  `native/apple/verification-artifacts/rea-mac-tv-2026-10-12/report.md` (gitignored).
- Don't run builds/tests; don't edit OpenStream code. Close anything you open (workspace AGENTS.md "Clean up").
- Prefer the rea CLI/MCP over ad-hoc tools; heavy Ghidra jobs go through `~/Developer/bin/buildlock.sh` on Dev-Mini.

## Questions (answer each with evidence: symbol/class names, selectors, constants, call paths)
1. Hero / billboard ("Up Next"/featured carousel): auto-advance interval, what pauses it (focus, playback, reduced
   motion), when a trailer or motion art starts and stops, how many items, how the item list is picked.
2. Rows/shelves: lockup types (poster vs landscape vs ranked), when a lockup shows its title (always / on focus /
   never), "See All" behaviour, how rows are fetched and paged, row ordering and dedup across rows.
3. Up Next / Continue Watching: ordering rule, next-episode logic after finishing, when an item is removed, the
   progress bar and "x min left" labels.
4. Artwork: which image types are requested per lockup (keys like poster/cover/fullScreenBackground/logo), size/crop
   rules, placeholder behaviour while loading.
5. Top Shelf / system surfaces on Mac (if any) and the shared data model the tvOS Top Shelf would use.
6. Anything else clearly useful for OpenStream's Apple TV look (focus animation timings, parallax, transitions).

## Report
For each question: findings with evidence, confidence, and one line "what OpenStream should do". Then a ranked list
of the 10 changes most worth making in OpenStream, each tied to a finding. Finish with what you could not determine.
