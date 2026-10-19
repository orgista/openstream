# ISO playback like a regular player: time, duration, seek (checklist row 73, owner 2026-10-18 19:25)

Owner: "ISOs don't have menus, would like time to play like in a regular player." Branch `iso-player`
(worktree OpenStream-lanes/iso-player) from main 86bb4d9. Parent plan: specs/stabilize-2026-10-18.md. One row.

## What to establish first (diagnose, then fix)
1. On the owner-profile iOS 18.6 sim `7530ECB2-CE38-4BC6-B7E6-D4B3BEDDF48D` (wrapped in
   `python3 /Volumes/DevExt/dev/openstream-build/batch-1018a/protected.py <sim> <cmd…>`, `-OpenStreamMuteAudio YES`)
   and/or the ISO fixtures (`Tests/Fixtures`, `run-e2e.py --iso-fixtures`): play an ISO and screenshot the
   player transport 5 s in. Does it show elapsed / remaining / duration and a scrub bar? Can you seek? Read the trace
   (`disc …`, `duration`, `seekable`) lines. The expectation is that since f299aff ("discs skip the probe", to stop
   reading the whole ISO twice) the player has no duration for a disc, so the timeline is empty or disabled.
2. REA (per specs/stabilize-2026-10-18.md §REA): how Infuse plays an ISO — straight to the main title, with the
   regular time bar and chapter seek. `Infuse.app` strings / `Infuse-arm64` via the `rea` MCP: look for how it gets
   the title duration (libbluray/libdvdread title info, not a full read). ≤ 15 lines in the report.

## Fix (smallest)
- Play on an ISO goes straight to the main title (no menu step, no "Titles" sheet on the phone unless the user
  asks for it from the player), with the regular transport: elapsed, duration, scrub, ±10 s, chapter skip if the
  engine exposes chapters.
- Duration/seekable range come from the engine's title info after open (the engine fork exposes the main title
  length; AetherEngine / the HTTP disc reader in AppleSMBRangeServer — read the engine job notes in
  specs/engine-rebase-7.36-2026-10-15.md and OWNER-TODO) — never from a second full read of the ISO.
- Keep Play → first frame ≤ 6 s on DevPlus for John Wick 4 UHD (iso-open d627387), 0 `startup timed out`.
- tvOS: same transport behaviour; the tvOS Titles list (tv-disc-shelf) stays.

## Proof
- iOS 18.6 owner sim: screenshot of the transport with time + duration while an ISO plays; a seek to +10 min
  shown in the trace; ISO fixtures suite (`--iso-fixtures`) green.
- DevPlus (device lane, after the batch-1018c gate frees it): John Wick 4 UHD, Play → first frame ≤ 6 s, time bar
  present, one seek. Never OfficePlus.
- `swift test` full count on the compile lane; iOS + tvOS builds; code-anti-slop; zero-byte check.
- Builds/sims only on Dev-Mini via `scripts/mini.sh` (`OPENSTREAM_MINI_DEST='~/Developer/openstream-build/lanes/iso-player'`,
  `OPENSTREAM_MINI_LANE=compile` for swift test). FIFO locks; don't kill other jobs. No commit; no git
  stash/checkout/reset; nothing outside the disc playback path.
Report: what the transport showed before (screenshot), cause, change (file:line), proof paths, gates, `git status --short`.

## Lead answer (2026-10-18 19:50) to the worker's open question, and the continuation
The first run died mid-way (Codex session error) with 3 files changed: AetherPlaybackEngine.swift (adapter
forwards disc chapters; explicit main-title ID takes the regular disc path and publishes duration),
AppleMediaPlaybackView.swift (chapter menu uses the validated chapter-seek action), a real-ISO regression test in
ApplePlaybackEngineFixtureTests.swift. Keep that work; continue from the worktree state.
- **Default Play on an ISO goes straight to the main title** with the explicit main-title ID, so the regular disc
  path publishes duration/seekable range. The DVD navigator (menu) is not the default on any platform; a menu
  entry may stay reachable from the player's menu if it already exists, nothing new.
- Tests that assert menu-first Play (1881b4b era) are updated to the new rule, quoting the owner in the test's
  comment: owner 2026-10-18 "ISOs don't have menus, would like time to play like in a regular player."
- Then the proofs in the spec (sim screenshot of the transport with time + duration, seek in the trace, ISO
  fixtures green, DevPlus John Wick 4 ≤ 6 s with the time bar once the device lane is free), gates, report.

