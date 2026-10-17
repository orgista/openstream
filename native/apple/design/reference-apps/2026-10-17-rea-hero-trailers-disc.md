# REA round 3: hero cycle, title-page trailers, disc open (2026-10-17)

Spec: `specs/rea-round3-2026-10-17.md`. Static reading of shipped code only: no builds, no devices, no build lock. No reference code,
strings or assets were copied into OpenStream. Builds on the 2026-10-11 hero report, which only listed config keys. This round
recovers their **default values** and the **state logic** from code.

**Platform caveat.** Apple's evidence is the macOS 27 `VideosUI` framework. That framework is shared code: it branches on `isTV` /
`isPhone` / `isMac` at runtime, and the TV branch values are quoted below. The tvOS binary itself (FairPlay) was not read. A server
config can override every default.

## Do this (ranked)

1. **Make the hero cycle wrap again.** Since f82ef99 the hero stops on the last page (`AppleHeroRotationCycle.swift:42`, `index < count - 1`; max 5 pages). That is the "hero cycle is gone" report. Apple's controller also stops by default (`shouldAutoAdvanceLastPage` = false, §1.6), but build 15 wrapped and the owner wants that back.
2. **Give the Home hero trailer a startup timeout (about 8 s).** On timeout, treat it as a failure: show the still and restart the page timer. Today `isPlaying = true` is set when the trailer is requested (`AppleHomeBillboard.swift:726,749`), and a stall with no error holds the cycle forever. Only the title page has the 15 s timeout.
3. **Video pages: advance 1 s after the trailer ends, on every platform.** Apple's TV default is `advanceToNextPageDelayDuration` = 1.0 s, and its timer is ignored while video plays. iPhone already does this; iPad still waits out the rest of 12 s (`AppleHomeHeroCarousel.swift:81`).
4. **Image-only pages: dwell 5–6 s, not 12 s.** Apple's `advanceToNextPageDelayDurationImageOnly` = 5.0 s (10 s in a second state). Ours is a flat 12 s (`AppleHeroRotation.swift:13`). With 5 pages and 12 s each the cycle feels stalled before it even reaches the last-page stop.
5. **Time trailer start from the request.** Apple: TV 1.0 s, iPhone 0.5 s, iPad/Mac 2.0 s, *minus load time*; it starts at once if loading took longer (§1.2). Ours: a fixed 2 s after the art loads, then 4.5 s of hidden playback. The picture appears about 7 s or more after the page.
6. **iPhone title page: undo 13a2677's small 16:9 box.** Go back to build 15's full-bleed header with the one approved billboard fade. Apple's product page also puts the video in the full-width header backdrop (§2).
7. **Owner decision: YouTube's overlay.** d70aea9 stopped hiding YouTube's title strip, logo and "More videos" for terms-of-service reasons. That is the biggest visible regression from build 15 (§4). Don't silently revert it. Ask the owner.
8. **Prefer a clean preview source, with YouTube as fallback.** Apple plays its own HLS previews (`previewHlsUrl`, `BackgroundTrailer`) in AVPlayer, with no third-party chrome. Check that the iTunes Search API trailer `previewUrl` is allowed for this use; if so, play it in AVPlayer where it exists and keep YouTube as the fallback. This removes items 5 and 7 at the source.
9. **A pressed trailer must play under Low Power Mode or with "Auto-Play Video Previews" off.** Apple's switch gates only *automatic* playback ("accessibility video autoplay is disabled"); the explicit Play Trailer is separate. f82ef99 blocks both (`AppleDiscoverView.swift:5209,5217-5223`).
10. **Remember the user's sound choice.** Apple seeds sound from server config, but once the user taps mute or unmute that choice wins (`AutoPlayBgVideoSoundUserHasChanged`). It also mutes in background and ramps volume over 2 s in 5 steps. Ours hard-sets muted on every trailer (`AppleDiscoverView.swift:3713,3735`).
11. **Give the hero page gate a timeout.** If a page's art never reports loaded or failed, the timer waits forever (`AppleHeroPageGate.swift:106`). `AppleCatalogArtwork` drops `onFailure` while it waits for its size (`AppleDiscoverView.swift:3194`). Apple shows a placeholder and keeps paging.
12. **Prefetch the next hero page's trailer.** Load the player while the current page shows. Apple keeps a "prefetch player" for the next video, skipped during AirPlay, and preloads hero images 20 at a time.
13. **ISO open: read disc structure up front, Infuse style.** Infuse wraps every network file in a read-ahead loader that preloads the end of the file first (where UDF keeps an anchor), then the start. It reads the whole UDF/BDMV tree through one cached block reader. Ours reads sector by sector through HTTP range requests (256 KB first window), each one going over SMB (§3).
14. **ISO title choice: add libbluray's tie-breaks to longest-first.** Infuse uses libbluray (relevant titles only, then `bd_get_main_title`), which compares chapter count, video properties and audio properties and prefers known playlists. Ours takes the longest playlist after filtering decoys (`BDTitleSelector.swift`). Keep the decoy filter; add the tie-breaks for discs with several long playlists.
15. **ISO "playback still fails": get a trace first.** No failure was reproduced here (read-only task). Record the disc-open trace on DevTV/DevPlus with the failing ISO before changing the reader. Add Infuse's crash guard ("item seems to be crashing, won't open it"): one bad disc shouldn't crash-loop the app.

