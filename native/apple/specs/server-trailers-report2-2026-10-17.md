Waiting for the tvOS E2E job to get the main lock. It's queued behind the engine-lab run, which has held the lock since 05:01.

The tvOS E2E rerun has started; I'll report when it finishes.

The E2E is queued: it starts as soon as the main lock is free and retries if the lock wait times out. The iPad pass ahead of it has no known duration, so the ETA is unknown; I'm assuming about 20 minutes. I'll report when it completes.

## Done
- FIX 1: opt-out now cancels the Top Shelf download. Files: `AppleTopShelfTrailerFiles.swift` and `AppleTopShelfSnapshot.swift`. I added `AppleTopShelfTrailerDownloads.cancel()`. It cancels the running task and **waits for it to end**. The opt-out branch calls it before deleting the folders, so a download that is part-way through can't recreate the folder or save a file afterwards. New test `optOutCancels`: the first download is held in flight, Top Shelf is turned off, and the test checks that no second download starts and the folder stays gone. Without the fix it fails: the held download recreates the folder and the second one starts.
- FIX 2: the muted hero now takes the trailer audio session. File: `AppleServerTrailerView.swift`. `AppleServerTrailerStage.task(id:)` now guards on `prepareTrailerAudio(pressed: !muted)` before `start`, and stops if that fails. I removed the visionOS-only `onChange(of: trailerRequest)` that also called `prepareTrailerAudio(pressed: true)`: a press changes `restart`, which re-runs the task with `muted == false`, so it was a duplicate.
- FIX 3: a conflicting id now blocks the title+year match. Files: `AppleServerTrailer.swift` and `AppleServerTrailerTests.swift`. The fallback now requires that IMDb and TMDB each agree when both sides have one. I added a "Pinocchio 2022" candidate to `matching()`: with a conflicting IMDb id it returns nil; with a TMDB id but no IMDb id on the candidate it still matches.

## Not done / unclear
- Nothing.

## Gates run
- code-anti-slop pass → removed 1 duplicate path (the visionOS audio `onChange`). The new comments say why, not what. The opt-out test polls in 10 ms steps until the first download has started; that is how it knows a download is in flight before turning Top Shelf off.
- swift test → pass 3484/435 (`--no-parallel`, compile lane, scratch `/Volumes/DevExt/dev/openstream-build/server-trailers-spm`). Before the fixes it was 3483/435 (the worker's report); the new opt-out test is the extra one.
- xcodebuild → recompiled all four edited files (grep count 1 each) in all four builds, BUILD SUCCEEDED each time:
  - tvOS Debug
  - iOS Debug
  - visionOS Debug
  - tvOS Release, no add-ons
- E2E-tvOS, sim F2107E8F, default lane → 3/3 passed, with the same four files recompiled:
  - `testDiscoverHeroPlaysServerTrailer` (9 s)
  - `testDiscoverHeroButtonsAndPagingKeepFocus` (49 s)
  - `testTopShelfShowsRealContentWhenTheAppIconIsFocused` (56 s)

  Nothing ran on OfficePlus and no simulator is left booted.
- zero-byte check → clean

## Diff
My edits are in five files, four of them untracked (new on this branch), so `--stat` only shows `AppleTopShelfSnapshot.swift`:
- `Sources/OpenStreamApple/AppleTopShelfSnapshot.swift` (+1)
- `Sources/OpenStreamApple/AppleTopShelfTrailerFiles.swift` (+9)
- `Sources/OpenStreamApple/AppleServerTrailerView.swift` (+6/−5)
- `Sources/OpenStreamApple/AppleServerTrailer.swift` (+10/−3)
- `Tests/OpenStreamAppleTests/AppleServerTrailerTests.swift` (+37)

The full `git status --short` matches the snapshot at session start: 12 modified, 11 untracked, unchanged. Nothing is committed.

## Notes for the reviewer
- `AppleTopShelfTrailerFiles.swift` `cancel()` waits for the task, so turning Top Shelf off takes as long as the running download takes to stop. For `URLSession.download` that is immediate.
- `AppleServerTrailerView.swift:197`: if the audio session can't be taken, the hero now shows the still instead of the trailer, the same as the YouTube hero (`AppleHomeBillboard.swift:784`).
- The E2E runner in this worktree has no `--derived-data` option. It used the shared `~/Developer/sim-dd-internal` under the lock.
- The E2E had to wait about 1.5 hours for the main lock, behind the other lanes' engine-lab and iOS/iPad runs. One lock wait timed out and was retried.