## CORRECTION (owner 2026-10-18 22:05) — this replaces the "straight to the main title" reading above
Owner: "my ISOs are 1-1 disc copies, I want the app to act like a Blu-ray player and show the disc menus."
So the goal is the opposite of the earlier reading: **Play on a disc image opens the disc's menu, like a player**,
and the running time / duration / seek bar works once a title plays from that menu. Do NOT make Play skip the menu.
Undo any edit from the previous runs that changes the default Play start away from `.menu` when `discOffersMenu`
(AppleDiscoverView.swift:3280) or touches the "menu-first" tests; keep the useful parts (chapter forwarding, the
real-ISO regression test, duration publishing).

What is true today (read before coding): DVD menus exist (IFO/VM/SPU menu player in the engine fork;
AppleDiscMenuOverlay/Session/Input/Control; `discPlayStart = discOffersMenu ? .menu : .mainTitle`). Blu-ray/UHD
menus (HDMV/BD-J) are not supported — decided in specs/tv-disc-shelf-2026-10-15.md ("no menu promise on Blu-ray")
— so the owner's UHD copies (John Wick 4 UHD, Matilda UHD) go straight to the main title with no menu. That is
what the owner is seeing. The owner now wants menus; the lead is asking the owner about Blu-ray scope.

Do now, in this order:
1. **Time bar in the menu flow (the bug the first run found):** when a title starts from the DVD navigator, the
   engine path returns before publishing the selected title's duration/seekable range, so the transport shows no
   time. Fix that in the navigator path (publish title metadata when the navigator enters a title; chapters too).
   Proof: a DVD ISO fixture (Tests/Fixtures; if none has a menu, say so and use the smallest real DVD ISO the mini
   has access to under /Volumes/DevExt — never upload anything) on the iOS 18.6 owner sim: menu shown → pick Play →
   transport shows elapsed/duration, a +10 min seek lands (trace), chapter skip works.
2. **If a DVD ISO shows no menu on the owner's build**, find why (is `discOffersMenu` false for his files? trace
   lines) — that is also part of "ISOs don't have menus".
3. **Blu-ray menu feasibility, read-only, ≤ 20 lines in the report:** what the engine fork would need to render
   HDMV (IG/PG overlay) menus with libbluray (bd_play, overlay callbacks, ARGB compositing, remote navigation), what
   BD-J (Java) menus would need (not feasible on iOS), and how many of the owner's discs are BD-J vs HDMV-only
   (libbluray reports `bd_get_disc_info()->bdj_detected`; check John Wick 4 UHD and Matilda UHD on the mini's share
   if reachable, else say unknown). No implementation.
4. Gates as in the spec; DevPlus proof only for the DVD menu flow if a DVD ISO exists there; no commit.

## Fable reviews (2026-10-18 23:05) — both say FIX FIRST; apply all of these, then re-prove

### App diff review
**VERDICT: fix first.**

1. `Sources/OpenStreamApple/AppleDiscPlayback.swift:11-13` — `engineTitleID` now returns title 0 for every `.mainTitle` start, so DVD "Skip to Movie" (`AppleDiscoverView.swift:9981`, `:5815`, `:4717`) passes an explicit ID and the engine takes the ordinary title path instead of the navigator (`AetherEngine.swift:3069-3078`, whose own comment says Skip to Movie keeps navigation alive): the title opened is VTS group index 0 from `DiscReader.wrap`, not the VM's main title, and the "Disc Menu" transport item and Menu/Resume disappear on that path. This is outside the row, and `AppleDiscStartTests.swift:405-411` plus `AppleDiscPlaybackTests.swift:16,182` were rewritten to assert the new value, which the stabilize rules forbid without the owner's words.

2. Spec step 1 (publish title metadata in the navigator path) is not in the diff and the engine pin is unchanged (`Package.resolved` 07afad6; all 47 checkouts on the mini are at that commit and clean). At that revision a menu-started title loads as `.custom(reader, formatHint: "mpeg")` (`AetherEngine+DVDMenu.swift:236`) after `load` clears `selectedDiscTitle`/`discChapters` (`AetherEngine.swift:3221-3222`), and nothing refills them for a VOB sector reader, so `engine.chapters` stays empty and `selectedDiscTitle` is nil on the DVD menu flow. Consequence: `Tests/OpenStreamAppleTests/ApplePlaybackEngineFixtureTests.swift:377-383` fails at `#require(selectedDiscTitle)` and `!chapters.isEmpty`, and `Apps/OpenStreamiOSUITests/AppleiOSUITests.swift:425-428` fails waiting for `player.chapters`; no run log for either test exists on the mini.

