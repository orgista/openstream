# Batch gate: batch-1018a (2026-10-18)

batch-1018a = main cbeee9c plus:
- hero-settle
- settings-narration
- live-narration
- launch-speed
- stability1

The lead will merge flaky-e2e2 into this branch once its review passes. Re-sync and rerun only the affected E2E then.

Reuse the batch-1017b gate harness in /Volumes/DevExt/dev/openstream-build/batch-1017b/: its scripts, e2e.py and
gates/progress.txt layout. Copy it to /Volumes/DevExt/dev/openstream-build/batch-1018a/ and keep its rules:
- per-lane source dir `~/Developer/openstream-build/src-batch-1018a`
- internal `-derivedDataPath ~/Developer/sim-dd-batch1018a`, deleted at the end
- the FIFO default lane; hold the lock only while a stage runs
- compile work goes on the compile lane

Gates:
1. Serial `swift test` on the compile lane.
2. Builds: iOS, tvOS, visionOS and macOS, Debug and Release. Every changed file must show as recompiled. Release has 0
   OPENSTREAM_ADDONS flags.
3. Full E2E-iOS on iOS 27 (73E49263) and on iOS 18.6 (7530ECB2, the owner setup).
   - Back up the owner data first and restore it after, verifying the hashes.
   - Known flakes (`testCrawlLive`, the Messages bubble, `testCrawlSettingsPages`, `testCrawlPlayers`) get one isolated
     rerun. Anything else is a failure to report.
4. Full E2E-tvOS, `--iso-fixtures`, and `testB8DiscoverJank` on 18.6 (hero drawn ≤ 2).
5. Devices:
   - DevTV: a Release + add-ons install, the Top Shelf test and one hero rotation pass.
   - DevPlus: the John Wick 4 UHD ISO, Play → first frame ≤ 6 s.
6. The iPhone feedback checklist walk on iOS 18.6 with the owner setup.
   - The checklist is design/qa/iphone-feedback-checklist.md, plus the 24 narration rows in
     specs/recording-narration-2026-10-17.md.
   - For every row not proven fixed with an iOS 18 screenshot or trace, capture its screen.
   - Mark each row fixed, still broken, or can't-reproduce, with the evidence path. A still-broken row gets a one-line
     cause guess and the file.
   - Write the result into the checklist file. That is the only markdown edit allowed.

Rules:
- Never OfficePlus.
- Never print signing identities.
- No app code changes and no commits. If a gate fails because of a merge, stop that stage and report the failing test
  and the suspected branch.
- Codex runs to 100% of its weekly window.

Report: Done / Not done / Gates (a table) / Checklist summary (counts, plus every still-broken row).

## Lead 04:00: flaky-e2e2 merged into batch-1018a (2f9964f7dd77617eaee6c7f8c0c0d175de26074b). Its files: AppleLiveSystemChrome.swift, AppleMediaSourceViews.swift, the iOS UI tests and run-e2e.py. Re-sync the lane source before the E2E stages (or rerun swift test if it already finished), and drop the known-flake rerun exemption for the four tests: they must pass first time now.
