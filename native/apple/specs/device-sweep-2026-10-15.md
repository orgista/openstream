# Real-device sweep: every "needs a device check" item, now that devices are on Dev-Mini (2026-10-15)

Devices on Dev-Mini (`xcrun devicectl list devices`): iPhone 16e **DevPlus** (`00008140-000809A82E89801C`),
Apple TV 4K 3rd gen **OfficePlus** (`00008110-0001486E2189A01E`), Apple TV 4K 2nd gen **DevTV**
(`18139e8e65153ff7c3d6f1284646cd12d82a6173`, slow hardware: our speed floor). Vision Pro is NOT in scope (sleeps
unless worn; another job owns it). Signing: Xcode automatic signing with the ASC key (`-allowProvisioningUpdates
-authenticationKeyPath ~/.appstoreconnect/private_keys/AuthKey_Q843G8DW6C.p8 -authenticationKeyID Q843G8DW6C
-authenticationKeyIssuerID bc8a87e8-6fcf-4509-b6a1-0e21c32f2298 DEVELOPMENT_TEAM=2VQ74PD5YG`); DevTV may need
registering the same way (the owner OK'd registering the dev devices). Apple TVs must have Sleep After = Never; if one
is asleep, wake it with `devicectl` or say so in the report.

Where: branch `device-sweep`, worktree `Apps/OpenStream-lanes/device-sweep`; every mini command
`OPENSTREAM_MINI_DEST='~/Developer/openstream-build/src-device-sweep/native/apple' scripts/mini.sh '<cmd>'`; device
builds DerivedData under `/Volumes/DevExt/dev/openstream-build/dd-sweep-<platform>`. Shared build lock; wait, never
kill others. Read native/apple/AGENTS.md first. Pull the app trace (`Library/Caches/openstream-trace.log`) with
`devicectl device copy from --domain-type appDataContainer --domain-identifier com.orgista.openstream` for evidence.

## Check, in this order (OWNER-TODO.md items; each gets PASS / FAIL + evidence: trace lines, screenshot)
1. Double spinner (owner 2026-10-14: "a loading circle on top of a loading circle" when you click content): open 10
   titles from Home, Library, Search and Continue Watching on DevPlus and DevTV; screenshot at 100/300/700 ms after
   the tap (mobile MCP / `devicectl` screenshots); find every place two progress views can show at once.
2. Title open speed on DevTV (slowest device): tap → hero art, tap → metadata, tap → Play ready; p50/p90 over 10 titles.
3. ISO disc menus on DevPlus and OfficePlus (1881b4b, 3af460e): every ISO in the owner's library — Play Disc shows
   the menu, Skip to Movie, Disc Menu; Matilda PGS captions placed right.
4. Top Shelf on OfficePlus and DevTV: Continue Watching + Top Picks appear (35c1522), no error 513 in the trace.
5. Apple TV storage (782bac9): Library has no raw permission warning; a setup import into a TV (use the import code
   path from a test hook, not a QR scan) succeeds.
6. Live: the owner's config on DevPlus and OfficePlus: guide loads, a channel plays, channel up/down, multiview (TV).
7. E2E-iOS on DevPlus and E2E-tvOS on DevTV once each: record pass/fail per test vs the simulator.

## Fix
Fix what fails when the fix is small and provable (test + device re-check); list the rest with cause. No commits.
Gates for any fix: serial Swift suite, iOS + tvOS builds with recompile greps, the four Release (no add-ons) builds if
near `OPENSTREAM_ADDONS`. Report per AGENTS.md §7: table of items × devices, evidence paths, fixes, what's left.
