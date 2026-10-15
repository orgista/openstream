# Working in `native/apple` as an agent — read all of it before your first edit

You were handed a task by the main session (Fable) or by the owner. Do that task, nothing else,
and report in the format at the bottom. Where this file and your task disagree, ask; do not guess.

## 0. Where builds run (owner rule 2026-10-05 — overrides anything below)
Builds, `swift test`, xcodebuild, simulators and device runs happen on the Mac mini **Dev-Mini**, never on the
Mac Studio (it has no Xcode). Edit here; run every heavy command through `scripts/mini.sh '<command>'` — it syncs this
tree to dev-mini:~/Developer/openstream-build/src/native/apple and runs the command there under the shared build lock.
The gate below becomes: `scripts/mini.sh 'swift test --scratch-path ~/Developer/openstream-build/spm 2>&1 | tail -30'`.
xcodebuild DerivedData on the mini: `~/Developer/openstream-build/dd-<platform>`. Test device: iPhone 16e DevPlus
(UDID 00008140-000809A82E89801C) on the mini — prefer it over creating simulators. Read
/Volumes/Files/Projects/AGENTS.md "Apple builds and tests run on the Mac mini" and its concurrency gate.

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
- **Toolchain (2026-09-22):** Xcode 27.0 (27A266a), Swift 6.4, is `/Applications/Xcode.app` and is the ship
  toolchain. Floors are unchanged (iOS/tvOS 18, macOS 15, watchOS 11, visionOS 2). Never accept "Update to
  recommended settings" (keeps `objectVersion 71` / `LastUpgradeCheck` so an older Xcode can still open the project).
  After a Release build or archive run `scripts/sdk-floor-check.sh <.app|.xcarchive>` — it must exit 0.
