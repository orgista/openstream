# Handoff — OpenStream Apple (`native/apple`) — read this FIRST, every session

Written 2026-09-17 by the overnight session, at the owner's request: *"leave explicit
instructions for sonnet and opus."* Follow these literally. When something below is
violated, the usual result is a false finding or a false "fixed" — both have happened here.

Read `AGENTS.md` next, then the **tail** of `GUI-AUDIT.md` and `FEEDBACK.md` (the current
state is at the bottom of each, newest last).

## 0. The three commands you will run most, exactly as written

```
# The gate. NEVER plain `swift test` (the default .build lands on the SMB share and corrupts).
swift test --scratch-path "$HOME/Developer/openstream-build/main-merge-spm"
# Expect: "Test run with 1007 tests in 101 suites passed" (as of 2026-09-17 Codex continuation). Run it BEFORE
# and AFTER every change. If it prints "input file … was modified during the build", that is
# the SMB share, not you — sleep 30–45 s and run it again.

# tvOS build (sim UDID below). iOS uses the iPhone UDID; other UDIDs silently no-op.
cd Apps && xcodebuild -project OpenStreamApps.xcodeproj -scheme "OpenStream tvOS" \
  -destination "id=B251C620-E3AD-4F9E-9911-EF8CBA6C7353" \
  -derivedDataPath ~/Developer/openstream-build/DerivedData-deploy-tvos build

# Headless navigation to any screen after install:
xcrun simctl launch <UDID> com.orgista.openstream -OpenStreamVisionScreen <screen>
```

## 1. The SMB share lies about builds — the protocol, no exceptions

The repo is on an SMB mount. Xcode can print **BUILD SUCCEEDED without recompiling the file you
just edited**, and a screenshot then "proves" old code. This produced false results more than
once tonight. So, every time you edit a source:

1. `touch` every file you edited.
2. Sleep **≥ 12 s** before `xcodebuild`, **≥ 30–45 s** before `swift test` (more files → longer).
3. Redirect the build log to a file and **grep it**: you must see
   `SwiftCompile normal arm64 Compiling\ <YourFile>.swift` for *each* file you changed.
   A bare "BUILD SUCCEEDED" is not proof. If the line is missing, touch again and rebuild.
4. Only then `simctl install` and screenshot. If a build **failed**, do not install or
   screenshot — you would be photographing the previous binary.

The SPM gate builds **macOS**. Any file guarded `#if os(tvOS)` (e.g. `AppleTVLiveGuideView.swift`)
is invisible to it. A green gate does not mean tvOS compiles — always run the tvOS build too.

## 2. Simulators — persistent, never erased, no test data

| Device | UDID |
|---|---|
| iPhone 16 Pro | `6A037503-AF3A-4A22-B900-CF6573B15FB1` |
| iPad | `CC634933-18CE-4D3B-AECB-5021AC653A71` |
| Apple TV (1080p) | `B251C620-E3AD-4F9E-9911-EF8CBA6C7353` |
| Vision Pro | `F598603A-4DDB-4A06-9CE0-4CF1AE042FE0` |

- **One simulator booted at a time, one build at a time, at most 2 agents.** 32 GB Studio.
  Shut one down before booting the next (`xcrun simctl shutdown <UDID>`).
- The owner's **real sources** live on them. Never erase, never add fixtures to them.
- After a fresh install on tvOS wait **≥ 13 s** before screenshotting a routed screen; 9 s
  landed on Discover instead of the pane.
- The debug key `OpenStreamVisionScreen` **persists in defaults and survives reinstall**. If a
  route stops landing, `xcrun simctl spawn <UDID> defaults read com.orgista.openstream
  OpenStreamVisionScreen` and `defaults delete` it. Reading the app's `.plist` file is NOT
  reading its defaults — only `simctl spawn … defaults read` is truthful.
- `-OpenStreamVisionScreen` values: `discover library live detail episodes play first-run
  settings channels playback-settings subtitle-languages metadata server-downloads trakt
  watch-providers privacy storage about add-files add-live add-catalog network-share
  web-management`. Works on iOS, tvOS and visionOS (the fence was removed 2026-09-17).
- `simctl` has **no tap** and **no orientation** API. For taps/rotation/keyboard use the UI test
  targets (`OpenStreamiOSUITests`, `OpenStreamTVUITests`) and export attachments with
  `xcrun xcresulttool export attachments --path <x.xcresult> --output-path <dir>`.
- Flipping a persisted setting with `defaults write` works for **some** keys and is silently
  ignored for others: the live **package** key (`openstream.settings.live.package.v1`, values
  `premierGuide|everything|custom`) works on tvOS; the **tab** toggles
  (`openstream.settings.live.enabled.v1` etc.) were ignored on iPhone. If you write a default,
  **prove it took** from the screenshot (e.g. the tab bar lost a tab) before trusting the
  capture, and put the key back afterwards.
- The Mac's Simulator has *Connect Hardware Keyboard* ON. That suppresses the on-screen
  keyboard; the soft-keyboard UI test skips itself in that state. Don't file "no keyboard" as
  an app bug.
- `xcrun simctl ui <ATV> content_size|appearance|increase_contrast` → **unsupported** on tvOS.
  A tvOS Dynamic Type pass cannot be run headlessly. iOS: `content_size
  accessibility-extra-extra-extra-large` works; **set it back to `large`** when done.

## 3. Verification discipline — the rules that stopped false findings

- **Look at the capture.** Open the PNG and read it. Downscaled montages and pixel probes
  alone produced ~8 false findings; several times "the eye" was wrong and the measurement
  right, and twice the reverse.
- **Confirm every capture-based finding a second, independent way** — usually by reading the
  code path that draws it. Report neither until both agree.
- **Measure, don't guess**: leftmost-lit-pixel per band, ink spans, luminance behind text
  (PIL is installed; scratch under the session scratchpad, never in the repo).
- A green test is not evidence the app does something. Sixteen `static func`s and a whole
  feature (`AppleLibraryTVView`, 418 lines) are tested and never called (see GUI-AUDIT.md
  "Tested but never called"). Before trusting a ✅, `grep` for a caller outside `Tests/`.
- When a child ignores its parent's alignment, the bug is in the **child** (e.g.
  `.frame(maxWidth: .infinity)` on a button). Three container-level "fixes" made it worse.
- When a fix "does nothing", check for **stale binary** (§1) before theorising.
- `#expect` messages must include the actual value so a failure reads on its own.
- After a fix, re-screenshot **both** states (on/off, default/large type, phone/iPad). Two fixes
  tonight needed a second pass that only the capture revealed.

