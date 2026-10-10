# Live + portrait hero redesign — iPhone/iPad iOS 18 (2026-10-09)

Target: iPhone 15 Pro Max, iOS 18.7, portrait (430 × 932 pt, status bar 59 pt, home indicator 34 pt, tab bar 49 pt).
Owner verdict on Live today: "not modern, not clean, very AI, cheaply put together". Likes Paramount+ Live; DirecTV somewhat.
Scope: OWNER-TODO "UX overhaul" items 6–15, 19, 20, plus the Live PiP item. Back end is fine; this is front end only.
Builds on `specs/ux-research-2026-10-09.md` (its Top 10 stands; this spec decides the open points and gives exact values).
Rules that bind every line below: SF Symbols only, standard controls, Dynamic Type, 44 pt targets, no explainer text,
nothing blue except the brand accent `#FF3366`, no gradients over video, controls auto-hide, system tab bar untouched
(no custom paint), tvOS unchanged.

## 0. Critique of what ships today (build 17)

`⚠️ DEGRADED: single-context (design-only task; impeccable's detector is web-only, no sub-agents spent)`

Evidence: `verification-artifacts/live-2026-10-08/after/s1-26s.png`, `ux-tour-2026-10-08/iphone-06-live-*.jpg`,
`AppleMediaSourceViews.swift:143-325, 1311-1356, 1986-2537`, `AppleTransportOverlay.swift:395-440, 565-600, 880-900`.

