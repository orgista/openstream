# Real Apple TV: e2e + REA look at the Apple TV app and Netflix (2026-10-12)

Owner 2026-10-12: connected a real Apple TV to Dev-Mini and OK'd e2e on it plus REA research on the Apple TV app,
Netflix "etc". Device: **OfficePlus**, Apple TV 4K (3rd gen), UDID 00008110-0001486E2189A01E (wireless pairing; use
`xcrun devicectl list devices`). Read AGENTS.md (workspace + native/apple) first, including "Clean up after yourself".

## Signing (created with the owner's OK, 2026-10-12; do not create more)
Apple Development identity "Created via API" in build.keychain-db (unlock as AGENTS.md says, never print the password).
Installed tvOS development profiles, OfficePlus only:
- `OpenStream tvOS Dev OfficePlus 2026-10-12` (com.orgista.openstream)
- `OpenStream tvOS TopShelf Dev OfficePlus 2026-10-12` (com.orgista.openstream.topshelf)
- `Wildcard tvOS Dev OfficePlus 2026-10-12` (UI-test runner)
Pass signing on the xcodebuild command line (manual style, these specifiers); do not edit the pbxproj for it.

## Rules
- No commits; no app code edits unless a real app bug is proven (then stop and report with evidence).
- Gate + `buildlock.sh` for every build/test/device run. Device builds may use DevExt DerivedData.
- Installing our dev build replaces whatever OpenStream copy is on the TV (maybe the owner's TestFlight build 18).
  Snapshot the app data container first (`devicectl device copy from … --domain-type appDataContainer`) to the mini's
  internal disk, restore it after, and say in the report that the owner must reinstall build 18 from TestFlight.
- REA rules (AGENTS.md "How other apps do it"): observe UI only. No DRM or sign-in workarounds, no video frame capture
  of protected playback, no copying assets. Screenshots stay in `verification-artifacts/` (gitignored), never in the
  public repo or anywhere external. If an app needs sign-in or a profile pick, stop at that screen.
- Close everything you open; leave the TV on its Home Screen at the end.

## Work
1. Build and install OpenStream tvOS (Debug, stub-capable) on OfficePlus and run the E2E-tvOS plan there with the
   stub fixtures (`Tests/Fixtures/run-e2e.py` if it supports a device; else xcodebuild test with the plan). Report
   per test vs the sim result (sim: 20 pass / 0 fail / 16 skipped). Include the Top Shelf test.
2. REA pass with a throwaway UI-test method (keep it out of the commit set, or in a clearly named file the lead can
   drop): `XCUIApplication(bundleIdentifier:)` for the Apple TV app (`com.apple.TVWatchList`) and Netflix
   (`com.netflix.Netflix`, if installed), driven with `XCUIRemote`. Capture: home/hero (with dwell over time: when the
   hero auto-advances, how long, how trailers start), focus states on posters and landscape cards (are titles shown
   under posters, on focus or not at all), row headers, See All, title page layout, Top Shelf for each app. Note
   timings and focus behaviour in text. Save to `verification-artifacts/rea-tv-2026-10-12/` with a notes.md.
3. Same capture for OpenStream on the device for side-by-side.
4. Restore the OpenStream data snapshot; Home Screen; close apps.

## Report
Done / Not done / Gates; e2e table; a plain-text REA observations list (what the Apple TV app and Netflix do, with
timings) that the lead can hand to Muse for the comparison write-up.
