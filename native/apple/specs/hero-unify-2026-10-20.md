# Landing-page hero = title-page hero, and a faster landing page (owner 2026-10-20 on the RC build)

Owner: "hero is wrong, front loading page a little bit slow, maybe we aren't caching enough" and "hero on the
landing pages should be the same as the hero in the content pages." Branch `hero-unify` from main a2ea95d.
Landing pages = Discover (and Library's hero if it has one) on iPhone; content page = the title page (whose new
chrome — art under the status bar, top gradient, circular Back, centred title treatment — the owner accepted).

## 1. Same hero
Screenshot Discover's hero and the title page of the SAME title on the iOS 18.6 owner sim (7530ECB2…, owner data,
inside `python3 /Volumes/DevExt/dev/openstream-build/batch-1018a/protected.py <sim> <cmd…>`,
`-OpenStreamMuteAudio YES`) and list every difference: art source (poster vs backdrop vs TMDB), crop/framing
(AppleHeroPortraitArt rules from 3ee266d), height, gradient/scrim, title treatment (logo vs text, size, position),
metadata line, buttons, trailer behaviour. Then make the landing-page hero render the same component/rules as the
title-page hero for art, framing, scrim and title treatment (share the code; don't copy it), keeping only what a
landing hero needs on top (page dots, auto-advance, Play/My List). Phone only; tvOS/Mac/visionOS unchanged.
Proof: side-by-side screenshots for 3 titles (Spider-Man: Homecoming, Matilda, a show) — landing vs title page.

## 2. Faster landing page
Trace a cold and a warm launch on the owner sim (the app's own trace lines: launch marks, `hero portrait …`,
image decode times, `discover recommendations …ms`) and on DevPlus if it is connected; report time to first hero
art and to the first full screen of rows, cold and warm. Find what is not cached that should be (hero art / TMDB
answers / posters / Top 10 / metadata), using the existing caches (AppleRemoteImageCache, metadata disk cache,
hero portrait memory) before adding anything. Fix the biggest one or two; proof = the same trace before/after with
numbers. If DevPlus is connected, the numbers on it win.

Gates: serial swift test (compile lane), iOS build, the Discover/title-page UI tests on 18.6 (testCrawlDiscover,
AppleiOSStubSmokeUITests, testB8DiscoverJank: hero drawn ≤ 2), code-anti-slop, zero-byte. Dev-Mini only
(scripts/mini.sh, `OPENSTREAM_MINI_DEST='~/Developer/openstream-build/lanes/hero-unify'`), FIFO locks (another
lane is walking the owner's recording on the same sim — queue, never kill), never OfficePlus, mini > 12 GB free,
no commits. Report: the difference list, the change (file:line), screenshots, the before/after timings, gates.

## 3. (owner 2026-10-20 09:45, add to this job) No bar over the landing-page heroes
Owner: "Discover and Library are cut off by the bar at the top that says Discover and Library; those used to not be
there." The ck-visual change (1575018, rows 10/11) put the iOS 18 Discover bar on the system material; Library
kept an opaque bar. Make Discover and Library match the title page the owner accepted: the hero art runs under
the status bar with the short top gradient, NO bar and no large "Discover"/"Library" title over it at rest; the
toolbar controls (search, refresh) sit as round controls over the art like the title page's Back; a compact bar
with the page name fades in only once the hero has scrolled away (reuse ApplePhoneTitlePageChrome's mechanism —
opacity, identifier withheld while hidden; NOT a conditional insert, that looped layout in 1018g). Phone only.
Proof: Discover + Library at rest and scrolled on iOS 18.6 and iOS 27; testB8DiscoverJank (hero drawn ≤ 2).

## Lead 2026-10-20 09:55 — DevPlus is connected by cable now
`xcrun devicectl list devices` shows DevPlus (00008140-000809A82E89801C) connected, transport wired. The Apple TV
app is installed on it; the owner is installing Paramount+ (and possibly Netflix) on it now. Use it: device
screenshots (`xcrun devicectl device …` / the `mobile` MCP) of the reference app screens, and for hero-unify the
launch/landing timings on DevPlus (they win over the simulator). Install our app on DevPlus only with the
Release + add-ons owner build path or a Debug build for your lane — never touch the owner's own iPhone ("Anthony").
Check `xcrun devicectl device info apps --device 00008140-000809A82E89801C --include-all-apps | grep -i paramount`
before relying on Paramount+.

## Lead 2026-10-20 10:00 — new reference skill available
Load the `openstream-reference-patterns` skill (~/.claude/skills/openstream-reference-patterns, linked into the
Codex and work-Claude skill homes): pinned Apple Destination Video, Swiftfin, VLC iOS, Kodi, Nuke, Kingfisher with
file/line pointers on dev-mini:/Volumes/DevExt/dev/rea/targets/oss/. Relevant here: hero-apple / hero-swiftfin /
top-bars (hero-unify), live-swiftfin + pvr-kodi — Swiftfin keeps the channel column and time ruler OUTSIDE the
grid's scroll, iPhone rows 74 pt (live-oss), playback-vlc / discs-kodi (video-1016), images-nuke / images-kingfisher
for the landing-page caching.

## Fable review (2026-10-20 18:00) — FIX FIRST: apply 1–8
1. **Hero art can flip three times per page** when TMDB has no textless backdrop. The upgrade's title-page backdrop falls back to TMDB's titled backdrop at `Sources/OpenStreamApple/AppleHeroArtworkUpgrade.swift:103`, so the stage goes catalog backdrop → TMDB titled backdrop → add-on backdrop once the resolver's details arrive and win at `Sources/OpenStreamApple/AppleHomePhonePortraitStage.swift:19`. That is two visible swaps and three decodes, and the memory at `AppleHomePhonePortraitStage.swift:93` keeps whichever landed last, so the next visit flips again. Store only the textless URL in `titlePage.backdropURL` and let `choose` fall through to the item's backdrop.
2. **The first-row peek rule is silently broken.** The hero is now 40 pt taller than its art (`Sources/OpenStreamApple/AppleHomePhoneHero.swift:81`), but the peek clamp in `artHeight` and `firstRowLead` still measure from the art bottom (`Sources/OpenStreamApple/AppleHomePhoneHeroLayout.swift:49`). Real peek above the tab bar: iPhone 16 Pro ≈77 pt, 16e ≈68 pt, SE ≈50 pt against the 90 pt rule. The `rowPeek` test helper also uses `artHeight`, so it cannot see this.
3. **A positional test was deleted, not updated.** `theButtonsAndDotsSitWhereTheAppleTVAppsDo` is removed from `Tests/OpenStreamAppleTests/AppleHomePhoneHeroTests.swift:271`, while the layout header at `AppleHomePhoneHeroLayout.swift:6` still claims buttons at 64 % and dots at 70 %. Either update the constants and the test or rewrite the comment.
4. **Crawl hittability loosened.** `classifyForCrawl` now routes through `isSafelyHittable`, which returns true for any `home.featured.*` element whose centre is on screen without asking XCTest (`Apps/OpenStreamiOSUITests/AppleiOSUITests.swift:5074`). With the navigation bar gone on phone, `guard bar.exists` at line 5086 also disables the under-the-bar check, and the new compact `.bar` overlay is not a navigation bar. A hero control under the chrome would be reported hittable.
5. **Every phone trailer cover now renders on the main actor.** `titlePageArt` is always set, so `render()` takes the `ImageRenderer` branch for plain backdrops too (`Sources/OpenStreamApple/AppleHomePhonePortraitStage.swift:127`). The off-main `draw` path that the 2026-10-14 review added is now dead on phone. Keep it for backdrops.
6. **The landing hero drops the prefetched wordmark.** The phone branch ignores the `wordmark` Discover resolved and cached, and waits for the identity-plus-details round trip before showing a title (`Sources/OpenStreamApple/AppleHomeBillboard.swift:390`). The task re-validates the PNG whenever `actionMetadataLoaded` flips. Seed `phoneLogoCandidates` with `wordmark` so a warm launch titles the hero immediately.
7. **No hero means no page name at all.** On a loading or empty Discover or Library the chrome shows only round controls, and the compact title can never appear because the threshold assumes a hero (`Sources/OpenStreamApple/ApplePhoneTitlePageChrome.swift:99`). Treat "no hero extent and no hero" as offscreen.
8. **Double load report.** When the placeholder is the same cached bucket, `ApplePhoneHeroArtwork` fires `onLoad` from `onAppear` and again from the task (`Sources/OpenStreamApple/ApplePhoneHeroArtwork.swift:27` and `:57`), so the stage remembers, reports ready and records the launch mark twice and the "hero portrait image decoded" trace double-counts. Harmless, but guard on identity.
Lead: all eight. 1) one art decision per page: pick the final source before showing (or only upgrade to a
strictly better asset once, never back down) — no visible flips; 2) the 90 pt first-row peek holds on 16e, 16 Pro
and SE (measure from the hero's bottom, not the art's), test it; 3) update the constants + the positional test to
what the layout now does (no deletions); 4) restore real hittability for the crawl except the three iOS hero
buttons mid-transition (as e2e27-discover2 11106f1 does), and make the under-the-bar check see the compact bar
overlay; 5) backdrops back on the off-main draw path; 6) seed the wordmark from Discover's cache; 7) no hero → the
compact page title shows; 8) guard onLoad by identity. Then: serial swift test, iOS build, Discover crawl + stub
smoke + testB8DiscoverJank on 18.6, chrome checks on 18.6 + 27, DevPlus hero timing cold/warm (3 samples each).
Move design/2026-10-20-hero-unify/ to OpenStream-lanes/evidence/hero-unify-2026-10-20/ when done. No commits.

