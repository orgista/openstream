# Speed and metadata: what Plex, Infuse, Netflix and Jellyfin do (REA round 2, 2026-10-16)

For `specs/rea-speed-metadata-2026-10-16.md`. Read-only: no app code changed and nothing built. The build lock was held by
another lane (`avp-ipad` sweep), so no Ghidra run was started; evidence comes from shipped strings, bundled JS and one REA
JADX class search. Builds on `2026-10-11-plex-backend.md`, `2026-10-11-plex-lessons-for-openstream.md` and
`2026-10-14-metadata-artwork.md` without repeating them. OpenStream paths are relative to `Sources/OpenStreamApple/`.

## Ranked action list (user-visible gain per effort; all app-only unless marked)

| # | Change | Fixes | Effort | Needs |
|---|---|---|---|---|
| 1 | **Top 10 artwork through TMDB ids, persisted.** Resolve each Netflix entry with TMDB search (title + type, season title stripped, year where known). Keep a rank → TMDB-id map on disk per week, then use TMDB poster/backdrop by id. Draw a text card only after TMDB *and* the catalogs have no art. | grey "UNABOMBER"-style cards | S–M | TMDB key (already used) |
| 2 | **Cache the Top 10 week on disk; stop the per-launch full download.** Reuse one client (memo never hits today) and keep the parsed week with its fetch date; refresh at most daily, conditional GET. | Top 10 row late or missing on every launch; 64 MB-cap TSV parse | S | — |
| 3 | **Parser: "Season N" in the file name with no episode token and a year after it means a movie.** Count `Season N` as a season only from a folder name, or with an episode token. Fixtures: Open Season 2/3, Season of the Witch, `Show.Season.3.1080p` (folder), `Show.S03E04`. | "Open Season 3" as show "Open" | S | — |
| 4 | **Show cached shelves before the index load and progress sync.** `loadCachedSections` is serial behind `mediaIndex.load()` and `synchronizePlaybackProgress()`; run it first (or concurrently). | Discover painting late on launch | S | measure on DevPlus |
| 5 | **Smaller-size-first images.** When a size isn't decoded yet, show any decoded size of the same URL at once, then swap (Plex's image cache does this). Snap request sizes to a few buckets so sizes share entries. | blank card flashes when the same art appears at another size (row → hero → detail) | S | — |
| 6 | **Colour placeholders instead of flat fill.** Use the server's BlurHash where given (Jellyfin `ImageBlurHashes`; Plex has `artBlurHash` + UltraBlur colours). For TMDB/Cinemeta art, store the average colour (or a small BlurHash) of each decoded image with the disk entry. | grey/near-black tiles before art | M | server fields exist; nothing new on servers |
| 7 | **Right-sized server images.** Jellyfin Backdrop has `maxWidth: nil` (original size); Plex posters are fixed 600×900 and art 1920×1080. Request bucket × screen scale and pass Jellyfin `tag` (immutable, 365-day cache). | slow backdrops from Jellyfin/Plex, bigger decodes | S | — |
| 8 | **Keep decoded display-size thumbnails on disk** (Infuse's "display" cache) or at least request the smallest TMDB bucket that covers the tile. Today every memory miss decodes the raw w500/w1280 file again. | scroll-back and relaunch art pop-in | M | measure first |
| 9 | **Prefetch the next row and decode it** (bytes only today; one row; 200 ms dwell). Remove the dwell for items visible on first paint. | art arriving after the row is on screen | M | trace before/after |
| 10 | **TMDB title search before the serial add-on walk** in library matching when TMDB is configured; run add-on searches concurrently. | slow first match of new files | S–M | — |
| 11 | **Plex requests like Plex's own client:** hubs with `excludeFields=summary` and `count+1`, windowed library pages (400 local / 100 remote), detail with async augmentation. Recently Added is capped at 30 today. | Plex libraries feel thin/slow | M | Plex server (already there) |
| 12 | **Memoize Top 10 matching** (it runs twice per entry on every draw) and persist matches beyond card `@State`. | small CPU, repeat searches on remount | S | — |

Nothing here needs AetherEngine. "Needs server" only means using fields the Plex/Jellyfin servers already return.
The owner's "4 s black screen" (iPhone recording, build dd8d32d) predates the current cover: today the cover is
black with the mark, no spinner, and lifts after 350 ms–1.3 s (`AppleLaunchReadiness.swift:33-48`). The remaining
launch spinner is the refresh `ProgressView` over cached rows (`AppleDiscoverView.swift:405-409`), shown whenever the
catalog cache is older than 6 h (`AppleCatalogStore.swift:942-945`). Re-measure on DevPlus before working on launch.

## 1. Speed: why Plex and Infuse feel instant

### Plex (web client 4.160.0 bundled in Plex.app; PMS 1.43.4)
Evidence: `W/js/main-8792-…-plex-4.160.0-75ddd7b.js` (`M`, SHA-256 `e59d55e3…edc01`, same file as the 10-11 report);
offsets are character offsets. PMS strings from `Plex Media Server` (SHA `957ff12b…`).

- **The server resizes every image.** The client never downloads originals for tiles: `/photo/:/transcode?url=…&width=&height=&minSize=1&upscale=1`
  (`M:557218`; React path `M:1712488`). PMS registers `PhotoTranscodeRequestHandler` and the format string
  `%s?height=%d&width=%d&minSize=1&upscale=1&url=%s`.
- **Size buckets × pixel ratio.** Module `66861` (`M:~1713000`) defines 8 widths: `small-60, small-120, medium-240,
  medium-360, large-480, large-720, large-1280, large-1920`. The builder picks the smallest bucket ≥ the requested width
  and multiplies by `min(devicePixelRatio, 3)` (module `9049`, `M:422416`). Height = bucket × aspect. Few distinct URLs
  per image, so caches hit across screens.
- **Smaller size first.** The image cache (module `17204`, `M:~1777000`) keys an image by its URL with
  `size|scale|width|height` stripped, keeps every loaded size sorted, and `getPlaceholder()` returns the largest size
  already loaded when a new size is requested. The view shows that at once (`loadBlob` → `t.notify(placeholder)`), then
  the sharp one. Memory-only: `maxSize: 50` items, 3 cycles. A separate model cache (module `8580`) keeps 100 metadata
  models, so reopening a title doesn't refetch.
- **Placeholders are colour, not grey.** PMS computes a BlurHash per item at scan (`BlurHashProcessor`,
  `GenerateBlurHash(MetadataItem, MetadataField)`, fields `artBlurHash`, `blurHashesChangedAt`; log
  `[BlurHashProcessor] Generated for item %d %s in %d ms`) and four corner colours (`UltraBlurProcessor`,
  `UltraBlurColors`, endpoint `/services/ultrablur`). The client draws an UltraBlur gradient (`M:1807223`, 4 corner
  rgba values). Poster theme colours include `posterPlaceholderIconColor` (`M:2915499`).
- **Lists are windowed.** Paging constants (module `13825`, `M:1777579`): 400 items per request on a local server,
  100 via cloud (`G_=400`, `ZK=100`). `fetchRange` asks only for the visible window via `X-Plex-Container-Start/Size`
  (`M:2439887`); collections track a `populatedRange` (`M:207488`). A custom grid virtualizer renders only visible
  cells with `overscan: 1` (module `41623`, `M:678432`; used at `M:902139`, `M:1017177`).
- **Light payloads, slow parts later.** Hubs default to `excludeFields=summary` and ask for `count+1` to know if a row
  has more (`M:180588`). The title fetch asks for everything in one call (`includeOnDeck, includeExtras,
  includeChapters, includeMarkers, …`) but with `asyncAugmentMetadata=1`, `asyncCheckFiles=1`,
  `asyncRefreshAnalysis=1`, so the server answers before file checks and enrichment finish (`M:288884`). Related rows
  come in a second request with `hubCount: 8` (`M:346852`).
- **No persisted client cache found.** No IndexedDB, service worker, `staleTime` or sessionStorage in the bundle (grep
  counts 0). Plex's speed is the server: a local SQLite library (the PMS strings include the full `metadata_items` /
  `media_items` / `media_parts` select), pre-made thumbnails and BlurHashes. **Inference:** the client feels instant
  because every answer is a cheap local query plus a small, pre-sized image.