## 4. Architecture facts that bit us (don't rediscover them)

- **The Live tab is two views.** `AppleMediaSourceViews.swift` draws iOS/visionOS (in an
  `#else`), Apple TV draws `AppleTVLiveGuideScreen` in `AppleTVLiveGuideView.swift`. A change
  to one is not a change to the other.
- **`AppleTVLiveGuideScreen` has an explicit `init`** (it supplies `metrics` itself). Adding a
  stored property is not enough — add the parameter to that init or the call site fails with
  "extra argument".
- Settings panes all title through `appleSettingsPageTitle` (tvOS draws `TVPageHeader`; iOS is
  an **inline** navigation title, deliberately — large titles collided with section headers).
  `appleSettingsPane` wraps content in the 900 pt tvOS form column; empty states must sit
  **outside** it or they centre on the column, not the page.
- Brand buttons use `RoundedRectangle(cornerRadius: 30)`, not `Capsule` (a capsule becomes an
  ellipse when the label wraps at accessibility sizes and the text falls outside it).
- Toggles: `AppleBrandToggleStyle` (accent switches) is applied **at the iOS root only**. On
  tvOS a Toggle is an On/Off row — tinting it paints the label pink. Do not add it there.
- The channel guide: `AppleLiveChannelSnapshot.minimumLineupMatches = 8` (Premier Guide falls
  back to "everything" below it) and `maximumDisplayedChannels = 300` (display cap; the parser
  still ingests up to `AppleIPTVClient.maximumChannels = 25_000`). Don't collapse the two.
- tvOS: toolbar items always draw a box; `.navigationTitle` draws over the page; `Form`
  uppercases section headers but `List` does not; a `.plain` button draws a focus platter.
- iOS type-checker timeouts in `AppleDiscoverView` / `AppleMediaSourceViews`: **extract** a
  sub-expression into a computed property or `func`; moving a block out (not nesting deeper)
  is what compiles.

### 4b. Traps found 2026-09-17 (UI tests, downloads, tracing)
- **`simctl get_app_container` can return a STALE container.** After a UI-test install the app's data
  container id changes; the old path still exists. To find the live one:
  `find ~/Library/Developer/CoreSimulator/Devices/<UDID>/data/Containers/Data/Application -name openstream-trace.log -mmin -10`.
  Reading the old container's trace and concluding "nothing happened" cost an hour.
- **The interaction trace is now ON in UI tests.** `-OpenStreamTrace YES` used to be ignored
  (`object(forKey:) as? Bool` on the String "YES"); `isEnabled` now uses `bool(forKey:)`. The trace
  file is `<container>/Library/Caches/openstream-trace.log`, timestamps are ms since launch (grep
  `^0ms ` for launch markers). Download phase changes are traced as `network download <state>` and
  failures as `failure download …`; progress ticks are NOT traced (throttled by `State.phaseName`).
- **Downloads are automatic — never add a source picker back.** Owner decision, verbatim: "no I don't
  want a download from I want it to be automatic". `startDownload(episode:)` → coordinator walks the
  ranked plans. The row's feedback is `AppleEpisodeDownloadIndicator` (pure, tested) → ring + label.
- **Match episode rows by identifier, not label.** `detail.episode.download` is the accessibility
  identifier of every row's ↓; its label changes ("Download …" → "Preparing …" → "Downloading …, 4%"
  → "Downloaded …") and also changes once metadata resolves. A label predicate "vanishes" mid-test.
- **UI-test downloads are real and leave residue.** The detail route is a real series (9/11, 2.8 GB
  episodes). Always cancel through "Download Options" and check
  `<container>/Library/Application Support/OpenStream/Offline/manifest.json` is `{}` afterwards. If a
  test left an mp4, remove the manifest entry and the file with the app terminated — the sims are
  never erased.
- **Series pages hid download failures** until today (`downloadFailureNotice` was `EmptyView()` for
  series). It now shows for series too. Don't "clean it up" back to hidden.
- **The SMB trap hits the gate too**: "input file … was modified during the build" from `swift test`
  means sleep 45 s and rerun — the second run passed every time today.

- **Default arguments that construct objects, evaluated inside a `@MainActor` async store
  method, can crash the task allocator.** `addStremio(manifestValue:)` has
  `client: AppleManifestClient = AppleManifestClient()`; calling it with the default from inside
  `AppleSourceStore` crashed `swift test` with "freed pointer was not the last allocation"
  (signal 6), deterministically, and the whole gate died with it. Pass `client: manifestClient`.
  If the gate ever ends with that message and no "Test run with" line, bisect with `--filter`
  per test — it took five variants to find; the log names only the tests in flight.
- **`swift test` output filters**: never `grep -v trace` on the gate — file paths and test
  names contain it. Grep for `Test run with|error:|Expectation failed|freed pointer` and always
  check the exit code.
- **UI tests: SwiftUI Form pickers** are tapped through their *value* button ("Xtream Account"),
  not the "Type" label (StaticText, not hittable). `sources.live.playlistText` is the M3U editor's
  identifier, `sources.live.chooseFile` the file button.
- **Pasted playlists** live at `<Application Support>/OpenStream/Playlists/pasted.m3u`, addressed
  by the stable URL `openstream-playlist://local/pasted.m3u` (`AppleLocalPlaylistStore`). The
  IPTV client reads that scheme from disk; `AppleIPTVEndpointPolicy.normalize` passes it through.

- **A source file went to 0 bytes on the share after the gate had passed** (`AppleBuildChannel.swift`,
  2026-09-17 ~11:00, and the commit captured the empty file). Debug builds never noticed because the only
  references sit in `#else` of `#if DEBUG`; the Release archive did. Before any archive or commit:
  `find Sources Tests Apps -name "*.swift" -size 0` must print nothing, and `git show HEAD:./path | wc -c`
  must not be 0 for a file you created. Rewrite from the transcript if it happens again.
- **Release archives on this Mac use MANUAL signing pinned in the pbxproj** (tvOS app, Top Shelf,
  visionOS app; identity "iPhone Distribution", profiles by name — see `ExportOptions-*-b11-export.plist`).
  Debug stays Automatic. Automatic signing has no Xcode account here and the API-key path
  (`-allowProvisioningUpdates -authenticationKey…`) fails "Authentication failed: bearer token".
  Archive with `-derivedDataPath ~/Developer/openstream-build/DerivedData-deploy-<platform>` and
  `CURRENT_PROJECT_VERSION=<n>`; export with `destination export`; upload with
  `asc publish testflight --app 6807530757 --ipa <ipa> --platform TV_OS|VISION_OS|IOS --group "Internal,TraceEnabled" --submit`.
