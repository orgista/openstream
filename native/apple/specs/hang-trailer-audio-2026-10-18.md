# Main-thread hang: trailer audio session activated synchronously (owner tailspin 2026-10-18 15:13:40)

Branch `hang-trailer-audio` (worktree OpenStream-lanes/hang-trailer-audio), from main 5f7d7a0. Parent plan:
specs/stabilize-2026-10-18.md. Owner evidence: iOS Hang Detection tailspin from the owner's iPhone (iOS 18) on the
15:00 owner build; excerpt in design/qa/owner-hang-2026-10-18-151340.txt. Row: new checklist row 63 in
design/qa/iphone-feedback-checklist.md.

## What the tailspin shows
Main thread, 342 samples: 99 samples (~1 s) inside SwiftUI `PlatformViewChild.updateValue` →
`AppleYouTubeAutoPreview.updateUIView` → `ApplePlaybackSessionPolicy.prepareTrailerAudio(pressed:)` →
`AppleAudioSessionWorkQueue.shared.performSynchronously` → `DispatchQueue.sync` (asyncAndWait) on
"com.orgista.openstream.audio-session", which runs `AVAudioSession.setCategory` + `setActive(true)`. Those talk to
mediaserverd and can take hundreds of ms; doing them synchronously inside a view update stalls the whole UI.

## Fix (the behaviour, not the mechanism, is fixed)
- `prepareTrailerAudio` must never block the main thread. Activate the session on the audio-session queue
  asynchronously (or in a detached task) and let the trailer start; when the activation completes, apply the policy.
  A hero trailer is muted/ambient, so it can begin before the session is active; a pressed trailer (sound) may wait
  for the activation completion before unmuting, off the main thread.
- Keep the existing ordering guarantee the comment describes ("drain pending long-form preparation/deactivation
  before taking over"): the async work is enqueued on the same serial queue, so it still runs after the pending work.
- No synchronous `performSynchronously` / `DispatchQueue.sync` may be reachable from `updateUIView`, `body`,
  `onAppear` or any other main-thread view code for the trailer path. Check the other callers of
  `prepareTrailerAudio` and `AppleAudioSessionWorkQueue.performSynchronously` and list them in the report; fix only
  the trailer path, note the others.

## Proof
- Unit: a test that `prepareTrailerAudio` returns without waiting on the queue (inject a queue that blocks for 2 s;
  the call returns in < 50 ms) if the structure allows; otherwise explain why not.
- iOS 18.6 owner-profile sim `7530ECB2-CE38-4BC6-B7E6-D4B3BEDDF48D` (wrap in
  `python3 /Volumes/DevExt/dev/openstream-build/batch-1018a/protected.py <sim> <cmd…>`): open a title page with a
  trailer and the Discover hero trailer; the app's trace log (`appleTrace`, see AppleInteractionTrace) must show the
  trailer preparing with no `hang` lines; capture the main-thread with
  `xcrun simctl spawn <sim> log stream --predicate 'subsystem == "com.apple.UIKit" AND category == "HangTracer"'`
  or `--process "OpenStream iOS"` during the open and show no hang ≥ 250 ms. One screenshot of the trailer playing.
- `swift test` on the compile lane (full count), iOS build, code-anti-slop on the diff, zero-byte check.

## How to work
- Builds/tests/sims only on Dev-Mini: `OPENSTREAM_MINI_DEST='~/Developer/openstream-build/lanes/hang-trailer-audio'
  OPENSTREAM_MINI_LANE=compile scripts/mini.sh 'swift test 2>&1 | tail -5'`; drop the LANE variable for simulator
  work. Touch edited files before test runs. Never build on the Studio.
- Do not commit; no git stash/checkout/reset; nothing outside the trailer audio path. Report: cause, change
  (file:line), callers list, proof paths, gate results, `git status --short`.
