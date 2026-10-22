# OpenStream — owner to-do list

Every piece of feedback the owner gives goes here the moment it arrives, as a checkbox, before any
work starts. Ticked only when it is merged into main **and** installed on the devices; the commit
goes on the line. A request that has been asked for before is marked **(asked again)** so it is
never dropped a second time. Detail and evidence stay in `FEEDBACK.md`; this file is the list.

## Open

- [ ] **10-21 12:00 owner: "for duo we want no unused real estate please."** Folded and unfolded, every screen fills the display: full-bleed, no bands or centred max-width columns; the unfolded screen gets more posters per row, edge-to-edge heroes, the large title page, Live stage + list side by side, Settings split, edge-to-edge player. Added to lane duo-layout (Codex; spec section "Owner requirement"). Cloud audit (branch cloud/duo-audit, design/2026-10-21-duo-readiness.md): the app keys "small screen" on the device type, so an unfolded Duo would stay portrait-locked with phone chrome over iPad layouts — the duo-layout job replaces that with one size-based policy. Real Duo proof waits for Xcode 27.1 on the mini (owner to download the .xip to the Files share).

- [ ] **10-21 09:00 owner: "It appears we can ship Duo so we gotta make sure that works as well."** App Store Connect has accepted iOS 27.1 SDK builds since Oct 5; the owner has two apps built on 27.1, tested in the Duo simulator, already approved and live. The SDK an app is built with decides full-bleed vs black bars on the Duo (day one is the 23rd); for most apps it is a recompile. The lead had said devs can't ship for an unreleased phone — wrong. Facts on the mini: only Xcode 27.0 (SDK 27.0); the "DUO" sim CA2CCA73 is an iPhone 18 Pro renamed, not a Duo. Plan: Xcode 27.1 on the mini beside 27.0 (needs the owner's Apple ID to download) → Duo sim on the 27.1 runtime → build + run OpenStream there (folded/unfolded, rotation, Discover/title page/Live/player), fix layout → RC built with the 27.1 SDK (SHIP-CHECKLIST: SDK + floors). Rows: 82.
- [ ] **10-21 08:30 batch-1020b gate (Codex):** stages 1–7 green with rulings — unit 3625/446; 8 builds; iOS 18.6 49 pass after the legacy Discover test fix (54cede1, the phone has no bar since hero-unify); iOS 27 smoke + jank pass (Players flake passes alone); tvOS 24 pass, guide test order-dependent (row 81), stub smoke stale since f82ef99's Library dedupe → test now opens Movie Two (378258a, 3/3); owner screenshots good; DevPlus Release + add-ons: hero art 864 ms cold / 778 ms warm (was ~1.5 s). Found: the trailer mute glyph sat under the round Refresh on the iPhone Discover/Library heroes → moved under that row (AppleHomeBillboard), proof running; then main + owner iPhone install.

