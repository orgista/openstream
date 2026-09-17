# Handoff for the next session (any model) — OpenStream Apple, 2026-09-14 09:30

Read `AGENTS.md`, then the tail of `FEEDBACK.md` (tables R*, S*, U*, V*, W* and the "UX/UI audit and Apple TV rework plan" section). This file is the operational state; delete it when the items below are done and folded into FEEDBACK.

## Machines and rules
- Mac Studio (32 GB) rebooted 2026-09-14 ~01:00 from RAM exhaustion. Caps: at most 2 editing agents, 1 xcodebuild/swift build at a time, boot only the simulator being verified, no headless Chrome alongside builds.
- Simulators (never erase): iPhone 16 Pro `6A037503-AF3A-4A22-B900-CF6573B15FB1` (owner left it in landscape), iPad `CC634933-18CE-4D3B-AECB-5021AC653A71`, Apple TV `B251C620-E3AD-4F9E-9911-EF8CBA6C7353`, Vision Pro `F598603A-4DDB-4A06-9CE0-4CF1AE042FE0`. Owner's real sources live on them.
- Deploy: `~/Developer/openstream-build/deploy-all-v2.sh [ios tvos visionos]` (default ios tvos; boots a sim only while installing and shuts it down again unless it was already booted). The old deploy-all.sh boots all four sims at once and pushed the 32 GB Studio to 0.1 GB free (RealityKeyboard crash on the Vision Pro sim, 09:27) — do not use it. Full tests: `swift test --scratch-path "$HOME/Developer/openstream-build/main-merge-spm"` (539 tests / 30 suites green at 09:10). iOS xcodebuild must use the iPhone UDID as destination (other UDIDs no-op).
- Headless tvOS navigation: `xcrun simctl spawn <ATV> defaults write com.orgista.openstream OpenStreamVisionScreen -string <settings|discover|library|live|add-live|add-catalog|…>` then relaunch; delete the key afterwards. The simulator tap tool addresses the PORTRAIT frame on a landscape iPad: landscape (X, Y) → tap (834 − Y, X).
- Unraid workers (work Claude account, Fable): `~/Developer/openstream-build/unraid/run-worker.sh <name> <prompt-file>`; outputs/markers in `Infrastructure & Server/ServerPlus/Files/agent-state/openstream-workers/<name>.out|.done`. They cannot compile Swift — run the gates on the Mac after they finish.
- Codex: `gpt-reserve` works headlessly (`CODEX_HOME=~/.codex-headless codex exec -m gpt-reserve …`); luna/astra are capped until Sep 19. agy print mode: `agy -p "<prompt>" --effort high --dangerously-skip-permissions`.
- Usage: personal Claude account is for orchestration, gates and verification only; long jobs go to the work account (unraid), Codex reserve, agy or OpenRouter.

## In flight right now
- Unraid worker `manifests` (add-on manifest URL edge cases, U7–U10) and `webmgmt` (portal end to end, S6–S8): when `.done` appears, run `swift build`/`swift test` on the Mac, fix compile issues, deploy, verify.
- Owner-verified items still pending on the Apple TV after the 09:15 deploy: Live tab (rebuilt, guide-first; the "Live" page title is still drawn — audit task 3 removes titles on tvOS), Top Shelf content, icon parallax, SMB Test Connection message, add-on logos.

## Queue (audit plan, in order) — dispatch one at a time to the unraid work account, gates on the Mac
1. Audit task 3 tvOS chrome pass (no page titles on tab roots; header inside content on pushed pages; drop the `.offset(y: -88)` glyph overlay; remove global `.tint(.white)` on tvOS).
2. Task 5 tvOS title page layout (U2), then task 4 tvOS Discover metrics.
3. Task 7/8 tvOS Settings split view and forms (U1 title overlap is the same bug family; an earlier settings/subtitle agent was cut off — check AppleSettingsViews.swift/AppleSourcesSettingsView.swift for partial edits first).
4. V1 Discover/Library toggles (like Show Live tab); V3 wordmark shown together with the artwork (text title only during trailer playback).
5. More Like This ranker (an agent was cut off; check for AppleRecommendationRanker.swift and finish), R2/R10/R11 verification on the phone.
6. Audit task 1 (tvOS UI-test target with XCUIRemote) and task 12 (regression script) once fewer agents run.
7. iPhone landscape rework: an agent finished builds but not screenshots — verify `design/iphone-landscape-rework-*.png` and the notch coverage during trailer playback (V2).

## Owner questions outstanding (from the audit)
Brand assets for portal/Top Shelf; Live tab order on Apple TV; keep "Other sources" only on failure; tvOS Settings split view vs list; tab bar on iPhone portrait title pages.