3. `Tests/OpenStreamAppleTests/ApplePlaybackEngineFixtureTests.swift:339` and `:381` — exact `Double` equality between the IFO/MPLS title duration and `aether.duration`, which comes from the demuxer's format context; this will fail or flake unless the engine copies the title duration verbatim, so use a tolerance.

4. `Sources/OpenStreamApple/AppleMediaPlaybackView.swift:477-479` — a second `AppleTransportOverlayModel` on the same coordinator observes the engine and writes `coordinator.handsOffAtEnd` on every tick (`AppleTransportOverlayModel.swift:184-190`) beside the surface overlay's own model; on iOS a DVD title plays on `.surface`, so the new avPlayer-only Chapters menu (`:349-358`) is dead on the DVD path and the UI test's `player.chapters` is the pre-existing surface menu (`AppleTransportOverlay.swift:494-506`). The tvOS branch (`:792-798`) adds new transport-bar chrome through a shared view.

5. `Sources/OpenStreamApple/AetherPlaybackEngine.swift:544-546` — the immediate `applyPosition(aether.currentTime)` after every seek changes the non-disc path too (your check 6): harmless on the native route, but on a `.stalled` software reposition the clock still holds the pre-seek time, so the scrubber can snap back once before the next tick.

6. `Apps/OpenStreamiOSUITests/AppleOwnerContentUITests.swift:283-291` — the owner-ISO test accepts either the menu or a title at start, so it proves seek and timeline but says nothing about menu-first; it weakens no existing assertion, and the existing menu-first and Skip-to-Movie tests (`AppleiOSUITests.swift:252-254`, `exerciseDVD`) are untouched.

7. Checks that pass: the default start is unchanged on every platform (`AppleDiscoverView.swift:3280` and `AppleLocalLibraryStore.swift:1011` both default to `.menu`, asserted by the new alias test); the Blu-ray explicit path is at least as fast, since ID 0 equals `DiscReader`'s default index, the recognition cache stores both keys (`DiscReader.swift:117-123`), and the DVD-session probe is now skipped; a seek during a navigator title goes to the software host's demuxer over the title's sector reader while the VM idles, `titlePosition` reads `engine.currentTime` (`AetherEngine+DVDMenu.swift:259-261`), and only `stop()`/`load()` without the hand-off flag tear the session down, so menus after seeking still work.

8. `Sources/OpenStreamApple/AetherPlaybackEngine.swift:748-751` — the `combineLatest` forwarding is correct and leaves non-disc content unchanged (`discChapters` is empty there), and it gives Blu-ray direct titles chapters for the first time; it simply has nothing to forward on the DVD menu path until finding 2 is fixed in the engine fork and the pin is bumped.

### Engine fork diff review (~/Developer/openstream-build/AetherEngine-fork on Dev-Mini)
**VERDICT: fix first** (small fixes; the design is right). Checked against the base checkout on Dev-Mini (`~/Developer/openstream-build/*spm*/checkouts/AetherEngine` at 07afad62). Checks (1) IFO-only, (3) non-menu paths untouched and (5) thread-safety all pass: duration and chapters come from `titlePGCs`, `ptts`, `programMap` and cell `playbackTime`, nothing reads a VOB; `cellRanges` keeps its defaulted signature and is only called from `DVDMenuPlayer`; the engine and `EngineDVDTitleHost` are both `@MainActor`, and `selectedDiscTitle` / `discChapters` / `duration` are `@Published` on the main actor. Check (2) holds: the `$state` watch and `titleEnded` path are unchanged and the engine test still reaches the VMGM still after the seek. Findings:

1. `Sources/AetherEngine/Disc/DVDMenu/AetherEngine+DVDMenu.swift:265` — `TitleInfo(id: request.title - 1, …)` violates the type's documented contract (`DiscMetadata.swift:8-9`: id is the longest-first ordinal and the key for `selectTitle(id:)`), so an app that feeds `selectedDiscTitle.id` back to `selectTitle` or matches it against `discTitles` picks the wrong title; use the probe's ordinal or document that menu-session ids are VMG title numbers.

