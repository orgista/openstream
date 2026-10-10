# Review: Live + portrait hero redesign spec (2026-10-09)

## 1. Verdict

**7/10 as written. 9/10 with the cuts below.**

The bones are right: edge-to-edge 16:9 at the top, no nav bar, underlined text tabs, an "on now" list with a WATCHING pill, a system-styled fullscreen overlay, portrait key art. That is the Paramount+ skeleton and it will read as a different app from build 17.

What holds it at 7 is that the spec then adds four layers Paramount+ does not have, and each one is where the "AI-made" smell comes back: a hide-on-scroll tab bar, a Now Playing bar that duplicates the WATCHING row, a 16:9 trailer slot pasted over a dimmed poster, and brand-pink lines on four different element types. The fullscreen chrome is close to the system player but not actually the system layout, and the live label appears twice. Fix those and this is on par with Paramount+ and the Apple TV app. YouTube TV is a different model (no docked player) and is not the target.

## 2. Ten problems, each with a fix

**1. Hide-on-scroll tab bar is a gimmick with real iOS 18 risk.** Your own research says "keep the tab bar visible". No first-party iOS 18 app hides the tab bar on scroll, Paramount+ does not, and the gain is one list row. Toggling `.toolbar(.hidden, for: .tabBar)` inside `TabView` changes the safe area; the `ignoresSafeArea` plus `contentMargins(.bottom, 83)` trick leaves an 83 pt dead band under the last row whenever the bar is hidden, and iOS 18 `TabView` is known to re-lay out its content on that toggle.
*Fix:* tab bar always visible. Delete `AppleLiveTabBarVisibility`, `AppleLiveTabBarHiding`, the preference key and the UI test. Keep only `tabBarMinimizeBehavior(.onScrollDown)` behind `#available(iOS 26, *)` for later.

**2. The trailer slot will look like a broken embed.** A poster dimmed to 70 %, a hard-edged 16:9 strip across its middle, the poster's subject half-visible above and below, and a Play pill under it that means "play the film" while a trailer is already playing. No shipping app composites video this way.
*Fix:* iPhone Discover and Library heroes are static. Trailer autoplay stays on the title page, where the header is already a 16:9 slot. Paused state there is one `play.fill` 44 pt with the 40 % shadow, mute is one `speaker.slash.fill` 20 pt in a 44 pt target bottom-right. Cut commit 12.

**3. The Now Playing bar duplicates the WATCHING row and adds a fourth band.** On load the current channel's logo, name, programme and progress appear in the bar and again 44 pt lower in the list. The fixed header reaches 401 pt. Paramount+ names the channel with a persistent logo over the video and has no bar.
*Fix:* cut the bar. Draw the channel logo at 20 pt height, 12 pt inset top-left of the video, with the 40 % shadow, persistent (not part of the auto-hiding chrome); channel name in `.footnote.weight(.semibold)` white when there is no logo. Put the single 2 pt programme progress line directly under the video so it reads as the video's progress. Programme title lives in the WATCHING row. Header becomes 347 pt and the list shows eight full rows with the tab bar visible. Hide the logo while an error card is in the frame.

**4. Brand pink on four element types.** Underline, bar progress, every row's progress, WATCHING pill, swipe tint. On a black screen this reads as "the accent colour was applied to everything".
*Fix:* `#FF3366` only on the WATCHING pill and the leading swipe action. Tab underline 2 pt white. Progress line white 70 % on white 15 %. No progress line on list rows at all.

**5. Fullscreen chrome is "system-like" but not the system layout, and LIVE appears twice.** The iOS 16+ `AVPlayerViewController` puts `xmark` and `pip.enter` top-left, `ellipsis` top-right, the scrubber at the bottom with AirPlay and captions under it on the right, and renders LIVE as the scrubber's left time label. The spec puts AirPlay and captions top-right, a LIVE pill bottom-right, and a second "Live" word at the end of the scrubber.
*Fix:* copy the system arrangement exactly (wireframe in §5): top-left `xmark` then `pip.enter` when PiP is possible; top-right `ellipsis` only; bottom row is the scrubber with the LIVE pill as its left label (red `circle.fill` 6 pt + "LIVE" `.caption.bold` at the edge, grey when behind) and "−0:42" `.caption.monospacedDigit()` as the right label only when behind; under it, right-aligned, `airplayvideo` (`AVRoutePickerView`), `captions.bubble`, `list.bullet`, each 44 pt. Without a DVR window the row holds the LIVE pill alone. Screenshot a system player on the sim and match it to the point.

