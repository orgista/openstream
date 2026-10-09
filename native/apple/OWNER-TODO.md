# OpenStream — owner to-do list

Every piece of feedback the owner gives goes here the moment it arrives, as a checkbox, before any
work starts. Ticked only when it is merged into main **and** installed on the devices; the commit
goes on the line. A request that has been asked for before is marked **(asked again)** so it is
never dropped a second time. Detail and evidence stay in `FEEDBACK.md`; this file is the list.

## Open
- [ ] **Apple TV "Set Up from iPhone" fails: "Couldn't import this setup." (owner 2026-10-09, build 17, real Apple TV +
      real iPhone).** Scanned the QR with the iPhone; the TV showed that error with Show New Code / Close. Investigating.
      **Same TV, Library:** a warning row reads "ServerPlus: You don't have permission to save the file 'OpenStream' in
      the folder 'Application Support'." Likely root cause of both: real tvOS can't write Application Support (only
      Caches/tmp), while the tvOS sim allows it. Also, raw error text must not show in the UI.
      **Fixed 782bac9 (needs a new build on the TV):** confirmed cause: the media index lived in Application Support;
      the import's watchlist restore threw NSCocoaErrorDomain 513 and failed the whole import. Apple TV now keeps
      those files under Caches (`AppleStorageLocation`); import skips parts it can't keep instead of failing; the
      Library no longer shows the raw message. Proof: unit test with a read-only Application Support, and sim to sim
      with the owner's config (TV's Application Support made read-only): "Setup imported · 8 sources", Library 462
      titles, Live 3,924 channels.
- [ ] **UX overhaul before the App Store (owner 2026-10-09, build 17, iPhone iOS 18.7 portrait). Test on the iOS 18.6 sim
      with the owner's config.** Owner: "no ton of bugs, it's UX"; the back end is good (Live plays fast, the guide loads fast).
      **Cast & crew:**
      - [x] (1) Not every face sits in its circle; some are cut off. Use face-aware crop. **Fixed a8c0855** (Vision face
            crop, iOS 18.6 sim before/after in verification-artifacts/ux-ios18-2026-10-09).
      **Trailers:**
      - [x] (2) Trailers have NO audio. **Fixed a8c0855:** autoplay starts muted; the sound control or Play Trailer
            turns sound on (checked in the app trace on the iOS 18.6 sim).
      - [x] (3) No mute/unmute control. **Fixed a8c0855** (small speaker control, top right under Search).
      - [x] (4) **Fixed a8c0855** (art holds until real frames, 0.4 s crossfade, no art jump; frames in after/). Glitchy start: it flashes as the trailer begins (e.g. "Ticketmaster" from the Disney+ shows row; Spider-Man
            Brand New Day). Needs a graceful crossfade from art into video. Capture frame-by-frame.
      - [x] (5) Paused state shows a play triangle inside a circle inside a circle; that's bad UI. **Fixed a8c0855**
            (one play.fill).
      **Heroes (Discover + Library, iOS portrait):**
      - [x] (6) The hero is cut off and not centred, playing or paused. Art is out of place / too zoomed in; the crop is
            broken. Research how Plex, Jellyfin and the big streaming apps do portrait heroes (face/subject-aware framing,
            portrait or textless art). **Fixed b354bd1 + 12b2c91:** textless poster art at 1.25 × width, chosen before it
            draws, no trailer in the iPhone hero; trailers play in a 16:9 header on the title page (no zoom, one paused
            play glyph). Shots: verification-artifacts/hero-redesign-2026-10-09/after.
      **Live (needs a full redesign; owner likes Paramount+ Live best, DirecTV somewhat):**
      - [ ] (7) The player is a cut-off box. While playing there's nothing showing which channel you're on, in the
            player or the guide.
      - [ ] (8) Remove or rework the All / Favorites / News / Sports / Entertainment bar. It also floats and jumps on
            scroll.
      - [ ] (9) The "Live" title + search wastes space. Make the video bigger; Live can live elsewhere.
      - [ ] (10) The translucent tab bar over the guide: hide it while browsing the guide and bring it back on scroll,
            or similar.
      - [ ] (11) How do I get to pay-per-view?
      **Fullscreen Live player:**
      - [ ] (12) The X top-left looks tacky.
      - [ ] (13) The "Channels" / "Last Channel" buttons look tacky.
      - [ ] (14) The progress bar is big, loud and cheap-looking; it should be subtle and clean. Going LIVE works.
      - [ ] (15) The back button and the enlarge icon look odd; use SF Symbols / Apple-standard controls.
      Good: mute works, the sleep timer is fine (check "end of program"), captions work.
      **Settings:**
      - [x] (16) Remove "Export Working M3U" (greyed out, pointless); it belongs in the full backup if anywhere.
            **Fixed a8c0855.**
      - [x] (17) Can't find where to scan a QR code to set up or sync. Make Set Up from iPhone / Send Setup easy to find.
            **Fixed a8c0855** (both rows under Backup & Sync at the top of Settings).
      **Library:**
      - [x] (18) "Your provider's movies and series are unavailable": say WHICH provider. **Fixed a8c0855.**
      - [x] (19) The Library hero has the same crop problems as (6). **Fixed b354bd1** (same hero as 6).
      **Live error:**
      - [x] (20) **Fixed a8c0855** (an unreachable or blocking panel now says "Can't reach <provider>."; the stream limit
            only when the panel reports it). "Your live TV account has reached its stream limit" is shown, but the owner thinks it's our network
            block. The message must match the real cause (an IP block / unreachable panel is not a stream limit).
      **Process (owner):**
      - Research the streaming apps (Paramount+ Live, DirecTV, Plex, Jellyfin, YouTube TV).
      - Run designs past the skills (impeccable, ui-ux-pro-max), then Fable; if Fable's design isn't better, try Mythos,
        else the best design tool or skill available.
      - Live needs many research agents.
- [ ] **Picture in Picture for Live (owner 2026-10-09, build 17):** "if I swipe away it stops playing". Swiping home
      while a Live channel plays should continue it in PiP (iPhone/iPad), same as movies. Being built.
- [ ] **iPhone Duo support (2026-10-08)** — the foldable iPhone (iOS 27.1) ships 10-23. Done: audit of everything
      that assumes one screen size (verification-artifacts/duo-2026-10-08/AUDIT.md) and fixes written as patches,
      held back so tomorrow's App Store build is untouched: the app stays portrait-only on the big inner screen
      (fix: it rotates there like on iPad), the Live channel restarts when the window changes shape on iPad and
      would on the Duo (fix: it keeps playing), and the big screen gets the phone's hero, Live layout, channel list
      and Settings instead of the iPad's (fix: they follow the screen size, not the device type). The patches pass
      all 2926 tests; the iPad-simulator resize run (rotate on Home, a title page, a playing video, Live) is written
      but did not run tonight (build machine busy with release prep). Left: apply the patches after the release,
      run that test on the iPad simulator, then check on the Duo simulator (real screen sizes, half-folded poses, 4K
      quality on the inner screen). **Blocked on you:** download Xcode 27.1 beta (needs your Apple developer
      sign-in) onto the Mac mini.
