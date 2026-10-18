# Round 4 fix jobs from the forensics and REA reports (2026-10-17)

Sources:
- design/qa/regression-forensics-2026-10-17.md (F#)
- design/reference-apps/2026-10-17-gui-rea-round4.md (G#)
- design/reference-apps/2026-10-17-infuse-stability-rea.md (I#)

Each item below traces to an owner complaint. Build nothing else from those lists without an owner pick (F §6).

Rules for every job:
- Branch from batch-1017b, in your own worktree.
- Read native/apple/AGENTS.md and the root AGENTS.md first.
- Compile and unit work goes through the compile lane:
  `OPENSTREAM_MINI_DEST='~/Developer/openstream-build/lanes/<branch>' OPENSTREAM_MINI_LANE=compile scripts/mini.sh ...`
- Simulator and device work uses the default FIFO lane:
  - own `-derivedDataPath ~/Developer/sim-dd-<branch>`
  - hold the lock only while a test runs
  - iPhone proof on the owner's iOS 18.6 sim 7530ECB2 (restore its data afterwards) and iOS 27 73E49263
  - tvOS proof on DevTV
  - never OfficePlus
- Every fix carries the report's measurable target as a test or a trace line.
- Run code-anti-slop on the diff before reporting.
- Never print signing identities.
- No commits.
- Report: Done / Not done / Gates / Evidence.

## S1 stability: disc and SMB I/O (branch stability1). Owner: "playback still fails on ISOs", slow discs.
- I1: open a disc image in bulk.
  - read the end-of-file anchor first, then the start
  - large reads; the reader window keeps its size across non-contiguous reads
  - persist the disc parse (DiscRecognitionCache) across launches, keyed by file identity + size + mtime
  - targets: cold open ≤ 2 s over SMB, warm ≤ 0.3 s, ≤ 10 range requests per disc open (trace count)
- I2: one SMB file handle per playback.
  - keep-alive range server
  - stream chunks as they arrive instead of collecting 4 MiB
  - positioned reads on one open handle
  - targets: first byte < 50 ms on the LAN, `smb opens` = 1 per session
- I3: short versus full buffering.
  - a short stall with ready packets draws nothing
  - count full reloads in the trace
- Proof:
  - John Wick 4 UHD ISO on DevPlus: Play → first frame ≤ 6 s; second open ≤ 2 s
  - a normal MKV over SMB plays and seeks
- Do not touch the AetherEngine pin (7.36 is held).

## S2 launch speed (branch launch-speed). Owner: slowness, "takes forever".
- F8: launch marks in the trace on every build: process start → first frame → first row → hero art.
- Move Top 10, recommendations and the Top Shelf publish out of the first 2 s.
- F11: decode the Top 10 store off the main thread; no synchronous file read inside Discover's body.
- Targets, on DevPlus and the 18.6 sim:
  - first frame ≤ 1 s
  - rows ≤ 2 s
  - launch cover gone ≤ 1.5 s
  - no hang mark > 250 ms on Discover, the title page or Settings › Sources
- Report before/after numbers.

## S3 GUI round 4a (branch gui-r4a). Owner: Apple TV "no trailers or sync through heros"; slop on the title page.
- G2: the tvOS hero keeps cycling while Play merely has focus. It pauses for 5 s after the last remote input, and while a
  cover or full screen is up.
- G3: crossfade between hero pages:
  - art 1.0 s
  - copy fades out then in
  - Reduce Motion = instant
  - no new scrim
- G12: title page clean-up:
  - remove the Accessibility glossary paragraphs and the "Episodes aren't available…" line
  - "More Like This" everywhere
  - delete the Release `print`
- G15: iPad/landscape trailer fits with no zoom.
- G16: rotating hero gets a white Play; its indicator is driven by the cycle.
- Proof: DevTV idle on Home 60 s, page advances ≥ 4 with focus on Play; frame capture shows no single-frame cut;
  before/after screenshots.

## S4 Live feel (branch live-r4, from live-narration ce4920e). Owner: Live "takes forever", "things take you forever".
- G4 zap coalescing: collect presses and tune once, 400 ms after the last; stop at the ends (no wrap); the logo and
  number stay visible while the target accumulates. Measure: 5 presses in 1 s → exactly 1 stream open (`live zap` trace).
- G5 tuning visual: keep the last frame (or the channel logo on black, no spinner, for the first 1 s); show a spinner
  only after 1 s; drop the "Connecting to X" line. Measure: no spinner frame when the first frame comes in < 1 s.
- G18 Live resume like Paramount+: resume the last channel only on the first Live entry per launch, and only if it was
  watched in the last 30 min; never re-arm on every tab visit. Measure: leave and re-enter Live on DevTV → no auto
  full screen.
- F12 `live first picture` marks: zap → first picture, logged per zap, so the owner's provider can be measured from
  the phone trace.
- Proof on DevTV and the iOS 18.6 sim, using the local fixture lineup (the owner's provider is unreachable from the mini).
