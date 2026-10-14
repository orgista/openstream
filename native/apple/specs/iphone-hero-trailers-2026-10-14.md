# PRIORITY: iPhone hero — full-bleed again, trailers again (owner 2026-10-14)

Owner: "heros in build 18 changed no more trailers and it nots full screen like it was before on iOS … look into how
netflix and apple tv handle trailers and fix that please that was my fave feature". OWNER-TODO.md top item.
Read native/apple/AGENTS.md first (all of it; §0–§3 are hard rules), then the `swiftui-pro` and
`swiftui-performance-audit` skills.

## Cause (lead's investigation)
`b354bd1` (2026-10-09, in build 18, not 17) made the iPhone portrait hero a static still:
`AppleHeroPortraitArt.phoneHeroPlaysTrailers = false` (AppleHeroPortraitArt.swift:63; test at
AppleHeroPortraitArtTests.swift:139), the phone path returns `AppleHomePhonePortraitStage` before the trailer ZStack
(AppleHomeBillboard.swift:~368), trailer availability `.none` on phone (:113), and the art height became 1.25 × width
(AppleHomePhoneHeroLayout.swift:64-67). Before it, `0d100ce` (owner 2026-09-23 "the hero needs to be bigger"): art and
trailer from the screen top (under the status bar and large title) to 73 % of the screen height, ≥ 90 pt of the first
row peeking above the tab bar (SE 466 pt … 15 Pro Max 680 pt).

## Do
1. Full-bleed again: phone hero art + video from the very top edge to 73 % of screen height with the 0d100ce clamp
   (row peek ≥ 90 pt). Keep b354bd1's art CHOICE and settle-before-draw (it fixed owner item 6: cut off / off centre /
   too zoomed), just in the taller frame; keep the focal crop sensible at the new aspect.
2. Trailers again on iPhone, Apple TV app style (verification-artifacts/rea-mac-tv-2026-10-12/report.md:70-94):
   muted autoplay once the still has settled, video aspect-fill in the same frame, cross-fade from the still; the
   existing sound control unmutes. Only when `settings.autoPlayTrailer` is on, Reduce Motion off, Low Power off, the
   app active, and at least half the hero visible; pause when scrolled away, covered (title page pushed, sheet), or
   backgrounded; resume or fall back to the still cleanly. While a trailer plays, no auto-advance; advance ~1 s after it
   ends (dwell rules from 229cabe/17e7041). Button says Play Trailer again where a trailer exists.
   Reuse the shared trailer code the iPad/tvOS hero uses (AppleHomeBillboard.swift:526-545) rather than a second copy.
3. Remove the `phoneHeroPlaysTrailers` flag (or set true) and update tests; add unit tests for the frame height at
   SE / 16e / 15 Pro Max widths and for the trailer gating policy.
4. Nothing else changes: iPad/Mac/tvOS heroes, title-page trailer header, Library hero (check it still looks right).

## Proof
- Screenshots on the iPhone 16e DevPlus or the iOS sim (simulator builds use
  `-derivedDataPath $HOME/Developer/sim-dd-internal`): Discover BEFORE (current HEAD, = build 18 look) and AFTER: still,
  trailer playing at ~3 s and ~10 s, scrolled half away (paused), and Library hero. Also iOS 18.6 sim `5CFC965C…`
  AFTER. Sims muted (`-OpenStreamMuteAudio YES`). Save to `verification-artifacts/iphone-hero-2026-10-14/` with
  BEFORE-/AFTER- prefixes.
- Gates: serial Swift suite; iOS + tvOS builds with recompile greps; E2E-iOS (expect 40/1 AirPlay) and E2E-tvOS (20/0)
  via `Tests/Fixtures/run-e2e.py`. All heavy work through `scripts/mini.sh` / buildlock, foreground.
- Other uncommitted work may be in the tree (ISO disc menus, network-share folders): do not touch or revert it.
- No commits, no markdown edits. Clean up sims/apps you open. Report per AGENTS.md §7.