2. `Sources/AetherEngine/Disc/DVDMenu/DVDMenuPlayer.swift:329` and `AetherEngine+DVDMenu.swift:257` — chapter and resume entry now relies on a time seek into a whole-PGC MPEG-PS reader (`startPosition: request.startSeconds`) instead of starting the reader at the cell sector, and `t.startSectorOffset` is no longer used except for `isResume`; on cells flagged `stcDiscontinuity` (`DVDNavigationIFO.swift:127`) the stream's PTS timeline no longer matches the IFO-derived `cellStartSeconds`, so "chapter 5" or a resume can land in the wrong cell. No test exercises an entry at `startCell > 1` at the engine level.

3. `AetherEngine+DVDMenu.swift:237-239` and `DVDMenuPlayer.swift:332` — `titleDuration` and `cellStartSeconds` sum every cell of the PGC, while `cellRanges(of:angle:)` drops the unselected angle-block cells, so on a multi-angle title the declared duration exceeds the stream, the scrubber shows a tail that cannot play, and chapters after an angle block are shifted later (pre-existing for `cellStartSeconds`, newly surfaced through `declaredDurationSeconds`).

4. `Tests/AetherEngineTests/DVDMenu/DVDMenuPlayerTests.swift:176-181` — the `titlePosition(seconds:)` re-indexing (now 1-based instead of `startCell`-relative) is only exercised with `startCell == 1`, where old and new code agree; add a `titlePosition(seconds:)` call after the `startCell == 2` resume and assert `state.resume?.cell`, otherwise a regression there would save the wrong RSM cell.

5. `AetherEngine+DVDMenu.swift:268` — `engine.duration = titleDuration` is redundant: `AetherEngine+Loading.swift:205` already forces `duration = declared` on every host publish once `declaredDurationSeconds` is set; drop the line (anti-slop) so there is one source of truth, and note `declaredDurationSeconds` stays in `engine.loadedOptions` after the title ends until the next title overwrites it.

6. `DVDMenuPlayer.swift:74` — `var startSeconds: Double { cellStartSeconds[startCell - 1] }` has no bounds check; it is safe today because `cellStartSeconds` has one entry per PGC cell and the VM validates `cellNumber` (`DVDVirtualMachine.swift:476`), but a `Double?` or a `guard` with a `dvdMenuSessionEnded` would turn a malformed IFO into a navigation error instead of a trap on the main actor.

### Lead instructions
- App finding 1 is a rule violation: revert the `engineTitleID` change so `.mainTitle` without an explicit title ID
  keeps the navigator path (Skip to Movie keeps Disc Menu / Menu / Resume alive), and restore the two rewritten
  tests (AppleDiscStartTests.swift:405-411, AppleDiscPlaybackTests.swift:16,182) to their committed assertions
  (`git show HEAD:./Tests/…`). The Blu-ray explicit-ID path may stay only where an explicit ID was already passed.
- App findings 2–5: the duration/chapter publishing on the DVD menu path lives in the engine fork — that is fine,
  but the app tests must then be run against the fork build (temporary override is OK for proof; the lead bumps
  the pin after the fork is pushed). Use a tolerance for duration equality; remove the second
  AppleTransportOverlayModel and the dead avPlayer-only Chapters menu (the surface overlay already has
  `player.chapters`); drop the post-seek `applyPosition` on the non-disc path (or guard it to disc playback).
- Engine findings 1–6: apply each (title id contract per DiscMetadata.swift:8-9; chapter/resume entry starts the
  reader at the cell sector, not a time seek into the whole PGC, or prove PTS continuity; multi-angle duration from
  the selected angle's cells; a `startCell == 2` test asserting `state.resume?.cell`; drop the redundant
  `engine.duration =` line; bounds-checked `startSeconds`). Engine tests must pass (`swift test` in the fork on
  the compile lane).
- Then re-run: fork tests; app `swift test` serial; iOS + tvOS builds; the ISO UI checks (iOS menu cases, the
  timeline/scrub/chapter test, tvOS DVD menu tests) against the fork build. Report with the AGENTS.md format and
  the engine diff stat. No commits (the lead commits the fork, pushes it from the Studio, bumps the pin).

## Fable second pass (2026-10-18 23:45) — FIX FIRST; all twelve earlier findings resolved; apply these five, then re-run the gates
**VERDICT: fix first** (one real regression, one small robustness hole; the rest is optional polish).