- [ ] **App Store submission 2026-10-09 (owner 2026-10-08: "apple store submission will be tomorrow").**
      **Checked tonight:**
      - App Store Connect "validate":
        - iPhone/iPad passes with 0 errors.
        - Apple TV and Vision Pro have no build attached.
        - Mac has no build and no screenshots.
      - The support page (orgista.com/support) and the privacy page (which covers oStream) are live.
      - Every bundle has a privacy manifest.
      - The local-network prompt no longer says "add-ons".
      - The private-repo user-agent is gone.
      - Build 16 passed Beta App Review (Reddit).
      - The public Jellyfin demo login now fails (HTTP 400), so the review notes rely on the Apple sample M3U only.

      **Tonight (agent, once the UX tour frees the build lock):** a release-candidate run of the App Store
      flavour (add-ons compiled out) from main:
      - check-no-addons, sdk-floor, the strings audit.
      - A clean Release install on each of iPhone, iPad, Apple TV, Vision Pro and Mac. Each must show No Sources;
        then the review-notes M3U plays.
      - Every Open item for those platforms fixed, or listed as a known issue.
      - Duo layout changes stay out of main until after submission.

      **Release-candidate run done (2026-10-08 night, e855f12):** iPhone, iPad, Apple TV and Vision Pro pass on clean
      installs (No Sources, the no-content line, sample playlist plays, Settings pages, no add-on words). Mac builds and
      launches; its screens were not checked. Fixed: the review notes said "paste the playlist" but there was no Paste
      (added); debrid/torrent words were left in the App Store binary (removed); Vision Pro Live category buttons were blank
      (fixed). Gate 2919/371. Report, known issues and the **new review notes to paste into ASC**:
      verification-artifacts/rc-2026-10-09/RC-REPORT.md. **YOU, besides (1)-(4):** paste the new review notes; host
      the playlist at orgista.com/openstream/review.m3u for Apple TV (or drop that line); decide whether "Radarr &
      Sonarr" stays visible in the App Store build. Build 17 = e855f12 or later.

      **YOU:**
      - (1) ASC → App Privacy → "Data Not Collected" → Publish. The API can't confirm it.
      - (2) Say **"ship 17"**. That builds the TestFlight build plus the separate no-add-on App Store archive for
        all four platforms, attaches them, and swaps out old build 10 on iPhone.
        **TestFlight half done 2026-10-09:** build 17 (08f57a5, add-ons on) is on TestFlight for all four
        platforms, Internal + Reddit (DELIVERIES.md). The no-add-on App Store archive is NOT built or attached:
        that needs your separate OK.
      - (3) Mac screenshots need `sudo /usr/sbin/DevToolsSecurity -enable` on Dev-Mini (Screen Sharing).
      - (4) Pick manual release.
