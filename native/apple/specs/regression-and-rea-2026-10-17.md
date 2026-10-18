# Why the app got worse since build 15, and REA round 4 (2026-10-17)

Owner, 2026-10-17: "the app used to be decent and now it's kinda in a worse place and we gotta find out why."
References: the Apple TV app, Netflix and Paramount+ Live for the GUI; Infuse for stability.

Shared rules for all three jobs:
- Reports only. Do not edit Sources/, Apps/ or Tests/, and do not commit; the lead turns findings into fix jobs.
- No simulator or device. Compile-only work on Dev-Mini goes through `~/Developer/bin/buildlock-compile.sh`.
- REA follows the root AGENTS.md `rea` rules and native/apple/AGENTS.md §4.2. Never copy code or assets, never bypass
  DRM, never upload targets. IPAs are FairPlay-encrypted, so use the Mac apps, the dyld shared cache in
  `/Volumes/DevExt/dev/rea/targets/dsc-macos27.0.1-arm64e` (TV.app frameworks), the APKs in `targets/apk`, and
  public web bundles.
- Read the existing reports in design/reference-apps first, and only add what is new or deeper.
- Every finding gives evidence (commit SHA and file:line, or the binary/symbol/string it came from), the effect the
  owner sees, and a concrete fix that is measurable (timing, size, count, behaviour).
- Never print secrets, tokens or signing ids.

## Job R1: regression forensics (build 15 `ad66774` → main)
Find which changes made the app worse. Sources:
- `git log ad66774..main`
- the owner's complaints in OWNER-TODO.md (Open and Done since 10-12)
- design/qa/iphone-feedback-checklist.md (on the iphone-jank branch)
- design/qa/owner-recording-2026-10-15-transcript.srt
- the phone traces under design/qa

For each complaint area, find the commit(s) that introduced it and say whether the current fix branches cover it.
Areas: hero cycle and trailers, the title-page header, Live, launch time, scroll jank on iOS 18, ISO/disc
playback, metadata speed, Settings sprawl, and things the owner "never asked for".

Also look for systemic causes:
- features added without an owner request
- tests that asserted the wrong thing
- fixes verified on iOS 27 only
- merges that undid earlier fixes

Output: design/qa/regression-forensics-2026-10-17.md, with a ranked list of fixes (what to revert, what to fix, what
to delete) and the process changes that would have caught each one.

## Job R2: GUI REA (Apple TV app, Netflix, Paramount+ Live)
Compare screen by screen: Home hero and its cycle, the title page (header, trailer, wordmark, buttons, episodes),
Live (guide, categories, channel switching, the mini player), Library and Search.

For each screen, give the reference app's measurable rules (layout sizes, spacing, timings, transitions, what is
deliberately absent) and OpenStream's current behaviour, file:line.

Output: design/reference-apps/2026-10-17-gui-rea-round4.md, ending in a prioritised gap list sized as fix jobs.

## Job R3: stability REA (Infuse)
Infuse.app plus the Infuse-arm64 engine in targets. Cover:
- how playback starts (probe, open, first frame)
- buffering and network stalls
- SMB/NFS reads and caching
- ISO/BDMV/VIDEO_TS handling
- error recovery and retries
- threading off the main thread
- memory limits
- what it shows while it waits

Compare with OpenStream's AetherEngine bridge, AppleDiscPlayback, the SMB client and the player views, file:line.
Use the traces and failed e2e runs as evidence of our own instability.

Output: design/reference-apps/2026-10-17-infuse-stability-rea.md, with a top-10 stability fix list.
