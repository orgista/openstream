# iPhone screen recording, owner, 2026-10-15 22:54–23:04 (old build dd8d32d, iOS 18, iPhone 15 Pro Max)

Recording: /Users/macstudio/Downloads/RPReplay_Final1792123442.mp4 (9 min); contact sheets (one frame / 4 s) were
reviewed by the lead. Several items were fixed in main 2f8604f since (discs open/play, Rill https). RE-CHECK EACH on
main first (iOS 18.6 sim with the owner setup + DevPlus), then fix what still happens. Never test on OfficePlus.

1. **Launch:** ~4 s of black screen with a faint spinner before Discover.
2. **Discover Top 10 rows have no artwork:** grey text-only cards ("UNABOMBER", "The Widower: 'Til Death Do Us
   Part", "A Different World", "East of Eden"…) on every visit. Find why Top 10 items get no poster/backdrop (match
   to TMDB/metadata, image URL policy) and fix; a text card only when no art exists anywhere.
3. **"Open Season 3" parsed as a TV show "Open":** file `Open.Season.3.2010.1080p.BluRay.DD+5.1.x264-playHD.mkv`
   appears under Library › Shows as two "Open" cards with no art, title page "OPEN · 2010", Episode list. The title
   parser treats "Season.3" as a season marker. Movie titles containing "Season N" + a year and no episode token must
   parse as movies (Open Season 3 (2010), similar: "Open Season 2", "Season of the Witch"). Tests.
4. **Live:** first open shows "No channels" plus an "IPTV · Importing · 0 channels · Zero KB · Cancel" toast that
   keeps coming back while channels are listed; Channel Manager shows "IPTV: Could not reach the IPTV panel. The
   request timed out."; several channels sit on "Reconnecting…" then "Can't reach IPTV". Separate provider timeouts
   (show once, plainly, retry quietly) from our own bugs (the 0-channel import toast repeating, empty list first).
5. **Blu-ray ISO title page still offered Play Disc / Skip to Movie** for `The Last Airbender (2010).iso` (27.8 GB,
   no BLURAY token in the name). Check main's AppleDiscImagePolicy on a network-share ISO whose size is known: it must
   resolve Blu-ray (size > 9 GB / engine read) before the title page draws its buttons.
6. **YouTube trailers show YouTube's own UI over the hero:** title bar ("The Last Airbender (2010) Trailer #1 ·
   Rotten Tomatoes Classic Trailers", "Marshals | Season 1 Official Trailer | CBS"), the YouTube logo, "More videos"
   strip, link icon. Hide every YouTube overlay we're allowed to (embed params, crop the frame so the overlays fall
   outside, show the video only after the overlay fades), staying within YouTube's embed terms.
7. **A capsule "oStream 540 ms" / "749 ms" appeared at the top of the screen** after returning from the full-screen
   trailer. Not found in our sources by a quick grep; find out whether it is ours (a debug/latency HUD in Release) or
   iOS's; remove it if ours.
8. (Closed: the recording predates the Rill move; owner 10-16: gallardo.dev only.)
Gates: code-anti-slop; serial swift; iOS 18.6 + iOS 27 sims; E2E-iOS on both; DevPlus check; screenshots before/after
for 2, 3, 4, 6. Report per AGENTS.md §7. No commits.

## From REA round 2 (design/reference-apps/2026-10-16-speed-and-metadata-rea.md), do with items 2, 3, 1
- Top 10 art: TMDB lookup by title + type, persist rank → TMDB id on disk; cache the weekly Top 10 file on disk
  (today a new client per Discover load re-downloads Netflix's all-weeks file; the 4 h memory cache never hits);
  memoize matches.
- Parser: "Season N" + year and no episode token in a FILE name = movie; in a FOLDER name it stays a season.
- Launch order: draw saved Discover rows before the media-index load and progress sync.
- Episode row jumps ~28 pt when a download starts on the title page (found by the iOS 18.6 job): fix the layout so the row keeps its place.
