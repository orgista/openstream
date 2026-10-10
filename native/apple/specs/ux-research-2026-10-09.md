# OpenStream iOS UX research — Live, player, heroes, cast, PiP, errors

Date: 2026-10-09. Target: iPhone 15 Pro Max, iOS 18.7, portrait. Owner reference: Paramount+ Live (liked most), DirecTV (somewhat).

Evidence: current App Store iPhone screenshots (fetched 2026-10-09; Paramount+ set is labelled `SEP2026`), Apple docs/HIG, WWDC sessions, TMDB docs, Jellyfin client sources, press coverage. Where I state in-app behaviour that the screenshots don't show, it's marked *(observed; verify on device)*.

---

## 1. Live TV on iPhone, portrait

**Paramount+ Live** ([App Store](https://apps.apple.com/us/app/paramount/id530168168)). Player is a 16:9 strip pinned to the top, **edge-to-edge, no nav bar or title above it**; the status bar sits over the video. Overlay on the video only: channel logo top-left, four glyph buttons top-right (Cast, AirPlay, captions, fullscreen). Directly under the player: a single row of **underlined text tabs** (All · News · Sports · Drama · Kids & Family), not pill chips. Then an **"on now" list**, one row per channel: channel logo in a fixed ~56 pt column, programme title, and on the playing row a small red **"WATCHING"** pill; a trailing schedule glyph per row opens that channel's upcoming programmes. No time grid, no poster thumbnails, generous row height (~64 pt), hairline separators. The tab bar (Home · Search · Clips · Live TV · Profile) stays visible. Why it reads "clean": one image on screen (the video), everything else is type and logos on near-black.

**YouTube TV** ([App Store](https://apps.apple.com/us/app/id1193350206); redesign Jan 2023 per [TechCrunch](https://techcrunch.com/2023/01/18/youtube-tv-upgrades-its-live-tv-guide-and-library/)). Bottom tabs Home · Live · Library. Live tab: top bar with logo, Cast, Search, ⋯; a **"Sort ▾"** menu (favourites / A–Z / most watched) plus the current time at the left of a sticky header. Rows: square tile with the **circular channel logo** on the left, card on the right with title and "9:00–10:00AM · 12 min left". Tapping a row **expands it in place** to a 16:9 thumbnail with a red progress bar, episode line, description, "Add to library". Video plays fullscreen or in a mini player, not docked at the top. PiP since March 2022, live and on-demand ([TechCrunch](https://techcrunch.com/2022/03/31/youtube-tv-finally-adds-picture-in-picture-support-on-ios-youtube-support-expected-in-coming-months)).

**Hulu + Live TV** ([App Store](https://apps.apple.com/us/app/id376510438); guide history [TechCrunch 2018](https://techcrunch.com/2018/05/16/hulus-mobile-and-web-apps-get-the-new-live-tv-guide-better-recommendations-and-more/)). Player at the top with rounded corners; under it a now-playing row (circular channel logo, "8:00 – 9:30PM", title, ⋯) and a trailing **"FILTER: SPORTS ▾"** menu. Below: a section pill ("SPORTS ON NOW") and a time header, then rows. Hulu also exposes outlined chips (Local · Sports · News · Movies) elsewhere in Live.

**DirecTV** ([App Store](https://apps.apple.com/us/app/directv-stream-tv-on-demand/id1136238277)). Tabs Home · Guide · My Library · On Demand · Sports. Home uses 16:9 cards with a red **LIVE** badge and "Show · S11 E20" subtitle; Guide is a classic time grid; Sports Central has "Live & Upcoming" and circular team logos. Press calls it "an excellent grid guide" ([TechHive](https://cordcutterweekly.substack.com/p/hidden-streaming-remote-tricks)).

**Fubo** ([App Store](https://apps.apple.com/us/app/id905401434)). Guide tab: title, Search/Cast/Profile; pill chips (All · Favorites · Trending Channels · Entertainment…); sticky time header ("Today · 2:00pm · 2:30pm"); **time grid** with channel-logo tiles (star = favourite) and an orange now-line. Tabs Home · Sports · Guide · My Stuff.

**Sling** ([App Store](https://apps.apple.com/us/app/id945077360)). Tabs Home · Guide · DVR · On Demand · Search; blue LIVE badge on cards. In fullscreen a swipe up shows a thin **mini guide** strip along the bottom to flip channels without leaving the stream; the newer version was criticised for burying it ([Tom's Guide](https://www.tomsguide.com/opinion/the-new-sling-tv-update-is-so-bad-i-want-to-cancel-my-subscription)).

**Peacock** ([App Store](https://apps.apple.com/us/app/id1508186374)). Top segmented nav (Movies · TV Shows · Sports · More ▾), live channels under a "Channels" tab in the bottom bar; reviewers call that page's navigation "wonky" ([Tom's Guide](https://www.tomsguide.com/reviews/peacock)).

**Pluto TV** ([App Store](https://apps.apple.com/us/app/pluto-tv-stream-movies-shows/id751712884)). Tabs Home · Live TV · Search · Sign In. Live TV is the long EPG grid grouped by category; the live player in the screenshot is portrait fullscreen with only ⟲15 · pause · ⟳15 centred.

**Apple TV app** ([App Store](https://apps.apple.com/us/app/id1174078549)). Tabs Home · Apple TV · Store · Library · Search. No channel guide; live sport appears as cards with team crests, start time and a "Matches ›" row; live scores in Up Next ([Apple Support](https://support.apple.com/en-sg/guide/tvapp/atvb2c74ee59/web)). Playback is the system player.

**Pay-per-view / events.** Nobody puts PPV in the guide. Paramount+ puts UFC under a "Sports ▾" hub with a "Live & Upcoming" rail of 16:9 cards carrying date/time badges; DirecTV/Fubo/Sling do it under a Sports tab. **Search** is a tab-bar item in every app (`magnifyingglass`); YouTube TV also puts it in the Live top bar.

**Recommendation for OpenStream (iOS 18, portrait):** copy Paramount+ exactly. Player = 16:9, full width, flush with the top safe area, no nav bar; only four glyphs over the video (`airplayvideo`, `captions.bubble`, `pip.enter`, `arrow.up.left.and.arrow.down.right`). Under it: underlined text category tabs (All + your groups), then an "on now" list (logo column 56 pt, title, `WATCHING` pill in red on the current row, trailing `list.bullet.rectangle` for the channel's schedule). No posters, no time grid in portrait; offer the grid as a secondary "Guide" sheet like Fubo. Keep the tab bar visible. Sort menu (`arrow.up.arrow.down`) like YouTube TV for Favourites / A–Z / Recent. PPV/events go on a Sports/Events hub, not in the guide.

## 2. Fullscreen live player controls

- **System player.** `AVPlayerViewController` already draws the red **LIVE** pill and switches the scrubber to the DVR window from `seekableTimeRanges`; `requiresLinearPlayback`, `isSkipForward/BackwardEnabled`, `speeds`, PiP (`allowsPictureInPicturePlayback`, `canStartPictureInPictureAutomaticallyFromInline`, iOS 14.2+), `contentOverlayView`, `entersFullScreenWhenPlaybackBegins` are all iOS ([AVPlayerViewController docs](https://developer.apple.com/documentation/avkit/avplayerviewcontroller)). The HIG: "Use the system video player… If your app truly requires a custom video player, reference the behavior and interface of the system video player" ([HIG Playing video](https://developer.apple.com/design/human-interface-guidelines/playing-video)). The iOS 16 redesign and speed menu are in [WWDC22 10147](https://developer.apple.com/videos/play/wwdc2022/10147); inline→PiP on swipe-home in [WWDC21 10290](https://developer.apple.com/videos/play/wwdc2021/10290/).
- **Apple TV app** = system look: LIVE pill left of the bar, "–1:23:45 behind" style readout, AirPlay/captions/PiP glyphs top-right, `xmark` top-left. **YouTube TV**: a thin red bar with "LIVE" dot at the right end, "Jump to live" when behind, channel surf via up/down list *(observed)*. **Paramount+**: same four glyphs as inline, big centred `gobackward.15`/`pause.fill`/`goforward.15`, no scrubber on live channels (no FF per [user report](https://discussions.apple.com/thread/255427919)).
- **Close/back.** Every custom player uses `xmark` or `chevron.down` top-left; the system player uses `xmark`. Swipe-down-to-dismiss is expected.
- **Channel switcher.** Sling's swipe-up mini guide and `chevron.up.chevron.down` buttons; YouTube TV lists channels in a sheet. None show channel numbers.
- **Audio/subtitles/AirPlay/PiP** sit top-right as glyphs; the speed/quality menu is a `⋯` or `gearshape`.

**Recommendation:** use `AVPlayerViewController` for live and VOD. Set `allowsPictureInPicturePlayback`, `canStartPictureInPictureAutomaticallyFromInline`, `speeds = []` for live, `isSkipForwardEnabled = false` when at the live edge, and put channel up/down in `contentOverlayView` as two 44 pt `chevron.up`/`chevron.down` buttons on the right edge that auto-hide with the controls. Don't rebuild the LIVE indicator; the system one is the cleanest on iOS 18.

## 3. Portrait heroes on iPhone

Every major app has moved to **portrait key art, not cropped 16:9 backdrops**: Apple TV (full-bleed 2:3 art, gradient to black, "+ Add" and `info.circle` pills, page dots), Netflix (2:3 billboard, Play + My List), Max (2:3, hamburger + page dots), Peacock (2:3, yellow Watch Now), Disney+ (2:3 Indiana Jones art), Plex (2:3 card over blurred colour). Hulu uses a rounded 16:9 card instead of a tall hero, which is the fallback when only landscape art exists.

- **TMDB**: posters are 2:3, backdrops 16:9; "99% of backdrops don't contain a language", so `include_image_language=en,null` returns textless backdrops first and then the best-rated with text ([TMDB image languages](https://developer.themoviedb.org/docs/image-languages)); sizes come from `/configuration` (`poster_sizes` w342/w500/w780, `backdrop_sizes` w780/w1280, `profile_sizes` w185/h632). Logos (`/images` → `logos`) let you do art + logo + gradient.
- **Cropping**: Vision `VNGenerateAttentionBasedSaliencyImageRequest` (iOS 13+) returns a heat map plus `salientObjects` bounding boxes ([docs](https://developer.apple.com/documentation/vision/vngenerateattentionbasedsaliencyimagerequest)); centre the crop on the union of those boxes ([tutorial](https://iosdevie.substack.com/p/ios13-vision-saliency)). Faces: `VNDetectFaceRectanglesRequest`, bias the crop to the largest face.
- **Jellyfin clients**: Streamyfin's hero card is `width = window − 72`, `height = min(width × 1.15, 440)`, requests the backdrop at exactly that size, and swaps an episode's 16:9 still for the series poster because it "crops badly in the portrait thumb slot" ([HomeHeroCarousel.tsx](https://github.com/streamyfin/streamyfin/blob/develop/components/home/HomeHeroCarousel.tsx)). Swiftfin puts a **blurred landscape backdrop** behind the poster ([FocusedPosterCinematicBackgroundView.swift](https://github.com/jellyfin/Swiftfin/blob/main/Shared/Components/FocusedPosterCinematicBackgroundView.swift)); jellyfin-web crossfades backdrops with a `backdropImageFadeIn` class ([backdrop.js](https://github.com/jellyfin/jellyfin-web/blob/master/src/components/backdrop/backdrop.js)).

**Recommendation:** hero = full-width, height ≈ 1.25 × width (≈ 540 pt on the 15 Pro Max), image order: TMDB poster (textless, `null` language) → saliency/face-centred crop of the textless backdrop → blurred backdrop + poster. Bottom 40% gets a black gradient; title logo (TMDB `logos`, max 60% width) above a one-line meta row and two pills (`play.fill` Play, `plus` My List). Page dots, not arrows.

## 4. Hero trailer autoplay

- Netflix on phone only autoplays on the title page, not the home billboard, and the toggle lives in profile settings ([Tom's Guide](https://www.tomsguide.com/how-to/how-to-disable-autoplay-previews-on-Netflix)); its vertical Clips feed shows the mute control as a **`speaker.slash.fill` glyph on the right rail**, no circle. Apple TV app autoplays background video muted by default with a separate "Autoplay Video Sound" switch ([Apple Support](https://support.apple.com/en-mk/guide/tvapp/atvb4114b931/web)). Disney+ added video previews to the hero carousel in 2025 ([TechRadar](https://www.techradar.com/streaming/disney-plus/disney-is-giving-its-apps-a-visual-revamp-for-easier-navigation-and-more-personalization-heres-whats-new)).
- **No flash**: keep the still on top and only fade the `AVPlayerLayer` in once `isReadyForDisplay` flips to true (KVO; Apple: "Use this property to determine when to show or animate a player layer into view" — [docs](https://developer.apple.com/documentation/avfoundation/avplayerlayer/isreadyfordisplay)). For YouTube embeds, wait for `onStateChange == PLAYING` **plus ~400 ms** so the branded loading frame is gone, then crossfade 300 ms.

**Recommendation:** start trailers 1.5 s after the hero settles, muted, with a single 32 pt `speaker.slash.fill` / `speaker.wave.2.fill` button bottom-right of the art (no ring). Crossfade still→video on first frame, video→still at the end. Respect Reduce Motion and Low Power Mode (no autoplay). Pause on scroll-away and in the background. No double-circle play glyph: use `play.fill` inside the Play pill only.

## 5. Cast & crew circles

Apple TV app and IMDb use circular headshots; Letterboxd's app lists cast as text tags *(observed)*. TMDB profiles are 2:3 (`w185`, `h632`). Aspect-fill centred on a 2:3 portrait cuts foreheads, because heads sit in the top third.

**Recommendation:** 72 pt circles, `h632` source, `VNDetectFaceRectanglesRequest` once per image (cache the normalised centre); position the crop on the face centre with the circle's vertical centre at 0.4 of the face box. Fallback with no face: top-biased alignment (`contentMode = .top` equivalent, anchor y = 0.25). Placeholder: `person.crop.circle.fill` in secondary grey. Name on one line, role on a second in secondary colour.

## 6. Picture in Picture for live

YouTube TV PiP (live + VOD) starts when you "swipe up from the bottom of the screen" ([TechCrunch 2022](https://techcrunch.com/2022/03/31/youtube-tv-finally-adds-picture-in-picture-support-on-ios-youtube-support-expected-in-coming-months)); Hulu has supported PiP since iOS 9 ([TechCrunch](https://techcrunch.com/?p=1337590)); Apple TV app does it automatically. Mechanism: `canStartPictureInPictureAutomaticallyFromInline` on `AVPlayerViewController` or `AVPictureInPictureController`, only for content that is "the user's primary focus" ([docs](https://developer.apple.com/documentation/avkit/avpictureinpicturecontroller/canstartpictureinpictureautomaticallyfrominline)); the player must be playing and on screen. Live streams need the `.playback` audio session and the audio background mode; the PiP window shows the system LIVE pill and a seek range only if `seekableTimeRanges` is non-trivial. HIG warning: avoid mixing audio when PiP is muted and another source plays.

**Recommendation:** enable auto-PiP on the live player only (not on hero trailers), keep `requiresLinearPlayback = false` so the DVR window is seekable in the PiP window, and restore the player inline when the user taps "return".

## 7. Errors and empty states

Hulu's Oscars failures showed "no content available" and rights messages, which users hated because they didn't say why ([Yahoo](https://www.yahoo.com/news/hulus-first-live-oscars-stream-163846035.html)); a Hulu patent notes stream-limit errors "don't say which devices are active" ([patent](https://patents.justia.com/patent/20210281915)); Netflix's 2011 wording was "you've reached the limit… please stop playing one movie and try again later" ([Consumer Reports](https://www.consumerreports.org/cro/news/2011/09/netflix-now-enforcing-streaming-video-restrictions/index.htm)). Apple TV channels state the limit as a number ("up to 3 simultaneous streams" — [Apple](https://support.apple.com/en-ng/118239)).

**Recommendation:** name the source and the cause, then one action. Centred `wifi.exclamationmark` (unreachable) or `person.2.slash` (stream limit) at 48 pt, title ≤ 5 words, one sentence, one button.
- "Can't reach *HomeRun*" / "OpenStream couldn't connect to 192.168.1.20. Check the server is on and you're on the same network." · **Retry**
- "Too many streams on *Xtream*" / "This source allows 2 streams and both are in use." · **Stop another stream** / **Try again**
- Empty guide: `tv` glyph, "No channels yet", "Add a source to see live TV here." · **Add source**

---

## Top 10 changes, ranked

1. Rebuild Live to the Paramount+ layout: edge-to-edge 16:9 player at the top, no nav bar, underlined category tabs, "on now" list with logo column + `WATCHING` pill; tab bar stays.
2. Drop poster/thumbnail imagery from the Live list in portrait; keep the time grid as a secondary Guide sheet.
3. Use `AVPlayerViewController` for live (system LIVE pill, DVR scrubber, PiP, AirPlay, captions) and remove custom transport chrome.
4. Enable `canStartPictureInPictureAutomaticallyFromInline` on the live player.
5. Hero: portrait key art (TMDB textless poster/logo) at ≈ 1.25 × width with a bottom gradient; never a raw 16:9 crop.
6. Fallback crop by Vision saliency/face centre; last resort blurred backdrop + poster.
7. Trailer autoplay: muted, crossfade on `isReadyForDisplay`/`PLAYING + 400 ms`, single `speaker.slash.fill` glyph, honour Reduce Motion.
8. Cast circles: face-centred crops from `h632` profiles, top-biased fallback.
9. Channel up/down as `chevron.up`/`chevron.down` in the player overlay plus a swipe-up mini list (Sling pattern).
10. Error/empty states that name the source and cause with one action ("Can't reach HomeRun", "Too many streams on Xtream").
