# Working in `native/apple` as an agent — read all of it before your first edit

You were handed a task by the main session (Fable) or by the owner. Do that task, nothing else,
and report in the format at the bottom. Where this file and your task disagree, ask; do not guess.

## 1. The three commands (verbatim — no substitutions)
```
# GATE — run BEFORE and AFTER every change. NEVER plain `swift test` (default .build lands on the
# SMB share and corrupts). Expect "Test run with N tests in M suites passed"; note N/M in the report.
swift test --scratch-path "$HOME/Developer/openstream-build/main-merge-spm"

# If it prints "input file … was modified during the build": that is the share, not you.
# sleep 45 and run it again. If it ends with "freed pointer was not the last allocation" and no
# "Test run with" line: a test crashed the process — bisect with --filter, do not ignore it.

# Simulator builds (one at a time; only if your task asks for a build):
cd Apps && xcodebuild -project OpenStreamApps.xcodeproj -scheme "OpenStream tvOS" \
  -destination "id=B251C620-E3AD-4F9E-9911-EF8CBA6C7353" \
  -derivedDataPath ~/Developer/openstream-build/DerivedData-deploy-tvos build > /tmp/build.log 2>&1
#   iOS: scheme "OpenStream iOS", id=6A037503-AF3A-4A22-B900-CF6573B15FB1,
#        -derivedDataPath ~/Developer/openstream-build/DerivedData-uitests
```

## 2. The SMB share lies — the protocol, no exceptions
The repo is on an SMB share. Builds see stale files and stale directory listings.
- After editing: `touch <every edited file>`, `sleep 16`, THEN build. Then prove it:
  `grep -c "SwiftCompile normal arm64 Compiling.*<File>.swift" /tmp/build.log` must be ≥ 1 for
  every file you edited. "BUILD SUCCEEDED" without that line is not proof.
- Before reporting and before any commit: `find Sources Tests Apps -name "*.swift" -size 0` must
  print nothing. A new file went to 0 bytes on this share once; check yours.
- Write files with a normal write (heredoc / editor); never `>>` onto a file you have not read.

## 3. Never (these end the task — stop and report instead)
- Never upload to TestFlight/App Store, run `asc publish`, `asc builds upload`, `xcodebuild
  -exportArchive`, or `git push`. Never add a build to a TestFlight group.
- Never erase, delete, reset, or create simulators. The four persistent sims are: iPhone 16 Pro
  `6A037503…`, iPad `CC634933…`, Apple TV `B251C620…`, Vision Pro `F598603A…`. Boot ONE at a time.
  Never leave test data on them (a source, a download, a playlist you added — remove it).
- Never use Computer Use / screen control / osascript UI automation — the owner is using this Mac.
- Never create LaunchAgents, cron, routines, background workers.
- Never edit signing: `project.pbxproj` CODE_SIGN_*/PROVISIONING_PROFILE_*, entitlements,
  `Info.plist` keys, `ExportOptions*.plist`, anything under `~/.appstoreconnect`, `.p8` files.
  Never print key ids, issuer ids, tokens, passwords, or stream URLs with provider tokens.
- Never put a provider URL/token in the repo. Fixtures use `https://fixture.example/…`. Playlist
  URLs for tests come from the environment (`OPENSTREAM_TEST_M3U`), not from source.
- Never run more than one `xcodebuild` at a time; never run `swift test` concurrently with one.
- Never edit `AppleSMBRangeServer.swift`, `AppleSharePlay*.swift`, or the AetherEngine package
  checkout unless the task names them.
- Never commit. The main session reviews the diff and commits (as the owner, cyberbanksy).
- Uploads are the driver's job only, by the runbook in `HANDOFF-NEXT-SESSION.md §9`, after "ship N".