All twelve earlier findings are resolved. App: the Skip to Movie bypass and the two rewritten test files are gone from the diff, which is now only the adapter plus tests. Publishing lives in the fork and is tested there. Durations compare with tolerances. The second transport model and the dead Chapters menu are gone. The post-seek position push is guarded to disc playback. Engine: the title id now comes from the same ordering rule as the probe. Chapter and resume entry lands on the cell's first byte, proven by the new demuxer test. Multi-angle duration and starts come from the selected angle. The resume test now exercises position re-indexing at cell two. The redundant duration write is gone. The start offset is optional with a navigation error on a bad IFO. I read code only and did not re-run the gates.

1. **Seeks read linearly from the cell start.** `Sources/AetherEngine/Disc/DVDMenu/DVDTitleIOReader.swift:36-43` lands every time seek on the cell's first byte and leaves the rest to the packet gate, per the contract in `IO/IOReader.swift:33-36`. The old plain concat reader got FFmpeg's byte binary search. A +10 min seek, a resume or a Skip to Movie with a saved position now reads and discards up to a whole cell of VOB before landing. Single-cell titles mean gigabytes, and over the owner's SMB share that is tens of seconds. The fixtures have one to two second cells, so no gate can show it. Fix: store each cell's byte length and duration in `Cell`, land proportionally inside the cell on a 2048-byte boundary, then optionally walk to the next NAV pack with `DVDNavPack.parse`. Mid-cell landings fold correctly because `timestampShift(at:)` is constant per cell.

2. **One bad cell kills the whole navigation session.** `DVDDiscSource.swift:174-183` returns nil when any selected cell's first sector fails `DVDNavPack.parse`, which `startTitle` turns into "title sectors unreadable" at `AetherEngine+DVDMenu.swift:170`. `walkCell` deliberately tolerates damaged cells. Fall back to the previous cell's shift instead of failing. Also note each cell costs one synchronous read at title start, so a remote ISO with many cells pays that many round trips before the first frame.

3. **The chapter-seek base is stale on the folded axis.** `AetherEngine.swift:3515-3516` sets `sourceStartSeconds` from the probe's raw container start, and `selectChapter(id:)` at `:5727` adds it. Cell one now folds to zero, so an engine host calling `selectChapter` lands late by the raw start time. OpenStream seeks chapters via `seek(to:)` at `AppleTransportOverlay.swift:496`, so the app is unaffected. Set it to zero when the loaded reader is a `DVDTitleIOReader`.

4. **Duplicated title-ordering rule.** `DVDDiscSource.swift:149-154` restates `DiscReader.swift:171-183` (size-sorted VOB groups, filtered by the TT_SRPT title sets, falling back to all). Extract one helper on `DVDTitleSelector` so the two cannot drift. Same anti-slop pass: the computed `startSeconds` sits between stored properties at `DVDMenuPlayer.swift:74-77`.

5. **A UI-test predicate taps the screen.** `Apps/OpenStreamiOSUITests/AppleOwnerContentUITests.swift:364-369` re-shows the transport from inside the polled predicate block. Side effects inside an `NSPredicate` run on the waiter's cadence and make failures hard to read. Tap once before the wait instead.

### Lead instructions
- Findings 1 and 2 are required (the owner's discs live on an SMB share; a seek that reads a whole cell linearly
  is exactly the "disc read 17 s" class of bug we just fixed in iso-open). Implement the proportional landing on a
  2048-byte boundary (+ optional walk to the next NAV pack) and the per-cell fallback; add an engine test that a
  +10 min seek on a multi-GB synthetic cell reads < 2 MB before landing (mock reader counting bytes).
- Finding 3: set `sourceStartSeconds` to 0 when the loaded reader is a DVDTitleIOReader.
- Finding 5: tap once before the wait.
- Finding 4 (dedupe the title-ordering rule) only if it stays under 20 lines; otherwise leave a one-line note.
- Re-run: engine `swift test`; app `swift test` serial; iOS + tvOS builds; iOS 5/5 + tvOS 4/4 ISO UI checks with the
  fork override; then restore the pin. No commits. Report (AGENTS.md format) + engine diff stat.