---

## 1. Apple TV app hero (media showcase)

Code: `PaginatedMediaController` (Swift, VideosUI) drives paging. `VUIBackgroundMediaController` (ObjC) plays the still or video
on each page. `VUIMediaShowcasingConfig` holds the defaults; `-[VUIFeaturesConfiguration _populateMediaShowcaseConfig:]`
overwrites them from the server dictionary, key by key.

### 1.1 Defaults: `-[VUIMediaShowcasingConfig init]` @ `0x2A1CD1060`
Field names come from each getter's ivar offset (e.g. `playbackDelayInterval` reads +0x40). Values are written in `init`.

| Field | Default | Note |
|---|---|---|
| `playbackDelayInterval` (still → video) | **phone 0.5 s · TV 1.0 s · Mac/iPad 2.0 s** | `isPhone ? 0.5 : isTV ? 1.0 : 2.0` |
| `advanceToNextPageDelayDuration` | **1.0 s** | after a video page ends (§1.3) |
| `advanceToNextPageDelayDurationImageOnly` | **5.0 s** | image-only page dwell |
| `isAutoAdvanceToNextPageEnabled` | **on** | also `carouselBehaviorEnabled` on, `isParallaxEnabled` on |
| `autoSwipeAnimationDuration` | **TV 1.0 s** · Mac 0.4 s · others 0.75 s | the automatic page slide |
| `swipingEndAnimationDuration` | 0.3 s | after a manual swipe |
| `animationTransitionDuration` / `backgroundMediaTransferAnimationDuration` | 0.75 s / 0.75 s | |
| `backgroundMediaFullscreenTransitionDuration` | 0.25 s | hero video → full screen |
| `volumeTransitionAnimationDuration`, `numberOfVolumeIncrements` | 2.0 s, 5 | audio ramps, never jumps |
| `metadataFadeOutSpeed` / `metadataFadeInSpeed` | 1.5 / 1.5 | title and metadata fade separately from the art |
| `titleViewTransitionDistance` / `navigationBarTransitionDistance` | 100 / 40 pt | scroll-driven fade distances |
| `parallaxRatio` / `mirrorSlideParallaxRatio` | 0.5 / 0.7 | |
| `visibleVideoHeightPercentage` | 0.5 | |
| `swipeCompletionSpeedFactor` | 0.5 | |
| `itemHoverDelayDuration` / `focusDebounceThreshold` | 0.2 s / 0.1 s | |
| `hideMuteButtonDelayDuration` / `hidePageIndicatorsDelayDuration` | **5 s / 5 s** | controls auto-hide |
| `quoteTimerDuration` | 4 s | |
| `preloadImageBatchSize` | 20 | |
| background/foreground volume | −1 (unset) | |