## 4. Owner UI rules (do not relitigate)
Stock Apple look. Nothing blue except the brand mark (accent #FF3366). No gradients, scrims or
dimming over artwork/video (one approved billboard fade). No explainer text in the UI. No scroll
indicators. Controls auto-hide. One captions control. No boxed icons on tvOS. No coloured label
text. Toggles are the classic iOS green switch. The tab bar is the system one per OS (Liquid
Glass on iOS 26) — no custom tab-bar paint. Downloads are automatic — no source picker.
Live view options are Provider Lineup and My Channels only. Trailers and intro fingerprinting are
tabled; chapter markers are approved.

## 5. Architecture traps (each one cost an hour)
- The app targets consume `Sources/OpenStreamApple` through the local SwiftPM package; new files
  are picked up automatically — but `#if os(tvOS)` files never compile in the SPM gate (macOS),
  so a tvOS-only change needs a tvOS build to prove it.
- `AppleTVLiveGuideScreen` and other tvOS screens have EXPLICIT inits: a new stored property must
  be added to the init too or the call site fails with "extra argument".
- A pushed SwiftUI page must carry its own `.task(id:)`; the parent's sleeps while covered.
- A lazy `List` hides off-screen rows from XCUITest — scroll before asserting.
- SwiftUI Form pickers are tapped through their VALUE button in UI tests, not the label.
- Match episode-row controls by identifier (`detail.episode.download`), not label — labels change.
- Awaiting `addStremio(manifestValue:)` with its default `client:` from inside `AppleSourceStore`
  crashes the task allocator; pass `client: manifestClient`.
- `simctl get_app_container` can return a stale container after a UI-test install; find the live
  one by mtime. The interaction trace is `<container>/Library/Caches/openstream-trace.log`.
- `#if DEBUG … #else …` — the `#else` branch only compiles in Release archives; reference-check it.
- Tests are Swift Testing (`@Suite`, `@Test`, `#expect`); pure policy types get pure tests.

## 6. Where to write things down — and nowhere else
The only living documents are `AGENTS.md`, `GUI-AUDIT.md`, `FEEDBACK.md`, `HANDOFF-NEXT-SESSION.md`,
`DELIVERIES.md`, and the references under `design/*.md`. Everything else is trash.
- `GUI-AUDIT.md`: tick the item you worked on (`[x]`/`[F]`/`[!]`) with what changed and how it was
  verified (gate count, screenshot, test name). No essays.
- `FEEDBACK.md`: append a short dated section written for the owner (plain words, no jargon).
  Sections older than two weeks get rotated into `FEEDBACK-ARCHIVE-*.md` by the tidy pass.
- Screenshots you must keep go under `design/<date>-<item>/` and are deleted once the GUI-AUDIT
  entry describes them; never into the tree root, never `scratch/`, never `*.log`.
- Do not create new markdown files, plans, proposals, or handoffs. If you think one is needed, put
  the content in the matching section of the documents above.
- Build scratch lives in `~/Developer/openstream-build/`: `main-merge-spm` + the DerivedData dirs +
  the last two builds' `.xcarchive`s. Older archives, `export-*` folders and worktrees are deleted by
  the tidy pass (`/openstream-tidy`, run at the end of every heartbeat).

## 7. Report format (return exactly this, under 60 lines)
```
## Done
- <item> — <files> — <one line on how>
## Not done / unclear
- <item> — <why>
## Gates run
- swift test … → pass N/M | fail (<one line>)
- xcodebuild <scheme> → recompiled: <files confirmed by grep> | BUILD FAILED (<one line>)
- zero-byte check → clean
## Diff
<git status --short -- . ; git diff --stat -- .>
## Notes for the reviewer
- <risky spots, assumptions, anything to spot-check, with path:line>
```

## 8. Skills — read the matching SKILL.md BEFORE writing that kind of code
They live in `~/.claude/skills/<name>/SKILL.md` (Claude Code loads them by name; agy needs
`--add-dir ~/.claude/skills`; codex reads them as files). Each is a checklist + references; the
references folder next to it has the details. Apply the one that matches, then do the task.

| When the task touches… | Read | Then |
|---|---|---|
| any SwiftUI view/modifier change | `swiftui-pro` | check the diff against its review list |
| a long `body`, inline side effects, view models, `@Observable` | `swiftui-view-refactor` | small dedicated subviews, MV over MVVM |
| jank, slow scroll, too many view updates | `swiftui-performance-audit` (refs: 8) | audit first, then fix |
| tvOS focus, `@FocusState`, `focusSection`, remote moves; iOS/visionOS focus | `swift-focusengine-pro` (refs: 31) | this repo's tvOS player/guide bugs were mostly focus |
| `async`/`await`, actors, `@MainActor`, `Task`, Combine sinks | `swift-concurrency-pro` | the store/coordinator/engine files are actor-isolated |
| tests (`@Suite`, `@Test`, `#expect`, traits, fixtures) | `swift-testing-pro` | no XCTest in the package; UI tests stay XCTest |
| WidgetKit, Live Activity (download activity), Top Shelf, watch complications | `widgets` (refs: 20) | Widgets/TopShelf/Watch targets under `Apps/` |
| background downloads, BGTaskScheduler, background URLSession | `background-execution` (refs: 12) | the offline download coordinator |
| VoiceOver labels/values/identifiers, Dynamic Type, accessibility audit | `ios-accessibility` (refs: 18) | every control needs a label; UI tests depend on identifiers |
| driving the simulators headlessly (tap, type, screenshot, app state) | `ios-simulator-skill` (refs: 41) | its erase/delete scripts were removed on purpose — never recreate them |
| App Store Connect via `asc` (builds, groups, crashes, ids, signing, release) | `asc-cli-usage` first, then `asc-build-lifecycle` / `asc-testflight-orchestration` / `asc-crash-triage` / `asc-id-resolver` / `asc-signing-setup` / `asc-xcode-build` / `asc-release-flow` | read-only use is fine; anything that uploads or assigns groups needs the owner's "ship N" |
| the web portal / landing page look, any new visual direction | `frontend-design` | one bold element, quiet everything else; stock Apple stays stock |
| posters, press images, social art | `canvas-design` (refs: 83) | brand: black, white, accent #FF3366, no gradients |
| App Store name/subtitle/keywords/description, listing audit | `aso` first; `vibe-aso` for keyword research + 50-locale metadata (its setup wants an ASC API key — use the existing `asc` login, NEVER paste a key) | French testers → fr-FR first |
| positioning, "why OpenStream vs Stremio/Infuse", messaging | `product-marketing` → then `copywriting` | write the context doc once, reuse it |
| TestFlight "What to Test", Reddit/TraceEnabled group posts, release notes | `launch` + `copywriting` + `social` | short, plain, no hype |
| pricing/tiers questions | `pricing` | owner decides; skill drafts |
| marketing plan / channel choice / measuring it | `marketing-plan`, `analytics` | drafts for the owner |
| **anything "slow"** — before touching code | `ios-performance-profiling` → pick the tool; `xctrace` → record/analyze/**compare** a trace headlessly (`scripts/trace_record.py`, `trace_compare.py`; templates on this Mac: App Launch, Time Profiler, Animation Hitches, SwiftUI, Allocations, Network) | measure first; a fix without a before/after trace is not done |
| app launch, time to first frame, work at startup | `ios-launch-performance` | our launch runs the library scan/group/metadata pass up front (2.6 / 4.9 / 7.5 s in traces) |
| "posters take time", spinners, blank shelves, perceived lag | `ios-perceived-performance` | progressive render + placeholders + the artwork disk cache |
| view invalidation, identity, body cost, scroll jank | `swiftui-performance` (plus the installed `swiftui-performance-audit`) | Discover detail is 5,225 lines; the guide grid renders 300 rows |
| task explosions, MainActor bottlenecks, actor hopping, cancellation | `swift-concurrency-performance` | stores/coordinators/engines are `@MainActor`; image cache is an actor |
| ARC/COW/dispatch cost in hot loops | `swift-runtime-performance` | M3U parse (25k lines), lineup projection, search ranking |
Not for this repo: the cloudflare*, wrangler, durable-objects, agents-sdk, sandbox-sdk, docker,
deployment, web-perf, turnstile skills — ignore them here. (`brand-guidelines` is Anthropic's own
brand and was not installed; write OpenStream's under `design/DESIGN-SYSTEM.md` instead.)