## Fable third pass (2026-10-19 00:10) — FIX FIRST; items 1–5 of the second pass resolved; apply these, then re-run the gates and KEEP THE LOGS
**VERDICT: fix first.** Items 1 to 5 from the second pass are resolved: proportional 2048-aligned landing (`DVDTitleIOReader.swift:38-53`), per-cell NAV fallback (`DVDDiscSource.swift:181-183`, tested for both cells), `sourceStartSeconds = 0` for the title reader (`AetherEngine.swift:3516-3520`, and the reload path leaves it 0 because stopInternal zeroes it), the ordering rule deduped in six lines (`DVDTitleSelector.swift:27-31`), and the owner UI test taps once before the wait with read-only predicates. Non-disc playback is unchanged: the fold is gated on `dvdTitleReader`, and `clipSubtractSeconds` returns 0 on an empty timeline (`Demuxer.swift:309`). The angle, chapter and resume indexing is consistent (all PGC-indexed, selected cells only in the reader). Two new problems, one real.

1. **Seek landing can overshoot and makes relative seeks wrong.** `DVDTitleIOReader.swift:42-48` maps time to bytes linearly inside the cell. On a VBR title the landing is early or late by the cumulative bitrate deviation (tens of seconds on 5-minute chapter cells, minutes on single-cell titles). Landing late breaks the contract at `IO/IOReader.swift:33-36` (at or before the target; the gate only drops what precedes it), so the playhead shows the late time. Worse, the error is a function of absolute position, so "skip forward 10 s" from a landed point seeks to `current + 10` and lands at the same offset again: with a 30 s early error, skip forward moves the playhead 20 s back, and the owner UI test's 64-skip loop diverges instead of converging. Fix without extra VOB reads: parse VTS_TMAPT from the IFO (VTSI_MAT 0xD8; per PGC a VOBU sector every `tmu` seconds, bit 31 = discontinuity) and land on the table entry, keeping the proportional guess only when the table is absent. Cheaper alternative if TMAPT is out of scope: after landing, walk to the next NAV pack, read `pci.vobuStartPTM`, and bisect inside the cell (two or three sector-sized probes) until the landing is at or before the target.

2. **An audio-track switch during a menu title wipes the title and chapters.** `selectAudioTrack` reloads through `stopInternal`, which clears `selectedDiscTitle` and `discChapters` (`AetherEngine.swift:6054-6055`). The reload only restores them when the reopened demuxer reports disc titles (`AetherEngine+Loading.swift:2025-2037`), which a `DVDTitleIOReader` never does, and the host sets them only in `startTitle` (`AetherEngine+DVDMenu.swift:268-270`). So the app's chapter menu and title info vanish after the first language change on a multi-audio DVD. Snapshot and restore them across the reload the way `activeDiscTitleID` already is.

3. **The byte-counting test never reads.** `DVDSubpictureTests.swift` `tenMinuteSeekDoesNotReadThroughAGigabyteCell` (about lines 216-233): after `seek(to: 600)` the cursor is already at `target`, so the `while` body never runs and `#require(count > 0)` is dead. It proves the reader does not read on seek, not that a demuxer seek reads under 2 MB before landing. Either seek through a `Demuxer` over a synthetic MPEG-PS cell, or assert the landed byte offset and drop the read loop.

4. **One synchronous sector read per cell at title start.** `DVDDiscSource.swift:180` reads every selected cell's first sector before the first frame, so a remote ISO with 30 cells pays 30 range requests on the title handoff. Only cell one is needed up front; the other shifts can be resolved on first use (first packet or first seek in that cell) and cached.

5. **No gate evidence on the mini.** The lane copy under `/Volumes/DevExt/dev/openstream-build/lanes/iso-player` is from 19:30, the `Package.swift` override from 23:51, and no log there or under `~/Developer/openstream-build` mentions the new tests. I read code only. The report must show the engine `swift test` count, the app serial run, and the iOS and tvOS ISO UI results with the fork override before merge.

### Lead instructions
- Finding 1 (required): land seeks on the VTS_TMAPT time map (VTSI_MAT 0xD8; per PGC one VOBU sector every `tmu`
  seconds, bit 31 = discontinuity), proportional guess only when the table is absent; the landing must be at or
  before the target (IOReader contract) so relative skips converge. Add an engine test with a synthetic TMAPT.
- Finding 2 (required): snapshot/restore `selectedDiscTitle` and `discChapters` across the audio-track reload the way
  `activeDiscTitleID` is.
- Finding 3: make the byte-counting test real (seek through a Demuxer over a synthetic MPEG-PS cell, or assert the
  landed byte offset and drop the dead loop).