## Fable second pass (2026-10-20 20:30) — FIX FIRST (items 1–8 confirmed); apply the new findings
1. **CONFIRMED, fix first.** `Sources/OpenStreamApple/ApplePhoneTitlePageChrome.swift:55` hides the navigation bar for landing pages, and when there is no hero the chrome paints an opaque 44 pt bar at rest, but no top inset is added to the scroll content. On a populated Discover or Library with no backdrop candidates (poster-only Xtream VOD, local files without art), the first shelf title sits 16 pt below the status bar and is covered by the bar, along with the top of its posters and the Library error label. Add a top content margin of 44 pt when `hasHero` is false.

2. **CONFIRMED, acceptable with caveat.** `Apps/Shared/OpenStreamApps.swift:47` selects `WindowGroup(_:content:)`, which the iOS 27 SDK marks deprecated from iOS 18, macOS 15, tvOS 18, watchOS 11 and visionOS 2 (the exact floors), renamed to `init(_:makeContent:)`. The content is now built eagerly on main during `App.body`, which is why the executor assertion stops. Launch cost is negligible (view values only, no bodies). Multi-window on iPad, visionOS and Mac is the pre-iOS-18 behaviour: per-window `@State` is still per instance. Scene restoration is unaffected. Costs: a deprecation warning on every platform, and the root cause stays, which is `platformRoot` reading the App's `@State` inside the scene builder. The proper fix is to keep the lazy builder and move `showLaunch`, the router and the launch readiness into a root view.

