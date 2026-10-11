# REA deep dives: four reference-app topics (owner 2026-10-11)

The owner asked to focus REA on: **Paramount+ live functions, Netflix GUI, Plex backend + features, Infuse engine +
source setup for local sources.** Read native/apple/AGENTS.md (all of it; §3, §4.2 and §7 matter most) and load the
`reverse-engineer-anything` skill. The first run's report, design/reference-apps/2026-10-11-skip-intro-next-episode.md,
shows the expected quality: evidence locations, "not found" said plainly, no guessing, no copied code.

Two workers split this: **worker A** does topics 1 and 2 (Android), **worker B** does topics 3 and 4 (Mac). Do only
your two. One report per topic, written to the path given. Time-box each topic to about 90 minutes.

## Topic 1 (A): Paramount+ live functions
Target: /Volumes/DevExt/dev/rea/targets/apk/paramount/com.cbs.ott.apk (Android TV, 17.1.1).
OpenStream context: Live uses Paramount+ as its design reference (video pinned at the top edge to edge, channel list
with logos and what's on now under it, guide secondary, search as an icon); we have IPTV (M3U/Xtream) channels, an EPG
guide, Start Over, a live buffer and favorite channels.
Answer, with evidence: how the live screen is structured (player + channel list + guide: states, focus moves, what the
remote buttons do); channel switching (up/down, number entry, last channel, preview-on-focus vs tune-on-select, how
fast it tunes, what shows while tuning); the guide (time window, how far ahead/back, paging, now/next, program
details); Start Over / restart / pause / rewind live (DVR window, how the "live" edge is shown, jump-to-live); the
mini-guide/overlay while watching; local-affiliate/location logic; favorites/recents; how live ads or blackouts are
signalled to the UI; error/retry behaviour when a channel fails.
Report: design/reference-apps/2026-10-11-paramount-live.md

## Topic 2 (A): Netflix GUI
Targets: /Volumes/DevExt/dev/rea/targets/apk/netflix-mobile/ (phone app; base `com.netflix.mediaclient.apk` plus
`config.xxhdpi.apk` and `config.en.apk` splits; signers checked: Netflix + Google Play stamp) and
apk/com.netflix.ninja.apk (TV; its UI is mostly inside libnetflix.so — say so and move on if nothing is reachable).
OpenStream context: Home/Discover uses Netflix as its reference (billboard hero, dense poster rows, titles under
posters, Continue Watching with progress on the artwork, Top 10 numerals); iPhone is portrait.
Answer, with evidence (layouts, dimens, styles and the classes that drive them; `decode_android_resources` works now):
home structure (billboard/hero, row types, row order, lazy loading, how many items per row, card sizes and spacing in
dp, title placement); Top 10 row (numeral treatment); Continue Watching (progress bar, the ⋯ menu actions,
remove-from-row); title detail page (sections, episode list, season picker, buttons and their order); "My Netflix" /
profile and downloads entry points; navigation (tab bar items, what each holds); motion (hero autoplay/preview,
card expand, transitions, durations); empty/loading/error states (skeletons/placeholders).
Report: design/reference-apps/2026-10-11-netflix-gui.md

## Topic 3 (B): Plex backend and features
Targets: /Volumes/DevExt/dev/rea/targets/Plex Media Server.app (1.43.4; executables in Contents/MacOS: Plex Media
Server, Plex Media Scanner, Plex Media Fingerprinter, Plex Commercial Skipper, Plex Transcoder, Plex Tuner Service,
Plex DLNA Server, Plex Relay, Plex Script Host) and the client web bundle in Plex.app/Contents/Resources/web-client
(for the API as clients use it). Use `lipo -thin arm64` copies in /tmp for Ghidra; prefer strings/symbols first.
OpenStream context: we index sources (Jellyfin/Plex/Emby servers, SMB shares, IPTV) into a local media index with TMDB
metadata, show Continue Watching / Up Next, and may add markers (chapter markers approved; intro fingerprinting
tabled).
Answer, with evidence: library scanning (how a folder becomes items: filename/folder parsing rules, TV season/episode
patterns, multi-part, extras, what triggers a rescan); metadata matching (agents, match confidence, fallbacks);
On Deck / Continue Watching and Up Next rules (thresholds for "watched", when an item enters/leaves); hubs (what
home rows exist, how ordered); intro/credits/commercial detection (what the Fingerprinter and Commercial Skipper do,
inputs, outputs, when they run); transcode decision (direct play vs direct stream vs transcode: what the client sends,
what decides it); play queues; Live TV & DVR via the Tuner Service (EPG source, recording rules) at a high level;
the main API endpoints a client uses for each feature.
Report: design/reference-apps/2026-10-11-plex-backend.md

**Owner clarification (2026-10-11):** "Plex backend in the sense that they are the longest in the game, so what can we
learn from them as far as how our app works." The Plex report is the input to a follow-up step (Topic 3b, run after
worker B): hold each Plex finding against OpenStream's actual code and say where we are weaker and what to change.

