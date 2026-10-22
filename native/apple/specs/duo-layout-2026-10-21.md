# Duo layout: size-based layout instead of device-type checks (2026-10-21)

Owner (2026-10-21): "It appears we can ship Duo so we gotta make sure that works as well." Apple's foldable iPhone
(Duo) launches 2026-10-23; apps built with the iOS 27.1 SDK run full-bleed on it. Folded it is a phone; unfolded it
is still `userInterfaceIdiom == .phone` but with an iPad-like, regular-width window, and it changes size at runtime.

## Input
- The cloud audit on this branch: `design/2026-10-21-duo-readiness.md` (top 10 findings, P3 list, what is fine).
- The earlier audit + patches (NOT in git, read them from the main checkout):
  `/Volumes/Files/Projects/Code, Apps & Websites/Apps/OpenStream/native/apple/verification-artifacts/duo-2026-10-08/`
  (AUDIT.md, patches/01–04; 02 and 04 apply cleanly, 01 and 03 need rebasing, 03 is mostly obsolete).
- This branch's commit 1b12889 (shared `AppleDesignTokens.phoneHeroControlInset`) — verify it as part of this job.

## Job
1. One policy, one place: a pure "large screen" decision from the window/scene size (and size class), not the device
   idiom — e.g. `AppleLayoutClass.isLarge(width:height:horizontalSizeClass:)` with Swift Testing tests (folded Duo,
   unfolded Duo-like sizes, iPhone SE/Pro Max, iPad, iPad split view). Pick thresholds from the iPad/phone layouts
   already in the code; write the sizes you assume into the tests.
2. Fix audit findings 1–6 with that policy (orientation lock re-evaluated on size change; iPad hero on a large window;
   phone chrome only where the phone hero is used; root measured on every iOS device; Live rows/picker by layout,
   not idiom). Then 7–10 if they are small; list what you leave.
3. Nothing changes on today's iPhones and iPads: same layouts, same screenshots.

## Proof (no Duo simulator exists yet — the mini has Xcode 27.0 only; the "DUO" sim CA2CCA73 is an iPhone 18 Pro)
- Unit tests for the policy and the orientation decision.
- Regression on iOS 18.6 (owner sim, ONLY via `/Volumes/DevExt/dev/openstream-build/batch-1018a/protected.py`):
  AppleiOSStubSmokeUITests, testB8DiscoverJank, testCrawlDiscover, the Live tests; screenshots of Discover, a title
  page and Live before/after — must match.
