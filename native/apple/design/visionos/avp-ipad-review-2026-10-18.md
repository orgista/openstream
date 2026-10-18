## Review: avp-ipad (Vision Pro on the iPad screens + iPad a11y)

**Verdict up front: CHANGES.** The visionOS widening itself is the right pattern and is build-proven, but the branch also replaces the iPad's system tab bar with a hand-rolled sidebar, re-enables the immersive player experience the owner had parked, removes the iPhone's accessibility type caps, and changes several shared looks on iPhone, Mac and tvOS that nobody asked for. Most of these were done to make an XCTest accessibility audit pass rather than for the owner.

**Evidence state.** All 29 production files hash-match the recorded candidate in `design/visionos/review-build-evidence.json`, which lists the 8 Debug/Release builds at exit 0 and the serial Swift gate at 3444/428. The iPad parity screenshots are from that candidate. There are zero `review-after-visionOS-*` screenshots: the Vision Pro side has no visual evidence of the final state, only pre-review pairs.

### Findings (most severe first)

1. **Unasked, owner-rule violation: iPad gets a custom sidebar instead of the system tab bar.** `Sources/OpenStreamApple/OpenStreamRootView.swift:238`, `:322`, `:347`, `:356` and `AppleRootViewportTracking.swift:46-85`. In regular width every tab is wrapped in its own `NavigationSplitView` with a `List(selection: .constant(...))` of buttons, `.tabViewStyle(.tabBarOnly)` plus a hidden tab bar removes the system bar, and the sidebar stays open in portrait too (`.balanced`, screenshots show 280 pt taken from a portrait title page). GUI-AUDIT admits the motive: "native-sidebar experiment removes four tab-label font findings" from the audit on Apple's own tab bar. Owner rule §4: "The tab bar is the system one per OS ... no custom tab-bar paint." If a sidebar is ever wanted, `.tabViewStyle(.sidebarAdaptable)` is the stock answer. Also a grey selection pill from a new `sidebarTint` token is new paint. Scenario: owner opens Discover on iPad and the floating tab bar is gone.

2. **Reverses an owner decision: immersive player enabled on visionOS.** `ApplePlayerHost.swift:100` adds `.immersive` to `allowedExperiences`; the deleted comment said "no immersive button until the owner decides on one (2026-10-07)". The prior review asked only to restore `.expanded`. Scenario: Vision Pro player now shows AVKit's immersive control.

3. **iPhone AX regression risk: the accessibility type caps were deleted.** `AppleHomePhoneHero.swift:85-88` (removed `.dynamicTypeSize(...accessibility2)`), `:157-160` (title `lineLimit(nil)`, `minimumScaleFactor(1)`), and the same cap removal on the phone title page (`AppleDiscoverView.swift` ~9490, `:9588`). Those caps were added because at AX-XXXL "Play was clipped and the round buttons hit the screen edges". The policy keeps the phone hero at AX (`AppleHomePresentationPolicy`), so an iPhone at AX5 with a long title now gets an unlimited-line 48 pt black uppercase title plus full-size buttons. The only guard (`AppleiOSUITests.swift:2018-2033`) runs behind `OPENSTREAM_TITLE_PAGE_PROOF=1` and was not run.

4. **Shared clamp now unclamps at AX sizes everywhere.** `AppleDiscoverPhoneRowViews.swift:41-45`: `AppleWordClampedText` shows full text whenever `isAccessibilitySize`, unless the new flag is set. Callers that passed AX line budgets (`AppleContinueWatchingTile.swift:66`, `AppleDiscoverPhoneRowViews.swift:149`, `AppleDiscoverView.swift:2873/9991/9999`, episode overviews) now get unbounded captions. The file's own comment warns the lazy row sizes every card off the first one. Scenario: iPhone AX3, Continue Watching row, one long title makes the row uneven or cuts later cards. Same effect from `AppleCatalogCard` at `AppleDiscoverView.swift:2727`.

5. **Guide sheet UIKit hack changes VoiceOver semantics on iPhone and iPad.** `AppleMediaSourceViews.swift:1398-1420`: `presentationBackgroundInteraction(.enabled)` on a `.large` sheet plus a controller walk setting `accessibilityViewIsModal = false` and `accessibilityElementsHidden = false` on the presenter. VoiceOver can now swipe out of the Guide into the covered Live stage; on iPad the form sheet no longer dismisses on an outside tap. The Done button also became an icon-only X (`:1389`). None of this was asked for.