### Infuse 8.5.6 (`Infuse.app`, strings and source paths from `Contents/MacOS/Infuse`)
- **Two image caches.** "Original" thumbnails (`Thumbnails/Orignal/Cache/DefaultThumbnailsCache.swift`,
  `DiskThumbnailsPersistentStorage.swift`, `PLThumbnailsDAO.swift`) and "Display" thumbnails rendered at display size
  (`Thumbnails/Display/Processors/Render/ImageRendererThumbnailProcessor.swift`, filters factory), stored in
  `DisplayThumbnails.MemoryNSCache`, `DisplayThumbnails.SqliteDiskCache` and `DisplayThumbnails.FilesDiskCache`
  (`DisplayCache/DiskCache/DisplayThumbnails.DiskCache.{Sqlite,Files}.swift`). **Inference:** a relaunch reads a
  ready-to-draw bitmap, not a JPEG that must be downsampled again. Kingfisher is linked too (with its
  `ImagePrefetcher` queues), plus `cleanExpiredDiskCache`.
- **A local metadata database.** SQLite tables include `index_file_info (ItemID, VFS_Key, Path, FileName, HttpUrl,
  SeriesTitle, SeasonNumber, EpisodeNumber, ParentID)`, `meta_plex_seasons (… PosterURL, BackdropURL, UpdatedAt)`,
  `cached_plex_series`, `cached_collections`, `plex_collection_items`, `SpotlightIndex`, with `PRAGMA optimize`.
  Plex sections are cached (`FCPlexSectionsCache load/save/setSections:forServerID:`). Public docs: "Pre-Cache
  Details" and "Pre-Cache Artwork" fetch details and posters/fanart during indexing ([Firecore](https://support.firecore.com/hc/articles/27862264977047-Library-Scanning-Indexing)).