- iPad Pro 13" sim (8939801C…): Discover, title page, Live, Settings split — must match before/after.
- A large-window phone proof if possible without new simulators: e.g. a unit/UI test that hosts the root view at an
  unfolded-Duo-like size (about 7–8" class, regular width) and asserts the iPad hero/large layout is chosen.
- When Xcode 27.1 lands the lead runs the real Duo simulator; keep the change easy to tune (thresholds in one place).

## Rules
Dev-Mini only (`scripts/mini.sh`, `OPENSTREAM_MINI_DEST='~/Developer/openstream-build/lanes/duo-layout'`); sims through
`~/Developer/bin/buildlock.sh`, compile-only through `buildlock-compile.sh` (FIFO; queue, never kill). Never install on
"Anthony", never test on OfficePlus; never create/erase simulators. No commits, stash, checkout, reset. Keep the mini
> 12 GB free (it is at ~11 GB: delete only your own scratch). Gates: serial swift test; iOS, tvOS, visionOS, macOS
Debug builds (shared code); code-anti-slop on the diff; no zero-byte Swift files. Report per AGENTS.md §7 with the
policy, the findings fixed/left, the thresholds, and the before/after screenshot paths.

## Owner requirement (2026-10-21 12:00): "for duo we want no unused real estate please"
Every screen fills the whole Duo display, folded and unfolded: full-bleed (27.1 SDK), no letterbox/pillarbox, no
max-width column centred with empty margins, no phone layout stretched or floating in the middle of the inner screen.
On the unfolded screen the extra space is USED: more posters per row (tile counts from the width, not fixed), heroes
edge to edge, title page using the iPad/large layout, Live with the stage and the channel list side by side, Settings
as a split view, the player edge to edge. Check every place that caps a width (`.frame(maxWidth:)`, fixed column
counts, fixed tile widths, readable-width guides) and report each one: kept (why) or opened up. Proof screenshots at a
large phone-window size must show no empty bands.

## Round 2 (lead, 12:30): finish
Round 1 stopped after overlapping xcodebuild/swift test (AGENTS.md §3) — run ONE heavy job at a time, each through
its lock. Finish:
1. Serial swift test (clean pass), iOS + tvOS + visionOS + macOS Debug builds, iOS Release no add-ons.
2. iPad Pro 13" after-captures vs `design/2026-10-21-duo-layout/before/ipad/` (Discover, title page, Live, Settings).
3. The owner requirement above ("no unused real estate"): the width-cap audit (every `.frame(maxWidth:)`, fixed column
   count, fixed tile width, readable-width guide reachable on iPhone/large phone windows) — open up each one that
   leaves empty bands on a large phone window; list kept ones with the reason. Proof via your debug layout host at an
   unfolded-Duo-like size (regular width, ≥ 600 pt short side) for Discover, Library, title page, Live, Settings:
   screenshots with no empty bands.
4. Remaining findings 6 and 10 (and 12–15 if small); explain anything left.
5. Explain the AppleCEA608DetectorTests change (unrelated to Duo? revert it if so) and keep AppleDebugLayoutHost
   DEBUG-only (it must not ship in Release).
Then the §7 report. Xcode 27.2 RC is now at /Volumes/DevExt/Applications/Xcode-27.2.app but its simulators are NOT
set up yet (needs the owner's admin password) — keep using Xcode 27.0 for this round.

## Round 3 (lead, 14:45): the REAL Duo on Xcode 27.2 — start after round 2 is reported
Xcode 27.2 RC (27B48) is set up on the mini: `DEVELOPER_DIR=/Volumes/DevExt/Applications/Xcode-27.2.app/Contents/Developer`
(27.0 stays the default for everything else). Real Duo simulator: **iPhone Duo 57B18C7A-A409-4F2E-8E26-F9CEB1A0ACE8**
(iOS 27.2 24B91014). Do NOT create or delete simulators or runtimes; the internal disk has ~14 GB — keep > 10 GB,
put DerivedData for this at `~/Developer/sim-dd-duo` (internal: sim builds must be internal) and delete it at the end.
1. Build the app with Xcode 27.2 (iOS Debug, simulator) and confirm it compiles cleanly with the 27.2 SDK (list any
   new warnings/deprecations that matter).
2. On the Duo sim, with the stub fixtures (the same fixture setup the UI tests use): Discover, Library, a title page,
   Live (playing), Settings, the full-screen player — FOLDED and UNFOLDED, and the transition between them while a
   title page and the player are open. Find out how the simulator folds/unfolds (Simulator/simctl; describe it in the
   report) and capture each state.
3. Judge every capture against the owner rule "no unused real estate": full-bleed, no bands, the unfolded screen uses
   its width (more posters, large title page, Live side by side, Settings split). Fix what fails, re-capture.
4. Record the folded and unfolded window sizes (points) and set the policy threshold from them.
5. Same gates as before (one heavy job at a time) plus the iOS UI smoke on the Duo sim.

## Round 4 (lead, 18:40): close the gaps — work Claude takes over from Codex
Evidence reviewed by the lead (design/2026-10-21-duo-layout/large-phone/, native-27.2/). Do, in order:
1. **Live at the large size leaves half the screen empty** (duo-large-wide-live.png: the stage sits top-left, a black
   band below it). Owner rule "no unused real estate": side by side, the left column must be filled — e.g. the stage
   on top with the selected channel's now/next programme info + schedule (or the category's guide) beneath it, or a
   taller stage; look at how Paramount+ and the Apple TV app lay out Live on iPad (openstream-reference-patterns skill)
   and pick the one that fills the column. Same check for the portrait large size.
2. **Discover/Library at the large size show a "Discover"/"Library" bar over the hero** (duo-large-wide-discover.png).
   The owner removed that bar on iPhone (2026-10-20: "Discover and Library are cut off by the bar at the top … those
   used to not be there"). The Duo is a phone: use the phone's landing chrome (no bar at rest, round Search/Refresh
   over the art, compact title only after scrolling) on large PHONE windows; iPads keep their current look (prove
   iPad unchanged). The hero art must run edge to edge on the wide canvas.
3. **Fold/unfold on the native Duo sim (57B18C7A, Xcode 27.2):** find a way to switch displays. Try `xcrun simctl`
   options, Simulator.app's Device menu (driving Simulator.app on Dev-Mini with osascript is allowed for this — the
   mini is the build machine, nobody uses its screen; close Simulator.app when done), and the Duo device type's
   display list in its profile. Capture Discover, Live, a title page and Settings unfolded, plus a fold while the
   player runs. Record the unfolded window size and set the large-layout threshold from it (one place).
