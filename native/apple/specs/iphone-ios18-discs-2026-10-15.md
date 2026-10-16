# iPhone on iOS 18: discs don't play + "a ton of issues" (owner 2026-10-15 22:50)

Owner, iPhone 15 Pro Max (UDID 00008130-000610103443001C, iOS 18.x), dev build dd8d32d (Release, add-ons): "the iOS 18
build on my iPhone is worse ... there is a ton of issues also disks don't play at all". Trace on the mini:
`/Volumes/DevExt/dev/openstream-build/traces/owner-iphone-1015.log` (session from line 4632, 2026-10-16T03:46Z).

## Discs (Blu-ray / UHD ISOs over the network share)
- The Last Airbender (2010).iso ×2, John Wick 4 UHD ISO ×1: `disc start menu` → UDF/BDMV parse takes 12–14 s →
  `[AetherEngine] load superseded (gen 2 -> 3); unwinding` (66298 ms, 70233 ms) → never a first frame, no error shown
  ("3 tried, 0 played, 0 failed"). The title page trailer keeps playing/reveals underneath (28473 ms).
- Expected fix: tv-disc-shelf (Blu-ray → main feature, no menu round trip) removes the second load. PROVE it on
  DevPlus (owner backup restored there) and on the owner's iPhone build with these ISOs; if anything still supersedes,
  find who issues gen 3 and fix it.
- Add: an immediate player/loading state on Play while the disc is read (no silent 14 s); stop the title trailer on
  Play; a real error if a disc can't open; check the selected title is the main feature (Airbender picked clip 00125).
- Speed: cache the parsed disc structure per file (size+mtime) so the second open is instant; look at why the parse
  over SMB loopback takes 12–14 s on iPhone vs ~9.7 s on Apple TV.

## iOS 18 regressions
- Home hero layout jumps during the first seconds (`discover phone hero layout` top inset 149→97 over ~20 frames at
  3751–4114 ms): settle the safe-area/nav-bar inset once (iOS 18 nav bar), no visible jump.
- Walk the app on the iOS 18.6 sim `7530ECB2…` (owner's imported setup) and the owner's phone traces: list every
  difference from iOS 27 (layout, nav bar, sheets, search, player controls). Owner notes/recordings get added here.
Gates: code-anti-slop; serial swift; iOS 18.6 + iOS 27 sims; E2E-iOS (both OS versions); DevPlus + owner iPhone.

## Add Media Server: Rill fails with "The server's reply made no sense." (owner screenshot 23:05)
Jellyfin, name Rill, address `stream.ourzephyr.com` (no scheme), user root. Cause (verified with curl):
`AppleAddMediaServerView.swift:28` prepends `http://`; Cloudflare answers 301 → https; URLSession follows a 301 on a
POST as a GET without the body, so `Users/AuthenticateByName` never authenticates and `decodeSession` throws
`.malformedResponse`. https works (System/Info/Public 200; wrong password → 401 JSON). Fix:
1. No scheme → try `https://` first; fall back to `http://` only when https fails to connect (LAN servers, IPs).
2. Adopt the final URL after redirects from `publicInfo` (response.url) as the base for every later call; never POST
   to an http URL that redirects.
3. `malformedResponse` writes the request path, HTTP status and content type to the trace (no tokens, no body).
Tests: scheme choice, redirect adoption (URLProtocol stub), error trace line. Check against Rill on the owner's iPhone.
