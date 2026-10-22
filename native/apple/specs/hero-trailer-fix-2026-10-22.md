# Discover hero gone; no trailers anywhere (owner, iPhone, build 9c25ff9, 2026-10-22 ~12:00)

Owner, verbatim: "discover main hero is just complete gone, its only in library, and library plays no trailers at all".
His phone (iOS 18) runs main 9c25ff9: add-on sources were deleted by the no-add-ons migration; he keeps media servers
(Jellyfin incl. his Rill server, possibly Plex/Emby), an SMB share, Live TV. Likely causes to CHECK, not assume:
- Discover hero picks depended on add-on catalogs / the removed catalog rails or metahub/cinemeta; with only media
  servers + TMDB the hero list is empty → hero hidden. Discover must build its hero from the user's own media servers
  (recently added / continue watching / server items with art) and TMDB trending when a key is set — like Library does.
- Trailers: the YouTube embed origin/baseURL changed to https://orgista.com and the frame scripts/CSS were removed in
  the compliance pass (AppleYouTubePreviewHTML.swift, AppleMetadataClient.swift ~247, AppleDiscoverView ~8772). YouTube's
  IFrame API rejects players whose origin/referrer doesn't match the page (error 152/153) → check the WKWebView baseURL /
  origin / Referer combination against YouTube's documented requirements and fix it the official way (no injection into
  YouTube's frame, no stream extraction). Also check server-hosted trailers (Jellyfin/Plex local trailers) still play.
Reproduce on the iOS 18.6 owner sim (7530ECB2, ONLY via /Volumes/DevExt/dev/openstream-build/batch-1018a/protected.py —
it mirrors his setup) and the fixture Jellyfin; read the app trace (`OPENSTREAM_TRACE`) for the hero selection and the
YouTube player events. Fix both with tests (hero non-empty for a media-server-only setup; trailer player reaches
"playing" — UI test on the sim). Then DevPlus: a title page trailer plays on hardware.
Rules: Dev-Mini only (`scripts/mini.sh`, OPENSTREAM_MINI_DEST='~/Developer/openstream-build/lanes/hero-trailer-fix'),
own sim DerivedData `~/Developer/sim-dd-hero-trailer`, FIFO locks (others share the mini — queue, never kill), owner-data
sims only via protected.py, never Anthony/OfficePlus, keep the internal disk > 15 GB, no commits. Load
app-store-review-hardening (no add-on code may come back; YouTube via the official IFrame API only), swiftui-pro,
swift-testing-pro. Gates: serial swift test; check-appstore-compliance.sh --build; iOS 18.6 Discover crawl + smoke +
the new trailer test; tvOS smoke; code-anti-slop; zero-byte. Report per AGENTS.md §7 with the cause (file:line).

## Round 2 (lead, 15:30): API review — fix first. Your round-1 work is uncommitted here. Bounded ~90 min.
Leave OWNER-TODO.md to the lead (I will drop the Reddit handle line myself).
1. `grep -rn "orgista.com" Sources/` must be empty for the YouTube path; every loadHTMLString for the trailer passes the
   same baseURL as `embedOrigin`; AppleYouTubePreviewHTML emits the matching origin + referrer policy. Cite YouTube's doc
   for the origin/referrer format in a one-line comment.
2. Derive the app identity from `Bundle.main.bundleIdentifier` (fallback to the constant) so tvOS/macOS/visionOS/
   extensions are right; keep `swift test` stable.
3. Prove the hero cause: run your server-only hero test against 9c25ff9's code (reason from the diff or a scratch copy,
   not by moving files in this tree) — it must fail there; if it doesn't, write the test that does, and state the cause
   with file:line.
4. Keep `top10ListsEnabled` as the gate for the TMDB trending fetch (rows AND hero) — the owner's toggle must stop the
   network call.
5. Trending-only heroes only when at least one source exists (no non-owned titles on a fresh install).
6. Cache scope/fingerprint includes the metadata-key state (no trending hero restored after the key is removed).
7. Dedupe trending vs owned items by normalized title+year when no IMDb/TMDB id (test).
8. Drop the unrequested ratings→disliked seeding unless it is required for the fix (justify if kept).
9. Accessibility: move the playback-state marker off `VideoPlayer` onto a zero-size overlay; non-localized identifier.
10. Tests: note in the report that testMediaServerHeroTrailerReachesPlaying needs network; confirm serve.py's trailer
    fixture + `__main__` guard; device smoke must not pass -OpenStreamResetOnLaunch after adding the demo server.
Same gates as round 1 (serial swift test; compliance --build; iOS 18.6 via protected.py; tvOS smoke; DevPlus trailer).

## Round 3 (lead, 16:55): API review — fix first. Bounded ~60 min. Work is uncommitted here.
Full review: /private/tmp/claude-501/-Volumes-Files-Projects/openstream-lead/api-hero2.txt (read it).
1. Revert OWNER-TODO.md (lead owns it).
2. Name the regression test that fails on 9c25ff9 and passes now in the report (file:line); state the cause with file:line.
   If the serverOnly test passes on 9c25ff9, say so — keep it only as a control.
3. Dedupe across id spaces: owned imdb/jellyfin item vs trending tmdb item of the same title+year → one entry (owned wins).
   Also dedupe an item that is in both a server shelf and localItems. Tests for both.
4. Main-thread cost: build a [UUID: AppleSource] dict once, cap Library candidates (e.g. 40), and make sure
   contentRevision does not tick per scanned file (if it does, debounce the recompute). Note results.
5. YouTube identity from an extension: use the host app bundle id (strip known extension suffixes) — test.
6. Answer every item in review §6, §8, §10 with a one-line evidence note in the report (grep/test output).
7. The zero-size marker: hide it from VoiceOver except as the test hook (accessibilityHidden is not allowed if XCUITest
   then can't find it — pick what works on iOS 18 + tvOS and say which).
8. Restore the deleted "Run-script asserts…" comment and the EOF newline.
Gates as before (serial swift test; compliance --build; protected iOS + tvOS UI tests; DevPlus trailer).
