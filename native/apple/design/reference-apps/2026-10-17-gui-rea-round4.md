# GUI REA round 4: Apple TV app, Netflix, Paramount+ vs OpenStream, screen by screen (2026-10-17)

Spec: `specs/regression-and-rea-2026-10-17.md`, Job R2. Static reading only: no builds, no simulators or devices, no
build lock, nothing installed or run, nothing uploaded. No reference code, strings or assets went into OpenStream; the
rules below are behaviours and numbers. OpenStream paths are under `Sources/OpenStreamApple/` at main `72966f9` unless a
full path is given. Short names: **DV** = AppleDiscoverView.swift, **MSV** = AppleMediaSourceViews.swift,
**TVG** = AppleTVLiveGuideView.swift, **TVM** = AppleTVGuideMetrics.swift, **GG** = AppleIPTVGuideGridView.swift.

This round adds only what the earlier reports lack: 2026-10-11 appletv-hero-gui (config key names), netflix-gui (rows,
cards, Top 10, details order), paramount-live (TV layers, surf keys) and 2026-10-17 rea-hero-trailers-disc (showcase
defaults, paging state machine, trailer history). New this round: the Apple product-page and search/library/multiview
numbers, Netflix billboard/details/search/My List geometry and autoplay policy, Paramount's guide card model, category
behaviour, surf coalescing, channel memory and guide auto-hide.

**Branch status.** `hero-trailers` 311a53b (in batch-1017b, live-narration and hero-settle, **not in main**) already
fixes these: hero wrap, stalled-trailer give-up (8 s), advance 1 s after a trailer on every platform, 6 s still pages,
trailer start timed from page appear, iPhone full-bleed title header (undoes 13a2677), pressed trailers under Low
Power, remembered mute and an 8 s art timeout. Rows marked **[311a53b]** below need a merge and a device check, not new
code.

## Evidence base

| Reference | Artifact (on Dev-Mini) | How it was read |
|---|---|---|
| Apple TV app | macOS 27 `VideosUI` in the live shared cache (UUID CBD252C1-A639-3C95-8A06-92EAE6228089); extracted copy in `targets/dsc-macos27.0.1-arm64e` | `dyld_info -disassemble`, stub→selector map from round 3, Swift field metadata/vtables, ivar-offset uses. Addresses are unslid shared-cache addresses |
| Netflix | Android phone 9.87.1 (`apk/netflix-mobile/`) | apktool resources, dexdump index, about 45 single-class jadx decompiles (`/tmp/rea4-nf-*`) |
| Paramount+ | Android TV 17.1.1 (`apk/paramount/com.cbs.ott.apk`). `com.cbs.ott.xapk` is byte-identical (`cmp`), so **no phone build exists** | apktool -s resources, dexdump, about 40 single-class jadx decompiles (`/tmp/rea4-pp-*`) |

Limits:
- **Apple.** This is the macOS build, so tvOS-only branches (focus scale, tvOS banner height) are compiled out. Runtime
  `isTV`/`isPhone`/`isVision` branches remain. Most Apple layout is server-driven (`layout`/`injectedLayout` keys), so the
  binary holds defaults only. No layout JSON ships in VideosUI or TV.app Resources.
- **Netflix.** Several flags (mute, loop) come from decoding Compose default bitmasks. The TV app's UI is native
  (`libnetflix.so`) and was not read.
- **Paramount+.** One codebase serves P+ US, P+ International and Pluto TV (flavour enum `v60`, `a() = this == PLUTO`).
  Rows say which flavour a value belongs to.

---

## 1. Home hero and its cycle

### Reference rules
- **Apple TV app (round 3 values, the TV branch).**
  - Still pages dwell 5 s; video pages advance 1 s after the clip ends; no timer runs while video plays.
  - Trailer start: phone 0.5 s / TV 1.0 s / iPad and Mac 2.0 s after the page appears, minus load time.
  - Automatic slide 1.0 s on TV (0.75 s elsewhere); metadata fades separately at speed 1.5; parallax ratio 0.5.
  - Mute button and page indicators hide after 5 s.
  - **New, Observed:** `MediaShowcasingMetadataLayout` gives page control height 44 and a margin of 8 from the media
    tags to the title.
  - **Focus is not an input to `shouldEnableAutoAdvance`** (round 3 §1.3). Its inputs are accessibility, config,
    full-screen playback, off-screen, post-play and background.
- **Netflix phone (new, Observed).**
  - **No rotating hero.** The billboard is a single item; `LoMoType.BILLBOARD` fetches 3 and no rotation timer exists.
  - Card height (`o.jNG.c`, jNG.java:7-27):
    - portrait phone: min(0.65 × screen height, min(width, 400 dp) × 1.45 − 40 dp), about 530 pt on a 393×852 phone;
    - otherwise: 16:9.
  - Card style: radius 12 dp, max width 400 dp, 20 dp side padding (layout 0x7f0e003f).
  - Logo: width 0.6 × screen, height from the asset's aspect (`o.kVB.d`, kVB.java:133-160); text title if no logo.
  - Buttons: Play and My List share the row equally (weight 1), on a guideline 64 dp from the bottom.
  - **The video card has no scrim.** The only gradient found is in the games billboard (`o.kVK`).
  - Motion preview (`o.kWs.b` → `PlayerSessionConfig("motionBillboard")`): **muted, loops, crop-to-fill**.
  - Playback is driven by an autoplay manager (`o.jSJ`): it plays at ≥ 50 % visible, decides 100–350 ms after
    scrolling settles, always plays `PLAYABLE_VIDEO_MUTED`, and pauses below the threshold or on `onStop`.
  - Which item plays (`o.jSO.e`): visible fraction × 1000, + up to 200 for centring, − rank × 10, +10000 if the user
    just touched it. The current item is kept unless another beats it by 30.
  - The profile's "Autoplay previews" off (`disableVideoMerchAutoPlay`, `o.lAM`) stops all of it.
  - Entry animation: scale 1.15 → 1.0 in 600 ms (PathInterpolator 0.23, 1, 0.32, 1) plus alpha over 300 ms.