| # | Finding | Why it reads cheap | Heuristic |
|---|---|---|---|
| 1 | Inline nav bar "Live" + a 44 pt circled search button, then a 16:9 box that starts 150 pt down (`s1-26s.png`) | Two rows of chrome before any picture; the video is a "cut-off box" (owner #7, #9) | Hierarchy, use of space |
| 2 | Nothing names the channel or programme while playing; the grid below is a `Channels` column + time grid with "No information" cells in a dark-pink wash | The current channel is invisible (owner #7); the pink wash + magenta now-line is the only colour on screen and it is on the least important thing | Visibility of system status; colour discipline |
| 3 | Category row is a horizontal `ScrollView` of text buttons sitting inside the guide column, under an optional failure row and an optional cap notice (`:218-285`) | Its y-position depends on whatever rows appear above it, so it moves ("floats and jumps", owner #8) | Stability, consistency |
| 4 | Landscape/portrait are two different view trees (`:305-319`); size change rebuilds the player (Duo audit finding 2) | Channel restarts on iPad rotation | Technical robustness |
| 5 | Inline player chrome: `play.fill` 34 pt centred, mute top-right, fullscreen top-LEFT, captions bottom-right, "Last Channel" bottom-left, a blurred "Back to Live" capsule (`:2040-2113`) | Five controls in five corners, no grouping, uses `arrow.uturn.backward` for Last Channel | Grouping, standard controls (owner #13, #15) |
| 6 | Fullscreen: `xmark` inside a 1 pt stroked circle (`AppleTransportOverlay.swift:404-408`), text buttons "Channels" and "Last Channel" in the top row, a stock `Slider` with thumb for a live scrubber, "LIVE" caption in red/grey | The stroked circle and bare text buttons are the "tacky X / tacky buttons" (owner #12, #13); the thumbed slider is the "loud" bar (#14) | Stock Apple look |
| 7 | Error pages: `Couldn't Load Your Channels` with two stacked pills (white + grey), or `Kids Four is not broadcasting right now.` + `127.0.0.1 is not sending this channel.` + `Try Again` inside the player box, pushing the grid down | Cause never named by source; an IP block reads as "stream limit" (owner #20); the error moves the layout | Error clarity, layout stability |
| 8 | Hero (`AppleHomePhoneHeroLayout.artFraction = 0.73` of screen, art = `backgroundURL ?? posterURL`, `scaledToFill` centred, `.clipped()`) | A 16:9 backdrop centre-cropped into ≈ 430 × 640 keeps a 232 pt wide slice: faces off-frame, "too zoomed in" (owner #6, #19) | Imagery |
| 9 | Hero trailer paused state: play glyph in a circle in a circle (owner #5) | Three nested shapes for one action | One control per state |

ui-ux-pro-max (`--stack swiftui`, `--domain ux`): use `List` for the scrollable channel list (not `ScrollView` + `VStack`);
every tap gets feedback within 100 ms (row highlight, WATCHING pill moves immediately, before the stream starts);
44 × 44 targets with ≥ 8 pt gaps; reserve space so nothing shifts when data arrives (progress line, logos, error card);
icon-only buttons need `accessibilityLabel`s. All applied below.

## 1. Live tab — iPhone portrait

### 1.1 Structure (one fixed header, one scroller)

```
┌──────────────────────────────────────────┐ 0
│ 9:41                        ●●●● ◔ ▮    │ status bar, black (59 pt)
├──────────────────────────────────────────┤ 59
│                                          │
│                                          │
│              VIDEO 16:9                  │ 430 × 242 pt, edge to edge
│          (AVPlayerViewController host)   │ no nav bar, no title
│                                          │
│                                          │
├──────────────────────────────────────────┤ 301
│ [logo]  ESPN                   1:12 left │ Now Playing bar, 56 pt
│         NFL Live                         │ name 15 semibold / title 13 secondary
│▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬│ 2 pt progress line, full width
├──────────────────────────────────────────┤ 357
│ All   Favorites   Sports   News   Mo…  ⌕ ▦│ category bar, 44 pt (FIXED, never scrolls)
│ ───                                      │ 2 pt underline under the selected tab
├──────────────────────────────────────────┤ 401
│ [logo]  ESPN                             │ ← List starts here and is the ONLY scroller
│         NFL Live            WATCHING  ≣  │ row 64 pt
│         ▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬            │
│ [logo]  FOX Sports 1                     │
│         UFC Countdown                 ≣  │
│         ▬▬▬▬▬▬▬▬▬                        │
│ [logo]  CBS                              │
│         60 Minutes                    ≣  │
│         ▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬                │
│   …                                      │
├──────────────────────────────────────────┤ 849
│  ✦ Discover   ▤ Library   ((•)) Live  ⚙ │ system tab bar, 49 + 34 pt
└──────────────────────────────────────────┘ 932
```

- Root: `VStack(spacing: 0) { AppleLiveStage (player); AppleLiveNowPlayingBar; AppleLiveCategoryBar; AppleLiveOnNowList }`.
  The first three are fixed; only the `List` scrolls. Nothing is pinned inside a scroll view, nothing floats, so the
  category bar cannot jump and the player cannot be scrolled off. `.toolbar(.hidden, for: .navigationBar)` on the Live root
  on iPhone (already done for tvOS, `AppleMediaSourceViews.swift:1169`).
- The "Live" title is gone on iPhone (the tab bar names the tab). Search = `magnifyingglass` icon in the category bar.
- The status bar stays on black above the video (not over it): nothing covers the picture and the player keeps its full
  16:9 frame. Player height = `floor(width × 9 / 16)` = 242 pt on the 15 Pro Max.
- Before a channel has ever been chosen: the same 16:9 frame holds the last-watched logo (existing
  `AppleLiveConnectingArtwork`, kept, renamed `AppleLivePlaceholderStage`) — the frame never changes size.

### 1.2 Player (the one stable container)

- One `AppleLivePlayerContainerViewController` (existing, `:1986`) hosted by one `UIViewControllerRepresentable`, created
  once per `ApplePlaybackCoordinator` (`.id(ObjectIdentifier(playbackCoordinator))` stays). It is placed by a custom
  `Layout` (`AppleLiveStageLayout`), never by `if portrait { … } else { … }` branches: the Layout places the same child
  views stacked (compact width) or side by side (regular width), so SwiftUI identity never changes and the channel never
  reloads on resize. This is Duo patch 03's intent, done with `Layout` instead of a shared `ScrollView`. `LivePinnedPlayerLayout`
  (`:1311-1356`) is deleted.
- The player view is a plain black rectangle: `videoGravity = .resizeAspect`, no corner radius, no border.
- Inline chrome (shown on tap, auto-hides after 3 s, hidden immediately on the fullscreen transition):
  - centre: `pause.fill` / `play.fill`, 34 pt symbol in a 64 pt target;
  - top-right, one `HStack(spacing: 4)`: `speaker.wave.2.fill` ⇄ `speaker.slash.fill`, `captions.bubble` ⇄ `captions.bubble.fill`
    (menu, same entries as today), `arrow.up.left.and.arrow.down.right`; each 44 × 44, symbol 20 pt semibold, white,
    `shadow(.black 40 %, radius 2)`;
  - nothing in the other corners. The "Last Channel" and "Back to Live" buttons leave the inline player (they move to
    the fullscreen `…` menu and the row list respectively). The existing `UISwipeGestureRecognizer` up/down zap stays.
  - Buffering: a `ProgressView().controlSize(.large).tint(.white)` centred, replaces the play glyph; nothing else.

### 1.3 Now Playing bar (56 pt, always visible while a channel is selected)

- `HStack(spacing: 12)`: logo slot 44 × 28 (`scaledToFit`, no background), then `VStack(alignment: .leading, spacing: 2)`:
  channel name (`.subheadline.weight(.semibold)`, primary), programme title (`.footnote`, secondary, 1 line, `.truncationMode(.tail)`).
  Trailing: time left (`.footnote.monospacedDigit()`, secondary) — "1:12 left" (h:mm) under an hour "23 min left".
- Progress line: 2 pt, full width, at the bar's bottom edge: track `white 12 %`, fill `brandAccent`, fraction =
  `(now − start) / (end − start)` from `guide.nowAndNext(channelID:)`; updated by a `TimelineView(.periodic(by: 30))`.
  No EPG → title row shows the channel group (e.g. "Sports"), no time, no line (track still drawn so the height is constant).
- Tap the bar → opens this channel's schedule sheet (same as the row's trailing glyph). The bar is one accessibility
  element: "ESPN, NFL Live, 1 hour 12 minutes left, Now playing". Identifier `live.nowPlaying`.
- Padding: horizontal 16. Background: black. Separator under it: none (the category bar's own baseline is the separator).

### 1.4 Category bar — decision: fixed underlined text tabs

Decision: Paramount+-style underlined text tabs, fixed in the header, not chips, not a menu.
Why: one tap per switch (a Filter menu costs two taps and hides the state); it is the exact pattern the owner likes; the
"floating, jumpy" complaint was about position, not the tab style, and a fixed header cannot move. Favorites stays a tab
(not a section): a section would put favourites at the top of "All" and double every favourite row.

- Height 44. `ScrollView(.horizontal)` of `Button`s, `.scrollIndicators(.never)`, `.scrollTargetBehavior(.viewAligned)` not
  needed; selected tab is scrolled into view with `scrollTo(id, anchor: .center)` on change.
- Tab label: `.subheadline.weight(.semibold)` (15 pt), selected = primary white, others = secondary; 2 pt `brandAccent`
  underline the width of the text (`.overlay(alignment: .bottom)`), `.animation(.easeInOut(0.2))` on the selection;
  horizontal spacing 24; leading inset 16; trailing fade 24 pt (`mask` with a linear alpha, this is a mask over text, not a
  scrim over art). Each button `frame(minWidth: 44, minHeight: 44)`, `.accessibilityAddTraits(.isSelected)` (keep).
- Order: `All`, `Favorites` (only when `settings.favoriteChannelIDs` is non-empty), `Events` (only when
  `settings.showPayPerViewChannels` and `AppleIPTVLineupPolicy.isPayPerView` matches ≥ 1 channel), then the lineup groups in
  provider order (existing `channelSnapshot.categories`).
- Trailing, outside the scroller, fixed: two 44 × 44 icon buttons: `magnifyingglass` ("Search Channels", opens the existing
  search sheet, `AppleLiveSearchModifier` kept) and `calendar` ("Guide", opens the time grid sheet, §1.6). Symbol 17 pt
  semibold, secondary colour, no circle background. Identifiers `live.search`, `live.guide`.
- The source-failure row and the "Showing N of M channels" cap notice (`:262-285`) move out of this header: the cap
  notice becomes the List's footer (`.footnote` secondary, centred); a failed playlist becomes a List section header row
  "Couldn't load Home IPTV · Try Again" (§3), so neither can move the tabs.

### 1.5 On Now list (`List`, `.listStyle(.plain)`, the only scroller)

- Row 64 pt (grows with Dynamic Type; at accessibility sizes the logo column is dropped and text wraps to 2 lines):
  ```
  │ [logo 44×28]  Channel Name                         [WATCHING]  ≣ │
  │               Programme title                                    │
  │               ▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬ (2 pt, brandAccent on white 12 %)  │
  ```
  Name `.body`, title `.subheadline` secondary 1 line, progress line spans the text column only. No EPG → title = "" and the
  line is hidden but its 2 pt row is reserved (no reflow when EPG arrives). Separators: system `.listRowSeparator`, inset to
  the text column (`.alignmentGuide(.listRowSeparatorLeading)`).
- Trailing `list.bullet.rectangle` 17 pt secondary, 44 × 44 target: opens that channel's schedule sheet (next 12 h, plain
  rows "8:00 PM · Title", current one bold, catch-up rows tappable where `catchUp != nil` → existing `playProgramme`).
- WATCHING state (current row): capsule, `brandAccent` fill, `caption2.weight(.bold)` white "WATCHING", padding 8 × 3, placed
  before the trailing glyph; the channel name turns `brandAccent`? No — name stays white; the pill is the only marker.
  The pill moves on tap, before the stream starts (`selectedChannel` changes synchronously; the probe runs after). On tap the
  List also scrolls so the row stays visible (`scrollTo(id, anchor: .center)` only if it is off-screen).
- Swipe actions: leading `heart`/`heart.slash` ("Favorite"/"Unfavorite"), tint `brandAccent`; trailing `eye.slash` ("Hide")
  → existing hidden-channels setting. Channel health (`onShowHealth`) → long-press context menu "Channel Info".
- Events tab rows use the same row: logo, event name (channel name), programme = the event's time window if the EPG has it.
  "How do I get to pay-per-view" (owner #11) is answered by the `Events` tab; when the PPV setting is off, the tab is absent
  and Settings › Live TV › "Show pay-per-view" is unchanged.
- Empty category: one centred `.footnote` secondary line "No channels" — no icon, no button.
- `List` is lazy: UI tests scroll before asserting (AGENTS.md §5).

### 1.6 Guide sheet (time grid, secondary)

- `calendar` button → `.sheet` with `.presentationDetents([.large])`, `.presentationDragIndicator(.visible)`, containing the
  existing `AppleIPTVGuideGridView` filtered by the selected category, title "Guide" in an inline nav bar with a `Done`
  button. Row tap plays and dismisses. The grid's pink cell wash and magenta now-line become: cell background `white 6 %`,
  current cell `white 12 %`, now-line 1 pt `brandAccent`. Nothing else in the grid changes.

### 1.7 Tab bar over the list — decision: hide on scroll down, show on scroll up

Decision: hide on scroll down, show on scroll up or when the list is at its top; never opaque paint (owner rule: system tab
bar, no custom background). iOS 18 has no `tabBarMinimizeBehavior` (iOS 26), so:

- `AppleLiveTabBarVisibility` (pure): input = scroll offset deltas; rule: hide after 24 pt of downward travel, show after
  12 pt upward or when `contentOffset.y <= 0`; ignore deltas while the content is shorter than the viewport.
- iOS 18: `List.onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y }` (iOS 18 API) feeds the policy; the
  result drives `.toolbar(hidden ? .hidden : .visible, for: .tabBar)` on the Live tab's `NavigationStack` root inside
  `withAnimation(.easeInOut(duration: 0.25))` (iOS 18 animates this toggle). The List keeps `ignoresSafeArea(.container,
  edges: .bottom)` plus `contentMargins(.bottom, 49 + 34)` so the content inset does not change when the bar leaves and
  nothing jumps. Reset to visible on tab change, on `scenePhase` change, and when the channel picker/sheet opens.
- iOS 26: `if #available(iOS 26, *) { .tabBarMinimizeBehavior(.onScrollDown) }` and the manual toggle is bypassed.
- Haptic: none. Reduce Motion: toggle without animation.

### 1.8 Scroll behaviour

- The player, bar and tabs are outside the scroller: no sticky-header maths, no `GeometryReader` on scroll, no `pinnedViews`.
- Pull-to-refresh on the List (`.refreshable`) reloads the lineup (replaces the `Try Again` pills for the healthy case).
- The List's top content inset is 0; the first row sits right under the category bar's baseline.

### 1.9 iPad and landscape (brief)

- Regular width (iPad, Duo inner screen via `AppleAdaptiveCanvas.isLarge` after patch 01): `AppleLiveStageLayout` places
  the player column (62 % of width, 16:9, top-aligned, Now Playing bar under it) and the guide column (38 %, min 340 pt:
  category bar + List) side by side with a 1 pt `white 10 %` divider. Same child views, same identities.
- Compact height (iPad window short side < 500 pt, iPhone landscape never happens outside the player): the stage goes
  fullscreen (existing `verticalSizeClass == .compact` behaviour), the guide column hides.
- iPhone stays portrait-only outside the fullscreen player (owner rule).
- Category bar and List behave identically in both shapes; the tab bar hide/show runs only on compact width.

## 2. Fullscreen Live player

### 2.1 Decision: custom overlay that copies the system look (not `AVPlayerViewController`'s controls)

Facts from the engine: `AetherPlaybackEngine.mapRoute` (`AetherPlaybackEngine.swift:888-895`) gives three picture routes:
`.avPlayer` (remote-bypass/loopback; an `AVPlayer` exists), `.surface` (libavcodec software decode into an
`AVSampleBufferDisplayLayer` drawn by `AetherPlayerSurface`, no `AVPlayer` picture) and `.audioOnly`. `AVPlayerViewController`'s
system controls can only drive `.avPlayer`; on `.surface` the picture is a SwiftUI view mounted over an empty player
(`AppleMediaSourceViews.swift:2229-2250`). The owner's lineup routes many channels through `.surface` (`AppleTVChannelPreview.swift:120`).
Mixing system controls on some channels and custom on others would be two players in one lineup, so: **one custom overlay,
`AppleTransportOverlay`, restyled to the iOS 16+ system player.** `AVPlayerViewController` stays as the video host
(`showsPlaybackControls = false`), which keeps AirPlay routing and PiP on the `.avPlayer` route.

### 2.2 Chrome (shown)

```
┌──────────────────────────────────────────────────────────────┐
│ ✕                                       ⎚   ⊡   …           │ top row, 44 pt targets, 16 pt from safe edges
│                                                              │
│                                                        ˄     │ chevron.up (next channel)
│                  ⟲15     ▮▮     ⟳15                           │ centre transport (⟲/⟳ only with a DVR window)
│                                                        ˅     │ chevron.down (previous channel)
│                                                              │
│ [logo] ESPN · NFL Live                          ● LIVE   ≣   │ bottom row
│ ▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬ │ 3 pt scrubber (DVR only)
│ −0:42                                              Live      │ caption monospaced (DVR only)
└──────────────────────────────────────────────────────────────┘
```

| Element | SF Symbol / text | Size | Placement | Notes |
|---|---|---|---|---|
| Close | `xmark` | 17 pt semibold, 44 × 44 | top-left, 16 pt from safe leading/top | No circle, no stroke, no material. Swipe-down on the video also closes (existing). |
| AirPlay | `AVRoutePickerView` (system) | 44 × 44 | top-right group, first | `activeTintColor = .white`, `tintColor = .white`. |
| Captions | `captions.bubble` / `.fill` when on | 20 pt semibold, 44 × 44 | top-right group, second | Existing menu; one captions control (owner rule). |
| More | `ellipsis` | 20 pt semibold, 44 × 44 | top-right group, third | `Menu`: Audio (submenu), Sleep Timer (existing), Last Channel (`arrow.uturn.backward`, identifier `live.player.lastChannel`), Start Over (if catch-up), SharePlay (existing). |
| Play/Pause | `pause.fill` / `play.fill` | 44 pt symbol, 72 × 72 target | centre | Buffering → `ProgressView` large white in the same slot. |
| Skip | `gobackward.15` / `goforward.15` | 32 pt, 56 × 56 | 48 pt either side of play | Only when `seekableTimeRanges` spans > 30 s; `goforward.15` disabled at the live edge (`.opacity(0.4)`). |
| Channel up/down | `chevron.up`, `chevron.down` | 22 pt semibold, 44 × 44 each, 8 pt apart | right edge, vertically centred, 16 pt from safe trailing | Zap next/previous (existing `AppleLiveZappingPolicy`); swipe up/down also zaps (existing). Hide with the chrome. |
| Now playing | logo 32 × 20 + "ESPN · NFL Live" | `.subheadline`, white, 1 line | bottom-left, above the scrubber | Reads from `guide.nowAndNext`. |
| LIVE pill | `circle.fill` 6 pt + "LIVE" | `.caption.weight(.bold)`, red dot + white text at the live edge; grey dot + secondary text when behind | bottom-right before the list glyph | Tap when behind → jump to live (existing `onWatchLive`). |
| Channel list | `list.bullet` | 20 pt semibold, 44 × 44 | bottom-right, last | Opens the quick channel list (§2.4). |
| Scrubber | custom bar, no `Slider` thumb | 3 pt track `white 30 %`, fill white, 44 pt hit band | full width between 16 pt safe insets | While dragging: track grows to 6 pt and a 12 pt white dot appears at the finger; time labels `caption.monospacedDigit()`: left "−0:42" behind-live, right "Live". Absent without a DVR window. Chapter marks: none on live. |

Removed: the `Text("Channels")` and `Button("Last Channel")` buttons (`AppleTransportOverlay.swift:417-436`), the stroked
circle on `xmark` (`:404-408`), the `arrow.up.left.and.arrow.down.right` close variant (the fullscreen player closes with
`xmark`; "enlarge" exists only inline), the `Slider` in the live case, the red/grey "LIVE" text without dot. VOD keeps the
VOD transport; only `request.isLive` takes the rows above.

Background behind the chrome: `black 35 %` flat over the whole frame while chrome is shown (the system player does the same);
not a gradient (owner rule: no gradients over video). Fades with the chrome.

### 2.3 Timing and gestures

- Chrome appears on presentation and on any tap; auto-hides after **4 s** of no touch while playing; never hides while paused,
  while a menu/sheet is open, or while VoiceOver runs. Fade 0.25 s ease-in-out; Reduce Motion → 0.
- Tap on the video with chrome hidden → show chrome. Tap again (not on a control) → hide immediately. This replaces the
  current "tap opens the channel picker" (`:1905-1911`), which surprised testers.
- Swipe up/down (≥ 60 pt) → zap, with a 0.8 s zap debounce (existing); a zap does not show chrome, it shows the Now Playing
  row alone for 2 s (bottom-left, identical typography) then fades.
- Swipe down from the top 20 % of the screen → close (existing dismissal).
- Double-tap: none (keep single-tap semantics clean).

### 2.4 Quick channel list

- Portrait fullscreen (iPhone): the existing leading panel (`AppleLiveChannelPickerOverlay`) with rows restyled to §1.5
  (logo, name, now-title, WATCHING pill), width 300, slides in from the leading edge over a `black 60 %` dim, `Done` is an
  `xmark` 44 pt top-trailing of the panel, tapping outside closes. Scroll position opens on the current channel.
- Landscape (iPhone and iPad): the bottom strip (`AppleLiveChannelStripOverlay`), 96 pt tall, logo tiles 120 × 68 with a
  2 pt `brandAccent` underline under the current one, name + now-title under the tile. `AppleLiveChannelPickerPresentation.choose`
  takes `isLandscape:` instead of `isPad:`.
- Either closes on selection; the chrome is hidden after a selection.

### 2.5 Mute, sleep timer, captions

- Keep. Mute button only inline (§1.2) — fullscreen uses the hardware volume; a muted stream shows `speaker.slash.fill` 17 pt
  secondary at the bottom-left before the logo (indicator, 44 × 44 tap unmutes).
- Sleep timer lives in the `…` menu with "End of programme" using the EPG end time; existing `AppleSleepTimerPresentation`.
- Captions: one control, as today.

### 2.6 Picture in Picture (auto-PiP on swipe home)

Requirements: `UIBackgroundModes = audio` (present, `Apps/Shared/Info.plist:15-18`), `.playback` audio session (existing
`AppleAudioSessionCoordinator`), and an `AVPictureInPictureController` whose content is **visible and the primary content**.

- `.avPlayer` route: `AVPlayerViewController.canStartPictureInPicturePlaybackAutomaticallyFromInline = true` is set
  (`ApplePlayerHost.swift:100`) but the controller has `showsPlaybackControls = false` and, inline, sits in a 242 pt box
  under a list — AVKit treats that as secondary content and does not auto-start. Fix: in the fullscreen presentation the
  player is the whole screen, so auto-PiP works there once `allowsPictureInPicturePlayback` is true for the route
  (`AppleTVPictureInPicturePolicy.allowsPictureInPicture(route:)` must return true for `.avPlayer`; verify). For the inline
  Live tab, create an explicit `AVPictureInPictureController(contentSource: .init(playerLayer:))` on the inline player's
  layer with `canStartPictureInPictureAutomaticallyFromInline = true` — the explicit controller honours it for an inline
  layer that is on screen and playing (this is how YouTube TV does it).
- `.surface` route: `AVPictureInPictureController(contentSource: .init(sampleBufferDisplayLayer: layer, playbackDelegate:))`
  with the engine as `AVPictureInPictureSampleBufferPlaybackDelegate` (play/pause/isPlaybackPaused/timeRange from the
  coordinator; `setPlaying` → `engine.play()/pause()`). Dependency: `AetherPlayerSurface` must expose its
  `AVSampleBufferDisplayLayer` (an `AetherEngine` package change; if the package cannot expose it this release, auto-PiP ships
  for `.avPlayer` channels only and the `…` menu hides "Picture in Picture" on `.surface`).
- `.audioOnly`: no PiP; background audio continues.
- Return from PiP ("restore"): `restoreUserInterfaceForPictureInPictureStop` re-presents the fullscreen player if it was
  fullscreen, else selects the Live tab with the inline player (existing `ApplePictureInPictureWatcher` hooks).
- Hero trailers: never auto-PiP (`canStartPictureInPictureAutomaticallyFromInline = false` on their layer).

## 3. Error states

Format everywhere: `[symbol 28 pt secondary]` + title ≤ 5 words naming the source + one bordered button. No second line,
no paragraphs, no endpoint strings. The technical text stays in the trace (`AppleLiveFailurePresentation` already does this).

`AppleLiveFailureCause` (new, pure, tested) maps real causes:

| Cause (input) | Detection | Symbol | Title | Button |
|---|---|---|---|---|
| Unreachable / timeout / blocked | `ApplePlaybackFailure.kind ∈ {.network, .timedOut}`; `AppleIPTVError.unreachable`; HTTP 401/403/429/5xx **without** an Xtream `user_info` body (an IP block answers with a bare status or an HTML page) | `wifi.exclamationmark` | "Can't reach *Home IPTV*" | **Try Again** |
| Auth | `.authentication`; `AppleIPTVError.authenticationFailed` with status `expired`/`disabled`/`banned`/default | `person.crop.circle.badge.exclamationmark` | "*Home IPTV* login failed" (expired → "*Home IPTV* account expired") | **Open Settings** |
| Max connections | **only** Xtream JSON `user_info.status == "maxconnections"` or `active_cons >= max_connections` (`AppleIPTV.swift:1240`) | `person.2.slash` | "*Home IPTV* stream limit" | **Try Again** |
| Channel dead | `.player`, `.sourceEnded`, `.unavailable` | `tv.slash` | "*ESPN* isn't broadcasting" | **Next Channel** (zaps) |
| Unsupported | `.unsupportedMedia` | `exclamationmark.triangle` | "*ESPN* can't play here" | **Next Channel** |
| No sources | lineup empty | `tv` | "No Live TV source" | **Add Source** |

Rule that fixes owner #20: a status code or string match never yields "stream limit"; the string list in
`AppleMultiviewPolicy.swift:124` ("too many", "http 401", "http 403", "http 429") is not reused for user-facing copy.
Source name = the saved Live TV source's display name (`liveSourceNames[channel.sourceID]`), never the host.

Placement:
- Whole-tab failure (no channels): centred in the content area, title `.title3.weight(.semibold)`, one button
  `.buttonStyle(.bordered)` `.controlSize(.large)`. Identifier `live.failure`, button `live.failure.retry`.
- Channel failure: inside the 16:9 player frame, centred, title `.subheadline.weight(.semibold)`, button `.bordered`
  `.controlSize(.small)`; the Now Playing bar keeps the channel name; the list stays usable. The frame does not change
  height. In fullscreen the same card is centred over black and the chevrons stay available.
- Playlist failure while others loaded: List section header row "Couldn't load *Home IPTV*" with a trailing `Try Again`
  text button (`.footnote`), identifier `live.sourceError` (kept).

## 4. Portrait heroes (Discover + Library)

### 4.1 Geometry (iPhone)

- Art height = `round(width × 1.25)` = 538 pt on 430 pt (replaces `artFraction = 0.73` of screen in
  `AppleHomePhoneHeroLayout.artHeight`; keep `minimumArtHeight` 440 and the row-peek clamp so the first row still peeks).
- Art starts at the top edge under the status bar + large title as today (`topOverlap` unchanged).
- Bottom 40 % of the art: the existing approved billboard fade (`AppleHeroScrim`, black 0 → 85 %), unchanged in kind.
- Copy block (bottom-anchored, as today): title logo max 60 % width × 96 pt (`AppleTrimmedTitleLogo`), meta line, Play
  pill + `plus` round button, page dots 26 pt below. No change to buttons.
- iPad: unchanged (`AppleMacHeroLayout` billboard).

### 4.2 Art selection — `AppleHeroPortraitArt` (new, pure policy; the fetch lives in `AppleHeroArtworkUpgrade`)

Order, first hit wins; each candidate is tried through the existing `AppleCatalogArtworkPolicy` failure-advance:

1. **Portrait key art**: TMDB poster with `iso_639_1 == null` (`/movie/{id}/images?include_image_language=null,en`, pick the
   first `null`-language poster by `vote_average`, size `w780`) + TMDB logo (`logos`, `en` then `null`, `w500`). Rendered
   `scaledToFill` into 430 × 538 — a 2:3 poster (430 × 645) loses 54 pt top and bottom, which is safe for key art
   (margins are designed in). Posters WITH burned-in titles (no `null` poster) are allowed only when no logo is needed: if a
   logo exists, a titled poster is skipped (double title).
2. **Focal-point crop of the textless backdrop**: `AppleHeroFocalPoint` (new actor): `VNDetectFaceRectanglesRequest` → union
   of faces (largest face weighted ×2); none → `VNGenerateAttentionBasedSaliencyImageRequest.salientObjects` union; none →
   centre. Output a normalised `CGPoint` cached in `AppleArtworkDiskCache` under `"focal-v1"` keyed by the image URL hash
   (`AppleCatalogArtworkPolicy.traceID`-style hash). Crop: the tallest 430:538 window that fits the backdrop (for a 1280 × 720
   backdrop that is 575 × 720 source px), positioned so the focal point sits at x = focal.x clamped into the window and
   y = 0.40 of the window height (faces sit in the upper 40 %), window clamped to the image. Implemented as an `Image`
   with `.scaledToFill` + `.offset` computed from the focal point, no CoreImage.
3. **Blurred backdrop + poster**: backdrop `scaledToFill` + `.blur(radius: 40)` + `black 35 %` flat overlay (allowed: it is
   not over the subject, it is the subject's background), poster centred at 60 % width with 12 pt radius, offset up 24 pt
   so the copy block does not overlap it.
4. Nothing → the existing `AppleHeroTitlePolicy` name-in-capitals over black.

Media-server items (Jellyfin/Plex/Emby) without TMDB art: Jellyfin `Primary` (poster) = step 1 art, `Logo` image type =
logo, `Backdrop` = step 2 input; Plex `thumb` = poster, `art` = backdrop, `clearLogo` where present. If the item carries a
TMDB id (`ProviderIds.Tmdb` / Plex guid `tmdb://`), the TMDB lookup in step 1 runs first; otherwise the server images follow
the same order. Xtream VOD (Library hero): `stream_icon` = poster, `backdrop_path[0]` = backdrop, `tmdb` id when present.

### 4.3 Trailer in the portrait hero — decision: 16:9 slot over the still, not full-bleed, not black bars

Netflix: no autoplay on the phone home billboard. Apple TV app: autoplays muted full-bleed because Apple cuts portrait video.
We only have 16:9 YouTube trailers, so full-bleed would crop 55 % of the frame and letterboxing on black would look like a
broken image. Decision: the trailer plays in a full-width 16:9 slot (430 × 242) centred on the art's vertical middle, over
the still, which stays visible above and below under a flat `black 30 %` dim (the still is the slot's frame). Crossfade
0.3 s on first frame (`AppleTrailerArtFirstPolicy`, existing); the still returns on end. Honour Reduce Motion / Low Power
(no autoplay). Logo/buttons stay where they are (bottom), outside the slot.

```
┌──────────────────────────┐
│ Discover           ⌕  ⟳  │
│ ░░░ still, dimmed 30 % ░░│
│ ░░░░░░░░░░░░░░░░░░░░░░░░░│
├──────────────────────────┤
│                          │
│      TRAILER 16:9        │  ← video slot, crossfaded in
│                     🔇   │  speaker.slash.fill 20 pt, 44 target, bottom-right of the slot
├──────────────────────────┤
│ ░░░░░░░░░░░░░░░░░░░░░░░░░│
│ ░░░░░ fade to black ░░░░░│
│        [ LOGO ]          │
│     Movie · Horror       │
│   (▶ Play)   (+)         │
│          ● ○ ○ ○         │
└──────────────────────────┘
```

Paused state (one control): `play.fill` 44 pt white with `shadow(.black 40 %, radius 3)` centred on the slot. Nothing
else: no ring, no material disc, no second circle. Tap → resumes. The mute glyph stays. On iPad/Mac the same single glyph.

## 5. Mockups

Live default and Live scrolled are in §1.1 (the only difference when scrolled: the tab bar is gone, rows continue to the
bottom edge, the header is identical). Fullscreen chrome shown is in §2.2. Hero static/trailer/paused in §4.3.

Fullscreen, chrome hidden (zap just happened):
```
┌──────────────────────────────────────────────────────────────┐
│                                                              │
│                                                              │
│                        VIDEO                                 │
│                                                              │
│ [logo] FOX Sports 1 · UFC Countdown                          │ ← 2 s, then fades
└──────────────────────────────────────────────────────────────┘
```

Live, channel error inside the frame:
```
├──────────────────────────────────────────┤
│                 ⚠ tv.slash               │
│          ESPN isn't broadcasting         │
│             ( Next Channel )             │
├──────────────────────────────────────────┤
│ [logo]  ESPN                             │ Now Playing bar keeps the name, no time
│ All   Favorites   Sports   …        ⌕ ▦  │
│ rows…                                    │
```

Live, whole-tab error:
```
│                                          │
│            wifi.exclamationmark          │
│           Can't reach Home IPTV          │
│               ( Try Again )              │
│                                          │
```

## 6. Implementation plan

### 6.1 Files

New (all `Sources/OpenStreamApple/`, iOS-only parts under `#if os(iOS)`):
- `AppleLiveStageLayout.swift` — `Layout` placing player / bar / tabs / list stacked or side by side; `AppleLiveStage` view.
- `AppleLiveNowPlayingBar.swift` + `AppleLiveNowPlayingModel` (pure: name, title, remaining text, fraction).
- `AppleLiveCategoryBar.swift` + `AppleLiveCategoryOrder` (pure: All/Favorites/Events/groups rule).
- `AppleLiveOnNowList.swift` — `List`, row view, swipe actions, schedule sheet.
- `AppleLiveTabBarVisibility.swift` — pure policy + `AppleLiveTabBarHiding` modifier (iOS 18 path + iOS 26 path).
- `AppleLiveFailureCause.swift` — pure cause → (symbol, title, action) + `AppleLiveFailureCard` view.
- `AppleLiveScrubberBar.swift` — thin DVR bar (replaces `Slider` in the live case).
- `AppleHeroPortraitArt.swift` — pure art-order policy; `AppleHeroFocalPoint.swift` — Vision actor + cache.
- `AppleLivePictureInPicture.swift` — explicit `AVPictureInPictureController` for inline `.avPlayer` and `.surface`.

Changed:
- `AppleMediaSourceViews.swift`: `AppleLiveTVView` iOS body (`:143-327`) → `AppleLiveStage`; container VC chrome (`:2040-2113`)
  → §1.2 set; `AppleLiveFullScreenControls` tap semantics (`:1905-1911`); nav bar hidden on iPhone (`:346`).
- `AppleTransportOverlay.swift`: live top row (`:395-440`), LIVE pill (`:565-581`), live scrubber (`:880-900`), chevrons,
  4 s auto-hide for live, flat dim.
- `AppleLiveChannelPickerModel.swift`: `choose(isLandscape:)`.
- `AppleLiveChannelPicker.swift`: row restyle, `xmark` done button.
- `AppleIPTVGuideGridView.swift`: colours only (§1.6).
- `ApplePlayerHost.swift`: PiP controllers per route; `configureLivePlaybackControls` unchanged.
- `AppleHomePhoneHeroLayout.swift`: `artHeight` = 1.25 × width rule; tests updated.
- `AppleHomePhoneHero.swift`, `AppleHomeBillboard.swift`: art order, trailer slot, single paused glyph.
- `AppleHeroArtworkUpgrade.swift`: fetch `null`-language poster + logo (cache type `"portrait-v1"`).
- `AppleHomeHeroCarousel.swift`: `AppleHeroPageArt` gains `poster`, `focal`.
- `OpenStreamRootView.swift`: nothing structural; the Live tab's `.toolbar(…, for: .tabBar)` binding comes from the Live view
  via a preference (`AppleLiveTabBarHiddenKey`).

Deleted:
- `LivePinnedPlayerLayout` and `livePinnedPlayerLayout(…)` (`AppleMediaSourceViews.swift:1311-1356`).
- The `videoColumn` / `guideColumn` / `isLandscape` branch (`:150-320`), the horizontal category `ScrollView` (`:219-251`).
- `lastChannelButton`, `watchLiveButton` and their constraints in the container VC (`:2059-2113`, `:2160-2199`).
- "Channels" / "Last Channel" buttons and the stroked `xmark` in `AppleTransportOverlay.swift:395-436`.
- The inline "Connecting to …" text row (`:151-160`) — the buffering spinner in the frame replaces it (no explainer text).
- The `probeFailureMessage` detail line "<host> is not sending this channel" on iOS (trace only).

### 6.2 iOS 18 API constraints

- No `tabBarMinimizeBehavior`, no `glassEffect`, no `.scrollEdgeEffectStyle` — all behind `if #available(iOS 26, *)` with the
  iOS 18 path as the default. `onScrollGeometryChange`, `onScrollPhaseChange`, `contentMargins`, `Layout`, `.scrollTargetLayout`
  are iOS 17/18 and fine. `AVPictureInPictureController(contentSource:)` with a sample-buffer layer is iOS 15+.
- Floors stay iOS/tvOS 18 (AGENTS.md §1). No `UIScreen.main`. Size by `horizontalSizeClass` + measured viewport, not idiom
  (Duo audit).
- tvOS: none of the new iOS files compile there; `AppleLiveTVView`'s tvOS branch (`tvGuide`) is untouched; a tvOS build
  proves it (AGENTS.md §5).

### 6.3 Order of work (small commits, each passes the gate)

1. Pure policies + Swift Testing suites: `AppleLiveFailureCause`, `AppleLiveTabBarVisibility`, `AppleLiveCategoryOrder`,
   `AppleLiveNowPlayingModel`, `AppleHeroPortraitArt`, `AppleHomePhoneHeroLayout` 1.25× rule.
2. `AppleLiveStageLayout` + stage: player container moved out of the scroller, nav bar hidden, search icon; delete
   `LivePinnedPlayerLayout` and the branch. (Rows unchanged yet.) UI test: player frame identical before/after a swipe.
3. Now Playing bar + fixed category bar (+ Events tab) + guide sheet button.
4. On Now `List` rows, WATCHING pill, swipe actions, schedule sheet; cap notice → footer; source failure → section row.
5. Tab bar hide/show (iOS 18 path; iOS 26 path).
6. Inline player chrome: three top-right glyphs + centre play; remove the rest.
7. Fullscreen chrome: `xmark`, `…` menu, chevrons, thin scrubber, LIVE pill, 4 s hide, tap semantics, flat dim.
8. Quick channel list restyle + landscape strip.
9. Error states wired through `AppleLiveFailureCause` (tab, frame, fullscreen, section row).
10. PiP: fullscreen auto-PiP on `.avPlayer`; inline explicit controller; `.surface` path behind the engine-layer dependency.
11. Hero: portrait art order + TMDB null-poster/logo fetch + focal-point crop + blurred fallback (Discover and Library share it).
12. Hero trailer slot + single paused glyph + mute glyph placement.

### 6.4 Test plan

Gate: `scripts/mini.sh 'swift test --scratch-path ~/Developer/openstream-build/spm 2>&1 | tail -30'` before and after every
commit (report N/M). Unit suites for every pure type in 6.3 step 1, including: an HTTP 403 with an HTML body never maps to
"stream limit"; `maxconnections` JSON does; tab-bar policy ignores short content; category order with/without favourites/PPV;
art order with and without logo/null poster/server images; focal crop stays inside the image at both extremes.

UI tests (`Apps/OpenStreamiOSUITests`, XCTest, on the iOS 18.6 sim "iPhone 15 Pro Max iOS18"
`7530ECB2-CE38-4BC6-B7E6-D4B3BEDDF48D` and the iOS 27 iPhone sim `6A037503-AF3A-4A22-B900-CF6573B15FB1`, one at a time
through `buildlock.sh`, after the concurrency gate):
- `testLiveLayoutIsStable`: open Live with the fixture playlist, record the player's frame, swipe the list up twice and down
  once; the frame and the category bar's frame are unchanged (± 0 pt); no `live.connecting` text exists.
- `testLiveNowPlayingNamesTheChannel`: `live.nowPlaying` label contains the tapped channel's name and the WATCHING pill exists
  on exactly one row.
- `testLiveTabBarHidesOnScrollDown` (iOS 18 only): after a swipe up the tab bar's "Live" button is not hittable; after a
  swipe down it is.
- `testLiveFullscreenChromeIsSystemLike`: no button labelled "Channels" or "Last Channel"; `player.close` exists; chevrons
  "Next Channel"/"Previous Channel" exist; controls disappear after 5 s and return on tap.
- `testLiveErrorNamesTheSource` (fixture that answers 403 HTML): title contains the source name and not "stream limit".
- `testLiveStreamLimitIsOnlyFromPanelJSON` (fixture with `maxconnections`): title contains "stream limit".
- `testHeroPortraitArtFillsTheFrame`: hero art height ≥ 1.2 × width, the paused trailer control is one button with
  label "Play trailer".
- Extend `testLiveTappedStatesArePhotographed` and `AppleUXTourUITests.testB6Live` to save: `live-default`, `live-scrolled`,
  `live-fullscreen-controls`, `live-fullscreen-hidden`, `live-error-frame`, `live-error-tab`, `hero-static`, `hero-trailer`,
  `hero-paused` into `verification-artifacts/ux-ios18-2026-10-09/after/` for both sims, next to the `before/` set.
- Device check on DevPlus (iPhone 16e): swipe home while a `.avPlayer` channel plays fullscreen → PiP window appears; tap
  restore → fullscreen player returns. Repeat for a `.surface` channel once the layer is exposed.
- tvOS build of `OpenStream tvOS` must succeed (no tvOS behaviour change).

## 7. Open questions for the owner (max 3)

1. **Tab bar over the guide:** hide on scroll down / show on scroll up (recommended: keeps the system bar untouched, gives
   the list the full height, and is what iOS 26 will do natively) — or leave it always visible?
2. **Trailer in the portrait hero on iPhone:** 16:9 video slot over the dimmed still, mid-art (recommended: no black bars,
   no cropped faces, logo and Play stay put) — or no hero trailers on the phone like Netflix, keeping them on the title page?
3. **Last Channel:** demote to the fullscreen `…` menu plus the swipe (recommended: the visible text button is what reads
   as cheap, and the gesture already covers the common case) — or keep a visible `arrow.uturn.backward` glyph in the
   bottom row?
