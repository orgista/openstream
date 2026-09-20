Live skip-back fix — verification, 2026-09-20
=============================================
Harness: two local ffmpeg HLS origins on 127.0.0.1:8099 (recipe in
HANDOFF-NEXT-SESSION.md §7e). No provider URL, no credentials, nothing external.
Test: Tests/OpenStreamAppleTests/AppleLiveSeekIntegrationTests.swift, run against
a real AVPlayer through NativePlaybackEngine.

live-seek-lab.log     the run's own record (both cases)
before-skip-back.png  frame at the live edge, 84.25 s
after-skip-back.png   frame after one skip-back, 74.25 s

The picture is ffmpeg's `testsrc` pattern, which burns its own clock into the
frame: it reads 1152 before and 1142 after. Ten seconds came off, on screen.