- Finding 4: resolve only cell one's NAV shift up front; the others on first use, cached.
- Finding 5: write every gate run's output under /Volumes/DevExt/dev/openstream-build/iso-player/gates/ (engine
  swift test, app serial swift test, iOS + tvOS builds, iOS and tvOS ISO UI runs with the fork override) and quote
  the counts with those paths in the report.
- No commits anywhere; restore the Package.swift pin after the proofs.

## Fable fourth pass (2026-10-19 00:55) — FIX FIRST; carry-over items 1–5 confirmed; three items left (engine only)

**VERDICT: fix first** (one confirmed defect in the new fold path; everything else is merge-ready).

**Carry-over items 1 to 5, all confirmed.** Seeks land on VTS_TMAPT entries at or before the target, with the proportional guess only when the table is absent, and the synthetic TMAPT test covers both the landing and a truncated table. The title and chapters survive the audio reload. The byte-counting test asserts the landed offset with zero bytes read. Only cell one's NAV shift resolves up front, the rest lazily and cached, including damaged cells. Gate logs exist under `/Volumes/DevExt/dev/openstream-build/iso-player/gates/`: engine 2672/360 passed (after an EOF failure on the audio-reload test, fixed by the rewind before reopen), app serial 3590/446 with the fork override and the pin restored, iOS and tvOS builds succeeded, iOS ISO UI 5/5 including the new timeline test, tvOS 4/4. The last engine run postdates the last source edit.

**New checks that pass.** VTS_TMAPT is at VTSI_MAT 0xD4 per the spec, with 0xD8 correctly left to the menu cell addresses. Entry k maps to (k+1) × tmu, bit 31 is masked, maps index by pgcn − 1 in PGCIT order, and the sector space matches the cell addresses. The lazy resolve is safe: lock order is always demuxer access lock, title reader lock, disc source lock. The playback cursor is a forked base reader, so the NAV read on the disc's own reader cannot move it, and session end cancels that reader. Non-disc playback is untouched: every new branch is gated on the title reader, and `clipSubtractSeconds` returns 0 on an empty timeline. `selectChapter` looks chapters up by id, so non-contiguous PTT ids are fine.

1. **`Sources/AetherEngine/Demuxer/Demuxer.swift:1476-1484` (`resetAfterTimeSeek`), consumed at `:1334-1341`.** After a time seek, `avio_flush` empties the buffer but leaves the AVIOContext `pos` where the last read ended, so every later packet reports a stale byte position and the fold picks the wrong cell. Confirmed with a throwaway probe on menu-test.iso: after seeking to cell two the reader cursor was at 34816, but the first packets reported 71718 and 72704, and after seeking back to 0 the next packet reported 108582. The fixtures hide it because their cell shifts differ by 1 ms (0.5334 s vs 0.5344 s). On a disc with per-cell STC resets the playhead jumps after the first seek and relative skips misland. Fix: when `dvdTitleReader != nil`, set the context's `pos` to the reader's cursor after the flush (or `avio_seek` to it), and extend `demuxerChapterEntryStartsAtTheCellSector` to assert the first packet's `pos` lies inside cell two's byte range.

2. **`Sources/AetherEngine/Disc/DVDMenu/DVDNavigationIFO.swift:433-446`.** `parseTable` returns an empty array when any single map fails a guard, including `interval > 0`. Dummy or short PGCs commonly carry a zero-entry map, and some authoring tools write tmu 0 there, which would strip the time map from every PGC in the VTS and silently degrade all seeks to the proportional guess. Append an empty map for a bad entry and continue, so the index stays aligned and the other PGCs keep their maps.

3. **`Sources/AetherEngine/Disc/DVDMenu/DVDDiscSource.swift:190-199`, note only.** TMAPT entries inside an angle block point at angle one's cells, so for any other angle they are dropped and seeks inside the block land at the block start. Acceptable degradation; worth a one-line comment so nobody reads it as a bug later.


### Lead instructions
- Finding 1 (required): after the time-seek flush, set the AVIOContext `pos` to the title reader's cursor (or
  avio_seek to it) when `dvdTitleReader != nil`; extend `demuxerChapterEntryStartsAtTheCellSector` to assert the
  first packet's pos lies inside cell two's byte range.
- Finding 2 (required): a bad TMAPT entry yields an empty map for that PGC and parsing continues; test it.
- Finding 3: one-line comment.
- Re-run the engine `swift test` and the app serial `swift test` with the fork override; iOS + tvOS builds; the
  iOS 5/5 and tvOS 4/4 ISO UI checks; logs under /Volumes/DevExt/dev/openstream-build/iso-player/gates/ (new
  file names, keep the old ones); restore the pin. No commits.

