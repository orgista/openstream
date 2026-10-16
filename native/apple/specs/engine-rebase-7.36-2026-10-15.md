# AetherEngine: rebase our fork onto upstream 7.36+ (TrueHD Atmos / DTS:X via APAC) (owner 2026-10-15)

Owner pointed at r/appletv "Open Source AetherEngine now supports Dolby TrueHD 7.1 and DTS:X Spatial Audio on Apple TV
via APAC" (post 1x6e633). Upstream: superuser404notfound/AetherEngine. We pin cyberbanksy/AetherEngine 07afad62
(engine-lab branch): **based on upstream 6.66.0 (2026-09-02), 22 commits ahead, ~1,190 behind main.**
Upstream since then, relevant to us: 7.34.0 TrueHD Atmos heights rendered to APAC (Dolby MAT), 7.34.1 faster TrueHD
seeks, 7.35.0 BDMV folders over HTTP + persistent HLS ingest + no main-thread stall at first readyToPlay, 7.35.1 muxer
teardown crash fix, 7.36.0 DTS:X keeps heights + video returns after screen lock, #777 LibTrueHD/LibDTSX behind package
traits (`TrueHDObjectAudio`, `DTSXObjectAudio`, on by default; "some apps can't ship them"), #782 jump-back anchoring,
#759 software VOD residency. Thread also mentions DV P7→P8.1 and a DV→HDR10+ PR, and a user report of AetherEngine
timestamp issues at the end of a video that skip back several seconds at each video transition (watch our part handoff
and next-episode handoff for this).

Read native/apple/AGENTS.md first (engine lane rules; memory: openstream-apple-engine-lane). Work in the engine fork
on Dev-Mini (`~/Developer/openstream-build/AetherEngine-fork` → DevExt), never in the app tree except the pin.

## Do
1. Licence gate FIRST: identify LibTrueHD and LibDTSX (repos, licences, decoder provenance, patent notes). Write the
   finding to `design/engine/2026-10-15-object-audio-licences.md`. If either is not clearly shippable in an
   Apache-2.0 App Store app, plan to build with that trait OFF (channel bridge) and say so; the owner decides.
2. Rebase (or re-apply) our 22 fork commits — DVD menus (IFO/NAV/VM/SPU/menu player), engine-lab harness, VOD-cutter,
   AVIO Range-ignore, HEVC VUI colour, software seek/EOF fixes, remote ISO reader — onto the newest upstream release
   tag. Drop any of ours upstream already fixed (say which). Keep the clean-room DVD notes.
3. Run upstream's tests + our DVD/engine-lab tests + the aetherctl lab scoreboard before/after (no new regressions).
4. Push the rebased branch to cyberbanksy/AetherEngine as a NEW branch (keep engine-lab untouched) — Dev-Mini has no
   GitHub credentials: bundle on the mini, copy to the Studio, push from a clone there.
5. Pin the app to it (Package.swift + Package.resolved), adapt any API changes, and add the OpenStream playback check:
   TrueHD 7.1 Atmos and DTS:X fixtures (generate legal test tones if no sample exists; never commit commercial clips)
   report APAC/object audio on tvOS; E-AC-3/AC-3 unchanged.

## Gates
Engine tests + lab scoreboard; app serial Swift suite; iOS + tvOS builds with recompile greps; the four Release
(no add-ons) builds; `scripts/apple-license-check.sh` (ThirdPartyLicenses updated for any new library); E2E-iOS and
E2E-tvOS (known: Live AirPlay); DVD/ISO e2e cases. Everything through buildlock, foreground. No app commits.
Report per AGENTS.md §7 with the licence verdict at the top.
