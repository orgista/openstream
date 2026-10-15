# Small fixes batch (2026-10-15)

Read native/apple/AGENTS.md first. Nobody else is editing the tree right now; still touch only what each item needs.

## Do
1. Fix Match: an all-digit name ("1917", "1922", "2012") is also searched as a title, not only as an ID/year.
   Unit test: "1917" finds the 2019 film; "tt0111161" and "tmdb-603" still go the ID path.
2. Share setup (Fable lows on 7abd843):
   a. `AppleNetworkShareSetupViews.swift` ~764: Return in the folder-name field saves again on iOS (`.onSubmit`).
   b. `AppleSourcesSettingsView.swift` ~2079: share group headers use the same tvOS uppercase as "Your Sources".
   c. `AppleNetworkShareSetupViews.swift` ~770: the tvOS confirm page shows the server name again.
   d. `AppleSourceStore.swift` ~1753: one unreadable sibling Keychain entry must not block adding a folder on that
      server (`try?` for the sibling lookup); update the rollback test that relied on the throw.
3. Title page (Fable lows on e4409ca):
   a. `AppleDiscoverView.swift` `loadOptionalDetailArtwork`: run only once all providers have answered (not on the
      first partial), so the artwork resolver isn't called when a later provider has the art.
   b. `AppleTitlePageOptionalTasks.swift` ~30: key the episode task on load-finished + count so an empty series
      still records once.
Unit tests where behaviour changes.

## Gates
Serial Swift suite (≥ 3376 passing), iOS + tvOS builds with recompile greps, E2E-iOS (known fail: Live AirPlay) and
E2E-tvOS 20/0, a tvOS screenshot of the share confirm page and the Sources share group. Simulator builds use
`-derivedDataPath $HOME/Developer/sim-dd-internal`; everything through `scripts/mini.sh`/buildlock, foreground.
No commits. Report per AGENTS.md §7.
