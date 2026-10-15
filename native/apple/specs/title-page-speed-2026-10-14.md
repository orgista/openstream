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