- **Deliberately absent in both:** synopsis on the phone hero (Netflix shows a one-line tags row only), explainer text,
  coloured buttons other than the brand Play (Netflix red; Apple white/system), page-change text effects.

### OpenStream now
- **Shared.** 12 s pages (`AppleHeroRotation.swift:13`), at most 5 pages (`:17`). **Stops on the last page**
  (`AppleHeroRotationCycle.swift:42`, `index < count - 1`) **[311a53b]**. Page changes wait for art and wordmark
  (`AppleHeroPageGate.swift:96-109`). Wordmark grace 5 s (`AppleHeroTitlePolicy.swift:37`).
- **tvOS.**
  - Art 1920×980 (`AppleTVBillboardMetrics.swift:20`). Wordmark ≤ 558×140.8 (`AppleTVBillboardView.swift:125`).
  - Synopsis one line, 28 pt (`AppleTVBillboardMetrics.swift:37`).
  - No trailer (`AppleTitlePagePolicy.swift:279-281`). Server trailers (Plex/Jellyfin) arrive on another branch.
  - **The cycle pauses whenever anything in the hero has focus** (`AppleTVHeroPaging.swift:68-70` returns
    `heroHasFocus`; `AppleHomeTVHeroCarousel.swift:95-97`). Focus lands on Play when Home opens
    (`AppleTVHeroPaging.swift:60-62`), so **an idle Apple TV Home never cycles**. 311a53b does not touch this file.
  - **Page change is a hard cut** (`AppleHeroPageGate.swift:50-77`; `AppleTVBillboardView.swift:49-114`); only the
    scrim animates (0.4 s, `:69`).
  - Indicator: 4 pt high, 14/48 wide (`AppleTVBillboardMetrics.swift:64-67`).
- **iPhone.**
  - Full-bleed art to 73 % of the screen, at least 440, with 90 pt of the first row showing
    (`AppleHomePhoneHeroLayout.swift:26-53`).
  - Push transition `.smooth(0.45)` (`AppleHomePhoneHeroCarousel.swift:43,123-127`).
  - Wordmark ≤ 280×96 (`AppleHomePhoneHero.swift:154`). No synopsis.
  - Buttons: white Play (min 180×50, radius 12) and a 44 pt round My List (`AppleHomePhoneHeroActions.swift:17-55`).
  - Trailer starts 2 s after the art, hidden until 4.5 s of media (cap 12 s)
    (`AppleHomeBillboard.swift:701-730`; `AppleTrailerRevealPolicy.swift:28-54`) **[311a53b retimes the start]**.
- **iPad / Mac.**
  - Height min(900, w × 0.9, h × 0.66) / w × 0.75 (`AppleMacHeroLayout.swift:46-67`).
  - Synopsis 3 lines (`:78-81`).
  - **No 1 s advance after a trailer** (`AppleHomeHeroCarousel.swift:81`) **[311a53b]**.
- **Rotating hero (iPhone landscape, Vision Pro, iPad at accessibility sizes).**
  - Boxed with radius 18 (`AppleHomeHeroCarousel.swift:110`; `AppleMediaShelf.swift:259`).
  - **Pink brand Play/Details buttons** (`AppleMediaShelf.swift:389,398`); every other hero is white.
  - Hard cut between pages.
  - **The indicator fills from the wall clock** (`AppleHomeBillboard.swift:482-488`), so it runs on while the cycle
    is held.
- **Release logging.** A `print` of the title, YouTube key and state runs on every trailer state change
  (DV:5382).

### Gaps
1. The tvOS hero never cycles while focus rests on Play. Apple's auto-advance ignores focus; it stops for real
   interaction, full screen, off-screen and accessibility.
2. tvOS and the rotating hero hard-cut. Apple slides in 1.0 s on TV, with metadata fading separately. iPhone and Mac
   already push.
3. The rotating hero's pink buttons and wall-clock indicator are inconsistent with the other heroes.
4. Dwell, wrap, trailer timing and stall handling are fixed on 311a53b, not on main.

## 2. Title page: header, trailer, wordmark, buttons, episodes