### 1.2 Still → trailer start (`VUIBackgroundMediaController`)
- **Delay.** `-_computedPlaybackDelayInterval` (`0x2A1D37370`) uses the media info's `playbackDelayInterval` (from the table: TV 1.0 s), falls back to the controller's `playbackStartDelay`, and lets a debug default win when it is above 0. The `playbackStartDelay` default is **5.0 s** (`-initWithName:`). **−1 means never autostart.**
- **Load time counts against the delay.** `-_showPlaybackIfPossible` logs `timeTakenToLoad … playbackDelayInterval`. If the delay is 0 or loading took at least as long, it starts at once (`fcmp d9,d8; b.mi`); otherwise it waits `delay − timeTaken` (`fsub d8,d8,d9` @ `0x2A1D3711C`). So a slow trailer never adds a second wait on top.
- **Crossfade still → video 0.5 s.** `_imageVideoTransitionAnimationDuration` = 0.5. Image changes take 0.75 s, the image→image transition 0.5 s, and `showImageView:…` uses a 0.3 s transition.
- **Other `-initWithName:` defaults:** `_muted` NO; `_mutePlaybackInBackground` YES; `_shouldPauseAtEnd` NO; `_shouldShowImageAndStopAfterPausingAtEnd` NO; `_stopPlayerWhenViewDisappears` YES; `_stopWhenAnotherMediaControllerStarts` YES; `_exitsFullscreenWhenPlaybackEnds` YES; `_playbackStopDelay` 0.5 s; `_clearPreviousImageBeforeLoading` YES; `_prefetchesVideoFrame` NO (set per screen).
- **Same-image updates.** If new media info carries the same image and that image has been up less than **5 s**, an `imageDelayTimer` holds the swap until 5 s after the image appeared (`_registerStateMachineHandlers` block 6, `fmov d0,#5.0; fsub` @ `0x2A1D3CE60`).
- **Paused preview.** It is torn down after **480 s** (`pauseStateTimeoutTimer`, block 12, `0x407e…` @ `0x2A1D41688`).
- **Prefetch.** Log strings show a prefetch player for the next video: "Created prefetch player", "loading playback with prefetch player", "Not prefetching player because external playback is not none", "Not prefetching next video because prefetchesVideoFrame is NO". `MediaInfoFetch` prewarms playback when preload is on.
- **Automatic playback is gated by the system switch:** "accessibility video autoplay is disabled", plus a cellular check: "is playback disabled by defaults %d. is on cellular but not allowed".

### 1.3 Paging state machine (`PaginatedMediaController`)
- **No timer while video plays.** `updateAutoAdvanceTimer` invalidates the old timer and logs "updateAutoAdvanceTimer when video is playing. Ignore" (`0x2A21D3A98`).
- **Image-only dwell** (`0x2A21D3C6C`): `advanceToNextPageDelayDurationImageOnly` (5 s) when the page-state byte is ≤ 1, otherwise a hard **10 s**.
- **Video-page delay** (`0x2A21D3BFC`): `advanceToNextPageDelayDuration` (1 s) when state & 0x3; **0 s** when state & 0x18; otherwise a hard **2.0 s**. The enum case names are stripped, so which state is which is not established.
- **End of video** (handler around `0x2A21DF918`): skipped in full screen. It stops the player unless `shouldShowImageAndStopAfterPausingAtEnd`/`prefetchesVideoFrame` say otherwise, then (if auto-advance is allowed) schedules the 1 s timer. So a video page plays its **whole preview clip to the end**; no fixed play length was found. Apple's clips are server-cut previews (`previewHlsUrl`, `trailersPlaylist`). "Ambient" videos loop `repeatLoopCount` times.
- **`shouldEnableAutoAdvance`** (log @ `0x2A2889150`) is true only when all of these hold: `isAutoAdvanceEnabled`, not `isAutoAdvanceDisabledByAx` (accessibility), not `forceDisableAutoAdvance`, `autoAdvanceEnabledByConfig`, not `isMainVideoPlaybackPlaying` (full-screen playback), not `isViewOffScreen`, not `isPostPlay`, not `suppressStageAutoAdvanceInBackground`. **Focus is not one of these inputs.** Whether tvOS focus or interaction changes `isAutoAdvanceEnabled` was not recovered.
- **Manual swipe:** "didSwipeToPage", "Swipe animation is running, ignore page control event", `nextPageChangeIsAutomatic`; the timer is re-armed afterwards.

### 1.4 Sound
- **Showcase mute button.** `TV.Button.Mute` / `TV.Button.Unmute`; "MediaShowcaseViewController:: Toggle mute button".
- **Starting state comes from config.** `-[VUIFeaturesConfiguration _updateTVSettingsIfNeeded:]` writes server `autoPlayVideoSound` into the `AutoPlayBgVideoSound` default *unless* `AutoPlayBgVideoSoundUserHasChanged` is set. The user's own choice is sticky.
- **Mute reasons:** InitialSetting, Assigned, Backgrounded, Foregrounded, Fullscreen (`VUIBackgroundMediaControllerPlaybackMuteReason*`). Volume changes ramp (`rampToVolume:withDuration:`).