6. **Text shadows removed from title-page copy over art to satisfy the audit.** `AppleDiscoverView.swift` ~3854, ~3878, ~4305, ~5436 (`seriesAuditDiagnosis.change` in the evidence JSON confirms this was the fix). N20 was raised precisely because copy sits on bright backdrops. Scenario: iPad/Mac/visionOS title page over a light poster, title and metadata lose legibility. Also `titleMetadataColor` (light-mode Mac handling) is gone in favour of forced white.

7. **Shared visual changes on iPhone, Mac and tvOS that were not in scope:**
   - `AppleDiscoverView.swift:8854` corner radius becomes `actionButtonHeight / 2`: 30 pt on visionOS/tvOS (height 60) instead of 18. Check the tvOS title page pills.
   - `AppleDiscoverView.swift` ~7631-7645: Play/Trailer/Download labels switch from a fixed width with shrink-to-fit to `minWidth` + `fixedSize(horizontal: true)`. Buttons are no longer equal width, and a long label ("Resume S12 E3") cannot shrink any more, so the row can overflow on iPhone landscape. Used by `AppleMediaShelf.swift:365/374` too (hero Details/Play).
   - `AppleDiscoverView.swift` ~5980-5998: season `Picker(.menu)` replaced by `Menu` with a hand-drawn chevron. On macOS the pull-down adds its own indicator (double chevron); the stock picker already showed the value. Owner rule: stock look.
   - `AppleTitlePageSections.swift:666`: cast initials replaced by a `person.fill` glyph on every platform.
   - `AppleLiveCategoryBar.swift:85`: unselected Live categories are now white, not secondary. The doc comment that quoted owner item 8 ("the others secondary") was edited to delete that phrase.
   - `AppleLiveOnNowList.swift:173`: WATCHING pill text goes black on the brand pink.
   - `AppleHomeMacHero.swift`: metadata/summary/rating opacities dropped to pure white on the Mac too, plus `.environment(\.colorScheme, .dark)`.
   - `AppleIPTVGuideGridView.swift:91`: the Mac guide (also used at `AppleMediaSourceViews.swift:294/480`) becomes one two-axis ScrollView, so trackpad scrolling can drift diagonally where the axes were separate before.

8. **iPad Live layout change hiding behind the Vision minimum window.** `AppleLiveStagePolicy.swift:15` drops the side-by-side floor from about 895 pt to 680 pt. iPad Split View widths 680-894 now go two-column with a 340 pt guide. `AppleMediaSourceViews.swift:1338` hard-codes 760 instead of `AppleVisionPlayerWindowPolicy.browseMinimum.width`.

9. **`AppleClampedLabel` is a second clamp implementation with layout quirks.** `AppleTitlePageSections.swift:94-153`: a UIKit label that re-implements `AppleWordClampedText`, always takes the full proposed width (`sizeThatFits` returns `width: width`), has no baseline. In the guide rail (`AppleIPTVGuideGridView.swift:357`) it sits in an `HStack(alignment: .firstTextBaseline)` with the health dot after it, so the dot is pushed to the far edge of the rail and no longer aligns with the name. Anti-slop: duplicate helper, no stated reason the SwiftUI clamp could not be used.

10. **Global `.tint(.white)` and UIKit dark-mode forcing are redundant or risky.** `OpenStreamRootView.swift:322-323` adds `.tint(.white)` on the iOS TabView and `AppleRootViewportTracking.swift:28-43` sets `window.overrideUserInterfaceStyle = .dark` per tab. The root already has `.preferredColorScheme(.dark)` at `:631` and `.tint(.white)` at `:636`, so this is slop. The 37 toggles keep green only where `.tint(.green)` is set explicitly; check any that relied on the default.

11. **Accessibility labels changed under existing tests and VoiceOver users.** `AppleIPTVGuideGridView.swift` ~374 ("Play 12, CBS"), `AppleLiveOnNowList.swift` ~97 (programme and Watching folded into the label instead of the value), `AppleTitlePageSections.swift:535` ("Play S1 E1, title, overview" with `.combine`). Repo tests were rewritten to `BEGINSWITH` to cope. State belongs in `accessibilityValue` (ios-accessibility skill); the episode label now reads the whole synopsis before the action.

12. **run-e2e.py behaviour changes for existing callers.** `Tests/Fixtures/run-e2e.py:572`: with no `--platform` the script now also boots the Vision Pro simulator. `:587`: results move from `<work>/iOS/fixtures-ios.json` to `<work>/iOS/1/...` even with `--repeat 1`, which breaks the paths the docstring and the handoff specs quote. `:239` sets `OPENSTREAM_HERO_SHOT_DIR` for every iOS run, so the hero-shot test stops skipping and writes PNGs into scratch on every E2E.