3. **PLAUSIBLE, verify.** `Sources/OpenStreamApple/ApplePhoneTitlePageChrome.swift:125` applies `onScrollGeometryChange` to the whole page rather than the ScrollView. If nested horizontal poster rows also report, their offset of zero flips `heroIsOffscreen` back to false, and the compact title and bar vanish while the user swipes a row below the hero. Check by scrolling past the hero and then swiping a row sideways; if it flickers, hoist the read into `AppleDiscoverHeroLayoutReader`, which already sits on the ScrollView.

4. **CONFIRMED, minor.** `Sources/OpenStreamApple/AppleHomePhonePortraitStage.swift:57` counts the cached poster placeholder as the first shown art. On a cold visit where the poster is cached (it usually is, from the shelves) and the backdrop is not, the catalog backdrop loads, `hasUpgradedArtwork` locks, and the textless backdrop is skipped until the next visit. Only set the lock when the previous `shown` came from a real load, not from the placeholder.

5. **CONFIRMED, minor.** `Sources/OpenStreamApple/AppleHomePhonePortraitStage.swift:25` puts the remembered backdrop in the `backdropURL` slot and drops `item.backgroundURL` from the candidates when memory has one. If the remembered textless URL fails on a later visit, the page falls to a poster card instead of the catalog backdrop. Keep `item.backgroundURL` as the next candidate.
Lead: 1 required (no-hero landing page: content gets the bar's top inset so the first shelf title is not under the
opaque bar); 2 use `init(_:makeContent:)` if it keeps the eager construction that fixed the iOS 27 crash, else keep
the deprecated overload with a one-line comment why; 3 verify with a capture (scroll past the hero, then swipe a
poster row) and scope `onScrollGeometryChange` to the vertical ScrollView if it flickers; 4 and 5 apply. Then the
same gates as before (serial swift test, iOS build, Discover crawl + stub smoke + testB8 on 18.6, chrome 18.6+27).
No commits.
