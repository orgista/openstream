# Finish the agent items in OWNER-TODO.md (owner 2026-10-09: "Finish the todo please, tomorrow hopefully everything is done")

Repo: /Volumes/Files/Projects/Code, Apps & Websites/Apps/OpenStream/native/apple (git root is OpenStream/). Read HANDOFF/AGENTS docs
there, OWNER-TODO.md (Open section) and verification-artifacts/owner-todo-triage-2026-10-09.md (rows marked TODO + "Top 10").

## Scope (in this order)
1. #19 credential-bearing cache copies + background resume data.
2. #35 iCloud deleted-source tombstones (no resurrection on merge) + tests.
3. #52 iOS 18 nav icons/large title readable on bright hero art; full-screen VoiceOver modality. Check on the iOS 18.6 sim
   "iPhone 15 Pro Max iOS18" (UDID 7530ECB2-CE38-4BC6-B7E6-D4B3BEDDF48D) with the owner config seeded (scripts/seed-sim.sh).
4. #53 subtitle switch mid-stream (sparse cues) — prove with a test; fix the engine path if it fails.
5. #21 remaining Live review findings, esp. multiview stream churn on layout change.
6. #4 Live Picture in Picture on iPhone/iPad (swipe home keeps playing). UI test testLiveFullScreenGoesToPictureInPictureOnHome
   exists. Use the physical iPhone DevPlus if it is unlocked; if locked, prove on the sim and leave the device check to the owner.
7. #34 engine fixes (seek/playback; truncated/interlaced/VC-1/AV1) with before/after measurements.
8. #44 Apple TV focus polish (season picker, sidebar, bright-art readability).
9. #56 Stremio add-on sweep remainder, Security-fix leftovers (Mythos 2026-10-07 item), Live slice 2 from
   specs/live-hero-redesign-2026-10-09.md + its Mythos review (Guide sheet, Vision focal crop) — as time allows.
OUT OF SCOPE: old iPhone/iPad full-test reports (#58, #59) — owner: "older iPhone and iPads are not considered atm".
Also out: Duo (after submission), anything that needs owner devices/accounts/App Store Connect.

## Rules
- All builds/tests/sims on Dev-Mini via scripts/mini.sh and ~/Developer/bin/buildlock.sh. Never on the Mac Studio. Sims launched
  with -OpenStreamMuteAudio YES. Mini disk is tight; clean DerivedData/xcresults you create.
- Another worker may build Android on the mini; buildlock serializes — just wait for the lock.
- No TestFlight/App Store upload. Never print secrets, provider URLs, logins, stream URLs. No git stash/checkout/reset; commit only
  your own changes, one commit per item with a clear message. Don't touch native/google-tv.
- Run the full Swift test suite before each commit (touch edited files first; SPM on the share can run stale code). Keep the
  test count >= 2989 and green.
- After each item: in OWNER-TODO.md mark it [x], add "**Closed 2026-10-10 (done, verified):** <evidence: commit, test, sim proof>"
  and move it under ## Done. If it needs the owner, leave it open and add one plain line saying exactly what they must do.
- Owner UI rule: no explainer text in the UI. SF Symbols, system look.
- Usage-aware: read /Volumes/Files/Projects/Infrastructure & Server/ServerPlus/Files/agent-state/usage-board.json before long steps.
- End with: done (commits), in flight, next, owner actions.