- iCloud sync prefetch exists (`quickPrefetchWithContainer:recordTypes:`). No BlurHash string was found.

### Jellyfin + Swiftfin (open source; jellyfin `aec42b3`, Swiftfin `5685d08`)
- Server resizes and caches (`Jellyfin.Drawing/ImageProcessor.cs:77,118-197`, `resized-images`); with `tag` the
  response is `Cache-Control: public, max-age=…, immutable`, 365 days (`ImageController.cs:1679-1682, 2029-2032`).
- BlurHash is computed at scan (`LibraryManager.cs:2632`) and returned inside every item as `ImageBlurHashes`
  (`BaseItemDto.cs:530`, `DtoService.cs:1050-1060`). Swiftfin draws an 8×8 BlurHash while loading
  (`ImageView.swift:142-155`, `PosterImage.swift:60-66`).
- Swiftfin (Nuke): posters disk cache 1000 MB keyed by URL without `maxWidth` plus `-maxWidth`
  (`ImagePipeline.swift:19-41`, `DataCache.swift:23-31`); memory 200 MB; sizes are points × screen scale, iOS posters
  200/300 pt, tvOS 500 (`PosterDisplayType.swift:10-16`). Library paging 50 items, next page 300 pt before the end
  (`PagingLibraryViewModel.swift:15`, `PagingLibraryView.swift:145-149`). No prefetcher.

### OpenStream today (checked against source)
- Memory cache: actor + `NSCache` of decoded `CGImage`, 300 entries / 160 MB, key `url|maxPixelDimension`
  (`AppleRemoteImage.swift:303-305, 338, 350-354`). Another size of the same URL is a miss: no smaller-size placeholder.
- Disk: raw downloaded bytes in `Caches/OpenStream/Artwork-v1/SHA256(url)-variant.bin`, 512 MB LRU, no expiry
  (`AppleArtworkDiskCache.swift:6-14, 37-38, 56, 77-82`). Every memory miss decodes again (off main, CGImageSource
  thumbnail; `AppleRemoteImage.swift:405-449`). Good: decode off main, size clamp 64…2560.
- Sizes: TMDB buckets 92…780 posters / 300…1280 landscape (`AppleArtworkResolver.swift:9-24`) — already Plex-like.
  Plex fixed 600×900 / 1920×1080 (`ApplePlexClient.swift:493-504`); Jellyfin Backdrop `maxWidth: nil`
  (`AppleMediaServerLibraryStore.swift:387, 394, 1246`).
- Prefetch: 20 items in the current row after a 200 ms dwell, bytes only, 4 at a time
  (`AppleArtworkPrefetchPolicy.swift:11-36`; `AppleRemoteImage.swift:359-401`; `AppleDiscoverView.swift:2417-2425`).
- Placeholder: flat `white.opacity(0.025)` (`AppleRemoteImage.swift:37, 76`); no BlurHash or colour anywhere.
- Launch: Discover task runs `mediaIndex.load()` → `synchronizePlaybackProgress()` → `loadCachedSections` →
  `refresh` in series (`AppleDiscoverView.swift:566-586`). Catalog snapshot `catalogs-v2.json`, 6 h fresh, shown when
  stale (`AppleCatalogStore.swift:770-821, 904`). `AppleSourceStore.init` does keychain work on main
  (`AppleSourceStore.swift:1012-1057`) — measure before changing.
- Network: one ephemeral bounded session, `urlCache = nil` (`AppleBoundedHTTPDataLoader.swift:19, 86-107`); TMDB its
  own ephemeral session. Connection reuse works within a session; nothing is configured for HTTP/2/3 (system default).
