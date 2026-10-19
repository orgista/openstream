# Live tab: Paramount+ Live layout pass (owner 2026-10-19 11:20, for tonight's submission)

Owner: "REA Paramount+ (live) section … added to oStream and submit it for App Store tonight." Branch `live-pplus`
from main b8ed703. Parent plan: specs/stabilize-2026-10-18.md. Time-boxed: ≤ 3 hours wall clock; stop and report
at the box even if items remain. Paramount+ Live is the reference for the phone Live tab's look and behaviour; our
Live failure handling (rows 44/46, inline "Can't reach <source>") and the removals (no import card) stay.

## REA first (≤ 25 lines in design/reference-apps/2026-10-19-pplus-live.md)
- `rea` MCP on `/Volumes/DevExt/dev/rea/targets/apk/paramount/com.cbs.ott.apk` (+ the mobile xapk if present):
  the Live tab's structure — top stage (player with channel name/program/progress), channel rail or list (card
  size, art, "on now" text, progress bar), category/filter bar, guide (how many rows visible, time header),
  behaviour on tap (inline play vs full screen), what shows while connecting. Prefer layout XML + strings over
  decompiled code; measure dp sizes. Owner screenshots, if the lead appends any, win.
- Compare ours on the iOS 18.6 owner sim (`7530ECB2…`, protected.py, `-OpenStreamMuteAudio YES`): screenshots of
  the Live tab at rest, after a tap, and the guide.

## Fix (the five most visible differences, layout/behaviour only — no new features, no new settings)
Candidates (confirm against the REA): stage proportions and the channel/program/progress line on it; channel
cards (logo size, on-now line, progress bar); category bar style; guide density (rows visible, time header);
tap behaviour consistent with P+ (inline on the stage, Full Screen a separate control — already ours).
Phone only; tvOS/Mac/visionOS untouched (`#if` guards). Keep every accessibility identifier the UI tests use
(`live.*`, `player.*`); if one must change, update the test with the owner's words quoted.

## Proof
- iOS 18.6 owner sim before/after screenshots of the three states, side by side with the P+ reference frames
  (from the APK resources / a P+ screenshot the lead appends); iOS 27 unchanged where glass applies.
- `swift test` compile lane; iOS build; testCrawlLive on the 18.6 owner sim once; code-anti-slop; zero-byte.
Builds/sims only on Dev-Mini via scripts/mini.sh (`OPENSTREAM_MINI_DEST='~/Developer/openstream-build/lanes/live-pplus'`);
FIFO locks; never kill other jobs (four lanes + a gate share the mini). No commit. Report: REA findings, the five
items (done/not), change (file:line), screenshot paths, gates, `git status --short`.