- **Long jobs:** run every build, test and archive in the FOREGROUND. A headless worker that backgrounds a job and
  ends its turn kills it (`** BUILD INTERRUPTED **`). If a step can exceed 10 min, `nohup` it with a done-marker
  and poll the marker in foreground loops. Never create scratch files inside this tree — use `/tmp`.

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
- Never erase, delete, reset, or create simulators. The persistent sims on Dev-Mini (owner cleanup 2026-10-14, 24
  default sims deleted) are: iPhone 18 Pro iOS 27 `73E49263…` (E2E-iOS), iPhone 18 Pro Max iOS 27 `2E61439B…`,
  iPhone 15 Pro Max iOS 18.6 `7530ECB2…` (owner's imported setup), DUO foldable `CA2CCA73…`, iPad Pro 13" `8939801C…`,
  Apple TV 4K `F2107E8F…` (E2E-tvOS), Apple Watch Series 12 `4ABCBF60…`, Vision Pro `46B2DEDC…`. Boot ONE at a time.
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
- Never commit, `git add`, `git stash`, `git checkout --`, `git reset`, or `git clean`. Other agents'
  uncommitted work lives in this tree; a stash/pop or checkout would take it with yours. To test "without
  your change", reason from the diff or run only your own test suite — never move files around.
- Never create files or folders outside the paths your task names (no `scratch_store`, no `REPORT.md`);
  use `/tmp` for scratch.
- Uploads are the driver's job only, by the runbook in `HANDOFF-NEXT-SESSION.md §9`, after "ship N".
  Before any upload, every line of `SHIP-CHECKLIST.md` must pass (owner rule 2026-09-28).

## 4. Owner UI rules (do not relitigate)
Stock Apple look. Nothing blue except the brand mark (accent #FF3366). No gradients, scrims or
dimming over artwork/video (one approved billboard fade). No explainer text in the UI. No scroll
indicators. Controls auto-hide. One captions control. No boxed icons on tvOS. No coloured label
text. Toggles are the classic iOS green switch. The tab bar is the system one per OS (Liquid
Glass on iOS 26) — no custom tab-bar paint. Downloads are automatic — no source picker.
Live view options are Provider Lineup and My Channels only. Trailers and intro fingerprinting are
tabled; chapter markers are approved.


### 4.1 Design references (owner, 2026-09-18 15:40)
Design every screen against these, as a blend: **Home/Discover = Netflix** (billboard hero, dense
poster rows with tight spacing, titles under posters, Continue Watching with progress on the
artwork, Top 10 numerals); **Live = Paramount+** (video pinned at the top, edge to edge, channel
list with logos and what's-on-now under it, guide secondary, search as an icon); **Player and
overall feel = the Apple TV app** (transport layout, scrubber with times, info/captions/audio menus,
chapter and skip affordances, quiet chrome that hides together). On iPhone the app is portrait-only
except the full-screen player, which follows the device orientation and also plays in portrait.

### 4.2 How other apps do it: REA (owner, 2026-10-11)
When the owner asks for an app function, check how the reference apps build it before designing ours. Every agent
has the `rea` MCP ([morluto/rea](https://github.com/morluto/rea) 6.4.0, pinned) and the `reverse-engineer-anything`
skill; the server runs on Dev-Mini (`ssh -T dev-mini ~/Developer/bin/rea-mcp.sh`; CLI:
`ssh dev-mini '~/Developer/bin/rea-mcp.sh cli <command> …'`). Engines: Ghidra 12.1.4 (native), JADX headless 0.7.1
(Android).
- Targets on the mini, under `/Volumes/DevExt/dev/rea/targets/`: Apple TV app (`/System/Applications/TV.app`),
  `Infuse.app` (8.5.6, from the Studio; `Infuse-arm64` slice for Ghidra), `Plex.app` (desktop 1.115), `apk/com.netflix.ninja.apk` (Netflix, Android TV)
  and `apk/paramount/com.cbs.ott.apk` (Paramount+, Android TV). APK signers were checked (Netflix, Inc. and CBS
  Interactive, plus Google Play's stamp); re-check with `apksigner verify --print-certs` when replacing one.
- Learn the behaviour (when, how long, which states, what the remote does), then write our own code. Never copy their
  code, strings, art or assets; never bypass DRM, sign-in or encryption; never run or install the downloaded APKs;
  never upload a target or REA output anywhere.
- Tips from the first run (2026-10-11): search strings first (e.g. Apple TV `com.apple.hls.skip`), then follow xrefs;
  Ghidra rejects universal binaries — use `targets/Infuse-arm64` (made with `lipo -thin arm64`), and on Infuse narrow
  string searches still hit the 600 s limit, so read its `Localizable.strings` and symbol names first; Plex's logic is
  the bundled web client (`Plex.app/Contents/Resources/web-client`, `analyze_javascript_application`); Netflix keeps its
  player logic in the 81 MB `libnetflix.so`, so the Java side says little; apktool and ripgrep are installed.
  First report: `design/reference-apps/2026-10-11-skip-intro-next-episode.md`.
- Findings go in `design/reference-apps/<date>-<feature>.md` (one page per feature: per-app behaviour, the evidence
  location, and what OpenStream should do).

## 5. Architecture traps (each one cost an hour)
- **Add-on distribution boundary:** `OPENSTREAM_ADDONS` is defined for Debug in the app project and
  SwiftPM module/tests. App Store Release builds leave it undefined (owner 2026-10-02: TestFlight
  builds for internal testers KEEP add-ons — archive them with the override below; never submit that build to App Review). Manifest,
  catalog, meta, stream and add-on subtitle transports and their add/edit UI are compiled out.
  Saved unsupported source payloads are ignored and retained in storage and backups.
  For internal TestFlight, sideload or the Mac Developer-ID download, append the single xcodebuild
  setting `SWIFT_ACTIVE_COMPILATION_CONDITIONS='$(inherited) OPENSTREAM_ADDONS'` (equivalently,
  `SWIFT_ACTIVE_COMPILATION_CONDITIONS = $(inherited) OPENSTREAM_ADDONS` in a local xcconfig).
  For the developer sweep or SwiftPM Release, use `-Xswiftc -DOPENSTREAM_ADDONS`.
  Never pass either override to an App Store submission archive. Run
  `bash scripts/check-no-addons-in-release.sh` before shipping (SHIP-CHECKLIST.md §4).
  **Gate for any change that touches code under `#if OPENSTREAM_ADDONS` or its `#else`:** build
  `-configuration Release CODE_SIGNING_ALLOWED=NO` for iOS, tvOS, visionOS and macOS. Debug, SwiftPM and E2E all
  define the flag, so they cannot see a no-add-ons break (two shipped unseen in 947fdc1/e4409ca, fixed 6e92441).

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
Public source exports follow `scripts/release/public-export.sh`'s exclusion list: never add owner notes to the public repo.
The only living documents are `AGENTS.md`, `GUI-AUDIT.md`, `FEEDBACK.md`, `HANDOFF-NEXT-SESSION.md`,
`DELIVERIES.md`, `OWNER-TODO.md` (the owner's feedback checklist, asked for 2026-09-26), and the
references under `design/*.md`. Everything else is trash.
- **If a driver dispatched you** (your task says "Report: AGENTS.md §7"), do NOT edit any markdown —
  the driver verifies on the simulators and writes the records. The two bullets below are for a
  standalone session with no driver.
- `GUI-AUDIT.md`: tick the item you worked on (`[x]`/`[F]`/`[!]`) with what changed and how it was
  verified (gate count, screenshot, test name). No essays.
- `FEEDBACK.md`: append a short dated section written for the owner (plain words, no jargon).
  Sections older than two weeks get rotated into `FEEDBACK-ARCHIVE-*.md` by the tidy pass.
- Screenshots you must keep go under `design/<date>-<item>/` and are deleted once the GUI-AUDIT
  entry describes them; never into the tree root, never `scratch/`, never `*.log`.
- Do not create new markdown files, plans, proposals, or handoffs. If you think one is needed, put
  the content in the matching section of the documents above.
- Build scratch lives in `~/Developer/openstream-build/`: `main-merge-spm` + the three
  `DerivedData-deploy-{ios,tvos,macos}` dirs + the last two builds' `.xcarchive`s +
  `ExportOptions*.plist` + the signing material. Nothing else belongs there. A fourth DerivedData
  dir is a bug, not a convenience.
- **Retired artifacts are archived, not deleted.** The tidy pass moves older `.xcarchive`s,
  `export-*` folders, worker logs/specs, screenshot piles and media fixtures to
  `/Volumes/OSArchive/` (`archives/ exports/ logs/ specs/ ui-artifacts/ fixtures/`) — a 4 TB
  case-insensitive APFS external. Hot build paths NEVER move there: it is ~15x slower on the
  small-file metadata churn that dominates Swift builds (measured 2026-09-21), and AGENTS.md §1
  hands out the internal paths verbatim. No symlinks, ever.
- **Nothing secret goes on `/Volumes/OSArchive`** — it is unencrypted, and that is only safe
  because of this rule. Private keys, `openstream.keychain-db`, `*.mobileprovision`, `*.m3u`,
  `pbxproj-backup-*` and `ExportOptions*.plist` stay on the FileVault-encrypted internal disk.
  Old gate logs can contain `player_api.php?username=…&password=…` traces, so filter by CONTENT
  and not just by filename before archiving anything.
- Guard every write to the drive on the mount sentinel, because an unclean eject leaves an empty
  stub directory behind and a re-attach can land at `/Volumes/OSArchive 1`:
  `[ -f /Volumes/OSArchive/.osarchive-ok ] || { echo "OSArchive not mounted — STOP"; exit 1; }`
  Copy with `ditto`, verify, then delete — never `mv` across volumes.

## 7. Report format (return exactly this, under 60 lines — as your final message, NEVER as a file in the tree)
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
They live in `~/.claude/skills/<name>/SKILL.md`. Every worker loads them **by name** — the iOS/Swift
set below is symlinked into `~/.claude-work/skills` (work Claude and Muse), `~/.codex/skills`,
`~/.codex-headless/skills` and `~/.gemini/config/skills` (agy), verified 2026-09-22. If you do not
see e.g. `swiftui-pro` in your skill list, stop and say so. Each is a checklist + references; the
references folder next to it has the details. Apply the one that matches, then do the task, and
check your diff against that skill's review list before you report.

| When the task touches… | Read | Then |
|---|---|---|
| any SwiftUI view/modifier change | `swiftui-pro` | check the diff against its review list |
| SwiftUI, App Intents, UIKit modernization, tests — Apple's own guidance (first-party, exported from Xcode 27 on 2026-10-14) | `apple-swiftui-specialist`, `apple-swiftui-whats-new-27`, `apple-app-intents-specialist`, `apple-app-intents-whats-new-27`, `apple-uikit-app-modernization`, `apple-modernize-tests`, `apple-device-interaction`, `apple-audit-xcode-security-settings` | Apple's word wins over third-party skills where they disagree |
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
