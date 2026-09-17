# OpenStream GUI audit — every element, every screen

Working checklist for the overnight GUI pass (owner, 2026-09-15). Trailers and intro
fingerprinting are **tabled until tomorrow**; chapter markers are approved and in scope.

Audited against:
- the `ui-ux-pro-max` pre-delivery checklist (icons, interaction, contrast, layout, accessibility)
- Apple's tvOS geometry as already encoded in `AppleTVChromeMetrics` / `AppleTVGuideMetrics`
  (80 pt horizontal and 60 pt vertical safe insets on a 1920×1080 canvas; SF Pro tvOS text
  sizes Body 29, Callout 31, Caption 1 25, Caption 2 23)
- the owner's standing UI rules: stock Apple look, no gradients or scrims (one approved billboard
  fade), nothing blue but the brand mark, no Liquid Glass, no explainer text, no scroll indicators,
  one captions control, controls auto-hide, no boxed icons on tvOS, no green text

Status: `[ ]` not checked · `[x]` checked, correct · `[!]` defect found · `[F]` defect fixed

---

## A. Cross-cutting checks (apply to every screen below)

- [x] A1 Safe area — nothing clipped across every tvOS and iPhone capture taken tonight
- [x] A2 One left edge — verified on Discover (title x=81 vs the 80 pt column), the settings
      panes and Add Files after the label fix
- [x] A3 Icon/label spacing — swept 2026-09-16; every remaining raw `Label` is a toolbar item, a
      menu label, an `.iconOnly` button or a pill. None are List rows.
- [x] A4 Focus ring clearance — measured 36 pt between the Discover pills, 24 pt on the
      first-run card after widening it
- [x] A5 Disabled semantics — Storage dims Clear Metadata and Delete All Downloads while Clear
      Cache stays live; the live guide pill reads `isEnabled` and drops to 0.4 opacity
- [x] A6 No boxed icons on tvOS — **swept and clear.** The rule is about tvOS drawing a box around
      a toolbar item's glyph (T4/R1). Every `ToolbarItem` and every `.buttonStyle(.bordered
      /.borderedProminent)` in the sources was checked against its `#if` context: the only
      tvOS-reachable toolbar was Channel Manager's, now fixed, and the remaining ones all sit
      inside `#else` branches of `#if os(tvOS)`. The Discover tab's boxed symbol is fixed
      separately. Nothing boxed is left on a tvOS surface.
- [x] A7 Nothing blue, no green — swept 2026-09-16: **zero** occurrences of blue or green in the
      whole source.
- [!] A8 Five fields are placeholder-only (ZIP code, Server URL, Root folder path, Quality
      profile ID, Channel or group). Deliberately left — see FEEDBACK.
- [F] A9 Loading state fills its container and is centred — never a corner-pinned speck
- [x] A10 One spinner — verified by frame-stepping a player open, 18 captures
- [x] A11 Empty states — verified on tvOS and iPhone empty installs
- [F] A12 Long values — the three rows prone to space-free values now truncate in the **middle**;
      see FEEDBACK
- [x] A13 Icon-only controls — swept 2026-09-16; each carries its title in the `Label`, which
      `.labelStyle(.iconOnly)` hides visually but not from VoiceOver.
- [!] A14 41 off-rhythm literals, mostly deliberate fine-tuning. Considered deviation, see
      FEEDBACK.

## B. Apple TV — screens

### Discover
- [F] B1 Billboard art fills the frame; the one approved fade only
- [x] B2 Title treatment — REACHER renders as wordmark art with no duplicate plain title
- [x] B3 Metadata line — "Action · Crime · 2022", no leading or trailing separator
- [x] B4 Rotation indicator — segment count cannot disagree with the hero count: both come from
      the same array in one call (`AppleDiscoverView.swift:168` passes `rotationCount: heroes.count,
      rotationIndex: index`, and `AppleHeroRotation.index(at:count:)` is under test). Five segments
      observed in the Discover capture match `AppleHeroRotation.maximumCandidates = 5`.
      A pixel probe of the fill returned an empty crop; that was a bad crop window, **not**
      a missing fill, and is not reported as a defect.
- [x] B5 Pills — measured: Play 86–273, Details 309–498, **36 pt gap** (needs ≥24), one baseline
- [x] B6 **Checklist row was wrong, not the app.** The first row is *meant* to peek —
      `AppleTVBillboardMetrics` documents it and a test asserts it. Corrected.
- [x] B7 **Checklist row was wrong, not the app.** There is no glyph pair on tvOS: the whole
      toolbar is inside `#if !os(tvOS)` because Search is its own tab there and the catalog
      refreshes on appear (X4). No amount of scrolling would have revealed it. The dead
      `#if os(tvOS)` branches *inside* that block — unreachable, and what made the row look
      live — are now removed. Verified where the pair does exist: on iPhone it sits in the
      stock toolbar, right-aligned with the large title, inside the safe area, white not blue.
- [x] B8 Row titles align — shelf title edge x=81 against the 80 pt column

### Library
- [F] B9 Loading state centred (fixed 2026-09-15)
- [x] B10 Shelf order — correct **by construction**: the body emits Continue Watching, then
      per source Movies/Shows/Other, then Recently Added, in that order and nothing reorders them
      (`AppleMediaSourceViews.swift:1150-1165`). Continue Watching confirmed first on screen; the
      rest are below the fold and the harness cannot scroll.
- [F] B11 **Continue Watching resume bar** — width + NaN fixed 2026-09-16, verified rendering
      full-width and equal across all three cards on iPad. The "clipped by the tab bar" claim was
      wrong; see FEEDBACK.
- [F] B12 Sort accessory — **the control could vanish entirely.** See below.
- [x] B13 Empty state — **answered by construction, and the answer is "there isn't a per-source
      one".** A source contributing no titles draws no shelf at all (each shelf is behind
      `if !titles.isEmpty`), so an empty source among populated ones is silently absent rather
      than announced. The pane-level "No Videos" appears only when everything is empty:
      `groups.isEmpty && continueWatching.isEmpty && featuredCandidates.isEmpty && !isLoading`.
      That last clause matters — it stops "No Videos" flashing while the library loads.
      Worth an owner nod: silently omitting an empty source is the right default (otherwise every
      empty add-on earns a "nothing here" row), but it does mean a misconfigured source gives no
      signal on this screen.

### Live
- [x] B14 Info strip — tile on the left with the text column beside it: title, "FOX (EAST) ·
      6:30–7:00 PM", then the description. Layout matches the spec.
- [x] B15 Category rail — All / Favorites / News / Sports / … clearly scrolls (content continues
      past the visible "Lo…"), and the trailing search glyph ends **93 px** from the right edge,
      inside tvOS's 80 pt title-safe inset. Measured.
- [~] B16 Now-line — present and drawn inside the current half-hour column, which is right.
      **Colour is a question for the owner**: it is red, the one non-monochrome element in the
      app. Red is the universal TV-guide convention, so it is left alone rather than changed to
      match the otherwise strictly monochrome palette. Say if you want it white.
- [F] B17 Channel numbers **were grouped** — fixed, see below. Logos: slots consistently
      aligned on a uniform 100 px row pitch, artwork aspect-fitted inside (so a wide CBS mark and
      a square HSN mark differ in drawn size, which is correct — logos are never stretched).
