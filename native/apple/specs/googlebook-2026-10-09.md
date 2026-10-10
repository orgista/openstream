# OpenStream for Googlebook + "Made for desktop" badge (owner 2026-10-09)

Owner ask: "Build a Googlebook version of OpenStream, verify e2e, make sure it earns the 'made for desktop' badge."

## Repo / rules
- Android app: /Volumes/Files/Projects/Code, Apps & Websites/Apps/OpenStream/native/google-tv (Gradle). Read OpenStream/HANDOFF.md
  and native/google-tv docs first. One Play app (com.orgista.*): TV AAB vN + mobile AAB vN+1 (see release policy in HANDOFF/README).
  Googlebook ships in the MOBILE/large-screen AAB, never a separate app id.
- ALL builds/emulators run on Dev-Mini (`ssh dev-mini`) through `~/Developer/bin/buildlock.sh`. Android SDK at
  /Volumes/DevExt/android/sdk, AVDs in /Volumes/DevExt/android/avd (ANDROID_AVD_HOME) — `oBrowser_Googlebook` already exists;
  oBrowser's Googlebook e2e lives in /Volumes/DevExt/obrowser-e2e (reuse its approach). Copy sources over ssh (tar | ssh) or a clone in ~/Developer;
  never build on the Mac Studio. Mini disk is tight (~27 GB free): clean your build outputs when done.
- No Play upload, no signing-key changes, nothing uploaded externally. Never print secrets/provider URLs/logins.
- Don't touch native/apple Swift code (other agents). Commit only your own files in native/google-tv (+ this spec dir), small commits.

## Steps
1. Research (web) the current Google Play desktop/large-screen quality requirements: the "Made for desktop" badge (Googlebook /
   Android desktop) and the large-screen app quality tiers. Write the checklist with sources into
   native/google-tv/docs/googlebook-desktop-quality.md (create docs/ if needed; keep it short).
2. Audit the app against every item (resizable windows + freeform resize without restart/state loss, all orientations,
   keyboard nav incl. Tab/arrows/Enter/Esc/Space play-pause/shortcuts, mouse + trackpad (hover states, right-click context menu,
   scroll wheel, no touch-only gestures), stylus if listed, multi-window, large-screen layouts (no stretched phone UI),
   input focus, `android:resizeableActivity`, no `screenOrientation` locks, camera/uses-feature not required (touchscreen
   required=false), media key handling, picture-in-picture, drag & drop if listed, etc.).
3. Implement the gaps. Keep the TV (leanback) build unchanged — verify the TV build still assembles and its tests pass.
4. E2E on the Googlebook AVD (and a resizable/desktop window mode): install, first run, add a source (use the test fixtures the
   repo already has — no owner secrets in logs), browse, open a title, play a video, keyboard-only pass, mouse-only pass,
   resize the window during playback, rotate, multi-window. Save screenshots + a REPORT.md under
   native/google-tv/verification-artifacts/googlebook-2026-10-09/ with a pass/fail per badge item.
5. Run the existing Android unit tests (and scripts/android-device-smoke.sh if it applies).
6. Final report: what was built, badge checklist pass/fail with evidence, commits, anything that needs the owner
   (e.g. a Play Console declaration). Write "done / in flight / next" if you must stop early.