13. **mini.sh**: `scripts/mini.sh:38` passes `BUILDLOCK_POLL`, which `~/Developer/bin/buildlock.sh:31` does read, so the mechanism works; but the comment at `:8` promises "up to two hours", and buildlock still gives up at its own limit, so the comment overstates it. It conflicts textually with main's `45aef27` (same compile-lane lines rewritten without main's owner comment). Keep main's version and re-add only `--no-sync` and the poll variable.

14. **Anti-slop leftovers.** `AppleHomePhoneHeroActions.swift:28` `max(50, 44)` is a constant comparison; `AppleHomeMacHero.swift` has two blank lines added mid-file and `.foregroundColor` (deprecated) at `AppleHomeMacHero.swift:103`, `AppleDiscoverView.swift:5436/5942`, `AppleIPTVGuideGridView.swift` ~374 with no reason; `ApplePadParityUITests.swift:153` and `:220` end tests with a dead `launch("discover")`; `AppleIPTVGuideGridView.swift:89` keeps a `GeometryReader` whose `geometry` is now only used for one width; `AppleSidebarContrastTests.swift` asserts a constant token against another constant. Run-e2e's `--derived-data`, `--simulator`, `--repeat`, `--shots-dir` and the `/capture` endpoint are tooling growth nobody asked for, though they are reasonable.

What is fine: the `|| os(visionOS)` widenings in `AppleDiscoverView`, `AppleMediaSourceViews`, `AppleHomeBillboard`, `AppleHomeHeroCarousel`, `AppleLiveCategoryBar`, `AppleLiveOnNowList`; `AppleHomePresentationPolicy` mapping `.vision` to `.pad`; the `AppleReloadGate` coalescing at `AppleLocalLibraryStore.swift:466` (tested); the `isActive` guard; `chromeIsHeldOpen` in `AppleMediaPlaybackView`; the settings layout policy; the Vision test-only window-size hook under `#if DEBUG`; `AppleHomePhoneHeroCarousel` `.disabled(isTouching)` is safe because the drag needs 20 pt first.

### Files likely to conflict with main (base 4a615b9, main cbeee9c)

Hunk-level overlap (real merge conflicts):
- `Sources/OpenStreamApple/AppleDiscoverView.swift`: main replaced the hero `onScrollGeometryChange` block (lines ~316-335) with `AppleDiscoverHeroLayoutReader` and changed the viewport setter at ~411; the branch edits inside both. Also the phone action row (~9727, main adds a server-trailer button) and the AX cap region (~9479-9492).
- `Sources/OpenStreamApple/AppleMediaSourceViews.swift`: same hero reader replacement in `AppleLibraryView` (~3332-3342).
- `Sources/OpenStreamApple/AppleHomeBillboard.swift` (~577, `heroesSettled` vs `settlesTrailerPicture`).
- `Sources/OpenStreamApple/AppleHomePhoneHeroCarousel.swift` (~56-59, main's cycle events).
- `scripts/mini.sh` (compile lane rewritten both sides).

Same files, non-overlapping hunks, needs a semantic re-check after merge: `OpenStreamRootView.swift`, `AppleHomePhoneHero.swift`, `AppleHomeHeroCarousel.swift`, `AppleLocalLibraryStore.swift` (30 main hunks), `AppleMediaPlaybackView.swift`, `AppleTitlePageSections.swift`, `AppleiOSUITests.swift`, `AppleiOSStubSmokeUITests.swift`, `Tests/Fixtures/run-e2e.py`. Main also added `AppleHomePhoneHeroLayout`, hero trailer gates and the iPhone title header, which the branch's phone-hero font/lineLimit edits will need re-measuring against.

### VERDICT: CHANGES

Runtime checks still needed, after the changes above:
- iPhone 18 Pro at AX-XXXL: Discover/Library hero and both title pages, Play reachable without scrolling, buttons inside the screen edges.
- iPhone and iPad: Continue Watching and poster rows at AX3, row heights even.
- tvOS DevTV: title-page action pills (corner radius, widths), season menu, cast rail glyph, guide focus.
- macOS: title page metadata/shadows over bright art, season `Menu` indicator, Live guide trackpad scrolling.
- iPad: Live stage at 680-894 pt Split View widths; Guide sheet dismissal and VoiceOver escape; Settings split view inside the detail column if the sidebar survives.
- visionOS sim: current screenshots for every parity row (none exist), hover on category bar and On Now rows, 60 pt page-dot spacing, 760x540 window, and the immersive control decision from the owner.
- Full E2E-iOS and E2E-tvOS with the renamed accessibility labels, and `run-e2e.py` with no arguments to confirm the new default platform set is wanted.