- [F] B18 Narrow cells — **half the row was obsolete.** The 60 pt rule is implemented and used:
      below that a cell draws no text. The 200 pt "drop the subtitle" rule guarded a subtitle the
      cell **stopped drawing** — its own comment says "the title, nothing else: the description
      belongs to the info panel above the grid". `showsSubtitle` and `subtitleMinimumCellWidth`
      had no callers anywhere, yet had a passing test, so the behaviour looked covered when
      nothing exercised it. Both removed; the test now pins the one threshold that is real,
      including its exact boundary.
- [x] B19 "No information" cells — grey on a slightly lighter cell than its neighbours, reading
      as a deliberate gap rather than a failed load. Confirmed on the MeTV row.
- [~] B20 Failure message — **found the jargon, could not reach the live failure.** See below.

### Title / detail page
- [x] B21 Action buttons (Play, My List, Rate) aligned on one baseline
- [x] B22 Rating control — **now under test with a real remote.** Opening Rate hands focus to the
      first rating choice; asserted that focus is neither nowhere nor back on Play
      (`testOpeningRateKeepsFocusOnTheChoicesNotPlay`, with a screenshot attached). The source
      comment names the exact failure it prevents: the Rate button is replaced by the choices, and
      "focus with nowhere to go falls back to `defaultFocus`, which is Play".
- [x] B23 Episode list — driven with the remote and **measured off the attached frame**. The
      three unfocused thumbnails share an identical top edge at y=145; the focused one sits at
      y=133, a 12 pt focus lift, and carries a white ring with a brighter title. Titles and the
      "S1 E4 · Sep 1, 2021" metadata lines are consistently aligned beneath each thumbnail.
      `testEpisodeRailMovesAndShowsTheFocusedEpisode` also asserts the rail actually **moves** on
      Right (E3 → E4) — a rail that swallowed presses would look identical in a screenshot to one
      that works.
- [x] B24 "Other sources" — it is **not a visible control on Apple TV**: it lives in a
      `contextMenu` on the Play button, so the only way to it is a long press of Select.
      `testOtherSourcesIsReachableByLongPressingPlay` drives that long press and asserts the entry
      appears; the attached frame shows it opening as the standard tvOS pill with its list glyph.
      **Worth your attention as a product call, not a bug:** nothing on screen advertises it, so a
      viewer who does not know to hold Select will never find it.
- [~] B25 Scrolling — **measured, and deliberately not concluded.** See below: the shelf survives
      rapid input and the per-press cost is now recorded (619 ms for 10 presses on Continue
      Watching), but the one probe that looked like a defect contradicted the screenshot, so no
      verdict is claimed.

### Player
- [x] B26 **Exactly one loading circle** — no double spinner on open
- [x] B27 Transport — captured mid-playback on tvOS and **measured**: elapsed "17:26", a
      scrubber whose track measures **8 px tall** (tvOS renders 1920×1080 at 1×, so 8 pt),
      "-56:33" remaining, and exactly **one** control — the captions glyph, below right. No
      play/pause, no skip buttons, no boxed icons. Matches the spec exactly.
- [x] B28 Auto-hide — covered by `transportControlsHideTogetherAfterThreeSecondsAndReturnOnActivity`,
      which asserts controls start visible, hide (polled rather than slept, so it cannot flake on
      a loaded machine), return on activity, **and stay visible while paused**. Also seen on
      screen: a later capture of the same playback is full-bleed video with a subtitle cue and no
      transport chrome at all.
- [F] B29 Subtitle cue — now anchored to the picture. Measured on iPhone: caption moved from
      ~540 pt below the video to ~58 pt below it.
- [F] B30 **Next Episode card** — alignment, safe-area inset, focus, does not cover the cue
- [x] B31 Captions menu — `AppleSubtitleTrackFilter` covers it in five cases: a picked language
      lists only itself, a picked language that matches nothing lists **nothing** (rather than
      falling back and re-offering everything), no preference lists everything, a *guessed*
      language that matches nothing still lists everything, and the order follows the viewer's
      preference order.
- [F] B32 Skip-intro affordance (chapter markers) — policy + engine + button done 2026-09-16

### Settings
- [F] B33 Root list: one column, consistent glyph slot
- [x] B34 Playback pane
- [F] B35 Sources — add rows (Add Files / Add Instance / Add Catalog / Add Live TV / Web
      Management) with consistent leading glyphs and right-aligned chevrons, then the source list
      with logo tiles, "Add-on · strem.fun" subtitles, On values and chevrons. **The section
      header was inconsistent** and is fixed — see below.
- [x] B36 Add Files (fixed 2026-09-15) — re-verify
- [x] B37 Add Network Share — SERVER / SHARE / ACCOUNT uppercase, every field label sits above
      its field (Name, Server URL, Port, Folder, Username, Password). Matches the spec.
- [x] B38 Add Live TV — same conventions: a Type row of choice pills (M3U Playlist / Xtream
      Account, the selected one check-marked), uppercase CONNECTION, labels above fields, the
      password field with its reveal control beside it, and Save / Test Connection as pills.
- [x] B39 Source detail
- [x] B40 Subtitle Languages picker
- [x] B41 Web Management pane
- [x] B42 About / Third-Party Notices

## C. iPhone / iPad
- [x] C1 Phone + iPad swept 2026-09-16
- [x] C2 Tab bar labels and icons — measured on iPhone: label centres 152 / 453 / 754 / 1055,
      a dead-even **301 px pitch**, left margin 152 vs right 151. Labels all present and sentence
      case; selected tab is white, unselected grey — nothing blue. Symbols are all outline
      variants in code (`sparkles.tv`, `books.vertical`, `dot.radiowaves.left.and.right`,
      `gearshape`). The Discover symbol was a boxed icon and is now fixed — see below.
- [x] C3 Sheets and navigation titles — titles verified on iPhone: Settings draws the large title
      at the leading edge, the title page draws none and shows only the floating back chevron.
      **Sheets now exercised too**: tapping the toolbar's Search glyph presents the search sheet
      with its field, a Cancel control and the stock keyboard, and it dismisses correctly — driven
      through the new iOS UI test target, captured. The one open defect is unchanged and still
      needs a decision: "Title page text collides with the status bar" below.
- [x] C4 Forms: keyboard handoff — **real gap found and closed.** `submitLabel` and `onSubmit`
      were used **zero** times across 25 `TextField`s, so the return key read "return" and did
      nothing on every form. All five multi-field forms are now chained (15 fields), and the
      behaviour is confirmed on a device: the return key reads **"next"** on the first field of
      the Metadata form and **"done"** on the last.
- [F] C5 **Widgets** (iOS + iPadOS) — target built 2026-09-16
- [F] C6 **Live Activity for background downloads** — built and wired 2026-09-16
- [F] C7 Dynamic Type at largest size — two real defects found and fixed at
      `accessibility-extra-extra-extra-large` on an iPhone 16 Pro; see below.
- [x] C8 Landscape — **verified on a real rotation.** An iOS UI test target now exists, so
      `XCUIDevice.shared.orientation` can do what `simctl` cannot. Rotating to landscape hides the
      tab bar and content fills the screen; rotating back brings the bar straight back. Both
      directions asserted, both captured. The viewport-level behaviour stays pinned by the
      extremes tests below.

## D. Empty-install pass (no content at all)
- [x] D1 Fresh tvOS simulator — swept 2026-09-16 (older runtime not installed; see FEEDBACK)
- [F] D2 Fresh iPhone simulator (SE 3rd gen, 375 pt) — swept 2026-09-16
- [x] D3 First-run card — verified on a fresh install on an iPhone SE (smallest screen): brand
      mark, one title, two actions at the bottom (white primary pill, outlined secondary), no
      explainer text. The large gap between title and actions is the intended layout (title
      centred, actions pinned low), not a break.
