# Apple TV: Blu-ray titles, no fake disc menu, full-screen Top Shelf (owner 2026-10-15, OfficePlus)

Owner on OfficePlus (dev build dd8d32d): "I tried to watch matilda and it plays it detects its a disc but no menu ...
under titles it says titles and it lists like an infinite amount of titles and in the tv shelf lets look at apple tv
its full screen and no progress bars so we can remove progress bar ... can we do full screen art work and do the same
'swipe up for full screen?'". Trace (`/Volumes/DevExt/dev/openstream-build/traces/officeplus-1015.log` on the mini):
`Matilda.1996.COMPLETE.UHD.BLURAY-B0MBARDiERS.iso` → "title page disc: menu" → "disc start menu → main title (engine
menu pending)" → engine "Blu-ray recognized: 28 title(s), selected 0 clips=[00001]"; playback was fine.

Where: branch `tv-disc-shelf`, worktree `Apps/OpenStream-lanes/tv-disc-shelf`; mini commands via
`OPENSTREAM_MINI_DEST='~/Developer/openstream-build/src-tv-disc-shelf/native/apple' scripts/mini.sh`. Shared build
lock; wait for it. Read native/apple/AGENTS.md first; name the skills you use. No commits. Another branch (Stage B, in
main) also edits AppleLocalFileInspection.swift: keep changes there minimal.

## 1. Blu-ray: no menu promise
DVD menus (IFO/VM) stay. Blu-ray/UHD (BDMV, HDMV/BD-J) menus are not supported (BD-J needs Java; Infuse doesn't do them
either). For a Blu-ray ISO/BDMV: no "Disc Menu"/"Play Disc → menu" wording; Play goes straight to the main feature;
the trace says why. Apply on every platform. Test: Blu-ray fixture/metadata → no menu actions, main title chosen.

## 2. Titles list like Infuse
Build the list from engine titles: main feature first (longest, or the playlist the disc marks as first-play feature),
merge duplicates (same clip sequence / same duration ±2 s and same chapter count; obfuscation playlists), hide titles
under 2 minutes behind a "More" row or drop them, show duration + chapters, cap the visible list. Make the list
finite and focus-friendly on tvOS. Unit tests with a 28-title fixture shaped like the trace (and a 300-playlist
obfuscated disc). Check with the owner's UHD ISOs on OfficePlus if the device is awake.

## 3. Top Shelf: full-screen carousel like the Apple TV app
`Apps/OpenStreamTopShelf/TopShelfProvider.swift` returns `TVTopShelfSectionedContent` with `playbackProgress`.
Switch to `TVTopShelfCarouselContent` (style `.details` or `.actions`, pick what the Apple TV app looks like) with
full-screen 1920×1080 backdrop art (textless backdrops OK per owner 2026-09-22; title/wordmark + genre/year/summary
in the item fields), Play and More Info actions deep-linking like today, NO progress bars. Content: Continue Watching
first then Top Picks (same snapshot). Preview video: only if a direct trailer file URL exists (Plex/Jellyfin local
trailers); YouTube trailers can't play there; skip if none. Keep the 513-safe Caches write path (35c1522). Tests: the
snapshot → carousel item mapping; E2E-tvOS Top Shelf test updated. Verify on OfficePlus (and DevTV) by installing a
dev build and checking the shelf; screenshot it.

## Gates
Serial Swift suite; tvOS + iOS builds with recompile greps; E2E-tvOS Top Shelf + disc tests; the four Release (no
add-ons) builds if near `OPENSTREAM_ADDONS`. Report per AGENTS.md §7 with screenshots of the shelf and the titles list.