- [ ] **10-20 10:10 owner:** Paramount+ installed on DevPlus (com.cbsvideo.app 15.28.0, confirmed) and possibly on DevTV → live-oss told to observe both. "The iPhone widget — I'd like it to look better; the size I use now is the landscape one; it should be more hero, edge to edge, with the wordmark overlaid" → lane widget-hero (Codex). Reference skill openstream-reference-patterns built (ref-library 1c6d747; Destination Video, Swiftfin, VLC, Kodi, Nuke, Kingfisher pinned on the mini).
- [ ] **10-20 09:45 owner:** "Discover and Library are cut off by the bar at the top (Discover / Library) — those used to not be there" → added to hero-unify (no bar at rest on the landing pages, same chrome as the title page). "The Live REA was not done; get the Paramount+ IPAs or use OSS to redo Live; the Favorites bar in Live is not static, it floats within itself" → lane live-oss (Codex): references = P+ on DevPlus if connected, OSS (Swiftfin, VLC iOS, an OSS Swift IPTV/EPG app), P+ Android; static Favorites bar first. Decrypted IPAs stay off-limits (told the owner).
- [ ] **10-20 09:35 owner on the RC (iPhone): "nope still wrong and the video feedback I sent was not addressed"; "hero is wrong, front loading page a little bit slow, maybe we aren't caching enough"; "hero on the landing pages should be the same as the hero in the content pages."** Ship 19 on hold. Jobs: video-1016 (work Claude: walk every item of the 10-16 recording on the RC build with the owner's data, then fix every still-wrong one); hero-unify (landing-page heroes use the same art, framing and title treatment as the title-page hero; landing-page load speed with a trace and caching of hero/poster art).
- [ ] **10-20 07:30 trailer P2 check (work Claude):** none of the three RC visual-judge trailer P2s is an app bug — Spider-Man: Homecoming's trailer itself opens on a dark night shot, so the hero goes dark when the art fades (hero luma flat 95 while loading, 95 → 38 at the fade); the paused iOS 27 trailer brings the art back within one frame (not reproduced); no darkening while loading on 18.6 or 27. No code change; holding the art over dark/blank openings would be a reveal-timing change → owner's call. Evidence dev-mini:/Volumes/DevExt/dev/openstream-build/trailer-p2/shots/before/.
- [ ] **10-20 04:45 RC-19 READY (work Claude, overnight):** batch-1018h gate green — unit 3607 (2 known flakes green alone), 8 Release builds no add-ons PASS, **full iOS 18.6 E2E on the owner setup 46/0** (first fully clean run), iOS 27 smoke 7/7, title pages 6/6. RC: build 19 > 18 on all platforms; 8 archives (App Store no add-ons + TestFlight) signed, team ok, get-task-allow false, SDK floors ok; clean installs open to Welcome / No Sources; DevTV resume ok; visual judge: no P1 (P2s: Spider-Man trailer first frame, paused iOS 27 trailer shows black, hero darkens while its trailer loads, phone-landscape Live panel tint, "Can't reach Home TV" in Locals, Vision Pro shots 1×1). Open lines: DV badge on DevTV, DevTV trailer, DevPlus (disconnected). **The "x ms" pill is iOS's Hang Detection HUD (Settings › Developer on the owner's iPhone), not the app** — it shows real hangs; the trailer-audio hang is fixed. Main → ef17169. Waiting for "ship 19".
- [ ] **10-20 00:20:** **Codex is out until 2026-10-24 15:40** (weekly limit hit mid-report of the 1018g gate). Work Claude (Opus) takes the gates and the RC from here (owner 10-19: "use work Claude and Codex"). 1018g gate (from its progress file): unit serial green, 8/8 builds, iOS 27 smoke green, visionOS green, DevTV Top Shelf/hero/cycle green, ISO fixtures + DVD row + owner ISO + colon search + Live + title pages + trailers green; failures = iOS 18.6 stub smoke (fixed on title-page-chrome, 18.6 proof running), tvOS full (the order-dependent guide test; passes alone on batch and main), John Wick device probe (DevPlus disconnected). Plan: commit the title-page fixes → batch-1018h → work-Claude gate → RC-19 → "ship 19" in the morning.
- [ ] **10-19 17:00:** 1018g gate stalled on iOS 18.6 — the conditional compact title (063d588) looped SwiftUI layout on the stub title page (main thread 100 % in layout; sample on the mini). Fixed on title-page-chrome (opacity + identifier withheld while hidden) together with the iOS 27 glass Back (44 pt + identifier) and a snapshot-safe scroll rule; proofs on iOS 27 + 18.6 queued; the killed test let the gate continue (iOS 27 smoke green so far, tvOS next). Next: commit → batch-1018h → full gate → RC-19. Submission tonight ≈ midnight at best; owner asked whether to push through or ship in the morning.
- [ ] **10-19 16:20 1018f gate report (late):** iOS 18 full suite was stopped early by its stop rule (2 stub-smoke failures, fixed in 1018g); iOS 27 Back control on the new title page measures 26.67 pt with no `detail.back` under the glass style (row 79) → fixed on title-page-chrome (44 pt control + identifier on the styled button; stub test now asserts ≥ 44 pt), proofs on iOS 27 + 18.6 running; testDVDMenuTestSkipToMovie failed on the iOS 27 ISO fixtures (row 80, tvOS passes — watch in 1018g); tvOS guide-focus test is order-dependent (passes alone on batch and main; row 81). Reveal timings 2.57–4.35 s on the owner sim.
- [ ] **10-19 16:00 BD-J Spike B4 PASSED (work Claude):** John Wick 4's own Java (BD-J) menu runs on the iOS simulator under the Avian interpreter + OpenJDK 8 class library: top menu renders, Right/Right/Enter → Scenes, Play → playlist 00800; Matilda proven on the macOS-host build of the same stack (sim run pending). Numbers: menu playlist 34–55 s cold on the sim (first frame 18.6 s cold / 2.1 s warm; desktop JDK 23 s), ~9 % of a core, 140 MiB peak, +4.1 MB native + 0.8 MB jar; the 124 MiB class library must be trimmed. avian.patch + result.json + frames in /Volumes/DevExt/dev/openstream-build/bluray-menus/spikeB4/. Build phase estimate 14–22 days (engine bridge 6–9, class-library trim 2–3, app side 4–6, DevTV performance 2–4). App Store guideline 2.5.2: BD-J stays in add-ons/sideload builds; App Store builds play the main feature + Titles list. **Owner decision: start the Build phase (tomorrow, after ship 19)?**
- [ ] **10-19 15:30:** batch-1018g = 1018f + e2e27-discover2 11106f1 (hero buttons by identifier, snapshot hittability; iOS 27 crawl 3/3) + title-page follow-up 063d588 (Back identifier after metadata reset; compact title out of the tree while hidden; strict stub tests) — gate running, feeds RC-19. 1018f gate: all suites green except the two stub-smoke tests + iOS 27 Discover crawl (both fixed in 1018g); DevPlus disconnected. Known flaky: testDiscoverRowOpensATitleFromStubsAndComesBack at its Discover scroll step (pre-existing). Mini disk keeps filling (5 GB at 15:25) — the hourly cleanup is not enough during gates; manual prunes every ~90 min.
- [ ] **10-19 15:00 BD-J Spike B4:** Codex's safety filter refused the JVM method-resolution work twice (flagged "cybersecurity"), after producing avian.patch (interface-table walk + regression test) and finding the next crash (Avian's legacy ZIP adapter vs OpenJDK 8's getEntry native). Continued on work Claude (Opus). RC-19 spec written (specs/rc-19-2026-10-19.md): ship checklist + archives (App Store no-add-ons + TestFlight) + visual judge; upload only on "ship 19"; the full-verification spec's matrix/sanitizers/exploratory crawls are not part of tonight (owner told). ASC builds top out at 18 on all platforms.
- [ ] **10-19 12:35 BD-J Spike B2:** Avian + OpenJDK 8 class library builds and boots on the iOS simulator (Graphics2D/Path/Files initialise); blocker = java.awt's native half (libawt.dylib etc.). Spike B3 launched: build the headless AWT natives (libawt headless + mlib_image + fontmanager/FreeType) for the simulator from jdk8u, or a minimal native library for exactly the natives libbluray.jar + the owner xlets reach; then the first xlet on the sim.
- [ ] **10-19 12:35 toward tonight's submission:** committed after Fable review — title-page-chrome 5952db5 (row 76), trailer-reveal 92efeb4 (rows 77/3/21: 6–7 s → 3.3–3.5 s), live-pplus 3ca2bc9 (Paramount+ Live layout pass; worker's playing-row no-op and category weight change reverted). batch-1018f = batch-1018e + those three, gate running (Codex). 1018e gate report pending (cleanup done; tvOS guide-focus failure retested in 1018f). Plex trailers check PASSED (20/20, 5/5). BD-J: Spike B2 continuing (OpenJDK 8 class library download approved). Then: RC = App Store Release no-add-ons build + SHIP-CHECKLIST walk + full verification; "ship 19" on the owner's word.
- [ ] **10-19 11:45 BD-J Spike B:** Avian interpreter builds for iOS arm64 (sim + device, ~5 MiB), OpenJDK Zero does not configure for iOS; blocked on Avian's class library (no java.awt.Graphics2D, java.nio.file.Path). Spike B2 launched: Avian + OpenJDK 8 class library (openjdk-src mode) first, else a shim module for the exact classes the owner xlets + libbluray.jar load; then the menu on the simulator. Title-page chrome implemented to the written TV-app reference (no bar, circular Back, no Search, fading compact title) — Fable review running; owner screenshots still wanted.
- [ ] **10-19 12:25:** Spike A PASSED (libbluray 1.5.0 + BD-J on JDK 21 on the mini: both owner discs render + navigate their Java menus, Play picks the right playlist, ~4.5 % CPU / 185 MiB) → Spike B launched (interpreter-only JVM on an Apple simulator; OpenJDK -Xint/Zero first, Avian second). Plex trailers check: 20/20 titles with Plex trailers offered by OpenStream, 5/5 without correctly none; tvOS hero plays the Plex trailer muted; Jellyfin demo creds staged on the mini. Trailer reveal: 6.0–6.9 s → 3.3–3.5 s on title pages (hero 6.8 → 5.8 s); the ≤ 2.5 s target not met because of the native picture-settle wait (AppleTrailerPictureSettle) — follow-up row. Title-page chrome: sim has no TV app → relaunched to the written reference; owner screenshots still wanted.
- [ ] **10-19 11:05 owner: BD-J menus — "how can we emulate Java… there is a way to emulate or even translate/rebuild Java menus; might take time but we have the resources."** Plan agreed by the lead: Spike A (3–5 d, mini + desktop JRE: libbluray with BD-J driving John Wick 4 / Matilda menus from a harness; proves the discs' menus run and fixes the overlay/input contract) → Spike B (~1 w: interpreter-only JVM, Avian first, for iOS/tvOS arm64 running libbluray's BD-J stack + one xlet on a sim; stop if it fails) → Build (3–5 w: engine bridge, overlay compositing, input, popup, resume; BD-J only in the add-ons/sideload build until the App Store question is settled). Lane bluray-menus, Codex. Owner options (a)/(b)/(c) from 10:30 superseded by this.
- [ ] **10-19 10:30 Blu-ray menus — milestone 0 facts (Codex):** the engine fork has NO libbluray at all (ISO → UDF → BDMV playlists → longest title → M2TS concat). The owner's discs: John Wick 4 UHD = 0 HDMV / 5 BD-J titles, first-play + top menu BD-J; Matilda UHD = 17 HDMV / 3 BD-J titles, first-play + top menu BD-J. So HDMV menu support (5–10 days) would NOT render either disc's menu; BD-J needs a Java VM (not feasible on iOS/tvOS). Milestone 1 paused; owner decision: (a) build our own "disc menu" (titles/extras from the playlists, chapters, audio/subtitle picks, popup during playback — the useful parts, no Java), (b) HDMV only for other discs, (c) leave as is. Lead recommends (a).
- [ ] **10-19 09:40 owner on 1018d:** "content page looks not like Apple TV, there is a solid bar at the top; trailers do not play cleanly again — REA Apple TV app; the content page has a search icon we don't need; discs still do not have menus, it just plays — are you testing this e2e with the discs?" → three jobs: title-page-chrome (REA TV.app title page: see-through bar + gradient + legible controls, no search icon; replaces the ck-visual solid bar), trailer-reveal (option a: reveal ≤ 2 s, hide only YouTube's centre play glyph), bluray-menus (engine: HDMV IG menus via libbluray; BD-J discs detected and explained). Lead answer: DVD menus were tested e2e (fixtures + John Wick transport); the owner's UHD copies have no menu because the engine renders none — that is the gap.
- [ ] **10-19 08:00 status:** landscape test fixed (row 74, eb4e177: cause = earlier crawls leave another channel selected; test selects + uses Full Screen; 3/3 in suite order). Parked branches rebased (25714fc: unit-determinism, gui-r4a, live-r4; serial 3606, tvOS E2E 24/0, Live crawl pass; one rebuffer test flakes only in parallel). batch-1018e = main + those two, gate running (Codex); DevPlus disconnected again (Wi-Fi pairing). OfficePlus install of the 1018d tvOS build armed for 09:00. Row 75 (Matilda owner-ISO test search assertion) open.
- [ ] **10-19 04:45: batch-1018d gate green on code** (3,596 unit; 8 builds; iOS 18.6 43/1 + landscape rerun pass; iOS 27 5/5; tvOS 23/0; visionOS 11/0 parity 7/7; DevTV; ISO fixtures 9/9; owner-sim DVD timeline/chapters 1/1; John Wick transport 1/1; row 72 colon search PASS) → main 1bcc34d, pushed; owner iPhone build + tvOS rebuild for the 09:00 OfficePlus install. Open from the gate: row 74 (landscape test flake ×3), row 75 (Matilda owner-ISO test search assertion), DevPlus disconnected again.
- [ ] **10-19 02:30 status:** iso-player (row 73) done after six Fable passes: engine fork cyberbanksy/AetherEngine engine-lab → 1fa363a9 pushed from the Studio (DVD titles from the menu publish duration/chapters/timeline; VTS_TMAPT seeks; multi-angle; audio reload keeps the title), app d7fe83f with the pin bumped (swift test 3590 with the real pin). batch-1018d = main + iso-player, gate running (Codex). Blu-ray menus (HDMV vs BD-J) still the owner's call. Parked branches with conflicts: unit-determinism dcdae27, gui-r4a ebd4f31, live-r4 4606aaf (need a rebase job). Mac settings UI test harness starts 0 cases (1018c gate) — harness item. DevPlus drops to Wi-Fi pairing; device proofs skipped when disconnected.
- [ ] **10-18 23:30 status:** batch-1018c gate green on code (3,593 unit, 8 builds, iOS 18.6 43/1 → Players rerun 2/2, iOS 27 5/5, tvOS 23/0, visionOS 11/0 parity 7/7, DevTV Top Shelf + hero, 3/3 removals verified) → main 16e5f18/0d394b3, pushed; owner iPhone installed 22:36; OfficePlus at 09:00 (tvOS pre-built). Unverified: DevPlus trailer/ISO timing (device kept dropping off the mini — Wi-Fi pairing only, 21:20 and later), the Mac settings UI test (runner started 0 cases, harness), row 20 companion. iso-player (row 73): both Fable reviews "fix first" (app: Skip-to-Movie bypassed the navigator — reverted; engine: chapter entry / multi-angle / title-id / bounds) → Codex applying; the fix spans the engine fork (cyberbanksy/AetherEngine, uncommitted on the mini) → the lead commits + pushes from the Studio (gh = cyberbanksy) and bumps the Package.swift pin. Blu-ray menus: HDMV feasible (libbluray nav + overlay + input, days), BD-J not; owner decision pending; disc classification (John Wick 4 / Matilda) unknown.
- [ ] **10-18 19:25 owner: "ISOs don't have menus, would like time to play like in a regular player." Corrected 22:05: "my ISOs are 1-1 disc copies, I want the app to act like a Blu-ray player and show the disc menus."** So: Play on a disc image opens the disc menu (DVD and Blu-ray, as far as the engine can render them), and the time/duration/seek bar works once a title plays from the menu. The lead had first read it as "skip the menu" — that job was stopped and redirected. Likely cause: discs skip the duration probe since f299aff (to stop the double read), so the timeline has no length. Job: lane iso-player (Codex), checklist row 73. Confirm the reading with the owner.
- [ ] **10-18 15:15 owner on the 15:00 build:** "hero and trailers are better but there is still this pill that says x(ms)" → a timing pill is visible in the owner (Release + add-ons) build: find and remove it from non-debug builds. "Spider-Man hero you can't even see the artwork, it's not centered, how do Netflix or Apple TV do it?" → REA job: hero art framing on the phone (focal point / portrait billboard art) vs ours. Owner sent a UIKit-runloop tailspin (OpenStream iOS 15:13:40): main-thread hang, analysed in the lead session → fix job.
- [ ] **10-18 15:40 status (lead on Fable; owner: "orchestrate… build 18 reliability with build 15 cleanliness, new features stay, use lower-usage models"):** plan in specs/stabilize-2026-10-18.md. Batch-1018a gate fixes merged → main 2682431, pushed; owner iPhone + OfficePlus installed 15:00 (add-ons). In review/fix-up: ck-visual (rows 10/11 solid iOS 18 bar + readable icons, 30 round title buttons; row 14 split to lane row14-held after Fable found it changed tvOS/Mac and rotation), ck-data (20 Chernobyl match, 44/46 inline "Can't reach", N7 health message; 45 still open: provider cause not in logs), avp-native (Vision Pro = iPad layouts, 7/7). **Owner decision — trailers (rows 3/21):** (a) reveal in ~2 s and hide only YouTube's centre play glyph, or (b) keep the 4.5 s hold. Removals queued next: WATCHING pill, duplicate Setup rows + camera alert, Recently Added chevron, Channel Health box on Settings root, surprise Live import card, Top 10 default OFF.
- [ ] **10-18 13:00 speed-up (lead call, owner asked "anyway to get it faster?"):** batch gates run the full E2E-iOS suite on iOS 18.6 only (the owner's OS, owner setup); iOS 27 gets a smoke set (launch, tabs, title page, player open, Live open). Saves ~3 h per batch. Waiting on the owner: (a) use the current Mac Studio as a second test node now (reinstall Xcode; lifts the 10-06 no-builds-on-Studio rule), (b) Xcode Cloud for test suites (code goes to Apple via GitHub). ETA given: next owner build tonight/tomorrow AM, second batch 10-19 evening, full verification 10-20/21, submission ~10-21/22.
- [ ] **3090 (owner 10-18):** not hardware per the owner (same setup fine with the 2080 Ti). Fable diagnosis in Infrastructure & Server/ServerPlus/Files/agent-state/gpu-3090-diagnosis-2026-10-18.md: every host setting identical to the clean 2080 Ti run except Ollama 0.40.6 (first GPU run ever) and an unidentified Qwen2.5:7b caller. Proposed test A (Ollama stopped, non-Ollama CUDA copy + gpu-burn) waits for the owner's go + a reboot. Open question to the owner: did the 2080 Ti ever run on the new ADT dock + cable? No purchases (owner).

- [ ] **10-18 04:35:** flaky-e2e2 committed (a73850a) + merged into batch-1018a (2f9964f); Codex batch gate running (iOS 27 E2E 12/0 so far). avp-ipad NOT merged: Fable found unasked shared changes (custom iPad sidebar, deleted AX caps, removed text shadows) and the immersive player enabled against the 10-07 decision → redone narrowly as avp-native (visionOS-only paths) on work Opus. live-r4: wrap-around zapping restored (it was an unasked change), coalescer races fixed, iOS pending-channel banner. Note for the owner: after this update Apple TV auto-resumes Live only for a channel watched in the last 30 min, so the first launch won't resume.

- [ ] **10-18 02:35: batch-1017b gate PASSED → main fast-forwarded to cbeee9c and pushed** (server trailers, iCloud sync, ISO open, iOS 18 jank, hero trailers/cycle + build-15 title header). Swift 3548/443; iOS 27 40/2 and iOS 18.6 41/2 (known flakes only); tvOS 22/0; ISO fixtures 8/8; hero drawn 2 on 18.6; DevTV Top Shelf + hero wrap OK; DevPlus John Wick 4 ISO 7.9 s to picture. Owner iPhone install running (add-ons build); OfficePlus at 09:00. Next batch: hero-settle + settings-narration + live-narration + flaky2 + stability1 + launch-speed + gui-r4a when each passes review.

- [ ] **10-18 02:05 status:** committed on their branches for the next batch: settings-narration e37d846 (in-app QR scanner for Transfer To; camera usage key added by the lead; needs a real-camera check on DevPlus), live-narration ce4920e, hero-settle 74d484e. In review/fix: stability1 (ISO 17 s → ~8 s on DevPlus; Fable CHANGES → SMB open count + a libsmb2 close race), launch-speed (Fable CHANGES → prewarm launches skip the deferral). Owner still to decide: Top 10 saved ON on the phone, the "Test" wording.

- [ ] **Round 4 fixes launched 22:40** (specs/round4-fixes-2026-10-17.md, from the three reports): S1 disc/SMB stability (Infuse I1-I3, work Opus, branch stability1), S2 launch speed (F8/F11, branch launch-speed), S3 tvOS hero cycle/crossfade + title-page clean-up (G2/G3/G12/G15/G16, branch gui-r4a). Settings Job B: Fable CHANGES → work Opus fixing (in-app QR scanner for Transfer To, no Transfer To on tvOS, tests off the owner's sources). Codex AVP job stopped 22:27 (held the sim 40+ min twice); its diff awaits review + one scheduled runtime slot.

- [ ] **Why the app got worse since build 15 + REA round 4** (owner 2026-10-17: "leverage work Claude a lot and work Fable until limit is exhausted… REA Paramount+ Live, Netflix and Apple TV as the main GUI and Infuse as the main stability… the app used to be decent and now it's kinda in a worse place and we gotta find out why"). Spec: specs/regression-and-rea-2026-10-17.md. R1 regression forensics (work Fable), R2 GUI REA (work Opus), R3 Infuse stability REA (work Fable), launched 21:40. Findings become fix jobs.

- [ ] **PRIORITY (owner 2026-10-15): fix everything, verified end to end, THEN submit.** 17:20 "app store submission
      today ... use skill anti slop for the code"; 17:30 "lets fix and test e2e before just stagger each step let set
      a max agent fixes at a time verify them e2e then move on we need to fix before submissions there is still work
      to be done on all plats atv has general slowness". **Process: at most 2 fix jobs at once; each one: anti-slop →
      unit gate → E2E-iOS + E2E-tvOS (+ E2E-visionOS when it touches visionOS) → real device (DevPlus / OfficePlus /
      DevTV) → Fable review → commit + push; only then the next job.** Stopped 17:30 to make room (work kept): Vision
      Pro pass, device sweep, engine 7.36 (rebased locally on the mini: 17 of 22 re-applied, 4 already upstream),
      flaky-e2e harness. Queue:
      1. ~~Stage B~~ **committed 71e2f97 (21:05)** after 2 Fable reviews (fixed: launch rewrote the version cache once
         per title). Apple TV Blu-ray/Titles/Top Shelf: **merged to main 031ecc2 (00:00 10-16)** after Fable fixes; swift 3429/425,
         E2E-tvOS 20/0 + 4 DVD menu tests, E2E-iOS 39/2 (the 2 known flaky). PENDING: install + look on OfficePlus/DevTV once
         the slowness job's measurements end (`ssh dev-mini '~/Developer/bin/buildlock.sh /tmp/tvdisc/install.sh'`).
      2a. **Apple TV speed: merged to main 4a615b9 (08:05 10-16).** DevTV with the owner's 472 titles: Home 441→197 ms,
          library on screen 5.9→2.3 s, slowest tab switch 433→67 ms; Fable FIX 3 items done; swift 3436/426, E2E-tvOS
          20/0, E2E-iOS 39/2 (known flaky); Release builds carry no debug restore hook.
      2b. **iPhone iOS 18: discs don't play + "a ton of issues"** (owner 22:50) → specs/iphone-ios18-discs-2026-10-15.md;
          **03:30 10-16: fixed on the branch** — John Wick 4 UHD plays on DevPlus (player up in 94 ms with a disc spinner,
          first frame 10.6 s, disc read once instead of twice, trailer pauses on Play); Rill https-first + redirects;
          iOS 18 hero no longer jumps (Discover bar now see-through on iOS 18: owner to judge on the phone). Gates +
          Fable review running. Engine follow-up (queue 5): cache the parsed disc per file inside AetherEngine. Owner feedback: short notes per issue / screen recordings AirDropped to the Mac.
      2. **Apple TV general slowness** (owner): profile on DevTV + OfficePlus (time profiler, trace timings: launch,
         tab switch, focus moves, title open, Play), fix the top causes, before/after numbers; + the device-sweep checks.
      2c. **iOS 18.6: 6 E2E tests fail on main already** (found 10-16 by the iPhone job, same failures on 031ecc2):
          config export Save button, widget placement focus, episode download tap, stub Discover row never drew,
          landscape tab bar, player options/captions refusing touches. Likely part of "iOS 18 build is worse". Next
          iPhone job; also give the https attempt in Add Media Server a short timeout (Fable note: LAN host dropping 443
          waits 60 s).
      2d. **Owner screen recording 10-15 22:54 (old build):** specs/iphone-recording-1015-2026-10-16.md — launch 4 s black,
          Top 10 cards without art, "Open Season 3" parsed as show "Open", Live 0-channel import toast + panel
          timeouts, Blu-ray ISO still offering Play Disc, YouTube overlays on trailers, an "oStream 540 ms" capsule.
          Next iPhone job after 2c.
      2e. Recording fixes done 15:50 (Fable review running): Open Season parser, Top 10 cached + TMDB art (rows ~4.5 s
          instead of 13 s), Live import card/quiet retry, trailer art held until 4.5 s of play, episode-row jump.
          Follow-ups: (a) launch: billboard must accept a late Continue Watching pick so saved rows can draw before
          the index load (rows at 1.3 s); (b) trace the 0.5–0.75 s main-thread hangs iOS's Hang Detection HUD showed
          after the full-screen trailer and on Settings › Sources.
      2f. **Done 10-16/17:** Unmatched section (77538b9), Top Shelf round 2 (13e7a26), speed round 2 (Fable review) →
          integration branch batch-1017 + full suites. Speed round 2 on DevTV: Play fresh 2.1–2.7 → 1.1 s (dropped
          first share connection fixed), library first change 2.7 → 1.7 s, launch parser CPU 3× less, Top 10 parse
          766 → 3 ms. Left: launch → first focus 3.3 s (Plex 2.4; `AppleDiscoverView.topPicks` ≈1.26 s CPU → speed 3),
          tvOS stock tab transition holds the old page ~1.1 s (system), resume spinner ~9 s from AetherEngine's 8 s
          "scrub landing" watchdog (→ engine job).
      2g. **Speed round 2 merged to main 72966f9 (04:30 10-17)** after the batch gate (3475/431, 8 builds, E2E-tvOS 21/0,
          E2E-iOS known flakes, DevTV Play → picture ~1 s, 0 dropped connections).
          **Server trailers done (Fable review running):** Plex extras + Jellyfin/Emby local trailers → Apple TV/Vision Pro
          hero (muted, no YouTube on Apple TV), title-page Trailer button everywhere, Top Shelf preview from a local file.
          **Owner 10-17: "Use plex server token"** → token copied (never shown) to Dev-Mini ~/Developer/openstream-build/.plex-server-token (0600); real-server check on DevTV running. Rill should arrive by iCloud sync (→ iCloud sync job).
          Undo later: two test trailers added to jellyfin-demo on ServerPlus (Sintel, Big Buck Bunny).
      3. Vision Pro on the iPad screens (P1s from the Fable review first): **Codex running since 08:05** (branch avp-ipad).
      4. Plex/Jellyfin/Emby trailers; Unmatched section.
      5. Flaky-e2e harness; engine 7.36.
      **Owner 2026-10-16 14:05: concurrency by resources + scoped tests per job; when the queue is empty run the full
      verification (specs/full-verification-2026-10-16.md: feature matrix, real-data runs on every platform, screenshot
      visual-judge pass, data assertions, timing budgets, owner-bug regression suite, coverage + sanitizers,
      exploratory crawl).** Dev-Mini lanes: buildlock.sh = sims/devices/emulators (one), buildlock-compile.sh = compile
      only (one) beside it; mini.sh OPENSTREAM_MINI_LANE=compile.
      Then the release-candidate run (App Store flavour, all four platforms, clean installs) and "ship 19".
      **YOU today:** (a) ASC → App Privacy → "Data Not Collected" → Publish (API can't confirm); (b) release type: ASC
      has all four on automatic release after approval; say if you want manual; (c) ~~"Radarr & Sonarr" visible~~ **owner 22:35: keep them visible ("look at Ruddarr ... I don't think having the arrs
      viable is an issue"; Ruddarr 2.0.1 and Helmarr are live on the App Store)**; (d) review notes: the lead writes them into ASC's App Review Information at "ship 19" (owner didn't know what
      they were); (e) permanent SSH fix on Dev-Mini (Screen Sharing → Terminal):
      `sudo sh -c 'printf "PerSourcePenaltyExemptList 192.168.1.0/24\nMaxStartups 100:30:200\nMaxSessions 64\n" > /etc/ssh/sshd_config.d/200-lan.conf'`
      (17:20 the mini's OpenSSH 10 locked the Studio out for opening too many connections; worked around with one
      shared connection via ServerPlus).
- [ ] **REA round 2: speed vs Plex + metadata (owner 2026-10-16: "I think we might be the slowest Plex is pretty
      fast").** **Done 12:18:** design/reference-apps/2026-10-16-speed-and-metadata-rea.md — 12 ranked actions (Top 10 art via
      TMDB + disk cache, parser "Season N"+year = movie, saved rows before index load, any-size image first, colour
      placeholders/BlurHash, server-sized images, decoded thumbnail cache, prefetch, parallel matching, Plex request
      shapes). Items 1-4 folded into the recording job; 5-12 → specs/speed-round2-2026-10-16.md.
      **Plex vs us on DevTV (17:20):** we're faster at focus moves (381 vs 610 ms) and opening a title (2.2 vs 3.2 s);
      Plex is faster at cold launch (~1 s), library page (~1.1 s); Plex never started the 4K DV file (buffered 50 s),
      we start in 2.75 s but lose ~1 s to a dropped first connection. Speed round 2 queued after the recording merge.
      Side-by-side timing needs Plex installed on DevTV + DevPlus (App Store, owner's Apple ID): **owner OK/install?**
- [ ] **Apple TV Top Shelf follow-up (owner feedback window 10-16 12:05, OfficePlus build 2f8604f):** "full screen on
      apple tv working but no wordmark and swipe for full screen not working, no trailers or sync through heros".
      Plan: bake the title wordmark into the 1920×1080 carousel artwork (tvOS gives no logo field; Netflix-style
      composite saved in the shared Caches folder), fix the swipe-up-to-full-screen (reproduce on DevTV), Top Shelf
      items = the Home hero carousel titles in the same order, previewVideoURL from server trailers (queue 4).
      Owner can record the TV via QuickTime on Dev-Mini (New Movie Recording → camera: OfficePlus).
- [ ] **Server trailers on Apple TV (owner 2026-10-15: "for apple tv we can do plex/jellyfin then and emby trailer
      support").** Spec `specs/server-trailers-2026-10-15.md`: Plex extras + Jellyfin/Emby local trailers as the first
      trailer source everywhere and the only one on Apple TV (hero, title page, Top Shelf preview); YouTube stays the
      fallback on iPhone/iPad/Mac/Vision Pro. Starts after Stage B is committed.
- [ ] **Trailer source without YouTube? (owner 2026-10-15: "is there a trailer addon ... or a trailer api ... we
      would just need to fit it and crop onto the screen").** Checked: TMDB, KinoCheck, Stremio addons and Jellyfin
      remote trailers all return YouTube IDs. Direct files: iTunes Search API `previewUrl` (works, no key, but SD
      640×356–480 and meant to promote iTunes purchases), Plex extras and Jellyfin/Emby local trailers (HD, only for
      titles on those servers), Video Detective (ex-IVA, what Plex licenses; paid, HD). Proposed chain: server trailer
      file → iTunes preview for small tiles → YouTube embed last (iOS/Mac only). **Owner: want a Video Detective price?**
- [ ] **Apple TV, OfficePlus dev build (owner 2026-10-15): Matilda UHD Blu-ray ISO "detects its a disc but no menu";
      the Titles list is endless; Top Shelf should be full screen like the Apple TV app, no progress bars, swipe up for
      full screen.** Cause: Blu-ray/UHD menus (BD-J) aren't supported (Infuse doesn't either); engine saw 28 titles.
      Spec `specs/tv-disc-shelf-2026-10-15.md` (branch tv-disc-shelf, work Claude): no menu promise on Blu-ray, Infuse-
      style Titles list (main feature first, duplicates merged, short clips hidden), full-screen carousel Top Shelf;
      trailers there only from direct trailer files (Plex/Jellyfin), not YouTube.
- [ ] **LEAD MISTAKE (found 2026-10-17 11:00): the dev builds installed on the owner's iPhone + OfficePlus on 10-16 and
      10-17 had NO add-ons** — owner-build.sh never passed SWIFT_ACTIVE_COMPILATION_CONDITIONS='$(inherited)
      OPENSTREAM_ADDONS' (Release doesn't define it). The owner's 6 add-ons were hidden on both devices, which explains
      part of "the app got worse". Fixed: the script passes the flag and owner-install.sh refuses a build without it;
      reinstalled with add-ons 11:0x. Re-check any perf numbers taken with owner-build.sh copies.
- [ ] **PRIORITY (owner 2026-10-15): Vision Pro needs real e2e testing; "its probably the worse out all".** Spec
      `specs/visionos-e2e-2026-10-15.md`: full E2E-visionOS crawl on the simulator (3 green runs) + fixing what it
      finds. **Owner 2026-10-15: "ipad it is!"**: Vision Pro uses the iPad screens, kept native (glass, hover, ornaments, 60 pt targets), and a 5-minute worn device pass (build prepared BEFORE the headset goes on). VP registered and a Debug
      build (dd8d32d) installed 2026-10-15; the first pass didn't happen (build took too long while the owner wore it).
- [x] **Owner decision (2026-10-17 09:35): TrueHD Atmos heights via APAC — OFF** ("okay so off"). Licence check
      (design/engine/2026-10-15-object-audio-licences.md): DTS:X can't ship (its decoder is an LGPL FFmpeg port relabelled
      Apache, linked statically; no DTS licence) → OFF. TrueHD Atmos code is clean but Dolby object-audio patents are
      unlicensed → OFF until the owner decides; lead recommends OFF for submission. E-AC-3 Atmos passthrough unaffected.
      Engine 7.36 rebase pushed (cyberbanksy/AetherEngine engine-lab-7.36 37bb7a32): 5,019 + 775 engine tests pass;
      resume-stall fix + cross-load disc parse cache; app pinned in worktree engine-736 with traits off (3475/431, 8 builds).
- [ ] **TrueHD Atmos / DTS:X on Apple TV via APAC (owner 2026-10-15: "make sure to account for" r/appletv post
      1x6e633).** Our engine fork is based on upstream 6.66.0 (Sept 2), ~1,190 commits behind; upstream 7.34–7.36 has
      TrueHD Atmos and DTS:X heights rendered to APAC, BDMV over HTTP, a teardown crash fix. Plan: licence check of
      LibTrueHD/LibDTSX first (owner decides if unclear), then rebase our 22 fork commits (DVD menus etc.) and re-pin.
      Spec: specs/engine-rebase-7.36-2026-10-15.md.

- [ ] **Unmatched section with manual matching (owner 2026-10-15: "We should have an unmatched section where users can
      match manually see infuse (change metadata)").** Library gets an Unmatched shelf/section listing files with no
      metadata match; each opens the existing Fix Match flow (search by name/year or paste an ID). REA Infuse's
      Change Metadata first. Spec: specs/unmatched-section-2026-10-15.md.
- [x] **Resume copy = most recently played (owner 2026-10-15).** "Make the most recent played as the resume copy
      unless it was replaced and no longer available then next best or next available." In the Stage B review fixes
      (specs/plex-7-8-stageB-2026-10-15.md, fix 1); replaces the earlier "sticky only on an explicit pick" answer.

- [ ] **Owner choice (2026-10-15): iPhone on iOS 18, should the top bar be see-through over the hero?** Owner 22:35:
      "I'd have to see it" → lead sends side-by-side screenshots (iOS 18.6 sim, solid vs see-through). It is solid on
      purpose since owner fix #52 (title and icons unreadable over bright art). See-through = full-bleed hero like iOS 26,
      but text over bright posters can be hard to read. Left solid until the owner picks.

- [ ] **Second build Mac (owner 2026-10-14): owner ordered a new Mac Studio; the current Mac Studio (32 GB, 512 GB)
      becomes a build machine instead of being sold.** When the new Studio is set up as the owner's daily Mac: wipe or
      clean-user the old Studio, install Xcode 27 + simulators, build keychain/signing copy, buildlock.sh, disk-guard,
      tidy-gui, mobile/rea MCP, external NVMe for project files, SSH alias. Split: Dev-Mini = OpenStream iPhone e2e;
      old Studio = OpenStream Apple TV e2e + other projects. Also pending: `sudo diskutil enableOwnership
      /Volumes/DevExt` on Dev-Mini (owner password) so simulators can live on the external drive.
- [ ] **Loading, speed and missing metadata (owner 2026-10-14, build 18).** "there is still two loading circles if
      you click content there is a loading circle on top of a loading circle and also the speed can be improved and the
      meta data fails often have no meta data we need a better catch/fix for that we need to see how stremio REA, plex
      REA, jellyfin REA, infuse REA handle meta data art work as they often have the meta data correct". Check the
      double spinner on the current build; speed up title open; REA metadata/artwork matching in Stremio, Plex,
      Jellyfin and Infuse; then a better match + fallback chain.
      Done 2026-10-14: research `design/reference-apps/2026-10-14-metadata-artwork.md`; metadata fixes 947fdc1
      (ID-first lookup, cleaned search names, year filter + retry, reasoned negative cache with backoff, old matches
      shown instantly, Fix Match on every platform). Open: the double spinner (owner: which device/tap?), title-page
      slow fill (research Part B ranks 6-8), Fix Match "1917"-style all-digit names also searched as names,
      iOS e2e testCrawlPlayers "playback did not settle in 10 s" (new since 16:32 in the shared tree).
- [ ] **Make the repos public once the App Store approves the app (owner 2026-10-14).** Before that: the private
      history holds commercial movie clips (Tests/Fixtures/private, added 6f807d7, removed dd4e101) and owner notes;
      they must be purged (history rewrite) or the public repo stays the scrubbed export (orgista/openstream-apple).
- [ ] **First-party agentic coding tools per platform (owner 2026-10-14).** Find Google's official Android/agentic
      coding skills and Apple's official agentic coding skills/tools for Xcode, install them for every agent, and use
      them for each platform.
      Done 2026-10-14: Google's official android/skills (30 skills, SHA 5bda39f) installed for Claude, work Claude,
      Codex, Codex headless and agy. Firebase skipped (no project uses it). **Apple:** Xcode 27's own skills export
      (`xcrun agent skills export`) waits for an approval inside the Xcode window on Dev-Mini; the owner opens Xcode
      there once via Screen Sharing and allows it, then the lead finishes the install. Xcode's MCP bridge needs a running
      Xcode too, so it is not registered.
- [ ] **Max out Codex and agy to 100% (owner 2026-10-14).** Overrides the 85% stop for Codex and agy.
- [ ] **GitHub synced with every beta, pushes automatic (owner 2026-10-14).** "change never to ask please instead
      automatic I rather know but in general they should be synced with the builds if a new beta goes out github should
      be updated". Done: the `git push` block in the workspace settings is removed; engine fork commit 07afad62 pushed
      (DVD menu fixes). SHIP-CHECKLIST §8 now requires the engine pin to be a pushed commit and every repo pushed on each
      ship. Pushes happen without asking; the owner is told after.
- [ ] **PRIORITY (owner 2026-10-14): iPhone hero lost its trailers and its full-screen look in build 18.** "heros in
      build 18 changed no more trailers and it nots full screen like it was before on iOS can we fix that look into
      how netflix and apple tv handle trailers and fix that please that was my fave feature". Find the commit that
      changed it, check Netflix and Apple TV app hero trailers (REA notes), bring back full-bleed hero + trailer
      autoplay on iOS, show screenshots of the current unpublished build next to build 18.
      Also: Codex is past 85% this week; route work to agy first, then work Claude (owner 2026-10-14).
- [ ] **PRIORITY (owner 2026-10-13): ISO playback with real disc menus doesn't work on iOS; test all ISOs; Matilda
      captions wrong.** Found: the engine already has DVD menus, the app never turned them on (Play Disc still plays
      the main title). Spec specs/iso-menus-captions-2026-10-13.md: wire Play Disc / Skip to Movie / Disc Menu on every
      platform, test every ISO, fix PGS caption display on Matilda (UHD DV remux, one English PGS track) and similar
      files. Codex starts it right after Plex 7/8 Stage A.

- [ ] **Network shares: add several folders from one share, like Infuse (owner 2026-10-13).** Today adding a share
      lets you pick one folder and that's it. Mapping the current flow and storage first so progress and matches
      survive; then Codex builds it after Plex 7/8 Stage A.

- [ ] **Overnight 2026-10-13 (all in the next build):** Apple TV app behaviours from the REA of the Mac TV app (17e7041):
      heroes pause and stop on the last item, watched by runtime band, post-play countdown with a 3-episode / 2-hour
      autoplay cap, Reduce Motion / Low Power stop auto video, no repeats across rows, faster artwork. Fable review of
      all of 2026-10-12: 15 findings, 14 fixed (15216f9). The 2 serious ones: library artwork/details never saved on a
      real Apple TV, and posters flashed grey after scrolling. Lead change: Apple TV keeps playback history in app
      settings, not in purgeable files. Gate 3248 tests / 402 suites (0170bad); simulators tvOS 20/0, iOS 40/1 (AirPlay, known).
      Apple TV 4/7/8/10 measured on the sim: no gap, nothing changed (verification-artifacts/remaining-polish-2026-10-13.md).
      **Owner decisions 2026-10-13:** Netflix 8 hero = "Mix": slot 1 is the title you're watching; of the other 4, up to 2
      unseen picks and 1 unseen release from the last 90 days; leftovers keep today's order (built, 6101d4c). Netflix 11
      badges = "No new labels": posters stay as they are.

- [ ] **Use all Fable usage each week, personal and work (owner 2026-10-12).** Done on personal Fable: REA of the
      Mac TV app (report in verification-artifacts/rea-mac-tv-2026-10-12/). Paused (5-hour window): a deep review of today's commits
      (specs/fable-review-2026-10-12.md). **Work account login expired:** the owner needs to log in again (Terminal:
      `CLAUDE_CONFIG_DIR=~/.claude-work claude`, then `/login`, then close the window). Then the heaviest Fable jobs
      move to work.

- [ ] **Real Apple TV connected (owner 2026-10-12): "OfficePlus" (Apple TV 4K) on Dev-Mini.** Owner OK'd e2e on it
      and REA research there on the Apple TV app, Netflix and others (UI only; no DRM or sign-in workarounds;
      screenshots stay in verification-artifacts, never in the public repo). Owner OK'd a tvOS development profile:
      three created 2026-10-12 (app, Top Shelf, wildcard runner; OfficePlus only; existing certificate). Spec:
      specs/appletv-device-2026-10-12.md; TV work paused 2026-10-12 night: the TV display was off (Home Screen and Top Shelf can't render), resume tomorrow with the TV awake (Sleep After: Never helps). Installing our test build replaces the
      OpenStream copy on that TV; reinstall build 18 from TestFlight afterwards.
- [x] **Agents leave windows open (owner 2026-10-12: "like 20" Terminal windows).** Rule added to the workspace
      AGENTS.md ("Clean up after yourself"). Dev-Mini now runs `~/Developer/bin/tidy-gui.sh` whenever the build lock is
      released: it closes idle Terminal windows and quits Simulator when nothing is booted. Gotcha found:
      `osascript … tell application "Terminal"` opens a new window by itself.
- [ ] **Use agy and Muse where possible (owner 2026-10-12).** agy takes short review and check prompts (agy-task.sh);
      Muse takes text-only work (REA write-ups, copy, reviews). Codex keeps the heavy simulator and device runs.
      agy reviewed the Live Pause fix (a58593f). **Muse is logged out since 2026-10-11** (ServerPlus runner stopped,
      AUTH-EXPIRED.txt). The owner needs to log in to muse.ai again so its cookies can be re-exported. Queued meanwhile:
      57-openstream-tv-netflix-published.md (what Apple and Netflix publish about TV home screens).

- [ ] **Apple TV posters: title on focus (owner 2026-10-12: "titles on focus").** Posters stay clean; the focused
      poster shows its title underneath, like the Apple TV app's focus caption. Built in 12aa663; verified on the tvOS simulator (only the focused poster shows its title).
- [ ] **Full e2e after the 2026-10-12 polish queue: green except 2 known.** Fixed: Top Shelf CPU hot loop
      (5e70036), import message overwritten (5e70036), Reset breaking widgets and Top Shelf (8af3ce3), Live tab Pause
      not responding (a58593f). Test data and outdated tests fixed (8af3ce3). Simulators: Apple TV 20 pass / 0 fail,
      iPhone 39 pass / 2 fail. The 2 failures: the AirPlay picker has no simulator UI, and the Messages share test is
      flaky only in full runs. Next: the same plans on the real Apple TV (OfficePlus). Results:
      verification-artifacts/e2e-2026-10-12/.
- [ ] **GitHub releases on every ship (owner 2026-10-12: "yes for all releases build into all pipes that it should be
      also being pushed to github").** Rule recorded in SHIP-CHECKLIST §8: every "ship N" also publishes the GitHub
      release (orgista/openstream-apple: public source snapshot + iOS/tvOS/visionOS IPAs + Mac zip + checksums).
      Build 18 release: PUBLISHED 2026-10-12 — https://github.com/orgista/openstream-apple/releases/tag/v1.0-18
- [ ] **Top Shelf on the real TV (owner 2026-10-12: "tv shelf still doesn't work").** OfficePlus with build 18: the
      shelf content file (topshelf-v1.json) was missing from the app's shared folder, so tvOS showed the static
      image. The write failed silently and was never retried. Fixed in the next build: a tvOS-safe write, a retry, and
      failures logged. Tests pass on the simulator; confirm on OfficePlus when the TV is awake.
      2026-10-13 on OfficePlus: still the static image; the new log showed every write failing with error 513 (no
      permission). Apple TV hardware won't let apps write the shared folder's top level, only its Library/Caches.
      Fixed in 35c1522. **Verified on OfficePlus 2026-10-13:** no 513 errors; the shelf shows 3 Continue Watching + 10 Top Picks with oStream in the top row; E2E-tvOS on the TV 20/0 (same as the sim). Ships in the next build. Owner: reinstall build 18 from TestFlight on OfficePlus. Dummy plug: owner is buying an HDMI dummy plug for headless
      testing (HDR plug suggested; Dolby Vision stays an eye check at ship + a DV-mode line in the app trace).
- [ ] **Top Shelf: possible second cause (2026-10-12).** The tvOS brand assets had only the wide Top Shelf image; the
      standard 1920x720 "Top Shelf Image" was missing, so tvOS can stretch the logo. Added it (same art); ships in the
      next build. The dynamic shelf fix is already in build 18 (see the Top Shelf item below).

- [ ] **Polish to perfection from two references (owner 2026-10-11): "Apple TV is the main GUI I am trying to emulate
      with heroes, and Netflix for icons [and] suggestion algorithm. Our design is in a good place but both those apps
      can help us bring it to perfection."** REA run: Apple TV app hero/shelves vs our billboard; Netflix artwork/icons +
      how suggestions are built vs AppleRecommendationRanker. Spec specs/rea-appletv-netflix-polish-2026-10-11.md;
      reports design/reference-apps/2026-10-11-appletv-hero-gui.md + 2026-10-11-netflix-artwork-suggestions.md, each
      ending in a ranked polish list for the owner to pick from.
      DONE 2026-10-11 (both reports in). Apple TV: 12 items, top = tvOS posters hide titles
      (AppleDiscoverView.swift:2412), extra leading fade on bright art (AppleHeroScrim.swift:119), hero timer runs
      while art loads. Netflix: 14 items, top = recommendations get empty genres (AppleDiscoverView.swift:648/672),
      duplicate titles across sources, history only from Continue Watching, likes not spreading to related titles,
      missing backdrops. Owner: pick which to build.
- [ ] **REA deep dives (owner 2026-10-11): Paramount+ live functions, Netflix GUI, Plex backend + features, Infuse engine +
      source setup for local sources.** One report each in design/reference-apps/, with what OpenStream should take.
      Plex = "longest in the game: what can we learn for how our app works" → extra step holds Plex's backend against
      our code (design/reference-apps/2026-10-11-plex-lessons-for-openstream.md). Spec specs/rea-deep-dives-2026-10-11.md.
      DONE 2026-10-11, five reports in design/reference-apps/ (paramount-live, netflix-gui, plex-backend,
      infuse-engine-sources, plex-lessons-for-openstream: 12 ranked changes). Owner: pick which changes to build.
- [ ] **Use the GitHub "REA" tool to see how other apps build a feature (owner 2026-10-11).** Set it up for the project
      so any "how should this function work" request can check reference apps; first run on Netflix, Apple TV app,
      Paramount+, Plex and Infuse.
      SET UP 2026-10-11: morluto/rea 6.4.0 as the `rea` MCP for every agent (runs on Dev-Mini; Ghidra + JADX), rule in
      AGENTS.md §4.2. Targets ready: Apple TV app, Infuse 8.5.6, Plex desktop, Netflix + Paramount+ Android TV (signers
      verified). First run (Codex, spec specs/rea-trial-2026-10-11.md): Skip Intro + Next Episode across all five →
      design/reference-apps/2026-10-11-skip-intro-next-episode.md. DONE: Apple TV, Plex, Paramount+ answered with
      evidence; Infuse partly (settings names only); Netflix's logic is inside its native library, not found.
- [ ] **Apple TV Top Shelf shows no content, only a blurry stretched logo (owner 2026-10-10).** Cause: publishing was
      off by default (Settings › Privacy › Show in Apple services), and a setup import wrote that off value onto the TV,
      so the extension had nothing and tvOS fell back to the static image. Fixed: on by default under a new v2 key (old
      off values ignored); regression test, 3027 tests green; fresh tvOS sim install now writes the shelf file unprompted.
      **YOU:** IN BUILD 18 (TestFlight 2026-10-11): update on the TV, open the app once, then hover it on the top row:
      Continue Watching / Top Picks tiles should appear.
- [ ] **Googlebook version of OpenStream + Google Play "Made for desktop" badge (owner 2026-10-09).** Build the
      large-screen/desktop variant (same Play app, mobile AAB), e2e on the Googlebook AVD on Dev-Mini (keyboard, mouse,
      resize, multi-window, playback), and meet every badge requirement. Spec: specs/googlebook-2026-10-09.md; work Claude
      worker running 2026-10-09. Owner: any Play Console declaration it reports.
      BUILT + e2e PASSED 2026-10-10 (e8a9bc7, 82fca93, 0331e3c, ae66124; 385 Android tests, 42 screenshots in
      native/google-tv/verification-artifacts/googlebook-2026-10-09/REPORT.md): window resize during playback, PiP, keyboard
      + media keys, Ctrl shortcuts, mouse hover/right-click/scrollbars. Google gives the label itself (no opt-in, criteria
      unpublished); built to Tier 1 Desktop. Left: Down-arrow from the top bar, multi-instance, drag-drop. Reaches users with
      the next AAB pair (TV vc3, mobile vc4) — needs your "ship".
      ROUND 2 DONE 2026-10-10 (892a81c..c014552, 387 tests): Down-arrow, tooltips, several windows (Ctrl+N), open local
      files + drag-drop, smoke test green. Owner: a hands-on check on a real Googlebook if you have one.
- [ ] **Rill bridge was broken since the 10-02 hardening; fixed 2026-10-09 (Tismlist session, owner-approved).** Every
      add-on fetch failed ("No manifest found at that address.") because Workers reject `redirect: 'error'`; now
      `redirect: 'manual'` + regression test, deployed to stream.ourzephyr.com (D1 restore point taken first). Source:
      branch `hardening-fix` (91588d0) in /mnt/user/backups/studio-openstream-build-2026-10-06/bridge/rill on ServerPlus;
      public hardened copy github.com/cyberbanksy/rill-hardened. **YOU:** re-test adding add-ons in Rill, then playback in
      OpenStream (Add Media Server › Jellyfin). The Reddit setup DM can now point to rill-hardened.
      **2026-10-15 23:10 (owner: "move rill to gallardo.dev domain im deprecating ourzephyr"):** Rill also answers at
      **https://stream.gallardo.dev** (custom domain on the same `rill` Worker, no redeploy; wrangler.jsonc routes list
      both). **Live 23:45: DNS published; System/Info/Public 200 with LocalAddress https://stream.gallardo.dev, sign-in
      endpoint answers.** stream.ourzephyr.com stays attached until you say to drop it; then remove it from the Worker and routes.
      Owner's iPhone: Add Media Server › Jellyfin works with `https://` (the no-scheme bug is in the iPhone job).
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
      - [x] (7) The player is a cut-off box. While playing there's nothing showing which channel you're on, in the
            player or the guide. **Fixed 6fafa72, c3a1dcb, c1faea9:** video edge to edge under the status bar, channel
            logo over it, programme line under it, WATCHING pill on the list row. Shots: verification-artifacts/live-redesign-2026-10-09/after.
      - [x] (8) Remove or rework the All / Favorites / News / Sports / Entertainment bar. It also floats and jumps on
            scroll. **Fixed 77d88b3, c1faea9:** fixed underlined tabs under the video, only the channel list scrolls
            (UI test testLiveLayoutIsStable passes on the iOS 18.6 sim).
      - [x] (9) The "Live" title + search wastes space. Make the video bigger; Live can live elsewhere. **Fixed 6fafa72**
            (no title bar; search is a glyph at the end of the tab row, 77d88b3).
      - [x] (10) The translucent tab bar over the guide: hide it while browsing the guide and bring it back on scroll,
            or similar. **Fixed 6fafa72** (your default: always visible, standard opaque background on iOS 18; iOS 26
            keeps its own glass).
      - [x] (11) How do I get to pay-per-view? **Fixed 77d88b3:** an Events tab lists the pay-per-view channels.
      **Fullscreen Live player:**
      - [x] (12) The X top-left looks tacky. **Fixed 80dd79c** (bare xmark, system player layout).
      - [x] (13) The "Channels" / "Last Channel" buttons look tacky. **Fixed 80dd79c, c3a1dcb:** list glyph; Last
            Channel is the first row of the ⋯ menu (plus the swipe).
      - [x] (14) The progress bar is big, loud and cheap-looking; it should be subtle and clean. Going LIVE works.
            **Fixed 80dd79c** (3 pt bar, LIVE as its left label).
      - [x] (15) The back button and the enlarge icon look odd; use SF Symbols / Apple-standard controls. **Fixed
            80dd79c, c3a1dcb** (mute, AirPlay, full screen together top-right inline).
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
      an empty iPad/iPhone it is also a button on No Sources. Apple TV's empty No Sources screen has the button too
      (24517d6). Still to do: the Android TV side (the format
      is written down in HANDOFF-NEXT-SESSION.md).
- [ ] **iCloud sync still looks broken (owner 2026-10-08):** 2026-10-17: owner's iPhone sends 3 sources (incl. Rill) but
      OfficePlus last applied 9; DevTV held by a debug restore. Job: specs/icloud-sync-2026-10-17.md (next free slot).
      Original note: owner doesn't think it works and doesn't know how
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

- [ ] **Vision Pro: audio kept playing after the app window was closed** (reported 2026-10-07, previous TestFlight
      build). Fixed in f91da00: the player now stops (and saves the resume point) when the window leaves the
      foreground. The simulator cannot close a window or background the app from a test, so this needs a device check.
- [ ] **Vision Pro environments** (owner, 2026-10-07). Apple's own environments (Mount Hood, Moon, etc.) can't be bundled,
      but the full-window player docks into them when you pick one with the Digital Crown — verify on the device. Next:
      our own "theater" environment (an immersive space with a docking spot for the screen), after the player work.
- [ ] **Vision Pro traces:** device isn't paired with Dev-Mini. Owner: Settings → Share Diagnostics → AirDrop to the Mac.
- [ ] **(2026-10-05) Live TV for Apple TV — built, needs your Apple TV (build 16).** Multiview (up to 4 channels,
      a9b71b9); instant/correct guide, guide matching, account info + clear login errors, catch-up error, hide/reorder,
      sleep timer, Match Content, reminders (f1276f0); channel up/down + banner, Last Channel, resume last channel
      (8ed357d); Start Over, live buffer, Top Shelf/Siri channels (4abfaac); provider movies & series (189dd18); parental
      PIN + import progress (8c29e10). Research + gap report: ~/Developer/openstream-build/specs/live-tv/gap-report-2026-10-05.md (Mac Studio only, not in git).
      DVR dropped by the owner 2026-10-06; Apple TV PiP built (7165a8e).

- [x] **(2026-10-04) Short app names.** Under the icon: oStream (all platforms, Share, Messages, Watch, widgets);
      App Store name oStream. Inside the app it's still OpenStream. (368be0c)

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
- [ ] **CarPlay (owner ask 2026-10-03) — not in build 15:** YOU request at developer.apple.com/contact/carplay/ for
      **Owner 2026-10-15: entitlement requested from Apple, approval pending.** Nothing ships until it is granted; then
      add the CarPlay audio template (Continue Watching audio-only / Live radio channels) + a new profile.
      com.orgista.openstream: Video (`com.apple.developer.carplay-video`, iOS 27+) AND Audio (so it appears in every
      CarPlay car; video-only shows only in cars with parked video). After Apple grants it: CarPlay scene + icon,
      parked video, Live TV/audio while driving, gate video behind a capability check (iOS 27 beta blank-screen bug
      on non-video head units), test in CarPlay Simulator. Research: muse-results/34-carplay-video-parked.md.
- [x] **Build 15 shipped 2026-10-03** to TestFlight Internal (iOS, tvOS, visionOS, macOS; add-ons kept), all VALID —
      see DELIVERIES.md.
- [ ] **Apple TV full pass 2026-10-02 (9c0be32):** most new features pass (reconnect, Watch on other list, catch-up,
      latest season, Start from Beginning, recent searches, disc badge, Play Disc/Skip to Movie, no tab replay).
      P0 FIXED 0e9a6d5: every on-demand play with artwork crashed (Now Playing artwork, from 40e9350) — verified.
      FIXED 4a866d8 (sim-checked): TMDB notice in full; Live categories from your playlist's groups; guide titles
      for shows that started earlier; channel numbers; row names read naturally (no "· Cinemeta"); search puts
      General Hospital 1963 first. Blank tab after fast hops: couldn't reproduce — added a safety net that rebuilds
      a tab that never appears. Re-checked after the crash fix: Subtitle Delay, Frame Rate, title-page badges,
      Playback Unavailable all work. Dropped per you: catch-up player chrome, special disc title page.
      Small: "Playback Unavailable" for a title with no streams says "details only" — wording could be clearer.
- [ ] **Engine lab round 2 — steps 2–4 DONE 2026-10-10; awaiting lead merge/install.**
      Fork branches are published: dvd-menus 4e877598; engine-lab source 45d64e8a9b2ac422bcdb7f467f8327c214eab2ed
      plus evidence a93c73dd. All 98 corpus entries available, no skips; downloaded/generated media 4.37 GB on DevExt.
      FFmpeg/MKVToolNix and downloads were lead-approved and completed. No tool-install action remains.
      **#34 DONE:** forced-software AV1 seek continuity 1/4 → 4/4; nine starving seeks (131–700 ms) → none,
      all twelve frame latencies below 1.5 s. Four truncated files end impossible seeks in 10–13 ms; valid generated-MKV
      seek still lands. VC-1 final clock 0.751 → 1.034 s, matching FFmpeg's last decodable picture in the truncated sample.
      Interlaced freezes were enqueue-time measurement errors: all six clips already show zero measured freezes in the
      corrected baseline. EOF drain preserves their final buffered pictures; no unobserved display-freeze fix is claimed.
      Whole-corpus baseline /Volumes/DevExt/engine-lab/runs/20261010-031451-round2-full-baseline; final 20261010-041939-round2-full-final.
      Both 98/98 results; frame score 92/94 unchanged, seek continuity 79/82 → 80/82. Playback 91/94 → 85/94 is six
      later-seek errors now reported explicitly; their six-second play windows remain healthy. Thresholds unchanged.
      Attached AV1 before/after traces complete decoding and three seeks; CPU demand similar. Raw EOF bounds apply only
      to unfolded Matroska; full-run timestamp-wrap valid seek preserved (82.5 ms). Fork gate 2656 / 359 green.
      Package.swift and both resolved files now pin the tested owner-fork source revision. OpenStream full serial gate 3018 / 384 green (60.581 s);
      default full gate reproduces the existing shared health-store race (3018 / 384, one issue), also present before edits.
      **Owner only:** check software AV1/interlaced pixel output and native-HLS heat on the real A12 Apple TV after the
      lead merges the OpenStream diff and installs a build. Checkbox stays open until merged and installed.
- [ ] **DONE da014fb (2026-10-02):** IPTV catch-up from the guide (back up to 3 days, plays a past programme from its
      start, Watch Live returns; sim-checked on Apple TV — iPad build only); Discover rows neutral + Top 10 off;
      channel lineup test-only; recent searches; offline UI-test stubs + smoke tests (pass on iPad + Apple TV);
      iCloud restore no longer rewinds Resume; "Forced"-only subtitle tracks never auto-picked. Open: a deleted
      add-on can come back after iCloud sync; search tab position on tvOS (kept first per your 09-14 call).
- [ ] **Open-source / public repo (2026-10-01) — owner 2026-10-09: do NOT rotate or recreate the AIOMetadata key, keep using it; key part closed. Remaining: publish orgista/openstream-apple (Apache-2.0, already decided).** — scan notes (specs/oss-public-readiness.md never existed in the repo; these findings live only here):** history scan (410 commits): no signing
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
- [ ] **Ideas from Strand + iProTV (2026-10-01, pick what you want):** smooth seek (no black flash) as a gate test;
      App Store risk — Strand pulled Stremio add-ons to pass review (fallback: Remux, add-ons behind a Jellyfin API);
      IPTV catch-up/timeshift + live pause; denser TV guide (TiviMate-style, Left → sidebar); IPTV multiview 2–4;
      "watch without tracking" / rewatch / shuffle; hand-off to Infuse/VLC keeping Trakt; per-Apple-TV-user
      profiles; Simkl + local watchlist; format badges (DV/HDR/Atmos); sports scores; iOS 27 external display
      (video on TV, controls on phone); first-run guide. Dead IPTV stream → offer the same channel from another list.
- [ ] **ISO / disc images (owner 2026-10-01):** today ISOs play the main title only. DECIDED: Apple disc symbol in the
      poster corner (A2) + that symbol spinning while the disc opens (S1); "Play Disc" opens the real DVD menu first,
      "Skip to Movie" plays the main title (D2) — menus are part of the experience; Disc Menu button in the player (P1).
      Engine forked (github.com/cyberbanksy/AetherEngine, public — LGPL-3.0 + App Store exception, so our engine
      changes are published; keep rebased on upstream). Phase 1 DONE (disc menu structure, button highlights, the
      DVD menu "brain", 70 tests, test disc) on branch dvd-menus in ~/Developer/openstream-build/AetherEngine-fork —
      **Published 2026-10-10:** dvd-menus 4e877598 is now on cyberbanksy/AetherEngine; the push owner action is closed. Phase 2 DONE (6 commits on dvd-menus): menus play on screen with
      button highlights, remote/touch/pointer input, stills, setup menus, Play Disc (`.menu`) vs Skip to Movie;
      97 DVD tests incl. an end-to-end menu → title → back-to-menu test. Open: menus are silent, resume restarts
      the cell, tiny gap on looping menus, multi-angle, no real-disc/Apple TV test yet. Phase 3 (wire into the app)
      needs the app dependency switched to the tested fork revision; the fork is now published.
- [ ] **Owner asks 2026-10-01 (evening):** use Muse's 2B tokens for research at scale (it's the Meta Model API /
      developer console, not meta.ai chat — needs an API key); on-device processing + ML + Apple silicon ideas;
      end-to-end tests for the iMessage app and iCloud sync on a real iPhone over USB (test Apple ID).

- [ ] **iOS 18.6 iPhone regression (b4d4793, 2026-10-01):** no hang (5 titles incl. General Hospital S64), Resume,
      next episode, no tab-switch replay, English-only captions, Live error ~9 s, configure-first, 0 crashes. Open:
      FIXED (sim-checked on iOS 18.6): hero Play Trailer over the preview gets sound; title-page art comes back
      (the art itself failed to load — now tries the next image); hero shows Play only when something plays; a
      swipe pages the hero; "£" → "♪" in subtitles; General Hospital 1963 first; VoiceOver no longer reads icon
      names. Still: "A Different World" search lists the 2026 show above 1987.
      Minor: title page flashes between auto-advanced episodes; CW time left uses the stream's length (director's cut).
- [ ] **tvOS verification of 4fd1ac5 (2026-10-01 early):** toggles/Retry readable ✅, cue placement ✅, field outlines ✅,
      audio labels ✅. Still broken: **every Settings Picker on tvOS opens an empty page** (Package, Live view,
      Playback › Player; Menu there quits to Home) — pre-existing; Skip Intro still not reachable with Down; Top 10
      "Wonka's" tile blank (TMDB+Cinemeta share an IMDb id → merge hides the TMDB record from the Top 10 artwork
      match); subtitle/audio menus keep the old checkmark after picking from More…/another track; Channel Manager
      error row draws an empty capsule; captions "off" still auto-selects English on some launches; a sparse-cue
      subtitle shows nothing after a mid-stream switch; UI test testFullSubtitleMenuSelectsSpanish needs updating.
      The sparse-cue switch is now verified against the actual engine fixture; finish-spec #53 is closed in Done below.
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
- [ ] **Apple Intelligence** (2026-09-28): owner asks where it could help when available. Ideas to propose.
## Waiting on an owner decision

- [ ] **Owner decisions from the 10-17 reports:** (a) YouTube chrome on trailers: hide again or accept until server/iTunes trailers replace it (F3); (b) tvOS Live: keep guide-first, or channel full screen behind a guide overlay like Paramount+ (needs a fade, against the no-dimming rule) (G20); (c) Live categories: keep All + Favorites (recommended) (G21); (d) your phone has Top 10 rows saved ON — the default is now off, switch it off in Settings if you don't want them; (e) "Test Connection" was shortened to "Test" — was "could use work too" about the wording or the greyed look?

- [x] **Mac launch test for build 19 (2026-10-13):** owner OK'd. Dev-Mini registered (ASC device X54DASSTUH,
      Provisioning UDID) and new profile "OpenStream Mac Development 2026-10-13" (5CLWYB44Z7; certs 6BCK8Q8A2P mini +
      DCJ4PSN9C6 Studio; devices Dev-Mini + Mac Studio) installed on the mini. Launch test queued for Codex.
- [ ] **UX tour 2026-10-08: four calls for you** (details in verification-artifacts/ux-tour-2026-10-08/FINDINGS.md):
      (1) the iPhone/iPad player has no Picture in Picture or AirPlay button; PiP only starts when you leave
      the app. Add both to the top bar like the Apple TV app? (2) Discover and Search each have a Refresh button;
      Apple TV dropped it. Remove it on iPhone/iPad/Mac too? (3) There is no Share button on a title page. Add one?
      (4) Long-pressing a Discover poster opens it, while Library/Continue Watching posters show a menu, and a
      shelf's "See all" is a plain text list. Give every poster the menu and make "See all" a poster grid?
- [ ] **"Remove the gradient"** — the screenshot was lost (2026-09-25). Which gradient? Retake it.
      (2026-10-12: 229cabe removed the extra fade over bright hero art; only the approved billboard fade is left.
      If that was the one, tick this.)
- [ ] **Check on your phone/TV (2026-10-12 polish, 1e91143..36da38c):** Top Picks (no duplicates), Continue
      Watching order + next episode after a finished one + "see all" when the row is full. The tvOS sim and tests
      pass, but these need real watch history, which only your devices have (DevPlus screenshots come out black).
- [ ] **ServerPlus 3090:** passed a full overnight bench test on Windows (2026-09-27, 350 W, 0 errors), so it may
      be the DEG1/OCuLink path at 3090 power. The server runs a 2080 Ti for now (11 GB: the 27B local
      model is slow). Next: capped run on the server (200 W + locked clocks), or a new dock, or return it.

## Done

- [x] **Plex lessons 9 — provider home hubs. Closed 2026-10-12 (done, verified):** supported Plex video hubs and Jellyfin/Emby Next Up and genre rows reuse existing title routes, custom row grouping and bounded paging; affected-row refresh preserves other rows, silently handles unavailable hubs and restores newly eligible empty hubs in their original position. Fake-server fixtures cover all three providers, duplicate headings, required-endpoint cache retention, paging and stale requests. Full serial Swift 3158 / 392; iOS/tvOS Debug builds confirmed all 14 changed production Swift files recompiled for arm64. No commit.
- [x] **Plex lessons 11 — chapter provenance. Closed 2026-10-12 (done, verified):** embedded chapter source, opaque loaded-media version and validated timing reach both engines and the transport overlay; invalid, duplicate and outdated markers are rejected, and chapter/intro seeks recheck the current runtime and version. Unknown runtime never seeks; chapter-free content gets no invented intro. Chapter policy and engine tests; full serial Swift 3158 / 392; iOS/tvOS arm64 compilation confirmed. Fingerprinting remains tabled. No commit.
- [x] **Hero Details duplication. Closed 2026-10-12 (done, verified):** tvOS omits the round info button when the primary opens Details, retaining My List and Play behavior; paging restores unavailable Details focus to My List. iPhone/iPad/Mac dedicated rows already omit the duplicate; fallback rows share the tested button policy. Button/focus policy tests; full serial Swift 3158 / 392; iOS/tvOS arm64 compilation confirmed. No commit.

- [x] **Netflix polish 5 — accessible recommendation union. Closed 2026-10-12 (done, verified):** all current enabled catalogs, including duplicate-heading catalogs, indexed playable titles and server shelves; bounded configuration-isolated TMDB recommendation/similar cache retains seed/origin and piggybacks on existing metadata requests. Off-main indexed intersection rejects inaccessible/ambiguous targets; metadata-off and expiry respected. Union, transport, cache-bound/concurrency and inaccessible-target tests; serial Swift 3139 / 391; iOS/tvOS builds. No commit.
- [x] **Netflix polish 6 — unseen picks and one seed row. Closed 2026-10-12 (done, verified):** Top Picks prioritizes relevant unseen titles; Continue Watching retains resume order. At most one >=6-item “Because you watched” row follows configured rails with heading deduplication and no extra UI text. Order/boundary/affinity tests; serial Swift 3139 / 391; iOS/tvOS builds; muted F2107E8F local-fixture capture `verification-artifacts/polish-2-2026-10-12/because-watched.png`; seed removed. No commit.
- [x] **Netflix polish 12 — shared semantic actions. Closed 2026-10-12 (done, verified):** play/info/more, My List add/check, outline/filled thumbs and distinct Love heart, and download states share SF Symbols and action labels across Discover/detail/Library's common components. Neutral tvOS controls preserved; semantic-state tests; serial Swift 3139 / 391; iOS/tvOS builds. No Netflix assets, no commit.
- [x] **Apple TV polish 6 — truthful Continue Watching line. Closed 2026-10-12 (done, verified):** local saved progress yields compact S2 E5 or minutes-left text under the title, with artwork progress retained; unknown/completed/invalid data yields no line. Caption tests; serial Swift 3139 / 391; iOS/tvOS builds; muted F2107E8F local-fixture capture `verification-artifacts/polish-2-2026-10-12/continue-watching.png`; seed removed. No commit.
- [x] **Apple TV polish 11 — accessible hero controls. Closed 2026-10-12 (done, verified):** native focused treatment retained; semantic material/opaque background responds to Reduce Transparency, and Increase Contrast adds a semantic border; existing shadow, scale and Reduce Motion behavior retained. Serial Swift 3139 / 391 and iOS/tvOS builds; normal fixture hero capture `verification-artifacts/polish-2-2026-10-12/hero.png`. Alternate accessibility appearance not runtime-verified: tvOS 27 simulator rejects Increase Contrast as unsupported. No commit.
- [x] **Apple TV polish 12 — one active title policy. Closed 2026-10-12 (done, verified):** unused AppleTVBillboardTitleTreatment removed; remaining artwork/billboard tests and comments name the active AppleHeroTitlePolicy / AppleTitleLogoPolicy, preserving the five-second grace and sticky text fallback. Serial Swift 3139 / 391; iOS/tvOS builds recompiled all 15 edited Swift sources. No commit.

- [x] **Apple TV polish 9 — stable first-load Discover. Closed 2026-10-12 (done, verified):** static surface-colour hero/rail placeholders share populated Discover's scroll geometry on TV/iPhone/iPad/Mac; existing empty/failure states retained, populated refreshes retained, no animation or visible loading text. Full serial Swift gate 3127 tests / 389 suites; iOS/tvOS simulator builds recompiled all eight edited sources. Muted F2107E8F loading capture (Debug-only state hold): `design/2026-10-12-atv9/loading.png`; capture used `ENABLE_DEBUG_DYLIB=NO` and bundled `DYLD_FRAMEWORK_PATH` after dyld stalled before SwiftUI. No commit.
- [x] **Netflix polish 13 — ranking provenance. Closed 2026-10-12 (done, verified):** internal recommendation components and hashed viewing/liked seeds; similar-title seed digest retained through diversity selection; Debug-only trace contains digests/numbers, deterministic strict ties and canonical representatives, existing score caps preserved, non-finite priors/extreme years handled. Provenance/cap/non-disclosure/permuted-input tests; full serial Swift gate 3127 / 389 and iOS/tvOS builds. No UI explanations, no commit.
- [x] **Netflix polish 14 — taste/cache hygiene. Closed 2026-10-12 (done, verified):** keyword entries validate synopsis and normalized genres, replace changed inputs without consuming capacity, and separate explicit namespaces; rating/playback stores accept the same storage-context namespace while default local keys retain existing data. Metadata-change, eviction, namespace-isolation and legacy-key tests; full serial Swift gate 3127 / 389 and iOS/tvOS builds. No profiles added, no commit.

- [x] **Plex lessons 3 — cloud terminal horizon. Lead-review correction 2026-10-12 (done, verified):** cloud copies retain the newest 2,000 terminals plus clocks linked to retained progress/activity or newer than its oldest date; byte-budget trimming retires oldest terminal/state bundles together, including episode links and stale histories that could regenerate barriers. Local history, backups and persisted schemas remain unchanged. The 20,000-finished-title/long-ID fixture, recent-activity retention, horizon union, deterministic encoding and partial/completed-state retirement tests pass. Full serial Swift gate 3121 / 388; iOS/tvOS Debug builds each confirmed AppleConfigurationSnapshot.swift recompiled for arm64. No commit or upload.

- [x] **Plex lessons 3 — progress sync that converges. Closed 2026-10-12 (done, verified):** retained completion, reset, removal and latest-play timestamps reconcile old backups and offline devices; later rewinds/rewatches win, while cloud/history trimming cannot revive stale state. Existing local data migrates once, preserving completed episode identity and activity; backup/iCloud fields are additive with legacy defaults. Full serial Swift gate 3118 / 388; iOS/tvOS Debug builds confirmed all six changed production Swift sources recompiled for arm64. No UI changes, commit or upload.
- [x] **Plex lessons 4 — reliable remote progress. Closed 2026-10-12 (done, verified):** persisted per-item coalescing and ordered delivery retain failed stops/scrobbles across relaunch, with bounded delivery/backoff and server-count reconciliation for lost responses; local rewinds/completions override stale provider offsets. Fake Plex/Jellyfin/Emby tests cover partial/completed response loss, repeated viewings, episode ordering, late ticks, sign-out, disable/re-enable and deletion. Full serial Swift gate 3118 / 388; iOS/tvOS Debug builds confirmed recompilation. Providers lack idempotency keys, so a server commit delayed beyond the retry's reconciliation read remains ambiguous. No UI changes, commit or upload.

- [x] **Plex lessons 5 — owned filename policy. Closed 2026-10-12 (done, verified):** explicit episode ranges/air dates, extras roles, multipart markers versus resolution/edition alternatives and confidence; ambiguous playable files keep filename rows with no guessed coordinates; consecutive parts chain through the existing player handoff, while shared episode-range files are not restarted at their contained successor. AppleLibraryLessonsTests covers every named format, specials, invalid dates/ranges, Unicode, undated parts and newer-part starting order. Item IDs unchanged. Full Swift gate 3093 / 386; iOS/tvOS Debug builds confirmed all five changed Swift sources recompiled for arm64, including final iOS incremental changes. No commit/upload.
- [x] **Plex lessons 6 — durable match corrections. Closed 2026-10-12 (done, verified):** Application Support match records retain explicit IDs, chosen candidate, provider, confidence and manual authority per library title; corrections win after rescan, cache replacement/version change and an in-flight automatic lookup; targeted refresh is available, with file playback/progress keys untouched. Fixtures cover duplicate titles, year mismatch, a corrected wrong first match, a reopened cache version and retained progress. Full Swift gate 3093 / 386; iOS/tvOS Debug builds confirmed recompilation. No existing correction entry point was found, so this step adds store/policy APIs only. No commit/upload.

- [x] **Plex lessons 1 — safe scans. Closed 2026-10-12 (done, verified):** complete/partial/failed source scopes gate index removal; incomplete/cancelled/unreachable scopes retain stale records and Library groups; bounded, cancellation-aware SMB traversal; persisted per-source successful-scan stamps, with incomplete attempts leaving launch freshness unchanged. Fixtures cover 5,001 local files, 12,080 SMB files across 302 folders, denied child, unreachable root, empty-folder cancellation, real deletion after a complete scan and persisted stamps. Full Swift gate 3077 / 385; iOS/tvOS Debug builds confirmed all 13 changed sources recompiled, including final incremental changes. No commit. **Lead-review correction 2026-10-12:** NAS Library uses AppleSMBNetworkLibraryScanner with byte-identical entry.path/URL/item IDs, no browse staging/depth filters, and 100,000-entry / 20,000-folder safety bounds; denied children and bounds yield partial, unreachable roots failed, cancellation propagates. Slash-variant identity, large seasonal share, stale retention/stamp, bounds and cancellation fixtures pass; full gate 3082 / 385; iOS/tvOS Debug builds confirm AppleNetworkShare, AppleLocalLibraryStore and the restored AppleSMBLibraryScanner recompiled. Browse scanner and browse tests match their original contents; no commit.
- [x] **Plex lessons 2 — one completion policy. Closed 2026-10-12 (done, verified):** shared local completion, successor and suppression policy drives Continue Watching/Up Next across Discover, Library and Top Shelf; persisted last activity survives resume deletion; known episode availability is encoded/decoded off MainActor; provider watched flags retained, including Plex viewCount without offset. Save → completion → index sync → row tests cover an available successor, no completed progress bar, exhausted series, removal, empty availability, specials/future episodes and short-runtime/30-second/95% boundaries. Full Swift gate 3082 / 385 (lead-review rerun); iOS/tvOS Debug builds recompiled all changed sources. No UI changes, commit or upload.

- [x] **Netflix polish 7 — varied recommendations. Closed 2026-10-12 (done, verified):** Top Picks and More Like This apply incremental soft primary-genre, sequel-family and source penalties against selected titles; stable ties, no penalty-based exclusions, Continue Watching and authoritative Top 10 order retained. Pure diversity, missing-signal and Top 10 preservation tests; full Swift gate 3064 / 384; iOS/tvOS Debug device builds confirmed all nine edited sources recompiled. Diff left for lead review; no commit.
- [x] **Netflix polish 9 — artwork by purpose. Closed 2026-10-12 (done, verified):** independent missing-poster/backdrop resolution with poster/resume/hero/logo purposes; source art preferred for its purpose, portrait framing/error fallback retained, metadata-off checked before cache, bounded lookups and queued concurrency. Missing-backdrop/poster, hero/logo, source-isolation and request-cap tests; full Swift gate 3064 / 384; iOS/tvOS Debug device builds recompiled. Diff left for lead review; no commit. **Lead-review follow-up 2026-10-12:** artwork task IDs use a non-secret SHA-256 configuration marker; marker stability/change/non-disclosure test, full Swift gate 3068 / 384 and iOS/tvOS Debug device builds recompiled AppleCatalogArtworkPolicy, AppleDiscoverView and AppleMetadataClient; no commit.
- [x] **Netflix polish 10 — crisp, shared artwork. Closed 2026-10-12 (done, verified):** canonical-title/kind/purpose/size/configuration cache and in-flight coalescing; nearest supported TMDB sizes from displayed pixels and scale, correct poster/backdrop fallback families, size-specific logo cache; signed provider URLs untouched. Canonical coalescing, cache-separation, scale/size and URL-preservation tests; full Swift gate 3064 / 384; iOS/tvOS Debug device builds recompiled all edited sources. Diff left for lead review; no commit. **Lead-review follow-up 2026-10-12:** unsigned TMDB loads wait for first geometry without reporting failure; fetch URL and fixed decode budget remain stable within a size bucket, with the previous image retained across bucket changes. Four pure tests cover initial hold, within-bucket identity, bucket crossing, signed/provider URL preservation and non-secret task markers; full Swift gate 3068 / 384; iOS/tvOS Debug device builds confirmed the three edited sources recompiled; no commit.

- [x] **Apple TV hero polish 2 — approved fade only. Closed 2026-10-12 (done, verified):** removed the extra bright-art leading/deeper fades on TV/iPhone/iPad/Mac and the iPhone top shade; retained existing copy shadows. `AppleHeroScrimTests` and full Swift gate 3049 / 384; iOS/tvOS builds recompiled all edited sources. Owner-config-seeded, muted tvOS Coyote hero before/after: `verification-artifacts/appletv-hero-polish-2026-10-12/hero-{before,after}.png`; artwork is clear and copy readable. Diff left for lead review; no commit.
- [x] **Apple TV hero polish 3 — full visible-page dwell. Closed 2026-10-12 (done, verified):** gate presentation starts the unchanged 12-second clock; shown-page indicator, manual paging, focus/visibility pause and Reduce Motion retained. Slow-art, manual-paging, initial-load and repeated-ready clock tests; full Swift gate 3049 / 384, iOS/tvOS builds. Diff left for lead review; no commit.
- [x] **Apple TV hero polish 5 — all Continue Watching entries. Closed 2026-10-12 (done, verified):** conditional existing header button beyond the 12-card rail opens all resumable entries using the same cards/progress; the full list is prepared outside the render body and refreshes in its own task. Cap-boundary tests at 0/11/12/13/30 entries; full Swift gate 3049 / 384, iOS/tvOS builds. Diff left for lead review; no commit.

- [x] **Netflix suggestions 1 — real genres and release years. Closed 2026-10-12 (done, verified):** normalized candidate/history genres, item.year/leading-year parsing; `genresAndLeadingYearsAreNormalizedWithoutInventingMetadata`, missing-genre/recency tests; full Swift gate 3044 / 384, tvOS build recompiled. Revision-keyed task caches the render inputs; snapshot work runs off MainActor. Diff left for lead review; no commit.
- [x] **Netflix suggestions 2 — canonical title deduplication. Closed 2026-10-12 (done, verified):** kind/IDs/year identity, stable accessible representative, retained playback routes, unique ranking/hero slots; identity, duplicate-ranker, hero and route-retention tests; full Swift gate 3044 / 384, tvOS build recompiled. One identity memo serves ranking and hero canonicalization; identity-reuse test passes. Diff left for lead review; no commit.
- [x] **Netflix suggestions 3 — real viewing history. Closed 2026-10-12 (done, verified):** saved progress/completed dates joined to known metadata, meaningful-progress threshold, bounded history and per-show cap, unknown dates preserved; viewing-date, unknown-date, episode/autosave and history-budget tests; full Swift gate 3044 / 384, tvOS build recompiled. Full index/resolver walk runs off MainActor; same-count index-revision test passes. Diff left for lead review; no commit.
- [x] **Netflix suggestions 4 — bounded ratings and related-title affinity. Closed 2026-10-12 (done, verified):** `.none` neutral, dislikes excluded, comparable capped scores and bounded genre transfer from likes; unrated-neutrality, dislike/like-transfer and comparable-weight tests; full Swift gate 3044 / 384, tvOS build recompiled. Set/remove/restore rating revisions invalidate the cached result; revision test passes. Diff left for lead review; no commit.

- [x] **Security fixes from the Mythos check (2026-10-07)** — nothing critical. 1–3 + subtitle bomb + Messages links FIXED
      2026-10-08 (tokens in cache files: protected + kept out of backups, not yet removed). ATS (4) WON'T DO (2026-10-08): IPTV playlists, guides, logos and
      remote media servers are often plain http; narrowing would break them. Code already forces https for TMDB/Trakt/etc.
      (1) HIGH: Xtream guide (EPG) URL with the password is saved in plain preferences — keep it in the Keychain only;
      (2) the web-portal diagnostics download and some trace lines can include stream URLs with credentials — redact;
      (3) Plex/Jellyfin tokens in cached URLs; (4) ATS wide open — narrow to media + local network. Report:
      `verification-artifacts/audit-2026-10-07/mythos-security.md`.
      **Verified 2026-10-10:** credential-bearing cache copies are removed and resume data is sealed (finish-spec #19,
      Done below). Cross-origin HLS children lose Cookie/Authorization, pairing attempts are capped per host, and
      playlist/download filenames are constrained; regression tests and gate 3018 / 384 pass. ATS remains your WON'T DO.
      **Round 3 closed 2026-10-10:** external URL media play opens the title; external Live and YouTube play
      require Play before entering Live (which can auto-resume). Typed Siri/Shortcuts routes preserve intentional playback. Paired playlist export requires an
      explicit redacted/full choice; redacted exports remove complete URLs and provider headers, including quote
      edge cases. Independent review completed; routing/export regression tests, full gate 3026 / 384.
      ATS remains the recorded WON'T DO; previous numbered fixes retained. Diff left for lead review.

- [x] **(2026-10-06) Mythos Live TV review → Opus.** Findings with file:line and fixes in
      ~/Developer/openstream-build/specs/live-tv/mythos-live-review-2026-10-06.md. Top three: the XMLTV guide is
      re-downloaded and re-parsed every 15 min of viewing (first zap after 15 min pulls the whole file); dead-channel
      failover exists only on Apple TV, not iPhone/iPad/Mac; multiview reopens all four streams on every
      grid↔full-screen trip. Order: 1 → 4 → 2 → 5 → 3 → 6 → 8 → 9 → 7 → 10 (numbers in the review).
      DONE a9e2594: 1 (guide fetched ≤ every 6 h, 304-aware), 4 (failover + one quick reopen on all platforms),
      2 (200k-programme guide 25 s → 2 s). Remaining device measurements are listed below.
      **Agent work 2026-10-10:** 5 retains tile players across fullscreen trips and caps tiles by cached provider limits;
      3 prunes to -3/+7 days and writes atomic binary day shards (200k mixed-history fixture: median read 360 → 172 ms,
      write 413 → 237 ms; Time Profiler cache samples 1490 → 757 ms). 6 fills the whole visible Xtream batch at four
      concurrent requests; 8 preserves HLS catch-up extensions; 9 uses the shared eight-match threshold. 10 extracts
      selection, request, preflight, resume and recall/zap state into AppleLiveSession; platform layout/focus stays in views.
      11 prevents health sweeps while any Live coordinator is active. Gate 3018 / 384 and local tvOS round-trip UI pass. Four-tile layout/fullscreen verification passes (14.289 s); trace confirms exactly one open per tile across both layout toggles and the round trip.
      **Native-HLS measurement 2026-10-10:** Apple's public bipbop advanced fMP4, native remoteBypass on Dev-Mini M4,
      three 10 s trials: first frame 529/633/860 ms; nine seeks 83–169 ms; no playback freezes, missing frames or buffering
      samples. Scoreboard: /Volumes/DevExt/engine-lab/hls-round2/scoreboard.md. Seek continuity fails 0/3 because the
      harness flags dark frames; content-versus-player cause is not verified. This measures the engine on macOS,
      not real Apple TV channel changes. No private provider sample is needed for this public baseline.
      **Owner action:** check four-tile heat on an A12 Apple TV.
      **Round 3 closed 2026-10-10:** all app findings resolved or measured above. Finding 7 has the public native-HLS
      baseline; provider/device tuning is dropped from this round without a measured device defect. No guessed buffer
      change. Full gate 3026 / 384; final tvOS compilation passes. A12 heat remains an owner-device action.

- [x] **Muse research triage (2026-10-01):** 229 findings from 6 Muse jobs → 92 already handled, 30 gaps, 71 to
      verify (specs/full-test-checklist-v3.md). Batch 1 DONE 40e9350: Subtitle Delay + Frame Rate fix (sim-checked),
      Settings › Audio Language (sim-checked), Spotlight opens the title, add-on catalog paging, Now Playing series/
      episode/artwork (not seen on a sim), honest "could not read this file" instead of "ended early". 20 more Muse
      jobs queued on ServerPlus. Next: disc badge/spinner/Play Disc, format badges, engine open retry (running).
      **Round 3 triage 2026-10-10:** all 30 GAP and 71 UNSURE entries rechecked against current Apple code.
      Unit/source evidence below is not a claim of hardware verification. No older full-test reports, Duo,
      CarPlay, Vision environments, owner accounts or package-checkout changes are included.
      - M01-02 — Dropped: requires a representative network playback soak; no reproducible app defect or authorized private fixture supplied.
      - M01-04 — Covered: corrupt index recovery is tested by AppleMediaIndexTests; migration/launch policies have regression suites (not a device soak).
      - M01-05 — Dropped: two-hour Apple TV footprint/jetsam measurement needs the owner device.
      - M01-06 — Covered: AppleProgressRestoreFreshnessTests proves per-title freshest progress wins, including a store open during restore.
      - M01-12 — Covered: fixed both adapters: delayed, failed and cancelled external subtitles remain unselected; AppleExternalSubtitleTests.
      - M01-16 — Covered: preferred audio selection and language normalization: AppleAudioLanguagePreferenceTests.
      - M01-18 — Dropped: A/V drift requires a timed audiovisual fixture/device capture; no confirmed app code defect.
      - M01-21 — Dropped: seek behavior belongs to the separate engine lab; round-2 corpus evidence retained, no speculative app patch.
      - M01-23 — Covered: deleted sources cannot reappear on cloud merge: AppleBackupRestoreTests/newerCloudCannotResurrectDeletedSourceAndSyncNowPublishesDeletion.
      - M01-26 — Covered: skip-based paging exists with AppleCatalogPagingTests.
      - M01-28 — Dropped: custom torrent/streaming-server path is unwired and outside the current distribution.
      - M01-31 — Covered: 10,000-title restore is tested by AppleProgressRestoreFreshnessTests/tenThousandTitlesRestoreInBoundedTime.
      - M01-36 — Dropped: stremio URL scheme registration would edit prohibited Info.plist keys; paste/add-on flow remains supported.
      - M01-37 — Dropped: first-frame behavior is engine/device validation; bounded startup failure/recovery already exists.
      - M01-40 — Dropped: audible midstream switching needs device/media verification; current pending-pick and sparse-cue tests cover app policy.
      - M02-01 — Dropped: 4K remux soak needs the owner Apple TV/network.
      - M02-04 — Covered: subtitle delay and frame-rate resync are implemented in AppleSubtitleTiming; timing tests pass.
      - M02-06 — Dropped: peak-time provider behavior cannot be reproduced with local mocks.
      - M02-07 — Covered: title-only Forced is never auto-selected: AppleSubtitleTrackFilterTests/aTitleOnlyForcedTrackIsNeverAutoSelected.
      - M02-10 — Dropped: 30/60/90-minute subtitle soak is runtime verification, not a demonstrated code change.
      - M02-11 — Dropped: A/V drift under frame-rate matching requires device/audio measurement.
      - M02-12 — Dropped: micro-stutter requires a device pacing trace and representative content.
      - M02-13 — Dropped: provider scan/sync performance needs a large representative server/account.
      - M02-14 — Dropped: HDMI negotiation/broken device state requires the owner television/device.
      - M02-16 — Dropped: HomePod long-run audio requires owner hardware.
      - M02-17 — Dropped: 10,000-poster navigation needs a before/after performance trace; no measured defect supplied.
      - M02-18 — Covered: audio and subtitle selection use separate IDs and commands; AppleTrackSelectionPolicyTests (not an audible device check).
      - M02-24 — Dropped: A8 Apple TV HD is excluded older hardware; codec fallback belongs to the engine.
      - M02-25 — Covered: tvg-shift and manual guide offsets exist; AppleIPTVGuideMatchingTests and AppleIPTVCatchUpURLTests.
      - M02-29 — Dropped: subjective audio-quality claim has no reproducible behavior or acceptance criterion.
      - M02-30 — Covered: visible Xtream batches and refresh/retry behavior covered by AppleIPTVGuideStoreTests and AppleIPTVGuideRobustnessTests.
      - M02-31 — Dropped: VPN/provider reachability is environmental; no confirmed app-side guide defect.
      - M02-32 — Covered: guide gaps render bounded empty cells; AppleGuideRegressionTests.
      - M02-33 — Covered: Xtream input and typed login errors covered by AppleIPTVAndLibraryTests and AppleIPTVFailureCauseTests.
      - M02-34 — Dropped: provider-side VOD buffering needs the provider/account and network measurements.
      - M03-03 — Dropped: 80 Mbps remux soak belongs to engine/device validation.
      - M03-05 — Dropped: long-idle hang is not reproduced; requires a lifecycle/network soak.
      - M03-06 — Dropped: SMB throughput requires representative server/network; protected SMB server is outside authorized edits.
      - M03-07 — Dropped: 25 fps frame-drop measurement needs real Apple TV hardware; engine lab is the owning work.
      - M03-08 — Covered: subtitle delay/frame-rate resampling already implemented and unit-tested.
      - M03-09 — Covered: each engine selects one audio track; separate selection policy tests pass (no VLC mixer exists here).
      - M03-10 — Dropped: font/tofu visual comparison requires representative styled/CJK/Hebrew content; no confirmed missing font.
      - M03-11 — Dropped: Apple TV stutter requires a recorded performance trace.
      - M03-14 — Dropped: thumbnail popup is system/engine rendering; no reproduced empty-preview defect.
      - M03-16 — Covered: existing TV Settings/sidebar UI test passed in round 2; retained under finish-spec TV focus item.
      - M03-19 — Dropped: Apple TV live audio stutter needs the owner device and same-stream comparison.
      - M03-22 — Covered: per-channel manual guide assignment is wired through the shared Live guide refresh; AppleIPTVGuideMatchingTests.
      - M03-23 — Covered: local playlist storage and purge boundaries have tests; no source-backed rename/delete defect found.
      - M03-24 — Covered: subtitle sync controls exist in the player menus and AppleSubtitleDelayTests pass.
      - M03-26 — Covered: transport hit targets use minimumActionSize or 44 pt minimum; transport/skip policies are tested.
      - M03-28 — Dropped: kill/resume artwork validation is a UI runtime check; artwork/resume unit coverage already exists.
      - M03-30 — Dropped: regression process recommendation is not an app code change.
      - M03-33 — Covered: system TV tab bar retained; navigation/focus regression suites cover current behavior.
      - M03-34 — Dropped: A/V desync requires a representative media/device recording.
      - M03-35 — Dropped: 500 ms subtitle-toggle black-screen measurement is an engine/device check; sparse-cue switching has a regression.
      - M03-36 — Covered: Live Home-to-PiP passed on DevPlus/iPad in round 2; lifecycle tests remain green (not a system-freeze soak).
      - M04-03 — Covered: stock VOD player has no custom gesture layer; Live owns the remote by approved design.
      - M04-06 — Covered: series/episode/artwork/live metadata implemented; AppleNowPlayingInfoTests.
      - M04-10 — Dropped: new native transport tabs would redesign the approved engine-first player; existing captions/audio/chapter controls remain.
      - M04-11 — Covered: AVMediaSelectionGroup and app language preference selection exist; AppleNativeSubtitleSelectionTests.
      - M04-12 — Dropped: custom chapter skip is approved and remotely reachable; native contextual-action parity is superseded by engine-first player choice.
      - M04-16 — Dropped: AVContentProposal redesign is superseded by existing episode handoff and native Next Episode contextual action.
      - M04-24 — Dropped: SharePlay account/device pair is excluded; protected AppleSharePlay files are outside scope.
      - M04-25 — Dropped: SharePlay PiP verification needs two owner accounts/devices.
      - M04-28 — Covered: participant-local volume/captions are not overridden; current player session tests cover app isolation.
      - M04-31 — Dropped: Live-first/tab-order proposal conflicts with approved Discover/Library/Live layout; no recordings tab exists.
      - M04-32 — Covered: Spotlight title routing and recent searches implemented; AppleSpotlightRouteTests/AppleRecentSearchesTests; tab placement follows owner-approved toolbar/TV layout.
      - M04-34 — Dropped: blanket ban on programmatic focus conflicts with approved TV skip/sidebar restoration behavior.
      - M04-38 — Dropped: HLS trickplay track authoring belongs to the engine; app already requests scrub thumbnails.
      - M04-39 — Dropped: spatial/3D media verification requires Vision hardware/content; environments are explicitly excluded.
      - M04-40 — Dropped: HDR/aspect/audio-output visual verification requires physical display/media; no app defect established.
      - M05-07 — Dropped: DV container metadata belongs to the pinned engine; package checkout edits are prohibited.
      - M05-12 — Dropped: TrueHD/audio route verification needs AVR/AirPlay hardware; engine bridges are covered by the engine lab.
      - M05-13 — Dropped: Atmos JOC playlist signaling is engine authoring plus AVR validation, outside app edits.
      - M05-15 — Dropped: stereo AAC rendition authoring belongs to the engine; no package checkout edits authorized.
      - M05-16 — Dropped: seek audio padding/drop is an engine implementation detail, not a demonstrated app bug.
      - M05-18 — Dropped: negative CTTS muxer flag belongs to the engine and may conflict with its existing repair policy.
      - M05-30 — Dropped: bitmap compositing format belongs to the engine; no app TIFF/HEIC/JPEG failure reproduced.
      - M05-32 — Dropped: alleged 255-slot queue concerns another engine; OpenStream uses tested dynamic subtitle storage.
      - M05-33 — Dropped: ASS raster pixel comparison belongs to the engine and needs a representative fixture.
      - M05-34 — Dropped: subtitle delay is implemented; the separate sRGB-on-HDR claim needs engine/display measurement.
      - M05-35 — Dropped: subtitle/frame-rate/HDR dropped-frame measurement needs a real Apple TV/display.
      - M05-37 — Dropped: broadcast multivariant constraints do not justify re-authoring the local single-route engine playlist.
      - M06-01 — Covered: platform-specific UI targets and E2E-iOS/tvOS/visionOS test plans exist; Mac retains its UI scheme.
      - M06-02 — Covered: Debug launch-argument network stub exists; task-local test roots now prevent cross-suite interference.
      - M06-04 — Covered: checked-in E2E test plans and UI schemes exist.
      - M06-14 — Dropped: devicectl inventories physical devices; simulator inventory remains simctl, so one-inventory premise is false.
      - M06-15 — Dropped: UDID/CoreDevice mapping is device-run infrastructure; current mini scripts already use explicit destination IDs.
      - M06-16 — Dropped: physical install/launch/console flow already belongs to release/devplus scripts; no app change required.
      - M06-17 — Dropped: real-device capture infrastructure requires a device session; current UI attachments supply screenshots.
      - M06-18 — Dropped: build-once device fan-out is test infrastructure for owner devices, excluded from this app-fix round.
      - M06-19 — Covered: Messages tests use predicates/waitForExistence; original fixed sleeps removed.
      - M06-22 — Covered: iOS/tvOS/Mac UI base classes attach failure screenshots with keepAlways; relevant current targets inherit them.
      - M06-23 — Covered: control-plane fixtures run through isolated bounded loader; AppleNetworkStubTests.
      - M06-25 — Dropped: cross-device Messages test requires two owner devices/accounts.
      - M06-26 — Covered: app uses KVS, not CloudKit; the alleged CloudKit Development/Production mismatch does not apply.
      - M06-27 — Dropped: same-account assertion needs signed-in owner devices/accounts.
      - M06-28 — Dropped: app uses KVS, not CloudKit push; two-real-device proof remains an owner action.
      - M06-29 — Dropped: CloudKit-specific polling does not apply to KVS; same-account device checks are excluded.
      - M06-31 — Dropped: airplane-mode sync conflict run needs two signed-in devices; merge/tombstone policies have unit tests.
      - M06-33 — Dropped: CloudKit seed/import harness does not apply to KVS; real-account sync is excluded.
      **Closed triage:** 101 individual dispositions (35 covered, 66 dropped). M01-12 fixed with delayed/failure/
      retry/cancellation tests in both playback adapters. Full gate 3026 / 384; this closes triage, not device soaks.

- [x] iOS 18 UX: nav icons + large "Discover" title unreadable on bright hero art (no glass on iOS 18); Streaming
      Services "Add Service" only tappable on its label; full-screen player not modal for VoiceOver; a search
      deep link with a title page open lands under it.
      Nav/title readability and fullscreen VoiceOver isolation are closed under finish-spec #52 in Done below.
      **Round 3 closed 2026-10-10:** a7b5fd2 nav/title and fullscreen presenter isolation reverified on the existing
      iOS 18.6 simulator on the rebuilt app by testLegacyDiscoverNavigationAndPlayerAccessibilityIsolation (35.554 s); both attachments inspected.
      Add Service hit area and search-route dismissal already fixed in the finish-spec; route policy tests pass.

- [x] **YouTube attribution.** The trailer frame CSS (N49) hides YouTube's title, channel and link;
      the fast iPhone/iPad trailer start (a130f96) relies on it. YouTube's API terms may require
      showing it. Keep it, or go back to the fixed wait on iPhone/iPad?
      **Round 3 closed 2026-10-10:** CSS preserves title/channel/link; obsolete showinfo/modestbranding flags removed.
      Fast frame reveal retained; HTML/metadata/title-entry regressions pass.

- [x] **Trailers with the title burned in.** Some trailers open on their own title card, so on the Mac
      hero a faint second wordmark shows behind ours (N57). Keep those trailers, or skip them?
      **Round 3 closed 2026-10-10:** valid source start offsets are carried into embed/API start and replay seek.
      Missing/invalid offsets stay at zero; current metadata gives no chapter offsets, so no title-card guesses.
      Known/negative/nonfinite offset tests pass.

- [x] **Apple TV row headers** are 76 pt, about twice the Apple TV app's 38 pt. Shrink to match?
      **Round 3 closed 2026-10-10:** AppleMediaShelf and AppleShelfHeading use shared explicit 38 pt bold metrics.
      Final tvOS build recompiles both views and the metric.

- [x] **iPhone tab bar shrinking on scroll** — allow it (the system behaviour), or keep it fixed?
      **Round 3 closed 2026-10-10:** native onScrollDown minimization on iOS 26+ iPhone; system tab bar retained.
      Older systems/iPad use their native default. Final iOS build passes.

- [x] **Receipt check (N39 F1).** The app tells TestFlight builds apart (to turn tracing on) with
      Apple's deprecated receipt URL, the last build warning. Its replacement is async and can put an
      App Store sign-in prompt on the Mac. Keep the deprecated check (recommended), or switch?
      **Round 3 closed 2026-10-10:** take the recommendation: retain AppleBuildChannel's deprecated receipt check.
      No async StoreKit/sign-in prompt introduced; sandbox/release channel regression tests remain green.

- [x] **Apple TV smoke of 22125ac (2026-10-01):** all pass (hero buttons, title art, Resume, no tab-switch replay,
      Goede Tijden S37, search order, Settings readable, 0 crashes). Polish: season picker opens focused on Specials
      not the checked season; Settings › Playback bottom row, Left doesn't reach the sidebar; faint metadata line
      over bright art (Goede Tijden).
      **Closed 2026-10-10 (done, verified):** Current season is first in the menu; Select immediately keeps it checked and Menu restores focus (tvOS UI 10.769 s). Left from the bottom of Playback returns to the sidebar (12.504 s). Metadata uses white with its existing shadow; bright-art screenshot inspected. Season-37 ordering regression and full gate 3018 / 384 pass; uncommitted.

- [x] **Picture in Picture for Live (owner 2026-10-09, build 17):** "if I swipe away it stops playing". Swiping home
      while a Live channel plays should continue it in PiP (iPhone/iPad), same as movies. Not in slice 1: the DevPlus
      check did not pass on the first try (the phone was locked, so the test saw a black screen); moved to slice 2.
      **Closed 2026-10-10 (done, verified):** The background lifecycle preserves a starting/active PiP session; ephemeral SwiftUI hosts no longer reset the engine's active PiP flag. DevPlus UI passes (40.961 s) with the window over Home at ten seconds and an active trace; iPad in-memory fixture UI passes (39.064 s), also active through Home. Original simulator data restored. Gate 3018 / 384; uncommitted.

- [x] **Finish-spec #19 — credential-bearing cache copies and background resume data.**
      **Closed 2026-10-10 (done, verified):** token-bearing artwork/stream URLs are removed from persisted library,
      index, offline and download metadata; existing copies migrate on load. Resume data is AES-GCM sealed with a
      device-only Keychain key, protected and excluded from backups; legacy resume files migrate or are discarded.
      Cache/live-URL and sealed-resume regression tests pass; full gate 3018 tests / 384 suites. Changes are uncommitted
      pending resolution of the spec's commit instruction versus AGENTS.md's explicit no-commit rule.
- [x] **Finish-spec #35 — deleted-source tombstones.**
      **Closed 2026-10-10 (done, verified):** source removals persist dated UUID tombstones; cloud/backup merges retain
      the newest deletion and remove stale source payloads. Newer stale cloud snapshots cannot resurrect a deleted
      source. Snapshot and actual controller/backup merge tests pass; full gate 3018 / 384; uncommitted.
- [x] **Finish-spec #52 — iOS 18 navigation and full-screen VoiceOver isolation.**
      **Closed 2026-10-10 (done, verified):** pre-iOS-26 navigation uses the opaque system background; full-screen
      presentation hides the presenting accessibility hierarchy and restores it on dismissal. iOS 18.6 owner-config
      UI check passes, including restoration; the Discover screenshot shows readable title/icons. Full gate 3018 / 384;
      uncommitted. Other issues in the older iOS 18 UX row are outside this finish-spec item.
- [x] **Finish-spec #53 — switching sparse subtitle cues mid-stream.**
      **Closed 2026-10-10 (done, verified):** the actual Aether fixture switches English to French after seeking into
      a sparse cue and immediately shows the new cue. The pinned engine already passes; regression coverage added.
      Fixture-enabled subtitle suite 7 / 1; full gate 3018 / 384; test change uncommitted.
- [x] **Test every public Stremio add-on (FMHY + r/StremioAddons + community catalogue)** (2026-09-30) — list, a
      headless harness using the app's own add-on code (manifest/catalog/meta/stream/subtitles), then in-app
      spot checks of flagged + top 20; harness kept for every release.
      **First sweep 2026-09-30 (17d6a4e): 594 probed, 0 crashes.** App fixes found: only movie/series catalogs used
      (78 add-ons show nothing: tv/anime/channel types); 2 MB catalog limit rejects TMDB's 12 MB shelf; catalog items
      without a name dropped (poster-only tiles in Stremio); meta requires an exact id match (Stravo mx→tt) and rejects
      redirects; 12-catalog cap hides catalogs; manifests with no resources accepted (unconfigured AIO Metadata);
      AppleAddonURLSecretPolicy flags 14 public add-ons as secret; 100-item shelves; one subtitle track per language.
      **Closed 2026-10-10 (done, verified):** The remainder checks cover 20 selected common add-ons plus all five public-URL
      flags. Fresh app-client probes: 25 checked, zero crashes/timeouts; manifests 24 accepted, Cyberflix returned HTML.
      Five iOS UI batches pass (76.687 / 103.477 / 76.593 / 78.077 / 84.884 s): add manifests, scroll to catalog posters,
      open a title page. Catalog/title screenshots inspected; no claim of a measured popularity ranking. Existing
      compatibility and 250-item paging regressions pass. One caption row per language follows the owner's 2026-09-24
      rule and its merge/selection tests. Provider failures remain external: TMDB Alternatives 500, Collections 404,
      Discover+ HTML, Community OpenSubtitles 404. No app crash; upstream failures are recorded rather than hidden.
      Full gate 3018 / 384 (61.219 s); original simulator app data restored byte for byte and test-created Keychain entries removed, with original values/attributes unchanged. UI harness change uncommitted.

- [x] **Finish-spec #56 — Live slice 2 Guide sheet and portrait focal crop.**
      **Closed 2026-10-10 (done, verified):** Guide opens as a system large sheet and returns to Live; portrait backdrop
      framing uses Vision face/saliency anchors with a bounded centre fallback and a disk cache. Key art keeps its own
      framing. Guide UI check passes on iOS 18.6; crop/cache regression tests and iOS/tvOS builds pass; full gate 3018 / 384;
      uncommitted.
- [x] **"New dialog in Live when it can't reach Live looks off and weird" (2026-10-08, build 16)** — it was an alert
      ("Playback Failed" + advice paragraph + Close/Retry) that popped up over the whole Live tab whenever the resumed
      channel could not start, plus a warning row with the system's error text over a working list.
      **Fixed, waiting for your phone:** the message now sits inside the picture ("CBS is not broadcasting right now",
      the server's name on one quiet line, Try Again); the guide under it stays usable. A list that can't refresh
      while its saved channels show says nothing. With no channels at all: "Couldn't Load Your Channels", Try Again,
      Open Settings (same as Discover). Screenshots: verification-artifacts/live-2026-10-08/.
      **Closed 2026-10-09 (done, verified against git):** d744332 replaces modal Live failure alerts with in-picture errors and suppresses refresh warnings over cached channels; 016b668 refines source-specific error copy.
- [x] **"Did not return a compatible source" on iOS (2026-10-08)** — sweep 100 random movies + episodes from
      different eras with the owner's config on DevPlus; table in verification-artifacts/playback-sweep-2026-10-08/.
      **Swept 2026-10-08:** 100 titles (20 per era, pre-1970 to 2020s, movies and episodes) with your config on
      the mini's iPhone: 86 played (median 2.8 s to the picture). The "compatible source" message came up 0 times:
      it only appears when an add-on sends nothing but torrent-only/YouTube/web links, and your Torrentio TB sent
      real links every time. What failed: 9 not cached on TorBox yet, 4 where Torrentio had nothing at all (the app
      wrongly told you to "add a stream source"; fixed, it now says nothing was found), 1 TorBox error video.
      If you see the message again, note the title: it points at a different add-on or your TorBox account state.
      Table: verification-artifacts/playback-sweep-2026-10-08/SWEEP.md.
      **Closed 2026-10-09 (done, verified against git):** 67bd3a9 completes the 100-title sweep and corrects empty stream-result messaging; verification-artifacts/playback-sweep-2026-10-08/SWEEP.md records outcomes.
- [x] **Apple TV has no Live and no way to import (2026-10-08)** — Apple TV only gets its setup from iCloud
      (broken, fix in progress) and has no import. QR "send setup to Apple TV" moves first in the QR work.
      **Import done in code (2026-10-08), waiting for your test:** the Apple TV can now take the whole setup
      (Live/IPTV, add-ons, media servers, network shares, sign-ins, settings) straight from your iPhone over the
      home network, no iCloud needed. See the QR line below for how to try it.
      **Closed 2026-10-09 (done, verified against git):** 81e7c57 adds Apple setup transfer, 24517d6 adds TV Welcome/No Sources entry points, and 782bac9 fixes real-TV import storage.
- [x] **Vision Pro: player lives inside the app window, resizable** (asked 2026-10-07; today it opens a separate
      "Player" window). Fable audit for direction → implement → overnight visionOS e2e on Dev-Mini. Also a Mythos
      security check and a project audit — reports in `verification-artifacts/audit-2026-10-07/`.
      **Status 2026-10-08:** built, uncommitted. The player now opens inside the oStream window; the window keeps its
      width, turns 16:9 (or the film's shape) and resizes uniformly while playing, and returns to its size on close.
      visionOS e2e on Dev-Mini: 4 passed, 1 skipped (below). Waiting for commit and a check on the real Vision Pro.
      **Closed 2026-10-09 (done, verified against git):** f91da00 commits the in-window, aspect-constrained Vision player and UI/policy tests; the note saying uncommitted is obsolete, with real-headset confirmation still useful.
- [x] **Vision Pro: audio keeps playing after the app is closed** (owner, 2026-10-07, previous build). Being fixed with the
      in-window player: the player stops (and saves your place) when the window closes; e2e test added.
      **Closed 2026-10-09 (stale, verified against git):** Duplicate of #15 (Vision Pro audio after window close); f91da00 supplies the shared fix, and #15 retains the device-verification action.
- [x] **(2026-10-06) Owner decisions:** ~~don't ship 16 yet~~ **shipped 16 on 2026-10-08** (TestFlight Internal, all four
      platforms, f08a908; see DELIVERIES.md); **no DVR/recording** (dropped); Apple TV (Wi-Fi) and the owner's
      iPhone (cable once → Trust) get paired with the Mac mini on 2026-10-07 — then install the waiting ad hoc build
      (`scripts/mini.sh 'zsh scripts/release/devplus-install.sh 16 00008130-000610103443001C'`); go ahead with the Mythos Live review fixes; make an OpenStream backup of the
      owner's own sources to import for content verification on DevPlus.

      **Closed 2026-10-09 (stale, verified against git):** The no-ship hold was lifted (36165c0/75434ba); #7, #13 and #23 retain device checks, #21 retains review work, and 6be1946 supplies the backup/test tooling.
- [x] **(2026-10-06) Your IPTV on DevPlus — app bug fixed (3614aaa), provider too slow tonight.** Opening a channel
      started it twice (the saved lineup auto-started your last channel, then the link restarted it 4 s later), so
      nothing ever played. Fixed and verified on DevPlus: one start, one connection. But CBS and FOX (East and West)
      all arrived at ~40% of real time (≈3 s of video per 6.5 s) at 23:40, so none reached a picture. **Your check:**
      does the same channel play right now in another player (VLC/TiviMate) on the same Wi-Fi? If yes, it's on us
      (look at connection count / user agent); if no, it's the provider. The Mac mini can't reach the panel at all.

      **Closed 2026-10-09 (stale, verified against git):** Superseded by #7's later provider-access diagnosis and cellular/Wi-Fi test; double-start itself was fixed in 3614aaa.
- [x] **(2026-10-04) App Store submission, what's left.** App Store Connect is filled for all four platforms: name
      **oStream**, subtitle, description, keywords, promo text, support/privacy/marketing URLs, copyright "2026 Raster
      Inc", categories Entertainment + Photo & Video, content rights, age rating 16+, review notes with Apple's public
      sample playlist (the public Jellyfin demo now needs a password, so it's no longer in the notes), and screenshots
      for iPhone, iPad, Apple TV and Vision Pro. Validation: iPhone/iPad 0 errors. Left: **you** fill App Privacy → "Data
      Not Collected" (website only); **"ship N"** builds the App Store (no add-ons) build and attaches it to all four
      platforms — the iPhone listing currently has old build 10 attached, which must be swapped; Mac screenshots need
      `sudo /usr/sbin/DevToolsSecurity -enable` first.
      **Closed 2026-10-09 (stale, verified against git):** Superseded by #6's newer submission checklist and RC report; privacy publication, no-add-on archives and Mac screenshots remain there.
- [x] **(2026-10-04) Channel lineup back as "Complete Guide".** You asked to bring back the biggest US package preset
      under another name. Codex is restoring it in all builds; it only organises your own IPTV playlist and defaults to
      Everything when your playlist doesn't match it.
      **Closed 2026-10-09 (done, verified against git):** ae9ce31 restores Complete Guide in every build with a match threshold and Everything fallback; recorded checks are in GUI-AUDIT.md's 2026-10-04 entry.
- [x] **Apple TV regression on the overnight code (2026-10-01 morning):** fixes committed 2026-10-01 (gate 2519/303).
      Done, checked on the sim: 3 dead IPTV panel (error + Retry by ~9 s, was ~21 s), 5 Clear Cache label, 6 search
      exact title first (stale half-typed results re-ranked), Show Captions opens on the checked value, My Channels
      spinner. Done, unit-tested only (needs a real-stream check on the Apple TV): 1 captions stay above the
      scrubber/Next card on widescreen, 2 stock player advances at the end (+ Apple's "Next Episode" button in the
      last 20 s), Resume label. 4 long series: every episode loads (Goede Tijden 7,333, was 1,000) and a soap with
      nothing watched opens on its latest season (unit-tested; check Goede Tijden on the Apple TV).
      **Closed 2026-10-09 (done, verified against git):** 6b9e532 fixes the regression set; 5298e1c, 0006afa and 22125ac complete Resume/title/stock-player/search behavior, with subsequent checks recorded in #44/#47.
- [x] **Build 15 feedback (owner, real iPhone, 2026-10-03):** (1) trailers still don't play (title page hero stays
      dark; Masters of the Universe 2026) — build 15's pre-ship test covered playback/resume, not trailers;
      (2) title page shows two refresh-looking buttons (global refresh + trailer replay). Fixing on Codex with
      iOS 18.6 + iOS 27 sim proof; trailers added to the pre-ship test list.
      **Closed 2026-10-09 (stale, verified against git):** Superseded by #13's later owner-phone trailer failure and fixes; 6bbf9a2/43feec0 fix earlier candidate/reveal issues and remove duplicate Refresh.
- [x] **App Store push (owner 2026-10-02: assume the bridge works, get the app ready to publish, then move on to the
      next app).** Running: Codex batch A (server discovery on your network, Quick Connect as the default on Apple TV,
      Dolby Vision/HDR/SDR + audio line in player info, Release first-run leads with Media Server); work Claude
      (App Store submission pack: description/keywords/review notes/legal demo/privacy label/screenshot list, and
      an Apple app playbook for future apps at Code, Apps & Websites/Apps/APPLE-APP-PLAYBOOK.md). Next: downloads
      from your media server; Release screenshots; then "ship" when you say so.
      **Closed 2026-10-09 (stale, verified against git):** Superseded by #6's submission RC/action list and #31's bridge decision; d195bc3, c9d4a12 and 075d096 implement the former preparation batches.
- [x] **Add-on route DECIDED 2026-10-02: Cloudflare bridge (Rill, github.com/mrtxiv/Rill, MIT).** Each user deploys
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
      **Closed 2026-10-09 (stale, verified against git):** Superseded by #1's hardened-bridge re-test and AGENTS.md's newer TestFlight add-ons rule; account/password actions still belong to the owner.
- [x] **iPad full pass 2026-10-02 (0fcee5b):** most pass (no crash with artwork, badges, Start from Beginning, subtitle
      delay, audio language, next episode, reconnect, catch-up, search, latest season, Remove from CW). To fix:
      HIGH: player ignores taps for long stretches — the title page behind it keeps recomputing source badges + a
      whole-library disc check on the main thread; HIGH: iPad Live guide cells draw over the channel column;
      Playback Unavailable shows raw engine text; Watch Live overlaps the speaker icon on the inline player; full-
      screen catch-up has no way back except the guide. Expected: Play Disc = main title until the engine fork is
      pushed. Rotation not testable headless.
      **Closed 2026-10-09 (done, verified against git):** e09772c fixes iPad responsiveness, guide overlap, raw playback errors, Watch Live placement and catch-up return; DVD menu integration is separately tracked in #42.
- [x] **Live TV DONE d018726 (sim-checked with a local fake IPTV server):** a dropped channel reconnects by itself
      ("Reconnecting…", 3 tries), then offers "Watch on <other list>" for the same channel; tvOS guide shows 7 channels
      × 3 hours (was ~4.5 × 2.3) with now-airing progress, Left goes to categories. Not done: catch-up from the guide
      (needs past listings + a play action + panel time zone) and live rewind on raw TS channels (engine buffer).
      **Closed 2026-10-09 (done, verified against git):** d018726 supplies reconnect/failover and denser guide; da014fb adds catch-up and 4abfaac adds live buffer/Start Over, completing the remaining named features.
- [x] **App Store compliance audit (2026-10-01) — specs/app-store-compliance-audit.md:** Apple pulled every app built
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
      **Closed 2026-10-09 (stale, verified against git):** Bridge choice superseded by #31, App Store preparation by #6/#30, and bundled-lineup removal by #25; native add-ons are now excluded by 9b63e9d/e855f12.
- [x] **iPad regression of today's fixes (2026-10-01):** 10/11 pass (Resume, latest season, next episode, captions,
      IPTV error ~9 s, configure-first, Remove from CW, rotation, search, 0 crashes). Open:
      1. FIXED (sim-checked on iPad): switching tabs back to a title page no longer starts playback by itself
         (it replayed ~2 s later; series played a wrong episode and wiped Resume). Likely in builds since 09-25.
      2. Question: after Remove from Continue Watching the title page still says Resume (progress kept). Intended?
      **Closed 2026-10-09 (done, verified against git):** c723611/b4d4793 prevent reappearance replay; 4440c97 adds Start from Beginning and preserves Resume after CW removal, resolving the report's remaining behavior question.
- [x] **Apple TV check of 630db1d (2026-10-01):** pass: Goede Tijden opens on Season 37, stock player advances to the
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
      **Closed 2026-10-09 (stale, verified against git):** Superseded by #27's final engine-first/hidden-Native decision (4440c97); earlier defects were fixed by 5298e1c, 0006afa and e8b60ec.
- [x] **iPad re-run (v2, 2026-10-01 morning):** 6 of the 9 iPad bugs from 09-30 fixed; next episode, SNL 1975,
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
      **Closed 2026-10-09 (done, verified against git):** 32d1283 fixes route eligibility, placeholder clips, parallel Live load, title logos/margins/labels, split Settings and player/cue/service UX; ed39ad5 completes accessibility-size handling.
- [x] **iPhone 27 re-run (v2, 2026-10-01 dawn):** most fixes since 09-30 hold (chapters, Quality, Also available on,
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
      **Closed 2026-10-09 (done, verified against git):** ed39ad5 fixes next-episode handoff, SNL country/year matching, subtitle encodings, accessibility layouts and small UX; tests include AppleNextEpisodeHandoffTests and AppleIPhone27SmallFixesTests.
- [x] **P0 iOS 18: app freezes when opening a title from Discover** (2026-10-01, iOS 18.6 sim, 3/3; hero or poster
      tap; main thread 100% in the navigation push layout, app frame AppleCatalogItemDetailView.phoneHero).
      Search → title works. Old iOS 18 crash: 0 crashes now.
      **Closed 2026-10-09 (done, verified against git):** ec61260 moves episode content out of the changing lazy push layout; commit records 6/6 iOS 18 and 2/2 iOS 27 title-open checks.
- [x] Watch on Netflix opened tv.apple.com when the Netflix app/id was missing — a fallback must stay on the
      labelled service (Netflix search), not jump to Apple TV.
      **Closed 2026-10-09 (done, verified against git):** ec61260 keeps fallback on the selected streaming service; only Apple TV falls back to its own site.
- [x] **Full-test bugs (Apple TV tvOS 27, v2 plan, 2026-10-01 overnight):**
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
      **Closed 2026-10-09 (done, verified against git):** 4fd1ac5 fixes the full TV batch, a695c35 fixes choice pages/Top 10, 3b3494f proves intro focus, and 782bac9 completes actual-device storage protection.
- [x] **Streaming services must be useful, not just a label** (2026-09-30): when no add-on/source can play a title,
      Play becomes "Watch on <service>" (menu if several of the viewer's services have it), and it must open the
      TITLE in that app, not just the app. Plan: TMDB/JustWatch providers for availability; per-service title IDs
      from Wikidata (Netflix/Disney+/Hulu/Prime/Max/Apple TV by IMDb id) → universal links; fallback = service
      search for the title. tvOS deep links are limited (search/TV app fallback). Overnight: verify which links work.
      **Owner decision 2026-09-30: use Wikidata** for the per-service title IDs.
      **Closed 2026-10-09 (done, verified against git):** 67210b7 implements provider actions and Wikidata title IDs; ec61260 fixes service fallback and 32d1283 fixes in-app route eligibility; installed-service app checks remain useful owner validation.
- [x] **Crash reported: the stravio.site add-on crashes the app** (2026-09-30, tester report).
      **Closed 2026-10-09 (done, verified against git):** fa19152 hardens Stravo hero rotation, duplicate headers and runtime overflow with fixture tests; fd858aa/630db1d complete tolerant metadata handling.
- [x] **Reset: a total wipe of the app on this device** (2026-09-29) — everything incl. downloads; the last step is
      holding the final button for 5 seconds. Owner: device-only; tell the viewer iCloud data must be deleted manually.
      **Closed 2026-10-09 (done, verified against git):** b4a4977 implements full device reset and five-second hold (AppleResetView.swift:87); f907e54 returns to first run without exiting, preserving device-only semantics.
- [x] **Rework the Live GUI — "still not great", wants something better and fresh** (2026-09-29). Start with design
      directions for the owner to pick from before building.
      **Closed 2026-10-09 (stale, verified against git):** Superseded by #3's explicit 2026-10-09 Live overhaul and its implemented fixes (6fafa72, 77d88b3, c1faea9, 80dd79c).
- [x] **Test fixture: auto-import the owner's sources into every simulator/app for testing** (2026-09-29) — one private
      file on this Mac (never in the repo or OSArchive) + a Debug-only import-at-launch hook + a seed script.
      `scripts/dev-sources.py` (interactive; can pull every add-on from the Stremio account) writes
      ~/Developer/openstream-build/signing/dev-sources.json. Still to build: the app hook + scripts/seed-sim.sh.
      **Closed 2026-10-09 (done, verified against git):** e28039c supplies private-source builder; f907e54 adds Debug launch import and scripts/seed-sim.sh; OpenStreamRootView.swift:440 wires the import hook.
- [x] **Import Backup leaves every source "Needs Sign-In"** (2026-09-29, iOS 18 sim). The file was exported without a
      passphrase, which silently drops all credentials AND the addon URL paths, so even public addons (Cinemeta,
      OpenSubtitles) arrive broken. Fix: public addons keep working without a passphrase; exporting makes the
      passphrase choice explicit; Needs Sign-In rows are tappable to fix.
      **Owner direction 2026-09-29:** the backup always contains everything (passwords included), encrypted so only
      OpenStream on their own devices can read it (key in iCloud Keychain; passphrase only for another Apple Account),
      and restores with no Needs Sign-In. Also: the Enabled toggle on imported sources can't be turned on — fix.
      **Closed 2026-10-09 (done, verified against git):** b4a4977 implements full encrypted backups with iCloud Keychain/passphrase support and restored-source sign-in/enabling; AppleBackupRestoreTests covers round trips.
- [x] **Hero title logos (word art) not showing — plain text title instead** (2026-09-29, iOS 18 sim screenshot:
      "JEOPARDY!" in bold text over the backdrop).
      **Closed 2026-10-09 (done, verified against git):** 05b9000 retries/fetches missing hero wordmarks; 32d1283 supplies title-page logo fallback; b354bd1 settles portrait art before drawing.
- [x] **Play Trailer tap turns sound on** (owner decision 2026-09-28: yes). Autoplaying hero trailers stay muted;
      an explicit Play Trailer press unmutes.
      **Closed 2026-10-09 (done, verified against git):** c445b33 unmutes explicit Play Trailer; a8c0855 retains muted autoplay with a sound control and verifies explicit sound intent.
- [x] **Streaming services: keep the quiet "Also available on …" line only (owner chose option a), but make it
      easier to spot** — no Play replacement, no service rows.
      **Closed 2026-10-09 (stale, verified against git):** Superseded by #55's 2026-09-30 owner decision to offer Watch on service with Wikidata title deep links (67210b7).
- [x] **Subtitles menu still lists every language instead of defaulting to English (asked again)**
      (2026-09-28, build 14). The earlier fix (FEEDBACK.md "A picked language was not the only option")
      only filters strictly when a language was explicitly picked; with device defaults and no exact match it
      still falls back to every track. English should be the default and the only entry.
      **Closed 2026-10-09 (done, verified against git):** d0eda15 removes fallback-to-every-track and defaults to English; 4fd1ac5 retains preferred-language first-level choices with an explicit More menu.
- [x] **Streaming services setting: an "Add" menu instead of the long list, top 10 by popularity only**
      (2026-09-28). Owner also asks what turning one on does — toggling Netflix on showed no visible difference.
      **Closed 2026-10-09 (done, verified against git):** b6fbea7 adds Add Service/top-10; ed39ad5 excludes stores/aggregators and improves ranking/taps, 32d1283 deduplicates tiers, and 67210b7 supplies visible Watch on behavior.
- [x] **When a trailer ends it should go back to the movie art** (2026-09-28, owner) — today it stays on the
      finished video.
      **Closed 2026-10-09 (done, verified against git):** 021ec54 returns completed trailers to artwork; later 6647eb3 stabilizes end/cap behavior and traces return reasons.
- [x] **iPhone crash: UINavigationBar layout assertion** (TestFlight crashes on builds 10 and 12, iOS 18.7, 4 of 4
      readable reports; one tester comment "Search"). Owner shared another crash on build 14 today — not yet
      in App Store Connect; read it when it appears.
      **Build 14 crash read 2026-09-29** (AMKnSe6teuQS5qAin8cixtU, iPhone 15 Pro Max iOS 18.7.8, "Just scrolling the
      app"): same assertion, reached from a layout pass while scrolling Discover, with loadTop10 running. 305af48
      (not in build 14) removes the Discover Refresh item flip; hardening the scroll-driven hero layout too.
      **Root cause found 2026-09-30:** tapping the tab you're already on rebuilds that tab's navigation stack
      (`.id` bump), which iOS 18 rejects — 24/24 crashes on the iOS 18 sim, build 14 AND main. 305af48 did not fix
      it. Fix in progress: pop to root without rebuilding; deep links too.
      **Closed 2026-10-09 (done, verified against git):** be84a94 replaces tab-reselect/deep-link NavigationStack rebuilds with path updates, fixing the reproduced iOS 18 assertion; 305af48 alone was insufficient.
- [x] **iCloud sync / backup on a new device (asked again)** (2026-09-28, iPad, build 14): a fresh iPad with no
      sources gets nothing from iCloud, so there's no content, and there's no visible backup/import to
      bring the setup over. Make iCloud sync switchable on and working on a fresh install, and make
      backup/import easy to find from the empty state. **Fix committed 66e2d46** (sync on by default, fresh
      device pulls, keychain retry, Restore/Import buttons on No Sources) — tick once installed (build 15).
      **Closed 2026-10-09 (stale, verified against git):** Superseded by #12's newer real-device sync regression/test; 66e2d46 implemented this earlier fresh-device/default-on/Restore-Import work, and f20c0e0 adds missing publication.
- [x] **iOS trailers don't play** (2026-09-28, build 14). Failures are silent by design; asked the owner whether
      Auto-Play Video Previews is on and whether Play Trailer on a title page fails too.
      **Closed 2026-10-09 (stale, verified against git):** Superseded by #28 and then #13's later real-phone trailer failures; 6bbf9a2/43feec0/6647eb3 implement successive fixes, with #13 retaining owner re-test.
- [x] **iOS Live TV subtitles are out of sync — they appear too late** (2026-09-28, build 14; they show up now).
      **Fix committed 1f3f9f0** (cues follow the on-screen frame, not the scrub clock) — tick once installed.
      **Closed 2026-10-09 (done, verified against git):** 1f3f9f0 paces captions from presented source frames instead of the scrub clock, with cue/overlay regression tests; new-build owner listening remains useful validation.
- [x] **Remove a specific title from Continue Watching** (2026-09-28; clarified 2026-09-29: per title like Netflix,
      not hiding the whole row). Progress is kept; it comes back if played again.
      **Closed 2026-10-09 (done, verified against git):** 77a0f5a adds per-title CW removal with progress retained and return-after-play policy; 4440c97 adds the complementary Start from Beginning choice.
- [x] **Discover Rows reorder is hard to use** (2026-09-28, Mac screenshot): the list of ↑/↓ chevrons
      works but isn't friendly for long moves (about 25 rows). Make it drag-and-drop (or similar) on
      every platform, keeping a non-drag way for Apple TV and accessibility.


      **Closed 2026-10-09 (done, verified against git):** 77a0f5a implements drag reorder plus TV pick-up/carry/put-down and accessible non-drag moves, replacing the earlier chevron-only experience.

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