- [ ] **Live doesn't work with the owner's config (2026-10-08, build 16)** — being tested on DevPlus with the
      owner's imported backup alongside the trailer bug.
      **Fixed, waiting for your phone (2026-10-08):** your provider's channels take 12-16 s to show the first
      picture (the stream opens in ~3-4 s, the first segment arrives a few seconds later), and the app gave
      every channel only 10 s before calling it dead, then retried and fell back the same way: 0 of 5 played.
      A channel that is open and sending now gets 15 s more (dead channels still fail at 10 s). On the mini's
      iPhone with your setup: CBS and FOX both play (first picture ~14 s). Still slow to start; making it
      faster is engine work for later.
      **More fixed (2026-10-08 evening):** (1) your panel's login check gave up after 7 s; on the mini's iPhone
      simulator it missed that and the whole channel list failed, which on a phone with no saved list leaves Live
      empty. It now waits 20 s, like the channel download. (2) A list refresh asked for while another was running was
      dropped, so Live could sit on "No Live Channels" after adding or importing a setup until the app restarted;
      it now runs right after. (3) The new "can't reach Live" screens are redone (below). Not proven with your
      provider yet: from 17:10 to 18:10 its panel did not answer this network at all (also 20 s), so no channel could
      be tried on the simulator; worth a look on your phone after the next build. **~18:50 probe:** the address still
      resolves (same answer from home DNS, 1.1.1.1 and 8.8.8.8; hosted on CDN77 NYC), but every port times out from the
      Studio, Dev-Mini and ServerPlus (no refusal, no ping; packets die at the host's edge). DevPlus logged in fine
      this morning from the same network, so this looks like the provider blocking our home IP after today's test
      logins (or the panel being down). YOU: open Live on your phone with Wi-Fi OFF. Works on cellular = home IP is
      blocked (usually lifts within a day; else ask the provider); fails there too = the provider is down. Test
      agents told to stop logging in.
- [ ] **"New dialog in Live when it can't reach Live looks off and weird" (2026-10-08, build 16)** — it was an alert
      ("Playback Failed" + advice paragraph + Close/Retry) that popped up over the whole Live tab whenever the resumed
      channel could not start, plus a warning row with the system's error text over a working list.
      **Fixed, waiting for your phone:** the message now sits inside the picture ("CBS is not broadcasting right now",
      the server's name on one quiet line, Try Again); the guide under it stays usable. A list that can't refresh
      while its saved channels show says nothing. With no channels at all: "Couldn't Load Your Channels", Try Again,
      Open Settings (same as Discover). Screenshots: verification-artifacts/live-2026-10-08/.
- [ ] **"Did not return a compatible source" on iOS (2026-10-08)** — sweep 100 random movies + episodes from
      different eras with the owner's config on DevPlus; table in verification-artifacts/playback-sweep-2026-10-08/.
      **Swept 2026-10-08:** 100 titles (20 per era, pre-1970 to 2020s, movies and episodes) with your config on
      the mini's iPhone: 86 played (median 2.8 s to the picture). The "compatible source" message came up 0 times:
      it only appears when an add-on sends nothing but torrent-only/YouTube/web links, and your Torrentio TB sent
      real links every time. What failed: 9 not cached on TorBox yet, 4 where Torrentio had nothing at all (the app
      wrongly told you to "add a stream source"; fixed, it now says nothing was found), 1 TorBox error video.
      If you see the message again, note the title: it points at a different add-on or your TorBox account state.
      Table: verification-artifacts/playback-sweep-2026-10-08/SWEEP.md.
- [ ] **Apple TV has no Live and no way to import (2026-10-08)** — Apple TV only gets its setup from iCloud
      (broken, fix in progress) and has no import. QR "send setup to Apple TV" moves first in the QR work.
      **Import done in code (2026-10-08), waiting for your test:** the Apple TV can now take the whole setup
      (Live/IPTV, add-ons, media servers, network shares, sign-ins, settings) straight from your iPhone over the
      home network, no iCloud needed. See the QR line below for how to try it.
- [x] **Remove notices around the app (2026-10-08)** — About no longer says "a subsidiary of Raster Inc.";
      the TMDB/JustWatch/no-content (i) buttons are gone from Welcome, Sources, the TMDB key page and the
      watch-provider line. The credits stay once in About › Data Sources (TMDB requires it even with your own
      key) and on the empty No Sources screen (App Review).
- [ ] **Set up a new device by scanning a QR code (owner 2026-10-08):** a new device (Android/Google TV,
      Apple TV, iPad…) shows a QR code; scanning it with a phone that already has OpenStream sends the
      whole setup over the home network. Should work Apple→Apple and Apple→Android. **Apple→Apple built
      (2026-10-08), waiting for your test.** How to try it: on the Apple TV open Settings > Sources >
      **Set Up from iPhone**. A QR code appears. Point the iPhone's Camera at it and tap "Open in oStream", then
      **Send**. The TV asks "Import setup from <your iPhone>?" — press **Import**. Both need to be on the same
      Wi-Fi; the code works once and for 10 minutes. On iPad/Mac the same row is in Settings > Sources, and on
      an empty iPad/iPhone it is also a button on No Sources. Still to do: the button on the Apple TV's empty
      No Sources screen (that file was being edited by the trailer work), and the Android TV side (the format
      is written down in HANDOFF-NEXT-SESSION.md).
- [ ] **iCloud sync still looks broken (owner 2026-10-08):** owner doesn't think it works and doesn't know how
      to test it. Fixed in code, waiting for your test: a phone set up before sync was on by default never sent
      anything to iCloud, so the other devices found nothing. Now it sends at launch, when the app comes back,
      and on the new **Sync Now** button whenever iCloud has nothing or an older copy (never from the Apple TV,
      an empty device or a reset one). Backup & Sync now shows "Last sent / Last received" and how many sources
      are still waiting for passwords from iCloud Keychain; the Apple TV shows the same under Settings > Sources
      > iCloud Sync. Waiting sources also look for their passwords again each time the app comes back.
      **How to test:** on the iPhone open Settings > Backup & Sync and tap Sync Now ("Last sent" updates). Then
      open oStream on the iPad or Apple TV: "Last received" should show a fresh time and the sources should not
      be waiting for passwords. Needs a build with this change; real two-device iCloud can't be tested on the
      simulators.
- [ ] **Build 16 trailers still broken on the owner's iPhone (2026-10-08):** the trailer flashes for a split
      second then disappears; tapping a different trailer in the Trailers shelf doesn't reliably play it.
      The pre-ship check on the mini's iPhone 16e passed (1.65 s, demo data), so it reproduces with the
      owner's sources/phone only. Plan: owner cables the phone to Dev-Mini once (trust + Developer Mode),
      then e2e over the cable or Wi-Fi with traces.
      **Fixed in code, waiting for your phone (2026-10-08):** with your imported setup on the mini's iPhone
      (iOS 27) the trailer did not flash, so the exact cause on your iPhone 15 Pro Max (iOS 18.7) is not
      proven. Three things that could do it are fixed: (1) the page picked its trailer by its place in the list,
      and the list changes while a trailer plays (TMDB's trailers arrive and are put first), so a different
      video could replace the playing one mid-play; it now keeps the trailer it started. (2) The one-minute
      cap could use a too-short length the player reports as it starts and end the trailer right after it
      appeared; short lengths are now ignored. (3) A tapped trailer could be overridden by the page still
      looking for a replacement for an earlier one, and the press unmuted the old trailer for a moment; both
      fixed. Every way a trailer goes back to the art now writes its reason to the trace. Verified on the
      mini's iPhone with your setup (ad hoc Release 16.2): trailer still playing after 10 s, Trailer 2 tapped,
      switched and kept playing. If it still flashes on yours: Settings > Share Diagnostics right after.

- [ ] **Vision Pro: player lives inside the app window, resizable** (asked 2026-10-07; today it opens a separate
      "Player" window). Fable audit for direction → implement → overnight visionOS e2e on Dev-Mini. Also a Mythos
      security check and a project audit — reports in `verification-artifacts/audit-2026-10-07/`.
      **Status 2026-10-08:** built, uncommitted. The player now opens inside the oStream window; the window keeps its
      width, turns 16:9 (or the film's shape) and resizes uniformly while playing, and returns to its size on close.
      visionOS e2e on Dev-Mini: 4 passed, 1 skipped (below). Waiting for commit and a check on the real Vision Pro.
- [ ] **Vision Pro: audio kept playing after the app window was closed** (reported 2026-10-07, previous TestFlight
      build). Fixed, uncommitted: the player now stops (and saves the resume point) when the window leaves the
      foreground. The simulator cannot close a window or background the app from a test, so this needs a device check.
- [ ] **Vision Pro: audio keeps playing after the app is closed** (owner, 2026-10-07, previous build). Being fixed with the
      in-window player: the player stops (and saves your place) when the window closes; e2e test added.
- [ ] **Vision Pro environments** (owner, 2026-10-07). Apple's own environments (Mount Hood, Moon, etc.) can't be bundled,
      but the full-window player docks into them when you pick one with the Digital Crown — verify on the device. Next:
      our own "theater" environment (an immersive space with a docking spot for the screen), after the player work.
- [ ] **Vision Pro traces:** device isn't paired with Dev-Mini. Owner: Settings → Share Diagnostics → AirDrop to the Mac.
- [ ] **Security fixes from the Mythos check (2026-10-07)** — nothing critical. 1–3 + subtitle bomb + Messages links FIXED
      2026-10-08 (tokens in cache files: protected + kept out of backups, not yet removed). ATS (4) WON'T DO (2026-10-08): IPTV playlists, guides, logos and
      remote media servers are often plain http; narrowing would break them. Code already forces https for TMDB/Trakt/etc.
      (1) HIGH: Xtream guide (EPG) URL with the password is saved in plain preferences — keep it in the Keychain only;
      (2) the web-portal diagnostics download and some trace lines can include stream URLs with credentials — redact;
      (3) Plex/Jellyfin tokens in cached URLs; (4) ATS wide open — narrow to media + local network. Report:
      `verification-artifacts/audit-2026-10-07/mythos-security.md`.

- [ ] **(2026-10-06) Owner decisions:** ~~don't ship 16 yet~~ **shipped 16 on 2026-10-08** (TestFlight Internal, all four
      platforms, f08a908; see DELIVERIES.md); **no DVR/recording** (dropped); Apple TV (Wi-Fi) and the owner's
      iPhone (cable once → Trust) get paired with the Mac mini on 2026-10-07 — then install the waiting ad hoc build
      (`scripts/mini.sh 'zsh scripts/release/devplus-install.sh 16 00008130-000610103443001C'`); go ahead with the Mythos Live review fixes; make an OpenStream backup of the
      owner's own sources to import for content verification on DevPlus.

- [ ] **(2026-10-06) Mythos Live TV review → Opus.** Findings with file:line and fixes in
      ~/Developer/openstream-build/specs/live-tv/mythos-live-review-2026-10-06.md. Top three: the XMLTV guide is
      re-downloaded and re-parsed every 15 min of viewing (first zap after 15 min pulls the whole file); dead-channel
      failover exists only on Apple TV, not iPhone/iPad/Mac; multiview reopens all four streams on every
      grid↔full-screen trip. Order: 1 → 4 → 2 → 5 → 3 → 6 → 8 → 9 → 7 → 10 (numbers in the review).
      DONE a9e2594: 1 (guide fetched ≤ every 6 h, 304-aware), 4 (failover + one quick reopen on all platforms),
      2 (200k-programme guide 25 s → 2 s). Next: 5 → 3 → 6 → 8 → 9 → 7 → 10.

- [ ] **(2026-10-06) Your IPTV on DevPlus — app bug fixed (3614aaa), provider too slow tonight.** Opening a channel
      started it twice (the saved lineup auto-started your last channel, then the link restarted it 4 s later), so
      nothing ever played. Fixed and verified on DevPlus: one start, one connection. But CBS and FOX (East and West)
      all arrived at ~40% of real time (≈3 s of video per 6.5 s) at 23:40, so none reached a picture. **Your check:**
      does the same channel play right now in another player (VLC/TiviMate) on the same Wi-Fi? If yes, it's on us
      (look at connection count / user agent); if no, it's the provider. The Mac mini can't reach the panel at all.

- [ ] **(2026-10-05) Live TV for Apple TV — built, needs your Apple TV (build 16).** Multiview (up to 4 channels,
      a9b71b9); instant/correct guide, guide matching, account info + clear login errors, catch-up error, hide/reorder,
      sleep timer, Match Content, reminders (f1276f0); channel up/down + banner, Last Channel, resume last channel
      (8ed357d); Start Over, live buffer, Top Shelf/Siri channels (4abfaac); provider movies & series (189dd18); parental
      PIN + import progress (8c29e10). Research + gap report: ~/Developer/openstream-build/specs/live-tv/gap-report-2026-10-05.md.
      DVR dropped by the owner 2026-10-06; Apple TV PiP built (7165a8e).

- [ ] **(2026-10-04) App Store submission, what's left.** App Store Connect is filled for all four platforms: name
      **oStream**, subtitle, description, keywords, promo text, support/privacy/marketing URLs, copyright "2026 Raster
      Inc", categories Entertainment + Photo & Video, content rights, age rating 16+, review notes with Apple's public
      sample playlist (the public Jellyfin demo now needs a password, so it's no longer in the notes), and screenshots
      for iPhone, iPad, Apple TV and Vision Pro. Validation: iPhone/iPad 0 errors. Left: **you** fill App Privacy → "Data
      Not Collected" (website only); **"ship N"** builds the App Store (no add-ons) build and attaches it to all four
      platforms — the iPhone listing currently has old build 10 attached, which must be swapped; Mac screenshots need
      `sudo /usr/sbin/DevToolsSecurity -enable` first.
- [ ] **(2026-10-04) Channel lineup back as "Complete Guide".** You asked to bring back the biggest US package preset
      under another name. Codex is restoring it in all builds; it only organises your own IPTV playlist and defaults to
      Everything when your playlist doesn't match it.
- [x] **(2026-10-04) Short app names.** Under the icon: oStream (all platforms, Share, Messages, Watch, widgets);
      App Store name oStream. Inside the app it's still OpenStream. (368be0c)

- [ ] **Apple TV regression on the overnight code (2026-10-01 morning):** fixes committed 2026-10-01 (gate 2519/303).
      Done, checked on the sim: 3 dead IPTV panel (error + Retry by ~9 s, was ~21 s), 5 Clear Cache label, 6 search
      exact title first (stale half-typed results re-ranked), Show Captions opens on the checked value, My Channels
      spinner. Done, unit-tested only (needs a real-stream check on the Apple TV): 1 captions stay above the
      scrubber/Next card on widescreen, 2 stock player advances at the end (+ Apple's "Next Episode" button in the
      last 20 s), Resume label. 4 long series: every episode loads (Goede Tijden 7,333, was 1,000) and a soap with
      nothing watched opens on its latest season (unit-tested; check Goede Tijden on the Apple TV).
- [ ] **Owner decisions 2026-10-01 (afternoon):**
      1. FINAL: "native player with our engine" — remove the Player choice; always the OpenStream engine shown in
         Apple's player (Infuse-style). Native stays as a hidden debug override only. DONE 4440c97 (sim-checked).
         Kept on tvOS: an MP4 still opens straight in AVPlayer first — moving it onto the engine made a Dolby
         Vision MP4 (Mad Max) fail in the engine's demuxer ("Invalid data"); if the direct play fails, the engine
         takes over automatically. Investigated: the DV MP4 is fine (faststart, opens in ~1 s in the engine outside
         the sim) — the sim failure was a one-off open error with no engine log to explain it. Next (engine lab):
         send engine logs into the trace, retry a failed open once before moving to the next source, then re-try
         MP4-on-engine for tvOS.
      2. Remove from Continue Watching keeps Resume (already so). Add a "Start from Beginning" choice next to
         Resume on the title page. (in progress)
- [ ] **Build 15 feedback (owner, real iPhone, 2026-10-03):** (1) trailers still don't play (title page hero stays
      dark; Masters of the Universe 2026) — build 15's pre-ship test covered playback/resume, not trailers;
      (2) title page shows two refresh-looking buttons (global refresh + trailer replay). Fixing on Codex with
      iOS 18.6 + iOS 27 sim proof; trailers added to the pre-ship test list.
- [ ] **CarPlay (owner ask 2026-10-03) — not in build 15:** YOU request at developer.apple.com/contact/carplay/ for
      com.orgista.openstream: Video (`com.apple.developer.carplay-video`, iOS 27+) AND Audio (so it appears in every
      CarPlay car; video-only shows only in cars with parked video). After Apple grants it: CarPlay scene + icon,
      parked video, Live TV/audio while driving, gate video behind a capability check (iOS 27 beta blank-screen bug
      on non-video head units), test in CarPlay Simulator. Research: muse-results/34-carplay-video-parked.md.
- [x] **Build 15 shipped 2026-10-03** to TestFlight Internal (iOS, tvOS, visionOS, macOS; add-ons kept), all VALID —
      see DELIVERIES.md.
- [ ] **App Store push (owner 2026-10-02: assume the bridge works, get the app ready to publish, then move on to the
      next app).** Running: Codex batch A (server discovery on your network, Quick Connect as the default on Apple TV,
      Dolby Vision/HDR/SDR + audio line in player info, Release first-run leads with Media Server); work Claude
      (App Store submission pack: description/keywords/review notes/legal demo/privacy label/screenshot list, and
      an Apple app playbook for future apps at Code, Apps & Websites/Apps/APPLE-APP-PLAYBOOK.md). Next: downloads
      from your media server; Release screenshots; then "ship" when you say so.
- [ ] **Add-on route DECIDED 2026-10-02: Cloudflare bridge (Rill, github.com/mrtxiv/Rill, MIT).** Each user deploys
      their own free bridge to their own Cloudflare account (Deploy button), pastes add-ons into its page, and
      OpenStream signs in to it as a Jellyfin server — works anywhere, free, Orgista never touches it, App Store app
      has no add-on code. Remux removed from ServerPlus (container, image, data). Add-on code kept in the repo
      behind a build switch (Debug/sideload/Mac Developer-ID on; App Store/TestFlight compiled out). DEPLOYED
      2026-10-02 to your Cloudflare account (wrangler, no GitHub needed): https://rill.xcxhcprtpj.workers.dev
      (D1 "rill", queue "rill-jobs", free plan) + custom domain https://stream.ourzephyr.com (personal domain on purpose — keep streaming off orgista/Raster domains). Source: ~/Developer/openstream-build/bridge/rill; update =
      `npm run build && npm run deploy` there. YOU: open the address now and create the Rill account (first
      visitor claims it), add your add-ons, then test in OpenStream (Add Media Server › Jellyfin).
      Private fork: github.com/cyberbanksy/stream-bridge (push needed: `cd ~/Developer/openstream-build/bridge/rill
      && git push -u origin HEAD:main`). Security audit (specs/codex/rill-audit.out): NOT safe as-is — malicious
      add-on artwork (SVG) could take over the settings page; config links embed your password + add-on keys in
      reversible form; public routes can be abused; no login throttling; its build pulls upstream code at deploy.
      HARDENED + DEPLOYED 2026-10-02 (fork branch `hardening` b43c981): builds/deploys only our code, no auto-update,
      owner-only helper routes, raster-only images + size caps, outbound policy, same-origin settings, login
      throttling, revocable sessions, AES-GCM-encrypted add-on keys (key in ~/Developer/openstream-build/signing/
      rill/RILL_DATA_KEY — back it up), third-party features off. D1 backup taken first. Remaining: DNS-rebinding
      SSRF gap (platform limit); root still sends a harmless invalid CORS combo. YOU: sign in again, change the Rill
      password (old one was stored reversibly), then add your add-ons. Push: `cd ~/Developer/openstream-build/bridge/
      rill && git push -u origin hardening`.
- [ ] **iPad full pass 2026-10-02 (0fcee5b):** most pass (no crash with artwork, badges, Start from Beginning, subtitle
      delay, audio language, next episode, reconnect, catch-up, search, latest season, Remove from CW). To fix:
      HIGH: player ignores taps for long stretches — the title page behind it keeps recomputing source badges + a
      whole-library disc check on the main thread; HIGH: iPad Live guide cells draw over the channel column;
      Playback Unavailable shows raw engine text; Watch Live overlaps the speaker icon on the inline player; full-
      screen catch-up has no way back except the guide. Expected: Play Disc = main title until the engine fork is
      pushed. Rotation not testable headless.
- [ ] **Apple TV full pass 2026-10-02 (9c0be32):** most new features pass (reconnect, Watch on other list, catch-up,
      latest season, Start from Beginning, recent searches, disc badge, Play Disc/Skip to Movie, no tab replay).
      P0 FIXED 0e9a6d5: every on-demand play with artwork crashed (Now Playing artwork, from 40e9350) — verified.
      FIXED 4a866d8 (sim-checked): TMDB notice in full; Live categories from your playlist's groups; guide titles
      for shows that started earlier; channel numbers; row names read naturally (no "· Cinemeta"); search puts
      General Hospital 1963 first. Blank tab after fast hops: couldn't reproduce — added a safety net that rebuilds
      a tab that never appears. Re-checked after the crash fix: Subtitle Delay, Frame Rate, title-page badges,
      Playback Unavailable all work. Dropped per you: catch-up player chrome, special disc title page.
      Small: "Playback Unavailable" for a title with no streams says "details only" — wording could be clearer.
- [ ] **Engine lab DONE (fork branch engine-lab, 9 commits, NOT pushed):** 98 test files/servers (4.4 GB, off the repo)
      scored automatically. Fixed 5 engine bugs: MKV seeks landing one group late, debrid servers that ignore Range
      (hung 45 s → works), HDR10 MKV with no colour tags never showing a picture, software-decoded seeks near the end
      killing playback, TS seeks never showing a frame. Seek speed passes 55→71 of 84, seek smoothness 63→70.
      Next round: AV1 stutter after seek, truncated files stalling 12 s, interlaced TV freezes, VC-1 ending early.
      Push both fork branches: `cd ~/Developer/openstream-build/AetherEngine-fork && git push -u origin dvd-menus engine-lab`
- [ ] **DONE da014fb (2026-10-02):** IPTV catch-up from the guide (back up to 3 days, plays a past programme from its
      start, Watch Live returns; sim-checked on Apple TV — iPad build only); Discover rows neutral + Top 10 off;
      channel lineup test-only; recent searches; offline UI-test stubs + smoke tests (pass on iPad + Apple TV);
      iCloud restore no longer rewinds Resume; "Forced"-only subtitle tracks never auto-picked. Open: a deleted
      add-on can come back after iCloud sync; search tab position on tvOS (kept first per your 09-14 call).
- [ ] **Live TV DONE d018726 (sim-checked with a local fake IPTV server):** a dropped channel reconnects by itself
      ("Reconnecting…", 3 tries), then offers "Watch on <other list>" for the same channel; tvOS guide shows 7 channels
      × 3 hours (was ~4.5 × 2.3) with now-airing progress, Left goes to categories. Not done: catch-up from the guide
      (needs past listings + a play action + panel time zone) and live rewind on raw TS channels (engine buffer).
- [ ] **Open-source / public repo (2026-10-01) — specs/oss-public-readiness.md:** history scan (410 commits): no signing
      keys, .env, API keys or IPTV logins anywhere. But: (1) your AIOMetadata config URL (its id is a login token) is
      in the code — being moved out now; RECREATE that config in AIOMetadata. (2) 2.3 GB of movie/TV rips sit in git
      history (Tests/Fixtures/private/) plus build folders, ServerPlus IPs in notes/screenshots, 21 commits under your
      work email. No LICENSE yet. DECIDE: publish a fresh single-commit public repo from today's code minus the
      exclude list (recommended; keep the old private repos archived — never flip them public), and the licence
      (recommended Apache-2.0; MIT or MPL-2.0 also fine; engine/FFmpeg are LGPL, dynamically linked, so any works).
      DONE dd4e101: AIOMetadata URL out of the code (Debug catalogs now come from your private dev-sources file —
      put the NEW config there after recreating it); rips + build folders untracked (still on disk); full
      third-party notices in About. (i) credits + Source Code link DONE cfa0bb7.
- [ ] **Disc looks + badges DONE 987ce0a (sim-checked iPad + Apple TV):** disc badge on posters, turning-disc
      spinner, Play Disc / Skip to Movie (both play the movie until the engine menu is wired), Titles row, format
      badges (4K, Dolby Vision, HDR, Atmos, 7.1, Remux) on title pages only — the Quality picker stays plain per your
      09-24 rule. Engine retries a failed open once; engine logs in the trace; add-on paging actually works now.
      Known: Jellyfin/Plex disc items get no badge; VIDEO_TS/BDMV folders play as plain files (engine opens images only).
- [ ] **App Store compliance audit (2026-10-01) — specs/app-store-compliance-audit.md:** Apple pulled every app built
      around Stremio add-ons (Stremio Lite Jan 2026; Reelo, Omni, Fusion Aug 2026 — Reelo even after removing add-on
      install). Survivors (Infuse, SenPlayer, VidHub, IPTVX, Swiftfin, Channels) = "player for your own content".
      DONE a6765b2 (sim-checked): test add-ons seeded in DEBUG only (rotate the AIOMetadata keys anyway — they were
      in earlier TestFlight builds); torrent client removed; TMDB/JustWatch credits + "we don't provide any content"
      line; no "Stremio" in the UI (a test enforces it); About no longer links the private repo. Also caught: the
      Release build didn't compile (fixed). Note: the TMDB logo is blue-green — their terms require it unaltered.
      DONE 2026-10-01 (uncommitted, gates green): (3) rows keep the add-on's own catalog name (id→brand map
      AppleCatalogServiceName deleted), Top 10 off by default; (4) lineup JSON moved to Tests/…/Fixtures/ChannelLineup
      (Debug/test only, Release ships none → Premier Guide hidden, package defaults to Everything, playlist tvg-logo).
      (1) add-ons + (2) downloads: owner wants to KEEP both (incl. downloading away from home) in a safe way, e.g.
      add-ons configured online and synced. Researching: a server-side bridge (our own open-source "OpenStream
      Bridge" or Remux) where add-ons are set up on a web page and the app just signs in to "your media server" —
      downloads then come from your own server; plus a second build with native add-ons outside the App Store.
      Research done (specs/addon-bridge-options.md): every removed app ran add-ons ON the device; no add-on app has
      passed review since Aug 2026 (Vidi/All The Media haven't been re-reviewed). Recommended: App Store build = a
      generic Jellyfin client (no add-on code) + an "OpenStream Bridge" = Remux (open source, runs on Unraid/NAS or
      hosted) where add-ons are set up on its web page; add "download from your server" (~1 week); keep native
      add-ons in a Mac Developer-ID build + sideload build. Orgista-hosted accounts = possible but we'd become the
      aggregator (DMCA, user keys, bandwidth) — only as a deliberate business. DECIDE: go with the bridge plan?
      Owner still has the live App Store listing text to check by hand.
      Ideas picked by Claude (owner delegated), in order: engine lab with smooth seek as a gate; dead live stream →
      restart, then same channel from another list; format badges; denser TV guide; IPTV catch-up + live pause.
- [ ] **Ideas from Strand + iProTV (2026-10-01, pick what you want):** smooth seek (no black flash) as a gate test;
      App Store risk — Strand pulled Stremio add-ons to pass review (fallback: Remux, add-ons behind a Jellyfin API);
      IPTV catch-up/timeshift + live pause; denser TV guide (TiviMate-style, Left → sidebar); IPTV multiview 2–4;
      "watch without tracking" / rewatch / shuffle; hand-off to Infuse/VLC keeping Trakt; per-Apple-TV-user
      profiles; Simkl + local watchlist; format badges (DV/HDR/Atmos); sports scores; iOS 27 external display
      (video on TV, controls on phone); first-run guide. Dead IPTV stream → offer the same channel from another list.
- [ ] **Muse research triage (2026-10-01):** 229 findings from 6 Muse jobs → 92 already handled, 30 gaps, 71 to
      verify (specs/full-test-checklist-v3.md). Batch 1 DONE 40e9350: Subtitle Delay + Frame Rate fix (sim-checked),
      Settings › Audio Language (sim-checked), Spotlight opens the title, add-on catalog paging, Now Playing series/
      episode/artwork (not seen on a sim), honest "could not read this file" instead of "ended early". 20 more Muse
      jobs queued on ServerPlus. Next: disc badge/spinner/Play Disc, format badges, engine open retry (running).
- [ ] **ISO / disc images (owner 2026-10-01):** today ISOs play the main title only. DECIDED: Apple disc symbol in the
      poster corner (A2) + that symbol spinning while the disc opens (S1); "Play Disc" opens the real DVD menu first,
      "Skip to Movie" plays the main title (D2) — menus are part of the experience; Disc Menu button in the player (P1).
      Engine forked (github.com/cyberbanksy/AetherEngine, public — LGPL-3.0 + App Store exception, so our engine
      changes are published; keep rebased on upstream). Phase 1 DONE (disc menu structure, button highlights, the
      DVD menu "brain", 70 tests, test disc) on branch dvd-menus in ~/Developer/openstream-build/AetherEngine-fork —
      NOT pushed: pushing was blocked by permissions. Owner: run `cd ~/Developer/openstream-build/AetherEngine-fork &&
      git push -u origin dvd-menus` or allow it. Phase 2 DONE (6 commits on dvd-menus): menus play on screen with
      button highlights, remote/touch/pointer input, stills, setup menus, Play Disc (`.menu`) vs Skip to Movie;
      97 DVD tests incl. an end-to-end menu → title → back-to-menu test. Open: menus are silent, resume restarts
      the cell, tiny gap on looping menus, multi-angle, no real-disc/Apple TV test yet. Phase 3 (wire into the app)
      needs the fork pushed so the app can depend on it.
- [ ] **Owner asks 2026-10-01 (evening):** use Muse's 2B tokens for research at scale (it's the Meta Model API /
      developer console, not meta.ai chat — needs an API key); on-device processing + ML + Apple silicon ideas;
      end-to-end tests for the iMessage app and iCloud sync on a real iPhone over USB (test Apple ID).
- [ ] **Apple TV smoke of 22125ac (2026-10-01):** all pass (hero buttons, title art, Resume, no tab-switch replay,
      Goede Tijden S37, search order, Settings readable, 0 crashes). Polish: season picker opens focused on Specials
      not the checked season; Settings › Playback bottom row, Left doesn't reach the sidebar; faint metadata line
      over bright art (Goede Tijden).
- [ ] **iOS 18.6 iPhone regression (b4d4793, 2026-10-01):** no hang (5 titles incl. General Hospital S64), Resume,
      next episode, no tab-switch replay, English-only captions, Live error ~9 s, configure-first, 0 crashes. Open:
      FIXED (sim-checked on iOS 18.6): hero Play Trailer over the preview gets sound; title-page art comes back
      (the art itself failed to load — now tries the next image); hero shows Play only when something plays; a
      swipe pages the hero; "£" → "♪" in subtitles; General Hospital 1963 first; VoiceOver no longer reads icon
      names. Still: "A Different World" search lists the 2026 show above 1987.
      Minor: title page flashes between auto-advanced episodes; CW time left uses the stream's length (director's cut).
- [ ] **iPad regression of today's fixes (2026-10-01):** 10/11 pass (Resume, latest season, next episode, captions,
      IPTV error ~9 s, configure-first, Remove from CW, rotation, search, 0 crashes). Open:
      1. FIXED (sim-checked on iPad): switching tabs back to a title page no longer starts playback by itself
         (it replayed ~2 s later; series played a wrong episode and wiped Resume). Likely in builds since 09-25.
      2. Question: after Remove from Continue Watching the title page still says Resume (progress kept). Intended?
- [ ] **Apple TV check of 630db1d (2026-10-01):** pass: Goede Tijden opens on Season 37, stock player advances to the
      next episode, widescreen captions clear the scrubber, SNL 1975 first, Clear Cache readable, 0 crashes.
      Fixed in 5298e1c (unit-tested, not yet re-checked on the sim): Resume… shows however the title was opened;
      tvOS "Configure this add-on first." is plain text; stock player shows the real title (not "2023"); with
      Player = Native, MP4 sources come before MKV for the next episode; seeded sims no longer get the test catalogs
      (AIOMetadata is seeded on purpose in Debug/TestFlight). Still open:
      3. FIXED e8b60ec (sim-checked): stock player froze after a seek (AVPlayer stuck waiting with media buffered);
         it now plays what's buffered after 4 s.
      5. FIXED (sim-checked): Resume… now shows on Apple TV (the button was hard-coded "Play"); the player shows
         2015, not "2023"; on the stock player MP4 sources go first and MKVs are skipped instead of ~100 black-
         spinner retries. When every stream fails there is now a "Playback Unavailable" alert;
         on Native it offers "Try OpenStream Player" for that one play (sim-checked). DECIDE above still stands:
         switch automatically instead of asking?
- [ ] **iPad re-run (v2, 2026-10-01 morning):** 6 of the 9 iPad bugs from 09-30 fixed; next episode, SNL 1975,
      chapters, subtitle More… + encodings, resume after kill, rotation all pass. New / still open:
      1. HIGH: "Watch on <service>" never shows when an IPTV or SMB source exists (hasPlaybackRoute counts them,
         though they can't play catalog titles).
      2. HIGH: debrid placeholder clips ("Debrid failed to split torrent… only rar") play as the episode and
         auto-advance through the season; SNL then drops out of Continue Watching.
      3. Live tab waits ~35 s on one unreachable IPTV panel before showing other playlists.
      4. Still open: Hail Mary title page text instead of logo; title-page margins 40/16; Settings not split in
         landscape; text fields with only placeholders (no labels).
      UX: player icons vanish over bright video; subtitle cue drawn 3× over the Next Episode card; title name doesn't
      scale at accessibility sizes; live stall shows a frozen frame + Play icon; duplicate Paramount+/Peacock tiers.
- [ ] **iPhone 27 re-run (v2, 2026-10-01 dawn):** most fixes since 09-30 hold (chapters, Quality, Also available on,
      watch-link spam gone, row names, metadata on after seed, Stranger Things #1, audio labels + checkmark, subtitle
      More…, menus stay open, long series open fast, encrypted backup). Still broken / new:
      1. P0: Next Episode countdown ends → player closes, the next episode never plays (2/2); Continue Watching
         doesn't show the next episode.
      2. SNL S1E1/E2 still play "Saturday Night Live U K … 2026" — demotion misses "U K".
      3. Sidecar subtitles: Windows-1251 (Russian) mojibake; UTF-16 (Portuguese) shows nothing.
      4. AX-XXXL Dynamic Type: hero/title header collide with the nav bar, Play clipped, scrubber squeezed.
      5. Add Service row only tappable on its label; its top-10 list is still odd; Subtitle Languages first row under
         the nav bar; truncated-file failure shows raw engine text; Live error ".." with no Retry; search results
         still show "AIOMetadata  | ElfHosted"; Quality sheet has no Done.
- [ ] **P0 iOS 18: app freezes when opening a title from Discover** (2026-10-01, iOS 18.6 sim, 3/3; hero or poster
      tap; main thread 100% in the navigation push layout, app frame AppleCatalogItemDetailView.phoneHero).
      Search → title works. Old iOS 18 crash: 0 crashes now.
- [ ] Watch on Netflix opened tv.apple.com when the Netflix app/id was missing — a fallback must stay on the
      labelled service (Netflix search), not jump to Apple TV.
- [ ] iOS 18 UX: nav icons + large "Discover" title unreadable on bright hero art (no glass on iOS 18); Streaming
      Services "Add Service" only tappable on its label; full-screen player not modal for VoiceOver; a search
      deep link with a title page open lands under it.
- [ ] **tvOS verification of 4fd1ac5 (2026-10-01 early):** toggles/Retry readable ✅, cue placement ✅, field outlines ✅,
      audio labels ✅. Still broken: **every Settings Picker on tvOS opens an empty page** (Package, Live view,
      Playback › Player; Menu there quits to Home) — pre-existing; Skip Intro still not reachable with Down; Top 10
      "Wonka's" tile blank (TMDB+Cinemeta share an IMDb id → merge hides the TMDB record from the Top 10 artwork
      match); subtitle/audio menus keep the old checkmark after picking from More…/another track; Channel Manager
      error row draws an empty capsule; captions "off" still auto-selects English on some launches; a sparse-cue
      subtitle shows nothing after a mid-stream switch; UI test testFullSubtitleMenuSelectsSpanish needs updating.
- [ ] **Full-test bugs (Apple TV tvOS 27, v2 plan, 2026-10-01 overnight):**
      1. HIGH: focused toggle rows (Settings › Sources › add-on, catalog toggles) and the "Playback Failed" Retry
         button show no label — white text on the white focus pill.
      2. Opening Rate on a title page drops focus back to Play (B22 regression).
      3. Subtitle menu has no "More…" — non-preferred languages (Spanish) unreachable.
      4. Audio menu shows raw labels ("ENG (ac3) (eng)") and no checkmark on the playing track.
      5. Search "stranger things": the 2013 movie ranks first, twice (Cinemeta + TMDB not merged); 2016 series 3rd.
      6. Truncated file reports "format OpenStream cannot play" instead of an incomplete/network error.
      7. Skip Intro appears but Down from the video never reaches it.
      8. Channel Manager: Package page blank and My Channels spinner endless when the IPTV panel is down.
      9. Local playlists/channel health stored in Application Support — check tvOS purge safety (Swiftfin's #1 issue).
      UX: subtitle cue drawn on the scrubber line; tvOS form fields have no outline and an invisible placeholder;
      Live search "Clear Search" is red; weak focus in the guide; Top 10 "Wonka's" tile blank.
- [ ] **Streaming services must be useful, not just a label** (2026-09-30): when no add-on/source can play a title,
      Play becomes "Watch on <service>" (menu if several of the viewer's services have it), and it must open the
      TITLE in that app, not just the app. Plan: TMDB/JustWatch providers for availability; per-service title IDs
      from Wikidata (Netflix/Disney+/Hulu/Prime/Max/Apple TV by IMDb id) → universal links; fallback = service
      search for the title. tvOS deep links are limited (search/TV app fallback). Overnight: verify which links work.
      **Owner decision 2026-09-30: use Wikidata** for the per-service title IDs.
- [ ] **Test every public Stremio add-on (FMHY + r/StremioAddons + community catalogue)** (2026-09-30) — list, a
      headless harness using the app's own add-on code (manifest/catalog/meta/stream/subtitles), then in-app
      spot checks of flagged + top 20; harness kept for every release.
      **First sweep 2026-09-30 (17d6a4e): 594 probed, 0 crashes.** App fixes found: only movie/series catalogs used
      (78 add-ons show nothing: tv/anime/channel types); 2 MB catalog limit rejects TMDB's 12 MB shelf; catalog items
      without a name dropped (poster-only tiles in Stremio); meta requires an exact id match (Stravo mx→tt) and rejects
      redirects; 12-catalog cap hides catalogs; manifests with no resources accepted (unconfigured AIO Metadata);
      AppleAddonURLSecretPolicy flags 14 public add-ons as secret; 100-item shelves; one subtitle track per language.
- [ ] **Crash reported: the stravio.site add-on crashes the app** (2026-09-30, tester report).
- [ ] **Full-test bugs (iPad iOS 27, 2026-09-30):**
      1. HIGH: after Search → open result → Play, the player's controls/tap area are squeezed into the top 458 pt
         (keyboard height left over); rotating fixes it.
      2. Audio & Subtitles menu closes itself after 2-3 s (auto-hide of the controls closes it).
      3. "Also available on" never appears on iPad with Metadata on + Apple TV/Netflix added (no provider trace).
      4. Hail Mary title page shows text while its Discover hero shows the logo.
      UX: player controls vanish over bright video (no shadow), small 44 pt buttons on a big screen; Settings is one
      stretched list in landscape (no split view); Library hero ~200 pt with the logo touching the edge; title-page
      margins 40 vs 16 pt; duplicate raw audio labels "ENG (eac3) (eng)"; Radarr profile shows raw `7 = "…"`; import
      sheet pushed into the tab bar by the keyboard; unlabeled Search field, key fields and Radarr/Sonarr fields.
- [ ] **Full-test bugs (iPhone iOS 27, 2026-09-30; details in the test report):**
      1. Wrong show plays: SNL S1E1 (1975) plays "Saturday Night Live UK" — stream candidates not filtered by title/year.
      2. Chapters found by the engine (16 for Top Gun: Maverick) never appear in the player/scrubber; Quality item does nothing.
      3. Watch link retries "publish failed — not paired" every 250 ms forever (1,433 lines/25 min).
      4. Library shows "No Videos" when the share refuses access — show the error instead.
      5. Dev seed applies the TMDB key but leaves Use Metadata APIs off.
      UX: portrait title-hero trailer is a blurry crop; See All has no posters; search ranks the 2016 Stranger Things
      3rd; Add Service top 10 is odd (JustWatch TV, Amazon Video; no HBO Max/Paramount+/Peacock); "Metadata Is Off"
      dead end; number pad has no Done; subtitle menu check indent; raw add-on names in row headers
      ("AIOMetadata  | ElfHosted"); Top 10 row pops in above Airing Today; can't clear a rating; Subtitle Languages
      first row under the nav bar; no-backdrop title is a big black area.
- [ ] **Reset: a total wipe of the app on this device** (2026-09-29) — everything incl. downloads; the last step is
      holding the final button for 5 seconds. Owner: device-only; tell the viewer iCloud data must be deleted manually.
- [ ] **Rework the Live GUI — "still not great", wants something better and fresh** (2026-09-29). Start with design
      directions for the owner to pick from before building.
- [ ] **Test fixture: auto-import the owner's sources into every simulator/app for testing** (2026-09-29) — one private
      file on this Mac (never in the repo or OSArchive) + a Debug-only import-at-launch hook + a seed script.
      `scripts/dev-sources.py` (interactive; can pull every add-on from the Stremio account) writes
      ~/Developer/openstream-build/signing/dev-sources.json. Still to build: the app hook + scripts/seed-sim.sh.
- [ ] **Import Backup leaves every source "Needs Sign-In"** (2026-09-29, iOS 18 sim). The file was exported without a
      passphrase, which silently drops all credentials AND the addon URL paths, so even public addons (Cinemeta,
      OpenSubtitles) arrive broken. Fix: public addons keep working without a passphrase; exporting makes the
      passphrase choice explicit; Needs Sign-In rows are tappable to fix.
      **Owner direction 2026-09-29:** the backup always contains everything (passwords included), encrypted so only
      OpenStream on their own devices can read it (key in iCloud Keychain; passphrase only for another Apple Account),
      and restores with no Needs Sign-In. Also: the Enabled toggle on imported sources can't be turned on — fix.
- [ ] **Hero title logos (word art) not showing — plain text title instead** (2026-09-29, iOS 18 sim screenshot:
      "JEOPARDY!" in bold text over the backdrop).
- [ ] **Play Trailer tap turns sound on** (owner decision 2026-09-28: yes). Autoplaying hero trailers stay muted;
      an explicit Play Trailer press unmutes.
- [ ] **Streaming services: keep the quiet "Also available on …" line only (owner chose option a), but make it
      easier to spot** — no Play replacement, no service rows.
- [ ] **Subtitles menu still lists every language instead of defaulting to English (asked again)**
      (2026-09-28, build 14). The earlier fix (FEEDBACK.md "A picked language was not the only option")
      only filters strictly when a language was explicitly picked; with device defaults and no exact match it
      still falls back to every track. English should be the default and the only entry.
- [ ] **Streaming services setting: an "Add" menu instead of the long list, top 10 by popularity only**
      (2026-09-28). Owner also asks what turning one on does — toggling Netflix on showed no visible difference.
- [ ] **When a trailer ends it should go back to the movie art** (2026-09-28, owner) — today it stays on the
      finished video.
- [ ] **iPhone crash: UINavigationBar layout assertion** (TestFlight crashes on builds 10 and 12, iOS 18.7, 4 of 4
      readable reports; one tester comment "Search"). Owner shared another crash on build 14 today — not yet
      in App Store Connect; read it when it appears.
      **Build 14 crash read 2026-09-29** (AMKnSe6teuQS5qAin8cixtU, iPhone 15 Pro Max iOS 18.7.8, "Just scrolling the
      app"): same assertion, reached from a layout pass while scrolling Discover, with loadTop10 running. 305af48
      (not in build 14) removes the Discover Refresh item flip; hardening the scroll-driven hero layout too.
      **Root cause found 2026-09-30:** tapping the tab you're already on rebuilds that tab's navigation stack
      (`.id` bump), which iOS 18 rejects — 24/24 crashes on the iOS 18 sim, build 14 AND main. 305af48 did not fix
      it. Fix in progress: pop to root without rebuilding; deep links too.
- [ ] **iCloud sync / backup on a new device (asked again)** (2026-09-28, iPad, build 14): a fresh iPad with no
      sources gets nothing from iCloud, so there's no content, and there's no visible backup/import to
      bring the setup over. Make iCloud sync switchable on and working on a fresh install, and make
      backup/import easy to find from the empty state. **Fix committed 66e2d46** (sync on by default, fresh
      device pulls, keychain retry, Restore/Import buttons on No Sources) — tick once installed (build 15).
- [ ] **iOS trailers don't play** (2026-09-28, build 14). Failures are silent by design; asked the owner whether
      Auto-Play Video Previews is on and whether Play Trailer on a title page fails too.
- [ ] **iOS Live TV subtitles are out of sync — they appear too late** (2026-09-28, build 14; they show up now).
      **Fix committed 1f3f9f0** (cues follow the on-screen frame, not the scrub clock) — tick once installed.
- [ ] **Apple Intelligence** (2026-09-28): owner asks where it could help when available. Ideas to propose.
- [ ] **Remove a specific title from Continue Watching** (2026-09-28; clarified 2026-09-29: per title like Netflix,
      not hiding the whole row). Progress is kept; it comes back if played again.
- [ ] **Discover Rows reorder is hard to use** (2026-09-28, Mac screenshot): the list of ↑/↓ chevrons
      works but isn't friendly for long moves (about 25 rows). Make it drag-and-drop (or similar) on
      every platform, keeping a non-drag way for Apple TV and accessibility.

## Waiting on an owner decision

- [ ] **UX tour 2026-10-08: four calls for you** (details in verification-artifacts/ux-tour-2026-10-08/FINDINGS.md):
      (1) the iPhone/iPad player has no Picture in Picture or AirPlay button; PiP only starts when you leave
      the app. Add both to the top bar like the Apple TV app? (2) Discover and Search each have a Refresh button;
      Apple TV dropped it. Remove it on iPhone/iPad/Mac too? (3) There is no Share button on a title page. Add one?
      (4) Long-pressing a Discover poster opens it, while Library/Continue Watching posters show a menu, and a
      shelf's "See all" is a plain text list. Give every poster the menu and make "See all" a poster grid?
- [ ] **YouTube attribution.** The trailer frame CSS (N49) hides YouTube's title, channel and link;
      the fast iPhone/iPad trailer start (a130f96) relies on it. YouTube's API terms may require
      showing it. Keep it, or go back to the fixed wait on iPhone/iPad?
- [ ] **Trailers with the title burned in.** Some trailers open on their own title card, so on the Mac
      hero a faint second wordmark shows behind ours (N57). Keep those trailers, or skip them?
- [ ] **Apple TV row headers** are 76 pt, about twice the Apple TV app's 38 pt. Shrink to match?
- [ ] **"Remove the gradient"** — the screenshot was lost (2026-09-25). Which gradient? Retake it.
- [ ] **iPhone tab bar shrinking on scroll** — allow it (the system behaviour), or keep it fixed?
- [ ] **Receipt check (N39 F1).** The app tells TestFlight builds apart (to turn tracing on) with
      Apple's deprecated receipt URL, the last build warning. Its replacement is async and can put an
      App Store sign-in prompt on the Mac. Keep the deprecated check (recommended), or switch?
- [ ] **ServerPlus 3090:** passed a full overnight bench test on Windows (2026-09-27, 350 W, 0 errors), so it may
      be the DEG1/OCuLink path at 3090 power. The server runs a 2080 Ti for now (11 GB: the 27B local
      model is slow). Next: capped run on the server (200 W + locked clocks), or a new dock, or return it.

## Done

- [x] **Refresh spinner too big / poor UX** — the refresh arrow now stays the same size and turns
      while the tab reloads (iPhone, iPad, Mac, Vision Pro) — e4b8dee, installed 2026-09-26.
- [x] Crash report pasted 2026-09-26: **PosterBoard** (Apple's own screensaver process) in the Apple
      TV simulator, 01:09. Not OpenStream; it crashed inside Apple's framework while loading screensaver
      posters. No app change.
- [x] Narrow Mac windows: no decision needed any more. Since N62 the trailer covers the hero at
      every width; checked 2026-09-26 at 900 and 1100 pt wide on main ab12598, no black strip.
- [x] **Remove the "New Episode" pill** (asked several times) — gone from every hero (iPhone,
      iPad, Mac, Apple TV) and from the title pages ("New Season" / "New Episode Every …" too) —
      c9010e7, installed 08:45; Apple TV Dark Matter hero checked without it.
- [x] Discover row order is a setting (Settings → Discover Rows); Featured Movies / Shows can move
      above Your Library — 74a479e (N67).
- [x] If a streaming service (e.g. TorBox) is down, fall back to the next best one — 74a479e (N68).
- [x] Mac trailer no longer letterboxed in the hero — e92c9eb (N62).
- [x] Wordmark first; the text title only if the wordmark fails for 5 s (no swap/shift) — e92c9eb,
      7c6328d, 1ba00a9 (N62–N64).
- [x] Clicking a trailer on the Mac title page plays it; the trailer autoplays there — 28f7fb7,
      d3e116a, d513f8e (N69–N70).
- [x] Trailers reveal fast on iPhone/iPad — a130f96 (N75).
- [x] Apple TV white-on-white dialogs (Discover Rows, SharePlay source, Download Options) readable;
      destructive rows red — a2381dc, e60e277, 02d3e0e, abd9754 (N71–N74).