- Lists: `LazyVStack` of `LazyHStack` rails (`AppleDiscoverView.swift:242`; `AppleMediaShelf.swift:53-83`) — fine.
  On macOS `Group(subviews:)` builds every tile (`AppleMediaShelf.swift:69-75`).

**What we should do:** actions 4–9. We already have the hard parts (lazy rows, off-main decode, buckets, disk cache).
The gaps are the ones a user sees: a blank fill instead of colour, a refetch/redecode whenever the size changes, and
backdrops at full size from Jellyfin. Measure each with the existing `atv-slowness` harness on DevTV/DevPlus.

## 2. Metadata matching

### How they parse names
- **Plex native scanner** (strings in `Plex Media Scanner`, SHA `5692fde8…`): every TV pattern needs an episode number
  next to the season — `s(?<season>)…e(?<ep>)`, `(?<season>)x(?<ep>)`, `s(?<season>[0-9]{2})[-._ ]+(?<ep>)`,
  `sp(?<ep>)` specials, plus date patterns. The word "season" appears only in folder/art rules
  (`(?<season>^season)(-|\s)?[0]?%s[a-z]?(-poster)?$`) and `.*(?:^|[^0-9])(?<season>[0-9]+)` (folder). Editions:
  `[\{\[]edition-(.+?)[\}\]]`, stored as `edition_title`. Movies and shows live in different library types, so a
  movie library never runs TV rules.
- **Infuse** (`FCBaseTitleParser.m`, `FCSeriesTitleParser.m`): year anchored at the end `[^0-9]((?:19|20)\d{2})[\s\)\]]*$`,
  cut-after-year lookbehind `(?<=\d\d\d\d[\.\s-_\(\[])`, explicit IDs `\{(tmdb|imdb)-([a-z]*[0-9]+)\}`, parts
  `(cd|disc|disk|dvd|part|pt)(\d)`, episodes `(\d{1,2}?)x(\d{2,3})`, `^se?[\.\s-_]?([0-9]+)$` and
  `^%@[\.\s-_]*([0-9]+)$` (a localized "Season" word, anchored to the whole name). **Inference:** the anchored season
  rules are for folder names, not file names.
