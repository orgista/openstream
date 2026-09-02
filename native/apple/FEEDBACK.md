# OpenStream Apple — feedback tracker

Source: owner walkthrough videos (2026-09-01) + code audit. Three videos:
V1 = OpenStream iPhone walkthrough (+ TiviMax Live-TV reference at the end),
V2 = reference apps (Ruddarr / Apple TV / Netflix) for design direction,
V3 = Infuse SMB reference + OpenStream SMB. Full transcripts drove this list.

Status key: ✅ fixed this pass · 🔎 diagnosed, needs larger work · 📋 roadmap.

## Fixed this pass (code, verified building)

- ✅ **Wordmark font looked odd** (V1). Was `.rounded` heavy + lowercase
  "openStream"; now bold straight sans "OpenStream" matching the Android
  launch, TV banner, and store assets. `Apps/Shared/OpenStreamApps.swift`.
- ✅ **Detail page "went sideways", couldn't recover** (V1: Man of Steel).
  The detail view set BOTH a large `.navigationTitle` and an in-body
  largeTitle, so the name rendered twice and the nav copy bled over the hero
  art. Nav title is now inline. `AppleDiscoverView.swift`.
- ✅ **Web portal "cross-origin request rejected"** (V1 — blocked the whole
  web-add flow). The origin check rejected the mDNS `openstream.local` host
  the app advertises and required an exact port match, tripping privacy
  browsers. It now accepts session IP / `*.local` / loopback / any private
  LAN host and drops the strict port match; the one-use 128-bit session
  token remains the real authenticator on every POST. `AppleWebManagementProtocol.swift`.
- ✅ **Add Source example URL** (V1). Placeholder is Stremio-flavored
  `https://example.io/manifest.json` (nod to `.strem.io`), gray, no
  explainer text. `AppleSourcesSettingsView.swift`.
- ✅ **"Anything but OpenStream being blue, remove it"** (V1). Accent is now
  white (brand is monochrome). Added `AppleBrandPrimaryButtonStyle` (white
  fill, black label) for Play / Open Settings / Add Source so prominent
  buttons are readable — this also fixes the **white-on-white "Open Settings"**
  the owner saw on the Live tab (V3). `AppleBrandButtonStyle.swift` + call sites.
- ✅ **Add-on icons showed puzzle pieces** (V1, V3). The manifest logo was
  parsed and rendered, but the sanitizer dropped any non-HTTPS logo; ATS
  already allows arbitrary loads, so http logos now render too. Add-ons that
  ship no logo still fall back to a per-type glyph (unavoidable). `AppleSourceStore.swift`.
- ✅ **IPTV User-Agent/Referer dropped before playback** (audit finding —
  matters for the TiviMax-style Live TV the owner wants). Playlist
  `#EXTVLCOPT` headers now thread channel → prepared playback → player
  session → `AVURLAsset`, so header-gated IPTV origins stop returning 403.
  `AppleIPTV.swift`, `ApplePlaybackPreparer.swift`, `ApplePlayerSession.swift`,
  `ApplePlayerControllers.swift`, `AppleStremioPlaybackView.swift`, `AppleMediaSourceViews.swift`.

## Already fixed by codex before the video (verified in current code)

- Add Source placeholder was already gray; Radarr/Sonarr "Test Connection"
  is already a real `Button` (V1 asked for both — the video was an older build).

## Diagnosed, needs larger work

- 🔎 **"No streams available" for everything** (V1, V3 — the #1 complaint).
  Endpoint construction is correct (`transportURL` strips `/manifest.json`;
  `/stream/{type}/{id}.json` is well-formed). Root cause is Stremio id
  semantics: catalog items from the RT / Streaming-Catalogs add-ons carry
  non-IMDB ids, and Torrentio only resolves `tt…` IMDB ids. Stremio itself
  bridges this by fetching the item's META first and querying stream add-ons
  with the id(s) from that meta. OpenStream queries streams with the raw
  catalog id for movies, so non-IMDB items return empty.
  **Fix:** before querying stream add-ons, resolve the catalog item through a
  meta add-on (Cinemeta) to obtain its IMDB id (and, for series, the episode
  video ids — already handled). Needs a real add-on set to verify; can't be
  reproduced on a clean simulator without the owner's private Torrentio
  manifest. Highest-priority follow-up.

## Roadmap (design direction from V2/V3 — larger features)

- 📋 **SMB like Infuse** (V3): native "Add SMB" that auto-detects available
  shares (Infuse lists M2 Pro / ServerPlus / UNAS), not just the iOS Files
  picker. Current "Add Files or SMB Folder" (security-scoped Files bookmark)
  works but the owner wants native browse.
- 📋 **Bigger title cards + Apple-TV/Netflix-style home** (V2, emphasized):
  hero with a playing preview clip + dot pager, "For You" driven by the
  open-source GitHub algorithms, New Releases / Top 10 / Continue Watching,
  larger poster cards (current phone cards are too small).
- 📋 **Settings "Add Instance → choose type"** model (V2, Ruddarr-style):
  Radarr / Sonarr / IPTV / Stremio as instance types; translucent top/bottom
  bars; clear-cache / reset / spotlight / leave-a-review actions.
- 📋 **Content detail** (V2): trailer/clip at top (via YouTube), seasons
  selector, Download button with fast download-status reporting (tie to SMB),
  thumbs-up rating that feeds the recommendation algorithm.
- 📋 **Library empty despite Radarr/Sonarr** (V1): populate the Library tab
  from connected ARR instances.
- 📋 **Search + AI/Siri search** (V2): improve search; investigate an
  Apple-Intelligence / Siri-kit powered search path.
- 📋 **Metadata cache server** (V1): an OpenStream mini-server (Cloudflare)
  caching TMDB/OMDb so clients get baseline metadata without per-user keys.
- 📋 **Subtle in-app OpenStream mark** (V3): a small mark in a top corner of
  the browse screens (the app shows it in the launch + tab bar only).
- 📋 **Gateway clarity** (V1: "what is gateway?"): label/describe the
  transcode gateway in Settings.
- 📋 **Sign-in later** (V2): accounts deferred; watch-history sync via
  CloudKit private DB when it lands (see HANDOFF.md).

## Needs owner input

- OMDb API key to test metadata (it's in the macOS Keychain, service
  "OpenStream Deployment", account `omdb-api` — enter it in Settings →
  Metadata).