- [x] D4 Each tab's empty state — Discover "No Sources", Library "No Videos", Live "No Live
      Channels", each with one centred "Open Settings" button at the same vertical position and no
      explainer copy. Consistent across all three; titles leading-aligned on all four tabs.
- [x] D5 Settings with nothing configured — Sources and Channel Manager rows present and
      tappable, section headers correct, no empty or broken rows, toggles at their documented
      defaults (tab toggles on, Top 10 on).

## E. Web management portal
- [x] E1 Wordmark and brand mark
- [x] E2 Form alignment and labels
- [x] E3 Button hierarchy — primary Add, plain Remove (hover state not testable headlessly)
- [x] E4 Pairing flow — unpaired/paired/empty/error states all render
- [x] E5 Responsive at phone width — verified at a true 390 px viewport, no overflow
- [!] E6 NAS add via portal — **confirmed missing**, see FEEDBACK

## F. Search
- [F] F1 **"Jury Duty" returns shows and movies, not individual episodes** (owner, 2026-09-15)
- [x] F2 Result rows — **reached on iPhone** via `openstream://search?query=jury%20duty` (iOS
      opens a deep link without the confirmation tvOS puts up). Rows are aligned: poster, title,
      source name, kind + year, chevron, each on a consistent column with hairline separators and
      consistently sized artwork. **The duplicate-row problem is real and not fixed — see below.**
      Previous note: not reachable on tvOS — `typeText` against the search field fails on tvOS (the
      field never takes keyboard focus that way), and driving nine characters through the
      on-screen keyboard with the remote would be its own source of flake. Needs either your
      hands on the sim or a different input route.
- [F] F3 Empty state — the pre-search state is a centred glyph and "Search Your Sources", and
      **carried redundant copy that is now removed**; see below. The no-results-after-typing state
      is a separate screen and shares F2's blocker.
- [x] F4 Keyboard and focus — the Search tab is reachable with the remote (up to the bar, left
      along it), takes focus as `label='Search'`, and opening it presents the stock tvOS single-row
      keyboard (123 / SPACE / a–z / delete) above the results area with the field placeholder in
      place. `testSearchTabIsReachableAndTakesFocus`, with the frame attached.


---

## Pass 1 findings — 2026-09-15

**B26 load circle — checked, correct.** `ApplePlaybackSpinnerPolicy.showsScreenSpinner` requires
`route == .none && !hasRouted`; `AppleTransportOverlayModel.showsWaitingIndicator` requires
`route == .surface`. Mutually exclusive, so the two-spinner report is already fixed. Confirmed by
frame-stepping an open: 18 captures from launch to first frame, never two at once.

**B1 heroes drew text on black (fixed).** `AppleRemoteImage`'s loading fill is
`Color.white.opacity(0.025)` — deliberately near-invisible, which is right for a poster in a shelf
and wrong for a full-bleed billboard. At 2.5% white over black the hero is a void, so the title,
metadata, synopsis and pills sat on nothing until the art arrived. The fill is now a parameter;
billboards pass `AppleDesignTokens.surface`, shelf posters keep the quiet default.

**B33 settings width (fixed).** The Sources list was **1000 pt wide through the split view and
900 pt pushed on its own** — the same rows putting their chevrons in two different places depending
on how the viewer got there. `appleSettingsPane` used `formMaximumWidth`; every standalone page uses
`formColumnWidth`. Now one width. Measured: chevron column moved 1512 → 1412.

**B30 next-episode card (fixed).** Was using a 16 pt corner radius, a 0.75 black panel, `.headline`
and a bare 16 pt inset — all its own, none of them the app's. Now `cornerRadiusCard`,
`AppleDesignTokens.surface`, the Live strip's title size, and the app's own column inset.

**B21 detail action row — checked, correct.** Play and the My List / Rate discs already share a
centre through the custom `.appleTVControlCenter` alignment guide, and the labels clear the 60 pt
bottom safe inset (bottom at ~1015 against a 1020 line). The earlier focus-ring-over-label bug is
gone. Left as is.

**F1 search (fixed).** See FEEDBACK.

### Not yet done
Chapter markers · widgets + Live Activity · empty-install sims (tvOS + iPhone) · web portal audit ·
iPhone/iPad pass · remaining settings panes.

### Note
Four test files on the SMB share are read-only (`AppleTVSettingsLayoutTests`,
`AppleAddonManifestEdgeCaseTests`, `AppleSourceLogoRefreshTests`, `AppleTVDetailMetricsTests`), so
one assertion I wanted to add for the unified form width could not be written.

---

## Queue added 2026-09-16 (owner)

### G. "Where to watch" — subscription handoff (opt-in)

Design constraints from the owner, verbatim intent:

- [F] G1 **Opt-in, never default.** Nothing appears until the viewer adds a service themselves.
- [F] G2 **Only services the viewer says they subscribe to.** Corrected wording: the app has no
      way to verify a sign-in and never asks for service credentials.
- [F] G3 **Stay in the app by default.** A local or add-on source keeps `Play`. The external
      option is "a very subtle also available to stream on (platform)", not a second button.
- [F] G4 **Play becomes the external option only when there is nothing else** — no local file,
      no add-on stream.
- [F] G5 **Subscription and free-with-ads only. Never rent or buy.** TMDB's
      `/watch/providers` splits results into `flatrate` / `free` / `ads` / `rent` / `buy`, so this
      is a filter, not a heuristic: keep the first three, drop the last two. This is the
      owner's "not purchase options cause prime does that a lot".
- [F] G6 **Say which it is** — ads vs no ads — rather than implying a clean stream.
- [F] G7 Region-correct — required, never defaulted
- [ ] G8 Honest about deep-link depth: title-level links need partner agreements; without one the
      handoff opens the app, not the title. Do not imply otherwise in the UI.

### H. iOS widgets + Apple Watch

- [F] H1 iOS / iPadOS widgets — target built, embedded and installing 2026-09-16 (Continue Watching, small/medium/large)
- [F] H2 Live Activity for background downloads — built and wired 2026-09-16
- [F] H3 **Apple Watch app** — embedded, installed on a paired Watch sim and verified on screen 2026-09-16
- [x] H4 Watch now-playing + transport — **verified end to end on paired simulators**, correcting
      the earlier note here. With both halves of the pair booted the link reports
      `paired=true installed=true` in the trace, and the wrist showed "S1 E1 · First Response"
      with skip-back-10 / play-pause / skip-forward-10 against a playing phone. The play/pause
      glyph tracking the phone's phase was broken and is fixed (see the phase-republish entry).
      It does **not** need a real paired Watch; it needs both simulators booted at once.

### I. AirPods awareness

- [x] I1 Spatial Audio — already present: capability tracking, `spatialPlaybackCapabilitiesChangedNotification`,
      `renderingModeChangeNotification`, and `allowedAudioSpatializationFormats = .monoStereoAndMultichannel`
      on both engines
- [F] I2 Auto-pause on removal — **was missing**, fixed 2026-09-16. Deliberately no auto-resume.
- [F] I3 Route-change handling — the reason was recorded and ignored; now drives the pause
- [F] I4 Play/pause from the AirPods stem — **was entirely absent**, built 2026-09-16
- [x] I5 `allowedAudioSpatializationFormats` set on both `ApplePlayerSession` and `NativePlaybackEngine`

### Already done, not to be redone
- **Auto Play Next Episode is already optional** — `AppleSettingsStore.autoPlayNextEpisode`,
  Settings → Playback, on by default, verified on device reading **On**. With it off the card still
  appears and still works; only the unattended start stops.

