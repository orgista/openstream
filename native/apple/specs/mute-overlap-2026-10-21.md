# Landing hero: trailer mute sat under Refresh (2026-10-21)

The batch-1020b gate (shots/stage6-direct/discover-rest-isolated.png, shots/rows/discover-9.png, library-9.png under
/Volumes/DevExt/dev/openstream-build/batch-1020b) showed the trailer's mute glyph under the round Refresh control on
the iPhone Discover and Library heroes. Cause: AppleHomeBillboard's phone preview still used
`controlTopInset: copyFadeLine + 8`, from when a navigation bar sat there; hero-unify put the round Search/Refresh
row there instead. The lead's change (already in this tree, AppleHomeBillboard.swift ~line 443) moves it to
`copyFadeLine + AppleDesignTokens.minimumActionSize + 8`, under that row.

## Job (verification only, plus a fix ONLY if the proof fails)
1. iOS Debug build; prove AppleHomeBillboard.swift recompiled (grep the build log).
2. On the owner sim (iOS 18.6, 7530ECB2…, ONLY via /Volumes/DevExt/dev/openstream-build/batch-1018a/protected.py),
   capture Discover and Library at rest WHILE the hero trailer plays (reuse the batch-1020b stage-6 capture approach),
   and measure the mute control's frame (`detail.trailer.mute`) against `discover.compact-title.refresh` /
   `.search` frames: no overlap, mute fully inside the hero art, ≥ 44 pt. Also on iOS 27 (73E49263…).
3. Run testB8DiscoverJank (hero drawn ≤ 2) and AppleiOSStubSmokeUITests on 18.6.
4. Serial swift test (compile lane). code-anti-slop on the diff. No zero-byte Swift files.
Rules: Dev-Mini only, `scripts/mini.sh` with OPENSTREAM_MINI_DEST='~/Developer/openstream-build/lanes/tv-shelf'; FIFO
locks (another Codex job, front-load, shares them — queue, never kill); never Anthony or OfficePlus; no commits,
stash, checkout, reset; mini > 12 GB free. Report per AGENTS.md §7 with the frames and the screenshot paths.

## Round 2 (lead, 09:00)
Round 1 proof passed but the mute sat 12 pt right of the Refresh column (mute x 382 vs Refresh 370 on 18.6).
The lead added `AppleTrailerPreviewLayout.topControlInset = 16` (AppleDiscoverView.swift ~8680/8694): a top-placed
control now uses the 16 pt column inset; bottom placement keeps 4. New unit test
`aTopSoundControlLinesUpWithTheRoundControlColumn` (AppleTitlePageSlotArtTests). Re-run round 1's steps 1–4 exactly;
expect mute.x == refresh.x and mute.maxX == refresh.maxX on both OSes, plus one title-page capture with the trailer
playing (the title page also places its control at the top: it must sit at trailing 16 with nothing under it).
