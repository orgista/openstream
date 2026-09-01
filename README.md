# OpenStream

**The single source of truth for this project.** OpenStream deliberately keeps one Markdown file: goals, policy, architecture, per-platform behavior, security posture, and verification all live here. The only other tracked document is [`POST_DEPLOYMENT_SOURCES.txt`](POST_DEPLOYMENT_SOURCES.txt), which is an operator checklist and is intentionally *not* Markdown because no runtime, build, or migration may ever read it as configuration.

---

## Contents

1. [What OpenStream is and why](#1-what-openstream-is-and-why)
2. [Ownership and branding](#2-ownership-and-branding)
3. [The non-negotiable source provisioning rule](#3-the-non-negotiable-source-provisioning-rule)
4. [Kids Mode and the guardian admin PIN](#4-kids-mode-and-the-guardian-admin-pin)
5. [Where content comes from](#5-where-content-comes-from)
6. [Metadata and credentials](#6-metadata-and-credentials)
7. [Playback](#7-playback)
8. [Recommendations](#8-recommendations)
9. [Live TV](#9-live-tv)
10. [Offline downloads](#10-offline-downloads)
11. [Radarr and Sonarr](#11-radarr-and-sonarr)
12. [Interface and device presentation](#12-interface-and-device-presentation)
13. [Native platform matrix](#13-native-platform-matrix)
14. [Media capability matrix](#14-media-capability-matrix)
15. [Web application and gateway](#15-web-application-and-gateway)
16. [Security posture](#16-security-posture)
17. [Build, run, and verify](#17-build-run-and-verify)
18. [Verification history](#18-verification-history)

---

## 1. What OpenStream is and why

OpenStream is an independent, multi-platform media application maintained by [Cyberbanksy](https://github.com/cyberbanksy). It unifies **local files, NAS shares, Stremio add-ons, live TV, and YouTube channels** behind one interface, and it plays each title over the best route the current device can actually decode.

The project exists to answer three questions honestly on every device, from a phone to a VR headset:

1. **What is this title?** — real metadata, artwork, cast, certification, ratings.
2. **Where will it play from?** — a completed device download, a NAS file, or an add-on stream.
3. **Can this device faithfully play this exact format?** — proven by decoder, display, and HDR probes rather than assumed from a filename.

Three principles follow from that, and they explain most design decisions in this document:

- **Capability proof over labels.** A codec string, container label, or HDR-eligible display is never treated as a decoder guarantee. Unsupported routes are blocked rather than played incorrectly.
- **The owner supplies the content.** The app ships empty. Every source is provisioned by its owner on the device (see §3).
- **Credentials stay where they were entered.** Server addresses, API keys, IPTV accounts, and tokens live in backup-disabled app-private storage or an OS secret store — never in source, logs, screenshots, documentation, or an APK.

Interface influences are acknowledged openly: Apple TV contributes focus clarity and content hierarchy, Infuse contributes source and playback workflow depth. No third-party APK was decompiled, and no proprietary Netflix code, layout, asset, or resource is bundled — only high-level viewing patterns were reimplemented independently.

---

## 2. Ownership and branding

- Product name: **OpenStream**
- Maintainer: <https://github.com/cyberbanksy>
- Canonical publication target: the private [`cyberbanksy/OpenStream`](https://github.com/cyberbanksy/OpenStream) repository. The legacy `orgista/openstream` remote is retained locally only to preserve history until migration is reviewed.
- The Android application ID stays `com.orgista.openstream` purely as a compatibility identifier. Changing it would install a second app and lose existing app data, libraries, and resume history. It must never be presented as visible product branding.

The canonical identity is the three-bar "play of streams" mark: `brand/openstream-mark.svg` and `brand/openstream-app-icon.svg`. Geometry is a 96-unit grid, bars at y=31/48.5/66 with lengths 40/56/40, stroke 12.5. The same mark drives the launch animation, adaptive/round/monochrome launcher icon, Android TV banner, and the tappable app-bar brand.

**Launcher icon sizing is settled.** The adaptive foreground uses a **23 dp inset on the 108 dp canvas**, placing the mark on Material's 44 dp square keyline — deliberately between "lost in the mask" and "edge-to-edge". `LauncherIconPresentationPolicy` and its unit test pin this, including the requirement that every corner stays inside the 66 dp safe circle so no launcher shape clips it.

**Launch sequence** is a five-second native animation in four scenes — Signal (0.9 s), Confluence (1.3 s), Lockup (1.1 s), Discover (1.7 s): local, NAS, and add-on streams sweep in to form the three-bar mark, the wordmark resolves, then the lockup glides into the real top bar and hands off to Discover. The glide target is derived from the same `TopNavLayoutPolicy` metrics the resident top bar uses (including safe-area insets), so the two can never drift apart. Disabled system animations get a 220 ms static-mark handoff instead.

In Kids Mode the brand reads as **OpenStream KIDS** — plain wordmark-matched text, no pill or badge.

---

## 3. The non-negotiable source provisioning rule

OpenStream never hardcodes requested content or account configuration. Any request to add, include, restore, or preload titles, channels, catalogs, Stremio add-ons, ARR connections, NAS libraries, IPTV accounts, YouTube channels, or metadata credentials means **provision them after deployment on the intended device or account** through **Sources**, **Settings**, or **Web Management**.

Production code may implement generic adapters, schemas, and management UI. It must **not** turn a requested source into a constant, compiled catalog, packaged asset, seed cache, fallback row, migration default, sample preference, provider priority, or silently installed configuration. Tests may use clearly isolated local mocks that cannot enter a production package. Every fresh install stays empty until its owner deliberately configures it, so Discover opens with an honest empty state.

[`POST_DEPLOYMENT_SOURCES.txt`](POST_DEPLOYMENT_SOURCES.txt) is the human operator checklist for requested integrations. A policy audit may inspect it, but no runtime, migration, fixture, build, or packaging tool may import, use, or ship it. It contains names and verification steps only — real credentials, private manifest paths, account URLs, and LAN topology stay in device-private storage or an approved secret store.

Credentials pasted into a development chat are not treated as installed configuration and are never copied automatically.

---

## 4. Kids Mode and the guardian admin PIN

First launch asks who watches on this device. Choosing **Kids Mode** walks a guardian through a rating cap (**Little kids** G/TV-Y, **Big kids** PG/TV-PG, or **Teens** PG-13/TV-14), an optional blocklist of titles or words, a **required guardian admin PIN**, and an explicit irreversible confirmation.

Once enabled:

- Titles above the cap, blocklisted matches, and **all unrated content** never appear in Discover, Library, or Search, and refuse to play.
- Titles the owner's Radarr/Sonarr servers certify inherit that certification, so owned kid-appropriate files pass the cap instead of being blocked as unrated (see §11).
- **Live TV plays** the guardian-curated lineup. The lineup itself is the safety control, and managing it sits behind the admin PIN with the rest of source management.
- **Settings and source management require the admin PIN.** Kids installs created before the PIN existed prompt the guardian to create one the first time the gate opens.
- The PIN **never** unlocks the content filter. It gates configuration only.

The lock is tamper-evident, not merely hidden. The kids profile is sealed with an FNV-1a checksum; a present lock always resolves to a kids policy, and a missing, edited, or unparseable profile (PIN included) fails **closed** to the strictest cap — which has no PIN and therefore no admin access. Tampering can only make the filter stricter. The admin PIN itself is stored as a salted SHA-256 inside that sealed profile (`AdminPinPolicy`, 4–8 digits).

There is no setting or hidden exit from the filter. The only reset is uninstalling OpenStream — removing its app data — and setting it up again.

---

## 5. Where content comes from

### NAS libraries — the only source of owned media

Owned media appears **only** after its NAS share is connected and one of its folders is added as a library. Files stream over SMB2/3 (jcifs-ng → a custom Media3 `DataSource` with seeking) so ExoPlayer's extractors and the device's hardware decoders handle MKV/MP4/TS, HEVC and AV1 with no gateway and no transcoding for anything the device can decode.

On Android, local/NAS routes are probed with the same Media3 source graph used by playback and cached in app-private storage under a SHA-256 route key. The cache stores codec, codec string, resolution, frame rate, bitrate, bit depth, HDR transfer/Dolby Vision profile, audio format/channels, Atmos hint, and MediaCodec's exact hardware support result. Filename tags remain only a fallback until a route has been probed.

A library folder remembers its share **by connection id**, so removing and re-adding a share leaves the folder pointing at an id that no longer exists. `LibraryFolderLinkPolicy` handles this:

- If exactly one configured share matches the folder's remembered **name**, the folder is re-linked and persisted automatically.
- Ambiguous (two same-named shares) or genuinely absent shares stay orphaned rather than attaching to the wrong server.
- Anything still unmatched is **reported** — the Library subtitle reads `No titles — reconnect a NAS share in Sources`, the overflow menu shows a count, and the Sources row flags the folder in amber with the share name to add.

That reporting matters: the indexer previously skipped orphaned folders silently, so a fully configured library read as "0 titles" with no explanation.

### Stremio add-ons

Configured stream and catalog providers are deliberately opt-in: **Sources → Add-on**, paste the personal manifest, leave its switch enabled. Only HTTPS manifests are accepted. The full configured path lives only in app-private, non-backed-up preferences; the UI shows the host plus "private configuration", and the path is never logged or written to source. Only direct HTTP(S) stream URLs are playable — raw torrent locators are ignored.

Catalog responses refresh in the background every six hours and fall back only to an app-private cache whose add-on identity and catalog still exist in current settings. Removing or disabling an add-on immediately drops its cached rails. Discovery accepts only `movie` and `series` types, so book and arbitrary `other` catalogs cannot appear as video rails. Stream, metadata, subtitle, and recommendation resources stay independently usable when advertised.

Discover preserves each add-on's own catalog structure instead of flattening providers together: every enabled add-on is its own group with separate category rails, and the cache retains that provenance across restarts. Every installed add-on has an icon-only diagnostic that revalidates manifest identity and probes one real catalog route, showing only a neutral refresh icon, a progress indicator, then a green check or red X — details stay in the accessibility description rather than revealing private paths.

For series, Stremio `meta.videos` is parsed into season-ordered episodes with stable stream IDs, thumbnails, titles, descriptions, runtimes, and parent IMDb identity. Details open on Season 1 when it exists, specials stay under Season 0, and Play resolves S1E1 through the same route policy as movies.

### Global Search

Search is not limited to cached rails. After a 350 ms debounce it queries every enabled catalog route whose manifest declares the `search` extra, in parallel, then title-first ranks and merges provider results with the local/offline library by IMDb identity. The catalog is normalized once into a reusable search index rather than re-normalizing every title on each keystroke; provider-returned canonical aliases stay visible (a `Se7en` query whose catalog title is `Seven`). Requests cancel as the query changes and are skipped offline.

### YouTube channels

**Sources → YouTube** accepts an exact `@handle`, canonical `UC…` ID, or channel URL and verifies it to the canonical ID before saving. No API key, no ambiguous general search. Each enabled channel contributes a channel-named 16:9 rail inside one shared **YouTube** Discover group from the public Atom feed, and the newest upload per channel is eligible for **Up Next**. Feed identity, video IDs, XML declarations, response sizes, and artwork hosts are validated before display. Selecting a video opens a full-screen restricted WebView using the official [YouTube IFrame Player API](https://developers.google.com/youtube/iframe_api_reference) — OpenStream never extracts, proxies, downloads, or exposes a direct YouTube media URL.

### Netflix regional Top 10

Netflix's signed-in home page is personalized per profile and is not a public catalog API, so OpenStream depends on no account cookies or member endpoints. The account-free adapter:

1. Fetches the unauthenticated regional page for `OPENSTREAM_NETFLIX_TOP10_COUNTRY` (default `US`).
2. Locates the public **Trending Now** section.
3. Preserves displayed order, accepting the first ten unique validated `https://www.netflix.com/title/{id}` links.
4. Polls every four hours — a polling interval, not a claim that the ranking changes that often; Netflix documents the list as updating daily.
5. Writes each successful snapshot atomically to `logs/netflix-top10-cache.json`, owner-only.
6. Falls back to Netflix's official `all-weeks-countries.tsv` latest week (which yields separate movie and series lists) if the regional markup changes.
7. Retains the last known-good snapshot if both fail, marking it stale after 30 hours rather than emptying the rail.

This is a public **regional overall** list, not a personalized homepage. Implementation: `server/netflix-top10.mjs`; tests: `server/netflix-top10.node-test.mjs`.

```text
GET /api/catalog/netflix/top10
Origin: http://127.0.0.1:5173
X-OpenStream-Session: <gateway session token>
```

Response fields: `source`, `cadence`, `refreshedAt`, `lastAttemptAt`, `fallbackWeek`, `stale`, plus `overall`, `movies`, `series`. Config: `OPENSTREAM_NETFLIX_TOP10_REFRESH_MS` (30-minute minimum), `OPENSTREAM_NETFLIX_TOP10_CACHE_FILE`.

Source markup is treated as an unstable external interface. [Netflix Help](https://help.netflix.com/en/node/116472) and the [official country TSV](https://www.netflix.com/tudum/top10/data/all-weeks-countries.tsv) are the references. [`thitirat-mnc/Netflix-top10-dataset`](https://github.com/thitirat-mnc/Netflix-top10-dataset) is useful for analyzing weekly history; OpenStream copies neither its code nor its data.

### Discover feed ordering

**Sources → Discover feed** gives persistent visibility and Up/Down ordering for **Up Next**, **Library**, **Add-Ons**, and **YouTube** without disabling the underlying sources. Up Next is a bounded, duplicate-free local ranking: resumable titles first, then one newest upload per enabled YouTube channel, then metadata/history-ranked likely-unwatched titles.

---

## 6. Metadata and credentials

Never place a real API credential in source, Gradle files, documentation, launch arguments, logs, screenshots, or an APK.

Viewers opt in under **Settings → Artwork & descriptions (TMDB) → Use my metadata API credentials**. Stored credentials are reusable by library scans and title details **only while that switch is on**; turning it off makes them dormant without deleting the library. Supported TMDB formats: **v4 API Read Access Token** (preferred) or **v3 API key**. The optional OMDb key (Rotten Tomatoes / IMDb / Metacritic scores) uses the same switch.

When an add-on supplies an IMDb ID, OpenStream resolves the canonical TMDB record through `/find/{imdb_id}` before falling back to a title/year search. Detail responses fill missing overview, year, certification, runtime, poster, backdrop, genres, cast, director, and tagline. Enrichment is merged back into every matching discovery category and the app-private cache, and later six-hour refreshes retain those richer fields instead of replacing them with a sparse provider record. A bounded background warmer enriches up to 24 sparse likely-next titles four at a time; cached series retain episode metadata. IMDb, Rotten Tomatoes, and Metacritic fields merge independently so an IMDb-only catalog rating cannot discard later OMDb critic scores.

**Workstation and LLM tooling.** Never put an OMDb value in a prompt, command argument, tracked file, URL log, or generated artifact. On this Mac the private reusable copy lives in Login Keychain under service `com.cyberbanksy.openstream.omdb`; the wrapper checks `OMDB_API_KEY` first, then reads that Keychain item itself. `.env.local` is git-ignored when a local environment file is needed. A caller supplies only an IMDb id:

```bash
pnpm metadata:omdb -- tt3896198
```

`scripts/omdb-lookup.mjs` calls OMDb over HTTPS, keeps the credential inside the process, validates the IMDb id, and returns sanitized metadata without returning or logging the request URL. An LLM should receive this as a narrow `lookup_omdb(imdb_id)` tool and never gain raw key or Keychain access.

The metadata server reads its process environment (`TMDB_READ_TOKEN` takes precedence):

```text
TMDB_READ_TOKEN=<TMDB v4 read token>
TMDB_API_KEY=<TMDB v3 API key>
OMDB_API_KEY=<OMDb key, for the local lookup wrapper>
```

**Periodic recent-movie metadata.** The loopback gateway refreshes metadata only; it never downloads movie or TV files. Sources are TMDB now-playing, popular, and weekly trends, exposed at authenticated `GET /api/metadata/recent`. Cache files are `0600` in the ignored `logs/` directory.

```text
OPENSTREAM_METADATA_REFRESH_MS=21600000   # default 6 h, minimum 15 min
OPENSTREAM_METADATA_CACHE_FILE=logs/metadata-cache.json
```

---

## 7. Playback

### Route selection

Selecting a larger title tile opens Details, where one primary **Play** action begins playback automatically. The route policy prefers, in order: a **completed device download**, a **local/NAS candidate** verified against the device's actual decoder support, an optional **server transcode** for incompatible SMB files, then the **highest-quality add-on stream** compatible with the current display, decoder, HDR, and audio capabilities.

Featured **Play** opens Details for a series so the episode list stays available. The series Play decision is local and deterministic: an unwatched show starts at S1E1 (specials are never the default), the most recently unfinished episode resumes from its stored position, a completed episode advances to the next numbered episode, and a completed finale stays replayable. The Season dropdown and episode cards always allow explicit override.

Remote playback keeps up to **12** distinct direct routes. A preferred route gets two short retries for transient 408/429/5xx failures before advancing automatically, retaining the resume position. Alternate-route status never carries forward an unverified Dolby Vision claim. Private route URLs and error causes are never logged.

### Bandwidth measurement

Automatic preflight measurement is **cellular-only**. It uses bounded ramped Cloudflare transfers (100 KB, 500 KB, 2 MB, 5 MB), discards the connection-warmup sample, and takes the median sustained result. If Cloudflare rejects an app-style probe with an access/rate/server response, the same official endpoint is retried once with same-origin browser headers and a cache-busting query. Unmetered Wi-Fi and Ethernet start with the best device-compatible route instead of being downgraded by a handshake-dominated 1 MB sample. If on-demand startup stays buffered for five seconds, the connection is measured once and cached. No location permission and no SSID read.

### Dynamic range

Dolby Vision is selected **only** when the display path and decoder are both confirmed. Platform codec constants map to bitstream profiles; the Lenovo TB132FU advertises P4/P5/P8/P9, so explicit P8 encodes are preferred while unsupported P7 remuxes are rejected. An unprofiled non-remux can be inspected at runtime; an unprofiled remux is deferred behind a reliable HDR10/SDR route.

Display resolution and decoder input limits are separate concerns: the Lenovo's 2560×1480 panel can accept and scale a decoder-supported 3840×2160 stream. Track selection uses the 4K decoder cap and the physical panel as its viewport.

### Player surface

- One slim centered preparation panel. On-demand remote buffering may say **Optimizing for your network**; Live TV uses the neutral **Loading** label and skips the on-demand slow-start path.
- Chrome shows only the title and a compact route such as **4K Stream**, **HD Local**, or **HD Offline**. Provider names, seeds, file sizes, route counts, measured Mbps, and safety-buffer math never appear.
- Positions save every five seconds under a hash of the stable media identity (with a URI-hash migration fallback). Raw NAS paths and signed stream URLs are never stored in playback preferences.
- Resume is offered after 15 seconds, cleared in the last 30 seconds or after 95% completion.
- Title, route label, and back control are transient and follow touch/remote visibility.
- Status bar hidden, navigation bar transparent. Swipe-up Home stays available; an upward gesture from the lower portion also exits.
- One navigation rule everywhere: player/details → last tab, tab → Discover, Discover → exit.

### Android and player baseline

- Compile/target baseline: **Android 17 / API 37**, `minSdk 26`.
- Player baseline: **Media3 1.10.1** with the ABI-compatible NextLib FFmpeg extension `1.10.1-0.13.0`.
- Playback starts only from a viewer action, requests media audio focus, saves resume state continuously, and pauses on activity stop to satisfy current background-playback hardening.
- The current Media3 patch includes decoder-recovery, Dolby Vision, DASH/HLS, and extractor crash fixes while preserving direct-play/FFmpeg fallback.

---

## 8. Recommendations

Recommendations run **locally and deterministically**. Ranking gives highest priority to resumable titles, learns item-to-item genre affinity from recent and repeated playback, moves completed titles behind unwatched choices, then considers release recency and metadata completeness. Viewing identifiers and NAS paths are hashed in app-private preferences; **no viewing history is uploaded**.

The design borrows the useful small-device pieces of collaborative filtering without pretending one viewer has a community-sized model:

- `rcz7795/Movie-Recommendation-System` — item similarity, rating prediction, and measurable evaluation informed the split between interaction signals and ranking.
- GroupLens **MovieLens 32M** is the stable external benchmark for offline evaluation after reviewing its current license/terms. It is not bundled, redistributed, or fetched by the app.
- Recent r/vibecoding media projects — preserve existing behavior with small testable changes, ground recommendations in a known catalog, weight history by recency and repeat visits, keep reusable state-free UI blocks.

---

## 9. Live TV

**Live** loads only the M3U/M3U8 playlist or Xtream-style account configured under **Sources → Live sources**, plus individual channels explicitly saved in Channel Manager. No public playlist, regional lineup, account, or channel is compiled into the app. Usernames and passwords are masked, stored only in backup-disabled app-private preferences, redacted from object descriptions, and never written to source, logs, screenshots, or APK constants.

**Pluto TV** is a separate opt-in source on that screen. It requests a short-lived session from Pluto's current boot service, downloads the viewer's geographically available channel/category data and six-hour guide at runtime, and constructs v2 stitcher URLs only in memory. This replaces the retired static HLS links that began returning Pluto's unsupported-device slate in 2026. The implementation was validated against the current session/guide behavior documented by [OpenViX/PlutoTV](https://github.com/OpenViX/PlutoTV) and [mbc3k/pluto](https://github.com/mbc3k/pluto); neither project, a channel list, nor a playback token is bundled into OpenStream.

The guide organizes that source into **Local**, **Entertainment**, **Premier**, **Sports Pack**, **League Sports**, and **Pay Per View**, caps normal guide rows while retaining the full provider catalog for search, and stores package/favorite/manual-channel preferences privately.

Presentation is a fixed channel rail with a two-hour half-hour timeline, current-time marker, program progress, favorites, vertical scrolling, time paging/swipes, and touch/keyboard/remote focus. Search uses a prebuilt normalized channel/program index, ranks direct channel-name matches before schedule text, and waits 110 ms after typing; the 5,000+ channel manager uses the same indexed approach. The current lineup and guide live in a private in-memory 15-minute session, so returning from playback paints immediately without refetching playlists.

Preparation is stale-while-refresh: route merging, package classification, program grouping, and both search indexes run off the Compose UI thread while the last usable prepared guide stays visible and available to player channel controls.

Inside playback, a deliberate swipe anywhere across the picture changes channel — right is next, left is previous — using a natural tablet-width threshold, and it can recover the adjacent channel by normalized name if a guide refresh replaced the original route key. Transient chrome places the compact **Live** action beside the timeline controls. Live uses Media3's measured live offset or the current window end to seek **forward only**, keeps a two-second cushion, resumes without a seek when already live, and reconnects routes that expose no live timeline. A user pause never shows the preparation overlay or auto-resumes. Initial startup and rebuffering both use the compact **Loading** surface; rebuffering gets two bounded reconnect attempts for transient 408/429/5xx failures, while an initial dead channel fails over immediately. Terminal 401/403 explains that the provider denied the channel and may require an active package or refreshed link, without exposing the route URL.

**Schedules.** Provider-advertised XMLTV is the only automatic source, parsed as a bounded stream. The parser removes only the conventional inert `<!DOCTYPE tv SYSTEM "xmltv.dtd">` prefix while rejecting internal entity subsets and disabling external general entities, parameter entities, and external DTD loading. Empty or failed guides keep a one-hour retry backoff; unmatched channels stay playable and show **Schedule unavailable**.

All Live empty/error actions route to Sources — the Live screen itself carries no Sources button, since source management belongs in **Settings → Sources** (and behind the admin PIN in Kids Mode).

---

## 10. Offline downloads

- **Make available offline** always means a completed copy stored on the Android device. It is never an ARR/server availability status.
- The downloader considers direct NAS routes and configured direct-stream add-ons, then picks the best resolution, codec, dynamic range, audio capability, and size for the device.
- **Settings → Offline downloads** selects built-in device storage or app-specific storage on a mounted SD card, with no broad file permissions. Location changes are disabled while any download exists so nothing is orphaned; the built-in location retains the legacy app-specific cache path so upgrades keep existing downloads playable.
- **Identity proof.** Version 2 records require the provider filename to match the requested title before any bytes are queued; a filename for another movie is rejected. Legacy downloads have no identity proof, are quarantined from offline playback/catalogs, and surface as **Replace unverified offline copy** rather than being silently trusted or deleted.
- Content lengths that overflow a signed 32-bit field (files > 2 GB) are repaired before progress is calculated. Completed records always show 100%; an active transfer with no trustworthy total shows saved bytes instead of a false 0%. Details and Settings show remaining device storage and total offline bytes.
- **Series** keep one Season dropdown beside Play containing only season names; after selection one icon-only download action appears for that season, and every episode card keeps its own. An arrow means queueable, a compact progress indicator means preparing/transferring, a check means the verified device copy is complete. A season action queues only its missing episodes through the same identity and capability checks as a movie.
- **Delete After Watching** is optional and off by default; it removes only the completed device download after playback is marked watched, retaining unfinished playback and online streams.
- **Delete all downloads** shows the exact count and requires an explicit Delete all or Cancel; it removes completed, partial, queued, and failed downloads through Media3 while retaining libraries, credentials, settings, and history.
- **Settings → Storage** measures temporary cache and catalog/title metadata separately with B/KB/MB/GB precision. **Clear cache** removes Coil artwork and other app-owned temporary files. **Clear metadata** confirms first, then removes only the local library index and add-on catalog/detail cache. Neither can touch device downloads, playback history, connection settings, or credentials.
- The **Captions** panel uses the concise **Auto-On** setting name.

---

## 11. Radarr and Sonarr

**Radarr and Sonarr are request/download targets, not libraries.** They never contribute browsable titles. This is the single most misunderstood part of the app: if movies are missing, the cause is almost always a missing NAS connection (§5), not arr.

What arr does provide:

- **Settings → Server downloads** accepts independent Radarr and Sonarr base addresses and API keys — password-masked, stored only in backup-disabled app-private preferences, omitted from logs and object descriptions, never compiled into source or an APK.
- The compact **Test** action calls `GET /api/v3/system/status` with the `X-Api-Key` header. HTTPS is accepted normally; cleartext HTTP is restricted to literal private/loopback addresses through a bounded client.
- **Download button default** stores one app-private preference: **Ask** (compatibility default), **This device**, or **Server**. If the matching ARR is not configured, the action falls back safely to the device flow.
- **Send to Radarr/Sonarr** selects the strongest available quality profile by target/cutoff resolution and source (preferring 2160p/remux-style targets over broad `Any` or HD profiles), applies it to an existing title when needed, then starts an exactly scoped `MoviesSearch`, `SeasonSearch`, `EpisodeSearch`, or `SeriesSearch`. A missing title is first added with the server's first accessible root folder and that profile, then searched. A retryable offline/network/server failure is saved in an app-private queue **without an API key** and retried with the currently configured connection after recovery; invalid/authentication failures are not silently retried. Submission shows progress only while the request is in flight and never creates a false on-device check mark.
- **Certifications.** Both servers store an MPAA/TV certification for every title they manage. `ArrCertifications` fetches those in one bulk request per configured server and fills in the rating for indexed library titles that metadata matching left blank — an existing rating always wins. This is what lets owned kid-appropriate files pass the Kids Mode cap instead of being blocked as unrated.

---

## 12. Interface and device presentation

**Orientation and viewport.** Android phones are portrait-first with normal user rotation; Android tablets request user-landscape while staying adaptive (API 37 may override orientation on 600 dp+ displays by platform design); Google TV stays landscape; iPhone supports portrait plus landscape; iPad declares landscape. Playback and adaptive/offline track selection use the active display mode, hardware decoders, HDR display paths, and current audio output. Settings shows the exact detected viewport and capability report.

**Top navigation.** Discover / Library / Live are always-visible tabs; Sources and Settings live in the overflow menu. Compact (mobile) rows use `TextSoft` rather than `Muted` for unselected tabs — deliberately brighter than the design file, because the muted value reads too dim on phone hardware. Tapping the **OpenStream** wordmark returns to Discover.

**Discover.** Large portrait poster rails with lazy vertical composition, title-by-title horizontal snap scrolling, and a restrained focus scale/border for remote navigation. A short, thin, translucent progress line sits near the bottom of the featured stage, clear of the system gesture indicator; it fills during the 12-second dwell and resets on the next title, with no countdown text. Featured and Details use a true full-width 16:9 media stage with no legacy 500 dp height cap. Cinematic backdrops use a centered full-bleed crop so a narrower source cannot leave a hard internal edge on wide tablets; the softly blurred loading/fallback layer is clipped to the stage boundary.

**Details.** One prominent Play action plus mutually exclusive thumbs-up/thumbs-down preferences as accessible icon-only controls. Provider names on cards are normalized to **Stream**; device-backed routes read **Local** or **Offline**. When TMDB supplies a valid official YouTube trailer ID, Details may transition from still artwork to the official muted YouTube IFrame player — only online, on an unmetered connection, and while system animations are enabled. Unavailable previews fall back immediately to the complete still artwork, and no app overlay obscures standard YouTube controls.

**Sources.** **Add NAS share**, **Add YouTube channel**, and **Add add-on** sit beside their matching section headings. Libraries, NAS shares, YouTube channels, add-ons, and the custom Live source use an explicit section-level delete mode: destructive red X controls stay hidden until **Delete…** is selected and disappear again with **Done**. IPTV/Xtream/M3U configuration and Channel Manager live under **Sources → Live sources**.

**Web Management (LAN setup).** **Sources → Web Management** starts an explicit temporary HTTP page on the device's private `192.168.x.x`/`10.x.x.x` address. While active, the device advertises `openstream.local:<port>` over mDNS and serves the portal at its root, so there is no path or access code to type. Sources presents that short name as selectable plain text with a Copy action and keeps `<device-ip>:<port>` underneath as the reliable fallback for guest Wi-Fi, client-isolated, VPN, or multicast-filtered networks; the optional QR carries the complete numeric URL. The responder takes Android's Wi-Fi multicast lock only for the session and releases it on success, Stop, screen close, failure, or the ten-minute expiry, following [Android's multicast-lock lifecycle](https://developer.android.com/reference/android/net/wifi/WifiManager.MulticastLock).

The portal follows the monochrome brand system — black canvas, near-black surface, white wordmark/action, gray supporting text — uses the real three-stream mark as a transparent PNG rather than CSS art, and includes a compact HTTPS `manifest.json` form, in-progress feedback, a styled success confirmation, and an editable error state. Browser-side and server-side parsing explain missing schemes, unsupported schemes, missing hosts, embedded credentials, query/fragment components, and non-manifest JSON paths before storing anything. It accepts one HTTPS Stremio manifest at `/` or `/openstream`, rejects non-local clients and every other path, expires after ten minutes, and stops after a successful add, an explicit Stop, or when Sources closes. Closing its listening or multicast socket is normal shutdown, not an uncaught exception. **Use only on a trusted LAN**; metadata and account credentials are never accepted by this page.

*Design QA (Wi-Fi setup flow): passed with no actionable P0–P3 visual differences.* Verified on the Lenovo TB132FU — selectable address with working Copy and QR, desktop browser reaching the typed LAN route, `http://` input blocked inline with HTTPS guidance, and `https://opensubtitles-v3.strem.io/manifest.json` producing **Connected to OpenStream** with OpenSubtitles v3 visible in Android Sources.

**Trakt (optional).** TV-friendly OAuth device-code flow, seven-day access tokens refreshed with the single-use refresh token, remote resume imported when no local point exists, and start/pause/stop scrobbles for IMDb-identified movies and numbered episodes. Until a publisher-owned OpenStream Trakt application is registered, users opt in with their own client ID/secret under Settings; credentials and tokens stay in backup-disabled app-private storage.

**Immersive routing.** On Android XR/Quest-compatible hardware the catalog remains the launch surface. Runtime probes identify Android XR/OpenXR/Quest devices; titles marked 180°, 360°, fisheye, cubemap, SBS, top-bottom, or multiview route to the immersive backend while flat titles stay in the normal player.

---

## 13. Native platform matrix

| Platform | Native technology | Current runnable scope |
| --- | --- | --- |
| Android mobile/tablet | Kotlin, Compose, Media3 | Full catalog, metadata, add-ons, playback, resume, offline, captions, HDR/audio labels |
| Google TV | Kotlin, Compose for TV, Media3 | Independent Leanback app sharing the Android core |
| iPhone/iPad | SwiftUI | Source-driven native shell and shared source/content policy foundation |
| Apple TV | SwiftUI | Focusable source-driven shell; playback integration is future work |
| Apple Vision Pro | SwiftUI | Native source-driven shell; immersive playback integration is future work |
| LG webOS | Packaged HTML5 app | Configured-catalog shell, adaptive performance profile, remote focus, playback, resume, format labels |
| Samsung Tizen | Packaged TV web app | Configured-catalog shell, registered media keys, remote focus, playback, resume |
| Hisense VIDAA | Hosted HTML5 app package | Configured-catalog shell, remote focus, playback, resume |
| Roku | SceneGraph/BrightScript | Source-driven empty-state channel foundation; catalog pairing and playback are future work |
| Android XR | Kotlin, SceneCore, Media3 | Independent full-space APK, incoming-URI autoplay, flat/equirectangular surfaces, mono/SBS/top-bottom/MV-HEVC, HDR surface metadata, pause/resume lifecycle |
| Meta Quest | Android NativeActivity, Media3, OpenXR C++, OpenGL ES | Independent arm64 APK, VIEW-intent autoplay, decoded external texture to OpenXR swapchain, flat/wide/equirectangular compositor layers, GPU fisheye and 3×2 EAC/cubemap conversion, mono/SBS/top-bottom crops, lifecycle pause/resume, headset capability probes |

### Per-target notes

**`native/android-xr`** — the product on Android; no web runtime. Kotlin + Compose over Media3, first-run onboarding with irreversible Kids Mode, Discover/Library/Search/Details with rating chips, direct SMB NAS playback, Stremio add-ons, real decoder/display probes surfaced in Settings, and the bounded Live TV guide.

**`native/android-xr-scene`** — managed-full-space Android XR app pinned to `androidx.xr.scenecore:scenecore:1.0.0-beta01`. Intent extras `projection`, `stereo`, and `dynamicRange` override filename classification. Direct `SurfaceEntity` playback covers flat, wide-FOV, equirectangular 180/360, mono, SBS, top-bottom, MV-HEVC, HDR10, HDR10+, HLG, and Dolby Vision decoder output. Fisheye and EAC/cubemap sources are **blocked** with an explicit native-mesh requirement instead of being shown with incorrect UV mapping.

**`native/google-tv`** — ships as `com.orgista.openstream` (the unified OpenStream application ID across form factors; all Orgista apps use `com.orgista.*`) sharing the Android core, with `LEANBACK_LAUNCHER`, no touchscreen requirement, Compose for TV Material 1.1 / TV Foundation 1.0, Media3 sessions, HLS/DASH, captions, resume, app-storage downloads, and HDR capability declarations.

**`native/apple`** — the public-framework playback and capability layer for macOS, tvOS, and visionOS. `AppleAssetInspector` reads codec, transfer function, Dolby Vision atoms, stereo flags, and public projection metadata from a real asset. `DolbyVisionConfiguration` parses profile, level, RPU/EL/BL flags, and base-layer compatibility identifiers, distinguishing P8.1/P8.2/P8.4 when signaled with transfer-function fallback for incomplete records. `AppleCapabilityProbe` uses `AVPlayer.eligibleForHDRPlayback` only as a broad eligibility signal. `OpenStreamVisionPlayerController` uses the visionOS 26 `AVExperienceController` immersive experience for APMP/AIV rather than inventing a custom projection. HDR10+ per-frame metadata stays an asset/runtime check. Compile-verified against tvOS 26.2 and visionOS 26.2 SDKs with explicit Swift target triples; validate representative media on physical hardware before any device/profile support claim.

**`native/openxr`** — runtime-independent C++20 core shared by the SceneCore and Quest adapters: inward flat, wide-field, equirectangular 180°/360°, fisheye/VR180, and EAC presentation geometry; mono/SBS/top-bottom/multiview eye binding; per-eye UV crops and texture-array layers; capability negotiation for decoder resolution, H.264/HEVC/AV1/VP9, SDR/HDR10/HDR10+/HLG/Dolby Vision, standard/spatial/Atmos audio, projection, and stereo; deterministic ready/play/pause/seek/end/stop transitions including live behavior. Also a standalone CMake project — `cmake -S native/openxr -B /tmp/openstream-xr-cmake -DBUILD_TESTING=ON`, then build and `ctest`. `openstream_xr_core` is position-independent so NDK shared libraries and native executables link it unchanged.

**`native/meta-quest`** — arm64 Quest/OpenXR app linking the official Khronos Android loader `1.1.62` through Prefab, pinned to Media3 1.10.1, NDK `29.0.14206865`, SDK CMake `4.1.2`. Version 0.3.0 accepts `content:`, `file:`, `http:`, `https:` VIEW intents; Media3 decodes to an external GL texture, the renderer copies each frame into an OpenXR swapchain, and the runtime submits a quad or `XR_KHR_composition_layer_equirect2` layer. A GPU shader converts fisheye/VR180 and 3×2 EAC/cubemap sources to projection-correct equirectangular swapchains. Mono, SBS, and top-bottom sources get independent eye visibility and pixel crops. Optional extras: `projection`, `stereo`, `codec`, `dynamicRange`, `audio`, `width`, `height`, `durationSeconds`, `live` — HDR is accepted only from explicit metadata. Multiview and runtimes without the equirectangular extension stay explicitly blocked until the required texture-array or projection-mesh renderer exists.

```bash
adb shell am start -a android.intent.action.VIEW \
  -d 'https://media.example/video_360_sbs.mp4' -t 'video/mp4' \
  --es projection 360 --es stereo sbs --es codec hevc
```

**`native/smart-tv`** — remote-first HTML5 with direct `<video>` playback, saved resume, system captions/audio controls, brief 4K/HDR/Atmos labels, network detection, cached catalog metadata, and recommendation ranking. No demo catalog or bundled video. Packages: `webos` (`appinfo.json`), `tizen` (`config.xml`), `vidaa` (hosted HTML5 metadata), `roku` (native SceneGraph channel — not a browser wrapper). Host integration surface is `window.OpenStreamTV.configure({ catalog, sources })`; playback URLs are deliberately not retained in local storage, so the paired host supplies fresh routes on launch.

`node scripts/build-tv-packages.mjs` creates deterministic staging folders and source archives under `dist/tv`, emits a webOS `.ipk` when LG's `ares-package` is on `PATH`, and normalizes Roku artwork to required FHD dimensions on macOS.

**LG webOS submission.** Deliverables: packaged source `dist/tv/webos`, archive `dist/tv/artifacts/openstream-webos-1.0.0.source.zip`, Seller Lounge icon `icon-400.png`, packaged `icon-80.png`/`icon-130.png`, FHD `splash-1920x1080.png`.

```sh
ares-install --device <device-name> dist/tv/artifacts/<package>.ipk
ares-launch --device <device-name> com.cyberbanksy.app.openstream
```

LG packaged web apps declare a 1920×1080 or 1280×720 graphics surface, so `appinfo.json` correctly uses FHD. OpenStream never transcodes or resizes playback URLs in JavaScript — the URL goes to the television's native video pipeline, so a compatible UHD model plays 3840×2160 while the UI stays FHD. Certification should cover HTTP and HLS at 2160p, seek/resume, codec failure messaging, HDR labels, subtitles, and audio-track selection on the oldest supported TV and at least one current UHD model. References: [CLI introduction](https://webostv.developer.lge.com/develop/tools/cli-introduction), [appinfo.json](https://webostv.developer.lge.com/develop/references/appinfo-json), [streaming protocol and DRM](https://webostv.developer.lge.com/develop/specifications/streaming-protocol-drm). The local UHD smoke asset `test-media/Glacier Run (2026).mkv` (3840×2160 HEVC Main 10) is a test input only and is never bundled.

Store signing, vendor certificates, and account-bound submissions remain outside source control.

---

## 14. Media capability matrix

OpenStream separates metadata identification from playback proof. Support states: **Supported** (implemented public path the capability report accepts), **Runtime check** (asset/decoder/display/headset validation still required), **Fallback** (compatible base layer or tone-mapped presentation), **Unsupported** (blocked rather than presented wrongly).

### Dynamic range

| Format | Web | tvOS | visionOS | Android XR / Samsung XR | Meta Quest |
| --- | --- | --- | --- | --- | --- |
| SDR | Supported | Supported | Supported | Supported | Supported |
| HDR10 | Runtime check | Supported platform path | Supported platform path | SceneCore metadata + runtime check | Blocked pending headset proof |
| HDR10+ | Runtime check | Asset/runtime check | Asset/runtime check | SceneCore metadata + runtime check | Blocked pending headset proof |
| HLG | Runtime check | Supported platform path | Supported platform path | SceneCore metadata + runtime check | Blocked pending headset proof |
| Dolby Vision | Runtime check | Asset + decoder check | Asset + decoder check | SceneCore metadata + runtime check | Blocked pending headset proof |

The Apple inspector parses `dvcC` and `dvvC` records including profile, level, RPU, enhancement/base-layer flags, and base-layer compatibility identifier. Profile 8 is represented as P8.1 (HDR10-compatible), P8.2 (SDR-compatible), or P8.4 (HLG-compatible) when explicitly signaled; transfer function is only a fallback when the compatibility identifier is absent or unknown. P5, P7, P8.1, P8.2, P8.4, and unknown profiles remain runtime checks, and unsupported or future profile numbers stay unknown rather than being misreported.

Android probes `Display.HdrCapabilities`, advertised HEVC/AV1 Main10 profiles, and Dolby Vision decoder profiles. Codec-string inspection reports profile and level but never infers base-layer compatibility the string does not contain.

### Immersive projection

| Projection | WebXR | tvOS | visionOS | Android XR / Samsung XR | Meta Quest |
| --- | --- | --- | --- | --- | --- |
| Flat | Supported | Supported | Supported | Supported | OpenXR quad implemented; headset check |
| Mono/stereo 180 | Runtime WebXR | Unsupported | Public AVKit path | Native SceneCore path, device check | Media3 + KHR equirect layer; headset check |
| Mono/stereo 360 | Runtime WebXR | Unsupported | Public AVKit path | Native SceneCore path, device check | Media3 + KHR equirect layer; headset check |
| Fisheye / VR180 | Runtime WebXR | Unsupported | Runtime check | Blocked; native mesh required | GPU conversion + KHR equirect layer; headset check |
| Cubemap / EAC | Runtime WebXR | Unsupported | Runtime check | Blocked; native mesh required | GPU 3×2 EAC conversion + KHR equirect layer; headset check |
| Wide FOV / APMP | Runtime WebXR | Unsupported | Public AVKit experience path | Native quad path, device check | Native wide quad; headset check |
| Apple Immersive Video | Unsupported | Unsupported | Public AVKit experience path | Unsupported | Unsupported |

The browser viewer implements 180, 360, and wide projections with mono, SBS, and top-bottom stereo, validates source URLs, and supports local file selection. Browser HDR preservation depends on the browser, compositor, headset, and media pipeline, so OpenStream does not promise Dolby Vision or HDR10+ output through WebXR. visionOS uses public projection metadata and `AVExperienceController` rather than a custom projection for Apple Immersive Video; hardware validation with representative licensed/test clips is required before release claims.

The immersive session core rejects unsupported resolution, codec, projection, stereo, dynamic-range, and spatial-audio combinations **before** allocating runtime resources, then provides deterministic ready/play/pause/seek/end/stop behavior and per-eye texture bindings.

References: [Apple AVFoundation HDR and Dolby Vision guidance](https://developer.apple.com/news/?id=rwbholxw), [Apple immersive media overview](https://developer.apple.com/documentation/technologyoverviews/immersive-media/), [Dolby Vision profile overview](https://professionalsupport.dolby.com/s/article/What-is-Dolby-Vision-Profile?language=en_US).

---

## 15. Web application and gateway

Screens are addressable for development and QA:

`?screen=discover` · `?screen=library` · `?screen=details` · `?screen=live` · `?screen=connections` · `?screen=search` · `?screen=activity` · `?screen=settings` · `?screen=player` · `/xr/viewer`

**NAS folders and local transcoding.** A NAS folder connection points the loopback gateway at a directory this machine already mounts (for example an SMB share under `/Volumes`). Files stream with HTTP Range support for instant seeking. When the device cannot direct-play a format, the gateway transcodes locally with ffmpeg — VideoToolbox hardware encoders when available — always capped at the device's probed resolution and never upscaling. Playback falls back to the transcode route automatically when a direct route fails, and the player offers a manual Transcode control. Gateway-proxied add-on streams can be transcoded the same way.

**Android server transcoding for Unraid/NAS.** The Android app can use an OpenStream gateway on a LAN server when a direct SMB route is incompatible. This is explicit post-deployment configuration, not a source default. The server must be launched with a high-entropy token and an SMB-share-to-local-path mapping for the mounted media path:

```bash
OPENSTREAM_GATEWAY_ALLOW_LAN=1 \
OPENSTREAM_GATEWAY_HOST=0.0.0.0 \
OPENSTREAM_GATEWAY_PORT=8787 \
OPENSTREAM_GATEWAY_TOKEN="<32+ character random token>" \
OPENSTREAM_NAS_MAPPINGS='[{"host":"<smb-host-or-ip>","share":"<share-name>","rootPath":"/mnt/user/<mounted-share>"}]' \
pnpm gateway
```

Then enter `http://<server-lan-ip>:8787` and the token in **Settings → Server transcoding**. Android sends the token as `X-OpenStream-Session`; it is never embedded in the media URL. The gateway resolves only SMB files inside the configured `rootPath`, rejects unmapped shares and path traversal, and streams the transcoded output as fragmented MP4.

**Logging.** The gateway writes redacted JSONL logs (one file per day, `logs/` by default, `OPENSTREAM_LOG_DIR` to override) covering every request, connection test, transcode lifecycle, and errors the browser ships to `POST /api/logs`. Uncaught client errors are captured automatically, so a session can be replayed end to end from one file.

---

## 16. Security posture

OpenStream does not bypass DRM, extract protected media or keys, or claim playback support from metadata alone. Private-network connections require explicit consent. The development server uses a one-time launch capability and HttpOnly browser session; its proxy authenticates to the loopback-only gateway with a separate launch secret; gateway records and media capabilities are owner-bound. Credentials remain server-side. Signed XR media locators use one-time, owner-bound handoffs, and viewer navigation carries only an opaque fragment identifier.

A native and immersive security audit covering the OpenXR/Quest C++ engine, the Apple package, Android XR/SceneCore, and the smart-TV targets closed **17 findings (OS-SEC-01 … OS-SEC-17), all remediated and verified by test**:

| ID | Area | Issue |
| --- | --- | --- |
| OS-SEC-01 | OpenXR | Swapchain out-of-bounds read and image release leak |
| OS-SEC-02 | OpenXR | Sphere mesh 32-bit integer arithmetic overflow |
| OS-SEC-03 | Apple | Non-finite track dimensions causing a fatal trap |
| OS-SEC-04 | Android | `LanSetupServer` local-network CSRF add-on injection |
| OS-SEC-05 | Android | SMB credential relay and host forwarding |
| OS-SEC-06 | Android | Kotlin companion-object grammar error (build blocker) |
| OS-SEC-07 | OpenXR | 180° projection segment-count underflow |
| OS-SEC-08 | OpenXR | GLSL division by zero and EAC edge bleeding |
| OS-SEC-09 | Apple | Offline storage sandbox path containment bypass |
| OS-SEC-10 | Apple | Dolby Vision box parser version and buffer bounds |
| OS-SEC-11 | Android XR | `ACTION_VIEW` intent scheme injection and permission handling |
| OS-SEC-12 | Android XR | SceneCore `SurfaceEntity` node memory/resource leak |
| OS-SEC-13 | Smart TV | Wildcard origin without a Content Security Policy |
| OS-SEC-14 | Android | `MulticastLock` under-lock runtime exception |
| OS-SEC-15 | Smart TV | Unbounded persistent playback history |
| OS-SEC-16 | Android | Unhandled percent-encoding and subtitle URL parsing exceptions |
| OS-SEC-17 | Quest | Cross-thread memory visibility and JNI allocation |

Resulting invariants worth preserving: intent schemes are allowlisted to `content`/`file`/`http`/`https`; the LAN setup server verifies Origin/Referer and enforces a 128-bit session token; SMB hosts are validated to prevent credential relay; smart-TV playback history is LRU-capped at 50 items; the smart-TV `index.html` carries a strict CSP; mesh segment bounds are enforced at `[2..1024, 3..2048]`; and Apple track dimensions and frame rates are sanitized against `NaN`, `±Inf`, negatives, and extreme floats.

---

## 17. Build, run, and verify

### Local development (web)

```bash
pnpm install
pnpm dev
pnpm qa
pnpm test
pnpm build
pnpm netflix:top10:emulate
node scripts/live-smoke.mjs "<secure launch url>" "<nas folder>"   # E2E: onboarding, NAS, direct play, transcode
```

`pnpm dev` starts both Vite and the loopback gateway. Open the one-time secure launch URL printed in the terminal — it establishes a per-origin browser session, removes the launch capability from the address bar, and never creates a host-wide loopback cookie. Standalone gateway launches are for controlled integrations and require an explicit high-entropy `OPENSTREAM_GATEWAY_TOKEN` shared only with a trusted proxy.

**On this workstation** the Vite cache must live off the project volume:

```bash
OPENSTREAM_VITE_CACHE_DIR="$HOME/Library/Application Support/OpenStream/vite-cache" pnpm dev
```

`pnpm qa` audits every screen plus the onboarding/Kids Mode flow (rating filter, irreversibility, tamper fail-closed), writes temporary captures outside the repository by default, and needs `CHROME_FOR_TESTING_PATH`.

### Full verification sweep

```bash
pnpm test
pnpm build
pnpm test:android-device
node scripts/stremio-addons.mjs
node --test scripts/tv-core.node-test.mjs
node --test scripts/webos-package.node-test.mjs
node --test scripts/challenger2-security-stress.node-test.mjs
node scripts/build-tv-packages.mjs
node scripts/title-search-audit.mjs
sh scripts/openxr-core-test.sh
sh scripts/quest-layer-test.sh
swift test --package-path native/apple --scratch-path /tmp/openstream-apple-build --jobs 1
```

### Android (this Mac)

The project lives on an SMB volume, so Gradle needs a local project cache, `--no-watch-fs`, and `ANDROID_HOME`:

```bash
ANDROID_HOME="$HOME/Library/Android/sdk" OPENSTREAM_ANDROID_BUILD_DIR=/tmp/openstream-android-build \
  gradle --no-watch-fs --project-cache-dir /tmp/openstream-gradle-project-cache \
  -p native/android-xr testDebugUnitTest lintDebug assembleDebug
adb install -r /tmp/openstream-android-build/outputs/apk/debug/app-debug.apk
```

`OPENSTREAM_ANDROID_BUILD_DIR` routes generated output to local temporary storage; without it, AGP can fail to delete its generated `packageDebug/tmp` folder on an external macOS volume. The unprefixed form (`gradle … -p native/android-xr assembleDebug`, artifact under `native/android-xr/app/build/outputs/apk/debug/`) works when the volume cooperates.

Other Android targets:

```bash
OPENSTREAM_GOOGLE_TV_BUILD_DIR=/tmp/openstream-google-tv-build gradle --no-watch-fs \
  --project-cache-dir /tmp/openstream-google-tv-gradle -p native/google-tv testDebugUnitTest lintDebug assembleDebug
OPENSTREAM_ANDROID_XR_BUILD_DIR=/tmp/openstream-android-xr-scene-build gradle --no-watch-fs \
  --project-cache-dir /tmp/openstream-xr-scene-gradle -p native/android-xr-scene testDebugUnitTest lintDebug assembleDebug
OPENSTREAM_QUEST_BUILD_DIR=/tmp/openstream-meta-quest-build gradle --no-watch-fs \
  --project-cache-dir /tmp/openstream-meta-quest-gradle -p native/meta-quest lintDebug assembleDebug
```

### Credential-safe live checks

```bash
node scripts/stremio-addons.mjs
OPENSTREAM_STREAM_ADDON_MANIFEST_URL='<personal manifest>' node scripts/stremio-addons.mjs
```

Retries transient 408/429/5xx with bounded exponential backoff and reports only manifest identity, capabilities, catalog counts, and direct-stream counts. `node scripts/title-search-audit.mjs` runs the repeatable 50-movie/50-series public catalog audit, printing only totals and failures and never reading private add-on configuration.

### Test coverage by tier

| Tier | Harness | Scope |
| --- | --- | --- |
| OpenXR core | CMake/CTest | Vertex/index buffer generation for 180°/360°/EAC/fisheye/flat; segment bounds `[2..1024, 3..2048]`; 180° underflow; swapchain acquisition bounds and error-release cleanup; GLSL coordinate math |
| Meta Quest | Clang++ C++20 | Compositor layers, per-eye crops, JNI Media3 bridge lifecycle, `volatile` cross-thread flags |
| Apple native | Swift Package Manager | Track dimension/frame-rate sanitization; Dolby Vision `dvcC`/`dvvC` bounds, version, profile/level; offline sandbox containment and symlink traversal defense; format negotiation and projection classification |
| Android XR SceneCore | Gradle | `ACTION_VIEW` scheme allowlist; `SurfaceEntity` lifecycle disposal on release and init error |
| Android XR main | Gradle | `LanSetupServer` anti-CSRF and session token; `SmbDataSource` host validation; `MulticastLock.release()` guard; percent decoding and subtitle URI resilience; Kotlin 2.x companion-object conformance; launch/brand policy; Kids Mode and admin PIN; arr certifications; library folder re-linking |
| Smart TV | Node test runner | Strict CSP meta tag; LRU 50-item history cap under 2,000-item overflow stress; spatial navigation and focus; webOS/Tizen packaging |
| Web/server | Vitest + Node | Screens, gateway, Netflix Top 10 parser/fallback/cache/stale behavior |

---

## 18. Verification history

**Current Android suite:** 351 unit tests passing with zero failures, lint clean, debug APK assembling and installing.

**August 17, 2026** — Kids Mode and library work. Live TV plays in Kids Mode; the Sources button moved from Live into Settings; the KIDS pill became wordmark text; the guardian admin PIN was added to onboarding with a PIN gate on Settings/Sources and a first-use claim path for pre-existing kids installs; Radarr/Sonarr certifications now rate indexed titles; and `LibraryFolderLinkPolicy` replaced the silent orphaned-folder skip with auto-relinking plus visible Library and Sources warnings. Verified on device: a fully configured library that indexed nothing now reads `177 titles · a NAS share needs reconnecting` instead of appearing empty, and the log states `library folder has no NAS share configured: ServerPlus/movies`.

**August 14, 2026** — source/brand cleanup. 314 Android and 314 shared Google TV unit tests with zero failures, both lint pipelines, and both debug APK assemblies. Web passed 29 Vitest tests, 52 server/script tests, TypeScript checking, and a production Vite build; the Apple package passed all 10 tests; the webOS/Tizen/VIDAA/Roku package builder completed. The final APK installed as an upgrade on the attached Lenovo TB132FU and passed a cold-launch Discover → Library → Discover smoke test with no crash or ANR. The upgrade retained all three settings-added Stremio add-ons, found no compiled-default preference, discarded the stale compiled discovery cache, and removed ten obsolete public Live cache files. Discover rendered the source-driven empty state with no book row or bundled title.
Android APK SHA-256: `3d1ebc187a69f7c56a2f763165b093576ca8d0abc2883d888f417771d60d83ce`
Google TV APK SHA-256: `61b927f39403496968e8f466d0cebac15d533f444eb7dc69e113688ee442a0fc`

The former chronological device log was removed because it described compiled demo catalogs, public IPTV defaults, and visual assets that no longer exist.
