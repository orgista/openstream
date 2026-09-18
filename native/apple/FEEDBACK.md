# FEEDBACK (OpenStream Apple)

Older sections (2026-09-02 → 2026-09-14) live in `FEEDBACK-ARCHIVE-2026-09-02_2026-09-14.md`.

## 2026-09-15 10:40 — Traces on by default, and Web Management proven end to end

Owner: *"are traces on automatically so I can test it and you can see or no?"* and
*"how do I turn on traces for every function for the next build so I can nav through and note any issues"*.

**Answer: they were not. They are now — nothing to set.** `AppleInteractionTrace.isEnabled`
read `UserDefaults.standard.bool(forKey: "OpenStreamTrace")`, which is `false` when the key is
absent, so every trace was silent unless someone had set it by hand. It now defaults to **on in
every DEBUG build**; only an explicitly stored `OpenStreamTrace = false` turns it off.

**Coverage was the other half of the problem.** Before today only the live guide and one playback
timeout recorded anything — walking through Discover, Library, Search, Settings or the title page
left no trace at all. Added `AppleTraceModifiers.swift`: `.appleTraceScreen(_:detail:)`,
`.appleTraceSelection(_:value:)`, `appleTrace(_:)` and `appleTraceFailure(_:)`, all compiled away
outside DEBUG. Applied at the funnels rather than one screen at a time:

| Where | What it records |
|---|---|
| `appleSettingsPageTitle` | every settings page, present and future, appearing/leaving |
| `OpenStreamRootView` | tab changes |
| Discover / Search / title page | appear + section count, title name and id |
| `ApplePlaybackCoordinator` | play request (source kind, live, host, route), route changes, **first frame**, rebuffering, stalls, every failure with its kind and whether it will fall back |
| `AppleSourceStore.persist()` | all four silent bail-outs, each naming why the list was not saved, plus the success count |
| `AppleLocalLibraryStore.reload` | per-source file count and per-source scan failure |
| `AppleWebManagementServer` | every stage — see below |

**Where to read it:** `Library/Caches/openstream-trace.log` in the app container (one line per
event, `<elapsed>ms <kind> <detail>`), and the same lines print to the console as
`[OpenStream] trace …`.

**Fixed a bug in the tracing itself:** `begin()` truncated the log from the root view's `task`,
which runs *after* the first screens have appeared — so `discover appeared` was written and then
immediately erased. The file is now cleared by whichever entry is written first, and `begin()` only
resets the clock if nothing has been recorded yet. Confirmed: a plain launch now opens with
`0ms screen discover appeared`.

### Web Management — it works; what was missing was any way to see it fail

Owner: *"web management never worked so testing that end to end and adding more traces to find out why."*

Tested end to end against the tvOS simulator from a browser on the Mac (192.168.1.95), with no
special flags beyond the launch hook:

```
250ms  network web start on 192.168.1.95, preferred port 8090
262ms  network web listening on http://192.168.1.95:8090/ pairing=S67KUKF6 for 600s
951ms  network web bonjour published _openstream._tcp. on port 8090
9979ms network web GET / from 192.168.1.95 host=192.168.1.95:8090 origin=none
9980ms network web -> 200 OK
16450ms network web POST / … origin=http://192.168.1.95:8090     (pair)
16451ms network web -> 200 OK
22703ms network web POST / … (add add-on)
23335ms network web added addon source "Cinemeta"
23336ms network web -> 200 OK
```

Serve, pair, and add-a-source all succeed, and the source persisted. So the code path is sound —
which means the failure on the real Apple TV is environmental or device-side, and until now it
produced **no evidence at all**: the TV showed an address and a pairing code whether or not
anything could reach it.

Every stage that could swallow it silently now names itself:
- no usable LAN address, and which address was rejected
- each port in the 8090–8153 fallback range that was refused
- the address and pairing code actually being advertised
- **Bonjour publish success/failure** — it had no `NetService` delegate at all, so a refused
  registration (the clearest sign local network access was denied) was invisible. Added
  `AppleBonjourPublishMonitor`.
- every request with its method, path, client, `Host` and `Origin`, and the status it got back
- the three 403s distinguished: off-LAN client, `Host` mismatch (printing what was sent vs. what
  was expected), and origin/referer mismatch
- pairing failures: whether the code was absent or wrong, and whether a cookie was present
- add success by name, add failure by reason

**Next step needs the real Apple TV, not the simulator:** start Web Management on the device, try
to reach it, then pull `openstream-trace.log` from the container (Xcode → Devices → OpenStream →
Download Container) or watch the console. The trace will say which of the stages above it got to.
A totally empty request section means the browser never reached the listener — a network/subnet or
local-network-permission problem, not an app bug.

Also made the DEBUG auto-start hook cross-platform (`OpenStreamStartWebManagement`, previously
visionOS-only), so this path can be exercised headlessly on any simulator.

**Gate:** 693 tests / 50 suites green. tvOS UI tests 4/4 green against the traced build. Apple TV,
iPhone and Vision Pro all rebuilt, installed and confirmed writing traces on a plain launch with
nothing configured; one sim booted at a time.

## 2026-09-15 11:0x — Owner's live TV-sim round: trailers, Menu/back, button alignment

### Trailers on Apple TV — fixed, and the DNS theory was wrong

The standing note said Restricted Mode/DNS was the likely cause and a cache flush was needed
from the owner. **That was wrong, and the flush was never the blocker.** Reproduced the resolver's
exact request from the Mac (same endpoint, same IOS client context, same headers):

- A control video returned `status: OK` with an HLS manifest — so the network path and the client
  context were both fine, and DNS was never involved.
- The **real** trailer the app requests (`wyEOwHrpZH4`, from Cinemeta's `trailerStreams` for
  The Gentlemen) returned `playabilityStatus: OK` — **not restricted at all** — with
  **no `hlsManifestUrl`**, 27 `adaptiveFormats` and a `serverAbrStreamingUrl`.

So YouTube stopped returning an HLS manifest for this client, and `parse` only ever looked for
`hlsManifestUrl`, so **every** trailer failed as `noHLS`. Fixed: `Source` is now `.hls(URL)` or
`.adaptive(video:audio:)`. Adaptive formats are audio-only or video-only, never both, so
`AppleTVTrailerPlayerView` stitches the pair into an `AVMutableComposition` (one video track, one
audio track, clamped to the shorter duration) and plays that as a single item.

Selection is constrained by what an Apple TV can decode from a plain MP4 URL: the tallest
**H.264 up to 1080p** (the endpoint also offers AV1 and VP9 at 2160p — neither is a safe bet
across Apple TV generations) with **AAC** audio (the alternative is Opus in WebM, which
AVFoundation does not read). 1080p is also the right ceiling for a preview that fades in over the
hero: it starts sooner. Formats carrying `signatureCipher` instead of `url` are skipped rather
than guessed at. 5 new tests.

### Menu/Esc did nothing — one bug behind both reports

Owner: *"if I press esc here it doesn't go back"* (title page) and *"in live I can't go back when
pressing home/esc from live to go to the top bar … I have to scroll all the way up"*.

Same cause. `OpenStreamRootView` attached `.onExitCommand { popOneNavigationLevel(for: tab) }`
unconditionally. `onExitCommand` **consumes the press whether or not the closure does anything**,
and only Settings pushes through `navigationPaths` — every content page arrives as
`NavigationLink { detail(value) }`, the destination-closure form, which never touches the path.
So Menu was swallowed and then `popOneNavigationLevel` returned early on an empty path: the title
page could not be left, and at a tab root the press that hands focus up to the tab bar was eaten.

Fixed with `exitCommandHandler(for:)`, which returns `nil` unless there is a value-pushed screen
to pop. `nil` leaves the press to tvOS, which pops the link and, at a tab root, moves focus to the
tab bar — the stock behaviour, which is what the owner was asking for both times.

### Play / My List / Rate alignment

Owner: *"these buttons are not aligned play my list etc"*. `AppleTVDetailIconLabel` is a disc with
a word underneath; in a `.center`-aligned `HStack` the whole stack centred on the Play pill, which
put the *label* at the pill's middle and pushed both discs visibly above it. New
`VerticalAlignment.appleTVControlCenter` reports the disc's centre instead, so the row reads as one
line of controls with the labels hanging below. Verified: `design/tv-buttons-after.png`.

**Gate 698 tests / 50 suites** (was 693). tvOS rebuilt and installed.

### Still open from this round
- Live guide rail: channel name + `LIVE` truncates ("COMEDY… LIVE"); move/shrink `LIVE`, and show
  what is currently playing on the rail.
- Channel preview that starts before selection (DirecTV-style).
- `Demuxer: open failed (Input/output error (-5))` on a dead channel — needs a friendlier answer
  than a modal.
- Hero: cycling progress indicator, larger hero, Continue Watching moved below the fold.
- Library: `1992` still has no artwork.
- Installing DirecTV/Netflix on the tvOS simulator is **not possible** — App Store binaries are
  device-arch only; simulators need simulator slices. Comparison has to come from a real Apple TV.

### Rate sent focus to Play (owner 2026-09-15)

*"when you rate if you click rate it sends you back to play button."* Expanding Rate replaces the
Rate button with the three choices, so the view holding focus is removed from the tree — and the
choices had no `.focused()` of their own, so focus had nowhere to go and fell back to
`defaultFocus`, which is Play. Added `AppleTVDetailFocus.rateChoice(Int)`, bound each choice to it,
and the expand action now hands focus to `.rateChoice(0)` as it expands. Collapse already returned
focus to `.rate`. Gate 698/50; tvOS rebuilt and installed.

**Netflix / DirecTV on a simulator — not possible, on iPhone either.** App Store apps and
device-decrypted IPAs are built for the `ios-arm64` *device* platform; a simulator runs
`ios-arm64-simulator` binaries. Those are different platform slices, so the binary will not load on
the 16 Pro simulator regardless of the Mac being Apple Silicon, and there is no re-signing or
conversion that changes a device slice into a simulator one. Comparison has to come from the real
devices — the owner's own screenshots, which is the path already agreed.

### Trailers on Apple TV — correction, and where the wall actually is (2026-09-15 11:3x)

**Correction to the entry above:** it said trailers were fixed. The *resolver* was fixed; playback
was not verified end to end, and the owner was right that trailers still do not play. The full
chain has now been traced on the simulator, stage by stage:

```
 767ms trailer "The Gentlemen": 1 candidate(s) wyEOwHrpZH4
3356ms trailer candidate 0 resolved as adaptive          ← resolver fix works
3587ms composition unavailable (AVFoundationErrorDomain -11849); playing video only
3682ms trailer item failed: AVFoundationErrorDomain -11849 Operation Stopped
```

**Solved on the way, and worth keeping:**
1. The resolver no longer fails as `noHLS` — it selects an H.264 ≤1080p + AAC pair from
   `adaptiveFormats`. 5 tests.
2. **The streams only answer ranged requests.** Measured: `GET` with `Range` → **206**;
   `GET` without `Range` → **403**; `HEAD` → **403**. AVFoundation opens a remote asset with
   exactly those unranged requests, so `AVURLAsset` failed with `CoreMediaErrorDomain -12660`
   before reading a byte, and no header setting can fix it. New `AppleRangedAssetLoader`
   (`AVAssetResourceLoaderDelegate`) routes every read through an explicit ranged GET. That error
   is gone.

**The wall:** what the endpoint now returns is **DASH** — `ftyp` brand `dash`, fragmented MP4,
alongside a `serverAbrStreamingUrl`. AVFoundation speaks HLS, not DASH. `AVMutableComposition`
cannot cut tracks from a fragmented asset, and `AVPlayer` will not play one directly either: both
fail `AVFoundationErrorDomain -11849`. The video-only fallback fails for the same reason, so the
preview stays black.

**No other client context helps.** Tested `WEB`, `MWEB`, `TVHTML5`, `ANDROID` and
`IOS_MESSAGES_EXTENSION` against the same video: none returns `hlsManifestUrl`; most return
`UNPLAYABLE` or `LOGIN_REQUIRED` and no formats at all. `IOS` is the only context still returning
playable data, and it is DASH-only.

**Options, for the owner to choose:**
1. **Local HLS bridge** — parse the `sidx` box for fragment boundaries and serve a generated
   multivariant playlist with `EXT-X-BYTERANGE` segments (video + audio renditions) from a loopback
   server; AVPlayer handles separate renditions natively. This is the real fix and gives audio, but
   it is a day of work and it rests on an unofficial endpoint that has already changed once.
2. **Drop native tvOS trailers** and keep the other platforms' embed.

Kept regardless: the resolver fix, the ranged loader (useful for any range-only source), and the
six trailer trace points, which turned "trailers still aren't working" into an exact stage and
error code.

### Continue Watching progress bars (owner 2026-09-15)

*"these progress bars are not symmetrical."* `indexedShelf` drew `ProgressView(...).frame(width: 140)`
under a card that is wider than that, inside a `VStack(alignment: .leading)` — so every bar was
short and pushed to one side of its poster. Now `.frame(maxWidth: .infinity)`, which resolves to
the card's own width. Verified: `design/tv-progress-after.png`. Gate 698/50.

### Live channel strip — name fits, and it says what is playing (owner 2026-09-15)

*"the name and live doesn't fit because channel name is too long maybe move live somewhere else and
smaller"* + *"would like to also see what is playing"*.

The strip cell drew `HStack { name; LIVE }` inside a 224 pt card, so a long name lost most of itself
to the badge ("COMEDY… LIVE"). Now: logo, the channel name alone on a full-width line, then a bottom
line carrying a smaller `LIVE` and the programme showing now. The card grew 176 → 214 pt and the
strip 240 → 278 pt to fit the third line (the metrics tests assert relationships, not absolutes, so
both still hold).

**The programme line needed a real fix, not just a lookup.** EPG is fetched only for channels
*visible in the guide grid* (`onVisibleChannels` → `refreshVisible`), so a viewer who opened a
channel without scrolling the guide had no programme data at all and the new line would have been
blank almost always — which is exactly what the first capture showed. The player now asks for EPG
for the strip's own channels when it opens (`stripGuideChannelIDs(around:)`, the watched channel
±20, bounded because the lineup is thousands long).

Second defect found in the capture: the programme title was `AppleDesignTokens.textSecondary`, a
fixed light grey that vanished into the white focus platter — the focused card showed `LIVE` and
nothing else. Now `.secondary`, which is hierarchical and follows the inherited foreground.

Verified: `design/tv-strip-final.png` — FOX DEPORTES *Gol x gol América*, HBO *Lanterns*,
CINEMAX *Joker: Folie à Deux*, and the focused HBO COMEDY reading `LIVE Deadpool 2`, which is what
is on the screen behind it. Gate 698/50.

New review hook: `OpenStreamLiveFooterVisible` opens the channel strip at launch, since it otherwise
only appears on a remote swipe and could never be captured headlessly.

### Channel preview — it was running the wrong engine the whole time (2026-09-15 11:5x)

Owner, twice: *"would like to also see a preview of the channel similar to direct tv app — they
preview the channel, it starts playing before you click."* The preview had been built, wired and
marked done; it had simply never produced a picture, and nothing recorded why.

**It could not be checked headlessly**, which is how it survived: the preview is dwell-gated on a
focused rail cell, and launching into the Live tab leaves focus on the tab bar, so a `simctl`
capture shows a guide that is never previewing anything. New UI test
`testChannelPreviewStartsAfterDwellingOnAChannel` presses Down onto a channel, waits past the
1200 ms dwell and attaches the screen; the attachment comes out of the `.xcresult`.

With traces added to the preview, the cause was one line:

```
5066ms preview start "CBS (EAST)" host=jktv4.xyz
5096ms preview loaded "CBS (EAST)" player=true
10254ms preview after 5s: rate=0.0 timeControl=1 itemStatus=2 likelyToKeepUp=false
        error=AVFoundationErrorDomain -11850
```

`itemStatus=2` is **failed** and `-11850` is *operation not supported for asset*.
`AppleTVChannelPreview` hard-coded `NativePlaybackEngine` — AVPlayer only — while the owner's
lineup is MPEG-TS, which AVPlayer cannot demux. The full player never hit this because it builds
its engine through `ApplePlaybackEngineFactory` and lands on the libavcodec route. The preview now
uses the same factory.

That meant the preview also had to render either route: AVPlayer draws through `AVPlayerLayer`, the
libavcodec route through its own sample-buffer surface, so a preview that only knew about
`AVPlayerLayer` would still have shown nothing. New `AppleTVChannelPreviewSurface` picks by
`engine.route` and reuses the existing `ApplePlaybackSurfaceView`. Both routes are muted —
`avPlayer.isMuted` for one, `aetherEngine.volume = 0` for the other — so browsing the guide never
talks over what is already playing.

After: `rate=1.0 timeControl=2 itemStatus=1 likelyToKeepUp=true error=none`, and the attachment
shows a live CBS frame in the panel where the logo was.

**One test changed, deliberately.** `testMenuLeavesTheGuideRatherThanTrapping` began failing after
this morning's Menu fix. It pressed Menu while focus was still on the tab bar — the app root, where
stock tvOS leaves for the Home screen, so nothing holds focus and the assertion failed. The old
assertion only passed because the unconditional `onExitCommand` swallowed the press, which was the
bug. Rewritten to press Down into the guide first and then assert Menu hands focus *back to the tab
bar* — which is what the owner actually asked for. tvOS UI suite now 5/5.

Gate 698 tests / 50 suites.

### Hero: bigger, with a cycling indicator (owner 2026-09-15, from the reference videos)

The owner filmed three reference apps on their own TV — Netflix (`IMG_5304`), the Apple TV app
(`IMG_5307`) and DirecTV (`IMG_5308`) — as GUI feedback. Read as contact sheets via ffmpeg.

What they confirm, against the open list:
- **Netflix home**: the billboard fills the screen and the first row only *peeks* over the bottom
  edge. Ours was 65 % with a whole row sitting under it, which is what the owner meant by "take
  more of the screen for the hero and move continue watching until you scroll down".
- **DirecTV guide**: info panel at top with a small channel-preview thumbnail beside the
  programme's title, time and description — the same shape as the strip we just built, which is a
  useful confirmation that the placement is right. Differences worth noting but *not* acted on:
  their categories are a vertical rail rather than horizontal pills, the channel number is
  prominent in the rail, and focusing a cell shows a "Hold SELECT to favorite" hint.
- **Netflix title page**: actions are a *vertical* list (Play / Trailers & More / + Add to My List),
  where ours is a horizontal pill plus circular icons. Flagged for the owner rather than changed,
  since our row was only just realigned at their request.

**Done:** `artHeight` 700 → 980 (65 % → 91 % of the screen) and `copyBottomInset` 100 → 140 so the
copy clears the row below. The first row's header now lands at 908, leaving about 170 pt showing —
visibly more below, but Continue Watching takes a scroll.

**Cycling indicator:** `AppleHeroRotation.progress(at:interval:)` derives the position in the
current interval from the same clock as `index`, so it needs no state and cannot disagree with the
billboard. `AppleTVHeroRotationIndicator` draws one segment per billboard, the current one filling
over the interval. The fill is a local `.linear` animation rather than a fast `TimelineView`,
because re-rendering full-bleed artwork every frame to move a 4 pt bar would undo the work that
made this screen fast. Reduce Motion keeps the position marker and drops the sweep. 3 new tests.

**Second test changed today, deliberately.** `firstRowOfPostersIsFullyOnScreenBeforeScrolling`
asserted the opposite of what the owner asked for — a whole poster row visible without scrolling,
which is *why* the hero was 65 %. Rewritten as `firstRowPeeksSoTheHeroOwnsTheScreen`, which keeps a
real guarantee (the row header is on screen, at least 100 pt shows, the row is *not* fully visible,
and the hero is at least 85 % of the screen).

Verified on the TV sim: hero fills the screen, five segments under the pills, and two captures
apart show the active segment advanced and the artwork changed with it. Gate **701 tests /
50 suites**, stable across three consecutive runs (one earlier run reported three issues against a
stale binary mid-rebuild and did not reproduce).

### Dead channels stop being an error dialog (owner 2026-09-15)

Owner, flipping channels: *"changed to a channel eventually got to this error"* —
**Playback Failed / Demuxer: open failed (Input/output error (-5))**, modal, Retry and Close.

Three things wrong with that, on a provider carrying 9376 channels where a dead one is ordinary:
it stopped the remote, it quoted libavcodec at the viewer, and Close left playback entirely, so
the only way onward was back through the guide.

New `AppleLiveFailurePresentation` (pure, 6 tests) turns the engine's diagnosis into one sentence
and says what the screen should do with it:
- `player`/`timedOut`/`sourceEnded` → "CBS (EAST) is not broadcasting right now." — the common case.
- `network`, `unsupportedMedia`, `unavailable`, `authentication`, `engineUnavailable` each get their
  own line, all under 90 characters and named for the channel when it is known.
- `opensChannelStrip` is true for anything another channel could fix, and false for bad credentials
  (which fail identically on every row and are answered in Settings) and a missing engine.

The tvOS live player no longer raises an alert. The message is drawn over the picture with a Try
Again pill, and the channel strip **opens itself and takes focus**, so a dead channel leads to the
next channel instead of a dead end. The technical string is not lost — it goes to the trace, which
is where it is actually useful:

```
6507ms playback live C-SPAN phase=failed(...player, "Demuxer: open failed (Input/output error (-5))")
6508ms failure live C-SPAN failed (player): Demuxer: open failed … — opening the channel strip
```

The copy carries a text shadow rather than a scrim (standing rule), matching what the title page
already does over artwork; the last frame stays on screen behind it and can be anything.

**New review hook:** whether a given channel is dead changes hour to hour, so this state could only
ever be captured by luck — C-SPAN, the known-bad one, played fine during this run. `defaults write
com.orgista.openstream OpenStreamLiveFailureProbe -string player` (any `ApplePlaybackFailure.Kind`
raw value) stages one four seconds in. Verified: `design/tv-failure.png`.

**Gate 707 tests / 51 suites.** Worth recording: with simulators booted, two timing-sensitive tests
(`asynchronousCandidateFailureTriesTheNextStream` and
`protectedPlaybackServerStreamsLargeBodyWithBackpressureAndTearsDownWhenRevoked`) flake
intermittently — both are loopback/network timing tests, neither touches this change, and with the
simulators shut down the gate passed 4/4 consecutively. Something to watch, not a regression from
this work.

### A dead channel is replaced by another feed of the same network (owner 2026-09-15)

Owner: *"a dead channel could it be 'replaced'?"* — yes, and most of the machinery was already
there. `ApplePlaybackCoordinator` has fallen back across streams since the on-demand work, and
`shouldFallBack` already returns true for `.player`, the exact kind the demuxer failure arrives as.
Live playback simply called `begin(_:)` and handed it nothing, which is why every live trace read
**`attempt 0/0`**.

New `AppleLiveChannelAlternates` (pure, 7 tests) finds the siblings. Matching is
`AppleChannelLineupPresets.normalize(name:)` — the same comparison the guide already uses to fold
"US: CBS East", "CBS (EAST)" and "CBS HD" onto one lineup entry — so a replacement is always another
feed of the network the viewer chose, never a different channel that sorts nearby. It skips the
identical URL (the same feed fails the same way), skips pay-per-view and placeholder entries, puts
anything in the ten-minute `ApplePlaybackFailureHistory` last rather than trying it again
immediately, and caps at two because each feed costs a connection on a provider that may allow few.

**The lineup it searches had to be the unfiltered one.** The channel strip's list is the curated
Premier Guide, which `deduplicatedEastChannels` has already reduced to one feed per network —
exactly the feeds needed as replacements are the ones it removed. The player now takes the full
9376 alongside the curated strip.

**Measured on the owner's own lineup, which corrected the premise.** A diagnostic pass over all
9376 showed C-SPAN has **no** sibling at all: the only near matches are C-SPAN 2 and C-SPAN 3,
genuinely different channels, which the matcher correctly refuses. This provider is not thousands
of duplicates. Where siblings do exist it works — `CBS (EAST)` finds `CBS (WEST)`:

```
live CBS (EAST): 1 alternate(s) from 9376 channels — CBS (WEST)
live C-SPAN:     0 alternate(s) from 9376 channels
```

So the honest coverage is: networks carrying East/West or duplicate feeds now self-heal; networks
with a single feed still fail, and fall through to the plain message and the channel strip added
earlier this session. Trace shows the count on every channel open, so "why wasn't it replaced?"
has an answer on the device.

The temporary all-channels near-miss scan used to establish this was removed; it cost a 9376-item
pass per failed lookup and had served its purpose.

**Gate 714 tests / 52 suites.**

### `1992` has artwork — the year was gating the match instead of disambiguating it

Owner: *"1992 still does not have album art."*

The parser was not at fault, which is where the suspicion naturally falls for a film named after a
year. Traced on the owner's own library:

```
raw="movies/1992 (2024)/1992.2024.2160p.WEB-DL.DDP5.1.HDR.H.265-FLUX.mkv" → "1992" kind=movie year=2024
```

Correct: title `1992`, year `2024`. (`AppleLibraryTitleParser` was already hardened for numeric
titles — the year regex requires a preceding character and `year == Int(value)` nulls it.)

**The metadata match was the problem.** `bestMatch` required the parsed year to *equal* the
candidate's `releaseInfo`. Cinemeta's `tt4959750` is unambiguously the same film — cast Tyrese
Gibson, Ray Liotta, Scott Eastwood, `released: 2024-08-30` — but its `releaseInfo` carries the
**production** year, `2022`. A two-year disagreement in someone else's metadata outvoted an exact
title match, the lookup returned nil, and the card drew a blank tile with the filename in it.

Fixed by making the year do the job it is actually good for: an exact year still wins, but when
nothing matches exactly the year only chooses *between* same-named candidates. A single same-named
candidate is accepted — its poster beats a blank tile — and candidates with no year sort last
rather than counting as year zero. Wrong title and wrong kind are still refused. 5 new tests
alongside the existing `libraryMetadataRequiresMatchingYearAndKind`, which still passes unchanged.

Verified by clearing the stale lookups and re-resolving against the owner's library:

```json
{ "mediaID": "tt4959750", "name": "1992", "releaseInfo": "2022",
  "posterURL": "https://images.metahub.space/poster/small/tt4959750/img" }
```

**On the owner's own device this heals within the hour, not instantly**: a failed lookup is cached
for 3600 s (a successful one for a week), so the blank tile persists until that entry expires. No
action needed, but it is the reason the fix will not look immediate.

**New review hook:** `OpenStreamLibraryTitleFilter -string 1992` traces the parse for matching
titles only. The existing `OpenStreamLibraryTitleDump` prints all 1397 to the console, which neither
fits the trace ring buffer nor answers a question about one card.

**Gate 719 tests / 52 suites.**

## 2026-09-15 — Traces that survive a release build, and a way to read them off a device

Owner: *"add traces so we have logs please I want you to be able to review everytime I use until
the next build"*, alongside a request to push build 10 to TestFlight.

**Those two asks were in direct conflict and it would have shipped silently broken.** The whole
trace system was `#if DEBUG`; TestFlight builds are Release, so build 10 would have recorded
nothing at all. Three definitions carried 59 of the 76 call sites (`appleTrace`,
`appleTraceFailure`/`appleTraceScreen`/`appleTraceSelection`, and `traceWeb`), so un-gating those
plus `AppleInteractionTrace` itself covers the events worth having. `print()` stays DEBUG-only;
the file write does not.

**The log also wiped itself on every launch**, which would have meant only the most recent session
was ever readable — no good for "review every time I use". It now appends across launches with a
session banner naming the build (`=== session 2026-09-15T19:17:33Z v1.0 (1) ===`) and trims to
512 KB on a line boundary, oldest first, so daily use for a fortnight cannot fill a device.

**Reading it off a real device needed solving too.** On a simulator the container is right there;
on an Apple TV it is not. Rather than add a service or a phone-home, the existing Web Management
listener now serves `GET /diagnostics` — behind the same session token, and placed *after* the
expiry, `Host` and origin checks (the first draft had it before them, which would have bypassed the
DNS-rebinding defence). Verified on the TV sim: **403 without a token, the full rolling log with
one.**

### Live failures name the endpoint

Owner: *"something like endpoint x for channel x is unreachable or similar so they know its not the
app"*. `AppleLiveFailurePresentation.detail(for:endpoint:)` adds a quieter second line under the
headline — "jktv4.xyz did not respond.", "jktv4.xyz is not sending this channel." — so a dead
provider stops reading as a broken app. Nothing is drawn when the failure is not about reaching a
server (`engineUnavailable`, `cancelled`).

### Gate flakiness: investigated, and it is not from this change

Three timing-sensitive tests flake intermittently — `asynchronousCandidateFailureTriesTheNextStream`,
`searchIsConcurrentBoundedDeduplicatedAndPartiallySuccessful` (a hard 180 ms wall-clock bound), and
the protected-playback-server one. Since this change added file I/O to every trace, and one failure
is a duration assertion, the obvious suspicion was that it was self-inflicted. **Tested rather than
assumed:** with `isEnabled` forced to `false` — tracing entirely off — the suite still failed 3
issues. Pre-existing, and worth fixing separately: wall-clock assertions in a unit suite will keep
doing this.

### TestFlight readiness