**6. Gesture conflict in fullscreen.** Swipe down zaps to the previous channel, swipe down from the top 20 % closes, and swipe up from the bottom is the system home gesture and the auto-PiP trigger. Users will close when they meant to zap and zap when they meant to close.
*Fix:* remove swipe-down-to-close; `xmark` closes. Zap gestures only start in the middle 60 % of the height and never while the scrubber is being dragged. Chevrons remain the visible affordance.

**7. Hero art has two holes.** A titled poster with no logo gets the `AppleHeroTitlePolicy` text title on top, so the title appears twice. Vision focal points computed after first display will re-crop the image in front of the user.
*Fix:* if the chosen poster carries a burned-in title, suppress the text title and keep only the meta row and buttons. Compute the focal point inside the fetch task before the image is published; show the placeholder until both are ready. For the first slice replace Vision with a constant top-bias (focal y = 0.35) and ship Vision in slice 2.

**8. PiP is two bets.** Inline auto-PiP from an explicit `AVPictureInPictureController` on a 242 pt layer under a list is plausible (YouTube does it) but unverified here, and the `.surface` path depends on an `AetherEngine` package change.
*Fix:* slice 1 ships only fullscreen auto-PiP on the `.avPlayer` route, device-verified on DevPlus. The `…` menu lists "Picture in Picture" only when a controller reports `isPictureInPicturePossible`. Inline and `.surface` go to slice 2.

**9. IPTV logos will make the list look cheap unless handled.** Lineups mix wide transparent logos, square tiles and white-background PNGs, and some channels have none. A 44 × 28 slot squashes square logos to 28 pt.
*Fix:* 48 × 32 slot, `scaledToFit`, no background, no clip. Missing logo: `tv` 17 pt in tertiary label colour, never a monogram badge. Never put a rounded rect behind logos.

**10. Smaller misfits.** A 300 pt side drawer in a 430 pt portrait screen reads as Android. `calendar` means date picking, not a time grid. "1:12 left" reads as 72 seconds. A custom `Layout` is more code than needed. Chevrons 8 pt apart look cramped.
*Fix:* portrait quick list is a `.sheet` with `.presentationDetents([.medium, .large])` using the On Now rows; the landscape strip stays. Defer the Guide sheet; when it ships use `tablecells`. Time left formats as "1 hr 12 min left" via `Duration.UnitsFormatStyle`, abbreviated. Use `AnyLayout(compact ? VStackLayout() : HStackLayout())`, which preserves identity with no custom `Layout`. Chevrons `chevron.up` / `chevron.down` 20 pt regular, 24 pt apart, white 80 %.

## 3. What will still look AI-made, and what to cut

- **Four stacked bands under the video** (bar, line, tabs, rows). Cut to two: line and tabs.
- **A 2 pt progress line under every row.** Cut all of them.
- **A glyph at the end of every row.** Slice 1 has no schedule sheet, so no glyph. When it ships, 15 pt in tertiary label colour so it recedes.
- **Two icon buttons after a fading tab row.** One icon only: `magnifyingglass` 17 pt semibold secondary. Guide comes later.
- **Pink everywhere.** One pink element on screen: the WATCHING pill. 11 pt bold, tracking 0.5, capsule 20 pt high, padding 8 × 3. That is the Paramount+ pill and it should be the only badge on the screen.
- **Tabs smaller than the row titles.** Tabs are 15 pt, rows 17 pt, which makes the tabs look like an afterthought. Tabs `.body.weight(.semibold)` 17 pt, selected white, others secondary.
- **The trailer slot composite.** Cut on iPhone.
- **The poster card floating on a blurred backdrop.** This is the Jellyfin-client look. Keep it as the last resort only, log how often it hits, and if it exceeds a tenth of hero pages prefer the backdrop crop over the card.
- **The side drawer.** Replace with a system sheet.
- **Fullscreen top row with five items.** Three: `xmark`, `pip.enter`, `ellipsis`.
- **LIVE twice.** Once, as the scrubber label.
- **Inline captions.** Nobody toggles subtitles in a 242 pt box. Inline trio becomes mute, `airplayvideo`, `arrow.up.left.and.arrow.down.right`; captions only in fullscreen. One captions control still holds.

