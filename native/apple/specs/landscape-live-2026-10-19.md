# Row 74: testLandscapeHidesTheTabBarAndPortraitBringsItBack fails first time in every batch gate (2026-10-19)

iOS 18.6 owner-profile sim, full E2E-iOS: the test fails on the first run ("channel did not open full-screen")
in batch-1018b, 1018c and 1018d, and passes when rerun alone. Logs: dev-mini:/Volumes/DevExt/dev/openstream-build/batch-1018d/logs/e2e18-iOS-tests.log
(and …/batch-1018c/, …/batch-1018b/). Branch `landscape-live` (worktree OpenStream-lanes/landscape-live) from main b8ed703.

Diagnose first, then fix the right thing:
1. Read the three failure logs + attachments: what state is the Live screen in when the test rotates? Is the
   player still connecting (the owner provider gives 0 channels — row 45 — so the fixture source is used), is a
   failure line showing (rows 44/46 inline "Can't reach <source>"), is a previous test's state leaking (which test
   runs just before it in the full suite; does it leave the player open or a sheet up)?
2. If the app is at fault (e.g. rotating while the channel is still connecting never enters full-screen, or the
   inline failure line steals the tap), fix the app and prove it with the test run inside the full-suite order
   (run the preceding test + this one together, 3×) on the 18.6 owner sim. If the test is at fault (timing, a
   stale element, an assumption about the first run), fix the test without checking less than before, with the
   owner evidence quoted (rows 44/46/45 context), and prove it the same way.
3. Gates: swift test if app code changed (compile lane), iOS build, code-anti-slop, zero-byte check. Builds/sims
   only on Dev-Mini via scripts/mini.sh (`OPENSTREAM_MINI_DEST='~/Developer/openstream-build/lanes/landscape-live'`);
   wrap owner-sim runs in `python3 /Volumes/DevExt/dev/openstream-build/batch-1018a/protected.py <sim> …`. FIFO
   locks; never kill other jobs. No commit.
Report: cause (with the log lines), change (file:line), proof paths, gates, `git status --short`.
