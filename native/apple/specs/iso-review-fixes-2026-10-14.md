# ISO disc menus: review fixes + two follow-ups (2026-10-14)

The ISO work (files in `verification-artifacts/iso-menus-2026-10-13/owned-files.json`, plus the uncommitted engine
fork diff on Dev-Mini at `/Volumes/DevExt/dev/openstream-build/AetherEngine-fork`) is uncommitted. Fix every finding in
`verification-artifacts/fable-review-iso-2026-10-14.md`. Read native/apple/AGENTS.md first. Plex Stage A files
(AppleIdentityAliasStore, AppleLogicalItemKey, ApplePlaybackStore, AppleLocalLibraryStore, AppleLibraryMetadataResolver
and their tests) are another job's: do not touch or revert them.

## Fix
1. HIGH: a menu-launched DVD title that ends must return to the disc menu, not close the player. While a disc session
   is alive, `applyPhase` does not forward `.ended` / the transient `.idle`; only a real session end does. Add an e2e
   step (iOS and tvOS) that lets a title on menu-features.iso or menu-test.iso run out and asserts
   `player.disc.menu.active` reappears.
2. MEDIUM: show "Disc Menu" only when a DVD navigator exists (`discMenu.state != nil`). Blu-ray ISOs show no Disc
   Menu control. A DVD started with Skip to Movie keeps its position when the user opens the menu (no cold restart).
3. tvOS e2e: the chapter-menu assertion must prove the page changed (accessibility value "Button N of M" or similar).
4. Engine fork: probe before stopping in `startDVDMenuSessionIfPossible`.
5. Owner decision (lead): subtitle tracks with no language tag are listed in the Subtitles menu as "Unknown" (numbered
   if several) and are never auto-selected. Unit test + verify on ff-pgs-dts.m2ts that On renders in frame.
6. Authenticated SMB: if SMB fixture credentials already exist on Dev-Mini or in the e2e environment (look first,
   never print them, never create new ones), run the Matilda ISO + English PGS check over SMB on iOS and tvOS; else
   report "not run" with what is missing.

## Gates
Serial Swift suite (≥ 3302 passing), fork DVD/HTTP tests, tvOS + iOS builds with recompile greps, E2E-tvOS 20/0 and
E2E-iOS 40/1 (AirPlay), the ISO feature set, simulator builds with `-derivedDataPath $HOME/Developer/sim-dd-internal`,
via `scripts/mini.sh`/buildlock. No commits in either repo. Screenshots to `verification-artifacts/iso-menus-2026-10-13/`.
Report Done / Not done / Gates with file:line.