What is already clean and should not be touched: the status bar on black above the video, the single 35 % flat dim, the bare `xmark` with shadow, the spinner replacing the play glyph, the error cards with one bordered button, the Events tab, the empty state with one line of text.

## 4. Open owner questions

1. **Tab bar over the guide:** always visible. The system bar stays untouched, no safe-area jump, no iOS 18 `TabView` re-layout, and iOS 26 will minimize it natively for free. The cost is one list row, which the Now Playing bar cut gives back.
2. **Trailer in the portrait hero:** no hero trailers on the phone, like Netflix. The only non-cheap autoplay in a portrait hero is Apple's, and they shoot portrait-safe video. With 16:9 YouTube trailers the title page is the right home. Keep hero autoplay on iPad, Mac and tvOS where the hero is landscape.
3. **Last Channel:** demote to the `…` menu plus the existing swipe, as the spec recommends. The visible text button is what read as cheap. Add it as the first item of the menu with `arrow.uturn.backward` so it stays one tap away.

## 5. Revised wireframes (only where the spec changes)

**Live default** (430 × 932, tab bar always visible):
```
┌──────────────────────────────────────────┐ 0
│ 9:41                        ●●●● ◔ ▮    │ status bar, black, 59 pt
├──────────────────────────────────────────┤ 59
│ [ESPN]                                   │ logo 20 pt high, 12 pt inset, shadow, persistent
│                                          │
│              VIDEO 16:9                  │ 430 × 242, resizeAspect, no radius
│                                          │ chrome on tap: pause.fill centre; mute, airplayvideo,
│                                          │ fullscreen top-right, 44 pt each, 4 pt gap
├──────────────────────────────────────────┤ 301
│▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬              │ 2 pt progress, white 70 % on white 15 %
│ All   Favorites   Sports   News   Mov…  ⌕│ 44 pt, 17 pt semibold, 2 pt white underline
├──────────────────────────────────────────┤ 347
│ [logo]  ESPN                   WATCHING  │ row 60 pt: name .body, title .subheadline secondary
│         NFL Live                         │ pill 20 pt capsule, 16 pt from trailing edge
│ [logo]  FOX Sports 1                     │ no progress line, no trailing glyph
│         UFC Countdown                    │ separators inset to the text column
│ [logo]  CBS                              │
│         60 Minutes                       │
│ [logo]  NBC                              │
│         Nightly News                     │
│ [logo]  ABC                              │
│         World News Tonight               │
│ [logo]  TNT                              │
│         Inside the NBA                   │
│ [logo]  TBS                              │
│         Friends                          │
│ [logo]  USA                              │
│         WWE Raw                          │
├──────────────────────────────────────────┤ 849
│  ✦ Discover   ▤ Library   ((•)) Live  ⚙ │ system tab bar, never hidden
└──────────────────────────────────────────┘ 932
```

**Live scrolled:** identical header through 347 pt, rows scrolled under the tab row, WATCHING row off screen, tab bar still present. Nothing else differs, which is the point.

**Fullscreen, chrome shown** (portrait; landscape uses the same elements with the chevrons on the right edge):
```
┌──────────────────────────────────────────┐
│ ✕   ⧉                               …   │ xmark, pip.enter (only if PiP possible); ellipsis
│                                          │ 44 pt targets, 16 pt from safe edges
│                                      ˄   │ chevron.up, 20 pt, white 80 %
│          ⟲15     ▮▮     ⟳15              │ 32 / 44 pt symbols; skips only with DVR > 30 s
│                                      ˅   │ chevron.down, 24 pt below the up chevron
│                                          │
│ [logo] ESPN · NFL Live                   │ .subheadline white, shadow
│ ●LIVE ▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬ −0:42  │ 3 pt scrubber; LIVE pill = left label;
│                                          │ right label only when behind; no DVR = pill alone
│                         ⎚   💬   ≣       │ airplayvideo, captions.bubble, list.bullet, 44 pt
└──────────────────────────────────────────┘
```
35 % flat black dim behind the chrome, 4 s auto-hide, tap toggles, no swipe-down close.

