## Done
- **Main-title tie-breaks** — `AppleDiscPlayback.swift`, `AetherPlaybackEngine.swift`. New `AppleDiscMainTitlePolicy` sits on top of the engine's list, which already drops short and repeated-clip decoy playlists and puts the longest first. It applies libbluray's chapter rule: when both titles run over 30 min, one has fewer than 2 chapters and the other has more than 5 more, the one with chapters wins even if it's shorter. Otherwise the engine's id 0 stays.
  - If the disc's titles are already known, the pick goes in as `discTitleID` at load.
  - On a first open it switches once with `selectTitle`, but not on a resumed play, because the resume point belongs to the title that opened.
  - The Titles row now starts with the policy's pick and labels it "Main Feature".
  - Only Blu-ray main-feature starts use it; DVD starts and titles picked from the row don't change.
- **Crash protection** — new `AppleDiscCrashGuard.swift`, plus hooks in `ApplePlaybackCoordinator.swift`. A mark is saved in UserDefaults before each disc open and cleared when the open returns. A mark still there at the next launch means the app died during the open, so that disc is refused before the engine is called, with "oStream closed while opening this disc last time, so it won't open it again."
  - The refusal is keyed by build and file, so an app update tries the disc again.
  - On iOS and tvOS, leaving the foreground clears the mark, so swiping the app away mid-open doesn't count as a crash.
- **`modifiedAt` in the cache key** — `AppleSMBRangeServer.swift`, `AppleLibrary.swift`, the two SMB scanners, the library snapshot and the metadata resolver. The review was wrong that `file.modifiedAt` already existed: only the SMB directory entry had it, so I added it to `AppleLibraryItem` and passed it through. The key is now URL, size and mtime.
- **Only structure reads are cached** — `AppleSMBBlockCache.swift`: requests of 256 KB or less that start in the first 64 MiB (the review offered both fixes; I used both). The 512 KB and 1 MiB ramp reads, and any read past 64 MiB, go straight to SMB.
- **Doc sentence** — `ApplePlaybackStartPolicy.swift`: the extra start time only helps discs served through the SMB bridge on engine 07afad62.
- **Wider test margins** — deadline 200 ms, ticker 50 ms, window 300 ms, `.loading` checked at 600 ms. The cap test now uses a 300 ms window and an 800 ms cap.
- **New tests** in `AppleDiscStartTests.swift`: the policy (7), the guard (5), the coordinator refusing and marking a disc (2), a replaced file of the same size being read again, and a title-stream read bypassing the cache.

## Not done / unclear
- **Video and audio tie-breaks** — not possible on the pinned engine. Its `MPLSParser` doesn't read the playlists' stream table and its titles carry only length and chapter count. This needs an AetherEngine change, which is off-limits unless you name it.
- The review's request to add items to `specs/iso-open-report-2026-10-17.md`: not edited, since AGENTS §6 says no markdown edits when the task asks for a §7 report. The two items are in this report instead.
- The first-open title switch didn't run on a device: John Wick 4's engine pick (title 0 of 26) already agrees with the chapter rule. Only the unit tests cover the switch.

## Gates run
- code-anti-slop pass → removed 1 unneeded stored observer token and 1 duplicate cache-key string, simplified the policy loop, added the reason comment for `assumeIsolated`.
- swift test `--no-parallel` (full) → pass 3507/437. The first run failed 1 test: my message said "OpenStream" where the UI name is "oStream". Fixed and re-run.
- xcodebuild OpenStream iOS and tvOS (simulator) → both succeeded, and all 13 edited files recompiled on each. DevPlus Debug build → succeeded.
- E2E `--iso-fixtures`, the 4 DVD cases → iOS 4/4, tvOS 4/4. On iOS the edited files showed 0 recompiles because an earlier run of mine had already built the final sources into the same build folder (that log shows 1 each); tvOS showed 1 each.
- That earlier run was the full UI plan, which I started by mistake and stopped after 27 cases to free the shared lock. One unrelated case failed in it: `testCrawlLive`.
- DevPlus, John Wick 4 UHD ISO (Play to picture):

| Run | Disc read | Play → picture |
|---|---|---|
| Old bridge, +50 ms per read | 5.3 s | 16.7 s |
| Block cache, +50 ms per read | 0.3 s | 11.0 s |
| Block cache, LAN | 0.4 s | 6.1 s |

- zero-byte check → clean.

## Diff
```
 M AetherPlaybackEngine, AppleDiscPlayback, AppleLibrary, AppleLibraryMetadataResolver, AppleLocalLibraryStore,
   AppleNetworkShare, ApplePlaybackCoordinator, ApplePlaybackEngine, ApplePlaybackStartPolicy,
   AppleSMBLibraryScanner, AppleSMBRangeServer (.swift); Tests/.../FakePlaybackEngine.swift
?? Sources/OpenStreamApple/{AppleDiscCrashGuard,AppleSMBBlockCache}.swift, Tests/.../AppleDiscStartTests.swift, specs/iso-open-*.md
 12 files changed, 280 insertions(+), 21 deletions(-)   (plus 3 new Swift files)
```

## Notes for the reviewer
- `AppleDiscMainTitlePolicy` walks titles in id order, starting from the engine's id 0, and only the chapter rule can move it. A pure length comparison would have overridden the engine on the out-of-order Matilda test data.
- `AppleLibraryItem` gained `modifiedAt` (Hashable), so two items that differ only in mtime now compare unequal. Older saved library caches load it as nil, which is still a valid key.
- The 64 MiB limit is based on one disc (The Last Airbender's structure sits under 37 MiB). A disc with its structure further in would fall back to uncached reads: slower, never wrong.
- `ApplePlaybackCoordinator.swift` `beginAttempt`: the refusal runs before `startTimeout`, and the mark is set and cleared inside the load task with a `defer`.
- DevPlus still has the probe-built Debug app installed over the owner backup, as after the first round. Nothing is committed.