4. **iOS 18.6 testCrawlDiscover** failed once in round 3 and the retry stalled: run it 3× on the owner sim through
   protected.py; if it fails, find out whether this branch caused it (compare with main 4963d99).
5. Gates: serial swift test; iOS/tvOS/visionOS/macOS Debug + iOS Release; Duo smoke on 57B18C7A (Xcode 27.2);
   AppleiOSStubSmokeUITests + testB8DiscoverJank on 18.6; iPad reference test; code-anti-slop; zero-byte.
Report per AGENTS.md §7 with before/after captures for 1–3.

## Round 5 (lead, 21:30): Fable review — fix first (commit 17ecb4a is the base)
Fix each P1/P2 with a test; P3s: take the cheap ones (topInset guard, seed controlsSize). Use your OWN simulator
DerivedData `~/Developer/sim-dd-duo-r5` (another lane rebuilt the shared sim-dd-internal under round 4).
- P1 quality: today's iPhones must keep the 1080p Automatic cap; only large windows (iPad, unfolded Duo) may reach UHD.
  Flip the AppleStreamQualityTests 1290x2796 row; drop the foregroundActive-only window filter.
- P1 iPads: iPads keep every old path in ALL window sizes (Slide Over, split, Stage Manager): define the environment
  flag as `idiom == .pad || AppleLayoutClass.isLarge(...)`, revert the AppleDiscoverView compact check as suggested,
  keep the old regular+landscape Settings rule on iPad, derive the full-screen picker from the same flag. Add tests
  for an iPad compact window (e.g. 1/3 split) keeping the pad hero/chrome/Live behaviour.
- P2: title-page chrome and status-bar shield gated on "phone device and not large" only (no landscape term).
Same gates as round 4 (both Xcodes, Duo smoke, 18.6 via protected.py, iPad reference + a split-view iPad capture).
NOTE: 8939801C (iPad), 57B18C7A (Duo) and 2E61439B are being loaded with the owner's data by another job right now —
run anything on them ONLY through /Volumes/DevExt/dev/openstream-build/batch-1018a/protected.py.

### Review text
**VERDICT: fix first.** The size rule replaces iPad idiom checks as well as iPhone ones, and the Automatic quality cap was changed on today's Pro iPhones. Today's iPhones in portrait are otherwise unchanged; Release has no DEBUG host reference; tvOS, visionOS and macOS paths are untouched.

**P1 — Automatic quality now reaches 4K on most of today's iPhones**
- `Sources/OpenStreamApple/AppleStremioCandidateRanking+Device.swift:55-59`, `AppleStreamDeviceCapabilities+Current.swift:20-25`. Old rule: any iPhone caps Automatic at 1080p. New rule: UHD when the panel's short side exceeds 1080 px. iPhone X through 16 Pro Max (1125 to 1320 px wide) now rank 2160p streams first on Wi-Fi. `Tests/OpenStreamAppleTests/AppleStreamQualityTests.swift:106` asserts 1290x2796 gives `.uhd`, so this is intentional, and it contradicts the spec line "nothing changes on today's iPhones".
- Fix: keep the phone cap unless the window is large (pass the idiom plus the large flag, or raise the pixel threshold to 1440 so phones stay below and iPad mini 1488 and the Duo 2007 stay above); flip the test row.
- Same file line 20-22: the key window is taken only from `.foregroundActive` scenes, so a resolve while backgrounded gets `.zero` and 1080p on iPad too. Drop the activation filter.