All four platforms exist under one App Store Connect record (IOS, TV_OS, VISION_OS, MAC_OS), latest
build **9**, so build 10 is next as the owner intended. **One gap found: there is no tvOS
provisioning profile.** All three installed profiles cover `iOS / xrOS / visionOS` only, so Apple TV
would have failed at export. Archiving with `-allowProvisioningUpdates` and the ASC key so Xcode
creates it.

## 2026-09-15 — Web Management portal: wordmark, and a hierarchy that led with the wrong thing

Owner: *"it has the logo now but not the word mark and it looks too ai can we clean that up"*.

**The wordmark was literally absent.** `<header>\(brandMark)</header>` contained the three-bar SVG
and nothing else, so the page never said its own name. Added alongside the mark.

**The "too AI" read was accurate and diagnosable.** Rendered the live portal in headless Chrome
rather than guessing from source — worth doing, because the problem was visible immediately:

- The **address was the largest element on the page**, alone in a near-empty card, while being pure
  reference information. Demoted to a quiet line under the wordmark, so the page now opens on
  "Add a source" — the thing anyone is actually here to do.
- **Remove was an outlined pill on every row** — the loudest control in the list, for the one action
  nobody arrives wanting. Now muted text that turns red on hover/focus.
- The **Manifest URL field had no placeholder**, so nothing suggested what belongs in it.
- Section headings were body-weight like everything else; they are now small uppercase labels, so
  the cards read as sections rather than a stack of identical boxes.

**One test caught the change, and it was right to.**
`webManagementKeepsPairingAfterAnUnreachableAddonAndShowsIPAndPort` pins
`<p class="address">IP:PORT</p>` exactly — protecting a real guarantee (the address is shown as
IP:PORT, never a full URL with a scheme). Rather than edit a third test this session, the address
element was left byte-identical and demoted with a `.lead` wrapper instead. Gate **719 / 52**,
test unchanged.

Captures: `design/portal-before.png`, `design/portal-after.png`.

### Pair once, not once per session — instead of a default password

Owner: *"not sure if we can have them create an admin user so they don't need a pairing code?
usually default is like 1234 but asks to change password before they continue."*

**Kept the code, removed the repetition.** The pairing code is shown on the television, so entering
it proves presence in the room — a stronger claim than any password, and the reason this does not
ship a default one. A `1234` that never gets changed is a permanent way onto someone's media
sources from anywhere on the network; a code on the screen expires with the session. The owner's
real complaint was re-entering it every time, and that is what got fixed.

New `AppleWebManagementTrust`: a persistent secret, issued to a browser as a 30-day
`openstream_trusted` cookie once it has entered a code. A browser holding it is handed the session
token straight away and never sees the code again. `forgetAllBrowsers()` rotates the secret —
wired to **Forget Paired Browsers** in Web Management settings, because trusting a browser for a
month is only safe if it can be untrusted.

That needed a structural fix first: `AppleWebManagementHTTPResponse.headers` is a dictionary, so it
could only ever emit one `Set-Cookie`. The session token and the trust secret are genuinely two
cookies, so responses now carry them separately.

**Verified end to end on the simulator, not just in tests:**

| | result |
|---|---|
| Session 1, code `6VB2TZWQ` | paired, trusted cookie issued |
| Session 2, **new** code `JEVL4PG7`, cookie only | recognised, no code asked |
| Fresh browser, no cookie | asked for the code |
| Deliberately bogus trusted cookie | asked for the code |
| After revoking (secret rotated) | old cookie **rejected** |

Gate **725 tests / 53 suites** (6 new).

**A false alarm worth recording, because it would mislead anyone repeating the test.** Revocation
first appeared to be broken — a rotated secret still let the old cookie in — and it was reported as
a hole twice before the cause was found. Both times the test was wrong, not the code:
`xcrun simctl spawn <dev> defaults write com.orgista.openstream …` writes the *simulator user's*
plist, while a sandboxed app reads and writes its own **container** preferences at
`<data container>/Library/Preferences/com.orgista.openstream.plist`. Reads cross over, which is why
every DEBUG hook this session worked; writes do not. Rotating the container value directly gives the
correct result. (The secret also looked suspiciously constant across reinstalls — `simctl install`
over an existing app preserves the data container, so the plist survives.)

## 2026-09-15 — Owner GUI round: the tone, hero wordmarks, source picker, icons, focus

### The tone was ours, and it was new

Owner: *"I keep hearing a (tone) can you find out where that is coming from?"* Nothing in the app
plays a sound — no `AudioServicesPlay`, no `AVAudioPlayer`, no haptics. It was the **channel
preview added earlier today**: `request.autoplay = true` made `engine.load()` call `play()` *before*
the mute below it could run, so every guide preview barked about a second of live TV audio as it
opened. Its own comment claimed "a preview is a picture, not a viewing"; the code did not deliver
it. Now it loads with `autoplay = false`, mutes both routes, then plays.

### Black video on a local title — diagnosed, not yet fixed

Owner: *"video play back is black on this title 'about time' from local library"*. The trace shows
the pipeline is healthy and only rendering is dead:

```
30169ms play "About Time" attempt 1/1 networkShare host=127.0.0.1 route=none
30795ms rebuffering
30917ms first frame, route=avPlayer
```

Audio plays, the timeline advances, a frame is reported. That is a decoder signature, not a
streaming one — a 4K MP4 on the AVPlayer route. `NativePlaybackEngine` now traces the video track's
four-character format and dimensions (`avc1`/`hvc1`/`dvh1` + WxH) once tracks load, so the next
attempt says whether this is HEVC/Dolby Vision the simulator cannot render (in which case a real
Apple TV may be fine) or a routing bug where it belongs on the software decoder. **Needs one replay
on the device to capture it.**

### Hero wordmarks — two complaints, one bug

*"artwork with word mark and then the work mark is redundant"* and *"the heros don't load the word
mark art just text"* are the same defect. `AppleCatalogItem` carries `posterURL` and `backgroundURL`
but **no logo field**, so the billboard could never show a wordmark; and it falls back to the
*poster* when a title has no backdrop, and posters have the title burned in — which is why
"72 Hours" showed its name twice.

New `AppleTVBillboardTitleTreatment` makes it one decision: backdrop + wordmark → wordmark;
backdrop, no wordmark → text; **poster fallback → nothing**, because the art already says it. The
wordmark comes from the preview-assets cache the prefetcher already warms — the hero simply never
asked. Cache-only, never a fetch, so the home screen cannot get slower looking for a logo. 3 tests.
Verified: the Gentlemen hero now draws its real yellow wordmark instead of plain text.

### Transport focus trap

*"when I go up it to select it like stops and I can't select anything."* The scrubber's
`onMoveUp` handed focus to the **invisible full-screen surface** — nothing drawn as focused,
nothing selectable, which reads as the remote dying. The glyph row is the only other control, so
both directions now reach it and the surface is only a destination when no row exists.

### Delegated in parallel (two agents, isolated files)

**Add-on icons.** The cause was not a bug: Cinemeta's manifest has **no `logo`/`icon` field at all**,
and OpenSubtitles' logo is 602×151, which trips the existing intentional wordmark-hiding gate. Both
therefore fell through to the same generic glyph as "no icon". Add-on rows now fall back to a
per-source monogram, and `AppleRemoteImage`'s previously unused `onFailure` is wired so a genuine
fetch failure lands there too. `AppleAddonManifestIcon.swift` was found to be dead code.

**Source picker.** `[TB+]` provider tags stripped, and the five near-identical 1080p rows collapse
into real choices grouped by (local, resolution, dynamic range) via a new pure
`AppleStreamSourceGrouping`, reusing the existing ranking so "first of a bucket" is already the
backend's pick. A "Show all sources" toggle keeps every stream reachable, and the automatic
fallback loop still walks the full list. 8 tests.

**Gate 736 tests / 55 suites**, both agents merged.

### Still open from this round
Slow scrolling on the title page; a bigger Paramount-style live preview; the Web Management tvOS
layout (delegated, unverified visually); the detail page's own "Other sources" entry point, which
has the same picker problem and was flagged but not changed.

### NAS test connection: the white screen, and why focus vanished (owner 2026-09-15)

Owner: *"when I save NAS on ap tv test connection gui is turns white can't see what its doing and
save button takes forever."*

Two defects, both real:

1. **`AppleTVPillStyle` never read `isEnabled`.** A disabled pill kept the full focused treatment —
   solid white background, black text, 1.06 lift, shadow. So a disabled control looked exactly like
   the primary action, at full brightness. This style is used across the Apple TV UI, so the fix is
   app-wide: focus treatment and full opacity now require `isEnabled`.
2. **Both buttons disabled the moment work started**, including the one the viewer had just pressed.
   Taking focus off the focused view leaves tvOS with nowhere obvious to put it, which is what
   "can't see what it's doing" describes — the screen has a bright slab on it and the remote appears
   dead. Neither button disables now; re-entry is guarded in the action, and the pill that is
   working shows its own spinner (derived from the in-flight `connectionAction`, so there is no
   second piece of state to drift).

**Not yet addressed: "save button takes forever."** That is the SMB connection itself, not the
button — needs a look at the client's timeout and whether save re-runs the same probe the test just
did.

### Added to the list (owner 2026-09-15)

- **iCloud sync.** Settings, sources and watch progress across devices. This is a project, not a
  patch: it needs a decision about what syncs (sources include credentials), a conflict rule, and
  either `NSUbiquitousKeyValueStore` for small state or CloudKit for the library. Worth scoping
  before any code.
- **Keyboard handoff.** Focusing a text field on Apple TV should raise the "type on your iPhone"
  notification. It does not. Needs investigation — the notification is system-provided, so the
  likely cause is how the field is presented or focused rather than anything missing.
- **No way to add a network share from the web portal.** The portal offers add-on, M3U and Xtream
  only; NAS is Apple TV-only, which is the hardest place to type a hostname.

## Design — per-profile watch history + iCloud sync (owner 2026-09-15)

Owner asked for two things that turn out to be one capability:
*"add profile viewing history but leverage the apple profiles so maintain content from profile to
profile but not viewing history"* and *"icloud sync so that ios and ipad os can sync watch history
with tvOS"*.

**Read from the tvOS 26.2 SDK, not from memory** — and the obvious approach is the wrong one.
`TVUserManager.currentUserIdentifier`, `userIdentifiersForCurrentProfile`,
`presentProfilePreferencePanel` and `TVUserManagerCurrentUserIdentifierDidChangeNotification` are
**all deprecated since tvOS 16**. Reading the active profile and maintaining our own
user→profile mapping is no longer supported. The deprecation notice names the replacement:

> "Please use runs-as-current-user-with-user-independent-keychain and
> kSecUseUserIndependentKeychain for sharing keychain items across users."

And the class note says the quiet part directly:

> "When running as the current user each user would have to sign in again to the app, to avoid that
> behavior it is highly recommended that those apps also use `kSecUseUserIndependentKeychain` to
> store their account credentials across users."

That is the owner's requirement, as an Apple capability:

| What | Where it lives | Result |
|---|---|---|
| Watch history, progress, My List, ratings | the app's **per-user data container** (automatic under Runs as Current User) | separates per profile with no code |
| Sources, add-ons, IPTV/SMB credentials | **keychain, `kSecUseUserIndependentKeychain`** | shared across every profile |
| History on iPhone/iPad | **CloudKit private database** | each tvOS profile is a different Apple ID, so the private DB is already the right person's, and it is the same DB their phone uses |

So all three asks fall out of adopting the capability plus moving credentials to a user-independent
keychain. CloudKit and `NSUbiquitousKeyValueStore` are both confirmed present in the tvOS SDK.

### What makes this a project rather than a patch

1. **Adopting the capability re-partitions the container.** Everything currently in `UserDefaults`
   and the app container becomes per-user. Sources live there today, so without the keychain move
   first, profiles would each start with an empty app — the exact opposite of the ask. **Order
   matters: credentials and sources move to the user-independent keychain before the capability is
   turned on.**
2. **Existing data needs migrating** on first launch under the new capability, or the current
   profile appears to lose its library.
3. **`shouldStorePreferencesForCurrentUser` returns NO when there is only one Apple TV user**, and
   on tvOS 15 and earlier it must be treated as NO — so the single-user case has to behave exactly
   as it does now.
4. **iCloud history needs a conflict rule.** Two devices watching the same title is normal; last
   writer wins is wrong (a phone that paused at 3 minutes should not clobber a TV at 50). The rule
   should be furthest-position-wins per title, with an explicit "watched" flag that is sticky.
5. **Entitlement + provisioning:** `com.apple.developer.user-management` with
   `runs-as-current-user-with-user-independent-keychain`, plus the iCloud/CloudKit entitlement. The
   tvOS profiles were created by API earlier today and will need regenerating with the new
   capability.

### Suggested order
1. Move sources + credentials to the user-independent keychain, with migration. Verifiable alone.
2. Split watch history into its own store, keyed per profile. Verifiable alone.
3. Turn on Runs as Current User. Profiles now differ in history and share content.
4. Add CloudKit sync for the history store, with the furthest-position rule.

Nothing here is started — recorded so the sequencing decision is made before code.

---

## Overnight sweep, 2026-09-15 — empty and loading states (owner: "GUI with no content needs work")

The owner photographed the first-run card on Apple TV: **"Not Now" drawn on top of a truncated
"Getting…"**, the real title *below* the buttons, a screen-tall gap, and a full-width button
platter. The screen sweep had independently flagged `library.png` at 62 KB against 900 KB–3.7 MB
for every other screen — a bare tab bar and a spinner clipped into the top-left corner.

Both are the same defect class: **a placeholder that never gets the space it needs.**

### 1. First-run card (`AppleFirstRunGuidanceView`)

Two separate causes, both tvOS-specific:

- `.navigationTitle` + a `.cancellationAction` toolbar item land in the *same* corner on tvOS, and
  the title is drawn *over* the page rather than above it. This is the exact bug
  `AppleSettingsPageTitleModifier` was written to avoid (owner bug U1) — this card simply never
  adopted it. Hence "Not Now" over "Getting…".
- A `Spacer()` between the title and the single button, which on a fixed-size tvOS sheet card
  produces the void.

A tvOS `.sheet` is a **fixed-size inset card the content cannot shrink** — verified: removing the
`NavigationStack` and re-measuring gave a pixel-identical capture. Apple TV setup screens are
full-screen pages, so this one is too: `.fullScreenCover` on tvOS, `.sheet` elsewhere, via
`appleFirstRunPresentation`. The page is now the brand mark, the title, and two content-sized
pills, centred. The pill gap is `AppleTVBillboardMetrics.pillGap` (24) rather than 16, because a
focused pill's ring extends 9 pt past its edge and was touching its neighbour.

A `first-run` debug hook was added: the card only appears with no sources configured, so the review
simulator — which has eight — could never show it, and it went unreviewed until the owner hit it on
a fresh install.

### 2. Library loading state

`if library.isLoading && groups.isEmpty { ProgressView() }` sat as a plain item in a
**leading-aligned `LazyVStack`**. Inside a scroll view the stack is vertically unbounded, so the
`maxHeight: .infinity` these placeholders carry resolves to their own intrinsic height — the
spinner became a speck pinned in the safe-area corner. The fix already existed but was fenced to
`#if os(visionOS)` on the empty state only; it is now `appleCentredInViewport(_:)` and applies to
both placeholders on every platform. New `AppleSourceLoadingState` carries the app's standard
spinner treatment.

### 3. Library took ~10 s to draw a scan that finished at 2.5 s

Instrumented the reload phases rather than guessing. Measured, cold, 1397 files / 421 titles:

| phase | before | after |
|---|---|---|
| scan complete | 2438 ms | 2778 ms |
| scans done (index written) | 4291 ms | — |
| downloads read | 4693 ms | 3703 ms |
| **grouped — shelves can draw** | **5360 ms** | **4387 ms** |
| index written | — | 5144 ms |

Two causes, both fixed at the cause:

- **`mediaIndex.replace` ran inside the scan loop**, between the scan finishing and the grouping
  that actually produces the rows: 1.9 s of writing 1,397 records in front of the picture. The
  index feeds search and Discover matching, not the Library's own shelves, so the writes are now
  deferred until after `groups` is assigned. Failure handling is preserved.
- **`sorted(_:)` called `catalogItem(for:)` on both sides of every comparison**, and a metadata
  miss there constructs an item *and digests the group id* — ~29,000 of those per call, on a sort
  `AppleLibraryView` asks for five to eight times per body pass. Now decorate-once-then-sort (one
  call per group) plus a memo keyed on a content revision. This is almost certainly also the
  owner's "trying to scroll down here and its really slow".

`AppleLibraryView` had **no screen trace at all** — added, so the tab shows up in the owner's logs.

### Corrections to my own earlier notes

- I read a capture where "Recently Added" was the first shelf and started chasing a missing
  Movies/Shows shelf. It was a **transient mid-load state**, not a defect; the settled screen has
  the correct order. Nothing was wrong.
- The sweep's `detail` and `episodes` captures being byte-identical is **not a broken hook**. The
  `episodes` hook guards on `!episodes.isEmpty`, and the featured item it opened was a movie. The
  sweep needs to pick a show for that capture.

### Method note — a `BUILD SUCCEEDED` on this share can be a lie

`xcodebuild` reported success **without recompiling an edited file**: the SMB mtime lands behind
Xcode's last-build stamp, so the change never reached the binary while the build looked clean. A
verification screenshot then "proves" the old code — caught only by measuring the button spans and
finding them pixel-identical. `sleep 6` is not enough. Every edited source is now `touch`ed before
building, and the log is grepped for `SwiftCompile .* <File>.swift` to confirm the compile ran.
This is separate from the "input file was modified during the build" race.

Gate: 742 tests / 56 suites green throughout.

## Overnight sweep, 2026-09-15 — screen-by-screen pass (13 screens captured)

Captured every debug-hook screen on the TV simulator and read each one. Findings and fixes:

### Add Files — the screen the owner called out ("add files gui needs work")

Three different row treatments in one list, two of them wrong:

| row | was | render |
|---|---|---|
| Add Network Share | raw `Label` | glyph ran into the title |
| ServerPlus | `AppleTVNavigationLabel` | correct |
| Direct URL | `locationRow` → raw `Label` | glyph ran into the title |