### 1.5 Failure and slow loads
- Playback errors go through `-_playbackErrorDidOccur:`, and the still remains. "cleanup everything playback related in defensive case" and "playback is enabled and we have a stale player, perform cleanup and start reloading" show it reloads rather than hanging.
- A slow load eats into the start delay (§1.2) instead of adding to it. Which advance branch a failed video page takes is not established.

### 1.6 Last page
`autoAdvance` (`0x2A21E056C…`) computes `next = mediaInfoIndex + 1`. If `next == pageCount` and the `shouldAutoAdvanceLastPage` ivar is false, it logs "skip since it's the last page & shouldAutoAdvanceLastPage is OFF" and stops. Both `PaginatedMediaController` inits store **0** to that ivar (`0x2A21D4FAC`, `0x2A21D54DC`). The selector exists, so a server or screen can switch it on; whether Apple's Home does was not recovered. **OpenStream's last-page stop matches Apple's default; the owner prefers build 15's wrap.**

## 2. Apple TV app title (product) page
- **Where it plays.** The header is `CanonicalBannerViewCell` with its own `VUIBackgroundMediaController`: the video plays in the full-width header backdrop, not inline. `configureBackgroundMediaController:viewmodel` (`0x2A22850D0`) reads `playbackDelayInterval` (same table: TV 1.0 s). `…:supplementaryData` (`0x2A228531C`) sets `setClearPreviousImageBeforeLoading:`, `setShowsSecondaryVideoView:`, `setAllowsPictureInPicture:`, `setAutomaticPlaybackStart:` and `setShouldDelayLoadingImage:`. It sets a background colour, then "backgroundMediaController setMediaInfo".
- **Autoplay.** Yes, after the delay, unless the server sends `disableTrailerAutoPlay`, the screen's `isVideoAutoPlayDisabled` is set ("Ignore setting isPlaybackEnabled since isVideoAutoPlayDisabled = true"), or the system autoplay switch is off.
- **End.** Controller defaults (`shouldPauseAtEnd` NO, `SwapBehaviorShowImageAndStop`) return the **still** at the end: "showing image and then will stop playback". No loop for trailers.
- **Explicit trailer.** `TV.MediaShowcase.PlayTrailer` and `beginTrailerPlayback: %{bool}d, shouldDismissOncePlaybackEnds: %{bool}d` open the full-screen player, which closes itself at the end. Post-play has `TV.PostPlay.WatchTrailer`.
- **Chrome and sound.** A mute button that hides after 5 s (`hideMuteButtonDelayDuration`). The embedded player has optional play/pause, mute and full-screen controls (`VUIBackgroundPlayerViewController … needsControl`). It stops when the view disappears or another player starts. Full-screen playback disables it and resumes it afterwards ("fullscreenPlayback did end, enable playback").
- **Not recovered:** exact header geometry, button order, and whether tvOS shows the mute button on the product page.

## 3. Infuse: Blu-ray ISO / BDMV over SMB
Target: `Infuse-arm64` (8.5.6) plus thinned slices of its `libbluray` 1.3.2, `libudfread` and `StratospherixLibSMB` (`/tmp/rea3/thin` on the mini).
- **Pipeline** (class names from ObjC metadata; call sites from `bl` to import stubs):
  - `FCUDFImage -open` (`0x1000E3864`) calls `udfread_init` and `udfread_open_input` with its own `udfread_block_input {close, read, size}`. The ISO is read as blocks through Infuse's own network stream, not a mounted file. `FCUDFInputStream` reads files inside the image (`udfread_file_read` @ `0x10004FCB4`).
  - `FCBlurayFSHandler` registers libbluray dir and file hooks (`bd_register_dir` @ `0x100264DBC`, `bd_register_file`), so libbluray opens `BDMV/...` through the UDF reader.
  - `FCBlurayHandle +openHandleWithVFSItem:streamBuilder:` calls `bd_open(path, NULL)` (`0x1002BA054`; no key file).
  - `-[FCBlurayMovie openWithStreamBuilder:]` (`0x100059B04`) calls `bd_get_titles(bd, 3 = TITLES_RELEVANT, 0)` (`0x100059C28`), i.e. duplicate titles and clips filtered, no minimum length. It then runs `parseTitlesInfo:`, which calls `bd_get_title_info` **for every relevant title** (streams, clips, chapters on a 90 kHz clock, `0x40F5F9…` = 90000.0) and checks `isCancelled` between titles. Next come `mainTitleIndex` (`bd_get_main_title` @ `0x10005A830`), `setActiveTitleIndex`, `durationForTitleIndex:allTitles:` and `bd_select_title` (`0x100059D1C`).
  - Playback: `FCBlurayDemuxingIO` (`bd_read` @ `0x1000A14E8`) feeds FFmpeg through `FCBlurayDemuxingStream`. `FCBlurayTimestampGapsHandler` repairs timestamp jumps between clips ("ts diff is big … Will use previous correction"). `DurationProviderBluray` and `FCDvdBlurayInputStreamsMaker` also exist.