**P1 — iPads change in every non-full-screen window**
Multitasking is on (all four iPad orientations, no `UIRequiresFullScreen`), so Slide Over, 1/3 and 1/2 split on 11", and short Stage Manager windows are compact or under 600 pt. `AppleLayoutClass.isLarge` is false there, and every consumer that used `idiom == .pad` before now takes the phone path:
- `AppleHomePresentationPolicy.swift:13-15`: compact iPad window gets the `.phone` hero (was `.pad`); `.rotating` for a regular 900x500 window.
- `ApplePhoneTitlePageChrome.swift:106-110` and `AppleAlignedTabTitle.swift:38-40`: Discover and Library lose the stock bar and title, gain round Search/Refresh and the gradient; `AppleDiscoverView.swift:425`, `AppleMediaSourceViews.swift:3256` hide the toolbar.
- `AppleTabToolbarContext.swift:80-83` and `AppleDiscoverView.swift:3580`: title pages get the phone back button and lose the status-bar shield.
- `AppleMediaSourceViews.swift:1430-1432`: Live uses the phone stack and `playFromList` stops opening full screen on a row tap (line 1570). `AppleMediaSourceViews.swift:2254-2256`: full-screen picker falls back to the panel.
- `OpenStreamRootView.swift:359-363`: Settings split now also needs a 600 pt short side (was regular + landscape).
- Fix: in `OpenStreamRootView.swift:351-353` define the environment flag as `idiom == .pad || AppleLayoutClass.isLarge(...)` so iPads keep their old paths, revert `AppleDiscoverView.swift:9597` to `horizontalSizeClass == .compact && !isLandscapeLayout` (that already excludes a regular-width unfolded Duo), keep the old regular + landscape rule for iPad Settings, and derive the full-screen picker from the same flag. Add an iPad compact-window test to `AppleLayoutClassTests`.

**P2 — Title page chrome swaps under a landscape player on today's iPhones**
- `AppleTabToolbarContext.swift:80-83`, `AppleDiscoverView.swift:3580,3628`. The chrome is now gated on `usesPhoneTitlePage`, which includes `!isLandscapeLayout`. The title page under the full-screen player lays out at 932x430, so the phone chrome is disabled and the stock bar with Back plus tab toolbar is mounted. Closing the player in landscape rotates back while that bar is visible, so it can flash before the geometry reads portrait. Previously the chrome never depended on landscape.
- Fix: gate chrome and shield on "phone device and not large" only; leave the landscape test to the body layout.

**P3**
- `AppleDiscoverHeroLayoutReader.swift:61`: the settle task now draws a reading with `topInset == 0` after 750 ms; on phones that only happens with the status bar hidden, and the next reading corrects it. Transient, leave or restore the `topInset > 0` guard.
- `AppleAlignedTabTitle.swift:38`: `legacyNavigationBackground` is now applied on iPhone (bar hidden by the chrome, so invisible); confirm on the iOS 18.6 Library screenshot.
- `AppleMediaSourceViews.swift:2256`: `controlsSize` starts at zero, so the first body picks `.panel` and switches to the strip after the first geometry read; the picker opens 250 ms later, so no visible effect, but seed from the window size.
- Duo only: unfolding swaps the Discover hero type (`.phone` to `.pad`), restarting its trailer, and `AppleSettingsView` drops the pushed page when the split appears. Live stage keeps identity across the switch, which is correct.

**Checked, no finding:** root reader has no loop (size plus insets stays constant through keyboard and bars; the large flag changes nothing that resizes the root); `onChange(of: isLargeLayout)` never fires on fixed-size phones; orientation lock falls back to the old mask when `window` is nil; `AppleDebugLayoutHost.swift` and its call site are both inside `#if DEBUG && os(iOS)` with no other references; `AppleTrailerStartPolicy` keeps `.phone` on small phone windows; non-iOS platforms get the same values as before.