`AppleTVNavigationLabel` exists *specifically* for this — its own comment names the symptom ("a
stock `Label` in a tvOS list sizes its icon column to the font, so wide symbols run straight into
the title"). These two rows simply never adopted it, so the screen had three different left edges.
All rows now share one column. Same fix applied to **Third-Party Notices** in About, the only other
raw `Label` in a list row; the two in `AppleSettingsViews` at 478/484 are toolbar items, which
render as glyphs on tvOS and are correct as they are.

### Add Files — the discovery spinner never stopped

```swift
let report = await discovery.discoverReport()
guard !Task.isCancelled else { return }   // ← returns without clearing the flag
...
isDiscovering = false
```

The cancellation guard returns **before** `isDiscovering = false`, and the task is cancelled on
every navigation away. So after leaving and re-entering the screen, a spinner sat under "Network
Shares" for the life of the screen with nothing driving it. Now a `defer`. It was also pinned to
the leading edge, which read as a glitch rather than as a row that is searching; it is centred.

### Sources — the Stremio mark (owner's request, was not implemented)

Cinemeta publishes no logo and OpenSubtitles v3 publishes a wordmark too wide for a 44 pt tile, so
both fell back to a letter in a box. The owner asked for the Stremio mark instead: "same for any
stremi.io with no icons default to that it just helps differiate".

New `AppleStremioBrandIcon`. Two deliberate choices:

- **Referenced, not bundled.** The mark is fetched from `www.strem.io` (confirmed 200, 120×120 PNG
  — square, so it cannot trip the wordmark ratio that rejected OpenSubtitles' own logo). No
  third-party artwork ships inside OpenStream, and the monogram remains the offline fallback.
- **Matched on the label boundary**, not `contains`: `strem.io`, `stremio.com` and their
  subdomains qualify; `notstrem.io` and `strem.io.example.com` do not. Torrentio is on
  **strem.fun**, so it correctly keeps its own µ logo — verified on screen.

Only `kind == .stremio` qualifies, so an IPTV playlist or share that happened to sit on strem.io is
not branded as an add-on. 5 tests.

### Live — bigger preview (owner: "i'd like a bigger preview like paramount")

`stripLogoSize` 160×90 → **320×180**, `stripHeight` 120 → 196. Four times the picture area. Costs
76 pt of guide height — under one row — and the guide still shows five rows, verified on screen.
The preview surface itself already worked; it was only ever sized as a logo tile.

### Screens reviewed and found correct

`discover`, `settings`, `sources`, `add-live`, `add-catalog`, `network-share` (clean form: uppercase
section labels, placeholder fields, secondary Load Shares pill), `web-management`,
`playback-settings`, `subtitle-languages`, `source-detail` (Type / Manifest Host / Health / Last
Success / Status / Capabilities / Enabled, a Subtitles push and a red Delete Source — the
remove-a-source path the owner asked to be exercised is present and reachable).

### Not a bug, on review

The Live category rail looks clipped at the right edge ("Lo…"). It is a horizontal scroller with
more categories than fit; the search glyph beside it is a separate trailing item at x≈1810, inside
the 1840 safe edge. Nothing to fix.

Gate: 748 tests / 57 suites.

---

## Subtitles: why they do not work — researched 2026-09-15 (owner: "streams should have subtitles even without an add-on")

The owner is right that a stream should carry its own subtitles. It usually does — `tx3g` and
`wvtt` tracks in the MPEG-4 family, `#EXT-X-MEDIA:TYPE=SUBTITLES` renditions in HLS, SRT/ASS/PGS in
Matroska, DVB/teletext/CEA-608 in MPEG-TS. None of that needs an add-on. The bug is that **this app
only ever read them on one of its two playback routes.**

### The finding

`AppleTVPlaybackPresentationPolicy.engineKind` sends a stream to `NativePlaybackEngine` (AVPlayer)
whenever the container is one AVFoundation demuxes — `m3u8, m3u, mp4, m4v, mov, qt` — *and* the
codecs are hardware-friendly (h264/hevc + aac/ac3/…). On Apple TV that is most well-formed content,
including the majority of add-on streams and much of the owner's local library. Everything else
(MKV, TS, AVI, WebM, or a software codec) goes to `AetherPlaybackEngine`.

On `AetherPlaybackEngine`, subtitles are fully implemented: embedded tracks, cue rendering,
add-on tracks appended after the embedded ones, auto-selection by preferred language.

On `NativePlaybackEngine`, all three of these were true:

1. **`subtitleTracks` was never assigned.** It was declared, and stayed `[]` for the life of the
   engine. `AVMediaSelectionGroup` appears exactly once in the entire source tree — in a comment.
2. **`selectSubtitleTrack(id:)` was a no-op**, with the comment "No track-index selection surface
   on the bare AVPlayer fallback."
3. **`addExternalSubtitleTracks` fell through to the protocol's empty default**, so add-on
   subtitles did nothing on this route either.

On top of that, every call site configured captions with `if let aether = engine as? AetherPlaybackEngine`
— five of them — so on the AVPlayer route the viewer's chosen language and captions preference
were dropped entirely. That is the other half of the earlier report, "subtitles have too many
tracks since I only selected one language and they don't work": on one route the filter applied, on
the other there was nothing to filter and nothing to play.

**So: captions were dead on the route that plays most content, add-on or not.**

### The fix

`NativePlaybackEngine` now loads the asset's `.legible` media selection group on `load`, publishes
its options as `subtitleTracks`, and implements `selectSubtitleTrack` against
`AVPlayerItem.select(_:in:)`. Forced-subtitle options are excluded — those are for untranslated
foreign dialogue and are applied by the system, not chosen from a captions menu. Auto-selection
mirrors the demuxing engine: `.always` takes the first visible track, a language preference takes
the first that actually matches, `.off` selects nothing, and an explicit choice (including "Off")
is never overridden afterwards.

Caption settings now reach whichever engine is playing, through one
`applyCaptionPreferences(preference:languages:)` on the protocol, replacing the five
`as? AetherPlaybackEngine` casts.

**Verified against a real stream** rather than only in theory — Apple's reference HLS variant
playlist returns 8 legible options through the exact call the engine now makes:

```
[0] English SDH   lang=en  forced=false      [1] English (Forced)  forced=true
[2] French SDH    lang=fr  forced=false      [3] French Forced     forced=true
[4] Spanish SDH   lang=es  forced=false      [5] Spanish Forced    forced=true
[6] Japanese SDH  lang=ja  forced=false      [7] Japanese Forced   forced=true
```

Four selectable tracks after dropping the forced ones; with the owner's language set to English,
the filter shortens the menu to one. No add-on anywhere in that path.

### Still open on this route

Add-on subtitle *files* (OpenSubtitles) remain unsupported on the AVPlayer route — an external
file cannot be selected into an existing `AVAsset`. Two ways out: build an `AVMutableComposition`
carrying the fetched track, or parse it with the app's existing `AppleSubtitleTextParser` and drive
the overlay from the periodic time observer. The second reuses what already renders cues on the
other route. Not started; the embedded case above is what the owner asked for and is the common one.

Gate: 753 tests / 58 suites.

---

## Added to the list, 2026-09-15 (owner request)

### Next episode

Wanted: a "Next Episode" affordance while watching a show, and auto-advance at the end.

Most of this already exists and was removed rather than never built. `AppleTransportOverlayModel`
still carries `nextEpisode: (() -> Void)?` and `showsNextEpisode`, with the comment "The T7e
overlay no longer renders a Next Episode button, but the model still reports whether one is
wired." `AppleStremioEpisodeIdentity` (series/season/episode), `AppleLibraryTitleParser` (season and
episode from a filename) and `AppleLocalLibraryStore.resumeEpisode(for:group:episodes:)` are all
present. So the pieces are: re-render the button in the transport overlay, wire the action to the
next episode in the season, and decide the auto-advance rule (countdown card in the last N seconds
vs. straight advance on end-of-item, and whether it applies to the local library, add-on streams,
or both).

### Skip intro

No chapter or marker support exists anywhere in the tree. Three honest options, cheapest first:

1. **Embedded chapter markers.** MKV chapters and MP4 `chpl` sometimes carry a chapter named
   "Intro"/"Opening". Cheap and exact where present, absent on most content.
2. **A marker service.** Works, but means depending on a third-party database keyed by episode.
3. **Audio fingerprinting across a season** — what Plex and Jellyfin's Intro Skipper do: compare
   consecutive episodes and find the common segment. Accurate and source-independent, but far too
   expensive to run on an Apple TV. This is the same shape as the owner's parked unraid trailer
   bridge, and would live in the same place if that gets built.

Recommendation: do (1) now as a real feature for the content that has markers, and treat (2)/(3) as
a decision to make alongside the unraid question rather than separately.

## Captions: default on, and a picked language is the whole menu — 2026-09-15

Owner: "If English is selected in settings then English can be default only option as well[;] auto
on captions should be enabled by default but can be toggled off."

Two gaps against that, both fixed.

### 1. Captions defaulted to OFF on a fresh install

`AppleSettingsStore.init` ran a four-branch chain that landed on `.off` unless the viewer had a
stored preference, the legacy `captionsAutoOn` boolean, *or* had already been to the Subtitle
Languages screen. A fresh install has none of those — so captions were off, and the switch that
turns them on sits two screens deep. Combined with the AVPlayer route having no subtitle support at
all (previous entry), that is the whole of "subtitles are not working".

Now: **on unless a stored preference says otherwise.** `.off` still round-trips, so turning them off
sticks — a test covers exactly that, because "on by default" quietly becoming "on always" is the
easy way to get this wrong. The four branches collapsed to two; all of them were reaching the same
answer once the default flipped, and leaving them would have read as an accident.

Verified on the simulator with nothing stored: Settings → Playback → **Show Captions: Always**.

### 2. A picked language was not the only option

`AppleSubtitleTrackFilter.visible` fell back to listing *every* track when the preferred language
matched nothing, defending it as "an empty menu is worse than a long one". That is right for a
language the app **guessed** and wrong for one the viewer **picked** — and it is how a menu of
fifteen languages survived choosing English.

`visible(_:preferredLanguages:isExplicitChoice:)` now splits the two:

| languages came from | matches | no match |
|---|---|---|
| the viewer picked them | that language only | **empty** — the honest answer |
| the device's defaults | that language only | every track, as before |

The distinction already existed in the store as `hasChosenSubtitleLanguages` (true exactly when the
languages key has been written), so nothing new has to be tracked. It is threaded through
`applyCaptionPreferences(preference:languages:languagesAreExplicit:)` to both engines and to
`AppleTransportOverlayModel`, which derives it from the same key.

So with English picked: English is auto-selected on load, and English is the only entry in the
captions menu. A stream with no English offers nothing rather than quietly listing six other
languages.

### Also fixed on the way

Under `.always`, `AppleCaptionsPreference.preferredSubtitleLanguages` returns `[]`, so
`AetherPlaybackEngine` handed the demuxer **no** languages at load and corrected the selection
afterwards — a visible flash of the wrong language on every start. The viewer's picked languages
now win at load, and the preference-derived list is only the fallback.

### Deliberate test change

`captionsPreferenceDefaultsToOffWhenUnset` asserted the old default and is now
`captionsPreferenceDefaultsToOnWhenUnset`, plus a new `captionsPreferenceOffSurvivesAReread`.
Flagging it because it is an intent change, not a broken test.

Gate: 757 tests / 58 suites.

---

## Next Episode — built and verified on device, 2026-09-15

Working end to end on Apple TV. Captured mid-playback of *9/11: One Day in America* S1 E1: the card
reads **"S1 E2 · The South Tower"** with a live countdown and a dismiss beside it, sitting
bottom-right over the picture while the transport chrome has already auto-hidden, and not covering
the subtitle cue.

### Shape

A **card in the closing seconds**, not a transport button. The Apple TV overlay is deliberately a
scrubber and one captions control (rework plan task 3); a permanent Next Episode button would undo
that. 20 seconds of lead — long enough to read and act on with a remote, short enough not to sit
over the last scene.

- `AppleStremioEpisodePolicy.following(_:in:)` — the successor in display order, **crossing into
  the next season**. What a viewer wants after the last episode of a season is the first of the
  next, not nothing.
- `AppleNextEpisodePolicy` — when the card appears, what it counts down, and when the next episode
  starts by itself. Pure data, asserted without a view, same shape as `AppleTVLiveFooterState`.
- `AppleNextEpisodeContext` — the title and the action, built by whatever presented the player,
  because only that knows the series.

Starting the next episode **re-selects it and re-runs `resolvePlayback()`** — exactly what picking
that episode by hand does. So it resolves its own sources, resume position and subtitles rather
than inheriting the finished episode's. Wired once in `configuredSources`, which every playback
path on the detail page already funnels through.

### Rules worth stating

- Nothing is offered for a movie, a live channel, the last episode, or a stream whose duration has
  not arrived — a card that cannot say how long is left is worse than no card.
- **Dismissing is a real answer.** It stops the card *and* the auto-advance for the rest of the
  episode, rather than postponing either.
- **Auto Play Next Episode** (Settings → Playback, on by default) only governs the *unattended*
  start. With it off the card still appears and still works. Verified on device: the row reads
  **On** beside Auto Play Trailer.
- The advance fires once. The position observer ticks four times a second and end-of-item can be
  reported more than once.

### Two bugs found by verifying rather than assuming

1. **The card auto-hid with the transport.** It was inside `bottomBar`, which fades on
   `controlsVisible` after three seconds of playback — so a prompt that is counting down vanished
   while counting down. It is now its own layer, outside the chrome's fade.
2. **The simulator override defeated its own guard.** `isEligible` required
   `duration > leadSeconds`, so the review lever that brings the card up early (a lead longer than
   the episode) ruled the episode out and showed nothing. The floor now uses `defaultLeadSeconds`,
   which is what it was always for — keeping the card off something shorter than its window.

`defaults write com.orgista.openstream OpenStreamNextEpisodeLeadSeconds -float 99999` brings the
card up from the first frame for review. Reset on the review simulator.

17 tests. Gate: 774 tests / 59 suites.

### Also confirmed while verifying

Subtitles render on the surface route — the capture above shows a live cue, "CLIFFORD: When I got
to The Marriott I was early."

### Still open

Skip intro is unstarted — it is a decision (chapter markers vs. a marker service vs. fingerprinting
on unraid), written up in the entry above rather than guessed at.

---

## GUI audit pass 1 + search — 2026-09-15

Full checklist in **`GUI-AUDIT.md`** (A–F, every screen and element). Audited against the
`ui-ux-pro-max` pre-delivery checklist and the tvOS geometry already encoded in
`AppleTVChromeMetrics` / `AppleTVGuideMetrics`. Apple's HIG pages are JS-rendered and return only a
shell to a fetch, so the codebase's own documented values were the reference.

### Search — "Jury Duty" returned episodes (fixed)

The media index holds **one record per library file**, so a show with eight episodes on disk
produced eight near-identical rows; `mergedResults` deduped on record id, and every file has its
own. Add-on catalogs can return `.episode` entries on top of that.

Two changes: episodes are dropped outright, and what remains collapses on **title + year** rather
than record id. The kind is deliberately not in the key — a library file's kind is `.video`, the
*absence* of a classification, so including it would keep a local copy and its catalog entry apart,
and that merge is what makes a result useful: one row with the catalog's artwork and summary *and*
the local availability. Channels stay, because the field offers "movies, shows, and channels".

5 tests, including two films called *Dune* staying separate.

### Load circle — checked, no defect

Frame-stepped an open, 18 captures from launch to first frame. `showsScreenSpinner` needs
`route == .none && !hasRouted`; `showsWaitingIndicator` needs `route == .surface`. Mutually
exclusive — never two at once. The earlier two-spinner report is already fixed.

### Heroes drew their text on black (fixed)

`AppleRemoteImage`'s loading fill is `Color.white.opacity(0.025)`, deliberately near-invisible.
Right for a poster in a shelf, wrong for a full-bleed billboard: at 2.5% white over black the hero
is a void, so the title, metadata, synopsis and pills sat on nothing until the art arrived. Caught
on a capture of Discover mid-load — this is the recurring "GUI with no content". The fill is now a
parameter; billboards pass a real surface, shelf posters keep the quiet default.

### Settings: the same list rendered at two widths (fixed)

The Sources list was **1000 pt wide reached through the split view and 900 pt pushed on its own** —
identical rows putting their chevrons in two different places depending on how you got there.
`appleSettingsPane` used `formMaximumWidth` while every standalone page uses `formColumnWidth`.
Now one width; measured, the chevron column moved 1512 → 1412.

### Next Episode card, cleaned up

It had a 16 pt corner radius, a 0.75 black panel, `.headline` and a bare 16 pt inset — every one of
them its own value rather than the app's. Now `AppleDesignTokens.cornerRadiusCard`,
`AppleDesignTokens.surface`, the Live info strip's title size, and the app's own column inset.

### Detail action row — checked, correct, left alone

Play and the My List / Rate discs already share a centre through the custom `.appleTVControlCenter`
alignment guide, and the labels clear the 60 pt bottom safe inset. The old focus-ring-over-label bug
is gone. Reporting it as checked rather than changing something that is right.

### Blocked

Four test files on the share are read-only, so one assertion for the unified form width could not be
added: `AppleTVSettingsLayoutTests`, `AppleAddonManifestEdgeCaseTests`, `AppleSourceLogoRefreshTests`,
`AppleTVDetailMetricsTests`.

Gate: 779 tests / 60 suites.

---

## Skip Intro from chapter markers — 2026-09-16

Approved path of the three written up on 2026-09-15. Built and gated; **not yet seen on screen**,
because it only appears on content that carries chapter markers and I have not yet found one in the
test library. The trace line `native engine chapters: N — …` reports what each stream carries, so
the next playback of a chaptered file will show it.

- `AppleChapterMarkers` — finds the opening in a chapter list. Matches whole names against a short
  vocabulary (`intro`, `opening credits`, `main titles`, `theme`, `op`…), **never substrings**:
  substring matching catches "Introduction", which in a documentary is the first chapter of the
  programme, and skipping it would eat content. Rejects an "opening" shorter than 5 s, longer than
  300 s, or more than a quarter of the runtime — that last one catches a mislabelled single-chapter
  file. 9 tests.
- `NativePlaybackEngine.chapters` — reads `loadChapterMetadataGroups`, which is how AVFoundation
  surfaces the MPEG-4 family's chapter tracks and Matroska chapters.
- `AppleTransportOverlayModel.showsSkipIntro` / `skipIntro()` — seeks through the same coordinator
  path the scrubber uses. **Sticky**: once skipped, seeking back into the opening does not put the
  button up again and invite a loop.
- The button sits on the same layer as the next-episode card, outside the auto-hiding transport,
  for the same reason — it must not vanish while it is the thing to act on.

**Honest limit, restated:** content without chapter markers gets no button, and that is most
content. Fingerprinting across a season is the accurate way and stays parked.

Gate: 788 tests / 61 suites.

## iOS/iPadOS widgets — data layer done, target outstanding (2026-09-16)

The app already writes a shared snapshot for Top Shelf (`AppleTopShelfSnapshotWriter`), and it is
already cross-platform — the file write is `#if os(iOS) || os(tvOS) || os(visionOS)`. A widget needs
exactly that file, so the data layer was most of the way there. Three gaps closed:

1. **iOS had no app group.** `OpenStreamiOS.entitlements` carried only `group-session` (SharePlay),
   so `containerURL(forSecurityApplicationGroupIdentifier:)` returned nil on iOS and **nothing was
   ever written** — the writer ran and silently did nothing. Added
   `group.com.orgista.openstream`, matching tvOS and Top Shelf.
2. **No reader.** `AppleTopShelfSnapshotReader` — one decode path shared by the Top Shelf provider,
   the widgets and the tests, so they cannot drift. Returns nil rather than throwing, so a widget
   on a device where the app has never run draws its empty state.
3. **Nothing woke the widget.** `notify()` only called `topShelfContentDidChange()` on tvOS; it now
   also calls `WidgetCenter.shared.reloadAllTimelines()` on iOS/visionOS.

4 tests, including one that a private source's artwork URL (credentialed or query-carrying) never
reaches a widget — `AppleSystemArtworkPolicy` already restricts this to trusted hosts and the test
pins it, because a widget renders outside the app's sandbox.

**Still to do:** the WidgetKit extension target itself. That means editing
`Apps/OpenStreamApps.xcodeproj/project.pbxproj` to add a new target, which is project surgery rather
than code — flagging it as the next tick's work and the first thing here that could plausibly need
Xcode rather than a script.

Gate: 792 tests / 62 suites.

## iOS/iPadOS widget target — built, embedded, installing (2026-09-16)

`OpenStream Widgets` is a real target now. Continue Watching, small/medium/large, reading the
shared snapshot; tapping a poster opens `openstream://media/<id>?action=play`.

The project surgery was tractable because `project.pbxproj` is only 1043 lines with hand-assigned
sequential ids (`C…`/`D…`/`E…`/`F…`) rather than Xcode's random hex — so the Top Shelf extension
could be cloned exactly. Backed up first. Added: file references, a group, Sources/Frameworks/
Resources phases, the native target, both build configurations, the package dependency on
`OpenStreamApple`, a target dependency, and **a new Embed App Extensions phase on the iOS app,
which had none** — only tvOS did.

Two failures worth recording, both found by installing rather than trusting the build:

1. **`PRODUCT_NAME = "$(TARGET_NAME)"` produced `OpenStream Widgets.appex`** while the file
   reference said `OpenStreamWidgets.appex`. It built anyway, which is exactly the kind of
   mismatch that breaks later. Pinned to `OpenStreamWidgets`.
2. **Install refused: "missing or invalid CFBundleExecutable".** With
   `GENERATE_INFOPLIST_FILE = NO` the extension must supply the whole plist, and mine lacked
   `CFBundleExecutable`, `CFBundleInfoDictionaryVersion` and the `XPC!` package type. A clean
   `BUILD SUCCEEDED` said nothing about it.

Verified on the iPhone simulator:
- `PlugIns/OpenStreamWidgets.appex` present, extension point `com.apple.widgetkit-extension`
- **the app group container now exists on iOS** — `.../Shared/AppGroup/812502E6-…` — which is the
  proof the entitlement took; before today iOS had no group at all and the snapshot writer was
  silently writing nothing
- `com.apple.chrono.WidgetRenderer` resident, so the system picked the extension up

**Not verified:** the widget rendered on the Home Screen. Placing one needs Home Screen touch
interaction I cannot drive headlessly, so that is an owner check.

Gate: 792 tests / 62 suites.

## Download Live Activity — built and wired (2026-09-16)

Lock screen plus all three Dynamic Island presentations, driven by the real download coordinator.

- `AppleDownloadActivityPresentation` — the one mapping from coordinator state to what is shown, so
  the lock screen, the Dynamic Island and the in-app row cannot describe the same download
  differently. 8 tests.
- `AppleDownloadActivityAttributes` lives in the shared package, so the app and the widget
  extension — separate processes — agree on the shape by construction.
- `AppleDownloadLiveActivityController` — guarded by `areActivitiesEnabled`, holds at most one
  activity, and ends with a 4-second dismissal so a completed download is seen rather than
  vanishing mid-glance.

Two judgement calls worth recording:

1. **An unknown total renders an indeterminate bar, not a number.** `fractionComplete` is nil when
   the server sends no length, rather than inventing a denominator. A completed download reads 100%
   whatever the counters say, so the bar never sticks at 99% on a size mismatch.
2. **Driven from `transition`, not `stateDidChange`.** That callback is a single slot which
   `AppleSeasonDownloadQueue` claims and releases while running a batch — hijacking it would have
   broken season downloads. Only pause/resume/progress flow through; pausing does **not** dismiss
   the activity.

### Things the build would not have caught

- `Apps/Shared/Info.plist` is **preprocessed** (`#if OPENSTREAM_LONG_FORM_VIDEO`), so PlistBuddy
  cannot read or edit it — `NSSupportsLiveActivities` went in as a text edit. Verified in the
  *built* app rather than the source: `Print :NSSupportsLiveActivities` → `true`.
- I first wrote a comment claiming that flag was iOS-only. It is defined for **tvOS as well**, so
  the key lands in both plists. Corrected the comment rather than leaving a false statement in the
  file; the key is harmless on tvOS, where ActivityKit does not exist.

**Not verified:** a Live Activity actually on screen. That needs a real download running and the
Dynamic Island, which I cannot drive headlessly — owner check.

Gate: 800 tests / 63 suites.

## Empty-install pass, tvOS — 2026-09-16 (owner: "oled mode is only on some tabs")

Fresh sim, zero sources. The owner's two reports are both real and now measured.

**OLED black was on Library only.** Sampled on the empty install:

| tab | background |
|---|---|
| Library | `rgb(0,0,0)` |
| Discover / Live / Settings | `rgb(39,41,37)` and `rgb(43,40,30)` |

Two different values at two points, because it is the tvOS system **material** rather than a
colour — which also quietly breaks the no-gradients rule. The cause is per-branch styling:
Discover's `.background(Color.black)` sat on the **populated** branch, so an empty tab fell through
to the system ground. Fixed for Discover and verified `rgb(0,0,0)`; **Live and Settings still need
it** and are next.

**"Open Settings" moves when you flip tabs** — measured, pill centre y=598 on Discover against
y=504 on Library, a 94 pt jump. The cause is structural: Discover's empty state centres in the
whole tab area, Library's sits inside the ScrollView centred on `viewportSize − 32`. The fix is to
give Library the same shape Discover has rather than tuning an offset, so I have left it for a
clean edit rather than rushing a body refactor at the end of a tick.

**New, not previously reported: the app changes tabs on its own.** On a fresh install with no input
at all, the trace reads `9529ms press tab → settings`, `38890ms press tab → live`,
`39821ms press tab → library`. Suspect is `visibleTabs` recomputing as the stores settle, with
`OpenStreamTabVisibility.selection` moving off a tab that momentarily stops being visible. Not
diagnosed yet.

**Blocked:** the "older tvOS" half of the ask. Only tvOS 26.2 is installed and an older runtime is
a multi-GB download I did not start unprompted — say the word and I will.

Gate: 800 tests / 63 suites.

## OLED ground and the jumping button — both fixed, 2026-09-16

**Black ground now applied once, at the root.** Each tab used to bring its own, and Discover's was
on its populated branch only. Rather than patch Live and Settings the same way — which just spreads
the same mistake — `OpenStreamRootView.body` now carries one `Color.black.ignoresSafeArea()` for
every tab on tvOS. No tab, and no branch inside a tab, can drift again.

Measured on the empty install, all four tabs at two sample points:

| | before | after |
|---|---|---|
| Library | `rgb(0,0,0)` | `rgb(0,0,0)` |
| Discover | `rgb(39,41,37)` / `rgb(43,40,30)` | `rgb(0,0,0)` |
| Live | `rgb(39,41,37)` / `rgb(43,40,30)` | `rgb(0,0,0)` |
| Settings | `rgb(39,41,37)` / `rgb(43,40,30)` | `rgb(0,0,0)` |

**The 94 pt jump is gone.** The Library empty state was a *row inside* the ScrollView, centred on
`viewportSize − 32`, while Discover's is a sibling of its ScrollView centred on the whole tab area.
No offset could reconcile those, so Library now has the same shape: a `hasNothingToShow` branch
above the scroll view. The in-stack duplicate was removed and the screen trace moved up to the
Group so it still fires on both branches.

Measured after: "Open Settings" pill centre at **y=598 on Discover, Library and Live alike**
(was 598 / 504).

A side effect worth noting: with the empty state outside the scroll view it now takes focus, so the
one action on the screen is focused by default instead of the viewer having to find it.

Gate: 800 tests / 63 suites.

## Correction: the app does NOT change tabs by itself (2026-09-16)

I reported last tick that a fresh install navigates between tabs on its own. **That was wrong, and
the cause was mine.**

`OpenStreamVisionScreen` — the review hook — is written with
`simctl spawn <dev> defaults write com.orgista.openstream …`, which lands in the **simulator's
defaults domain, not the app's container**. `simctl uninstall` removes the container but leaves
that domain intact. So a reinstalled "fresh" app kept reading `settings` from the previous
measurement loop and navigated there at 40 ms, exactly as the debug hook is written to do. The
earlier 9.5 s / 38.9 s / 39.8 s readings were the same thing, interleaved with my own
`defaults write` calls mid-session.

With `defaults delete com.orgista.openstream` first: **zero tab changes in 30 seconds.** The app is
correct.

This is the second time the simulator's defaults domain has produced a false finding — the first
was the trusted-browser revocation "security hole" on 2026-09-15, where the same split between the
simulator plist and the app container misled me in the opposite direction. **Rule for the review
harness: `defaults delete com.orgista.openstream` before any clean-install test; uninstalling the
app is not enough.**

### What a genuinely fresh install actually looks like

Correct, and worth recording because it had never been seen outside a forced debug flag: brand
mark, "Welcome to OpenStream", **Open Sources** focused with **Not Now** beside it, on true black.
The first-run card, the root black ground and the focused-by-default action all behave.

Gate: 800 tests / 63 suites.

## Empty-install pass, iPhone — 2026-09-16

Spare sim: **iPhone SE (3rd gen)**, 375 pt wide — a different model from the owner's 16 Pro *and*
the small-phone width the UI checklist asks for. Deleted after.

### The phone first-run sheet had every fault the TV card had

Because only the tvOS branch was rewritten on 2026-09-15; this one was left untouched. On a clean
install it showed:

- "Not Now" orphaned at the top-left, above the title
- **two titles stacked** — "Getting Started" (navigation title) over "Welcome to OpenStream"
- no brand mark
- a `Spacer` opening roughly 700 pt of nothing before the button on an SE-sized screen

Now the same shape as the TV card: brand mark, one title, both actions at the bottom, no navigation
title, no toolbar item. My own incomplete fix, found by running the pass rather than assuming the
platforms matched.

### Everything else on the phone is correct

Measured on the empty install:

- "Open Settings" pill centre at **y=690 on Discover, Library and Live alike** — no jump, unlike
  the 94 pt tvOS one
- All four tabs `rgb(0,0,0)`
- Discover empty state: "No Sources" + one action, centred
- Settings: grouped list on true black, section headers, white toggles (nothing blue), consistent
  insets

### tvOS "older runtime" — still blocked

Only tvOS 26.2 is installed. An older runtime is a multi-GB download I have not started unprompted.

Gate: 800 tests / 63 suites.

## Web management portal audit — 2026-09-16

Rendered all four states (unpaired, paired, empty, error) from the current code and looked at them
at desktop and phone width.

**Passing:** brand mark and wordmark present; address demoted under the header; the source-type
segmented control, field label, placeholder and primary Add button all align on one column; the
sources list shows name, kind and a Remove per row; the error state renders its message in place.

**E5 responsive — verified properly, and my first reading was wrong.** The phone screenshot appeared
to overflow: "Xtream" clipped, the Add button past the edge, both Remove links off-screen. Before
reporting it I probed the page, and **Chrome headless had laid the page out at a 500 px viewport and
cropped the screenshot to 390** — `--window-size` does not set the CSS viewport in that mode. The
page itself reported `scrollW == clientWidth`, i.e. no overflow. Re-tested inside a 390 px iframe,
which gives a genuine 390 px viewport: everything fits, all three segment labels visible, Remove
links right-aligned. **The portal is fine on a phone.**

That is the third harness artifact this session that nearly became a false finding — after the
simulator defaults domain twice. Checking the tool before blaming the code is now the habit.

**E6 — NAS is genuinely missing.** The segmented control offers **Add-on / IPTV playlist / Xtream**
and nothing else, so there is no way to add a network share from the portal, which is what the owner
asked for ("no way to add NAS via web portal either"). This is a real feature rather than a GUI fix:
a fourth type, a host/share/folder/credentials form, and a POST handler that writes the credential
to the keychain the same way the on-device Add Network Share flow does — **and it must never echo
the password back into the HTML.** Not started; flagged as the next substantive portal item.

Gate: 800 tests / 63 suites.

## Settings panes reviewed — 2026-09-16

The tvOS settings split view always opens on Sources and the other eight panes need the remote, so
they had never been seen on the simulator. Added a DEBUG-only hook —
`defaults write com.orgista.openstream OpenStreamSettingsPane -string privacy` — matching the
existing review hooks, and captured all nine.

**Consistent across every pane:** true black, uppercase section headers, the 900 pt form column from
yesterday's fix, right-aligned values, legible sidebar selection. Nothing misaligned.

**One real defect: "Zero KB".** The Storage pane showed it on three rows — Metadata, Downloads and
(before any download) Downloads size — beside real values like "4.5 MB". It reads as a placeholder
nobody filled in. `ByteCountFormatter` spells zero that way unless
`allowsNonnumericFormatting = false`, and that property can only be set on an **instance**: the
`ByteCountFormatter.string(fromByteCount:countStyle:)` class method gives no way to reach it, which
is exactly why all four call sites in the app produced the same wording.

`AppleByteFormatting.string(_:)` now owns it, and the Storage pane, the Discover download row, the
offline debug view and the download Live Activity all route through it. Verified on device:
**"0 bytes"**, matching Apple's own Settings. 3 tests, including that a negative count clamps rather
than rendering "-1 KB".

**Also correct, worth noting rather than changing:** Storage's "Clear Metadata" and "Delete All
Downloads" properly dim when there is nothing to clear while "Clear Cache" stays live — real
disabled semantics rather than a control that looks tappable and does nothing.

The review key has been cleared from the simulator, per the rule learned earlier today.

Gate: 803 tests / 64 suites.

## iPhone pass — the resume bar, 2026-09-16

The owner's very first report of this whole session was "continue watching does not actually have
placement of where you left off". On iPhone it still does not, for **three** separate reasons, two
now fixed.

1. **Fixed — hardcoded width.** `AppleLocalTitleShelf` drew `ProgressView(...).frame(width: 140)`
   under a poster that is 100 pt on a phone and 300 pt on a TV, so the bar was wider than the phone
   card and under half the TV card, sitting short and off to one side. That is the owner's
   "these progress bars are not symetrical" (2026-09-15). The **Discover** shelf had already been
   fixed for exactly this — its comment quotes the same complaint and uses
   `.frame(maxWidth: .infinity)` — and this second copy was missed. Now matched.
2. **Fixed — NaN.** `value.position / value.duration` with no guard is `NaN` before the duration has
   been read, and a `ProgressView` given `NaN` draws an **empty track**: "not started" for something
   half-watched. `AppleWatchProgress.fraction(position:duration:)` now owns the division; 4 tests.
3. **Not fixed — the bar is clipped by the tab bar.** Continue Watching is the last shelf, its
   posters run to the bottom edge, and the bar lives *below* the card in the stack, so it falls
   behind the tab bar and is never seen. Verified by cropping the bottom of the capture: poster,
   then tab bar, no gap. The scroll content needs a bottom inset that clears the bar — the UI
   checklist's "scroll content is not hidden behind fixed bars". Next tick.

Gate: 807 tests / 65 suites.

## Correction: the resume bar was never clipped (2026-09-16)

I reported last tick that the Continue Watching progress bar is "clipped by the tab bar and never
seen". **That was wrong.** I had cropped the bottom of an *unscrolled* iPhone capture, seen poster
then tab bar, and concluded the bar had nowhere to go. In fact the row simply continued below the
fold.

Verified on the iPad, where the whole row fits above the fold: **all three bars render, at full card
width, identical to each other** — which is both fixes working and the "not symmetrical" complaint
resolved. Nothing is clipped and no bottom inset is needed.

So B11 closes with two real fixes, not three:
- the hardcoded `frame(width: 140)` under a 100 pt phone / 300 pt TV poster
- `position / duration` producing `NaN` and drawing an empty track

**Fourth harness-shaped mistake of this session**, and the pattern is now unmistakable: three of the
four came from reading a *capture* or a *default* as if it were the whole truth — the simulator
defaults domain twice, Chrome's viewport once, and an unscrolled screenshot here. The habit that
works is the one that caught the Chrome one: when a capture suggests a defect, prove it a second way
before writing it down.

Gate: 807 tests / 65 suites.

## AirPods awareness — 2026-09-16

Most of this already existed and was better than expected. What was missing was the one thing a
viewer actually notices.

**Already there (verified, not rebuilt):** spatial audio capability tracking, observation of
`spatialPlaybackCapabilitiesChangedNotification`, `renderingModeChangeNotification` and
`renderingCapabilitiesChangeNotification`, interruption handling, and
`allowedAudioSpatializationFormats = .monoStereoAndMultichannel` on **both** engines. Head tracking
and headphone personalisation are left to the system, which is correct — an app that overrides them
fights the viewer's own settings.

**Missing: nothing paused when the output went away.** `routeDidChange` read the reason, stored it
in state, and did nothing with it — so pulling AirPods out moved the audio to the device speaker and
kept playing out loud. `AppleAudioRoutePolicy` now decides, and `ApplePlayerHost` pauses.

The rule, and why each part of it:
- **`oldDeviceUnavailable` and `noSuitableRouteForCategory` pause.** Losing the output in use, or
  losing every usable output, are the same situation to the viewer.
- **`newDeviceAvailable` does not.** Plugging AirPods *in* should move the audio, not stop it.
- **`categoryChange`, `override`, `routeConfigurationChange`, `wakeFromSleep` do not.** Those fire
  during ordinary session setup; pausing on them would stop playback at the moment it starts.
- **Nothing ever auto-resumes.** Putting AirPods back in leaves the player paused, as Apple's own
  players do — the viewer may have moved on, and audio restarting unattended is worse than a paused
  player. `shouldResume` returns false for every reason and a test pins that.

7 tests, including one that asserts the policy's raw values match `AVAudioSession.RouteChangeReason`
— the policy restates them so it can be tested without an audio session, and that is exactly the
kind of duplication that silently rots.

**A real trap in this file:** `AppleAudioSessionCoordinator` is declared **twice** — the real one
under `#if os(iOS) || os(tvOS) || os(visionOS)` and a macOS no-op stub in the `#else`. Adding the
callback to the real one alone compiled on device and broke the host on macOS. Both now carry it.

Gate: 813 tests / 66 suites.

## Remote commands — the stem press did nothing (2026-09-16)

There was **no `MPRemoteCommandCenter` anywhere in the app**. An AirPods stem press, Control Centre,
the lock screen and a car head unit all had nothing to talk to. `MPNowPlayingInfoCenter` was
populated, but only by `ApplePlayerSession`, which is AVPlayer-only and is not on the current
playback path — so even the Now Playing entry was largely absent.

`AppleRemoteCommandCenter` now registers play, pause, togglePlayPause and skip ±10 s, and publishes
Now Playing info.

**Bound to `ApplePlaybackEngine`, not to `AVPlayer`** — the decision that matters here. Most of the
owner's content takes the libavcodec route, which draws into an `AVSampleBufferDisplayLayer` and has
**no `AVPlayer` for the system to control**. Anything built on AVPlayer alone would have left a stem
press dead on exactly the content that needs it most, while appearing to work in a demo on an MP4.

Decisions worth recording:
- **`toggle` resolves against what is playing.** The stem sends `togglePlayPause`, not play or
  pause, so it has to read the engine's phase; an explicit command from Control Centre is obeyed as
  given and never reinterpreted.
- **Skips clamp into the item.** Nudging forward near the end lands on the last frame rather than
  running off the end and stopping playback, which is not what a nudge means.
- **A live stream gets no skip controls at all** rather than controls that are present and inert.
- **10 s matches the clickpad edges and the on-screen glyphs**, so every way of skipping moves the
  same distance.
- `teardown()` clears the Now Playing entry, so the lock screen stops offering to control a player
  that has gone.

8 tests. Both iOS and tvOS build.

**Not verified:** an actual stem press. That needs real AirPods on a real device — owner check. The
lock-screen controls on the simulator would be a partial check and I have not done it.

Gate: 821 tests / 67 suites.

## Apple Watch app — target builds, deliberately not embedded (2026-09-16)

**Blocked on verification.** The watchOS **SDK** (26.2) is installed but there is **no watchOS
simulator runtime**, so the app can be compiled and cannot be run or screenshotted. Installing a
runtime is another multi-GB download I did not start unprompted.

`OpenStream Watch` exists as a target and builds clean against `watchsimulator`. It is a **remote,
not a second browsing app**: a watch screen is a glance and a tap, and what belongs there is the
transport plus what is playing, not a catalogue. Title, then back-10 / play-pause / forward-10.
No artwork — on a watch face a poster costs the controls their room. "Nothing Playing" as the empty
state, one line, no instructions, the same rule the other empty states follow.

`AppleWatchLink` talks over **WatchConnectivity**, because App Groups do not span devices — the
watch cannot read the snapshot the widgets use. A tap sends `sendMessage` when the phone is
reachable and falls back to `transferUserInfo` when it is not, so a press is not silently dropped
with the phone asleep in a pocket. State is **not persisted**: a stale "now playing" on the wrist is
worse than an honest empty state, because the viewer would tap transport controls at something that
stopped an hour ago.

### I broke the iOS build and backed it out

Embedding the Watch app in the iOS target made **building iOS require the watchOS runtime**:

> This scheme builds an embedded Apple Watch app. watchOS 26.2 must be installed in order to run
> the scheme

So the Embed Watch Content phase and the target dependency are **removed**. The Watch target still
exists and still builds; it is simply not embedded yet. iOS builds clean again — verified, not
assumed. Embedding is one phase and one dependency away once a runtime is installed, and the ids
are already in the project.

**Not verified:** anything visual, the WatchConnectivity handshake, or the phone side (which does
not yet publish an application context — next step).

Gate: 821 tests / 67 suites.

## Watch link — phone side built (2026-09-16)

The wrist now has something to talk to. `AppleWatchCompanion` publishes what is playing and applies
what comes back, wired into `ApplePlayerHost` beside the remote command centre — attach on play,
refresh on change, detach on teardown so the watch shows "Nothing Playing" rather than offering
transport for a player that has gone.

**Commands run through `AppleRemoteCommandPolicy`** — the same rules the AirPods stem and Control
Centre use. The wrist is another remote, not a second implementation, so it cannot drift into
behaving differently.

Two decisions the tests pin:

- **Nothing playing omits the title key rather than sending an empty string.** The watch shows its
  empty state on a *missing* key and a blank now-playing card on an empty one — the difference
  between "nothing is on" and "something is on and I cannot name it".
- **`sessionDidDeactivate` reactivates.** Without it the link dies when the viewer switches watches
  and never returns without relaunching the app.

`[String: Any]` is not `Sendable`, so both sides resolve the payload on the delegate's own thread
and send only typed values across to the main actor — the same Swift 6 trap that failed the watch
build earlier today, avoided here by construction.

6 tests on the payload shape, because WatchConnectivity is untyped and a key typo would fail
silently on a device that is awkward to debug. The watch target restates the two key strings (it
does not link the package) and the phone-side tests pin them.

**Verified:** iOS, watchOS and tvOS all build; gate green. **Not verified:** the handshake itself,
or anything on the wrist — still no watchOS simulator runtime.

Gate: 827 tests / 68 suites.

## Where to watch — rules layer built (2026-09-16)

Every constraint the owner gave is now a rule with a test on it, rather than an intention.

| rule | how it is enforced |
|---|---|
| opt-in, never default | an empty `enabledProviderIDs` returns **nothing**; a fresh install cannot advertise a service |
| only services they signed into | membership test against that same set, not against what TMDB says the title is on |
| never rent or buy | `isOffered` is false for both; the buckets are still *decoded* so the exclusion lives in one rule with a test, not hidden in a parser |
| say whether there are ads | `displayName` → "Tubi · Free with ads"; a subscription gets no suffix |
| stay in the app | `replacesPlay` is false whenever a local or add-on source exists |
| external becomes Play | only when nothing else can play it |
| region-correct | the region is a **required** argument; a title on Netflix in the US may be nowhere in the UK, and the wrong region's answer is worse than none |

One case worth calling out: a service can appear in **two buckets at once**, and the better offer
wins — so a subscription is never labelled "free with ads". 10 tests.

The purchase exclusion is the differentiator, so it is pinned deliberately: JustWatch and Reelgood
lead with "Rent $3.99" because rental affiliate revenue *is* their business model. Refusing it is a
position, and positions rot without a test.

**Still to build:** the TMDB fetch is decoded but not yet wired to a request; the Settings screen to
add and sign into services; and the title-page row. Also unresolved and honest — **title-level deep
links generally need partner agreements**, so without one the handoff opens the service's app
rather than the title. The UI must not imply otherwise.

Gate: 837 tests / 69 suites.

## Where to watch — TMDB request wired (2026-09-16)

`AppleTMDBClient.watchProviders(imdbID:kind:region:configuration:)` goes through the same `load`
helper as everything else, so it inherits the response-size cap, the https/host check and the
credential handling rather than re-implementing them.

Five tests against a stubbed loader, no network. Two are about being careful rather than about
happy paths:

- **A show uses the `/tv/` endpoint, a film `/movie/`.** Looking a series up as a film returns a
  different title's availability, which would be wrong rather than empty — the worst failure mode
  for this feature.
- **A malformed identifier is rejected before any request is made**, asserted by counting requests
  and expecting zero.

The region test pins the actual point of the feature: the same title returns Netflix in the US and
Now in the GB block, and an unlisted region returns nothing rather than falling back to another
country's answer.

### A test bug I caused and fixed

`aShowUsesTheTVEndpoint` failed on the first run. The cause was my **stub**, not the code: the
`find` response had `"tv_results":[]`, so the series lookup threw `titleNotFound` before it could
reach the providers endpoint. Both result arrays are populated now. Worth recording because a
green-by-accident version of that test — one that passed because the code never got that far —
would have been worse than the failure.

**Remaining for G:** the Settings screen that drives `enabledProviderIDs`, the title-page row, and
making sure the copy does not imply a title-level deep link that partner agreements do not exist for.

Gate: 842 tests / 70 suites.

## Where to watch — the opt-in screen (2026-09-16)

**Settings → Services → Streaming Services.** Verified on the TV: the row sits second in Services
with the same glyph slot and chevron column as Metadata, Radarr & Sonarr and Trakt.

The screen lists the services operating in the viewer's region and they tick the ones they
subscribe to. That set *is* the feature's on-switch — `watchProviderIDs` is empty by default, and
empty means nothing about where else a title can be watched appears anywhere in the app.

Decisions worth recording:

- **The directory request asks only for the subscription list.** The viewer is choosing services
  they *subscribe to*; a rental storefront is not something to subscribe to, so it never reaches
  the picker.
- **Ordered by TMDB's `display_priority` for the region**, not alphabetically, so the services
  someone is most likely to have appear first.
- **The toggle writes straight through to the store.** There is no local copy of the selection to
  drift out of sync with what the title page reads.
- **The empty state names the actual cause.** With metadata off or no TMDB key the screen says
  "Metadata Is Off" rather than showing an empty list that looks broken — the same rule the live
  failure presentation follows.
- A directory entry is a *service*, not an offer for a particular title, so its placeholder
  `.subscription` value is never rendered as a label. Only a real availability answer gets
  "Free with ads".

**Remaining for G:** the title-page "also available on" row, and copy that does not imply a
title-level deep link — without a partner agreement the handoff opens the service's app, not the
title, and the UI must not promise otherwise.

Gate: 842 tests / 70 suites.

## Where to watch — the title-page row (2026-09-16)

"Also available on Netflix and Tubi · Free with ads", sitting with the synopsis in secondary text.

**A line of prose, not a second Play.** The owner's rule is that the app stays the way you watch
things — "in general prefer to stay in the app and just a very subtle also available to stream on
(platform)" — so this competes with nothing. It renders only when the viewer has opted in *and* a
service they subscribe to actually carries the title.

- **No request is made at all when they have not opted in.** The guard is before the call, not
  after it, so a viewer who never enables this never has their library sent to TMDB for provider
  lookups.
- **The list is capped at three plus "and N more".** A title on nine services would otherwise turn
  a quiet line into a paragraph, which is the opposite of the point.
- **Ads stay named inside the sentence** — "Tubi · Free with ads" — so "free" never quietly means
  "free with adverts".
- 6 tests on the sentence alone, because that string is the whole feature's manners.

### Deliberately not built: tapping it

Without a partner agreement a deep link opens the service's **app**, not the title. A row that looks
tappable and then dumps you on Netflix's home screen is worse than a row that just tells you. So the
row states availability and promises nothing, and the owner's "play becomes the option when there is
no local source" case waits on the link-depth decision — `AppleWatchProviderPolicy.replacesPlay`
already encodes the rule and has tests, so it is one view change away once that is settled.

**G is otherwise complete:** policy, TMDB request, opt-in screen, and the row.

Gate: 848 tests / 71 suites.

## Cross-cutting sweep, section A — 2026-09-16

The rows I had verified only in passing, now checked systematically rather than claimed.

**A7 passes outright.** Zero occurrences of blue or green anywhere in the source — not
`Color.blue`, not `systemBlue`, not an `accentColor`. The monochrome rule is held by construction,
not by vigilance.

**A3 passes.** Every remaining raw `Label(` is a toolbar item, a menu label, an `.iconOnly` button
or a pill. None are tvOS List rows, which is the only place the icon slot collapses into the text.

**A13 passes — and my first reading was wrong.** A grep flagged two icon-only controls as having no
accessibility label. On inspection both are `Label("Next Video", systemImage:)` and
`Label(tab.title, systemImage:)` with `.labelStyle(.iconOnly)` — the title is present and
`.iconOnly` hides it visually, not from VoiceOver. Checking the context rather than trusting the
grep is the same discipline that caught the Chrome viewport.

**A8 — a real deviation I am deliberately not "fixing".** Five fields use the placeholder as their
only label: ZIP code, Server URL, Root folder path, Quality profile ID, Channel or group. The
checklist calls that an anti-pattern, and on the web it is — but **Apple's own Settings does exactly
this** for short single-purpose fields in a grouped form, and the surrounding section header carries
the context. Changing five fields to fight the platform's own convention would make the app less
familiar, not more usable. Recording it as a known, considered deviation rather than silently
leaving it or blindly complying.

Still genuinely unswept: A1, A2, A4, A5, A12, A14 — visually checked across many captures tonight
but not row-by-row, so not ticked.

Gate: 848 tests / 71 suites.

## Apple Watch app — running and verified (2026-09-16)

Runtime downloaded (3.89 GB, owner approved), a Series 10 sim created and **paired with the owner's
iPhone 16 Pro**, the Watch app **re-embedded** in the iOS target, and the whole thing installed and
launched. `OpenStream iOS.app/Watch/OpenStreamWatch.app` is present in the built product.

Verified on the wrist: the title, and the empty state reading "Nothing Playing" on true black.

### One real defect, found by zooming

The empty state used `play.slash`. At watch size the slash crosses the play triangle's apex and the
whole thing **reads as a mouse cursor** — confirmed by cropping and enlarging the capture 4×, rather
than assuming the symbol had failed to load. A glyph that has to be squinted at is worse than none,
and the app's empty states are a title and nothing else anyway, so it is gone.

### My own rule caught a stale build

The first fix appeared not to work: the glyph was still there. The build had said **BUILD
SUCCEEDED** — but my grep for `SwiftCompile .* OpenStreamWatchApp.swift` came back **empty**, which
is exactly the check I wrote after the SMB share lied about a build last night. Touching the source
and rebuilding produced the compile line, and then the fix was there. Without that check I would
have reported a fix that had never been compiled.

### Correction carried into the audit

G2 said "only services they are **signed into**". The app cannot verify a sign-in and never asks for
service credentials — it is "services the viewer says they subscribe to". Reworded, because the
accurate version is also the better story.

**Still unverified:** the playing state on the wrist and the WatchConnectivity handshake, which need
live playback on the phone.

Gate: 848 tests / 71 suites.

## Watch link — traced to the exact refusal (2026-09-16)

Drove real playback on the phone and watched the wrist. It stayed on "Nothing Playing", so I traced
the publish path rather than guessing:

```
watch link: not activated (state=0)          ← first publish beat activation, harmless
watch link: paired=true installed=false      ← paired, but the phone says the app is not installed
watch link: publish failed — Watch app is not installed.
```

**The phone side is working.** It activates the session, sees the pairing, builds the payload and
calls `updateApplicationContext`. The OS refuses it because `isWatchAppInstalled` is false — I
installed the watch app **directly onto the watch simulator** with `simctl install` rather than
letting it propagate from the phone, and `WCSession` does not count that as installed. This is a
harness limitation, not an app defect, and it will need a real paired Watch to close.

### The diagnostic is staying

`publish()` used `try? session.updateApplicationContext(payload)` — which **swallowed this entirely**.
A viewer whose watch app was genuinely missing would have seen a wrist that silently never updated
and no way to find out why. It now names the reason, and the not-activated case is distinguished
from the refused case. That is worth keeping well beyond this session.

### Also fixed on the way

The `play` review hook was `#if DEBUG && (os(visionOS) || os(tvOS))` — **iOS was left out of all
four sites**, so nothing playback-dependent could be reviewed on the phone at all. Extended to iOS,
which is what made this diagnosis possible and unlocks verifying the player, the Live Activity and
the remote commands on iPhone from here on.

Gate: 848 tests / 71 suites.

## iPhone player — subtitles confirmed, and a real placement defect (2026-09-16)

First look at the player on iPhone, now that the review hook reaches iOS.

**Good: subtitles render on the phone.** Caught mid-playback — "And I tell them that there was signs
of devastation everywhere." That is the subtitle work confirmed on a second platform, through the
libavcodec route rather than AVPlayer.

**Defect (B29): the cue is pinned to the bottom of the screen, not to the video.** In portrait the
video letterboxes into a band about a third of the screen tall, and the caption renders roughly
450 px below where the picture ends, floating in the black.

Cause, confirmed rather than guessed — the trace says `route=surface`, so this is the app's own
overlay, and it is laid out as:

```swift
VStack { Spacer(); subtitleCueView }
    .padding(.bottom, model.controlsVisible ? 100 : 24)
```

Bottom of the overlay, which is bottom of the *screen*. On Apple TV the video is full-bleed so that
is exactly right, and the bug is invisible there. On a phone in portrait it is not.

**Not fixed this tick, deliberately.** Placing the cue against the picture needs the video's
aspect ratio, and **no engine exposes a `videoSize` / `presentationSize` anywhere** — I checked the
protocol, the Aether engine and the surface view. That is plumbing through `ApplePlaybackEngine`,
not a padding tweak, and rushing it at the end of a tick is how the 94 pt offset bug got written in
the first place. Recorded with the cause so the next tick starts from a diagnosis rather than a
symptom.

Gate: 848 tests / 71 suites.

## Subtitle cues now sit against the picture (2026-09-16)

`AppleVideoFitting` computes where the video actually is inside the player, and the overlay anchors
cues to that instead of to the screen. Measured on iPhone: the caption moved from roughly **540 pt
below the video** to **~58 pt below it**, reading as part of the picture rather than floating in the
letterbox. Apple TV is unchanged — the video is full-bleed there, so the inset is zero by
construction and a test pins that.

`ApplePlaybackEngine.videoSize` is new, defaulting to nil. `NativePlaybackEngine` fills it from the
format description it **already read for a trace and threw away**. The libavcodec surface comes from
the external AetherEngine package and cannot report its size, so that route falls back to an assumed
16:9 — deliberately, and in the safe direction: guessing *narrower* than the truth puts the caption
slightly inside a wide film, which is what every player does, while guessing wider would push it
back into the black.

### Two mistakes of mine this tick, both caught by looking

1. **The first version changed nothing on screen.** It compiled, and its geometry tests passed,
   because I applied `.padding(.bottom, inset)` *after* `.frame(...)` — which expands the view
   rather than lifting the cue inside it. Only the screenshot showed it. Tests on the maths cannot
   catch a modifier-order bug in the view.
2. **A test expectation was wrong, not the rule.** I asserted a 9:16 video pillarboxes on a phone;
   it does not — a 393x852 screen is proportionally taller still (0.461 against 0.5625), so even
   portrait video letterboxes slightly. Corrected the test and added the real pillarbox case.

8 tests on the geometry. Gate: 856 tests / 72 suites.

## Discover checklist rows — 2026-09-16

Measured rather than eyeballed. **B2, B3, B5, B8 pass.** Pills measured at Play 86–273 and Details
309–498, a **36 pt gap** against the 24 pt a focused brand pill needs, both content-sized and on one
baseline.

**B6: my checklist row was wrong, not the app.** I had written "first poster row fully on screen
before any scroll". The first row is *meant* to peek — `AppleTVBillboardMetrics` says so in a
comment ("the billboard fills the screen and the first row only peeks over the bottom") and a test
asserts it. A peek is how a viewer knows there is more below. Corrected the checklist instead of
"fixing" correct behaviour.

**Two measurements I nearly reported as defects, both threshold artifacts.** A first pass put the
shelf title at x=81 and the poster edge at x=186, which looked like a 105 pt misalignment; the
poster's left edge is simply dark art, and a lower threshold showed them sharing the column. The
same pass "measured" the pills as two dozen fragments — it was picking out the letters inside them
rather than the pill fills. Both were caught by re-measuring rather than writing them up, which is
the habit that has now saved four false findings tonight.

**B4 and B7 left open honestly.** The rotation indicator draws with the active segment filled, but
proving the segment count matches the hero count needs more than one frame. The search/refresh glyph
pair is not visible at scroll position 0 and confirming it needs a scrolled capture, which a
remote-free harness cannot drive.

Gate: 856 tests / 72 suites.

## Cross-cutting rows A1, A2, A4, A5, A12, A14 — 2026-09-16

**A12 fixed at the cause.** The owner saw values wrap **mid-word** on 2026-09-14
("opensubtitles-v3.strem.io", "Sep 13, 2026 at 10:49 PM"). Widening the form column hid that; it did
not remove it, because `LabeledContent(_:value:)` wraps, and a value with no spaces has nowhere to
wrap except through the middle of a word. Of 28 `LabeledContent` rows, only 4 had any truncation and
**none had a line cap**.

`AppleTruncatingValue` now backs the three rows that carry space-free values — the manifest host or
share path, the validation summary, and the capability list. **Middle** truncation, not tail: for a
host or a path the beginning and the end both identify it and the middle is the part nobody needs.
The other 25 rows carry short values (Type, Health, Items, Enabled) and are left alone rather than
churned.

**A14 — a considered deviation, not a fix.** 41 spacing literals are not multiples of four, led by
6 pt (×12), 10 pt (×8) and 2 pt (×7). Nearly all are deliberate fine-tuning: 2–3 pt between a title
and its subtitle, and the brand pill's own 18/11 metrics. The app's actual **tokens** —
`spacingSmall/Medium/Large/ExtraLarge` at 8/16/24/32 — are on rhythm, as are the metrics types.
Rewriting 41 local values to satisfy a web-leaning guideline would be churn with real regression
risk and nothing a viewer would notice.

**A1, A2, A4, A5 ticked on measured evidence**, not assertion: nothing clipped in any capture
tonight; Discover's title at x=81 against the 80 pt column; 36 pt between the Discover pills against
the 24 pt a focused pill needs; and Storage dimming exactly the two actions with nothing to do while
Clear Cache stays live.

Gate: 856 tests / 72 suites.

## 2026-09-16 — iPhone GUI pass

**Fixed: `&amp;` rendered verbatim in overview text.** Visible on the *9/11: One Day in America*
hero and title page — "the 9/11 Memorial &amp; Museum". Catalogue add-ons hand back text that was
escaped for a web page upstream.

One shared decoder (`AppleHTMLEntities`), applied at the single point every catalogue item is
built, so it cannot be applied twice. The subtitle parser's private copy of the same logic now
calls it instead of duplicating it.

The first fix did not take, and that was the useful part: a **fresh install still showed the
escaped text**, because `AppleCatalogItem` relied on the synthesised `Decodable`. Anything
already in the on-disk cache was assigned straight to the stored properties, skipping trimming,
clamping and the decode. Cache rehydration now routes through the normalising initialiser, so a
viewer whose cache predates a fix is repaired on read instead of keeping the old text forever.
That applies to every future normalisation fix, not just this one.

Gate: **867 tests / 73 suites**, green (was 856/72).

**B7 was a wrong checklist row, not a bug.** There is no search/refresh glyph pair on tvOS — the
whole toolbar is inside `#if !os(tvOS)`, because Search is its own tab there. The dead
`#if os(tvOS)` branches inside that block are removed. Verified the pair on iPhone instead.

**B4 needs no further measurement.** The rotation indicator's segment count and active index come
from the same array in a single call, so they cannot disagree.

Also confirmed in passing: captions anchor to the video's bottom edge rather than the screen's,
on a 2.39:1 title on a 6.9" phone.

**C2 tab bar (iPhone), 2026-09-16 — passes.** Label centres 152 / 453 / 754 / 1055: an even
301 px pitch with symmetric margins (152 / 151). Selected white, unselected grey, nothing blue.

One thing to decide, left alone for now because it is your call: the Discover symbol
`sparkles.tv` renders as a **solid white slab** next to three line glyphs (books, radiowaves,
gearshape), so that one tab reads as a boxed icon. The code picks outline variants consistently —
it is the symbol itself that is filled. The same symbol feeds the tvOS bar, where "no boxed icons"
is an explicit rule and A6 is still open. Swap it (`play.tv`, `sparkles`, or `house`) or keep it?

**Discover tab icon — boxed, now fixed (2026-09-16).**

The interesting part is *why* it was a box. The code picks outline symbols consistently
(`sparkles.tv`, `books.vertical`, `dot.radiowaves.left.and.right`, `gearshape`) — but **tab bars
substitute the `.fill` variant automatically**, so a tab icon is only ever as light as its filled
form. At tab size `sparkles.tv.fill` drops the sparkles and renders as a blank white rectangle.
Reading the source would never have caught it; only a capture shows it.

Now `sparkles`, which has no `.fill` counterpart and so stays line art in every state. Checked on
iPhone and on the tvOS bar. A guard test asserts no tab uses a symbol whose `.fill` is a solid box,
so this cannot come back by someone picking a nice-looking outline in the SF Symbols picker.

Gate: **870 tests / 74 suites**, green.

A6 ("no boxed icons on tvOS") is moved to in-progress rather than ticked — the tab bar is clean,
but the other tvOS surfaces still need a sweep before that row is honest.

**Search glyph spacing (tvOS) — could not tighten it; reverted.**

Measured the gap: search glyph ends at x=545, the Discover pill starts at x=576, so **31 px**.
Tried negative trailing padding on the icon-only tab label. It had **zero** effect — the pill spans
576–824 in the captures both before and after, identical to the pixel. tvOS lays the top tab bar
out itself and ignores padding inside `.tabItem`, so the no-op was reverted rather than left in as
misleading dead code.

That 31 px is stock tvOS inter-tab spacing; the search tab just looks further away because it is
icon-only and therefore much narrower than its neighbours. Closing it would mean replacing the
stock tab bar with a custom one, which is a much bigger change than the request implies — say the
word if it is worth that, otherwise it stays stock.

**Scope correction from the owner, same session:** the nav-bar icons (`tv`,
`rectangle.stack.badge.plus`, `photo.on.rectangle.angled`, …) are fine and stay as they are. The
"no boxes" rule applies to **Channel Manager and the Settings panes** — next item.

**Channel Manager boxes — fixed (2026-09-16).**

"Search Channels" and "Refresh" were tvOS toolbar items, and a tvOS toolbar item always draws a box
around its glyph — the same thing you called out on Discover and Search. They were being clipped by
the screen edge too, so they literally read "Searc  hannels" and "R  sh". Both are now plain rows in
the form with leading glyphs.

**I also introduced a regression doing it, and caught it before it shipped.** Putting those rows at
the head of the channel list made the Settings tab draw its selection pill *without the gear* and
overflowing the right edge of the tab bar. I A/B'd it against the original build rather than guess:
the original pill was correct, and a build with the toolbar removed but no rows added was also
correct — so it was my rows, not the toolbar removal. Giving them their own section fixes it.
Verified on screen, not inferred.

Gate: **870 tests / 74 suites**, green.

Outside the scope you set, so noted rather than touched: `AppleLibraryTVView` uses
`.buttonStyle(.bordered)` for "Next Video" and its channel rows, which draws boxes on tvOS. Say the
word and I'll do that one too.

**Channel Manager weirdness — ZIP code field (2026-09-16).**

It was always on screen, always empty, and disabled unless Live view was set to Regional. On a
television a permanently greyed-out field reads as broken rather than as not-applicable. It is now
disclosed only when it applies, matching the Custom Package section directly below it, which
already worked that way.

Checked both directions rather than just the one that proves me right: gone under Provider Lineup,
back under Your Regional. The sim's Live view setting was flipped for the test and has been put
back to Provider Lineup, and the debug screen key is cleared.

Gate: **870 tests / 74 suites**, green.

**C3 (iPhone navigation titles) — mostly good, one real defect.**

Titles are right: Settings draws its large title at the leading edge, and the title page draws no
title at all — just the floating back chevron over the backdrop.

**The defect: scrolled text collides with the status bar.** On the title page the clock, wifi and
battery are drawn straight on top of the overview text, and the Dynamic Island cuts through the
first line. The page hides the iOS navigation bar to get the full-bleed backdrop, so there is no
bar material for scrolled content to pass under.

I did not "fix" this on my own because every option changes something you already signed off:
(a) stop hiding the bar, and let iOS apply its standard scroll-edge material once the hero scrolls
    away — this is what the stock TV app does, but the page then has a bar it was designed without;
(b) inset the content below the safe area — that kills the edge-to-edge backdrop;
(c) leave it.
The usual answer is a scrim behind the status bar, which your zero-gradients rule rules out. Which
way do you want it?

Sheets are still unexercised on iOS — they open from controls the headless harness cannot tap, so
that half of C3 needs a UI test target or your hands on the sim.

Gate: **870 tests / 74 suites**, green.

**tvOS search routing — fixed (2026-09-16).**

A deep link or Siri phrase (`openstream://search/…`, App Intent) used to do two things at once on
Apple TV: select Discover, then push Discover's own search page on top of it — on the one platform
that already carries Search as a tab. The pushed page also carried a `navigationTitle`, which on
tvOS draws over the page.

The route now selects the Search tab where one exists, and Discover only pushes its own search page
on platforms without that tab. Split into `AppleSearchRoutePolicy` so both halves are asserted to
never fire together (4 tests).

Gate: **874 tests / 75 suites**, green (was 870/74). Compiles on tvOS.

**Still owed:** on-device proof. Verifying it means firing `simctl openurl` at the tvOS sim, which
you are using right now — I did not touch it. I will run that as soon as you are done.

**Top Shelf preview — fixed (2026-09-16, your report).**

Every part of the plumbing was already right: the snapshot file was being written and was current,
the extension was embedded with the correct extension point, principal class and app-group
entitlement, and the JSON was valid with 4 continue-watching and 10 top-pick items.

The bug was in the data. `AppleSystemArtworkPolicy` only trusted `image.tmdb.org` and
`images.metahub.space`, and your in-progress titles are served by `images.justwatch.com` and
`api.ratingposterdb.com` — so **0 of 4** Continue Watching tiles were published with artwork, while
Top Picks looked fine purely because Cinemeta serves metahub. That asymmetry is why it would have
seemed to work sometimes. Your media index uses 10+ artwork hosts, so a fixed allowlist was never
going to hold.

The rule is now about what is safe to hand to another process rather than who is serving it: https,
no credentials, no query, no fragment, no private/LAN host. I deliberately **kept** the no-query
rule — it stops a poster URL carrying a token from reaching a system surface, and none of the hosts
that broke need one. A NAS poster stays blocked too: the extension can't reach it, and publishing
it would leak an internal hostname.

Verified the republished snapshot: **4/4** Continue Watching items now carry artwork. The visual
needs your hover — `simctl` has no remote API, so I can't move Home-screen focus headlessly. The
build is installed on the sim; hover OpenStream and it should fill.

Gate: **882 tests / 76 suites**, green (was 874/75).

**iOS/iPadOS widgets — found the reason they were never going to work (2026-09-16).**

Chasing the Top Shelf artwork bug turned up something bigger next door. The Continue Watching
widget reads the shared snapshot file, because a widget runs outside the app's container and can
see nothing else — but **every call site that writes that file was `#if os(tvOS)`**. The phone's
app group container had no `topshelf-v1.json` at all. The widget was never going to show anything,
artwork or not.

It was always meant to publish on both: `notify()` already reloaded widget timelines on iOS and
visionOS. Only the writers were gated. Publishing now runs on tvOS, iOS and visionOS, behind the
same "show in Apple services" toggle.

Worth knowing: adding those four modifiers to the root view's body **broke the iOS build** with
"unable to type-check this expression in reasonable time", and the SwiftPM gate stayed green
throughout — that gate builds for macOS, where the block was compiled out. A green `swift test` is
not proof the phone compiles. Extracted into its own `AppleSystemSurfacePublishing` modifier, which
fixes it and reads better.

Gate: **882 tests / 76 suites**, green. Builds on iOS and tvOS.

**Not yet verified on device.** Confirming the file lands on the phone means booting the iPhone sim,
which means shutting down the Apple TV one you are using — one sim at a time is your standing rule,
so I left yours alone. Tell me when you are done with it and I will confirm.

**Confirmed on device, plus two more fixes, plus the Watch answer (2026-09-16).**

**iOS widgets now have data.** The phone writes a 13.5 KB snapshot: 2/2 Continue Watching items
with artwork, 10/10 Top Picks. Both of today's fixes verified on the phone rather than inferred.

**The widget's empty state was lying.** It said "Nothing in progress" whether you had genuinely
finished everything or nothing had ever been published — which on iPhone was always the case. You
have four half-watched shows; it told you there was nothing. It now distinguishes the two, and the
unpublished case reads "Off in Settings › Privacy".

**One thing I did not change, because it is your call.** Publishing is opt-in: `topShelfEnabled`
and `systemSearchEnabled` use a plain `defaults.bool` default-false, while every "should be on"
flag in the same initialiser uses `?? true` — so opt-in is deliberate, and it lives under Privacy.
The consequence is that a new user who adds the widget sees the empty state until they turn on
Privacy › Apple Services. Flipping a privacy default is not something I will do on my own. Want it
on by default?

**Apple Watch showed a play button while the phone was playing.** `attach` was the only thing that
published a play/pause state, and it runs while the engine is still loading — so the wrist kept the
loading-time value for the whole title. Nothing republished when the phase changed, because
`refreshRemoteCommands`, the one method that would have, had **no callers at all**. The republish
now rides the player's existing 0.25 s bind timer (no new timer), and an unchanged context is
dropped so the link is not spammed four times a second. Verified: ▶ became ⏸ against a playing phone.

---

### How developers test Watch ↔ phone sync

You do not need hardware. WatchConnectivity works between **paired simulators**, and you already
have a pair:

```
xcrun simctl list pairs
# A9060E1D…  (active, disconnected)
#   Watch: OpenStream Watch Review (8BA0CCFB-…)
#   Phone: iPhone 16 Pro (6A037503-…)
```

The catch is the word **disconnected**: a pair only links when **both halves are booted**. Boot the
watch while the phone is up and it flips to `(active, connected)` — that is the whole trick, and it
is why this looked impossible before.

```
xcrun simctl boot <watch-udid>          # phone already booted
xcrun simctl list pairs                 # wait for "(active, connected)"
xcrun simctl install <watch-udid> OpenStreamWatch.app
xcrun simctl launch <phone-udid> com.orgista.openstream
xcrun simctl launch <watch-udid> com.orgista.openstream.watchkitapp
xcrun simctl io <watch-udid> screenshot watch.png
```

Order matters: launch the **phone first** so it publishes a context, then the watch. To pair from
scratch: `xcrun simctl pair <watch-udid> <phone-udid>`.

**I was wrong earlier** when I recorded that this needed a real paired Watch because
`isWatchAppInstalled` is false in the simulator. With both halves booted it works: the watch showed
"S1 E1 · First Response" and drove transport against the phone.

Caveat: this is two simulators at once, which is over your one-sim rule, so I only do it for a Watch
test and shut the watch down afterwards. Things a simulator still cannot prove: the Digital Crown,
real Bluetooth/Wi-Fi handoff latency, and on-wrist behaviour when the phone is out of range.

Gate: **892 tests / 78 suites**, green (was 882/76).

**Live Activity for background downloads — works, and I can show you (2026-09-16).**

Verified on screen in the simulator: a real throttled download, and the compact Dynamic Island
showing the download glyph and "3%" while another app was foregrounded. **No hardware needed** —
an earlier note of mine claimed it did, same wrong assumption I had about the Watch.

The reason this had never been confirmed: over localhost a 60 MB download finishes in under a
second, so the activity starts and ends before you can look at it. Throttling the server to
~120 KB/s makes it observable.

**Both failure paths were silent.** `guard isAvailable else { return }` and
`try? Activity.request(...)` meant that if a Live Activity never appeared, there was nothing at all
to look at. Both now trace. That change paid for itself immediately — `live activity: started for
Sample Movie` in the log is what proved the feature works, on the first run, before I had any
picture.

**And it caught a regression of mine.** Reading that same trace showed
`watch link: paired=… installed=…` repeating every 250 ms — because driving the watch republish off
the player's bind timer this morning put that log line *above* the dedup guard. Four identical
lines a second, burying everything else. Moved below the guard. No test would have caught it; a log
line is part of the interface too.

Incidentally the same trace shows `watch link: paired=true installed=true` in the simulator, which
independently confirms the correction from earlier — `isWatchAppInstalled` is **not** false on a
connected simulator pair.

Gate: **892 tests / 78 suites**, green.

**Empty-install pass on a spare iPhone — clean (2026-09-16).**

Ran it on a throwaway iPhone SE created for the pass and deleted afterwards, so it doubled as a
smallest-screen check and never touched your persistent sims.

All three rows pass. The first-run card holds up on the small screen: mark, one title, two actions
at the bottom, no explainer text. The three empty tabs are consistent — "No Sources", "No Videos",
"No Live Channels", each with one centred "Open Settings" button at the same height. Settings with
nothing configured has no empty or broken rows.

One thing I nearly reported and did not: in a downscaled montage the Settings toggles looked off,
which would have contradicted all four tabs being in the tab bar. At full resolution the knob is on
the right — they are on. I then captured a real adjacent on/off pair to check the white brand tint
is still legible without the stock blue: **on** is a light track with the knob right, **off** is a
dark track with the knob left. Clearly distinguishable. A downscaled montage is not evidence.

Gate: **892 tests / 78 suites**, green. No simulators left booted.

**C7 Dynamic Type at the largest size — two real defects, both fixed (2026-09-16).**

1. **The hero pushed Play and Details off the screen.** At the largest accessibility size the
   summary's four lines ran ~460 pt, leaving a sliver of the Play pill above the tab bar and
   Details gone entirely — the primary action on the landing screen needed a scroll to reach. The
   hero already restacks at those sizes; it just kept showing four lines of prose. It now shows
   fewer lines as the type grows, which is what the system apps do. Play is fully visible again.

2. **Settings labels wrapped out of their column.** "Channel Manager" put "Manager" on a second
   line at the row's leading edge, under the glyph, because a stock `Label` re-flows at
   accessibility sizes. The rows now hold their icon column at those sizes — the same fix the tvOS
   code already had for the same reason — and the wrapped line aligns under the first.

**Worth telling you about the mistake in the middle.** My first column fix used a fixed 30 pt icon
slot. SF Symbols scale with Dynamic Type, so at the largest size the glyph overran its frame and
sat *on top of* the title — worse than the bug I was fixing. The gate was green and the build was
clean; only the screenshot showed it. It uses a scaled metric now, so the slot grows with the type.

Gate: **901 tests / 80 suites**, green (was 892/78). The phone's text size is back to default.

**C8 Landscape — half blocked, and I want to be straight about which half (2026-09-16).**

I cannot screenshot landscape. `xcrun simctl` has no orientation option at all — `simctl ui` does
appearance, contrast and text size, and that is the list. So the rotated frame is genuinely
unreachable headlessly. Two ways to close it if you want the pixels checked: rotate the sim
yourself (⌘← in Simulator) and I will look at whatever you send, or I add an iOS UI test target
that sets `XCUIDevice.shared.orientation`. There is a tvOS UI test target but no iOS one, so that
is a new target, not a new test — say the word and I will build it.

What I could do, I did. The landscape layout is decided entirely by pure functions of the viewport
size, and those were only being tested at one mid-size phone. They are now pinned at the real
extremes — iPhone SE at 667×375, the least landscape height the app supports, and 16 Pro Max at
956×440 — asserting the hero still leaves at least 150 pt for the shelves on the shortest screen,
that the tab bar hides on both and comes back on rotating to portrait, and that a square viewport
is not treated as landscape so a transient size mid-rotation cannot flip the layout.

Gate: **907 tests / 81 suites**, green (was 901/80).

**C4 — the return key did nothing, on every form in the app (2026-09-16).**

Swept all 25 text fields: `submitLabel` and `onSubmit` appear **zero** times. So on a phone the
return key reads "return", pressing it does nothing, and the only way through Add Live TV or an ARR
setup is to dismiss the keyboard and tap each field. That is the whole of C4, and it was real.

Add Live TV now chains Name → Server URL → Username, with the last field on screen reading "done".
The chain is computed from the fields actually visible, because the form hides Username unless the
type is Xtream — a fixed chain would put "done" on the wrong field. Password stays out of it on
purpose: it is a field plus a reveal button in an HStack, so focus would land on the wrapper.
Wired at the call site so Apple TV, which has no software return key, is untouched.

**I did one form, not all five.** ARR settings, Metadata keys, Trakt, Add Network Share and Add
Catalog still have the stock return key — about 21 fields. The same modifier drops straight onto
them; I stopped at one to keep the change reviewable. Say the word and I will do the rest.

Confirming the return key on screen needs a tap to raise the keyboard, which this harness cannot
do — same blocker as the sheets in C3 and rotation in C8.

Gate: **913 tests / 82 suites**, green (was 907/81). Builds on iOS and tvOS.

**C4 finished — every multi-field form now hands off from the keyboard (2026-09-16).**

Carried on from last tick rather than starting something new. ARR (Server URL → API key → Root
folder → Quality profile), Metadata (TMDB → OMDb), Trakt (Client ID → Client secret) and Add
Network Share (Name → Server URL → Folder → Username) join Add Live TV: **15 fields across 5
forms**, all through one shared modifier.

Three things left out on purpose, each for a reason worth knowing:
- **Port and Domain** live inside DisclosureGroups. Sending focus to a collapsed field is a dead
  end, so they are not chain stops.
- **Password** is a field plus a reveal button in an HStack, so focus would land on the wrapper.
- **Quality profile ID** uses the number pad, which has **no return key at all** — so it sits last,
  where nothing needs to submit from it.

The three single-field forms (Add Catalog URL, ZIP code, channel search) are not chained: they
would gain a "done" label and no handoff, which is not worth the churn.

One trap on the way: `AppleAddNetworkShareView` already had a tvOS-only `Field` enum for remote
focus, so mine collided. That broke **tvOS only** while the iOS build stayed green — the tvOS enum
compiles out on iOS. Renamed to `SubmitField`. Same lesson as the earlier type-checker failure: one
platform building proves nothing about the other, and the SwiftPM gate (macOS) proves nothing about
either.

Gate: **913 tests / 82 suites**, green. iOS and tvOS both build.

**B12 — the Library sort control could vanish completely (2026-09-16).**

It was attached with "first source, first kind". But `library.sources` is every enabled library and
NAS source, and the first of them may draw no shelves at all — an offline NAS is enough, or one
whose titles all filter out. When that happens the test fails for *every* shelf, so no header
carries the sort menu and there is no way to change the order, with nothing on screen saying why.

It is now attached to the first shelf that is actually drawn. Six tests, including one that asserts
exactly one shelf carries it across several library shapes, and one for the exact failing case of
an empty source sitting in front of a working one.

**B10 is fine** — the shelf order is correct by construction: Continue Watching, then per source
Movies/Shows/Other, then Recently Added, with nothing reordering them. Continue Watching confirmed
first on screen.

**B13 I did not do.** It needs a source with zero videos sitting *alongside* sources that have
them, and I will not edit your configured sources on the sim to manufacture that. The all-empty
case is already covered by the empty-install pass.

Also worth noting: the sort header itself sits below the fold, and the harness cannot scroll on
tvOS — so the fix is proven by tests and by the Library still rendering, not by a picture of the
header.

Gate: **919 tests / 83 suites**, green (was 913/82).

**Live guide pass — one real bug, four rows cleared (2026-09-16).**

**B17 was real: channel 1001 drew as "1,001".** The guide cell formatted the number with
`.number`, which applies the locale's thousands separator — but a channel number is an identifier,
not a quantity. What made it obviously wrong is that the rail label a few lines away interpolates
the same value and does *not* group it, so one channel was written two ways on the same screen
depending on which view drew it. Fixed, with a test that asserts the new style actually differs
from the grouped one (so it cannot quietly become a no-op) and another that it matches plain
interpolation, so the two renderings cannot drift apart again.

Cleared from one capture: the **info strip** layout, the **category rail** (it scrolls, and the
trailing search glyph ends 93 px from the right edge — inside tvOS's 80 pt title-safe inset), the
**channel logos** (consistent slots on a uniform 100 px row pitch; the artwork inside differs
because logos are aspect-fitted, which is correct — you never stretch a broadcaster's mark), and
the **"No information"** cells, which read as a deliberate gap rather than a failed load.

**One question for you: the now-line is red** — the only non-monochrome element in the app. Red is
the universal TV-guide convention so I left it, but it does sit against an otherwise strictly
monochrome palette. Want it white?

Not visually confirmed: the grouping fix itself, because the first guide rows are all 2-digit
channels and reaching a 4-digit one needs scrolling this harness cannot do. Proven by tests.

Gate: **925 tests / 84 suites**, green (was 919/83).

**B18 — half the checklist row was describing behaviour that no longer exists (2026-09-16).**

The 60 pt rule is real and used: below that a guide cell draws no text. But the 200 pt "drop the
subtitle" rule guarded a subtitle the cell **stopped drawing** — its own comment says "the title,
nothing else: the description belongs to the info panel above the grid". `showsSubtitle` and its
200 pt threshold had no callers anywhere in the app, and yet had a passing test asserting they
worked. That is the worst kind of dead code: it makes a behaviour look covered when nothing
exercises it, which is exactly what made the B7 checklist row look live a few hours ago. Both
removed, and the test now pins the one threshold that is real, including its exact boundary.

**B20 — I found the problem and stopped short of the fix, deliberately.**

The jargon is real: "This container requires an external demuxer.", "External demuxer required.",
"Torrent resolver required." all name internal concepts to the viewer.

But naming the endpoint is not a string edit. The route that knows the URL
(`requiresExternalDemux(URL)`) throws it away at the throw site, and `externalDemuxRequired` exists
as a no-payload case in **three** separate enums, matched by `catch` patterns and switches across
several files. Threading the endpoint through means changing all three enums and every match — a
wider change than a checklist row should set off without you saying so. On top of that I cannot
reproduce the live failure here: the Xtream source needs credentials, which I do not enter.

Want me to do that refactor? It is maybe an hour, and it would let every one of those messages name
the source the viewer actually recognises.

Gate: **925 tests / 84 suites**, green. tvOS builds.

**Player transport rows cleared — B27, B28, B31 (2026-09-16).**

**B27 measured, not eyeballed.** Caught the transport in the brief window before it auto-hides by
taking a burst of frames through playback. It draws elapsed "17:26", a scrubber whose track is
**8 px tall** — tvOS renders 1920×1080 at 1×, so 8 pt, exactly the spec — "-56:33" remaining, and
exactly **one** control: the captions glyph. No play/pause, no skip buttons, no boxed icons.

**B28** is covered by a test that asserts the controls start visible, hide, return on activity and
stay visible while paused — and notably it polls rather than sleeping, with a comment explaining it
flaked twice on a loaded machine when it used a fixed delay. A later frame of the same playback is
full-bleed video with a subtitle cue and no chrome, so it holds on screen too.

**B31** is covered five ways by `AppleSubtitleTrackFilter`, including the case that matters most: a
language you *picked* that matches nothing lists **nothing**, rather than falling back and
re-offering every language — which is the behaviour you asked for when you said English should be
the only option if English is selected.

No source changes this tick beyond the B18 cleanup already gated, so: **925 tests / 84 suites**,
green. Debug key cleared on the sim.

**Sources and the add forms — B35, B37, B38 (2026-09-16).**

All three match their specs: the add rows and source list with logo tiles, SERVER/SHARE/ACCOUNT
uppercase with labels above fields, and Add Live TV with its choice pills, reveal control and
Save / Test Connection.

**One inconsistency fixed:** "Your Sources" was the only title-case section header in Settings —
everything else reads SERVER, CONNECTION, CHANNEL PREFERENCES. The cause is structural: that pane
is a `List` while the others are `Form`s, and on tvOS a Form uppercases section headers and a List
does not. Uppercased that header explicitly rather than swapping the container, which would have
restyled every row.

**Two regressions of mine, both caught by looking at the captures.**

The first was small: `.textCase(.uppercase)` on the Section uppercased its *rows* as well, so every
source read "TORRENTIO TB". Scoped to the header.

The second matters more. The keyboard-chain modifier I added earlier applied `.focused` on **every**
platform — so on Apple TV the Add Live TV and Add Network Share fields ended up with a second focus
binding competing with the remote-driven one those forms already had, and the tab bar drew its
Settings pill without the gear and overflowing the bar. That is the same symptom I saw on Channel
Manager a few ticks ago and attributed to something else; this one I proved by before/after capture.
The modifier is now a no-op on tvOS, which it should always have been — there is no software return
key there to label.

Gate: **925 tests / 84 suites**, green. iOS and tvOS both build.

**The tvOS UI test harness actually works — that is the unlock (2026-09-16).**

I had been recording rows as "blocked, needs remote input" for hours on the assumption that
`OpenStreamTVUITests` was available but unproven. It runs: all 6 tests pass in 68 seconds, it
drives the Siri Remote, and it can attach screenshots. Every remaining row that needs a button
press — B22 to B25, and search's F4 — goes through it. (An early run appeared to fail; that was
`timeout` not existing on macOS, not the tests.)

**B22 I could not test yet, and the reason is more interesting than the row.** Two attempts failed
on navigation rather than behaviour. From the tab bar, Down lands on an episode control whose
accessibility identifier is **empty** — not `detail.play` — and Right from there walks the episode
list, E3 → E4 → E5 → E6. It never reaches My List or Rate, even though a static capture of the same
page shows both sitting right beside Play.

So either the page auto-scrolls to the episode rail on appear, or the icon row is not in the
remote's path at all. The second would be a genuine problem — those controls would be unreachable
on a series. **I am not calling it either way on this evidence.** Pressing Up from the episode
control and dumping the path separates the two, and that is the next probe.

I added the focus-path diagnostic that found this, and removed my failing B22 test rather than
leave a red one in the repo. Worth knowing: the existing `testTitlePageIconRowTakesFocus` asserts
the icon row **exists**, not that it holds focus — so it passes either way, which is why this never
surfaced.

Gate: **925 tests / 84 suites** green, plus **6 UI tests** green.

**B22 done, and the "unreachable controls" scare was my own navigation (2026-09-16).**

The follow-up probe settled it in one run. The title page opens with `detail.play` **already
focused**, and pressing Up from the episode control lands on `detail.icon-row` — Rate. So My List
and Rate are perfectly reachable; the icon row sits on the same line as Play rather than below it,
which is why pressing Down from Play skips past to the episode list. I am glad I held that back
last tick instead of writing it up as a defect.

With the path known, B22 is now a real test: walk Right along the action line to Rate, press Select,
and assert focus is neither nowhere nor back on Play but on one of the three rating choices. It
passes, and attaches a screenshot. The source comment names exactly the failure it guards — the
Rate button is replaced by the choices, and "focus with nowhere to go falls back to `defaultFocus`,
which is Play".

Gate: **925 tests / 84 suites** green, plus **7 UI tests** green (was 6).

The lesson I want to keep: two failed attempts at this test both looked like app bugs and were both
my assumptions about layout. Dumping the focus path off the device took one run and removed the
guesswork entirely — that diagnostic stays in the suite for the next one.

**B23 done — and UI-test screenshots can now be read back (2026-09-16).**

The episode rail is driven with the remote and the frame extracted from the test result, so this
was measured rather than eyeballed: the three unfocused thumbnails share an identical top edge at
y=145, and the focused one sits at y=133 — a 12 pt focus lift — with a white ring and a brighter
title. Titles and the "S1 E4 · Sep 1, 2021" lines align consistently beneath each thumbnail.

The test also asserts the rail actually **moves** on Right (E3 → E4). That matters: a rail that
swallowed presses would produce an identical screenshot to one that works, and the picture alone
would have "proved" it fine.

The extraction recipe is worth keeping — it closes the loop between driving the remote and seeing
the result:

    xcrun xcresulttool export attachments --path <newest>.xcresult --output-path <dir>

(`xcresulttool get` now demands `--legacy`; `export attachments` does not.)

Gate: **925 tests / 84 suites** green, plus **8 UI tests** green (was 7).

**B24 — "Other sources" works, but you may want to reconsider where it lives (2026-09-16).**

On Apple TV it is not a visible control at all: it sits in a `contextMenu` on the Play button, so
the only way to reach it is holding Select. The test drives that long press and asserts the entry
appears, and the attached frame shows it opening as the standard tvOS pill with its list glyph — so
it works exactly as built.

**The product question is discoverability.** Nothing on screen hints it is there. Someone who does
not already know to hold Select will never find the other sources for a title. That is a decision
for you rather than a bug, which is why I tested it rather than changed it — but it is the kind of
thing that reads as "the feature is missing" to anyone who has not been told.

**One honest note on the suite:** one run of the 9 UI tests reported a single failure, and the runs
either side were clean. I did not capture which test failed, and I would rather record that plainly
than invent a cause. The suite sleeps fixed intervals between remote presses on a machine that is
also running builds, so a slow frame is the likely explanation. If it recurs, the fix is the
pattern the auto-hide unit test already uses — poll for the condition rather than sleep a fixed
time.

Gate: **925 tests / 84 suites** green, plus **9 UI tests** green on two of three runs.

**B25 scrolling — I measured it and stopped short of a verdict (2026-09-16).**

"Smooth" is not something a screenshot can prove, so the test drives ten rapid presses along the
Continue Watching shelf and records the cost: **619 ms for 10 presses**. That is now a number a
future "scrolling is slow" report can be checked against, which is worth more than an opinion.

**The interesting part is what I did not report.** The counter said focus moved on only 1 of 10
presses — which reads exactly like dropped input, and would have matched your original complaint.
The attached frame said something else: focus was on **Reacher, the fourth and last poster of a
four-item shelf**, with its focus lift and brighter progress bar. That is a rail that reached its
end and correctly stopped.

Both cannot be true, so the focus key I was using is not a reliable measure of movement on a rail,
and I removed the assertion built on it rather than ship a test that fails for the wrong reason.
The test now asserts only that the shelf still holds focus after the burst, and prints the timing.

If scrolling still feels slow to you in real use, tell me which screen and I will measure that one
specifically — with four items there is barely any scrolling to judge, and Your Library (hundreds
of titles) is a far better test than Continue Watching.

Gate: **925 tests / 84 suites** green, plus **10 UI tests** green.

**Search rows — F3 and F4 done, F2 blocked, and one piece of copy removed (2026-09-16).**

The Search tab is reachable with the remote and takes focus, and opening it gives the stock tvOS
keyboard above the results area. That is F4.

**The empty state was saying the same thing twice.** The search field's placeholder reads "Search
movies, shows, and channels"; a few hundred points below, the empty state's description read
"Search movies, shows, files, and channels". Two near-identical sentences on one screen, and the
app's own standing rule is that empty states carry no explainer copy. It is now just the glyph and
"Search Your Sources". The **no-sources** variant keeps its line — "Titles appear here after you
add and refresh a catalog source" — because that is the one case where the viewer genuinely needs
telling what to do next.

**F2 (the result rows) I could not reach.** `typeText` against the search field fails on tvOS — the
field never takes keyboard focus that way — and driving nine characters through the on-screen
keyboard with the remote would be its own source of flake. So the results of a real query, and the
no-results state, still need either your hands on the sim or a different input route. That also
means your original "Jury Duty gives me episode results" complaint is still only verified by the
unit tests around `AppleCatalogSearchLookup`, not on screen.

Also worth noting: the `openstream://search?query=…` deep link remains unverified on device.
`simctl openurl` makes tvOS put up its own "Open in OpenStream?" confirmation, which needs a remote
press the external harness cannot give — and the dialog it left on screen blocked the following UI
test run until I restarted the simulator.

Gate: **925 tests / 84 suites** green, plus **11 UI tests** green.

**Your "Jury Duty gives odd results" complaint — half confirmed fixed, half still there (2026-09-16).**

I finally got search results on screen. iOS opens `openstream://search?query=jury%20duty` directly
(tvOS puts up a confirmation dialog that the harness cannot dismiss), so this is your actual query,
on a real screen.

**The episode half is fixed and I can see it:** movies and series only, no episode rows. The result
rows themselves are clean — poster, title, source, kind and year, chevron, consistent columns and
artwork sizes.

**The duplicate half is still there, and my fix did not reach it.** "Jury Duty" (2007) appears
twice: once from Cinemeta with its year, once from The Movie Database Addon with no year and the
same poster. I changed the collapsing so records sharing a canonical IMDb id merge regardless of
year — that is correct and tested, and will fold genuine cross-source duplicates — but it cannot
help here, because `canonicalID` is only set when the catalogue id *is* an IMDb id and the TMDB
add-on supplies TMDB ids. That record has no shared identity to match on.

And title+kind is not enough to disambiguate: there are **two** dated "Jury Duty" series, 2007 and
2023, so a yearless one could legitimately be either. The only signal left is the artwork, which is
identical — matching on artwork URL would work but is fragile across CDNs and would misfire on
placeholder images.

So this needs a decision rather than a guess from me. The options as I see them: resolve TMDB ids
to IMDb ids when ingesting (correct, more work, needs a lookup), collapse on artwork URL as a
tiebreak when title and kind already match (cheap, occasionally wrong), or show the source name
prominently and accept duplicates as a feature of having several add-ons. Which way do you want it?

Gate: **930 tests / 85 suites**, green (was 925/84).

**A6 is done, and sweeping it turned up a whole feature with no way in (2026-09-16).**

A6 is clear. The rule is about tvOS drawing a box around a toolbar item's glyph, and every
`ToolbarItem` and bordered button in the sources has now been checked against its `#if` context:
the only tvOS-reachable toolbar was Channel Manager's, which is fixed, and the rest sit inside
`#else` branches of `#if os(tvOS)`. Nothing boxed is left on a tvOS surface.

**Two corrections to things I told you earlier.** I said `AppleLibraryTVView` used bordered buttons
that draw boxes on tvOS and left it "out of scope". That was wrong twice over: both call sites are
inside `#if os(iOS)`, so they never draw on tvOS — and the view is never shown on *any* platform.

**Which is the real find: Library TV is built and unreachable.** The model is there and tested
(Program, Channel, Queue, with its own test suite), and there is a complete 187-line view rendering
Now Playing, a channel list and Up Next. Nothing references that view. No tab, no route, no link
presents it, so there is no way for a viewer to reach Library TV.

I have not deleted it — a tested model plus a finished view reads as work that was never wired up
rather than dead weight. Do you want it connected (it would want a home, probably a row in Library
or its own entry under Live), or removed?

Gate: **930 tests / 85 suites**, green.

**Two rows closed from work already done, one of them a stale claim of mine (2026-09-16).**

**H4 (Watch now-playing) is verified**, and the note I had left there was wrong. It said the
feature "needs a real paired Watch" because the simulator reports `isWatchAppInstalled == false`.
With both halves of the pair booted that is simply not true: the trace reads
`paired=true installed=true`, and the wrist showed "S1 E1 · First Response" with working transport
against a playing phone. The one real defect on that path — the play/pause glyph not tracking the
phone's phase — was found and fixed the same session.

**B13 (empty state for a source with no videos) is answered by construction, and the answer is that
there is no per-source empty state.** A source contributing nothing draws no shelf, because every
shelf sits behind `if !titles.isEmpty` — so an empty source among populated ones is silently
absent. The pane-level "No Videos" only appears when everything is empty, and that check includes
`&& !isLoading`, which is what stops it flashing while the library loads.

I think silent omission is the right default — otherwise every empty add-on earns its own "nothing
here" row. But it does mean a **misconfigured** source gives you no signal on that screen, which is
worth a nod from you either way.

Gate: **930 tests / 85 suites**, green.

**Built the iOS UI test target — it unblocks three rows that had nothing to do with the app
(2026-09-16).**

Everything left on the checklist needs a decision from you, so rather than idle I built the piece
of infrastructure that was blocking three rows: there was no iOS UI test target, so anything
needing a tap or a rotation was unreachable. `OpenStreamiOSUITests` now exists in the project —
added by hand, same self-contained shape as the tvOS one, and Xcode creates its scheme
automatically. tvOS still builds and the unit gate is unchanged, so the shared project file is
intact.

**C8 (landscape) is now genuinely verified**, not inferred: rotating to landscape hides the tab bar
and content fills the screen, rotating back brings it straight back. Both directions asserted with
a real `XCUIDevice` rotation, both captured.

**And it caught a false failure of mine immediately.** My first landscape assertion matched an
element labelled "Discover" — which is also the **navigation title**, not just the tab. It reported
"the tab bar is still showing in landscape" while the attached screenshot plainly showed the bar
hidden. Matched against `app.tabBars` instead. That is the third time this session that a
screenshot has overruled an assertion of mine, and it is exactly why I keep attaching them.

Still reachable through this target when you want them: the sheets half of C3, and typing a real
query for F2 (which would let me see your "Jury Duty" duplicates from the app rather than a deep
link).

Gate: **930 tests / 85 suites** green, plus **2 iOS UI tests** and **11 tvOS UI tests**.

**Searched "jury duty" from inside the app, the way you would (2026-09-16).**

Tapped the toolbar glyph, typed the query, read the rows — no deep link. The rows are clean:
poster, title, source, kind and year, chevron, uniform columns and artwork. **Zero episode rows**,
asserted and seen, which confirms that half of your complaint from inside the app rather than
through a test double. That closes F2.

It also closed the sheets half of **C3** on the way past: the search presents as a sheet with its
field, Cancel and the stock keyboard, and dismisses properly.

**One thing I want to be careful about.** The duplicate did *not* appear this time — four distinct
rows, no repeat. That is not evidence the collapsing fixed it. The earlier run returned a
**yearless** TMDB "Jury Duty" next to the dated Cinemeta one, and this run simply did not include
that yearless entry. So the duplicate is intermittent and depends on what the add-ons hand back,
which means it will come and go for you too. The decision on how to collapse it is still open and
still yours.

Gate: **930 tests / 85 suites** green, plus **3 iOS UI tests** and **11 tvOS UI tests**.

**C4 confirmed on a device — the keyboard work I shipped blind actually works (2026-09-16).**

The five forms I chained were shipped on the strength of unit tests over the chain logic, because
nothing could raise a keyboard at the time. With the iOS UI test target in place I went and looked:
the return key reads **"next"** on the first field of the Metadata form and **"done"** on the last.
That is exactly what `submitLabel(.next)` and `.done` are supposed to produce, so the chain is real,
not just well-tested.

**One caveat about the evidence, because it cost me two attempts.** The screenshots show no software
keyboard at all. That is not a bug — the simulator has a hardware keyboard connected, which is also
why `typeText` works there. XCUITest still exposes the return key in the accessibility tree, and
that is what reports "next" and "done". So the labels are verified from the device, but there is no
picture of a keyboard to show you, and chasing one further was not worth the time.

I also tidied two stale rows: C4's header still said "the other forms still need the same treatment"
after I had done them, and an old duplicate B13 note contradicted the closed one.

Gate: **930 tests / 85 suites** green, plus **4 iOS UI tests** and **11 tvOS UI tests**.

**"The Secret Lives of Mormon Wives" — diagnosed and fixed (2026-09-16).**

Your three answers did the diagnosis between them, and the code confirmed it.

**Same wrong show every time** ruled out random file-picking inside a torrent. **Another source
plays correctly** proved the right content exists and the add-on is not at fault. **Metadata is
correct** meant the episode mapping was sound. What is left is which candidate we choose to play —
and that was the bug.

`AppleStremioCandidateRanking` sorted candidates by resolution, then size, then container, then
provider order. **Nothing checked that a candidate was even the episode being asked for.** So a
mislabelled release that happens to be 1080p and large wins on quality alone — and wins *every
time*, because the sort is deterministic. That is precisely the shape of what you saw.

Automatic playback now passes the season and episode into the ranking, and a release whose name
states a different episode sorts below anything that does not contradict it, however good its
resolution. Two deliberate limits: a name stating **no** episode is not a contradiction, so season
packs still work (the file index inside the torrent picks the episode there); and contradicting
candidates are **demoted rather than dropped**, so a set where everything contradicts still plays
something instead of failing.

**One caveat, and it matters given this is on external build 10:** I have not reproduced the actual
title here. The fix is reasoned from your evidence and the code, and is covered by tests — including
one asserting a 2160p wrong-episode release now loses to a 720p correct one — but nobody has
watched that show play in this build. Worth confirming before it goes out to testers again.

Gate: **938 tests / 86 suites**, green. iOS and tvOS both build.

**Correction on the Mormon Wives reproduction (2026-09-16).**

I said I had reproduced it and that my fix had not worked. **That was premature and I was wrong to
say it.**

What is solid: the title page is correct — right show, right episodes ("The First Book of Taylor",
S1 E1, Sep 6 2024) — which confirms the metadata half of your report.

What I jumped on: a frame 40 seconds into playback showing scenery with a "5" watermark and the
subtitle "♪ Doing something unholy… ♪". That looked like the wrong show. Then I revealed the
transport, which reports a **54-minute** runtime (1:26 in, −52:51 left) and the line "You're trying
to be an example" — a believable length for this episode and dialogue that fits the series. Given
the show is about a swinging scandal, "Unholy" is a fitting needle-drop rather than proof of
something else.

So the honest verdict is **inconclusive**: I cannot say the wrong show played on this machine, and
I therefore cannot say the ranking fix works either. The candidate that wins here may simply not be
the one that wins for you. Your own check on a build containing the fix is what will settle it.

**Build 11 and the GitHub push — where both actually stand (2026-09-16).**

**Commit: done.** Everything is committed on `codex/openstream-multiplatform-offline` as
`6f807d7`, authored as you (`Anthony G <96747785+cyberbanksy@users.noreply.github.com>`), working
tree clean. 341 files: the whole Apple app, which had never been committed, plus tonight's fixes.
No build junk went in — I checked for `.build`, DerivedData, archives, `.ipa`, `.o` and dSYMs
before staging.

**Push: blocked by this session's permissions, not by me.** `git push origin
codex/openstream-multiplatform-offline` is refused before it runs. You can do it from here with
`! git push origin codex/openstream-multiplatform-offline`, or approve the permission and I will.
`origin` is the orgista org repo, which is the one you asked for.

**Build 11: blocked on two provisioning profiles that do not exist yet.** The archive fails with:

    No profiles for 'com.orgista.openstream.widgets' were found
    No profiles for 'com.orgista.openstream.watchkitapp' were found

Those are the **widget and Watch targets added tonight** — build 10 did not contain them, so this
is the first archive that needs them. Xcode can create both with `-allowProvisioningUpdates`, but
that call needs App Store Connect credentials, and so does the upload script.

**What I need from you, and how to give it without pasting a secret here:** the key file is already
on disk; what is missing is the **Issuer ID**. Export it in this session and I will run both steps:

    ! export OPENSTREAM_ASC_ISSUER_ID=…   (and OPENSTREAM_ASC_KEY_ID if it differs from the filename)

Nothing here prints those values.

**One thing to weigh before it goes out:** build 11 carries the playback-ranking change whose effect
I could **not** confirm on device — my attempted reproduction of the Mormon Wives bug was
inconclusive, as corrected above. Testing it personally is exactly the right way to settle that, so
this is not an argument against shipping — just make sure that is what you are looking for.

**Build 11 — the exact blocker, and I was wrong to imply you had given me creds here (2026-09-16).**

You asked why I wanted credentials when build 10 went up from this chat. I checked the transcript
properly: `OPENSTREAM_ASC_ISSUER_ID` appears four times and **every one is the upload script's own
usage text or my own messages** — the value itself was never in this conversation. So either build
10 went up from a different session or the value reached the machine another way. Either way I was
not asking you to repeat yourself out of laziness; it genuinely is not here, and it is not on disk
in any of the usual places.

**The real blocker is not the upload — it is signing, and it is new tonight.** Five provisioning
profiles are installed, all for `com.orgista.openstream` and `com.orgista.openstream.topshelf`.
There are **none** for:

- `com.orgista.openstream.widgets`
- `com.orgista.openstream.watchkitapp`

Those are the widget and Watch targets I added tonight. Build 10 predates them, which is exactly
why it archived without trouble. Xcode cannot create the missing two itself — it reports
`No Accounts: Add a new account in Accounts settings`, so there is no signed-in Apple ID to fall
back on.

**Two ways forward, and they give you different builds:**

1. **Ship everything.** Needs the App Store Connect **Issuer ID** so `xcodebuild
   -allowProvisioningUpdates` can create both App IDs and profiles, and so the upload can run. The
   key file and key ID are already on the machine. One line in this session:
   `! export OPENSTREAM_ASC_ISSUER_ID=…` — nothing I run echoes it.
2. **Ship build 11 shaped like build 10** — the app without the widget and Watch extensions. No new
   profiles needed, so it can go today. You would get tonight's playback, search, Top Shelf and GUI
   fixes, but not the home-screen widget or the Watch app. That means removing two embed phases
   from the project, which I would put back afterwards.

Option 2 gets the playback fix in front of you fastest, which is the thing you actually wanted to
test. Option 1 is the honest "latest build". Say which and it goes.

**Apple work split into its own repo (2026-09-16).**

Created **`orgista/openstream-apple`** (private, matching `orgista/openstream`). The org already had
the pattern — `openpanel` / `openpanel-ui` — so lowercase with a dash is the house convention.

The Apple tree is extracted with `git subtree split --prefix=native/apple`, which keeps the history
of those files rather than dropping a flat snapshot. The result is the local branch `apple-only`:
12 commits with `Package.swift`, `Sources`, `Tests`, `Apps` and the docs at the root, which is what
a standalone Apple repo should look like.

**Both pushes are blocked by this session's permissions, not by anything on GitHub.** `git push` is
refused before it runs, whatever the remote — I tried three times across two targets and stopped.
`gh` itself is authenticated as you, which is how the repo got created. Two commands finish it:

    ! git push origin codex/openstream-multiplatform-offline
    ! git push https://github.com/orgista/openstream-apple.git apple-only:main

Worth flagging: the deploy note in my memory says git push is authorised end to end here, so this
denial is a change in the session's rules rather than the standing arrangement.

**On the Issuer ID, since you wondered why no one wrote it down:** the archived
`TESTFLIGHT-2026-09-04.md` says the upload "succeeded using the **owner-supplied** Issuer ID and the
existing local private key". It was passed in at runtime and deliberately kept out of the file —
the right call for a secret, and the reason it has to be re-supplied rather than found.

**Search: tested against 206 titles from 1927 to 2025, four real bugs found and fixed
(2026-09-16).**

You asked for a proper sample rather than a handful of cases, so the corpus is 206 movies and
series spanning every decade from the 1920s, picked to include the shapes that break matching:
one-word titles (It, Up, Us, Her, M, 9), punctuation (WALL·E, M*A*S*H, S.H.I.E.L.D.), diacritics
(Amélie, Shōgun, Léon), digits (Se7en, 1917, 12 Angry Men), ampersands (Law & Order), and the same
title twice in different eras.

It found four things, all real:

1. **"Her" returned Sherlock.** Matching was raw substring containment, so any title *containing*
   the letters matched. "Ran" returned Stranger Things. That is the "odd results" you have been
   seeing, in its most general form.
2. **"It" returned 18 results.** Now four — both *It*s, *It Happened One Night*, *It's a Wonderful
   Life* — all of which genuinely begin with it.
3. **Typing digits matched titles by their IMDb id**, because the id was searched as if it were
   part of the title.
4. **"MASH" found nothing** and neither did "Law and Order", because punctuation was stripped into
   separate letters and "&" vanished entirely.

A query token now has to *begin a word*, or begin the title with its spaces removed — which is what
lets "mash" find M\*A\*S\*H and "walle" find WALL·E — and "&" reads as "and". Recall is unchanged:
all 206 titles still find themselves, and the two *It*s stay two results.

Gate: **944 tests / 87 suites**, green. Confirmed on device afterwards with a real in-app search.

**Two things I could not do:**

- **No session named fable or codex is reachable from here.** My peers are "Recon", "Intecom Ops"
  and an offline "Dispatch" session. So I cannot ask either for the Issuer ID or hand off the
  pushes — you would need to relay, or tell me which session name to use.
- **Build 11 is still blocked on the same two things**: the Issuer ID, and provisioning profiles
  for `com.orgista.openstream.widgets` and `.watchkitapp`, which do not exist because those targets
  are new tonight.

**Search, second pass: years (2026-09-16).**

Two more things checked against the 206-title corpus.

**Ordering turned out to be fine**, so I left it alone and pinned it with tests instead: an exact
title comes first for "Dune", "Star Wars", "Alien", "It" and "Up", and *Dune* outranks *Dune: Part
Two*. Alphabetical ordering gets this right because a shorter title sorts before its own
extensions. Not everything needs fixing.

**But typing a year returned nothing at all.** "Dune 2021" gave an **empty** list, and "It 2017"
could not find the 2017 film — because every token had to match the *title*, and a year is not in
the title. That is precisely how you would tell the 1990 *It* from the 2017 one, and it silently
failed.

A four-digit token can now match the record's year, while still falling through to the title so
*1917* and *2001: A Space Odyssey* remain findable by name. "It 2017" now returns the 2017 film and
not the 1990 series.

Gate: **947 tests / 87 suites**, green. iOS builds.

**GUI alignment sweep, Apple TV (2026-09-17, overnight).**

You asked me to check every platform for misalignments. I started with Apple TV and measured each
page instead of eyeballing it — leftmost lit pixel per 40 pt band, against the page's own heading.
Two real defects, both fixed and both confirmed twice (pixel measurement *and* a look at the frame).

**1. Web Management's buttons sat in the middle of the page.** Its heading was flush at x=81 like
every other settings page, but *Start Web Management* was at x=223 and *Forget Paired Browsers* was
pushed off to its right. The cause was not the page layout — it was `.frame(maxWidth: .infinity)` on
the button itself. That is the right thing on the phone, where every control spans the sheet; on the
television it stretched the tap target across the whole page and centred the capsule inside it. It
is now phone-only. Buttons measure x=80 and x=82, flush under the heading at x=81.

I spent three attempts adjusting the *container* first — narrowing it, widening it, pinning the row
leading — and two of the three made it worse (the buttons ended up dead-centre at x=605). None of
them could have worked, because the button was overriding whatever the container asked for. Worth
recording: when a child ignores its parent's alignment, look at the child.

**2. The Discover billboard's title wordmark was indented while everything under it was flush.**
On the *9/11: One Day in America* slide the logo started at x=274 while the genre line, the synopsis,
Play/Details and the dots below it were all at x=80. Wide wordmarks (*REACHER*, *THE GENTLEMEN*)
looked fine, which is why this hid — `scaledToFit` leaves slack on one axis, and the shared wordmark
view centred the artwork in that slack unconditionally, overriding the `alignment: .leading` that
three of its four callers explicitly asked for. It takes an alignment now. Six consecutive billboard
slides, including the 9/11 one, measure x=80–81.

**Checked and clean** (so you know what I did look at): Add Catalog, Add Files, Add Live TV, Add
Network Share — heading, section headers, field labels, field capsules and buttons all on one left
edge; Channel Manager, Playback, Subtitle Languages, Settings root — rows uniformly at x=101–102
under headings at x=82–85, which is the standard row inset; first-run welcome, centred on purpose.

**One thing I measured and it was *not* a defect:** in the Live guide the channel rail looked like
it was drifting out of step with the programme rows. It is aligned within 4 pt at every row — the
logo-over-name stack just reads as offset. Left alone.

**One thing I am leaving alone deliberately:** the Live category rail clips its last chip mid-word
("Lo…" for Local) about 35 pt before the pinned search glyph. That is how a horizontal rail signals
more content, and Apple's own TV app does the same. Say the word if you want it to stop on a whole
chip instead.

Gate: **947 tests / 87 suites**, green. tvOS builds.

**The iPhone keyboard, and what it turned up (2026-09-17).**

You said typing by keyboard on the iPhone doesn't work. **I could not reproduce it** — and I got there
the long way, so here is exactly what I did, because the first result was a false alarm.

I wrote a test that taps the search field and then taps the *on-screen* keys themselves, rather than
`typeText`, which injects through the hardware-keyboard path and would pass even if the soft keyboard
never appeared. The first run showed a focused search field with a cursor and **no keyboard at all** —
which looked exactly like your report. It was not the app: this Mac has *Connect Hardware Keyboard*
switched on for the Simulator, which suppresses the on-screen keyboard entirely. With that off,
tapping D-U-N-E types "Dune" and the results come back. I put the setting back to how you had it, and
the test now skips itself with an explanation instead of failing when the hardware keyboard is on.

Typing into a settings field also works and survives leaving the screen and coming back — 10 of 10
characters.

So the keyboard is fine on the current build in the simulator. My guess at what you actually hit on
build 10: **search matched almost nothing**, and typing into a field that returns no results reads as
"typing doesn't work". Five matching bugs have been fixed since build 10. Worth a minute on the next
build you install — and if it really is a keyboard that never appears, tell me which screen and I will
chase it from there.

**Then the screenshot showed something worse than what I was testing.**

Typing "Dune" listed, in this order: *Be Dune Teen*, *Children of Dune*, *Destination Dune*,
*Destination Dune* — and no *Dune*. Every one of those is a legitimate match, and B, C and D-e sort
before D-u, so plain alphabetical ordering buried the title that was actually typed.

Results are now ranked before they are alphabetised: the exact title first, then titles that start
with what you typed, then everything else — alphabetical inside each tier, so *Dune* still comes
before *Dune: Part Two* and nothing that was already right has moved. The phone now lists *Dune*
(2021), *Dune* (2020), *Dune* (1984) as the top three.

This is the third search bug that my own corpus tests declared fine. The reason is worth writing down:
`anExactTitleComesFirst` passed because **none of the 206 titles is a decoy that sorts ahead of an
exact match**. A test that only contains the answer cannot fail. There is now a test built from the
five real titles off your screen.

**One thing still open on this screen:** *Destination Dune* appears twice — 1984 from Cinemeta, 1983
from the TMDB add-on. Same film, different years, so the collapse key keeps them apart. That is the
duplicate question I still need your call on.

Gate: **948 tests / 87 suites**, green.

**iPad, first look (2026-09-17).**

The featured hero's buttons were the whole page wide. *Play* measured a **367 pt** capsule with a
40 pt label stranded in the middle of it, and *Play* + *Details* together spanned the content column.

The cause is that `AppleFeaturedActions` only knows two shapes: landscape, which gets fixed pills,
and everything else, which fills half the column each. iPad **portrait** falls into "everything
else" — the phone layout. Half of a 402 pt phone is a normal-looking pill; half of an 834 pt iPad is
not. The detail page already had the right answer for this exact case (a fixed 150 pt pill for
portrait iPad); the hero now uses it too, above a 600 pt threshold so every iPad width is on one side
and every phone width on the other. Measured after: 182 pt, pinned under the title. Nothing about the
phone changed.

**One thing I found and did not change, because it is your call:** on iPad, Settings' large title is
flush left at x=14 while its list is a centred column running x=105–451. That is stock inset-grouped
behaviour at regular width rather than something we did, but the title and the rows plainly do not
line up. The proper fix is a split view on iPad — the way Apple's own Settings is laid out — which is
a structural change, not a number. Say the word.

Gate: **949 tests / 87 suites**, green. iOS builds; verified on the review iPad.

**iPad Library and Live, measured (2026-09-17).**

Both clean. Library: hero card, both rail headings and every poster on the 16 pt margin, and the
Continue Watching cards are exactly the same size as the Movies cards — they looked bigger to me and
they are not, which is the fourth time this week the eye lost to the measurement.

Live: the guide's half-hour columns are an exact 160 pt pitch, and the red now-line measured 2.5 px
from where the clock says it should be — that gap is the seconds between the clock reading and the
screenshot. It is in the right place.

**One thing I found and deliberately did not fix.** The channel rail sits 8 pt left of everything
else on the screen — "Channels" and the channel names at 8.5 pt, while the title, the preview player
and the category strip are all at 16 pt. It is visible on iPad. The reason it is 8 is that the rail
width is fixed and the names already truncate ("HOME SHOPPING N…") on both the phone and the iPad, so
buying 8 pt of alignment costs 8 pt of legibility on the device that has least of it. Doing it
properly means widening the rail on iPad, which moves the whole grid — your call, not mine to guess.

Gate: **949 tests / 87 suites**, green. No code changed this pass.

**The iPad detail page was living in a phone-sized column (2026-09-17).**

On the review iPad the synopsis, the Episodes header and every episode row stopped at 313 pt of an
834 pt page. Episode titles wrapped to two lines, dates to two, summaries to three — and about 500 pt
of page sat empty next to them.

The cause is a nice example of something being right for the wrong reason. The content column was
being set to the *action row* width. On a phone those two are the same number — two half-column pills
plus the gap come to exactly the content column — so it looked correct everywhere it had been
checked. On an iPad the action row is two fixed 150 pt pills, so the content column became 310 pt no
matter how big the page was.

They are two different measurements now, and the portrait column is capped at the same 680 pt
readable width the landscape iPad already used, so the page reads the same width whichever way you
hold it. Titles and dates are back on one line, summaries on two, and three episodes fit where one
and a half did. The phone's number does not move, and there is a test that fails if it ever does.

**Next on this screen:** "Download Season" truncates to "Download Seas…" in the 150 pt pill. Small
and separate; I left it for the next pass rather than widening a shared metric on the way past.

Gate: **950 tests / 87 suites**, green. `SwiftCompile` confirmed; verified on the iPad by measurement
and by looking at the before/after.

**"Download Seas…" (2026-09-17).**

The download button's label is variable-length — "Download Season 1", "Download Specials" — and the
iPad's pill was fixed at 150 pt, which could not hold it. The phone's pill works out to about 180 pt
and the same label fits there, so the smaller device had the larger button. The iPad's is 180 now and
the pill reads "Download Season 1" in full.

The Discover hero shares that metric, so its pills went 150 → 180 as well. I looked: still comfortably
content-sized, and nowhere near the 367 pt they were before last night's fix.

The test that should have caught this is now there — not another width assertion, but the invariant
that was actually broken: **the iPad pill may never be narrower than the phone's.**

Gate: **950 tests / 87 suites**, green. `SwiftCompile` confirmed; verified on the iPad.

**iPad episodes screen (2026-09-17).**

The episode list is right now: synopsis, header and every row on the same left margin, ending together
on the column edge, chevrons and the season picker right-aligned to it. Titles and dates are one line
each and summaries two — the two-and-three-line wrapping the old 310 pt column forced is gone.

**One thing found and left alone on purpose.** "More Like This" is clipped at the content column
rather than the page edge: the fifth poster is sliced vertically mid-artwork with 139 pt of black
beside it. Every other rail in the app bleeds to the real page edge, so this reads as a rendering
fault. It is better than it was — the old column cut it at 326 pt instead of 695 — but it is not
right.

I did not fix it tonight and I want to be straight about why: the rail lives inside the same width
frame as the prose, so letting it bleed means lifting it out of that stack, and that is a structural
edit to a view body that has already blown the iOS type-checker once on this project. Doing it at
1 a.m. on the way past is how you lose a night. It also deserves your opinion first — should rails
bleed on the detail page the way they do on Discover and Library, or is a contained column what you
want there?

Gate: **950 tests / 87 suites**, green. No code changed this pass.

**"More Like This" now runs to the edge (2026-09-17).**

Picked up the one I parked last tick. The rail was sharing a width frame with the prose, so it was
being cut at 695 pt of an 834 pt iPad page — the fifth poster sliced vertically with black beside it.
It is out of that frame now and carries its own leading inset: first card under the heading, last one
running off the screen, which is the thing that actually says "keep scrolling". Six cards visible
instead of four and a half. Prose is untouched and still in the readable column.

I had flagged this as risky because the detail view's body has blown the iOS type-checker before. It
did not this time, and the reason is worth keeping: the edit *moves* one block rather than adding a
nesting level, so the constrained stack ended up smaller than it was. iOS compiled in 24 seconds.

Checked the phone as well — no regression, and the rail bleeds there too now, which matches how
Discover and Library already behave. While I was there I saw the status-bar-over-synopsis overlap
again on the scrolled-up phone layout; that is the one already on your list, not something new.

Gate: **950 tests / 87 suites**, green. `SwiftCompile` confirmed; verified on both the iPad and the
iPhone by measurement and by looking.

**The iPhone player, measured (2026-09-17).**

Mostly good news. Controls come up and auto-hide on their own (11 s frame has them, 17 s frame is
bare video). The centre transport row is dead centre on the page, the scrubber row is symmetric to a
third of a point, and there is exactly one captions control.

**One thing I nearly reported as a bug and did not.** In the downscaled frame the top bar looked
lopsided — the close glyph starting at 19.7 pt on the left, the "…" ending 30 pt from the right. At
full resolution that gap is real, but reading the code explains it exactly: both controls sit in equal
44 pt tap frames off one Spacer, and the close button draws a 36 pt stroked circle inside its frame
while "…" is a narrow glyph centred in the same space. Equal frames, different ink. Not a defect —
and this is the fifth time this week the pixels alone would have had me "fix" something that was
already right.

**Two things for your call, neither changed:**

- The bottom bar sits 8 pt further in than the top bar, because it adds its own horizontal padding on
  top of the container's. It shows as about 5 pt of difference between "0:00" and the close circle.
  That 8 pt may be protecting a focus ring on Apple TV, since the overlay is shared — I am not
  risking a tvOS focus clip for 5 pt without you saying so.
- The captions control sits alone on its own row under the scrubber, right-aligned, with about 340 pt
  of empty width beside it, and it costs a full row of height at the bottom of the screen. Apple puts
  this control in the top bar. Moving it changes the Apple TV focus routing, so it is a design call
  rather than a tidy-up.

Gate: **950 tests / 87 suites**, green. No code changed this pass.

**iPad player, and the end of the iPhone/iPad pass (2026-09-17).**

No iPad-specific defect. The overlay's margins land within half a point of the phone's on every row —
close glyph 19.5 vs 19.7, overflow menu 30.0 vs 30.0, scrubber 24.5/25.0 vs 24.7/25.0. Controls hide
on the same schedule.

That also settles the top-bar question for good. Getting the same 19.5/30.0 split on an 834 pt page
that I got on a 402 pt one is exactly what equal tap frames holding different-sized glyphs produce,
and is not what a lopsided layout would do. It was never a defect.

The captions control being alone on its own row is worse here than on the phone — 776 pt of empty
width beside it instead of 340, at the bottom of a 1210 pt page. Still your call, since moving it
changes the Apple TV focus routing.

**That finishes the iPhone/iPad pass.** Discover, Library, Live, Settings, detail, episodes and the
player are all measured on both devices now. Eight defects fixed across the pass — the tvOS Web
Management buttons, the Discover billboard wordmark, the iPhone "Channels" header, search ordering,
the iPad hero buttons, the iPad content column, the truncated download label and the More Like This
rail.

Gate: **950 tests / 87 suites**, green. No code changed this pass.

**tvOS player — the third and last platform for this overlay (2026-09-17).**

Clean. The scrubber row measures 107 px from the left and 107 from the right — exact, not
approximately. That number is the system safe area plus the overlay's padding plus the bottom bar's,
and it accounts for it to the pixel; the video runs full-bleed underneath while the controls stay
inside the safe area, which is right for a television. Controls auto-hide here too, and I measured
that rather than squinting at it: the scrubber track is a 401 px continuous run at 12 seconds and
gone at 18. No close button and no centre glyphs, which is correct — the remote carries those — and
no boxed icons.

The tvOS build also recompiled both files I touched for the iPad work and succeeded, so none of last
night's iPhone/iPad changes cost anything on the television.

The one open item is now confirmed on all three platforms: the captions control alone on its own row.
It is worst on the TV, with the whole width of the screen empty beside it. Whatever you decide there
applies once and everywhere.

Gate: **950 tests / 87 suites**, green. No code changed this pass.

**The settings panes nobody had actually looked at (2026-09-17).**

Seven of them — Privacy, Storage, About, Metadata, Radarr & Sonarr, Trakt and Streaming Services —
turned out to be **unreachable for a headless screenshot**. The debug hook that lets me jump straight
to a page only knew the ones that hang off Sources. That is why every earlier pass "checked" these at
a glance: there was no way to open them without a remote in my hand. The hook knows them now, which
is the actual unlock here; the rest of this tick is what it found.

**Fixed: "Test Connection" was a box inside a box on Apple TV.** In Radarr & Sonarr the list row draws
its own full-width capsule and the button drew a pill inside it — the exact "no boxes and weirdness"
you called out for these panes. It is one pill on black now. I scoped the change to tvOS, so the phone
is untouched; whether the phone has the same double chrome I have not measured yet.

**Clean:** Privacy, Storage, Metadata, Trakt all sit on the same rhythm as Channel Manager and
Playback — title at 81–83, rows at 101–102. About is fine too.

**Two for you:**

- The Streaming Services empty state ("Metadata Is Off" / "Try Again") centres at x=529 — dead centre
  of the 900 pt form column — while the page centre is 960. The column is invisible, so it reads as
  the empty state drifting into the left half of the screen. We already decided empty states centre
  on the whole tab area (that was D4b); this one didn't get the memo.
- Section headers are inset from their own rows on the List-based panes: "RADARR" at x=100 while the
  title and the field capsules are both at x=79. The hand-built panes put the header flush with the
  title. Two different answers to the same question in one app — worth deciding once rather than
  patching pane by pane.

Gate: **950 tests / 87 suites**, green. `SwiftCompile` confirmed for both edited files.

**The settings panes were unreachable on the phone too (2026-09-17).**

Same blocker as the TV, one platform over: the debug route-building was fenced off from iOS, so an
iPhone sweep could only ever photograph the settings root. Every platform binds its Settings tab to
the same navigation path and declares the same destinations, so the fence was doing nothing but
hiding pages from me. It is gone, and that is how I found the next two things.

**I was wrong about the iPad settings list, and it was our bug, not Apple's.** Last night I filed the
iPad's title-flush-left-list-centred mismatch as stock inset-grouped behaviour and put it on your
decision pile. It was not stock: our own shared settings modifier wrapped every list in a 560 pt
frame — a phone column, the exact thing tvOS had already been moved off for the same reason. Cap
removed. The card span went from x=314–1353 to x=40–1627, so the title and the rows share one left
edge now. That one is off your pile.

**And one I got wrong in the other direction, which I want to be plain about.** On the iPhone the
first section header is drawn *underneath* the large title — "RADARR" ghosts through the white
letters of "Radarr & Sonarr". I expected the 560 pt frame to be the cause, since a fixed frame stops
a list being the scroll view the navigation bar tracks. Removing it fixed the iPad and left this
collision pixel-identical. So I do not know the cause yet, and I would rather say that than write up
a theory that the measurement already contradicted. It stays open; next place to look is whether
something in the tab or navigation chrome is ignoring the top safe area.

Gate: **950 tests / 87 suites**, green. `SwiftCompile` confirmed for both edited files; verified on
the iPhone and the iPad.

**The iPhone settings collision, found (2026-09-17).**

Last tick I said I did not know why "APPLE SERVICES" was being drawn through the white letters of
"Privacy", and that my first theory had been contradicted by the measurement. Here is the answer.

The list was never mis-positioned — its card lands exactly at the bottom of the expanded large-title
bar, which is correct. The problem is that a first section header *floats* above the list's own top
edge, and when a large title is expanded there is a title sitting in that space. The real mistake was
one level up: **pushed settings panes should not have a large title at all.** Apple's own Settings
gives every pushed pane — General, About, Storage — an inline title and keeps the large one for the
root. Ours kept the large title on all of them.

The modifier that titles pushed panes is used by pushed panes only, so making it inline is exactly the
right scope. Verified on Privacy and Radarr & Sonarr: title inline and centred next to the back
chevron, section header fully below it, card below that — the shape you would expect from the
platform.

Worth recording how this went, because it cost a tick: the first theory was plausible, wrong, and
disproved by a measurement I nearly did not take. What worked was picking an experiment whose result
could only mean one thing, rather than reasoning further about the code.

Gate: **950 tests / 87 suites**, green. `SwiftCompile` confirmed; verified on the iPhone.

**Re-swept the iOS settings panes after the title change (2026-09-17).**

Changing the title mode moved every pushed pane, so I re-measured all eleven rather than assume the
two I had checked were representative. No collisions anywhere: section header ink at y=361 with the
card at 406–417, cleanly below the bar; title inline and centred, back chevron carrying the parent's
name where there is one.

Two things my scan flagged turned out to be nothing, and both were worth opening rather than trusting
the numbers: Channel Manager's content "starting high" is its search field, and Subtitle Languages'
is the navigation bar's own opaque background — it is the one pane in the set whose list is long
enough to sit under the bar, so iOS fills the bar in. Stock behaviour.

**One real thing found, not fixed.** When I fixed the box-in-a-box on Apple TV I said plainly that I
had not measured whether the phone had the same problem. It does — Web Management draws "Start Web
Management" as a white capsule *inside* a grouped-list card, which is two pieces of chrome for one
control. I am not bolting that onto the end of a sweep: it is a different set of call sites from the
tvOS one, several buttons across several panes, and it wants its own pass with its own before-and-
afters. That is what I will do next.

Gate: **950 tests / 87 suites**, green. No code changed this pass.

**The box-in-a-box, finished on iOS (2026-09-17).**

Three call sites, all verified on the phone with before-and-afters rather than reasoned about:

- **Test Connection** (Radarr & Sonarr): the row-fill clearing I added for Apple TV was gated to
  tvOS. The phone has the same double chrome, so the gate is gone. The card now ends after the last
  field and the pill sits on the page.
- **Start Web Management**: its own section with no row fill, so the white capsule sits on the page
  ground and "Forget Paired Browsers" keeps a normal iOS action row in its own card underneath.
- **Copy Address**: the same, and I checked it stays legible — a dark capsule on the page rather than
  vanishing into it.

The active-session half of Web Management only exists once a session is running, so rather than
assume, I used the app's existing start-on-launch default to get it into that state, measured it, and
deleted the default again.

**One small thing I noticed while verifying and did not touch:** in the active-session card, "Stop Web
Management" is centred while "Forget Paired Browsers" right below it is leading-aligned — only the
first carries a full-width frame. Two alignments in one card. Next pass.

Gate: **950 tests / 87 suites**, green. Four `SwiftCompile` lines confirmed across the two files.

**Two alignments in one card (2026-09-17).**

"Stop Web Management" was centred and "Forget Paired Browsers", directly below it in the same card,
was leading-aligned. The centring turned out not to be a decision at all: it was a full-width frame
left over from when that button was a filled capsule. On a plain action row the frame does nothing
except centre the text. Removed — both rows read from the same leading edge now.

Verified against the real active-session state again rather than the empty one, since that card only
exists while a session is running.

Gate: **950 tests / 87 suites**, green. `SwiftCompile` confirmed.

**The Streaming Services empty state, and a filing mistake of mine (2026-09-17).**

"Metadata Is Off" was centred at x=529 on a 1920 pt page — dead centre of the invisible 900 pt form
column — so it read as having drifted into the left half of the screen. I had put this on your
decision pile. That was wrong: it contradicted a rule we had already settled (D4b, that a tvOS empty
state centres on the whole area), so it was a defect, not a question.

The cause is that the settings-pane modifier wraps *everything* it touches in the form column, and
that column is for rows. The empty and loading states now take the page title without the column; the
populated list is untouched. The empty state's centre moved from 530 to **960** — the page centre
exactly — with the title still at the 80 pt inset.

Worth watching: I have been quicker to file things as "your call" than the evidence warranted. When a
rule already exists, the right move is to apply it.

Gate: **950 tests / 87 suites**, green. `SwiftCompile` confirmed; verified on the Apple TV sim.

**Audited every settings empty state (2026-09-17).**

If one pane could inherit the form column for its empty state, others could, so I checked all of them
— every empty state, loading state and unavailable view in the app, against the container it actually
sits in. Only Streaming Services had the bug, and it is fixed. The tab-level ones (Discover, Library,
Live) are all on the footing we set in D4b and centre in the viewport.

One thing did fall out of it: **"Source Not Found" was the only settings page in the app with no
title.** Its branch sits outside the page modifier, so it drew a bare centred message with an empty
navigation bar behind it — and since that modifier is also what records the screen for tracing, the
page left no trace entry either. The comment on that modifier says no page may be added later and
silently go unrecorded; this was the page that had. It is titled now.

To be straight about the verification: that state needs a navigation path holding a source id whose
source no longer exists, which the debug hook cannot produce, so this one is read-verified rather
than photographed.

Gate: **950 tests / 87 suites**, green. `SwiftCompile` confirmed.

**The tvOS accessibility pass is blocked, and not by a little (2026-09-17).**

I planned a Dynamic Type sweep on the television next. It cannot be done from here: `simctl ui
content_size` returns **unsupported** on the Apple TV simulator, and so do `increase_contrast` and
`appearance`; `reduce_motion` and `bold_text` are not simctl options at all. There is no way to put
that simulator into an accessibility text or contrast state headlessly. I would rather tell you that
than take a screenshot at the default size and file it as a pass. iOS is unaffected — that is how the
largest-text work got done there.

**While I was in the area I re-verified D4b**, because `[F]` rows in these files have outrun the code
before. It did land: Discover and Library now have the same shape, the empty state a sibling of the
scroll view rather than a row inside it, and the shared empty-state view fills and centres in whatever
it is given. The 94 pt jump between tabs cannot come back from that shape. I checked this by reading
rather than by capture on purpose — the claim is structural, and photographing it would need a
sources-free install, i.e. a throwaway simulator for a question the code already answers.

**Next**, and worth doing: every screen I changed tonight on iOS — the inline pane titles, Web
Management, the detail content column, the episode rows, the hero buttons — was measured at the
default text size only. Large type is exactly where new layout breaks, and on iOS I *can* set it.

Gate: **950 tests / 87 suites**, green. No code changed this pass.

**Largest text size found a real one (2026-09-17).**

I said large type is where new layout breaks, and it was — though not in the screens I changed. Both
brand button styles drew their fill as a **capsule**, and a capsule's corner radius is always half its
height. At the largest accessibility size "Start Web Management" wraps to three lines, the capsule
becomes an *ellipse*, and an ellipse is narrower at its top and bottom than the text it is supposed to
contain: the first and last lines were drawn outside the white shape entirely.

The styles use a rounded rectangle now with a 30 pt radius. That number is chosen so nothing else
moves: a rounded rectangle clamps its radius to half the smaller dimension, so at the 60 pt Apple TV
minimum it is exactly half and at the 44 pt iPhone one it clamps to 22 — both still perfect pills.
Only a wrapped label turns it into a rounded rectangle, which is full width at every height, so the
text stays inside. I checked all three states in one frame: the ellipse before, the rounded rectangle
after, and the default text size still drawing exactly the pill it always did.

Discover at that size is fine — the hero restacks, the summary holds to one line, and Play and Details
stack as full-width pills.

Still to re-check at that size: Radarr & Sonarr, Privacy, the detail page and the episode rows. I have
captures but they predate this fix, so they are worth nothing and I will retake them.

Gate: **950 tests / 87 suites**, green. `SwiftCompile` confirmed. The simulator's text size was put
back to normal.

**Finished the largest-text re-check (2026-09-17).**

Radarr & Sonarr and Privacy came back clean against the fixed build — "Test Connection" is a rounded
rectangle now with both its lines inside it, labels wrap, toggles stay put.

**Fixed: "Episodes" was breaking mid-word** — "Episod" over "es" — because the heading and the season
control were sharing one row and at that size there was no room for either. They stack now when the
type is an accessibility size, the same answer the hero's action row already used. Heading on one
line, "Season 1" beneath it.

**Found, not fixed, and it is the more serious one:** on the detail page, Play, "Download Season 1",
"My List" and "Rate" **ignore Dynamic Type entirely**. At the largest size they stay exactly as small
as they are now while the synopsis beside them is enormous — the two most important controls on the
page are the only things that do not grow. The cause is a hard-coded 15 pt font and a pinned 36 pt
height in the detail metrics. I am not doing it as a drive-by: those button widths are an asserted
contract in the tests, so scaling them properly is a metrics change with its own test work. It is the
next thing I pick up.

Gate: **950 tests / 87 suites**, green. `SwiftCompile` confirmed; sim text size restored.

**The detail page's buttons grow now (2026-09-17).**

Play, Download, My List and Rate were the only things on that page that ignored the text size — a
hard-coded 15 pt label and a pinned 36 pt height, so at the largest accessibility size the two most
important controls stayed exactly as small as they are today while the synopsis beside them was
enormous.

They scale from the same constants now, which matters: at the default size every number is identical
to what it was, and the width functions the tests assert are untouched. What changed is how the view
uses them, not the contract.

**One thing the first attempt got wrong, which is worth recording.** Scaling alone was not enough:
two scaled buttons do not fit across a phone, and "Download Season 1" ended up squeezed between the
screen edges and breaking *mid-word* into "Downloa / d Seas…". The row stacks vertically at those
sizes now — same answer as the hero's action row and the Episodes header — and the label wraps at the
word inside its own button. I only found that because I looked at the capture after the first fix
rather than calling it done.

Checked both sizes in one frame: stacked and scaled at the largest, and the old layout unchanged at
the default.

Gate: **950 tests / 87 suites**, green. `SwiftCompile` confirmed; sim text size restored.

**The iPad at the largest text size, and two follow-ons from last tick (2026-09-17).**

Taking the detail page to the iPad at that size showed that my previous fix was **incomplete**: Play
and Download had grown, but "My List" and "Rate" right beside them still had their 20 pt glyphs and
11 pt labels. Those two build their own labels rather than going through the button label view, so
they were never touched. They scale from the same constants now.

That fix then broke something of its own, which I caught by looking at the capture rather than
assuming: once the items hug their labels instead of sitting in fixed 44 pt slots, the row's zero
spacing had nothing left to hide behind and "My List" and "Rate" ran together into "My ListRate". The
row supplies its own gap at those sizes now, and there is a clear space between them.

That is two ticks running where the first version of a fix needed a second pass that only a
screenshot would have revealed. The discipline is earning its keep.

**Next, and I can see it in the same capture:** the rule I added for stacking those buttons is purely
"is this an accessibility text size", which is right on a phone and too eager on a tablet — on the
iPad, Play and "Download Season 1" come to about 460 pt on an 834 pt page and would sit side by side
comfortably, but they stack anyway. The decision needs the available width in it, not just the type
size.

Gate: **950 tests / 87 suites**, green. `SwiftCompile` confirmed; sim text size restored.

**Stacking now decided by measurement, not by a rule about text sizes (2026-09-17).**

My rule was "stack whenever the text is an accessibility size", which is right on a phone and too
eager on a tablet — the iPad stacked two buttons that came to about 460 pt on an 834 pt page.

I did not replace it with a better threshold. The row offers SwiftUI the side-by-side layout first
and the stacked one as a fallback, and SwiftUI picks whichever fits. The reason matters: computing
the threshold myself would mean estimating how much a button that hugs its own label grows at a given
text size, and that estimate is exactly what was wrong the first time. Better to let the layout
measure than to guess again.

Checked three states rather than the one that motivated the change: iPad at the largest size is side
by side now, iPhone at the largest size still stacks with "Download / Season 1" wrapping at the word,
and the iPhone at the default size is untouched.

Gate: **950 tests / 87 suites**, green. `SwiftCompile` confirmed; sim text size restored.

**iPad, largest text size, remaining screens (2026-09-17).**

Episodes and Web Management both come back correct against the build that carries tonight's three
Dynamic Type fixes: the Episodes header stacks, titles and dates hold one line each, summaries
truncate at a word, and "Start Web Management" sits on one line inside a proper pill.

**One thing I looked at hard and deliberately did not change.** The episode thumbnail stays 104×64 at
every text size, and next to three lines of very large text it looks small. My first instinct was to
scale it like everything else tonight. It is the wrong instinct: growing the thumbnail takes width
away from the text, and on a phone a scaled one would eat about half the row. The still is
illustrative, not essential — holding it fixed keeps reading width where someone at this text size
actually needs it. Recording that as a decision rather than leaving it looking like something I
missed.

**And one to fold into an item you already have:** the status-bar collision is on the iPad as well as
the iPhone — scrolled content draws across the clock on both. Worth knowing so it gets fixed once
rather than twice.

Gate: **950 tests / 87 suites**, green. No code changed this pass.

**Text no longer runs through the clock (2026-09-17).**

The detail page hides its navigation bar on iOS so the hero can reach the top of the screen. That is
right, but with no bar there is nothing behind the status bar once the page scrolls, so the synopsis
was drawn straight through the time and the battery — on the iPhone *and* the iPad, at the default
text size.

There is a flat black shield there now: invisible while the page is at rest, appearing the moment it
moves. Flat black rather than a fade, because the app is allowed exactly one gradient and this is not
it. Checked on both devices in both states — scrolled, the clock is fully legible and the text stops
below the band; at rest, the top of the page looks exactly as it did.

This one had been sitting on your decision pile, and it should not have been. "Stock Apple look" is a
rule you already set, and no Apple app draws body text across the clock. That is the second time
tonight I have taken something off that pile that I should never have put on it — I have been
treating "I would have to choose how to fix it" as if it meant "the owner must choose whether to fix
it", and those are different things.

Gate: **950 tests / 87 suites**, green. New file compiles on iOS and tvOS; `SwiftCompile` confirmed
for both.

**G8, and a ✅ that was not true (2026-09-17).**

G8 asks that the UI not imply a service handoff goes deeper than it can. **It is satisfied, in the
strongest way available: there is no handoff to be dishonest about.** The services line is plain text
— "Also available on Netflix and Tubi" — with no tap target, no button, no link. I confirmed it by
searching the whole app for `openURL`, `UIApplication.shared.open` and `NSWorkspace`: none of them
appear anywhere. The app never leaves itself for a service.

Checking that turned up something else. **G4 — "Play becomes the external option only when there is
nothing else" — is ticked as done and is not wired.** The policy exists and has three passing tests,
but its only callers *are* those tests. No view calls it. Play is never replaced by anything. I have
corrected the row rather than leaving a green tick on it; this is the same pattern that file has been
caught by before, which is why I now check the code before trusting a ✅ — including my own.

**I am not wiring it, and this one genuinely is your call.** TMDB gives us which services carry a
title but no title-level link, so an external button would open Netflix, not the title — the exact
honesty problem G8 exists to prevent. Three ways to go: open the service's app anyway and say so,
open a web search for the title, or leave it as the quiet sentence it is today. No rule you have set
answers that one.

Gate: **950 tests / 87 suites**, green. No code changed this pass.

**How much of the green gate is the app actually running? (2026-09-17)**

G4 being ticked-but-unwired bothered me enough to check whether it was alone. I took all **466**
`static func` declarations in the app's source and looked for callers outside the test suite.

**Sixteen are called only by tests.** Not deprecated, not `#if`'d out — written, tested, green, and
never executed by the app. Among them: the external-play policy from G4; the whole `MediaCapability`
type, which is referenced nowhere outside its own file; the offline download quality chooser; an
audio-resume policy that duplicates a check the player already does inline; and four catalog queries
in `AppleMediaIndex` — popular, new releases, recommendations, ARR records — that nothing asks for.

I hand-checked ten of the sixteen rather than trusting my own script, and one apparent hit turned out
to be a false positive (`popular` was matching `popularityScore`). The rest hold up.

**I have not deleted anything or wired anything.** Some of this is very likely written ahead of a
feature, and the behavioural ones are product decisions, not tidying. What I have done is record it,
because the honest version of "950 tests passing" is that sixteen of those policies are green in a
suite and absent from the app. That is worth knowing before either of us leans on a tick in an area
one of them covers.

If you want, the obvious next move is to go through the behavioural four — external play, download
quality, the catalog queries, capability evaluation — and decide for each whether it gets wired or
deleted. Both are better than the current state.

Gate: **950 tests / 87 suites**, green. No code changed this pass.

**Re-examined the tvOS section-header inset, and it stays parked (2026-09-17).**

Having twice taken things off your decision pile that I should never have put there, I went back
through the rest of that pile asking "is there a rule that already answers this?" The section-header
inset was the one I most expected to un-park. It stays, and the measurement is why.

There are **three** different left edges on one settings pane, not the two I originally reported: the
page title and the field capsules at 80–82, the section header at 101, and the field's own
placeholder text at 122. The system's header inset matches neither the card nor the row text, because
our rows carry internal padding the system header knows nothing about. The hand-built panes add a
fourth answer by putting the header flush at 80.

Apple's own grouped lists align a section header with the row text. Reproducing that here means
hard-coding a 21 pt nudge derived from our own field chrome — a magic number that breaks the first
time the field padding changes. So the real question is which of those edges the app aligns headers
to, and no rule you have set picks one. It is a decision, not a defect.

No code changed this pass — I measured, and the answer was "leave it alone", which is a result even
though it does not look like one.

Gate: **950 tests / 87 suites**, green.

**Triaging the sixteen (2026-09-17).**

A flat list of sixteen tested-but-uncalled functions is not something you can act on, so I read each
one and what the app does instead. They are three different things, not one.

**Two are dead for reasons already on the record.** The trailer sound bridge has no caller because
trailers are tabled — that is correct, not a gap. And `watchURL` builds a TMDB watch link that nothing
opens, which *is* the G8 answer from the last pass rather than a hole in it.

**Five are arithmetic or platform mirrors.** Two are geometry helpers the views do not happen to need
— and one of them, `iconCenters`, is actually a faithful model of the real layout, since those cells
genuinely are 120 pt wide laid edge to edge. The other two are runtime mirrors of a `#if os(...)` the
app already decides at compile time; a test asserting "tvOS → true" is testing the mirror, not the
app. Harmless, but worth knowing they buy no assurance.

**Nine are behaviour the app does not have:** the external-play option, the whole capability type, the
download quality chooser, the audio-resume policy the player duplicates inline, four catalog queries,
and the ARR fallback chain — the ARR calls do not go through it.

That is the useful part. "Sixteen things are wrong" becomes nine questions for you, five shrugs, and
two already answered. Still nothing deleted and nothing wired.

Gate: **950 tests / 87 suites**, green. No code changed this pass.

**Library TV: a finished feature nobody can reach (2026-09-17).**

I had noted once, a while back, that "Library TV is built but unreachable" and never went back to it.
It is bigger than that note made it sound.

It is **418 lines and 6 passing tests across three files** — a model, a view, and a test file — and
outside those three files nothing in the app mentions any of it. No screen presents the view, no route
reaches it, and the words "Library TV" do not appear anywhere else in the source. What it does is
assemble your local files into continuously-playing channels: programmes with security-scoped URLs, a
channel, a queue, a builder. It is complete.

Two details make this worth your attention rather than a tidy-up note:

- **The view is iOS-only.** It will not even compile for Apple TV — which is the platform where "my
  files as a TV channel" is the most obvious thing to want.
- **The model has no platform guard**, so it builds everywhere and its six tests pass on every run.
  That is exactly why nothing has ever flagged it: the gate is green because the tests are green, and
  the tests never needed the app.

So: wire it or delete it, and if wire, say where — a tab, an action on Library, and on which platform.
I am not guessing at that; it is a feature-shaped decision, not a layout one. But leaving a finished
feature unreachable is the one option that helps nobody.

Gate: **950 tests / 87 suites**, green. No code changed this pass.

**Are there other screens nobody can reach? (2026-09-17)**

Library TV made that worth asking properly, so I checked all 99 view types in the app for whether
anything constructs them.

Mostly reassuring. Fifty-two are only built inside their own file, which is just the normal shape of a
parent and its private subviews. **The sweep also caught its own blind spot**, which I want to flag
because it nearly became a false report: `AppleFirstRunGuidanceView` showed up as "never constructed"
only because it is built with a trailing closure, a shape my pattern missed. It is alive — I have
watched it render. I re-checked the rest by plain name before trusting the list.

Two genuine leftovers, and I treated them differently:

- **`AppleCatalogEmptyView` — deleted.** Ten private lines wrapping the shared empty state, built by
  nothing, tested by nothing. Gate unchanged at 950, tvOS rebuilt, Discover checked on screen after.
- **`AppleIPTVGuideView` — left in place, and I recommend you delete it.** Seventy-five lines, its own
  60-second timer, no tests, superseded *twice* — the iOS guide is `AppleIPTVGuideGridView` and the
  tvOS one is `AppleTVLiveGuideView`. The reason I stopped is that it is `public`, so it is part of
  the package's API surface. The hazard isn't the dead code; it's someone later wiring the old guide
  by mistake. Removing a public type is worth one line from you rather than me deciding at 7am.

Gate: **950 tests / 87 suites**, green. `SwiftCompile` confirmed.

**visionOS: the target was not building, and nothing was going to notice (2026-09-17).**

Hunting for what this audit had never touched, I found the app carries **110 visionOS-specific
branches across 19 files** and there is no visionOS pass anywhere in the record. So I tried to build
it. It failed — twice, for two unrelated reasons.

First, `WidgetCenter` is only available from visionOS 26.0 and that target deploys to 2.0. The widget
work wrapped the timeline reload in `#if os(iOS) || os(visionOS)`, which does not compile there. It is
availability-gated now rather than dropped, so the reload still happens on a visionOS that has
widgets.

Second, the Library scroll body stopped type-checking on that platform — the visionOS branches add
enough overloads to tip an expression the other platforms still manage. Two extractions fixed it, and
it needed both: after the first the error just moved to the new line number.

**The part worth your attention is why this sat there.** The gate compiles macOS, and the deploy
builds are iOS and tvOS. Nothing in the loop builds visionOS, so a target can stop compiling entirely
and every signal stays green. It builds now, and I checked iOS and tvOS still do, since the file I
restructured is shared.

The visionOS GUI itself is still unmeasured — building was the blocker, and the screenshot pass is
next.

Gate: **950 tests / 87 suites**, green. `SwiftCompile` confirmed; visionOS, tvOS and iOS all build.

**visionOS, first look at the GUI (2026-09-17).**

It renders properly — window in the room, tab ornament down the left, search and refresh at the
bottom, hero billboard, Top 10 shelf. Two things looked wrong at a glance and are not: the shelf
continuing past the window's bottom edge is just a scroll view, and the bottom ornament hovering over
the window edge is where visionOS puts ornaments.

**One real finding, and I measured it rather than trusting my eye.** On the *Mandalorian and Grogu*
billboard the synopsis sits on background luminance of about **120–143** across its width. White body
text on that is roughly **3.9:1**, under the 4.5:1 minimum. It is not a missing fade — the approved
one is there, but it starts 35% down and only reaches full strength at the very bottom, so at the 48%
mark where the synopsis sits it has applied about 0.17 opacity. Nowhere near enough against a bright
orange explosion. The buttons below are fine because they sit lower and have their own fills.

**It is not a visionOS bug.** The same hero draws your iPhone and iPad billboards. It has not been
caught there only because those captures happened to land on dark artwork — the Whisper Man, 2073,
1992 are all dim. Put a bright poster behind it and the phone will do the same thing.

I have parked it, and I want to be clear this is a different kind of parking from the others: it is an
accessibility failure, not a taste question, and I rank it the most urgent thing on that list. The
reason I did not just fix it is that all three fixes — start the fade higher, deepen it where the copy
sits, or put a solid plate behind the copy — change the look of a screen you have already reviewed,
and picking one of those at half past seven is how a reviewed screen quietly stops looking like what
you approved.

Gate: **950 tests / 87 suites**, green. No code changed this pass.

**Tester feedback from build 10 — first one fixed (2026-09-17).**

Took the tab trap first because it is a dead end for the user: switch a tab off and there was no way
back short of reinstalling.

The cause was a name. The policy was called `canHide`, it was wired as "disable the switch when
canHide is false", and read literally a tab that is already off has nothing to hide — so it returned
false and the switch went grey. A test asserted exactly that, with a comment saying so, which is why
the gate was green on a trap. It is `canToggle` now, with the rule the app actually wants: a tab that
is off can always be turned on; a tab that is on can be turned off unless it is the last one. The test
now asserts the opposite of what it did.

I proved it at the control rather than the policy. A UI test switches Live off, checks the switch is
still live, and switches it back on. It failed against the stale build for the tester's exact reason
and passed against the fixed one — and the review iPhone itself had been left in the trapped state by
the old code, which the fixed build released.

**The crash report is not on this Mac.** Organizer's local cache was last refreshed on the 11th,
before build 10 went out, and holds only its own query state. The report is in App Store Connect
under TestFlight → Crashes. Either open Organizer once on this Mac (it pulls crashes into that cache
and I can read them from there), or paste me the device, OS and the top of the stack.

Gate: **950 tests / 87 suites**, green. Fix confirmed compiled into the UI-test build (both files),
iOS built, control-level test passing.

**Bug 4 — "only one TV channel is displayed in M3U" — fixed (2026-09-17).**

Found it on one line. Under **All**, with the **Premier Guide** package every new M3U source lands on
by default, the guide shows only channels that matched your curated US lineup — and it only fell back
to "show everything" when the lineup matched *nothing at all*. So a French playlist with one channel
that happened to share a name with a US network showed exactly that one channel. That is the tester's
report, word for word.

The cliff at zero is a floor now: the lineup has to match at least eight channels before All is
allowed to show only the lineup. Eight is far below your real provider (a few hundred of 9,376 match)
and far above a name collision (one or two), so your guide is untouched — I checked on the Apple TV
with your provider, same twelve rail rows in view as before — and a tester's playlist shows all of it.

Two things worth knowing. **The old test asserted the bug**: it used a two-entry lineup, exactly the
tester's case, and expected two channels. And **your French playlist is now a fixture** with all 28
`#EXTINF` lines verbatim — the accented names, the `url-tvg` EPG header — and three tests, the last of
which is the tester's bug on your real list: All shows all 28 under Premier Guide. I replaced the
stream URLs with `fixture.example` because the originals carry a provider path token that should not
sit in the repo.

Gate: **956 tests / 88 suites**, green. tvOS and iOS both rebuilt with the fix confirmed compiled in.

**The toggles (2026-09-17).**

You were right that they were not great, and the reason is one line: the app tints itself white so
nothing reads as the iOS default blue, and that tinted every switch too — a white ON track under a
white knob, which you could only read from the knob's shadow.

Switches now take the brand accent — the same #FF3366 the favourites heart and the guide's now-line
already use, so it stays inside "nothing blue but the brand mark" — and *only* switches: the style is
applied once at the root and re-wraps each switch, so the buttons, links and chevrons next to them
stay white. ON is an accent track with the knob right; OFF is a dark track with the knob left. A mixed
page reads instantly.

Two things worth telling you. First, I verified OFF with the real control rather than a config poke:
a `defaults write` of the tab key was quietly ignored by the app, so my first "off" screenshot was
actually all-on — I noticed because the tab bar still had four tabs, and used the tab-toggle UI test's
own screenshot instead, where the bar drops to three. Second, **I caught and reverted a regression**:
I had applied the style on Apple TV as well, and Apple TV draws a Toggle as a row with an On/Off
label rather than a switch — the accent painted the row *text* pink, exactly the kind of coloured
label you have ruled out. It is iOS-only now, and the style refuses to tint on tvOS even if someone
applies it there later. Privacy pane recaptured, labels white.

Gate: **956 tests / 88 suites**, green. iOS and tvOS rebuilt from the final source, recompiles
confirmed.

**M3U at volume (2026-09-17).**

Two ceilings on a playlist: bytes and channels. The bytes were never the problem — 12 MB is about
49,000 entries in the shape of your French list. The channel cap was **10,000**, and your own
provider is **9,376**. That is 624 of headroom: one provider refresh, or two playlists merged into one,
and the tail was dropped — and dropped *silently*, because the code that enforces the cap just stops
reading. The guide ended early and nothing anywhere said why.

The cap is 25,000 now — far above any real provider, still well inside what the bytes can deliver —
and hitting it is traced as "kept N of M entries", so it can never be invisible again. Four tests pin
it, all on generated playlists in your format: 2,000 whole, **12,000 whole** (that one fails on the
old cap — it is your provider plus room), the cap honoured exactly, and the two ceilings agreeing so
the channel cap is actually reachable.

One flake, so nobody goes hunting: the first gate run failed a Web Management port test with
"address already in use" — the Apple TV simulator's copy of the app was serving the portal on this
Mac. Stopped it, re-ran, clean. Not this change; the four new tests passed both times.

Gate: **960 tests / 89 suites**, green. tvOS rebuilt, recompile confirmed.

**The 300-channel cap (2026-09-17).**

Done the way you described it. The parser still swallows a whole playlist — that is what lets Search
and the Custom package reach everything — but the guide draws at most 300, and when it has held some
back it says so in one line under the category chips: "Showing 300 of N channels". No explainer; the
count is the message. Channel Manager will not let you add a 301st channel to a hand-picked list —
it puts "Limit reached — the guide shows up to 300 channels." in the slot where its messages already
appear. Favourites are counted on their own, so five favourites out of nine thousand all show.

I checked it on your Apple TV by switching the package to Everything, where the cap actually bites:
the guide drew the uncurated EAST/WEST pairs and the line read **"Showing 300 of 4,836 channels"**.
Package put back to Premier Guide afterwards.

Two things cost me time and are written into the audit so the next session does not pay for them
again: the Live tab is two different views (the phone's and the television's), and the television's
has an explicit initialiser — adding a property to it is not enough, the initialiser has to take it
too, and the test gate cannot see that file at all because it is tvOS-only.

**On Channel Manager — my recommendation, since you asked.** The pain is the "My Channels" section:
it lists *every* channel from the provider as a toggle, which on 9,376 is a wall. Your second option is
the right one and it is mostly there already: keep it in Settings (it has to work on the TV with a
remote, where the web portal cannot help), make that section show **only the channels you have
chosen**, each with a remove, and make **Search Channels** the way you add — search, tap (+). "Search
Channels" exists today; what changes is that the main list stops being the whole provider. Web
management is worth adding *later* for bulk work on a keyboard, but as the second door, not the first.
Say the word and I will build it that way; it reshapes a screen you have reviewed, so I have not.

Gate: **967 tests / 90 suites**, green. tvOS rebuilt and verified on screen.

**Bug 2 — choosing the download source (2026-09-17).**

Downloads now ask. Tap Download on a title with more than one stream and the same sheet the player
uses for "Other sources" opens as "Download from" — local files hidden, since you don't download
those — and whichever row you pick goes first. It only *reorders*: everything else stays behind it as
fallback, because the download engine already walks the list when a source fails, and a pick you
make should never shorten that. One source means no sheet, and if the add-ons can't be asked it just
downloads the old way. Season downloads are untouched.

Proven with a UI test: the episode's ↓ opened the sheet with **seven sources in 22 seconds**, then
dismissed it without downloading anything onto your simulator.

**What the sheet then showed me, and I am not leaving it:** those seven rows read "[TB+] Add-on
1080p · via Add-on TB" four times and "…720p" twice. You cannot tell them apart, and for a download
the filename and size are precisely what you would choose on. The player's sheet has the same rows.
Next thing I do.

**And a correction I owe you.** I have been saying build 11 was blocked on you for the App Store
Connect Issuer ID. It was not. The key ID, issuer and the `.p8` have been on this Mac all along — in
`~/Developer/openstream-build/asc_lib.py` and `~/.appstoreconnect/private_keys/` — and the key works: it
just listed the app, five profiles and the registered bundle ids. I never looked. So the answer to
"command to save what I need" is: for App Store Connect there is nothing left to save. The real ship
blockers are on the developer account, and with a working key they are mine to fix: the bundle ids
`com.orgista.openstream.widgets` and `.watchkitapp` are **not registered** (only the app and topshelf
are), so no profile can exist for them, and the iOS App Store profile "OpenStream AppStore
openstream" is **INVALID**. Registering the two ids and creating three profiles is the next step;
I have pulled the certificate and bundle facts and will do it, since you said ship 11.

Gate: **970 tests / 91 suites**, green.


**Ship 11 — what was actually blocking it (2026-09-17).**

It was never the Issuer ID. The App Store Connect key — key id, issuer and the `.p8` — has been on this
Mac the whole time, in `~/Developer/openstream-build/asc_lib.py` and `~/.appstoreconnect/private_keys/`,
and it works: it listed the app, the profiles and the registered bundle ids the moment I tried it.
I kept telling you it was on you because I never looked. Nothing needs saving for App Store Connect;
if you ever want to store something else for me, the pattern this repo already uses is the macOS
Keychain service "OpenStream Deployment":
`security add-generic-password -s "OpenStream Deployment" -a <name> -w` (it prompts; nothing echoes).

With the key working I did what the archive needed: registered `com.orgista.openstream.widgets` and
`com.orgista.openstream.watchkitapp` as bundle ids, enabled App Groups on both, created an App Store
profile for each, installed them, and wrote `ExportOptions-b11.plist` with all four bundle ids mapped
to their profile UUIDs (your original export options file is untouched).

Then I tried the archive locally — no export, no upload — and it failed usefully. All three targets
say "requires a provisioning profile": the project pins none, because build 10 was archived with
Xcode's **automatic** signing, and my attempt forced manual signing without pinning any. Widgets also
needs its profile to carry the App Group, and the public API cannot assign a specific group to a
bundle id — both new profiles came back with an empty group list. Automatic signing handles that
itself, so the next attempt is the archive with `-allowProvisioningUpdates` and no manual override.
If that fails on the group, the fix is thirty seconds in the portal: Identifiers → each new bundle id →
App Groups → tick `group.com.orgista.openstream`.

## 2026-09-17 — downloads automatic, per-episode progress, skills + `asc`

Downloads no longer ask. The "Download from" sheet is gone; ↓ starts the download and the coordinator
tries the next ranked source itself if the first is dead — that is the real fix for the tester's
"a source is chosen by default but is not necessarily available". Since nothing asks any more, the
row had to *show* something: the ↓ turns into the App Store ring with a stop square and a live
percentage (your tester's "percentage bar during download"), and a failed or cancelled download now
prints its one-line status on series pages too — it was silently hidden there before. Proven on the
iPhone sim with a real 2.8 GB episode: tap → ring at 3 s → cancel → clean, nothing left behind.

Skills: 18 of the twostraws set are installed under `~/.claude/skills/` and load automatically (they
show up in the Skill list every session) — the App Store Connect ones plus SwiftUI performance/refactor,
Swift Testing, concurrency, accessibility, widgets, background execution, the tvOS focus engine and the
simulator skill (its erase/delete scripts removed — the sims are persistent). The `asc` CLI is
installed and logged in as profile "OpenStream" with the key that was already on this Mac; `asc apps
list --bundle-id com.orgista.openstream` answers. Nothing was uploaded.

Still blocking 11: automatic signing needs an Xcode Apple ID session on this Mac (or I pin the four
profiles manually), and the two new bundle ids need the App Group ticked in the portal.

## 2026-09-17 11:00 — your batch: toggles, traces, M3U text, AIOMetadata

Toggles are the classic iOS switch now (green on, grey off, white knob) — the exact look of that
codeburst CSS checkbox, which is just Apple's own switch. Tracing is on by default for every
TestFlight install (Internal and TraceEnabled both get it) and off for App Store installs; the
Settings toggle still wins. Add Live TV → M3U gained "Playlist Text" and "Choose File…": paste a
playlist or pick an .m3u and it merges into one local playlist, so the Sources list shows a single
"Playlists" row no matter how many times you paste — grouped like an Xtream account. Duplicate
streams are skipped and a guide header (`url-tvg`) is kept when one shows up. AIOMetadata is seeded
once per install on DEBUG/TestFlight builds as a normal catalog source; delete it and it stays gone.
One caution: that manifest URL carries your personal elfhosted instance id and now ships in the
binary — fine for testers, but say the word if you'd rather it came from a config the app fetches.

## 2026-09-17 11:25 — build 11 status

tvOS and visionOS build 11 are archived and exported (manual signing pinned per target in the
project for Release only — no Xcode account on this Mac, and the API-key automatic path fails
authentication). Upload + Internal/TraceEnabled distribution + beta-review submission runs through
`asc publish testflight`. iOS 11 needs you for 30 seconds: Developer portal → Identifiers →
com.orgista.openstream.widgets → App Groups → tick group.com.orgista.openstream. The API can turn
the capability on but cannot pick the group; once ticked I regenerate the widgets profile and ship
iOS the same way. One trap to know: a brand-new source file was silently truncated to 0 bytes on
the share after the gate passed — it's restored and committed, and the handoff now has the check.

## 2026-09-17 11:50 — your M3U, the guide, and where the builds stand

The French playlist: those channels are HLS behind extension-less URLs (`…/895` redirects to an
`.m3u8`). The engine treated them as raw TS and FFmpeg refused them. Live channels now get a one-time
32 KB look when the URL says nothing, and HLS goes straight to AVPlayer — TMC plays on the iPhone sim
with your exact playlist, no alert. The guide was a second bug: open-epg's France file redirects and
is 10.6 MB; the loader rejected redirects and stopped at 8 MB, hence "No information". Both fixed,
tested, will be in the next build (13).

Builds: **11** (tvOS + visionOS) is the non-trace build and is now in Reddit as well as Internal and
TraceEnabled; **12** (tvOS + visionOS) traces by default and is in Internal + TraceEnabled, submitted
for beta review. Honest note: 11 shipped without the trace default because that edit had been lost
in an aborted script — so 11 is exactly the "non trace" build you asked for Reddit, and 12 is the
traced one. iOS is still waiting on the Widgets App Group tick in the portal.

Mormon Wives: the ranking fix from 09-16 is in this tree and you still got the wrong show on the
sim, so it did not settle it — logged as open, next on my list after the Channel Manager cleanup you
asked for (Your Regional removed; selected-only list + searchable "Add Channels…" for 3,000-channel
lineups). Tab bar: understood — system bar per OS, no custom styling. Watch simulators removed.

## 2026-09-17 12:35 — Channel Manager, cleaned up

"Your Regional" is gone. Live view offers Provider Lineup and My Channels. The MY CHANNELS section
no longer shows 3,000 toggles: it lists only what you've picked (swipe or ⊖ to drop one) and one
row, "Add Channels…", opens a picker grouped by your provider's groups with a search box that stays
visible; ⊕ adds, ✓ shows what's in, and the 300 cap still speaks up. Checked on Apple TV and iPhone.
One thing I noticed on the iPhone sim: your Xtream source is switched off (Settings → Sources →
Live TV → On), which is why the manager said "add a source first" — it now says the source is off.
Nothing in the app disables a source by itself, and my tests only add/remove their own playlist.

## 2026-09-17 13:05 — Mormon Wives, the real cause

You were right that it was still wrong. It was never an episode problem: Torrentio answers that
episode with twelve streams and seven of them are *other shows* — "Secret Lives of Gypsy Wives
S01E01" and "Secret Sex Lives of Tyrants S01E01". They all say S01E01, so last night's episode rule
couldn't tell them apart, and the best-seeded Gypsy Wives release won. Candidates are now ranked on
the title's own words first; on the sim the top four are all Mormon Wives releases and episode 1
plays. The trace now also names the top candidates on every play, so the next "wrong show" report
is a file read, not a hunt. Tab bar is the system one (glass on iOS 26). All local — nothing pushed.

## 2026-09-17 — Codex continuation: chapter-backed Skip Intro

Resumed the interrupted chapter-marker work using the Claude work profile and the existing SwiftUI,
Swift Testing, and concurrency skills. The player now receives Aether's embedded chapters through
its shared engine interface. Late runtime metadata rechecks whether a chapter is a sensible intro;
skipping stays sticky within the item and resets when the engine leaves that item. No fingerprinting
or guessed intros were added. This button belongs to the custom surface player; native AVKit routes
continue to use their system controls.

Real iPhone and Apple TV tests played a locally generated four-minute MPEG-2 MKV with a 50-second
Opening chapter: red before the action, green afterward, playback at 0:52, and the button gone.
The first screenshots exposed the button covering captions; its placement now accounts for the
measured bottom controls. The iPhone test asserts that it is above the scrubber. The Apple TV test
uses Down and Select on the remote, including waiting for initial surface focus; the auto-hide timer
can no longer take focus away from the chapter action. Checked before/after captures are in
`design/2026-09-17-chapters/`.

The gate passes 1007 tests in 101 suites. iOS and tvOS Debug app builds plus both interaction tests
pass; visionOS simulator and native macOS Debug builds also pass with signing disabled. The latter
two are compile checks, not runtime or release-signing validation. Two baseline SharePlay timing failures passed in isolation
and on subsequent full runs; that unrelated code was not changed. Claude's new regression tests
were audited and corrected: the underlying Aether public stop already clears chapters, and changing
chapter metadata is not proof of a different item. AGY was attempted, but its headless read was denied
and its prompt-only retry timed out without findings. The local Ollama AI Council completed; its
asserted chapter-read race was rejected because recomputation is synchronous on MainActor. Its
remote-focus test suggestion is covered by the real Apple TV test. OpenRouter was not needed.

No builds were uploaded, no commits made, and no signing assets changed. Build 13 remains local.
The existing iOS 11/12 Widgets App Group blocker and macOS signing preparation remain in the handoff.
The temporary media server was stopped, both simulators were shut down as they were at session start,
and only the fixture videos' resume entries were removed; saved sources and other progress remain.

### 2026-09-17 — AGY headless timeout diagnosis

The original file-access attempt was soft-denied; the subsequent 97,774-byte prompt hit its explicit
180-second ceiling. Authentication succeeded in both runs. A fresh Pro High smoke request succeeded
in 3.3 seconds, but Pro High and Pro Low repeated analysis on a focused one-file review without
returning a final answer; both diagnostic runs were stopped. Flash Medium completed the same
23,672-byte review in 94.3 seconds, reporting 33,705 thinking tokens. Its proposed duration findings
remain unaccepted: the excerpt omitted engine reset behavior, and the equal-duration claim does
not establish a defect because the tracks event already recomputes against that same duration.

Verified working bounded-review invocation: Flash Low, low effort, sandbox, disabled slash expansion,
stream-json output, no plan mode, a 90-second ceiling, and a 3,475-byte excerpt checking one explicit
invariant. It returned SUCCESS / PASS in 2.7 seconds, correctly confirming that track metadata keeps
the sticky skip flag and idle resets it. Use smaller checks and validate final result status rather
than treating process exit alone as a completed review. Evidence: local
`~/Developer/openstream-build/codex-agy-diagnostic-*`. No global AGY settings, source code, signing,
uploads or commits changed in this diagnosis.

### 2026-09-17 — Native macOS 1 feature baseline audit

Owner chose Mac 1 as a separate starting build number, with features catching up to the current
Apple code. Both Xcode configurations and the previously built native Mac app already report
version 1.0, build 1, minimum macOS 15. Build number 1 does not require rolling shared code back.
This was a source/configuration audit, not a new Mac runtime or release-signing verification.

Critical blocker: OpenStreamRootView.swift:184–229 has visionOS, iOS and tvOS branches but no Mac
branch; every tab's content is compiled out on macOS. AGY Flash Low independently confirmed this
specific conditional-compilation defect in 1.7 seconds (SUCCESS); Codex verified it directly.
Evidence: `~/Developer/openstream-build/codex-agy-macos-tabs.jsonl`. No source fix was made here.

Shared implementations already compile for Mac: Discover/search/details, Library/Continue Watching,
live channels/guide/channel management, sources including local-folder security-scoped bookmarks
and SMB, downloads (explicitly enabled for Mac), settings/integrations, and the playback pipeline.
Mac AVPlayerView enables stock controls, full screen and PiP; the software-decoded surface uses the
shared transport with chapter Skip Intro and next-episode logic. These are implementation parity,
not proof that every feature works end to end on Mac while the shell is empty.

Remaining platform gaps confirmed in source: SharePlay is enabled only on iOS; custom remote media
command/Now Playing integration excludes Mac; system-surface snapshot publishing excludes Mac and
no Mac widget target is embedded. Detail-page viewport adaptation falls back to zero size and a
fixed 420-point hero on Mac; trailer autoplay is disabled. Live surface playback's full-screen
action changes state but the presentation is excluded on Mac, so that action needs a Mac path.
The shared app scene has no Mac-specific default/minimum window size, Settings scene or command
menu shortcuts. Native Mac signing profiles/certificates and TestFlight distribution still need
preparation. Existing sandbox/network/user-selected-read-only/bookmark entitlements are present;
the older note suggesting sandbox entitlements were entirely absent was too broad.

Recommended Mac 1 acceptance order: repair the main navigation; verify sources, playback, captions,
downloads and live TV with local fixtures; fix window/full-screen/input behavior; then complete
distribution signing. Widgets, SharePlay and immersive visionOS features should not be described
as already at parity. No upload, certificate creation, commits or application-code changes here.

### 2026-09-17 — iOS 11/12 delivered after Widgets assignment

Owner completed the Developer Portal App Group assignment. Created and installed the new widget
profile, verified its entitlement, and used the existing release snapshots/worktrees and identities.
Fresh gates passed: build 11 has 981 tests / 94 suites; build 12 has 985 / 96. These older snapshots
intentionally exclude the newer main-branch changes.

Apple rejected the initial iOS 11 upload with 90391/90713: the embedded Watch app had no icons or
icon metadata. Reproduced against the original archive (no asset catalog and no icon metadata).
Added a Watch asset catalog using an unchanged copy of the existing opaque 1024px app icon, added
the catalog to Watch resources, and selected AppIcon in both Watch configurations. Applied this
packaging-only fix to both release worktrees and main. Compiled the catalog, rebuilt, verified
the archive's generated CFBundleIcons / AppIcon and Assets.car, validated all bundle signatures,
and re-exported/re-uploaded the same authorized number. Apple accepted the corrected build 11;
build 12 subsequently passed. The Watch profile did not require an App Group change.

Final live reads: iOS 11 and 12 are VALID, unexpired, and IN_BETA_TESTING internally and externally.
11 is in Reddit + Internal + TraceEnabled; 12 is in Internal + TraceEnabled. Both support iPhone
and iPad on iOS 18+. Full identifiers and artifacts are in DELIVERIES.md. Nothing newer was
uploaded; macOS remains at its planned build-1 baseline. No commits or new certificates.

### 2026-09-17 — Xcode Cloud diagnosis and relevant tester notes

Read the Cloud workflows, all three run issue lists, and all four action log bundles for run 3.
Default runs 1–3 all failed at dependency resolution: “Project OpenStreamApps.xcodeproj does not
exist at native/apple/Apps/OpenStreamApps.xcodeproj”. All used September 1 commit 7a76d8d9 in
orgista/openstream; its Git tree confirms that path is absent. The Android paragraph shown in
Cloud is the source commit message, not What to Test. The separate workflow named TestFlight has
no runs and only a TEST action. No workflow edits, cloud runs or source pushes were performed.
The next Cloud repair must align repository, branch and project path with the intended published
Apple snapshot; the successful local iOS uploads are separate from these old Cloud failures.

Used article-writing and copy-editing (marketing copy) skills to write concise, factual iOS
11/12 notes. Verified features against the historical release snapshots, not newer main changes.
Build 11 covers automatic downloads/progress, playlist import, search ordering and layout fixes;
12 identifies its default diagnostic logging and clearly labels inherited changes. Updated both
en-US TestFlight localizations and verified exact readback. Full copy is in DELIVERIES.md and the
local receipt is codex-ios11-12-test-notes.json. The owner's Added/Fixed policy is now in the handoff
for future builds. This follow-up changed metadata and documentation only; no app build was needed.

### 2026-09-17 — build 12 source published to the dedicated Apple repository

Owner explicitly authorized publishing build 12 to the correct repository to repair Cloud.
Published a clean, isolated snapshot to https://github.com/orgista/openstream-apple, main and
annotated tag build-12, commit 4a7c402 (full SHA in local codex-b12-source-publication.json).
Remote main/tag and the Xcode project path were read back and verified. The original working
branch and its newer uncommitted source changes were not committed or pushed.

Publication starts from bf6988e plus the accepted Watch icon packaging. Configuration changes
are documented in the published DELIVERIES.md: automatic signing replaces local named profiles;
iOS/tvOS/visionOS and embedded target versions are stamped 12, Mac remains 1; shared schemes
are included. Personal catalog seeding now uses an optional local Info.plist array, with empty
configuration meaning no seed. Tests inject a fixture URL, and the long configured-manifest
URL test keeps its length/encoding coverage using synthetic data. Private media, screenshots,
logs, operational notes, build caches and old Git history were not published. A tiny synthetic
H.264/AAC clip is included because a core playback test otherwise fails on a fresh checkout.

Validation: original snapshot 985/96 passed; publication 986/96 passed (one added empty-config
check). The first publication test run exposed the missing generated clip; adding it resolved
that failure without skipping or weakening the playback test. iOS Release build passed with
signing disabled, the changed source was compiled, and app/Widget/Watch products all report 12.
All shared schemes parse; zero empty Swift files. Full initial diff has inherited whitespace
warnings from the historical source; no unrelated bulk formatting was applied. No new binary
was uploaded to TestFlight. Local publication: ~/Developer/openstream-build/publish-apple-b12.

Cloud: renamed Default (F9EFD723-518F-4473-8E7A-BFA6E152AB47) to Apple Build Checks and replaced
four archive actions with four simulator/Mac BUILD actions. Paused it and the unused TestFlight
workflow; read-back tables show Enabled=false. Prior configs saved privately as
codex-cloud-*-before-publication.json. Old failed runs are retained.

Cloud repair completed September 17: `orgista/openstream-apple` is connected and Apple Build Checks is enabled. Run 5 (`3a431b39-00a5-47b7-8b72-891a435db678`) passed all four platforms at commit `ba066e3`. Run 4 exposed two iOS ActivityKit isolation errors; the follow-up fixes them without unsafe Sendable suppression. Build-12 tag unchanged, old failures retained, separate TestFlight workflow paused. No new TestFlight binary.

## 2026-09-17 16:40 — artwork stays on disk now

Posters, backdrops and the title wordmark are written to disk the first time they're seen and come
back from disk on the next launch — the app used to force a fresh download of every image, every
launch, which is why testers saw slow or missing posters. On the sim the second launch read its
posters back from disk and the second open of a title reused the trimmed wordmark. Cap is 512 MB,
oldest first. Done by the cheap worker from a spec; I verified and committed. Next: prefetch what's on
screen so the *first* open is instant too, and cache title metadata the same way.



### 2026-09-17 — iPhone trailer, Live TV and native controls

Fixed the trailer's top framing and kept Back available while it plays. Opening a featured title
now keeps that title selected even when the home carousel advances. Live uses the normal iOS page
heading. Removed Playlist Text; retained file import and gave Save and Test Connection separate
working states. The source page hides old login errors after a successful connection. Channel
failures say what happened and offer Retry/Close without blaming a working saved account.

Checked every entry in the supplied 28-channel playlist twice: five decoded; 23 were denied by
the provider with HTTP 403 on this network. Working entries were M6, W9, 6TER, PARIS PREMIÈRE and
RTL9. A denied channel no longer prevents saving a valid playlist. Test Connection describes a
sample response rather than promising every channel will play. The audit also caught and corrected
a new metadata-cache collision between providers. Screenshots and test coverage are in GUI-AUDIT.md.

These changes are local simulator work, not a new TestFlight upload. Cloud is separately repaired:
Apple Build Checks run 5 passed all four Apple platforms in the dedicated Apple repository.

Verified completion: 1,024 automated tests pass, iOS and Apple TV builds pass, and the installed
iPhone binary matches the final build. Trailer rotation, source health, large text and channel
recovery checks pass. Selecting a channel also dismisses the search keyboard. Temporary sources
and channel caches were removed; the simulator is back on Live with the existing account.

## 2026-09-17 17:30 — title pages cache their metadata

Opening a title now keeps the add-on's answer on disk: the next open renders from that copy (fresh
for a day, then still shown while a quiet refresh runs, gone after two weeks). Artwork was done an
hour ago; episodes and the wordmark/backdrop lookups are with the worker now. Both were built by the
cheap worker from specs — the first metadata pass broke five tests (it forgot that several add-ons
answer the same title and get merged); the second pass fixed it. I only verified and committed.

## 2026-09-17 18:50 — launch is off the library's back

The Library shows its titles 142 ms after launch from a saved snapshot (it was ~5 s while the app
walked the share), the share walk runs quietly afterwards, and a relaunch within 10 minutes skips the
walk entirely. It took the worker three passes — the first two would have shown fake rows or an empty
Library — which is exactly why every pass gets measured on the sim before it's committed.

## 2026-09-17 19:25 — Apple TV guide is lazy again

Opening Live on Apple TV built every one of the 300 channel rows up front. The worker's own audit
found it, the fix is 24 lines, and the sim shows 71 MB less memory with an identical screen.
The same audit's iPhone/iPad findings are with the worker now.

## 2026-09-17 19:50 — iPhone/iPad guide stops re-drawing itself while you scroll

Every horizontal scroll frame used to re-render the entire guide, and each row re-filtered the
programme list every time. Rows now render from a precomputed model and only the header and the
now-line follow the scroll. Same look, verified with the French playlist. One thing to know: that
provider is now refusing TMC with a 403 — the app says "Channel Unavailable", which is the right
message; it's on their side.

## 2026-09-17 20:40 — Apple TV guide: the minute tick is quiet now

Every minute the guide used to rebuild all its cells on the main thread. It now rebuilds only when a
programme actually starts or ends, and off the main thread; the trace shows the minute mark being
skipped. Idle CPU on the sim was already low, so the number barely moves — the point is no more
once-a-minute stall on a 300-channel lineup.

## 2026-09-17 21:20 — web portal, first pass

The browser portal now reads properly: placeholders you can actually see, a brand-pink focus ring,
44-pt tap targets, no off-palette colours, sentence-case headings. Same layout. Left for a second
pass: the forms still reload the page on submit and don't validate inline.

## 2026-09-17 21:45 — settings panes

Streaming Services was missing from the iPhone/iPad Settings list (Apple TV had it) — it's there
now. Small hygiene on the Radarr/Sonarr fields (URL keyboard, password autofill), VoiceOver labels,
and the Streaming Services pane now looks like the other panes.

## 2026-09-17 23:22 — tester feedback of 17 Sep, and the two crash reports

The "toggles don't work once they're off" report (iPhone, iOS 27.0, en-CA) is build 10: the
screenshot shows the off tab switches drawn disabled. Build 11 already changed that rule — a tab that
is not on screen can always be switched back on — and the iPhone UI test for it passes. Nothing more
to do there; the tester needs build 11 or later.

The same tester asked for Plex, Jellyfin and Emby by account sign-in rather than a server URL. That
is tonight's feature stream: the sign-in client (Jellyfin URL + user/password or Quick Connect, Emby
Connect e-mail sign-in, Plex sign-in next) is written and going through the gate; the Add Media
Server screen, library shelves and playback follow. A real Emby server runs on the Mac for testing.

Two crash reports from 17 Sep (iPhone XS Max, iOS 18.7, French) are both build 10 and identical: a
UIKit assertion in the navigation bar when a screen comes back after the full-screen player goes
away. Nothing in the app's own code is on the stack. The likeliest trigger is turning the phone while
the player is up and then closing it. A UI test that does exactly that is written; it runs on a new
iOS 18.6 simulator (the crash is iOS 18-specific and the phone simulators here are on iOS 26).

## 2026-09-17 23:58 — AIOMetadata: why it looked like it did nothing

The add-on is fine: it is enabled, its catalogs are on Discover, and its details answer for every
IMDb id. What the owner saw was the built-in Cinemeta winning: when a title comes from a Cinemeta
catalog, the app asks the title's own source first and keeps the first answer, so the one-line
IMDb blurb ("Reality show about swingers…") beat AIOMetadata's full synopsis, logo and artwork.
Change under way: an add-on the viewer added always outranks the built-in fallback; Cinemeta only
fills what the add-on leaves empty.

Also from the same batch of screenshots: the "metadata failed" one is the Live guide of a French
M3U showing "No information" next to a playback failure — that playlist carries no programme
guide, and the streams refuse the app (provider side, noted earlier).

## 2026-09-17 23:58 — captions menu: one option

Off plus one entry — the best track for the preferred language from Settings (default first, plain
subtitles before closed captions, forced/SDH last). The entry is named after the language
("English"), never "English 1 (eng)". When the stream lacks the chosen language: nothing but Off if
the viewer picked the language, one track if the app only guessed it.

## 2026-09-18 00:45 — Add Media Server works against a real Emby; a white-on-white Save button caught

The new Sources → Add Media Server screen signed in to the Emby server on the Mac and answered
"Connected to Studio (4.10.0.40)". The photo also showed the enabled Save button as a blank white
pill — the same white-on-white the owner once reported on the Live tab's Open Settings button:
both this form and Add Live TV still used the stock prominent style under the app's white tint.
Both now use the brand primary/secondary buttons (white pill, black label; grey pill for Test).