## Fable fifth pass (2026-10-19 01:35) — FIX FIRST; pass-four items confirmed; three small engine items
**VERDICT: fix first** (two small regressions, one line each; everything asked for in pass four is present and correct).

Fourth-pass items, confirmed against the base checkout on Dev-Mini:

- **(1) AVIO pos after a time seek.** `Demuxer.swift` `resetAfterTimeSeek` sets `pb.pos` to the title reader's cursor right after `avio_flush`, which for a read context only empties the buffer and leaves `pos` stale. The guard is `dvdTitleReader != nil`. `demuxerChapterEntryStartsAtTheCellSector` now asserts the first packet's pos lies in cell two's byte range, so the test fails without the fix.
- **(2) Bad VTS_TMAPT entry.** `DVDTimeMap.parseTable` appends an empty map for a bad offset, zero tmu or truncated entries and continues. The parameterised test covers all three damage kinds and checks neighbours survive. Table layout (0xD4 pointer, u16 count, u32 end address, u8 tmu, u16 entries) matches the IFO spec.
- **(3) Angle comment.** Present at `DVDDiscSource.swift:194`.

New findings:

1. **`DVDDiscSource.swift:192` and `DVDTitleIOReader.swift:54`: an empty time map disables the proportional seek.** For a PGC whose TMAPT entry was rejected, `titleTimeMaps` holds an empty map, so `makeTitleReader` hands the reader `timeMap = []` instead of `nil`. In `seek(to:)` the `if let timeMap` branch then always falls to `cell.byteStart`. Every seek inside such a title snaps to the start of its cell. The tolerance added in pass two therefore degrades seeking to chapter granularity rather than to the old bitrate estimate. Fix: `timeMap = map.entries.isEmpty ? nil : …`, or guard `!timeMap.isEmpty` in the reader. Optionally, when the map has no entry inside the chosen cell, fall back to the proportional estimate for that cell instead of the cell start.

2. **`DVDMenuPlayer.swift:339`: chapter or PTT entry into an angle block faults when angle ≠ 1.** A program map entry points at the block's first cell, which is the angle-one cell. With SPRM 3 = 2 that index is not in `timeline.cells`, so the new guard raises "title cell missing". The old `cellRanges(fromCell:)` handled this by starting at the block and skipping to the selected angle. `cellStartSeconds` already carries the right start for the block head, so the fix is to resolve `t.cellNumber - 1` to the first selected cell at or after it before the guard. Nothing else regressed here: `titlePosition` sends `sectorOffset: 0` in external mode, so resume precision is unchanged from before.

3. **`DVDTitleIOReader.swift:89`: a fork starts with no resolved NAV shifts.** `makeIndependentReader` rebuilds `shifts` from `sourceStartSeconds` only, which `makeTitleReader` always passes as nil, so each side reader or probe re-reads NAV packs lazily through `readSectors`. On a remote ISO that is one range request per cell per fork. Correctness is fine because every fork resolves its own shifts consistently. Low priority: copy the parent's `shifts` under the lock when forking.

Checked and clean: `readSectors` takes the disc's own lock, so the resolve closure is safe beside the menu player; the reload path closes the old demuxer in `stopInternal` before the retained reader is rewound; the `else if let menuTitleToRestore` branch sits correctly after the concat-disc branch and does not touch `sourceStartSeconds`, which the engine already forces to 0 for a title reader; `orderedTitleVOBGroups` is behaviour-identical to the inline code it replaces; all test helpers used by the new tests exist at 07afad62.


### Lead instructions
- Finding 1 (required): an empty time map must leave the proportional seek in place (`timeMap = nil` when empty, or
  guard `!timeMap.isEmpty`); when the map has no entry inside the chosen cell, fall back to the proportional
  estimate for that cell. Test both.
- Finding 2 (required): PTT/chapter entry into an angle block with angle ≠ 1 resolves to the first selected cell at
  or after the block head before the guard. Test with angle 2.
- Finding 3: copy the parent's resolved shifts into a fork under the lock (small; do it).
- Re-run engine swift test, app serial swift test with the fork override, iOS + tvOS builds, iOS 5/5 + tvOS 4/4 ISO
  UI checks; logs under /Volumes/DevExt/dev/openstream-build/iso-player/gates/ with a `fifth-` prefix; restore
  the pin. No commits.