- **Widgets signing fixed 2026-09-17**: owner assigned `group.com.orgista.openstream` to
  `com.orgista.openstream.widgets`. New App Store profile `5ZP6L8ACKH`, named
  `OpenStream App Store widgets 2026-09-17`, UUID `9b677921-be29-4e96-b798-92cb82791049`,
  contains the group and is installed in both current Xcode and legacy profile directories.
  The Watch target has no App Group entitlement and works with its existing profile.

### 4d. Build 11/12 (iOS), 13 (existing platforms), and macOS 1 — how
- Owner update 2026-09-17: start native macOS at **1.0 (1)** and bring its features up to the
  current other-platform baseline. This supersedes the older requirement to start Mac at 13 or
  keep its build number identical to the other platforms. Both Mac target configurations and the
  existing local Debug app already report 1.0 (1), minimum macOS 15. No number change is needed.
  Parity audit found a release blocker: `OpenStreamRootView.tabs` has no macOS conditional branch,
  so the main TabView has no tab contents on Mac despite compiling. This remains unfixed; see
  FEEDBACK.md's macOS baseline audit. Starting a baseline does not itself publish an upload.
- Live release catch-up 2026-09-17: iOS 11 (`ec6ec0bc-db74-4005-bbe1-b3c3d163f7c1`) is VALID
  and IN_BETA_TESTING internally and externally, assigned to Reddit + Internal + TraceEnabled.
  iOS 12 (`a173faf4-49ce-42f3-9de2-c07ff664e0d6`) is also VALID / IN_BETA_TESTING internally
  and externally, assigned to Internal + TraceEnabled. Both deliveries are complete; actual
  installation on the owner's iPhone has not been observed. See DELIVERIES.md.
  visionOS 12 is VALID / IN_BETA_TESTING for Internal + TraceEnabled; visionOS 11 also has Reddit.
  Native macOS has no uploaded builds. CLI `asc web app-groups assign` supports future assignments
  with an Apple Account web session; the API-key profile is a separate authentication mechanism.
- Worktrees on local disk (no SMB lies): `~/Developer/openstream-build/wt-b11` = commit 3055de2
  (build 11 code, tracing off), `wt-b12` = bf6988e (build 12 code, tracing on by TestFlight receipt).
  Both have iOS/Widgets/Watch Release configs pinned to manual signing (uncommitted, build-only).
  Export options: `ExportOptions-ios-b11-export.plist` (profiles by name). Archive from
  `<worktree>/native/apple/Apps` with `-scheme "OpenStream iOS" -destination generic/platform=iOS
  -derivedDataPath ~/Developer/openstream-build/DerivedData-archive-ios CURRENT_PROJECT_VERSION=11|12`.
- The first iOS 11 upload was rejected because the embedded Watch app had no icons. Fixed only
  that packaging in both worktrees and main: Watch asset catalog reuses the existing opaque 1024px
  app icon, is included in Watch resources, and is selected in Debug/Release build settings.
  Rebuilt/re-exported with the SAME authorized number; Apple accepted the corrected build 11.
  Archive checks validate all three bundle signatures/build numbers, the embedded widget profile,
  Watch Assets.car + CFBundleIcons metadata, and iPhone/iPad support (iOS 18+).
  Final local artifacts: `OpenStream-iOS-b11-icons.xcarchive/.ipa` and
  `OpenStream-iOS-b12-icons.xcarchive/.ipa` under `~/Developer/openstream-build/`.
  Fresh gates for historical snapshots: build 11 = 981 tests / 94 suites; build 12 = 985 / 96.
  `main-merge-spm` was last used for the build-12 worktree, so its lower test count is not lost
  main-branch tests; main still has the newer 1007/101 suite. Logs: `codex-ios11-*`, `codex-ios12-*`.
- iOS 11 → groups Reddit + Internal + TraceEnabled (matches tvOS/visionOS 11); iOS 12 → Internal +
  TraceEnabled (matches 12). Both are owner-authorized on 2026-09-17 ("ship 11 & 12 for iOS").