### Reference rules
- **Apple TV app (new, Observed).**
  - **Header.** `CanonicalBannerLayout` (accessor 0x2a24cc460) holds a full-width backdrop with its own
    background-media controller (round 3).
  - **Info-block stack order** (field order of `CanonicalBannerInfoView`, 0x2a29cab40): badge → title image → title →
    subtitle → episode info → promo → description → genres/provider tags → metadata and badges → buttons → disclaimer →
    availability.
  - **Info block inset from the banner bottom** (0x2a24cae24): TV 75, Vision 80, Mac 40. iOS derives it from the
    width bucket.
  - **Width buckets** (0x2a1fb0ec0): < 1000, 1000–1320, ≥ 1320 usable points.
  - **Per-bucket metrics** (0x2a24cd0dc–0x2a24cd2ac; Inference that these are max width/height; the six slots are not
    mapped to platforms):
    - text max width 340/360/600/280/450;
    - title image max width 235/420/255/376;
    - title image max height 60/126/50/93.
  - **The header video stops when half off screen** (`VUICanonicalConfig init` 0x2a1cd14d8:
    `videoViewOffscreenThresholdToStopPlayback` 0.5; playback delay 1.0 s).
  - **Mac backdrop gradient mask** covers 0.5 of the rect height (`VUIProductUberBackgroundView`). This is Apple's one
    fade; ours must stay the single approved billboard fade.
  - **Primary button** carries the episode: "Play S%@, E%@" / "Resume S%@, E%@" (loc keys). The Up Next toggle is a
    separate button.
  - **Episodes.** The season picker is a horizontal strip whose highlight changes the season (`SeasonPickerView`
    `highlightedSeasonIndex`; Inference from the logs). On Mac it is a button with ⌃⌄ that opens a popup menu (17 pt,
    0.2 s).
  - **Episode row.** Horizontal compositional section, inter-group spacing **20**, scroll animations 0.25 s
    (0x2a1e4c890–0x2a1e50b40).
  - **Episode lockup** (`EpisodeLockupLayout`): image, badge, title, subtitle, button, download indicator,
    **playbackStatus (progress on the lockup)**, a 16:9 darkening gradient for accessibility. Progress bar radius 2–3.
  - **Footer** bottom padding 60 (0x2a25095a0).
- **Netflix phone (new, Observed).**
  - **Header** (`FullDpEpoxyController.buildMiniPlayerModels`, :1284-1390): a **16:9 mini-player** when a trailer
    exists, otherwise the box art.
  - **Trailer** (`o.kkP`, `PlayerSessionConfig("TrailerDP")`):
    - autoplays only with the setting on and no screen reader; does not loop;
    - mute state is shared with the rest of the app;
    - stops when it falls below its visibility threshold and **does not resume by itself**;
    - states: ReadyToPlay(image) → Buffering → Playing → **Finished(image)**, which returns to the still; Error(image).
  - **Controls** (`o.lAA`): play/pause, mute, seek, time and full screen; hide after **3000 ms**; the end state is a
    Replay button.
  - **Body order:** title (28 sp, max 2 lines, auto-size 20–28) → metadata line → Play (full width, min 40 dp,
    radius 3) → Download → progress → synopsis (**max 6 lines**) → cast/creators → action row (My List, Rate, Share;
    72–96 dp items) → tabs Episodes / More Like This / Trailers & More.
  - **Metadata line:** year · boxed rating · seasons/runtime at 60 % · quality badges at 12 sp (priority HD, UHD, 5.1,
    HDR10, HDR10+, DV, Spatial, AD, Subtitles).
  - **Episode row** (0x7f0e0095):
    - 130×80 dp thumbnail, radius 4, **2 dp progress bar on the thumbnail**;
    - number + title up to 5 lines; runtime at 55 %;
    - 60×80 trailing download button; synopsis below, max 5 lines; row bottom margin 21.
  - **Season picker:** a single-line button with a chevron; a plain label when there is one season.
  - **More Like This:** a 3-column grid, aspect 0.71.
  - **Opening:** no mini sheet first (only `FullDp` exists); phones use the default activity transition, tablets slide
    up over 200 ms.
- **Deliberately absent in both.** Explanatory paragraphs (no glossary of CC/SDH/AD; badges are icons with
  accessibility labels), quality pickers on the main surface, source names, and a debug or fix-match action on the
  primary button.

### OpenStream now
- **tvOS** (`tvOSDetailLayout`, DV:3522):
  - 1920×1080 backdrop masked from opaque at 0.72 of its height (`AppleTVDetailMetrics.swift:151,157`).
  - Copy inset 80 / bottom 60 / 900 column (`:160-166`). Wordmark ≤ 560×180 (`:169`). No trailer.
  - Buttons: Play pill ≥ 220×66 → Skip to Movie → Start from Beginning, then 80 pt My List and Rate discs
    (DV:4558-4752).
  - **Synopsis has no line limit** (`AppleTVDetailViews.swift:209-218`).
  - Episode cards 400×225, gap 40 (`AppleTVDetailMetrics.swift:209-224`), **no progress bar, no synopsis**
    (`AppleTVDetailViews.swift:129-137`).
  - Season control: a `Menu` pill 56 high (DV:4881-4926).
- **iPhone:**
  - **16:9 box under the status bar; the copy sits below it on black with no fade** (`AppleTitlePageSlotArt.swift:63-65`;
    DV:9590-9626). About 221 pt of art vs build 15's about 596 pt. This is the owner's "wordmark is below the trailer, it
    got worse" (recording 10-15) **[311a53b restores the 70 % full-bleed header]**.
  - Trailer: 2 s after the still, muted (DV:3721-3741), 15 s timeout (`AppleTrailerArtFirstPolicy.swift:13`), blocked by
    Low Power even when pressed (DV:5208-5239) **[311a53b]**.
  - Buttons: full-width white Play (radius 12, min 50) (DV:9881-9894), then 44 pt round My List / Download / Rate
    (`AppleTitlePageSections.swift:778-803`).
  - Play's long-press menu holds Start from Beginning, Quality, Play version… and Fix Match (DV:9946-9958).
  - Synopsis 3 lines (DV:10097-10133).
  - Episode cards: min(360, (w − 16) × 0.74), progress on the still, overview 3 lines, **no runtime**
    (`AppleTitlePageSections.swift:432-510`).
  - Season picker: a capsule that opens a 240-wide popover (`:231-344`).
  - Sections below: Discs → Trailers → **"Related"** (iPad and tvOS say "More Like This", DV:9551 vs 4038/4930) → Cast →
    About → Information → Languages → **Accessibility glossary paragraphs** (`AppleTitlePagePolicy.swift:454-462`;
    DV:9570-9579).
