# Live polish (owner, iPhone, build 9c25ff9, 2026-10-22 ~12:00)

Owner, verbatim: "subtitles in live says (unknown) for subtitle track; live video player icons are not the same size,
they are a bit jank in the live player; we need a better loading for live, like a pause to say loading channels or
something; faves bar is static but looks too big and not aligned with the other elements; I open live for the first
time and it takes a while to load the channels — I think there needs to be preload or something: once live is added it
starts fetching at minimum like 100 channels, cause it makes for an odd experience to have them loading like that."

1. Live subtitle track names: never "(unknown)". Name tracks from their language/label (CEA-608/708 → "English (CC)" /
   "CC1"…, DVB/WebVTT language codes → localized language names, fall back to "Subtitles 1/2"). Test the naming.
2. Live player controls (inline stage AND full screen): every icon the same size, weight and hit target (44 pt), evenly
   spaced and aligned on one baseline, like the Apple TV app's player. Measure frames in a UI test (equal sizes ±0.5 pt).
3. Loading: when Live opens and channels are not ready, show ONE calm loading state in the list area (system
   ProgressView + "Loading Channels" — this is a status label, not explainer text) instead of rows popping in; the stage
   shows nothing/black until a channel is chosen. One indicator only (tvOS/iOS).
4. Favorites/category strip: currently too tall and misaligned. Match the measured Paramount+ strip (iPhone: label
   baseline/insets aligned with the row text's leading edge and the stage edges; height from the P+ numbers used in
   live-fix; check the iPad/Duo stack too). Show before/after frames.
5. Prefetch: after a Live source is added and on every app launch (in the background, low priority, after first paint),
   load the playlist + the first ~100 channels' names/logos/now-next into the existing caches, so opening Live the
   first time shows rows immediately. Respect cellular/Low Data Mode and don't block launch. Measure: first Live open
   time-to-rows before/after on the 18.6 owner sim and DevPlus.
Rules: Dev-Mini only (`scripts/mini.sh`, OPENSTREAM_MINI_DEST='~/Developer/openstream-build/lanes/live-polish'), own sim
DerivedData `~/Developer/sim-dd-live-polish`, FIFO locks (others share the mini — queue, never kill), owner-data sims
(7530ECB2, 8939801C, 57B18C7A, 2E61439B) only via /Volumes/DevExt/dev/openstream-build/batch-1018a/protected.py, never
Anthony/OfficePlus, keep the internal disk > 15 GB, no commits. Another job (lineup-file) is editing the Live
lineup/guide grouping code — keep your changes to the player controls, strip, loading state, subtitle naming and the
prefetch, and avoid AppleChannelLineupPresets / lineup storage. Gates: serial swift test; iOS + tvOS Debug, iOS Release;
check-appstore-compliance.sh; iOS 18.6 Live UI tests via protected.py; code-anti-slop; zero-byte. Report per AGENTS.md §7.