## Topic 3b (follow-up, after worker B): Plex lessons for OpenStream
Inputs: design/reference-apps/2026-10-11-plex-backend.md plus OpenStream's code in native/apple/Sources/OpenStreamApple
(media index, source store, catalog, continue-watching resolver, playback/engine selection, SMB range server, metadata,
live/EPG). For each area (library model + scanning, filename parsing, metadata matching, watched/progress state and
Continue Watching/Up Next, home rows, markers, playback decision (direct play vs remux vs transcode), play queues,
offline/unreachable sources, sync/backup of state, Live TV/EPG): what Plex does, what OpenStream does today (with
path:line), the gap, and a ranked change list (impact, effort S/M/L, risk). Read-only; no code changes.
Report: design/reference-apps/2026-10-11-plex-lessons-for-openstream.md

## Topic 4 (B): Infuse engine and local-source setup
Targets: /Volumes/DevExt/dev/rea/targets/Infuse.app (8.5.6) and Infuse-arm64 (use this for Ghidra; native string
searches on the full binary hit the 600 s limit last time, so start with Contents/Frameworks, Localizable.strings,
plists, symbol names and `nm`/`otool -L`).
OpenStream context: our engine is AetherEngine (FFmpeg-based); local sources are SMB shares (we run a local range
server for playback), plus servers found on the local network.
Answer, with evidence: engine (bundled frameworks/libraries and versions, decoders, Dolby Vision / HDR10+ handling,
tone mapping, audio passthrough/Atmos, subtitle rendering incl. PGS/ASS, frame-rate and dynamic-range matching); local
source setup (share types offered: SMB/NFS/WebDAV/FTP/UPnP/Plex/Emby/Jellyfin…, how shares are discovered — Bonjour/
NetBIOS/WS-Discovery —, the add-share flow and fields, credentials storage, SMB versions/options, how a share is
browsed vs added to the library, folder-to-library scanning and filename parsing, metadata source, refresh/rescan
triggers, offline/unreachable handling, cloud services list).
Report: design/reference-apps/2026-10-11-infuse-engine-sources.md

## Every report
- Comparison/summary first, then findings with evidence locations, then "Not found", then "What OpenStream should do"
  (5–12 concrete bullets tied to our context above), then "How this was done" (tools that worked, dead ends).
- Learn behaviour; never copy their code, strings, art or assets into OpenStream. No DRM/sign-in bypass. Never run or
  install the APKs or the Plex server. Never upload anything. No builds, sims or emulators.
- Write only your two report files. Do not commit or `git add`. Scratch in /tmp on the mini.
- Ghidra is heavy: check `ssh dev-mini 'cat ~/Developer/.build.lock/owner'` before opening a native binary; if a build
  holds the lock, work on string/resource evidence meanwhile. Close native sessions when done.
- If a REA tool fails for setup reasons, report the exact error and continue with what works; do not install software.
- Final message: AGENTS.md §7 report format.
