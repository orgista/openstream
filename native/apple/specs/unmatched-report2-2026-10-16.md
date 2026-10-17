I've fixed the one FIX item from the review. The tests and all four builds pass. I still have to run the iOS and tvOS E2E tests on the simulators. Another project holds the simulator lock with a tvOS E2E run, which should finish around 23:05. A watcher will tell me when the lock frees, and I set a fallback check for 23:14.

The E2E run is queued behind another project's iPad test batch, which started at 23:13 and should take about 15 min. I'll be notified when it finishes, with a fallback check at 23:45.

## Done
- **FIX 1 (one read of each cache file at launch)**: `AppleLibraryMetadataResolver.swift:117`, `AppleLocalLibraryStore.swift:129,398,605,676`.
  - The new `cachedLookups(for:)` returns `(metadata, noMatch)` from a single read and decode of each group's cache JSON. A manual match still counts as a match, and only a cached `.noMatch` with no value counts as no match (same rules as before).
  - `publishPersistedIndex` now sets `metadata` and `noMatchIDs` from that one call before the first `contentDidChange()`.
  - The same fold is done in the scan merge (the old `merged`/`missed` double read at :609) and in `useAutomaticMatch`.
  - `cachedMetadata(for:)` and `noMatchGroupIDs(for:)` were removed, since no source file called them anymore. Their 9 test call sites now use `cachedLookups(...).metadata` or `.noMatch`.
- **Unit test**: `AppleLibraryUnmatchedTests.onlyACachedNoMatchCounts` now checks that one `cachedLookups` call returns both the no-match set and the matched title.
- **TMDB empty-search stubs**: kept, as you decided.

## Not done / unclear
- The review's other points are notes with no change required; none were touched.
- No DevTV Top Shelf test: this change doesn't touch Top Shelf.

## Gates run
- **code-anti-slop pass**: removed 2 single-use wrappers (`cachedMetadata`, `noMatchGroupIDs`) and the `refreshNoMatch` helper (inlined), and updated 1 stale test comment that named `cachedMetadata` (`AppleTextlessBackdropPolicyTests.swift:299`).
- **swift test --no-parallel** (`main-merge-spm`, compile lane): pass, 3452 tests / 428 suites, run after the last edit.
- **xcodebuild, generic destinations, compile lane, after the last edit**:
  - Debug: iOS and tvOS succeeded.
  - Release (no add-ons): iOS and tvOS succeeded; `OPENSTREAM_ADDONS` doesn't appear in either Release log.
  - Recompiled `AppleLibraryMetadataResolver.swift` and `AppleLocalLibraryStore.swift` once each in all four builds (grep).
  - No `#if OPENSTREAM_ADDONS` code was touched, so visionOS and macOS Release were not rebuilt.
- **E2E iOS** (E2E-iOS sim `73E49263`): `testUnmatchedShelfMatchesAndReverts`, `testDiscoverRowOpensATitleFromStubsAndComesBack` and `testCrawlLibrary` pass. Both edited files were recompiled.
- **E2E tvOS** (E2E-tvOS sim `F2107E8F`): `testUnmatchedShelfMatchesAndReverts`, `testDiscoverRowOpensATitleFromStubsAndComesBack` and `testLibraryHeroDrawsItsWordmarkOverTheBackdrop` pass. Nothing ran on OfficePlus or DevTV.
- **zero-byte check**: clean.

## Diff
```
 M Apps/OpenStreamTVUITests/AppleTVStubSmokeUITests.swift        | 85 +
 M Apps/OpenStreamiOSUITests/AppleiOSStubSmokeUITests.swift      | 68 +
 M Sources/OpenStreamApple/AppleLibraryFixMatchMenuAction.swift  | 27 +-
 M Sources/OpenStreamApple/AppleLibraryFixMatchView.swift        | 11 +-
 M Sources/OpenStreamApple/AppleLibraryMetadataResolver.swift    | 57 +-
 M Sources/OpenStreamApple/AppleLocalLibraryStore.swift          | 60 +-
 M Sources/OpenStreamApple/AppleMediaSourceViews.swift           |  4 +
 M Tests/Fixtures/run-e2e.py                                     |  3 +
 M Tests/OpenStreamAppleTests/AppleLibraryLessonsTests.swift     |  4 +-
 M Tests/OpenStreamAppleTests/AppleMetadataMatchFixTests.swift   |  6 +-
 M Tests/OpenStreamAppleTests/AppleTextlessBackdropPolicyTests.swift | 4 +-
 ?? (untracked files unchanged from the worker's set; plus AppleLibraryUnmatchedTests.swift edited)
 11 files changed, 303 insertions(+), 26 deletions(-)
```

## Notes for the reviewer
- `AppleLibraryMetadataResolver.swift:131-136`: the schema gate still applies only to a cached value. A no-match entry counts whatever its schema, as in the old `noMatchGroupIDs`.
- `AppleLocalLibraryStore.swift:398`: the single-group re-check after a resolve still reads that one file once. That isn't a double read.
- Edits to 3 existing test files are only the call-site rename.
- Cleanup: my E2E scratch and `/tmp` logs on the mini are deleted. None of my sims are left booted; another project's iPad job holds the lock now. Nothing committed.

The early sim-lock watcher hit its time limit and was stopped. Nothing depends on it: I queued the E2E run through `buildlock.sh` instead, and it already passed. The report above stands.