**Hero static:** geometry and art order as specified, with the titled-poster rule from §2.7. No wireframe change.

**Title page header, trailer and paused** (replaces the iPhone hero trailer):
```
┌──────────────────────────────────────────┐
│ ‹                                        │ existing back button
│                                          │
│              TRAILER 16:9                │ 430 × 242, crossfaded over the backdrop still
│                   ▶                      │ paused: one play.fill 44 pt, shadow, no ring
│                                      🔇  │ speaker.slash.fill 20 pt, 44 pt target
├──────────────────────────────────────────┤
│ [LOGO]   Movie · 2024 · 2 h 10 min       │ existing title block
```

## 6. Commit order and scope for the first shippable slice

**Slice 1, App Store in days.** Each commit passes the gate; order chosen so a revert at any point keeps the earlier wins.

1. **Fullscreen chrome restyle,** `AppleTransportOverlay.swift` only: bare `xmark`, `pip.enter`, `…` menu with Last Channel first, thin scrubber with LIVE as left label, bottom-right AirPlay / captions / list, chevrons, 4 s hide, tap toggles, flat dim, swipe-down close removed. One file, no layout risk, kills owner #12, #13, #14.
2. **Inline chrome** in the container VC: centre play/pause/spinner, top-right mute / AirPlay / fullscreen, persistent logo top-left, progress line under the video. Delete Last Channel, Back to Live and the "Connecting to…" row. Kills #13, #15, most of #7.
3. **Pure policies and tests:** `AppleLiveFailureCause`, `AppleLiveCategoryOrder`, the 1.25× hero rule. Drop `AppleLiveTabBarVisibility` and `AppleLiveNowPlayingModel`.
4. **Stage:** `AnyLayout`, nav bar hidden, player out of the scroller, `LivePinnedPlayerLayout` and the two view trees deleted, `testLiveLayoutIsStable`. This is the riskiest commit in the slice, which is why it comes after the chrome wins.
5. **Fixed category bar** with search glyph and Events tab. No Guide sheet.
6. **On Now `List`:** rows, WATCHING pill, swipe actions, cap notice as footer, playlist failure as section row. No trailing glyph, no schedule sheet.
7. **Error states** through `AppleLiveFailureCause` in tab, frame and fullscreen. Kills #20.
8. **Hero:** 1.25× geometry, TMDB null-language poster plus logo, top-biased backdrop crop as a constant, blurred fallback, titled-poster suppresses the text title. Kills #6, #19.
9. **Paused trailer glyph** becomes one `play.fill` on the surfaces that keep trailers; iPhone heroes go static. Kills #5.
10. **Fullscreen auto-PiP on `.avPlayer`** only if the DevPlus check passes first try; otherwise it moves to slice 2.

**Slice 2:** schedule sheet and row glyph; Guide sheet with `tablecells`; quick list as a sheet plus the landscape strip restyle; Vision focal crop with pre-publish computation; inline explicit PiP controller; `.surface` PiP behind the engine package change.

**Never on iOS 18:** custom tab bar hide/show.

**Test plan edits:** delete `testLiveTabBarHidesOnScrollDown`; replace `live.nowPlaying` in `testLiveNowPlayingNamesTheChannel` with the logo overlay's label `live.channelBadge` ("ESPN, now playing"); `testHeroPortraitArtFillsTheFrame` asserts no trailer player exists on iPhone and that the title page's paused control is one button labelled "Play trailer"; `testLiveFullscreenChromeIsSystemLike` additionally asserts exactly one element labelled "Live".

Chat naming per your global rule was not possible from this session: no shell tool is available here, so run the `chat-cleanup.py --name "OpenStream"` command yourself if this chat should keep a name.