- **iPad / landscape:** the trailer is **crop-zoomed** (1.35× upright; landscape cuts 14 % from the top and 9 % from
  the bottom, DV:8624-8656), which contradicts its own "nothing is cropped" comment (`AppleTrailerRevealPolicy.swift:8`).
- **Explainer and status text on the page:**
  - "Episodes aren't available from the connected metadata sources." (DV:4840, 6147, 10177, 10210, 10867);
  - "Download cancelled. You can retry when you're ready." plus the raw error (DV:5679-5688).

### Gaps
1. iPhone header boxed with the copy below. Both references keep title/buttons in or directly against the header with
   one fade; the owner wants build 15's full-bleed **[311a53b]**.
   - Netflix's 16:9 mini-player is the counter-example, and it is what 13a2677 copied. The owner has rejected it.
2. tvOS episode cards lack progress. Both references draw progress on the episode image.
3. tvOS synopsis is unclamped. Netflix uses 6 lines; Apple uses the description slot with a "more" action.
4. iPhone episode cards lack runtime. Netflix shows runtime on every row.
5. The glossary, "aren't available" lines, inconsistent "Related" naming and the debug `print` are all absent from both
   references.
6. iPad/landscape trailer crop. Apple and Netflix fit or fill the header box without zooming past it.

## 3. Live: guide, categories, channel switching, mini player

### Reference rules
- **Paramount+ TV (new, Observed).**
  - **The guide is not a time grid.** Each channel row is a logo plus a horizontal list of **fixed 313×48 dp programme
    cards** (`ga5.invoke`; `DefaultEpgRowItemSizeSpec`).
    - Card content: title + start time, a 3 dp progress bar (on now only), an 85 dp thumbnail (current card only), and
      a 2 dp border when focused.
    - **No dp-per-minute, no time ruler, no now-line anywhere.**
  - **Row sizes.**
    - P+ row: 48 dp, logo 40×40 on a 92 dp plate at 0.75 alpha (`c05.q`), rows 6 dp apart, listings starting at 98 dp.
    - Pluto compact row: 50 dp, logo 72×36.
    - Featured row: 92 dp, logo 50×50.
  - **Overlay.** The guide lies over **full-screen video that keeps playing**; the video is never resized
    (`fragment_livetv_video.xml` `video_frame` match_parent).
    - P+ fade: clear at the top to black at 55 % of the height (`c05.p`); Pluto uses a 5-stop fade.
    - Details drawer 320 dp with a 320×180 image (`lg4`).
  - **Auto-hide.** The guide hides after **10 s**, restarted by **every key press** (`mz4.a`, `jt6.dispatchKeyEvent`),
    and **never while system accessibility is on** (`zb8.C`).
  - **Scrolling and refresh.** Scroll-to-channel is debounced 500 ms (`kz4.a`). A failed guide load retries every 10 s
    while the channel keeps playing (`wq9.b`).
  - **Categories.**
    - P+ uses a horizontal chip row (top 32, spacing 11); Pluto uses a vertical tab list.
    - Categories come straight from the server; **the app adds no "All" or "Favorites" chip and shows no counts.**
    - Picking a category filters the list **without touching playback** (`u05`, `CategoryClickedItem`).
    - Pluto instead jumps within one continuous list, and the highlighted tab follows focus.
  - **Switching.**
    - **Focus never tunes**; clicking a listing sends `WatchLiveRequest`.
    - **Up/down surf accumulates the target in an AtomicInteger and restarts a 400 ms wait on every press, so there is
      one tune 400 ms after the last press** (`vq9.m1`, `wq9.c`).
    - **No wrap**: it stops at the first and last channel. It skips channels the user isn't entitled to.
    - No banner and no spinner on surf in the live screen; buffering is left to the player.
  - **Channel memory** (`livetv_channel_resume_time`, `sk2`/`vu9`): "session" (in memory) or N minutes. First channel
    on opening: deep link → last viewed (within the window) → server default (`yca.l`).
  - **Guide on startup** is true for P+ US and Pluto (`tx2` case 9).
  - **Deliberately absent:** channel numbers (no number field in any model), a time ruler, duration-scaled cells, an
    app-added All chip, on-screen help (accessibility strings only), TV PiP and video shrink.
- **Apple TV app (new, Observed).**
  - Multiview: up to **4** players, padding **20×20** (`VUIMultiviewConfig init` 0x2a1cd18f4).
  - Live post-play: auto-dismiss 30 s, shelf height 180, a 40×40 countdown ring with line width 4, score polling 60 s.
  - PiP resize animation 0.25 s. No channel-guide constants exist in VideosUI.
- **Paramount+ phone:** not available (see Evidence base). The owner's pinned-video phone layout stays the rule.