- **guessit 4.4.0** (run by the research worker): `Open.Season.3.2010…` → episode, title "Open", season 3 — the same
  bug as ours. Its own test needs `--type movie` for this film (`guessit/test/movies.yml:1761-1770`, "Open Season 2
  (2008)" → title "Open Season 2"). `RemoveWeakIfMovie` (`episodes.py:983-1050`) lets a year beat weak episode guesses.
- **Kodi / Jellyfin**: the user's library type decides (`VideoInfoScanner.cpp:400-444`; `MovieResolver.cs:227-235`).
  Inside a TV library both would turn `.2010.` into S20E10 (Kodi's greedy last rule; Jellyfin `NamingOptions.cs:395`);
  our pair regex (`S..E..` or `NxM`) does not have that trap. Jellyfin keeps a number before the year in the title
  ("The Wolf of Wall Street 2 (2013)", `CleanDateTimeTests.cs:14-21`).
- **Stremio video-name-parser**: series only with season *and* episode (`index.js:291-294`), else movie with a year;
  but its name stops at "season", giving "open".

### OpenStream today
`AppleLibraryTitleParser.swift:40-42` falls back to `\bSeason[ ._-]*(\d{1,3})\b` over the whole path (folders *and*
stem); `:56` makes anything with a season a show. `clean()` cuts the title at `Season\s*\d+`, giving "Open"
(`:222-229`). We have no library-type setting, so the rule has to live in the parser: **in the file stem, `Season N`
counts only next to an episode token; without one, if a year follows, it is part of a movie title.** `Season N` in a
parent folder keeps working as today.

### Lookup order, thresholds, unmatched items
- Plex: explicit IDs first, ranked title/year candidates, Fix Match on the server (10-11 / 10-14 reports). Unmatched
  items stay in the library under their cleaned file title, with no art.
- Infuse: TMDB with IDs from `{tmdb-…}` / `{imdb-…}`; "no online match" choice; local NFO/art override.
- Jellyfin: IDs from path, NFO before remote, TMDB scoring (exact title 8, prefix 4, year ±1 +2; `TmdbUtils.cs`).
- OpenStream (`AppleLibraryMetadataResolver.swift`): manual match → disk cache → per search form: TMDB/OMDb/Cinemeta by
  explicit ID (`:390-412`, fixed since 10-14) → Cinemeta + each add-on's search *in series* (`:413-437`) → TMDB title
  search with then without year (`:439-445`) → OMDb. Acceptance and miss caching are in good shape (G2, G4, G7 fixed;
  `AppleLibraryFixMatchView.swift` is reachable). Remaining: the serial add-on walk before TMDB (action 10), the serial
  first-24 eager loop (`AppleLocalLibraryStore.swift:609-613`), no NFO stage (G1), IMDb-only artwork fallback (G6).
- Artwork choice: Plex stores per-item `user_thumb_url`, `user_art_url`, `user_clear_logo_url` (logo/wordmark),
  `user_square_art_url`; Swiftfin asks logos as PNG. Ours already separates poster/backdrop/logo by purpose; the gap is
  non-IMDb items getting no fallback art.

## 3. Top 10 / chart rows

- **Netflix** (mobile APK `com.netflix.mediaclient.apk`, SHA-256 `4610837f…34db2`): the Top 10 row arrives from the
  server as one object with its own artwork. Dex strings: `LolomoTopTenRow`, `LolomoTopTenFeedRow`, `topTenEntities`,
  `TopTenVideoArtwork`, `VideoInfo$TopTenBoxart`, `imageParamsForTopTenRowBoxart`, `top10Ranking`,
  `suppressTop10Badge`, request flags `x-netflix.request.client.supportstop10`. The number is drawn by the client
  (`Top10NumberModel{drawableCreator=…}`). REA `search_android_classes(query: "TopTen")` over all 47,430 classes
  returned 0 class names (obfuscated; Evidence `ev_4eb6466a52f4f311eaeaa2094fff4d48053a846d2fb1f2b6f3782b5dea9cd17b`),
  so this rests on strings, not decompiled flow. **Inference:** Netflix never matches a chart title to artwork; the
  list and the art are the same record.
- **Public Netflix data** (`netflix.com/tudum/top10/data/*.tsv`) has titles and season titles only, no IDs or images.
  TMDB `/trending` and Cinemeta `top` give IDs and posters directly but are different charts.
- **Apple TV app / Plex:** not examined in this pass (Plex has no Top 10 row; Apple's TV app chart data is server-side).

**Why ours shows text cards** (`AppleNetflixTop10.swift`, `AppleTop10ArtworkLookup.swift`, `AppleDiscoverView.swift`):
1. The week is downloaded on every Discover load: `loadTop10()` builds a new client each time
   (`AppleDiscoverView.swift:1323`), so its 4-hour memo (`AppleNetflixTop10.swift:45`) never hits. It fetches
   `all-weeks-countries.tsv` (every week, every country) with a 45 s timeout (`:56-60`).
2. Each entry is matched first to loaded catalog items, then by add-on/Cinemeta *search* with exact normalized title
   (`AppleCatalogSearchLookup.swift:199-228`; `AppleTop10ArtworkLookup.swift:8-53`) — no TMDB, no year, no fuzzy.
   Documentary and older titles ("UNABOMBER", "A Different World", "East of Eden") often aren't in Cinemeta's search
   under the exact Netflix name.
3. Art falls back to Metahub/TMDB only for IMDb ids (`AppleCatalogArtworkPolicy.swift:71-74`;
   `AppleArtworkResolver.swift:96-98`).
4. The match lives in card `@State` (`AppleDiscoverView.swift:2560`), so every remount searches again; while it
   searches the card is `unresolved-rank-N` with no URLs (`:2585-2592`) and the title tile shows (`:2810`).

**What we should do:** actions 1, 2, 12 — make a Top 10 entry a persisted record with a TMDB id and art, as Netflix
does on its side. Use TMDB `search/tv` or `search/movie` with the title (TV: drop ": Season N"/"Limited Series"),
take an exact/alias match, prefer the newer release when ambiguous, then TMDB images by id (backdrop for the ranked
tile, logo where the tile design wants one). Store `week → [rank: tmdbID, type]` on disk so the row draws with art
from the first frame on the next launch.

## Not found / limits
- No Ghidra pass (build lock held by another lane); Infuse's matcher bodies, Plex's native match scoring and Infuse's
  display-cache sizes are unknown. Strings prove these components exist, not their timings.
- No runtime capture of Plex or Infuse; "instant" is inferred from architecture, not measured. Apple TV app charts not
  examined. Netflix chart flow is from dex strings; class names are obfuscated.
- OpenStream launch/scroll costs are source-level; actions 4, 8 and 9 need a before/after trace (`xctrace`, DevTV
  harness in `/Volumes/DevExt/dev/openstream-build/atv-slowness`).
- Nothing was copied: no code, strings or assets from Plex, Infuse or Netflix go into OpenStream; open-source rules
  above are cited for behaviour, and our parser rule is our own.