---

## Empty-install pass — tvOS, 2026-09-16

**Blocked on the "older tvOS" part.** Only tvOS 26.2 is installed; an older runtime is a multi-GB
download I did not start unprompted. Did the substance instead — a fresh throwaway sim
(`E2FBE387-D71F-4977-91AC-A4E118920DDE`, Apple TV 4K 3rd gen at **1080p**, the canvas the app's
metrics assume) with no sources at all. Kept for the rest of the empty pass, to be deleted after.

- [F] D4a **OLED black was on Library only.** Measured on the empty sim: Library `rgb(0,0,0)`,
      Discover/Live/Settings `rgb(39,41,37)` and `rgb(43,40,30)` — and *not flat*, two sample points
      gave two values, because it is the tvOS system **material**, which also breaks the
      no-gradients rule. Cause: Discover's `.background(Color.black)` was on the **populated branch
      only**, so an empty tab fell through to the system ground. **Fixed at the root** — one
      black ground for every tab. Verified `rgb(0,0,0)` on all four.
- [F] D4b **"Open Settings" jumps between tabs.** Measured: pill centre y=**598** on Discover,
      y=**504** on Library — a 94 pt jump when flipping tabs. Cause is structural, not a number:
      Discover's empty state centres in the whole tab area; Library's sits *inside* the ScrollView
      centred on `viewportSize − 32`. Fix is to give Library the same shape as Discover (empty
      state as a sibling of the ScrollView, not a row inside it) rather than tuning an offset.
      **Done** — Discover, Library and Live now all put the pill at y=598.
- [x] D4c Library empty state itself is correct — "No Videos" + one action, centred.
- [x] D4d **Retracted — not a bug.** The tab changes were my own leftover review key.
      `OpenStreamVisionScreen` lives in the simulator's defaults domain, **not the app container**,
      so `simctl uninstall` does not clear it and a "fresh" install kept navigating to whatever the
      last measurement loop had set. With the domain actually deleted: **zero tab changes in 30 s**.
- [x] D3 First-run card on a genuinely fresh install — correct: brand mark, title, Open Sources
      focused, Not Now, on true black.


## Settings panes — 2026-09-16

All nine tvOS panes reviewed (Sources, Channel Manager, Live TV, Discover, Services, Playback,
Privacy, Storage, About). Consistent: true black, uppercase section headers, 900 pt form column,
value rows right-aligned, sidebar selection legible.

- [F] **"Zero KB"** on Storage — three rows read it beside real values like "4.5 MB".
      `ByteCountFormatter` spells zero that way by default. Now "0 bytes", app-wide.
- [x] Storage disabled actions: "Clear Metadata" and "Delete All Downloads" correctly dim when
      there is nothing to clear, while "Clear Cache" stays live at 4.5 MB. Proper disabled
      semantics, not a dead-looking control.

### G progress 2026-09-16
- [F] TMDB `watch/providers` request wired, region-keyed, 5 tests with a stubbed loader
- [F] Settings → Services → **Streaming Services**, built and verified on screen 2026-09-16
- [F] Title-page "also available on" row — built 2026-09-16
- [x] G8 honest copy — the row states availability and promises no deep link; the
      tap-to-open case is deliberately not built until the link depth is decided

## iPhone pass — 2026-09-16

- [F] **`&amp;` shown verbatim in overview text.** The *9/11: One Day in America* hero and
      title page both read "the 9/11 Memorial `&amp;` Museum". Catalogue add-ons return text
      escaped for a web page upstream and nothing decoded it.
      Fixed with one shared decoder (`AppleHTMLEntities`), applied at the single point every
      catalogue item is built. `&amp;` is decoded **last** so already-escaped `&amp;lt;`
      cannot collapse into real markup.
      A fresh install still showed the bug after the first fix, which exposed the deeper
      cause: `AppleCatalogItem` used the **synthesised** `Decodable`, so anything already in
      the on-disk cache was assigned straight to the stored properties — skipping trimming,
      clamping *and* the new decode. Cache rehydration now routes through the same
      initialiser, so a viewer whose cache predates a normalisation fix is repaired on read
      rather than keeping the old text forever.
      Proven twice: 8 tests (incl. encode/decode round-trip stability) and a device capture
      against a cache written *before* the fix.
- [x] Toolbar glyph pair (B7 on iPhone) — search + refresh in the stock toolbar, right-aligned
      with the large title, inside the safe area, white not blue.
- [x] Captions anchor to the video, not the screen — confirmed on a 2.39:1 title on a 6.9"
      phone: the cue sits just above the letterbox edge, not at the bottom of the display.

### Measurement artifacts caught this pass (not defects)
- Cold launch appeared to auto-play video on a fresh install. Cause: `OpenStreamVisionScreen
  = play`, **my own** DEBUG hook, left set from an earlier capture. It did not appear in the
  container's `.plist` because cfprefsd still held it — `xcrun simctl spawn <id> defaults read`
  is the read that tells the truth. Same class as the earlier "self-navigating tabs" artifact.
- `xcrun simctl install` silently installed nothing because the product is `OpenStream iOS.app`,
  not `OpenStream.app`; the launch then ran the *previous* build and the capture would have
  "proved" old code. Always confirm `INSTALLED` before trusting a capture.

## Discover tab icon — 2026-09-16 (owner: "yeah lets not do boxes please")

- [F] **Discover tab rendered as a solid white slab.** Root cause is not the symbol that was
      chosen but the one the system substitutes: **tab bars apply the `.fill` variant
      automatically**, and at tab size `sparkles.tv.fill` loses the sparkles entirely, leaving a
      blank TV rectangle. The code picked outline variants consistently — the box came from the
      substitution, which is why reading the source alone would never have found it.
      Now `sparkles`, which has **no** `.fill` counterpart and therefore stays line art in every
      state. Verified on both platforms: iPhone before/after, and the tvOS bar.
      Guard test added: no tab may use a symbol whose `.fill` variant is a solid rectangle.

## Channel Manager — 2026-09-16 (owner: "channel manager and settings in there should be no boxes")

- [F] **Two boxed toolbar buttons on tvOS.** "Search Channels" and "Refresh" were
      `ToolbarItem(placement: .primaryAction)`, and a tvOS toolbar item always draws a box around
      its glyph — the same defect already fixed on Discover (T4) and Search (R1). They were also
      **clipped by the screen edge**, rendering as "Searc  hannels" / "R  sh".
      Both are now ordinary rows in the form, in their own section, with leading glyphs.
- [F] **Regression I introduced, caught before it shipped.** Putting those rows at the *head of
      the channel list* moved focus such that the Settings tab drew its selection pill **without
      the gear and overflowing the right edge of the tab bar**. Proven mine by A/B: the original
      build had a correct pill, and a build with the toolbar removed but no rows added was also
      correct — so the rows, not the toolbar removal, caused it. Moving them into their own
      section fixes it; verified on screen.
- [x] Other Settings panes: swept every `.toolbar` in the sources for tvOS reachability. Only
      Channel Manager had one; the two remaining tvOS toolbars are `.toolbar(.hidden, …)`, which
      remove chrome rather than add it. No other boxed items in Settings.
- [x] **Correction (2026-09-16):** an earlier note here claimed `AppleLibraryTVView`'s
      `.buttonStyle(.bordered)` drew boxes on tvOS. It does not — both call sites are inside
      `#if os(iOS)`. The note was wrong and is withdrawn.