### OpenStream now
- **iPhone / iPad (`liveStage`).**
  - Pinned 16:9 video, full width, no title bar (MSV:388, 1459-1464). Side by side at ≥ 894.7 pt with the player at 62 %
    (`AppleLiveStagePolicy.swift:7-22`).
  - Category row 44 pt, 17 pt semibold text tabs with a 2 pt white underline (`AppleLiveCategoryBar.swift:28-88`), plus
    a Guide glyph **and** a Search glyph (`:43-65`).
  - Order: All, Favorites, Events, then fixed groups (`AppleLiveCategoryOrder.swift:13-23`;
    `AppleLiveChannelSnapshot.swift:224`).
  - Rows ≥ 60 pt, logo 48×32, name over what's on now, **no number, no next, no per-row progress**
    (`AppleLiveOnNowList.swift:141-160`).
  - **Pink WATCHING pill** on the playing row (`:156-157`, `:169-176`). The owner (recording 10-15): "the Watching
    pills … kind of like AI sloppy".
  - **"Showing N of M channels" line** (`AppleLiveOnNowList.swift:65`; MSV:316; TVG:563).
  - Tap plays inline; tapping the playing row goes full screen (MSV:1535-1542).
  - While tuning: a black frame, a 132×76 logo and a large spinner (MSV:1573-1584).
  - **No mini player.** PiP only in full screen (MSV:1821-1822). Leaving the tab stops playback
    (`AppleLivePlaybackLifetime.swift:10-27`).
- **Shared guide grid** (macOS main view, the iOS Guide sheet):
  - Channel column 144, **160 pt per 30 min**, rows 76 (GG:48, 72-73).
  - Header with a "Channels" label (GG:120); 1 pt pink now-line (GG:134).
  - **Window runs from now to midnight with no minimum** (`AppleGuideChannelProjection.swift:45-54`), so at 23:45 it
    shows one slot. tvOS has a 3 h floor (TVM:106-112).
  - Re-projects up to 300 rows every 60 s (GG:76, 158-205).
- **tvOS (`AppleTVLiveGuideScreen`).**
  - **No video until Select.** Layout: info panel (196 tall, 320×180 tile) → chips → hour labels → grid (TVG:234-238;
    TVM:42-48).
  - The tile becomes a muted preview after 1.2 s of focus, only when trailer autoplay is on
    (`AppleTVGuidePreviewPolicy.swift:18`).
  - Grid: **240 pt per 30 min, rows 68**, channel column 340, logo 64×36, number column 60 (TVM:15-29); 3 pt pink
    now-line (TVM:30).
  - Chips: All, Favorites, groups; no Events (MSV:1252).
  - **Zap: no throttle.** Every press cancels and reopens a stream (TVG:2181-2192), **wraps at both ends**
    (`AppleLiveZappingPolicy.swift:41-52`), shows black + spinner + "Connecting to X" (TVG:1728-1752) and drops the old
    picture (TVG:1840-1846).
  - Banner with **"Now:" / "Next:" labels**, 2 s (`AppleLiveChannelBanner.swift:12-29`).
  - **One-time hint text**, 6 s (TVG:1760-1779).
  - Channel strip cards 224×214 (TVM:55-58) with **red "LIVE" text** (TVG:1464). **The strip closes 5 s after opening
    even while being browsed**: the timer is keyed on visibility only and focus moves don't restart it (TVG:1780-1785).
  - **Resume re-arms on every visit to Live and opens full screen** (MSV:408, 993; `AppleLiveSession.swift:75-82`).
  - Reconnect: 1/2/4 s within 15 s, an 8 s stall counts as a drop (`AppleLiveReconnectPolicy.swift:50-54`). This
    matches the "recoverable failure" rule.
- **Also on screen:** health dots and "Channel Info" (GG:346, 364; TVG:913), a failure line naming the provider host
  (`AppleLiveFailurePresentation.swift:56-76`), a pink underline on macOS chips (MSV:273), and a modal "Channel
  Unavailable" alert after a failed probe (MSV:526, 1318) while every other live failure is drawn in the picture.

### Gaps
1. **Zapping.** We open a stream per press and wrap. Paramount coalesces presses to one tune 400 ms after the last one
   and stops at the ends. One-connection IPTV providers punish our way.
2. **Tuning visual.** We go black with a spinner and a "Connecting" line. Paramount shows no switch spinner and lets
   the player keep its surface.
3. **tvOS strip auto-hide.** 5 s from opening vs Paramount's 10 s restarted on every key, and off under
   accessibility.
