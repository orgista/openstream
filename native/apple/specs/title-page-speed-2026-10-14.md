# Title page opens faster: ranked fixes 6–7 (owner 2026-10-14: "the speed can be improved")

Source: `design/reference-apps/2026-10-14-metadata-artwork.md` — read "Part B: Concrete causes of slow filling" 1–5,
the timing budget table and ranks 6–7. Read native/apple/AGENTS.md first.

Another job is editing the iPhone hero (AppleHomeBillboard, AppleHomePhonePortraitStage, OpenStreamRootView,
AppleHeroPortraitArtTests and the HERO lines of AppleDiscoverView). Do not touch those files or those lines, and do
not revert or reformat anything you did not write. Your AppleDiscoverView edits stay in the title-page/detail code.
Codex runs to 100% of its weekly window (owner override); stop only when the tool refuses.

## Measure first
Add signposts (or extend `AppleDetailFillTimeline`) for tap → first frame, first usable metadata, first hero art.
Record ≥10 warm + ≥10 cold openings on the e2e library fixtures BEFORE any change, same build config.

## Do
1. Rank 7 / cause 1: remove the fixed 1.5 s black slot hold (`AppleTitlePageSlotArt`, the phone slot art path in
   AppleDiscoverView). Show already-known/cached catalog art in the first frame; swap to better art when it arrives
   without a flash; answered-empty stays an explicit stable placeholder. No second spinner.
2. Rank 6 / cause 3: metadata merge publishes the first usable answer (catalog/local fields + the first provider
   that answers) and merges later providers in, instead of waiting for all bounded outcomes. Cancellation cooperative.
3. Rank 6 / cause 4: watch-provider enrichment and optional artwork fallback run independently; "done" no longer
   waits on them; episodes publish independently of enrichment.
4. Rank 6 / cause 2 + G5: identity lookup walks sources with a bounded parallel fallback and coalesces duplicate
   in-flight lookups per title (reuse what the metadata-match work added; don't duplicate it).
Unit tests for each policy (first-answer publish, late merge, no black hold, coalescing).

## Gates
Serial Swift suite (≥ 3363 passing), iOS + tvOS builds with recompile greps, E2E-iOS (known fails: Live AirPlay and
the pre-existing player skip-position assert) and E2E-tvOS 20/0. Simulator builds use
`-derivedDataPath $HOME/Developer/sim-dd-internal`; everything through `scripts/mini.sh`/buildlock, foreground.
Proof: before/after distributions of the three milestones. No commits. Report per AGENTS.md §7.

## Handoff 2026-10-15 (Codex hit its weekly limit mid-task; work Claude finishes)
Codex's partial edits are in the working tree (AppleDiscoverView title-page hunks, AppleDetailFillTimeline,
AppleDetailFillSpeedTests, AppleLibraryTitlesDebugView, AppleLocalLibraryTile, AppleiOSStubSmokeUITests, and its
console/run scripts on the mini in /tmp/openstream-title-speed-*). Its full log: /private/tmp/claude-501/-Volumes-Files-Projects/181ad4ad-2f9d-477b-bbf9-4afd7ae766a4/scratchpad/codex-titlespeed.log.
Review what it did against items 1–4, finish what is missing, and run every gate. The before baseline must come from a
clean HEAD copy on the mini (it never ran). The hero job is committed (98d4efb); AppleDiscoverView is yours now.
Also do: the Library hero title swap at ~8 s, see "5 follow-up" in /private/tmp/claude-501/-Volumes-Files-Projects/181ad4ad-2f9d-477b-bbf9-4afd7ae766a4/scratchpad/hero3-report.md (cached metadata merged
into the groups before contentDidChange() in AppleLocalLibraryStore.publishPersistedIndex); prove with a
Library+4s/+10s screenshot pair that the first hero page keeps its title.