- [F] **ZIP code field sat in the form permanently, empty and disabled.** It only means anything
      for the regional lineup, so on a television it read as a broken field rather than an
      inapplicable one. Now disclosed only when Live view is Regional — the same pattern the
      Custom Package section below it already used. Verified both ways on screen: absent under
      Provider Lineup, present under Your Regional.

## Title page text collides with the status bar (iPhone) — 2026-09-16

- [!] **Scrolled overview text runs under the status bar with nothing behind it.** On the title
      page the clock, wifi and battery glyphs are drawn directly on top of the words ("In official
      collaboration with the 9/11 Memorial & Museum…"), and the Dynamic Island cuts through the
      first line. Reproduced on the episodes anchor; it is the normal consequence of scrolling,
      not a one-off position.
      Cause: the page hides the navigation bar on iOS (`AppleDiscoverView.swift`,
      `.toolbar(.hidden, for: .navigationBar)`), so there is no bar material for scrolled content
      to pass beneath.
      **Needs an owner decision, because every fix touches something already approved:**
      (a) stop hiding the bar and let iOS apply its standard scroll-edge material once the hero
          scrolls away — stock Apple behaviour, but the bar then exists on a page designed
          without one;
      (b) inset the content below the safe area — kills the edge-to-edge backdrop;
      (c) leave it.
      A scrim behind the status bar is the usual third answer and is ruled out by the
      zero-gradients rule.

- [F] **tvOS: a Siri/intent `.search` route pushed an iPhone-shaped search page.** Fixed
      2026-09-16 — the route now selects the Search tab that already exists, and Discover no
      longer pushes its own search page where a Search tab is present
      (`AppleSearchRoutePolicy`, 4 tests). Compiles on tvOS; **on-device verification still owed**
      — it needs `simctl openurl` against the sim, which the owner is currently using.
      Original finding follows.
- [~] **tvOS: a Siri/intent `.search` route pushes an iPhone-shaped search page.**
      `router.route == .search` sets `showsSearch` on every platform
      (`AppleDiscoverView.swift:327`), which pushes a destination carrying
      `.navigationTitle("Search")` — on tvOS a navigation title draws over the page, and tvOS
      already has Search as its own tab. Narrow path (deep link / App Intent only), found by
      code sweep, not yet reproduced on screen.

## Top Shelf preview empty on hover — 2026-09-16 (owner report)

- [F] **Continue Watching published with no artwork, so hovering OpenStream on the tvOS Home
      screen showed blank tiles.** Everything in the pipeline was fine — snapshot written
      (12 KB, current), extension embedded, extension point and principal class correct, app
      group entitlement configured, JSON valid with 4 continue-watching and 10 top-pick items.
      The defect was in the data: `AppleSystemArtworkPolicy` trusted exactly two hosts
      (`image.tmdb.org`, `images.metahub.space`), and the owner's in-progress titles were served
      by `images.justwatch.com` and `api.ratingposterdb.com`. **0 of 4** Continue Watching items
      carried artwork; Top Picks survived only because Cinemeta happens to serve metahub — which
      is what made the shelf look intermittently fine.
      The index shows 10+ distinct artwork hosts, so a fixed allowlist can never track what
      add-ons use. The rule is now about what is safe to hand another process: https, no
      credentials, no query, no fragment, and no private/LAN host (a NAS poster is unreachable
      from the extension and would leak an internal hostname).
      **The no-query rule was deliberately kept** — it stops a poster URL carrying a token from
      reaching a system surface, and none of the hosts that actually broke need one.
      Verified: the republished snapshot carries **4/4** Continue Watching artwork (was 0/4).
      Visual confirmation needs a hover on the Home screen: `simctl` has no remote API, so focus
      cannot be moved headlessly.

## iOS/iPadOS widgets had no data source at all — 2026-09-16

- [F] **The Continue Watching widget could only ever be empty on iPhone/iPad.** The widget reads
      the shared snapshot — it runs outside the app container and can see nothing else — but every
      call site that writes that snapshot was wrapped in `#if os(tvOS)`. The phone's app group
      container held **no `topshelf-v1.json` at all**, so there was nothing for the widget to read,
      independent of the artwork bug fixed earlier today.
      The intent had always been to publish on both: `AppleTopShelfWriter.notify()` already
      reloaded widget timelines on iOS and visionOS, which is the mismatch that gave it away.
      Publishing now runs on tvOS, iOS and visionOS, gated by the same "show in Apple services"
      toggle — a widget is exactly that kind of surface.
      Extracted into `AppleSystemSurfacePublishing`: four more modifiers on the root view's body
      put the **iOS type-checker over its limit** ("unable to type-check this expression in
      reasonable time"), which the SwiftPM gate did not catch because that gate builds for macOS,
      where the block was compiled out. A green `swift test` is not proof the phone builds.
      Builds on iOS and tvOS. **Not yet verified on device** — confirming the file appears on the
      phone needs the iPhone sim booted, and the owner is using the tvOS one (one sim at a time).

## Widgets + Watch confirmed on device — 2026-09-16

- [x] **iOS widget data path confirmed end to end.** With publishing no longer tvOS-only, the
      phone writes a 13.5 KB snapshot carrying **2/2** Continue Watching items with artwork and
      **10/10** Top Picks. Both of today's fixes (the tvOS-only writers and the two-host artwork
      allowlist) verified on the phone, not inferred.
- [F] **The widget's empty state lied.** It read "Nothing in progress" whether the viewer had
      genuinely finished everything *or* nothing had ever been published — which on iPhone was
      always the case. Someone with four half-watched shows was told nothing was in progress, and
      the one setting that would fix it was hidden. Now distinguishes the two
      (`AppleWidgetEmptyState`, 4 tests); the unpublished case reads "Off in Settings › Privacy".
- [!] **Publishing is opt-in and defaults off — left as the owner's call.** `topShelfEnabled` and
      `systemSearchEnabled` use bare `defaults.bool` while every "should be on" flag in the same
      initialiser uses `?? true`, so opt-in is deliberate and it sits under Privacy. A new user who
      adds the widget sees the empty state until they turn on Privacy › Apple Services. Flipping a
      privacy default is not mine to make.
- [F] **Apple Watch showed a play button while the phone was playing.** `attach` was the only
      thing publishing a play/pause state and it runs while the engine is still loading, so the
      wrist kept the loading-time value for the whole title. Nothing republished on a phase
      change: `refreshRemoteCommands`, the one method that would have, **had no callers at all**.
      The republish now rides the player's existing 0.25 s bind timer — no new timer — and
      `publish` drops a context identical to the last one that went out
      (`AppleWatchPayload.signature`, 6 tests). Verified: watch went ▶ → ⏸ against a playing phone.
- [x] **Watch↔phone sync works in the simulator** — see FEEDBACK for the recipe. An earlier note
      in this file claiming it needed real hardware was wrong.

## Live Activity for background downloads — 2026-09-16

- [x] **Works, and verified on screen in the simulator.** Drove a real throttled download through
      the existing `-OpenStreamDownloadFixture` harness and captured the compact Dynamic Island
      presentation — download glyph plus "3%" — while another app was foregrounded. No hardware
      needed; an earlier note in this file said otherwise and was wrong.
      Recipe: serve a file slowly over `127.0.0.1`, launch with `-OpenStreamDownloadFixture` and
      `SIMCTL_CHILD_OPENSTREAM_DOWNLOAD_FIXTURE_URL`, then foreground another app so the activity
      surfaces. Over localhost at full speed a 60 MB download finishes before you can look at it.
- [F] **Both Live Activity failure paths were silent.** `guard isAvailable else { return }` and
      `try? Activity.request(...)` meant an activity that never appeared left nothing behind —
      the hardest kind of bug to answer. Both now trace (`live activity: started for …`,
      `request failed — …`, and a once-per-process line when Live Activities are switched off).
      That trace is what proved the feature works, in one line, on the first run.
- [F] **Trace spam I introduced earlier today.** Driving the watch republish off the player's
      0.25 s bind timer put `watch link: paired=… installed=…` *above* the dedup guard, so it
      wrote four identical lines a second and buried the timeline. Moved below the guard.
      Found by reading the trace rather than by a test — worth remembering that a log line is
      part of the interface.

## Empty-install pass, spare iPhone — 2026-09-16

Ran on a throwaway **iPhone SE (3rd gen)** created for the pass and deleted after, so the pass
doubled as a smallest-screen check. Nothing touched the persistent sims.

- [x] D3/D4/D5 all pass — see the ticked rows above.
- [x] Toolbar glyph pair present on Discover and correctly absent on Library/Live.

### Checked and cleared (not defects)
- Settings toggles looked **off** in a downscaled montage while all four tabs were in the bar,
  which would have been contradictory. At full resolution the knob is on the right: they are on.
  Captured a genuine adjacent on/off pair to be sure — **on** is a light track with the knob
  right, **off** is a dark track with the knob left, clearly distinguishable against the dark row
  even with the white brand tint instead of the stock blue.
  A montage downscale is not evidence; this is the same class of artifact as the earlier
  false findings.

## C7 Dynamic Type at the largest size — 2026-09-16

- [F] **Hero pushed Play and Details off the screen.** At the largest accessibility size the
      hero's four-line summary ran about 460 pt, leaving only a sliver of the Play pill above the
      tab bar and pushing Details off entirely — the primary action on the landing screen was
      unreachable without scrolling. The hero already restacks at accessibility sizes; it just
      kept showing four lines of prose. Now 3 lines normally, 2 at the first two accessibility
      steps, 1 above that (`AppleHeroSummaryLineLimit`, 5 tests, including one asserting the
      limit never grows as the type grows). Verified: Play fully visible.
- [F] **Settings row labels wrapped out of their column.** "Channel Manager" put "Manager" on a
      second line starting at the row's leading edge, underneath the glyph, because a stock
      `Label` re-flows at accessibility sizes. iOS rows now take the icon column over at those
      sizes — the same fix the tvOS branch already documents — and the wrapped line aligns under
      the first (`usesFixedIconColumn`, 4 tests). Verified: "Manag-" sits in the "Channel" column.

### A regression I made and caught before recording it
The first version of the column fix used a **fixed** 30 pt slot. An SF Symbol scales with Dynamic
Type, so at the largest size the glyph overran its own frame and landed **on top of the title** —
worse than the bug being fixed, and exactly what the tvOS comment warns about. The slot is now
`@ScaledMetric`, so it grows with the type. Caught by looking at the capture rather than trusting
that a green build plus a green gate meant the screen was right.

## C8 Landscape — 2026-09-16

- [~] **Blocked for capture, covered for behaviour.** `xcrun simctl` cannot rotate a device, so no
      landscape screenshot is possible from this harness. Two routes exist if the pixels matter:
      the owner rotating the sim by hand (⌘← in Simulator), or an iOS UI test target setting
      `XCUIDevice.shared.orientation` — there is a tvOS UI test target but no iOS one, so that is
      a new target rather than a new test.
- [x] Landscape behaviour pinned at the **device extremes** rather than only the mid-size phone
      the existing tests used: iPhone SE (667×375, the least landscape height the app supports)
      and iPhone 16 Pro Max (956×440). Asserted that both are recognised as landscape, that the
      hero leaves at least 150 pt for the shelves even on the shortest screen, that the 16:9 arm
      of the cap is the binding one there, that both hide the tab bar, and that rotating back to
      portrait restores both the tab bar and the fixed portrait hero height. A square viewport is
      asserted *not* landscape, so a transient size mid-rotation cannot flip the layout.
      6 tests.

## C4 Keyboard handoff in forms — 2026-09-16

- [F] **The return key did nothing, on every form in the app.** A sweep of all 25 `TextField` /
      `SecureField` sites found `submitLabel` and `onSubmit` used **zero** times. On a phone that
      means the return key says "return", pressing it does nothing, and the only way through Add
      Live TV or an ARR setup is to dismiss the keyboard and tap each field in turn.
      Add Live TV now chains Name → Server URL → Username, with the last field on screen reading
      "done" (`AppleFormFieldChain`, 6 tests). The chain is computed from the fields actually
      visible, because the form hides Username unless the type is Xtream — so "the last field"
      moves, and a fixed chain would label the wrong one.
      Password is deliberately left out: it is a composed control (field plus reveal button), so
      focus applied to it would land on the wrapper rather than the field inside.
      Applied at the call site, so Apple TV — which has no software return key and drives focus
      with the remote — is untouched. Builds on iOS and tvOS.
- [F] **Remaining multi-field forms chained** 2026-09-16 — ARR (Server URL → API key → Root
      folder → Quality profile), Metadata (TMDB → OMDb), Trakt (Client ID → Client secret) and
      Add Network Share (Name → Server URL → Folder → Username). **15 fields across 5 forms**,
      via a shared `appleFormSubmit(_:chain:focus:)`.
      Deliberately excluded, with reasons: Port and Domain sit inside DisclosureGroups, so
      focusing them when collapsed is a dead end; Password is a field plus a reveal button, so
      focus lands on the wrapper; Quality profile ID uses the number pad, **which has no return
      key at all**, so it is placed last where nothing needs to submit from it.
      Not chained: the three single-field forms (Add Catalog URL, ZIP code, channel search) —
      they would gain only a "done" label, not a handoff.
- [x] Both platforms build. `AppleAddNetworkShareView` already had a tvOS-only `Field` enum for
      remote focus, so the new one is `SubmitField`; the name collision broke **tvOS only** and
      the iOS build stayed green, because the tvOS enum compiles out there. Another case where
      one platform building proves nothing about the other.
- [x] **Return key confirmed on device** through the iOS UI test target: "next" on the first
      field, "done" on the last (`testReturnKeyReadsNextThenDoneAcrossAForm`).
      One honest caveat about the evidence: the screenshots show **no software keyboard**, because
      the simulator has a hardware keyboard connected — which is also why `typeText` works there.
      XCUITest still exposes the return key in the accessibility tree, and that is what reports
      "next" and "done", so the labels are verified even though no picture of the keyboard exists.
      Two capture attempts were wasted before working this out; the first was simply mistimed.

## B12 Library sort accessory — 2026-09-16

- [F] **The sort control could disappear from the Library entirely.** It was placed with
      `source.id == library.sources.first?.id && kind == firstKind(in: local)` — keyed to the
      first *source*, not the first shelf. `library.sources` is every enabled library/NAS source,
      so if the first of them draws no shelves (an offline NAS, or one whose titles all filter
      out), that test fails for **every** shelf and no header carries the sort menu: the viewer
      loses the only way to change the order, with nothing on screen to explain it.
      Now keyed to the first shelf actually drawn (`AppleLibraryShelfLayout`, 6 tests, including
      one asserting exactly one shelf carries it for several library shapes).
      Library verified to still render unchanged; the header itself sits below the fold, so its
      placement is not captured — the harness cannot scroll on tvOS.
- [x] B13 — superseded: answered by construction in section B (a source with no titles draws no
      shelf; the pane-level "No Videos" needs everything empty). This older note is stale.

## B17 Channel numbers were grouped — 2026-09-16

- [F] **Channel 1001 drew as "1,001".** The guide cell rendered the number with
      `Text(number, format: .number)`, which applies the locale's thousands separator — a channel
      number is an identifier, not a quantity. The rail label a few lines away interpolated the
      same value and did **not** group it, so one channel was written two different ways on the
      same screen depending on which view drew it.
      Now `AppleChannelNumberFormat`, 6 tests — including one asserting the new style differs from
      the grouped style it replaced (so the fix cannot silently become a no-op), one checking it
      stays ungrouped in de/fr/en-GB/hi locales, and one asserting it matches plain interpolation
      so the two renderings cannot drift apart again.
      Not visually confirmed: the first guide rows are all 2-digit channels, and reaching a 4-digit
      one needs scrolling the harness cannot do.

## B20 Failure messages — 2026-09-16

- [~] **The jargon is real and located, but the fix is bigger than it looks.** User-facing strings
      still name internal concepts: "This container requires an external demuxer.",
      "External demuxer required.", "Torrent resolver required.", "Gateway unavailable."
- [!] **Naming the endpoint needs a refactor, not a string edit.** The route that knows the URL
      (`ApplePlaybackRoute.requiresExternalDemux(URL)`) **discards it** at the throw site
      (`ApplePlaybackPreparer.swift:194`), and `externalDemuxRequired` exists as a case with no
      associated value in **three** separate enums, matched by `catch` patterns and switches in
      several files. Giving it the endpoint means changing all three and every match.
      Not started: that is a wider change than a checklist row should trigger unsupervised, and
      the live failure itself cannot be reproduced here — the Xtream source needs credentials,
      which I do not enter.

## Sources pane — 2026-09-16

- [F] **"Your Sources" was the only title-case section header in Settings.** Every other pane
      reads SERVER, SHARE, ACCOUNT, CONNECTION, CHANNEL PREFERENCES. The cause is structural: the
      Sources pane is a `List` while the other panes are `Form`s, and on tvOS a Form uppercases
      its section headers while a List does not. Fixed by uppercasing that header explicitly
      rather than swapping the container, which would have restyled every row in the pane.
- [F] **Regression I introduced and caught, twice in one pass.** First, `.textCase(.uppercase)` on
      the *Section* uppercased its **rows** too — every source read "TORRENTIO TB". Scoped to an
      explicit header view instead.
      Second, and more serious: `AppleFormFieldSubmit` applied `.focused` on **every** platform,
      so on tvOS the Add Live TV and Add Network Share fields carried a second focus binding
      alongside the remote-driven one those forms already had. The tab bar then drew its Settings
      pill **without the gear and overflowing the bar** — the same symptom seen earlier on Channel
      Manager. The modifier is now inert on tvOS, where there is no software return key to label
      anyway. Before/after captures confirm the pill is correct again.

## The remote-driven harness works — 2026-09-16

- [x] **`OpenStreamTVUITests` runs and drives the Siri Remote.** Never actually executed before
      this pass; it was assumed available but unproven. All 6 tests pass in 68 s:
      `xcodebuild test -scheme OpenStreamTVUITests -destination id=B251C620-… -derivedDataPath
      ~/Developer/openstream-build/DerivedData-uitests`. This is the route for every remaining row
      that needs a button press (B22–B25, F4), and it can attach screenshots.
      Note: `timeout` does not exist on macOS — an early run "failed" on that, not on the tests.
- [x] Added a **focus-path diagnostic** that prints where each press lands. Not an assertion — it
      exists so the focus path is read off the device instead of assumed.
- [x] **Resolved: not a defect, my navigation was wrong.** The follow-up probe settled it — the
      page opens with `detail.play` **already focused**, and Up from the episode control reaches
      `detail.icon-row` (Rate). The icon row is reachable; Down from Play simply skips past it to
      the episode list, because the row sits on the same line as Play rather than below it. Good
      thing it was not written up as unreachable. Original note follows.
- [~] **B22 could not be tested yet, and the reason is itself worth chasing.** Two attempts failed
      on *navigation*, not behaviour: from the tab bar, Down lands on an episode control whose
      accessibility identifier is **empty** (not `detail.play`), and Right from there walks the
      episode list (E3 → E4 → E5 → E6) rather than reaching My List / Rate — even though a static
      capture of the same page shows both sitting immediately beside Play.
      Either the page auto-scrolls to the episode rail on appear, or the icon row is not in the
      remote's path. **Not reported as a defect**: the evidence is consistent with either, and a
      wrong call here would be the ninth false finding of this session.
      Next probe: press Up from the episode control and dump the path, which separates the two.
- [x] Note for whoever writes the next one: `testTitlePageIconRowTakesFocus` asserts the icon row
      **exists**, not that it holds focus — so it passes whether or not the row is reachable.

## Reading UI-test screenshots — 2026-09-16

Attachments from `OpenStreamTVUITests` are extractable, so a remote-driven screen can be looked at
rather than inferred:

```
xcrun xcresulttool export attachments \
  --path ~/Developer/openstream-build/DerivedData-uitests/Logs/Test/<newest>.xcresult \
  --output-path <dir>
```

`xcresulttool get` now needs `--legacy`; `export attachments` does not. This is how B23 was judged.

## UI suite flakiness — 2026-09-16

- [!] **One run of the 9-test UI suite reported 1 failure; the two runs either side were clean.**
      Not chased down because the failing test was not named in the output I captured, and
      inventing a cause would be worse than recording the fact. The suite is timing-driven
      (`Thread.sleep` between remote presses on a machine also running builds), so a slow frame is
      the likely explanation. If it recurs, the fix is the pattern the auto-hide unit test already
      uses: poll for the condition instead of sleeping a fixed interval.

## B25 Scrolling — 2026-09-16

- [~] **A measurement, not a verdict.** "Smooth" cannot be asserted from a screenshot, so the test
      drives ten rapid Right presses along the Continue Watching shelf, counts how many change
      focus, and records the per-press cost: **619 ms for 10 presses**. That number is the thing a
      future "scrolling is slow" report can be checked against.
- [!] **The obvious conclusion was wrong and is not recorded as a finding.** The counter said focus
      moved on only 1 of 10 presses, which reads as dropped input. The attached frame said
      otherwise: focus was sitting on **Reacher, the fourth and last poster of a four-item shelf**,
      with its focus lift and brighter progress bar — a rail that reached its end and correctly
      stopped. Those two cannot both be right, so the focus key is not a trustworthy measure of
      movement on a rail, and the assertion built on it was removed rather than left to fail
      falsely. What is asserted is only that the shelf still holds focus after the burst.

## Search empty state — 2026-09-16

- [F] **The empty state restated the field's own placeholder.** Above: "Search movies, shows, and
      channels" in the search field. A few hundred points below: "Search movies, shows, files, and
      channels" as the empty-state description. Two near-identical sentences on one screen, and
      the app's standing rule is that empty states carry no explainer copy.
      Removed — the state is now the glyph and "Search Your Sources", nothing else. The
      **no-sources** variant keeps its line ("Titles appear here after you add and refresh a
      catalog source") because that is the one case where the viewer needs telling what to do.
- [!] **The `openstream://search?query=…` deep link still is not verified on device.**
      `simctl openurl` makes tvOS put up its own "Open in OpenStream?" confirmation, which needs a
      remote press that the external harness cannot give — and the dialog it leaves on screen
      blocked the next UI test run until the simulator was restarted. The routing fix itself is
      covered by `AppleSearchRoutePolicy`'s tests.

## Search duplicates — 2026-09-16

- [x] **The episode half of the owner's complaint is confirmed fixed on screen.** Searching
      "jury duty" on iPhone returns movies and series only; no episode rows.
- [F] **Cross-source duplicates now collapse by canonical identity.** The collapse key was
      `title|year`, so the same title from two add-ons stayed apart whenever one of them carried
      no year. Records sharing a canonical (IMDb) id now claim one key and merge
      (`AppleCatalogSearchStore.mergedResults`, 5 tests — including that a *local* file, which has
      no canonical id, still merges into its catalogue entry, which is the merge that puts artwork
      and local availability on one row).
- [!] **The duplicate the owner actually sees is still there, and this did not fix it.** "Jury
      Duty" (2007) appears twice — once from Cinemeta with its year, once from The Movie Database
      Addon with none and identical artwork. Confirmed still present after the change.
      The reason it cannot collapse: `canonicalID` is only set when the catalogue id **is** an
      IMDb id (`AppleMediaIndex.swift:451`), and the TMDB add-on supplies TMDB ids — so that
      record has no shared identity to collapse on.
      Nor is title+kind enough to disambiguate: there are **two** dated "Jury Duty" series (2007
      and 2023), so a yearless one could be either. The only remaining signal on screen is the
      artwork, which is identical — matching on artwork URL would work but is fragile across CDNs.
      **Needs a decision rather than a guess**, which is why it is left open.

## Library TV is built but unreachable — 2026-09-16

- [!] **The whole feature has no way in.** `AppleLibraryTV.swift` models it (Program, Channel,
      Queue) and `AppleLibraryTVTests` covers the model, and `AppleLibraryTVView.swift` is a
      187-line view that renders Now Playing, a channel list and Up Next — but **nothing anywhere
      references that view**. No tab, no route, no navigation link presents it, so a viewer cannot
      reach Library TV at all.
      Found while sweeping A6: I had flagged its buttons as tvOS boxes, which was doubly wrong —
      they are iOS-only *and* the view is never shown.
      Not deleted: a tested model plus a complete view reads as unfinished work rather than dead
      weight, and whether it ships is the owner's call.

## An iOS UI test target now exists — 2026-09-16

- [x] **`OpenStreamiOSUITests`**, added to `OpenStreamApps.xcodeproj` by hand (file refs, group,
      three build phases, native target, Debug/Release configs and their list, plus the product
      and target lists). Self-contained like the tvOS one: no test host, it attaches to the
      installed app by bundle id. Schemes are auto-created here, so no scheme file was needed.
      Run it with:
      `xcodebuild test -scheme OpenStreamiOSUITests -destination id=6A037503-… -derivedDataPath
      ~/Developer/openstream-build/DerivedData-uitests`
      This is the route to everything that needed a **tap or a rotation**: C8 (done), the sheets
      half of C3, and typing a query for F2.
- [F] **A false failure of mine, caught by the attached frame.** The first landscape assertion
      matched an element whose label is "Discover" — which also matches the **navigation title**,
      not just the tab. It reported "the tab bar is still showing in landscape" while the
      screenshot showed the bar correctly hidden. Now matched against `app.tabBars` directly.
      Same lesson as the earlier montage and focus-key traps: assert on the thing, not on a label
      that something else also carries.

## F2 driven from inside the app — 2026-09-16

- [x] **Searched the way a viewer does**: tapped the toolbar glyph, typed "jury duty", read the
      rows — no deep link involved. Rows are aligned and consistent: poster, title, source name,
      kind + year, chevron, one column each, uniform artwork. **Zero episode rows**, asserted as
      well as seen, which confirms that half of the owner's complaint from inside the app.
- [!] **The duplicate did not appear this time, and that does not mean it is fixed.** This run
      returned four distinct rows (Drawn for Jury Duty 2010, Jury Duty 2023, Jury Duty 1995,
      Jury Duty 2007) with no repeat. The earlier deep-link run returned a yearless TMDB "Jury
      Duty" alongside the dated Cinemeta one, which is the pair that cannot collapse.
      The add-ons simply did not return that yearless entry this time. The duplicate is therefore
      **intermittent and data-dependent**, not fixed — the decision about how to collapse it is
      still open.

## Owner report: wrong show plays for early episodes — 2026-09-16

- [F] **"The Secret Lives of Mormon Wives": metadata is right, but playing episodes (mainly 1–2)
      gives a different show entirely.** Owner report against **TestFlight build 10**. Diagnosed
      and fixed from the owner's answers; see below. Original note follows.
      Metadata being correct rules out the episode-identity mapping — `episodeIdentity` validates
      that the series id, season and episode all agree before an episode is listed, and the title
      page shows the right thing. That puts it in **stream/file selection**, after the episode is
      chosen.
      First place to look, from reading the path: `AppleStremioStreamingServer.playbackCandidates`
      resolves which file inside a torrent to play. It passes `seriesInfo` (season + episode) so
      the streaming server can guess, but when the add-on supplies no `fileIdx` **and** the
      server's `guessedFileIdx` comes back nil, the code falls through to
      `let selectedIndex = resolvedIndex ?? -1` — an index of **-1**. For a season pack that is
      not "episode 1", and on a pack containing anything else it is whatever the server picks.
      That would show up exactly as "the metadata is right but the video is a different show", and
      would bite hardest on the episodes most likely to be bundled in packs.
      Not yet confirmed: needs the owner's answers below, then a reproduction with the trace on.

### Diagnosis and fix — wrong show on early episodes

The owner's three answers settled it without a reproduction:
**same wrong show every time** (so not random file-picking), **another source plays correctly**
(so the right content exists and the add-on is fine), and **metadata is correct** (so the episode
mapping is sound).

That leaves candidate **ranking**, and the code confirmed it: `AppleStremioCandidateRanking`
ordered candidates by resolution → size → container → provider order, and **nothing checked that a
candidate was even the episode being requested**. A mislabelled release that happens to be 1080p
and large therefore wins on quality alone — and wins *every time*, because the sort is
deterministic. That is exactly "the same wrong show, and picking another source by hand works".

- [F] Automatic playback now passes the season and episode into the ranking. A candidate whose
      name states a **different** episode sorts below every candidate that does not contradict it,
      whatever its resolution (`AppleStremioEpisodeFilenameMatch`, 8 tests).
      Deliberately conservative in two ways: a name that states **no** episode is not a
      contradiction, so season packs — where the file index inside the torrent picks the episode —
      are untouched; and contradicting candidates are **demoted, not dropped**, so if every
      candidate contradicts the viewer still gets something rather than nothing.
- [~] **Attempted reproduction: inconclusive, and my first read of it was wrong.**
      Driven end to end on iPhone (search → title page → episode 1). The title page is **correct**
      — "The Secret Lives of Mormon Wives", Reality-TV 2024–, episodes "The First Book of Taylor"
      (S1 E1, Sep 6 2024) and "The Book of Belonging" — which confirms the metadata half of the
      report.
      A frame captured 40 s into playback showed scenery with a "5" watermark and the subtitle
      "♪ Doing something unholy… ♪", and I called that a reproduction. **That was premature.**
      Revealing the transport showed a **54-minute** runtime (position 1:26, remaining −52:51) and
      the dialogue "You're trying to be an example" — a plausible length for this episode and a
      line that fits the show. "Unholy" is an apt needle-drop for a series about a swinging
      scandal, so the earlier frame is just as consistent with a correct opening montage.
      **Verdict: cannot say the wrong show played here.** Not evidence the fix works either; the
      candidate that wins may simply differ from the owner's run. Needs the owner's own check on a
      build containing the fix.