- **macOS for 1**: the account has NO Mac signing assets (certs: only Apple Development +
  iOS Distribution; no Mac profiles; no local Mac identities). Needed: an "Apple Distribution"
  (DISTRIBUTION) or MAC_APP_DISTRIBUTION cert + MAC_INSTALLER_DISTRIBUTION cert (CSR from this
  Mac's keychain), a MAC_APP_STORE profile for com.orgista.openstream, sandbox entitlements on the
  "OpenStream macOS" target, and the macOS platform on the App Store Connect app record. Do the
  prep, then ask before creating certificates.

### 4e. ORCHESTRATION — ACTIVE since 2026-09-17 15:30 (owner: "from here on out it's your job to make sure things get done without taking much of your own usage")
The driver session (Fable, effort high) decides, specs, verifies and commits. **Workers do the typing.**
Any LLM can run this loop; nothing here needs the driver's memory.

**Rungs, in the order they are exhausted (one at a time, never idle):**
| # | Worker | Command (spec = a file under `~/Developer/openstream-build/specs/`, never in the repo) | Use for |
|---|---|---|---|
| 1 | **agy** (Gemini 3.1 Pro) | `agy -p "$(cat spec.md)" --mode accept-edits --dangerously-skip-permissions --add-dir "<tree>" --add-dir ~/.claude/skills --effort high --print-timeout 20m` (Gemini has only `low`/`high` — `medium` exits 1 with "invalid model selection") | mechanical edits, tests, fixtures, docs |
| 2 | **Claude fast window** | `claude -p "$(cat spec.md)" --model opus --effort xhigh --permission-mode acceptEdits --add-dir "<tree>" --output-format text` (headless; burns the subscription — only when rung 1 is out) or the `implementer` Agent (Sonnet) from inside a session | multi-file Swift work that needs Xcode/sim knowledge |
| 3 | **codex** (GPT‑6) | `codex exec -C "<tree>" -s workspace-write "$(cat spec.md)"` — ALWAYS pass `-s`; `-s read-only` for audits | same as 1 when agy is out or the Claude 5‑h bar is past ~90% |
| 4 | **everything** | `or-review-remote implement` / `review` (GLM‑5.2, free tier), Sonnet/Opus subagents | last |
Read-only questions go to rung 1/3 first (`--effort low` / `-s read-only`), never to the driver's context.

**The loop (per queue item; the driver runs it, a worker executes step 3):**
1. `git status --short -- .` — anything modified by the other agent (Codex desktop) is off-limits; pick another item if it collides.
2. Write the spec (template below) to `~/Developer/openstream-build/specs/<item>.md`. ≤3 files per spec; split bigger items.
3. Run the rung. Capture stdout to `~/Developer/openstream-build/specs/<item>.out`.
4. Verify yourself, always: `git diff --stat -- .` touches only the allowed files; `find Sources Tests Apps -name "*.swift" -size 0` empty; gate passes and N/M went up if tests were asked; UI/tvOS changes get the build + screenshot step from AGENTS.md §1–2 (driver does the LOOK).
5. Commit only the worker's files (`git add <paths>`), record in GUI-AUDIT/FEEDBACK, run `/openstream-tidy`.
6. If the worker went off-spec: `git checkout -- <files>` and re-run on the next rung with the failure quoted in the spec. Never patch its work by hand from the driver — that is the usage you are saving.

**Spec template (every line filled):**
```
Repo: /Volumes/Files/Projects/Code, Apps & Websites/Apps/OpenStream/native/apple — read AGENTS.md first, all of it.
Files you may change: <exact list>. Nothing else. Do not create files except the tests named below.
Change: <behaviour, exact; policy table or acceptance criteria>
Tests: <file + what they assert> (Swift Testing)
Gate: swift test --scratch-path "$HOME/Developer/openstream-build/main-merge-spm" — run before and after; report N/M.
Build/screenshot: none — the driver does it.
Forbidden: uploads, commits, git push, sims, signing, secrets, Computer Use, touching files not listed.
Report: AGENTS.md §7, under 60 lines, as your final message — do not write a report file. Then stop.
```
**Model presets:** driver = Fable 5.1 / effort high (pinned for the session — /model, /fast, /effort mid-session cold-reads the whole context); implementation sessions = Opus 5 + /fast / xhigh; subs = Sonnet; agy high (its only other level is low); codex high.
**Progress check-in:** the 15-minute Desktop heartbeat (no cloud routine, no LaunchAgent). Each firing: 1–3 lines, which rung ran, N/M, what's next.

### 4f. Dispatching work to a model — audit of 2026-09-17 15:10 (tested, all three rungs answer)
**Pick the model by the job, then give it the brief.** Every worker reads `AGENTS.md` first — it
now holds the commands, the SMB protocol, the never-list, the UI rules, the traps and the report
format. Your task message adds only what is specific to the task.

| Job | Use | Why |
|---|---|---|
| Judgment, design, owner questions, anything with a screenshot to LOOK at | this session (Fable; `/fast` when told) | only it sees images and owns ship/commit |
| Read-only lookup / audit / "where is X decided" | `agy -p … --effort low` (Gemini 3.1 Pro, ~14 s) or `codex exec -s read-only` (GPT‑6, ~16 s); `investigator` (Sonnet) only when the answer needs the Claude tool set — it cost ~19k tokens for a grep | free-ish rungs first; sip the subscription |
| Mechanical implementation with a written spec (≤3 files) | `agy -p "<spec>" --mode accept-edits --dangerously-skip-permissions --effort medium --print-timeout 20m` | rung 1 of the ladder (§4e) |
| Same, when agy is out or it needs Xcode/sim knowledge | `implementer` (Sonnet; `model:"opus"` for hard multi-file) | reads AGENTS.md, runs the gate, reports the diff |
| Same, when the Claude 5‑hour bar is past ~90% | `codex exec -C <tree> -s workspace-write "<spec>"` | rung 3; ALWAYS pass `-s` — the desktop config is `danger-full-access` |
| tvOS focus / SwiftUI review of a diff | Sonnet + the `swift-focusengine-pro` / `swiftui-pro` skills | cheap, specialised |

**Task-message template (paste, fill every line — a blank line is a bug):**
```
Repo: /Volumes/Files/Projects/Code, Apps & Websites/Apps/OpenStream/native/apple — read AGENTS.md first.
Files you may change: <exact list>. Do not touch anything else.
Change: <exact behaviour, or the policy table / acceptance criteria>.
Tests: <which suite/file; Swift Testing style>.
Gate: swift test --scratch-path "$HOME/Developer/openstream-build/main-merge-spm" (before and after; report N/M).
Build/screenshot: <none | scheme + sim UDID + what to grep in the log>.
Forbidden: uploads, commits, git push, sims erase/create, signing, secrets, Computer Use (see AGENTS.md §3).
Report: AGENTS.md §7 format, under 60 lines.
```
**Shared tree:** the owner's Codex desktop session ("Astra") edits `native/apple` live and can ship
(it uploaded iOS 11/12 on 2026-09-17). Before every edit: `git status --short -- .` and read any
foreign diff; commit ONLY your own files; never `git add -A` here; never revert what you did not
write; if a file you need is already modified by the other agent, say so and stop.

### 4c. Skills and `asc` (installed 2026-09-17 — use them, don't reinstall)
- 18 skills live in `~/.claude/skills/<name>/SKILL.md` and load automatically in Claude Code
  (`Skill` tool by name). For agy pass `--add-dir ~/.claude/skills`; codex reads them as files.
  The task→skill map is in `AGENTS.md §8`; the rule is *read the SKILL.md before writing that
  kind of code*. What each one is for in THIS repo:
  - `swiftui-pro` — review list for any view change (stock look, modifiers, Observation).
  - `swiftui-view-refactor` — when a `body` is long or a view owns side effects (Discover detail
    view is 4,000+ lines; extract, don't grow it).
  - `swiftui-performance-audit` — Live guide grid, 300-channel lists, poster shelves.
  - `swift-focusengine-pro` — tvOS focus (player overlay, Skip Intro, guide rail, settings rows);
    most tvOS defects this month were focus.
  - `swift-concurrency-pro` — `AppleSourceStore`/coordinators/engines are `@MainActor`; the
    default-argument-inside-async crash (§4b) is the kind of thing it catches.
  - `swift-testing-pro` — package tests are Swift Testing; pure policy types get pure tests.
  - `widgets` — Widgets/TopShelf/Watch targets, the download Live Activity.
  - `background-execution` — offline download coordinator, background URLSession.
  - `ios-accessibility` — labels/identifiers the UI tests key on (`detail.episode.download`,
    `sources.live.save`, `channels.add`, `player.skipIntro`).
  - `ios-simulator-skill` — headless sim driving; `simctl_erase.py`/`simctl_delete.py` removed
    (persistent sims). `idb` Python client is NOT installed; use `xcrun simctl` + XCUITest.
  - `asc-*` (8) — `asc-cli-usage` first; `asc-crash-triage` for TestFlight crashes
    (`asc testflight crashes list --app 6807530757`); `asc-signing-setup` for the Widgets App Group
    step; `asc-xcode-build` / `asc-release-flow` for archives — but uploads only on "ship N".
  - UX/UI + marketing (installed 2026-09-17, vetted, scripts stripped): `frontend-design`,
    `canvas-design` (anthropics/skills); `aso`, `launch`, `product-marketing`, `copywriting`,
    `pricing`, `social`, `marketing-plan`, `analytics` (coreyhaines31/marketingskills); `vibe-aso`
    (Kronop — keyword research + localized metadata; its ASC-key wizard must reuse the `asc` login).
    The `ui-ux-pro-max` plugin (design-system, brand, banner-design, slides, ui-styling) is also
    installed. Task→skill rows are in `AGENTS.md §8`. Not installed: `brand-guidelines` (it is
    Anthropic's brand), the ASO screenshot skill (needs a Gemini MCP key — owner decision).
  - Performance (installed 2026-09-17 16:00, vetted): `xctrace` (phillco — Python wrappers around
    `xcrun xctrace`: record, analyze, export, compare; the only skill with scripts, all read-only
    against the sim), `ios-performance-profiling`, `ios-launch-performance`,
    `ios-perceived-performance`, `swiftui-performance`, `swift-concurrency-performance`,
    `swift-runtime-performance` (Livsy90 — prose + references, no scripts). Audit verdict per skill:
    profiling = which tool for which symptom + signposts/MetricKit (we have none); launch = the
    startup scan/group/metadata pass; perceived = the poster complaint; swiftui = the 5k-line detail
    view and the guide grid; concurrency = MainActor stores; runtime = the M3U/lineup hot loops.
    Rule from AGENTS §8: nothing is "faster" without a before/after trace from `xctrace`.
  - Tidy: `/openstream-tidy` (project skill at `/Volumes/Files/Projects/.claude/skills/openstream-tidy`)
    is the constant clean-up — run it at the end of every heartbeat; it never deletes another agent's
    in-flight files and asks before anything over 1 GB or outside the build scratch.
  - Ignore here: cloudflare*, wrangler, durable-objects, agents-sdk, sandbox-sdk, docker,
    deployment-patterns, web-perf, turnstile-spin.
- `asc` (brew) is installed and authenticated: profile **"OpenStream"**, team `2VQ74PD5YG`, app id
  `6807530757`. Proof: `asc apps list --bundle-id com.orgista.openstream`. The key lives in the
  keychain and in `~/Developer/openstream-build/asc_lib.py`; NEVER print key ids/issuer/p8 in chat.
- Crash reports from TestFlight: `asc testflight crashes list --app 6807530757` (asc-crash-triage
  skill). Uploads: `asc builds upload` / `asc publish testflight` — ONLY after the owner says
  "ship"/"push (n)". Build 11 is still blocked on signing (Xcode account session or manual profile
  pinning) and the App Group tick for the widgets/watchkitapp bundle ids.

## 5. Owner rules — do not relitigate, do not ask again
- **SHIPPING (owner, 2026-09-17, after I pushed 12 unasked): nothing goes to TestFlight without an
  explicit "ship N" for that exact build number; all platforms go up on the same build; when there
  are changes, ASK "I made some changes — should I push them?" and wait.** Adding an existing build
  to another group is also a push. Current plan: iOS 11 and iOS 12 are authorized (to catch iOS up);
  13 waits for go/no-go on existing platforms. Owner subsequently chose **macOS native build 1**
  as its separate starting baseline (see 4d); it has not been uploaded.

- **Tab bar is the system one, per OS (owner 2026-09-17)**: iOS 26 floating glass bar, iOS 18 the
  classic bar. No custom tab-bar styling, no compatibility opt-out. (This supersedes "no Liquid
  Glass" for the tab bar only; everything else keeps the stock-but-not-glass rule.)
- **Live view options are Provider Lineup and My Channels only** — "Your Regional" is removed by
  owner decision; do not bring it back.
- **The owner drives the iPhone simulator through Codex computer-use while you build.** Installing
  or launching on `6A037503…` can interrupt them; prefer the UI-test runner (it reinstalls anyway)
  and keep sessions short. Trace files from their sessions land in the app container too.


- **NEVER upload to TestFlight/App Store unless the owner says "ship"/"push (n)"/"upload (n)".**
  Build locally. **The App Store Connect API key is on this Mac** — key id, issuer and `.p8` in
  `~/Developer/openstream-build/asc_lib.py` and `~/.appstoreconnect/private_keys/`; it works (never
  print its values). Bundle ids `com.orgista.openstream.widgets` / `.watchkitapp` were registered
  and App Store profiles created + installed on 2026-09-17 (UUIDs in
  `~/Developer/openstream-build/ExportOptions-b11.plist`). Caveat: the API cannot assign the
  specific App Group to a new bundle id — both new profiles carry
  `com.apple.security.application-groups = []`. If an archive fails on that entitlement, the fix
  is a 30-second portal step (Identifiers → the bundle id → App Groups → tick
  `group.com.orgista.openstream`), then regenerate the two profiles.
- **Credentials**: never type, echo, print or commit them. The SMB "Movies" password is never
  used. IPTV stream URLs with path tokens are replaced with `https://fixture.example/…` in any
  fixture (see `Tests/OpenStreamAppleTests/Fixtures/french-generalistes.m3u`).
- No LaunchAgents, cron, routines, workers or "helper scripts" on this Mac. Chat follow-up only.
- UI: stock Apple look; **no gradients/scrims** except the one approved billboard fade; nothing
  blue but the brand mark (accent is `#FF3366`); no Liquid Glass; no explainer text (one line
  max, and only when needed); no scroll indicators; one captions control; controls auto-hide;
  no boxed icons on tvOS; no coloured label text.
- Tabled until the owner says otherwise: trailers, intro fingerprinting. Chapter markers are
  approved.
- Small increments, one item at a time. If blocked, say so plainly and move on.
- Netflix IPA is layout inspiration only — never assets, fonts or branding.
- Commits are as **cyberbanksy** to the **orgista** org; the Apple work goes to its own repo
  (`OpenStream>Apple`). Pushes currently fail (805 MB `design/` committed) — owner item.

## 6. Where to write things down

- `GUI-AUDIT.md` — tick `[x]` checked / `[F]` fixed / `[!]` defect found; append a dated
  section per pass with **measurements**, not impressions. Correct a wrong tick in place and
  say why.
- `FEEDBACK.md` — a dated prose entry the owner reads: what changed, what was verified and how,
  what is on him. Say what you did *not* do and why.
- This file — update the "state" below when you finish a unit of work.

## 7. State as of 2026-09-17 20:40 (newest first)
- Orchestration ACTIVE (§4e). Worker (agy) landed today: watch-trace throttle (39573de), artwork disk
  cache (75108d6), metadata disk cache for details/episodes/previewAssets (ebd6115, 62988cf), prefetch
  API + policy (f26ba0e), launch snapshot + 10-min skip, tvOS guide laziness (−71 MB), iOS guide row models, tvOS minute tick. Gate 1036 / 108. Running: read-only web-portal audit.
  Parked: prefetch view hooks (`specs/artwork-prefetch.md`) until
  Codex releases AppleDiscoverView.swift (open since 16:28; Codex also started
  `design/2026-09-17-iphone-native-ux/`). Gate 1030 / 105.
- Skills: UX/marketing (11) + performance (7) installed and mapped in AGENTS.md §8. Tidy skill live.
- (Codex continuation, kept verbatim:)
- Build 12 source publication completed at owner's explicit request: private
  `orgista/openstream-apple`, main + tag `build-12`, commit `4a7c402`. Isolated checkout
  `~/Developer/openstream-build/publish-apple-b12`; 986/96 tests and unsigned iOS Release build pass.
  Configuration-only publication differences (catalog sanitization, automatic signing, shared
  schemes/version stamps/test fixture) are in its DELIVERIES.md. Newer development work stays local.
  Cloud now uses `orgista/openstream-apple`. Apple Build Checks enabled; four platforms passed
  run 5 (`3a431b39-00a5-47b7-8b72-891a435db678`) at `ba066e3`, which fixes iOS ActivityKit
  isolation errors found in run 4. Build-12 tag unchanged; TestFlight workflow remains paused.
  No new TestFlight binary. Current simulator UI fixes are newer local development changes.
- iOS 11 and 12 are delivered and their en-US TestFlight notes are now populated and read-back
  verified. See DELIVERIES.md; older signing/upload blockers below are historical.
- Owner's build-note policy (September 17): write concise, platform-specific “Added…” / “Fixed…”
  notes from the exact shipped snapshot, with one useful testing request. Apply the article-writing
  and marketing copy-editing skills. Include only verified user-visible changes; no raw commit
  messages, Android changes in Apple notes, unshipped features, test counts or generic hype.
  Build 12 adds default diagnostic logging; its other features are inherited from 11. Use
  `asc builds test-notes update` and read back the locale before calling notes delivered.
- Xcode Cloud audit: Default runs 1–3 (September 1) all failed before compilation because commit
  7a76d8d9 lacked `native/apple/Apps/OpenStreamApps.xcodeproj`. The workflow points to
  `orgista/openstream`; its Android “Last Commit” text is not TestFlight release notes.
  The separate TestFlight workflow has zero runs and only an iOS TEST action. Neither workflow
  was changed or rerun. Cloud repair needs the intended repository, branch and project path aligned
  with an approved published Apple snapshot; local iOS 11/12 delivery does not repair Cloud.
- Chapter markers: finished the interrupted Aether → playback protocol → overlay wiring.
  Duration events re-evaluate intro eligibility; `.idle` clears the per-item skip. A chapter
  metadata update does NOT reset a skip. Aether public `stop()` already clears `mediaChapters`
  (pinned engine line 4954); don't infer item identity from changed chapter arrays.
- Skip Intro no longer covers captions/scrubber: the action stack reserves the measured bottom-bar
  height. tvOS Down from the surface / Up from the scrubber reaches Skip Intro; auto-hide does not
  steal its focus. iPhone and Apple TV tests played a generated MPEG-2 MKV and proved a 50-second
  seek (captured at 0:52) and button removal. Screenshots: `design/2026-09-17-chapters/`.
  All changes remain uncommitted and unshipped; 13 still needs the owner's go/no-go.
- Final verification: `swift build` and 1007/101 gate pass; iOS/tvOS Debug builds and chapter UI tests
  pass; visionOS Simulator and native macOS Debug builds pass with `CODE_SIGNING_ALLOWED=NO`.
  macOS is buildable locally; distribution signing and runtime review are still separate work.
- Verification traps: UI-test schemes build ONLY their runner, not the app. Build the app, inspect
  SwiftCompile lines, boot the intended simulator, install explicitly, THEN run its UI-test scheme.
  `TEST_RUNNER_OPENSTREAM_CHAPTER_FIXTURE_URL` enables the new opt-in tests; test media is outside
  the repo under `~/Developer/openstream-build/chapter-fixture/`. FFV1 is unavailable in the bundled
  decoder; the MPEG-2 fixture works. The existing DEBUG `OpenStreamVisionPlaybackURL` launch route
  now works on all Apple platforms through Add Files. No source is saved. Tests write resume entries;
  fixture-only entries were removed after shutdown, and the temporary localhost server was stopped.
- Orchestration used `CLAUDE_CONFIG_DIR=~/.claude-work claude -p` with file tools only. Claude added
  six lifecycle tests; Codex corrected its mistaken stop/chapters assumption before accepting the
  patch. Initial AGY runs hit a headless read denial, then a 180-second timeout on a 97,774-byte
  prompt in Pro High / plan mode. Follow-up diagnosis: silent authentication succeeds; model
  generation continues without a final answer. Pro High and Pro Low both repeated analysis on a
  23,672-byte one-file review and were explicitly stopped. Flash Medium completed that review in
  94.3 seconds (33,705 thinking tokens); its two duration findings are not accepted patches.
  A focused 3,475-byte lifecycle invariant check on Flash Low completed successfully in 2.7 seconds.
  For bounded AGY checks use `--model gemini-3.8-flash-low --effort low --sandbox
  --disable-slash-commands --output-format stream-json --print-timeout 90s --print <prompt>`.
  Supply only relevant excerpts and explicit checks; omit `--mode plan`. Inspect the final JSON
  `result.status == SUCCESS` and nonempty response, plus stderr for permission denials. Broader
  audits may use Flash Medium and a longer ceiling, but must still be audited independently.
  Global AGY model, trust and permission settings were not changed. Evidence is under
  `~/Developer/openstream-build/codex-agy-diagnostic-*`. AI Council completed with
  `--providers ollama --ollama --ollama-model Qwen2.5:7b
  --synth-provider ollama --mode fast --timeout-seconds 90 --no-context --no-oss-fallback`.
  Its claimed concurrent chapter-read race was rejected: the read/recompute is synchronous on MainActor.
  No OpenRouter call, commits, TestFlight operations, signing changes, or certificates.
- Mormon Wives fixed by title-match ranking (AppleStremioTitleMatch; trace `candidates for …`).
  Tab bar is the system one. Channel Manager redesigned. Gate 999 / 99. Everything since 12 is
  local (13 candidates); iOS 11/12 catch-up is now delivered; macOS build 1 still needs signing.
- Live HLS-behind-bare-URL fix + guide limits (991 / 97). Build 12 (trace) tvOS in Internal +
  TraceEnabled, visionOS uploading; build 11 (non-trace) also in Reddit. Next: Channel Manager
  cleanup (remove Your Regional, selected-only list + Add Channels picker), then Mormon Wives.
- Build 11: tvOS and visionOS archived + exported (CFBundleVersion 11) with pinned manual signing;
  upload to TestFlight Internal + TraceEnabled in progress via `asc publish testflight`. iOS blocked
  on the Widgets App Group (owner, portal). Commits 86a0b2a, 3055de2 (+ visionOS pin pending).
- Toggles iOS-green; TestFlight installs trace by default (`AppleBuildChannel`); Add Live TV M3U
  has Playlist Text + Choose File merging into one local playlist/one source row; AIOMetadata
  seeded once on DEBUG/TestFlight. Gate 981 / 94. Ship 11 in progress (three platforms, automatic
  signing via the ASC API key, `asc publish testflight` to Internal + TraceEnabled).
- Downloads automatic (picker removed), per-episode ring + VoiceOver percentage, failure line on
  series pages, trace flag fixed, download phases traced. UI test
  `testDownloadStartsWithoutAskingForASource` passes (23 s). Gate 973 / 91. Sim manifest clean.
- Skills (18) installed; `asc` logged in. Ship 11 still blocked on signing + App Group (see 4c).

**Done tonight** (all gated, built on the platforms concerned, screenshot-verified): tester bugs 1
(tab trap) and 4 (M3U "one channel"); toggle colour UX; 300 display cap with notice + Channel
Manager guard; M3U cap 25k with truncation traced; owner's French playlist as a fixture; visionOS
target un-broken (it did not build — nothing in the loop compiles it); status-bar shield on
iPhone/iPad detail; Dynamic Type on the detail page; inline titles on pushed settings panes;
iPad content column / hero buttons / rail bleed; billboard wordmark alignment; search ordering
(exact title first); eight tvOS/iOS alignment fixes. Details in the two files above.

**Open, on the owner**: ASC Issuer ID + two profiles (ship 11); crash report (TestFlight →
Crashes, not on this Mac); the 805 MB `design/` push; which edge tvOS section headers align to;
captions-control placement; search duplicate policy; Library TV (418 lines, unreachable) — wire
or delete; nine tested-but-uncalled policies; `AppleIPTVGuideView` (public, superseded) —
delete?; hero synopsis contrast (fails 4.5:1 on bright art — **most urgent parked item**).

**Owner asks queued, in order**: tester bug 2 (download source picker); bug 3 + faster posters;
download %; landscape button in the player; M3U EPG in the guide; settings backup/restore
payload; iMessage "watch this" share extension (needs a third profile); visionOS every-screen
dead-button tally (it builds now); Channel Manager redesign — recommendation in FEEDBACK.md
(selected-only list, add via Search (+)); **iPhone DUO** — needs Xcode 27.1 beta, not released;
this Mac has 26.3, no DUO device type, no iOS 27 runtime. Tooling-blocked, not us.

**Test count**: 1007 / 101. If yours is lower, you lost tests — find out why before continuing.

## 9. SHIP RUNBOOK — copy, fill, run. Read it whole once; then never improvise a step
Written after Opus went in circles on this (owner, 2026-09-17). Every command below ran today.
Driver only: workers never upload. Authorization = the owner's literal "ship N" / "push N" for that
build number, all platforms on the same N. Nothing else authorizes an upload or a group change.

### 9.0 Facts you would otherwise rediscover
- Team `2VQ74PD5YG` · app id `6807530757` · bundle `com.orgista.openstream` (+ `.topshelf`, `.widgets`, `.watchkitapp`).
- Signing on this Mac is **manual**, pinned per target in `Apps/OpenStreamApps.xcodeproj/project.pbxproj`
  (Release configs of `OpenStream tvOS`, `OpenStream Top Shelf`, `OpenStream visionOS`; iOS/Widgets/Watch
  get the same pin when they ship). Identity: `iPhone Distribution: Raster Inc` (SHA‑1 `0A77397B…`).
  Profiles are installed in `~/Library/MobileDevice/Provisioning Profiles/` and named:
  `OpenStream tvOS App Store`, `OpenStream tvOS TopShelf`, `OpenStream App Store SharePlay 2026-09-10`
  (iOS + visionOS app), `OpenStream App Store widgets 2026-09-17`, `OpenStream App Store watchkitapp`.
- **Automatic signing does not work here**: no Xcode account, and `-allowProvisioningUpdates` with the
  ASC API key fails "Authentication failed: bearer token". Do not retry it. Do not "try Xcode".
- Build number comes from the command line: `CURRENT_PROJECT_VERSION=<N>`. Version is 1.0.
- Tracing default is stamped in `Apps/Shared/Info.plist` key `OpenStreamTraceDefault` (true = traced
  build for Internal + TraceEnabled; absent/false = non‑trace build for Reddit).
- Groups: Internal `ca5595ab-…` (receives every build automatically), TraceEnabled `64f18c4b-…`,
  Reddit `7360237c-…`. External groups need beta review: `--submit --confirm`.
- `asc` is logged in (profile "OpenStream"). Never print key ids, issuer ids or the .p8.
- One `xcodebuild` at a time. Archives take 5–12 min; run them detached with a done‑marker and poll.
- The share lies: before archiving, `find Sources Tests Apps -name "*.swift" -size 0` must be empty and
  every file you edited must be `touch`ed + 16 s old. Release compiles the `#else` of `#if DEBUG` —
  a symbol only referenced there fails only here.

### 9.1 Per platform (run tvOS, then visionOS, then iOS — sequentially)
```
B=~/Developer/openstream-build; N=<build number>; cd "<tree>/Apps"
# tvOS
xcodebuild -project OpenStreamApps.xcodeproj -scheme "OpenStream tvOS" -destination "generic/platform=tvOS" \
  -configuration Release -derivedDataPath $B/DerivedData-deploy-tvos \
  -archivePath $B/OpenStream-tvOS-b$N.xcarchive archive CURRENT_PROJECT_VERSION=$N > /tmp/archive-tvos.log 2>&1
grep -E "\*\* ARCHIVE|error:" /tmp/archive-tvos.log | sort -u        # must say ARCHIVE SUCCEEDED, no error:
xcodebuild -exportArchive -archivePath $B/OpenStream-tvOS-b$N.xcarchive \
  -exportOptionsPlist $B/ExportOptions-tvos-b11-export.plist -exportPath $B/export-tvos-b$N > /tmp/export-tvos.log 2>&1
ls $B/export-tvos-b$N/*.ipa                                          # "OpenStream tvOS.ipa"
# visionOS: scheme "OpenStream visionOS", platform=visionOS, DerivedData-deploy-visionos, ExportOptions-visionos-b11-export.plist
# iOS:      scheme "OpenStream iOS",      platform=iOS,      DerivedData-deploy-ios,      ExportOptions-ios-b11-export.plist
```
Check the archived number before uploading:
`/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$B/OpenStream-tvOS-b$N.xcarchive/Products/Applications/OpenStream tvOS.app/Info.plist"`.

### 9.2 Upload + groups (only after "ship N")
```
asc publish testflight --app 6807530757 --ipa "$B/export-tvos-b$N/OpenStream tvOS.ipa" --platform TV_OS \
  --group "Internal,TraceEnabled" --submit --confirm --wait --output json      # traced build
#   non-trace build → --group "Reddit"      visionOS → --platform VISION_OS     iOS → --platform IOS
asc builds add-groups --build-id <id> --group Reddit                            # add an existing build to a group
asc publish testflight --app 6807530757 --build-id <id> --group "TraceEnabled,Reddit" --submit --confirm   # submit an existing build
```
`--submit` without `--confirm` exits 2 ("--confirm is required"). "Skipped internal group … already receives all builds" is normal.

### 9.3 Verify — never trust a doc, read App Store Connect
```
asc builds list --app 6807530757 --output json | python3 -c "import json,sys; d=json.load(sys.stdin); pre={i['id']:i['attributes'].get('platform') for i in d.get('included',[]) if i.get('type')=='preReleaseVersions'}; [print(a['version'], pre.get((r.get('relationships',{}).get('preReleaseVersion',{}).get('data') or {}).get('id'),'?'), a.get('processingState'), r['id']) for r in d['data'] for a in [r['attributes']] if a.get('version')=='$N']"
asc testflight distribution view --build-id <id> --output json     # internalBuildState / externalBuildState = IN_BETA_TESTING
```
Then record in `DELIVERIES.md` (build → id → groups → commit) and FEEDBACK, and tell the owner the ids.

### 9.3a TestFlight "What to Test" notes — owner policy (2026-09-17, applies to every build)
Concise, platform-specific "Added…" / "Fixed…" lines written from the exact shipped snapshot, with
one useful testing request. Only verified user-visible changes: no raw commit messages, no Android
items in Apple notes, no unshipped features, no test counts, no hype. Use the `copywriting` /
`copy-editing` skills for the wording. Set them with `asc publish testflight … --test-notes "<text>"
--locale en-US` (or the testflight notes command from `asc-testflight-orchestration`) and read them back.

### 9.3b Source publication (Codex, 2026-09-17)
Shipped snapshots also go to the private GitHub repo `orgista/openstream-apple` (tag `build-N`,
isolated checkout `~/Developer/openstream-build/publish-apple-b<N>`), where Apple Build Checks run
on four platforms. That publication is configuration-sanitized (see its DELIVERIES.md); newer
development stays local on `codex/openstream-multiplatform-offline` until the owner says otherwise.

### 9.4 When it fails — what it means, what to do (all seen 2026-09-17)
| Symptom | Meaning | Do |
|---|---|---|
| `Authentication failed: … bearer token` on archive | automatic signing via API key; unsupported here | use the manual pins (9.0); do not retry |
| `No profiles for 'com.orgista.openstream.widgets' … App Development` | the target is still Automatic | pin that target's Release config (script pattern in §4d) |
| `requires a provisioning profile` at export | export plist names a profile that is not installed or misnamed | `ls ~/Library/MobileDevice/Provisioning\ Profiles/`, decode with `security cms -D -i` |
| Widgets codesign: `application-groups` entitlement not in profile | the Widgets profile lacks the App Group | owner ticks the group in the portal → `asc profiles create … --bundle-id 9UBVK6SYGV --certificate SH522LYR9M` → install → retry |
| `cannot find 'X' in scope` in Release only | a 0‑byte file on the share, or a `#else`-only reference | rewrite the file from the transcript/commit; `git show HEAD:./path \| wc -c` |
| `input file … was modified during the build` | share mtime lag | sleep 45, rerun |
| `asc … exit=2` with no output | flag error (usually missing `--confirm`) | rerun in the foreground and read stderr |
| build not in `asc builds list` after upload | still processing | `--wait`, or poll every 2 min; do not upload again |
| `Address already in use` in the gate | an app on a booted sim serves the web portal | `xcrun simctl terminate <udid> com.orgista.openstream`, rerun |

### 9.5 macOS (build 13+) — prerequisites before any archive
No Mac signing assets exist yet: needs a Mac App Distribution + Mac Installer Distribution cert (CSR
from this Mac's keychain), a MAC_APP_STORE profile for `com.orgista.openstream`, the macOS platform on
the ASC app record, sandbox entitlements on the `OpenStream macOS` target, and a manual pin like the
others. Ask the owner before creating certificates; then follow 9.1–9.3 with `-destination
"generic/platform=macOS"` and a `.pkg` export (`asc publish testflight --pkg … --platform MAC_OS`).


### Codex iPhone UX completion — 2026-09-17

Current local iPhone 16 Pro app is freshly built Debug 1.0 (1), not the numbered TestFlight binary.
See GUI-AUDIT.md, final September 17 native UX section, and design/2026-09-17-iphone-native-ux.
Final gate 1024/104; iOS and tvOS build success with changed-file compile evidence. Trailer
safe-area/Back/44pt controls and stable hero destination fixed; native Live title, search keyboard
dismissal, Playlist Text removal, independent Save/Test feedback, historical source-failure display,
and channel failure recovery verified. All 28 supplied channels tested twice (5 decoded,23 HTTP403).

Concurrent metadata disk-cache addition initially broke five resolver expectations by conflating
provider endpoints; corrected to Meta-v2 complete-endpoint hash and isolated injected transports.
Keep those corrections and seven cache regression tests when reviewing the pending diff. No current
UX changes committed/pushed by Codex; prior clean build-12 publication and CI-only ActivityKit fix
are separate. Cloud run5 green on all4platforms; no new TestFlight binary. Private install receipt:
~/Developer/openstream-build/codex-ios-ux-install-receipt.json. Temporary test source/cache removed.