4. **The guide has no video behind it on tvOS.** Paramount keeps the channel playing full screen under the guide.
   - This conflicts with the owner rules (no dimming over video; on tvOS "video pinned at top" isn't written).
     **Owner decision.**
5. **Slop the references don't show:** WATCHING pill, "Showing N of M", "Now:/Next:" labels, one-time hint, red
   LIVE, health dots, the provider host in failures, the Guide glyph beside Search.
6. **The iOS guide window collapses near midnight.**
7. **tvOS resume re-arms every visit.** Paramount resumes the last channel only inside a time window.
8. **Mini player.** Neither reference has an in-app mini player (Paramount TV: none; Apple: PiP only). Our "leaving
   the tab stops playback" matches that. The owner's item "swiping home stops Live" asks for automatic PiP, which is
   the Apple-native answer.

## 4. Library

### Reference rules
- **Apple TV app (new, Observed).**
  - Library menu types (`LibMenuType`): Recently Purchased (and split by Movies/TV), **Movies, TV Shows, 4K HDR,
    Downloaded, Genres → Genre**, Home Videos, Rentals, Family/Home Sharing. The sidebar groups by source kind, not by
    folder.
  - Grid stack with item and group spacing **20 / 20** (0x2a2344de4); lockups `LibraryLockup` / `libraryListLockup`.
    Column counts are server or adaptive.
  - A "Find in %@" filter bar.
- **Netflix My List (new, Observed).**
  - A **list**: rows with 140×80 dp landscape art, title up to 3 lines and a trailing Play or (in edit mode) Remove,
    min row 80 dp (0x7f0e0252).
  - Sort: Suggested / Date added / Alphabetical / Release date; filters with Clear All.
  - Empty states: one title, one line and one button.
- **Deliberately absent in both:** per-folder or per-source shelves, raw file names, inline scan errors, unbounded
  rows.

### OpenStream now
- **Shelves on every platform, no grid** (MSV:3321-3351). Top to bottom: hero, an inline error label, Continue
  Watching, **one shelf per source per kind** ("Movies" or **"Movies · <source>"**, plus **"Other"**, MSV:3300-3316),
  provider shelves, Recently Added (cap 24), Unmatched.
  - Per-kind shelves are **unbounded**: every title goes in one row (MSV:3313).
- **See all.** Local shelves open a **text list** of title and year (`AppleLocalLibraryStore.swift:1057-1066`).
  Provider shelves open a grid, 100 per page.
- **Errors and unmatched.** Raw scan errors appear inline ("<source>: <error>", MSV:3335-3337;
  `AppleXtreamLibraryView.swift:26-31`). The Unmatched list shows raw file names (`AppleLibraryUnmatched.swift:45-51`).
- **Sort.** Added / Title / Year (`AppleLibraryShelves.swift:92-95`). On tvOS it is a bare glyph on the first shelf's
  header (MSV:3424-3435). No Genres, no TV Shows / Movies split across sources.
- **Owner (recording 10-15):** "not enough categories in library, it just says movies … I shouldn't be able to tap
  recently added here … I didn't ask for this".
- **Loading.** Sources scan one at a time and nothing appears until all are done
  (`AppleLocalLibraryStore.swift:487-559`). One spinner, no placeholders.

### Gaps
1. **Categories.** Movies / TV Shows / Recently Added / Genres across all sources, not per folder. Rows capped about
   20 with a poster-grid See All.
2. **No poster grid anywhere for local media.** Apple uses a 20/20 grid.
3. Raw errors and file names on the main surface.
4. Progressive loading is missing: the first source should show before the last finishes.

## 5. Search

### Reference rules
- **Apple TV app (new, Observed).**
  - **Debounce 750** (`SearchTemplateController.searchFieldTextDidChangeFireDelay`, `mov w9,#0x2ee` at 0x2a1f0c2b0).
    Each keystroke cancels a pending `DispatchWorkItem`.
  - States: landing → history → hints → results.
  - **Recent searches store whole items as lockups**, 10 (`RecentlySearchedDataManager` cacheCapacity at 0x2a1f66dc4),
    with clear-all and per-item remove.
  - Results: **top results plus a category filter bar** (server categories), lockup kinds for titles, sports, cast,
    brand and team. Header 68; result transitions 0.25 s.
- **Netflix (new, Observed).**
  - **Debounce 700 ms** while typing, 0 on submit or clear (`o.mSW`; legacy `mQO.w`).
  - Before typing: a pre-query list ("Loading/Error/Success").
  - Results: poster rows, section header 24 dp. No-results: one title plus one line. Voice input. No recent searches.
- **Deliberately absent:** source names on results, a refresh button, rows that do nothing when tapped, text-only
  results on TV.

### OpenStream now
- **Placement.** tvOS: a leading Search tab (`OpenStreamRootView.swift:206-212`). Elsewhere: a magnifying-glass icon on
  Discover and Library (`AppleTabToolbar.swift:33-37`).
- **Timing.** 100 ms debounce, 2 s add-on deadline, 100 results, re-rank on every keystroke
  (`AppleCatalogSearchLookup.swift:300-350`).
- **Results.** **One flat `List`, not grouped, on every platform including tvOS** (DV:2000-2023). Each row: 58×87 poster,
  title, **source name**, kind + year (DV:2312-2328).
- **Dead rows.** **Channel and unmatched-file results are not links**: they look tappable and do nothing
  (DV:2017-2019; `AppleMediaIndex.swift:606-611`).
- **Empty results too early.** **"No results" shows while add-ons are still answering** (up to 2 s; `isSearching`
  unread, DV:1997; `AppleCatalogSearchLookup.swift:281`).
- **Prompt.** "Search movies, shows, and channels" (DV:2031), but Release builds have no catalog search without add-ons
  (`AppleCatalogSearchLookup.swift:363-366`).
- **Recents.** 10 query strings (`AppleRecentSearches.swift:9`), recorded on submit or after 2.5 s idle.
- **Other.** A Refresh button inside Search (DV:2185-2210). Live search is a separate screen, and on tvOS a Form text
  field (MSV:3004-3026).

### Gaps
1. tvOS results should be posters grouped by kind (Movies, Shows, Channels), not a text list.
2. Dead channel rows: a channel result should tune.
3. The no-results flash.
4. The debounce is 100 ms vs 700–750 ms in both references. 100 re-ranks and redraws on every key; the slower debounce
   also cuts network calls.
5. Recents should store the opened item, not just the query.
6. Remove source names, the Refresh button and the overpromising prompt.

---

## Prioritised gap list (fix jobs)

Size: S ≤ half a day, M = 1–2 days, L = 3+ days. "Measure" is the acceptance check. Each job follows the owner UI rules
(AGENTS.md §4) and is verified on iOS 18.6 **and** iOS 27 (or DevTV for tvOS).

| # | Job | Screens / files | Reference rule | Measure | Size |
|---|---|---|---|---|---|
| 1 | **Merge 311a53b to main and verify on the owner's iPhone (iOS 18) and DevTV.** Wrap, 8 s stall give-up, 1 s post-trailer advance everywhere, 6 s stills, timed start, full-bleed title header, pressed trailers under Low Power, remembered mute | Hero, title page | Apple showcase defaults (round 3) | 10 min idle on Home: page index wraps ≥ 2 times; iPhone title header ≥ 70 % of the screen with wordmark on the art; no regression in the hero E2E | S |
| 2 | **tvOS hero cycles while Play merely has focus.** Pause only for 5 s after the last remote input (paging, a press) and while a cover or full screen is up. Keep the paging stops | `AppleTVHeroPaging.swift:68-70`, `AppleHomeTVHeroCarousel.swift:95-97` | `shouldEnableAutoAdvance` has no focus input; hide-indicator delay 5 s | DevTV idle on Home with Play focused: a page change every 6 s (stills), focus stays on Play across the change | S |
| 3 | **tvOS and rotating hero: crossfade between pages.** Art 1.0 s, copy fade out then in, Reduce Motion = instant. No new scrim | `AppleHeroPageGate.swift:50-77`, `AppleTVBillboardView.swift`, `AppleHomeHeroCarousel.swift:105-110` | autoSwipe TV 1.0 s; metadata fade separate | Frame capture: no single-frame cut; 1.0 ± 0.1 s transition; Reduce Motion cut | M |
| 4 | **Live zap coalescing.** Collect presses, tune once 400 ms after the last; stop at the ends (no wrap); keep the logo and number visible while the target accumulates | TVG:2181-2192, MSV:2591-2599, `AppleLiveZappingPolicy.swift:41-52` | Paramount `vq9.m1` / `wq9.c` | 5 presses in 1 s → exactly 1 stream open (trace `live zap`); Up on the last channel does nothing | S |
| 5 | **Live tuning visual.** Keep the last frame (or the channel logo on black without a spinner for the first 1 s) and show a spinner only after 1 s. Drop "Connecting to X" | TVG:1728-1752, 1840-1846; MSV:1573-1584 | Paramount: no surf spinner, player keeps its surface | Zap on DevTV: no spinner frame when first frame < 1 s; no text line | M |
| 6 | **Live de-slop.** Remove the WATCHING pill (playing row = white title + a small speaker glyph), "Showing N of M", "Now:/Next:" labels (time ranges only), the one-time hint, red "LIVE" text, health dots on the main list, the provider host in the failure line, the pink macOS underline, and the extra Guide glyph (Guide inside the ⋯ or a long press) | `AppleLiveOnNowList.swift:65,156-176`; `AppleLiveChannelBanner.swift:15-16`; TVG:1464,1760-1779; GG:346; `AppleLiveFailurePresentation.swift:56-76`; MSV:273; `AppleLiveCategoryBar.swift:43-53` | Paramount absent list; owner rules (no coloured label text, no explainer text) | grep: none of these strings in Release; UI test row identifiers unchanged | S |
| 7 | **tvOS channel strip auto-hide 10 s, restarted on every focus move, off under VoiceOver;** don't clear the pending captions choice | TVG:1780-1785 | Paramount `mz4.a` 10 s, `jt6.dispatchKeyEvent`, `zb8.C` | Browse the strip 20 s with moves every 3 s: stays open; idle 10 s: closes | S |
| 8 | **Search, step 1 (correctness).** Channel results tune; unmatched results open Fix Match; spinner (not "no results") while sources answer; debounce 300 ms (local index) with add-on calls at 700 ms; drop source names and Refresh; Release prompt matches what's searched | DV:1997-2331; `AppleCatalogSearchLookup.swift:281,300-366` | Apple 750, Netflix 700; no dead rows | Typing "news": ≤ 2 result redraws; tapping a channel tunes; never "No results" before the 2 s deadline | S |
| 9 | **Search, step 2 (layout).** tvOS: poster lockups in sections Movies / Shows / Channels (+ Top Result). iOS: same sections as rows. Recents store opened items (10) with remove | DV:2000-2023; `AppleRecentSearches.swift` | Apple category filter + top results + item recents | DevTV: results are a focusable poster grid; section count ≤ 4 | M |
| 10 | **Library categories.** Replace per-source/per-kind shelves with Movies, TV Shows, Recently Added, Genres across sources; rows capped at 20 with See All = a poster grid (spacing 20); "Other" only if non-empty and named by kind; no tappable Recently Added header (owner) | MSV:3300-3351; `AppleLocalLibraryStore.swift:1057-1066` | Apple `LibMenuType`; 20/20 grid | Owner config: ≥ 4 categories; no row over 20 cards; See All opens posters | M |
| 11 | **Library: move raw errors and file names off the main surface** (errors → a source status in Settings; Unmatched shows the parsed name, file name only in Fix Match); progressive scan (show each source when done) | MSV:3335-3337; `AppleLibraryUnmatched.swift:45-51`; `AppleLocalLibraryStore.swift:487-559` | Neither reference shows raw errors | First source's shelves visible before the last source finishes (trace) | M |
| 12 | **Title page clean-up.** Remove the Accessibility glossary paragraphs and the "Episodes aren't available…" line (hide the section); name the row "More Like This" everywhere; delete the Release `print` | `AppleTitlePagePolicy.swift:454-462`; DV:4840,5382,6147,9551,10177,10210,10867 | Both references: icons + labels, no prose | grep Release strings; no `print(` in DV | S |
| 13 | **tvOS title page.** Episode cards get the 3 pt progress bar and a 2-line synopsis; the page synopsis is clamped to 3 lines with a focusable More | `AppleTVDetailViews.swift:129-137,209-218` | Apple `playbackStatus` on the lockup; Netflix 6-line synopsis, progress on the thumbnail | DevTV: a partly watched episode shows its bar; long synopsis ≤ 3 lines | S |
| 14 | **iPhone episode card: add runtime;** keep the 3-line overview | `AppleTitlePageSections.swift:432-510` | Netflix row: runtime on every episode | Card shows "N min" when known | S |
| 15 | **iPad/landscape trailer: fit, no zoom** (letterbox inside the header frame) and fix the comment | DV:8624-8656; `AppleTrailerRevealPolicy.swift:8` | Apple header backdrop; Netflix 16:9 box, no crop | No crop transform on the trailer layer | S |
| 16 | **Rotating hero consistency.** White Play like the other heroes; indicator driven by the cycle, not the wall clock | `AppleMediaShelf.swift:389,398`; `AppleHomeBillboard.swift:482-488` | Owner rule (nothing coloured but the brand mark); Apple indicator tied to paging | Indicator stops while held | S |
| 17 | **iOS guide window floor 3 h** (like tvOS); re-project only visible rows on the 60 s tick | `AppleGuideChannelProjection.swift:45-54`; GG:158-205 | Paramount guide always shows upcoming cards | At 23:45 the grid shows ≥ 6 slots | S |
| 18 | **Live resume like Paramount:** resume the last channel only on the first Live entry per launch and only if it was watched in the last 30 min; never re-arm on every tab visit | MSV:408,986-995; `AppleLiveSession.swift:75-82` | `livetv_channel_resume_time` window; `yca.l` priority | Leave and re-enter Live on DevTV: no auto full screen | S |
| 19 | **Live automatic PiP on iOS when leaving the app from the inline player** (owner item "swiping home stops Live") | `AppleLivePlaybackLifetime.swift:10-27`; MSV:1821-1822 | Apple: PiP as the only mini player; Paramount has none in-app | Swipe home while playing inline: PiP window appears | M |
| 20 | **Owner decision, tvOS Live.** Keep the guide-first screen, or play the channel full screen behind a guide overlay (Paramount TV, guide on startup, 10 s auto-hide)? The overlay needs a fade, which the no-dimming rule forbids today | TVG:234-238 | Paramount TV live host | Owner choice recorded in OWNER-TODO | — |
| 21 | **Owner decision, Live categories.** Paramount adds no All/Favorites chips and shows no numbers; ours adds All, Favorites and Events and shows numbers in the guide. Recommend keeping All and Favorites (IPTV lineups are huge) and dropping the per-row numbers only on iOS, where they don't appear anyway | `AppleLiveCategoryOrder.swift:13-23` | `kx4` server-only categories | — | — |

Not proposed as parity work:
- **Netflix's 0.71 cards and red Play.** Owner rules are white, stock Apple.
- **Netflix's 16:9 title-page mini-player.** The owner rejected it in 13a2677's aftermath.
- **Paramount's no-ruler card guide.** Our grid is the owner-approved secondary guide; keep it, fix job 17.
- **Apple's Mac backdrop blur.** Against the no-scrim rule.

## How this was done
- Read `/Volumes/Files/Projects/AGENTS.md`, `native/apple/AGENTS.md`, the spec, the six earlier GUI/hero reports, OWNER-TODO,
  the owner's 10-15 recording transcript and the iphone-jank checklist (b7b0a91).
- Dev-Mini gate: the build lock was held by a simulator chain. This work used no lock, no Ghidra and no simulator: only
  static `dyld_info`/`dexdump`/single-class jadx at low priority.
- Five parallel workers: two mapped OpenStream source (every number re-read with `grep -n`; I re-checked
  `AppleHeroRotationCycle.swift:42`, `AppleTVHeroPaging.swift:68-70`, DV:5382, TVG:1780-1785 and 2181-2192,
  `AppleGuideChannelProjection.swift:45-54`, `AppleLiveOnNowList.swift:65,156` and `AppleTitlePageSlotArt.swift:63-65`
  myself). Three did the reverse engineering (VideosUI, Netflix, Paramount+).
- The earlier `/tmp/rea-worker-a-*` decompiles had been cleared by the mini's hourly cleanup and were rebuilt narrowly.
  Scratch stays in `/tmp/rea4-*` on the mini; nothing is running.
- Branch coverage checked with `git diff main...hero-trailers --stat` and `git show 311a53b`.
- Only this file was written in the tree.