- **Main-title rule:** libbluray's guess, shown by REA/Ghidra on `libbluray-arm64` (Evidence `ev_cc5690939d57fec98de83a08cbc28a32a1db77e53fc67cd324b525aec8666724`):
  - strings "main title (%s,%s): chapter count difference", "… video properties difference", "… audio properties difference", and `prefer "known" playlist`;
  - it reads `BDMV/PLAYLIST` and falls back to `BDMV/BACKUP/PLAYLIST`.
- **Read-ahead.**
  - Network inputs are wrapped by `ReadAheadInputStream` and `ReadAheadLoader` (Swift; path `…/CachingStream/InputStream/ReadAheadLoader.swift`).
  - Strategies are `LimitedPreloadStrategy` and `UnlimitedPreloadStrategy`, with fields `minPreloadBytesLength`, `maxPreloadBytesPercent`, `maxPreloadTimeLength`, `preloadTriggerFraction`, `preloadTolerance` and `alsoPrefetchToMemory`.
  - Logs: "Preload near the end of file was finished, will also schedule preload from the beginning", "Timeout when waiting for …", "No free memory to preload", "Read:[perf:".
  - The numeric values were not traced.
- **Robustness.** "Bluray item seems to be crashing, won't open it" (a crash guard). Error logs: "[Bluray] No appropriate titles", "Failed to open handle", "Failed or cancelled fetching of children".
- **Not found:** progress UI for disc open, timeout values, and how often blocks are re-read.
- **Ours, for comparison** (AetherEngine `07afad62`, pinned):
  - `UDFReader` reads 2048-byte sectors one at a time through `HTTPDiscIOReader`. That reader starts at a 256 KB window, doubles up to 8 MB on sequential reads, uses a 30 s request timeout, and goes through the app's SMB-to-HTTP range server.
  - `BDTitleSelector` drops playlists under 10 s and repeated-clip decoys, then picks the longest.
  - `DiscRecognitionCache` exists.
  - Each scattered metadata read near the start of the disc is a separate range request over SMB. Infuse's end-then-start preload turns these into a couple of large reads.

## 4. OpenStream now vs build 15 (ad66774)
Read-only git comparison of ad66774 → 72966f9. Paths are under `Sources/OpenStreamApple/`.

**Build 15, title page** (iPhone/iPad/Vision Pro; never on tvOS, `titlePageAutoplays(.tv)` = false):
- **Picture:** a full-bleed tall header with the approved fade on iPhone. A WKWebView YouTube embed (nocookie) with `mute=1 autoplay=1 playsinline=1 controls=0 modestbranding=1 showinfo=0 rel=0 fs=0`, and CSS that **hid all of YouTube's overlay**.
- **Timing:** starts 2 s after the art. The reveal was capped at 3.2 s landscape / 0.9 s portrait, then a picture-settle step that never saw the video on a real device. The art stayed up about 8 s while the trailer played hidden, so the reveal came about 8.5 s in, past studio logos and title cards (commit 9760a49 confirms this from a trace). Crossfade 0.6 s.
- **End:** 60 s cap, back to the art with a replay control; on failure, the next trailer.

**Build 15, Home hero:** 12 s pages; trailers 2 s after art, muted; held while a trailer played; **wrapped last → first**. tvOS: held on focus, wrapped, no trailer.

**Changes since build 15** (affects: **T** = title page, **H** = hero):

| Commit | Date | Change | Affects |
|---|---|---|---|
| 7d2850f | 10-03 | Own web view per trailer; title-page 15 s startup timeout; error 150 → art | T |
| 9760a49 | 10-04 | Device skips the 8 s settle; trailer shown uncropped as soon as it plays (reveal about 0.5 s, not about 8.5 s) | T, **worse** |
| c0637f8 | 10-08 | Trailer held by key; 60 s cap ignores durations under 10 s | T |
| 86ece63 | 10-09 | Forced mute plus sound button; first-frames check; crossfade 0.6 → 0.4 s | T |
| 73455c3 | 10-09 | iPhone home hero: still image, no trailer (undone by ef4a4d3) | H |
| 13a2677 | 10-09 | iPhone title page becomes a 16:9 box under the status bar; no fade or crop | T, **worse** |
| d70aea9 | 10-10 | YouTube title strip, logo and "More videos" left visible; `modestbranding`/`showinfo` dropped; `start=` param | T, H, **worst** |
| 0840e92 | 10-12 | tvOS page timer waits for the next page's art | H |
| f82ef99 | 10-13 | **Hero stops on the last page**; holds under Reduce Motion or when less than half visible; Low Power or the system switch blocks trailers, even pressed ones | H, T, **"cycle gone"** |
| ef4a4d3 | 10-14 | iPhone hero full-bleed again with muted trailers; advances 1 s after a trailer ends | H |
| 98d4efb | 10-15 | Cover image rendered off the main thread after the 2 s delay | T |
| f299aff | 10-16 | Play pauses the trailer; no trailer under a loading Play | T |
| e63f693 | 10-16 | Art stays up until 4.5 s of trailer has played (12 s cap), to hide YouTube's start-up strip | T |

**What made title trailers "worse":**
1. **d70aea9.** YouTube's overlay is visible, and it can come back after the 4.5 s hidden start.
2. **13a2677.** A small boxed header instead of a full-bleed one.
3. **9760a49 → e63f693.** The hidden start went from about 8.5 s (an accident in build 15 that skipped logos) to 0.5 s, then 4.5 s.
4. **Minor.** The 15 s timeout gives up on slow starts; pressed trailers are blocked by Low Power; the crossfade is shorter.

**What can stop the hero cycle at HEAD:**
- the last-page stop (always, after at most 4 advances);
- a stalled Home trailer with no timeout (`AppleHomeBillboard.swift:749`, cleared only by ended/paused/error);
- the page gate waiting on art that never reports (`AppleHeroPageGate.swift:106`);
- Reduce Motion;
- tvOS focus on the hero buttons (`AppleTVHeroPaging.swift:68`);
- unverified: less than half visible (`AppleHeroVisibility.swift:56`), and page-list changes resetting to page 0 (`AppleHomeHeroCarousel.swift:113`).

## Evidence and method
- **Apple.** `dyld_info -arch arm64e -disassemble` on the live `VideosUI` (UUID CBD252C1-A639-3C95-8A06-92EAE6228089) gave a 2.97 M-line listing. Objective-C calls go through shared-cache stub islands, so a small resolver read each stub's `adrp/add` selector address from the shared-cache files (`/tmp/rea3-selres.py` on the mini): 7,874 stubs, kept in `/tmp/rea3/stubmap.txt`. Ivar names come from the `_OBJC_IVAR_$_` symbols of the extracted image in `targets/dsc-macos27.0.1-arm64e` and from getter offsets. Addresses above are unslid shared-cache virtual addresses.
- **Infuse.** `llvm-objdump` plus `otool -Iv` (import stubs) and `otool -oV` (class to method addresses). libbluray strings came through the REA MCP (Ghidra 12.1.4) on a thinned slice. Ghidra was not run on the 22 MB VideosUI or the 81 MB Infuse binary: the earlier report hit the 600 s limit on Infuse, and another OpenStream job held the build lock with load around 11.
- **Limits.** Swift enum case names in `PaginatedMediaController` are stripped, so the per-state meaning of the 2 s / 0 s / 10 s branches is not established. Server config can override every default. No runtime capture was made. This report is the only file written in the tree; scratch is in `/tmp/rea3*` on the mini.
