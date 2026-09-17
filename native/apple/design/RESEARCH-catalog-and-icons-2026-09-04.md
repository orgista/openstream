# Research: Catalog Naming and Add-on Icons (2026-09-04)

## Catalog Naming (Streaming Catalogs Add-on)
The "Streaming Catalogs" add-on exposes provider-specific catalog IDs. Based on the manifest and server routes (`src/server/routes/manifest.js`), the following mappings exist:

| Catalog ID | Service Name |
|---|---|
| `nfx` | Netflix |
| `nfk` | Netflix Kids |
| `hbm` | HBO Max |
| `dnp` | Disney+ |
| `hlu` | Hulu |
| `amp` | Prime Video |
| `pmp` | Paramount+ |
| `atp` | Apple TV+ |
| `pcp`, `pct` | Peacock |
| `cru`, `fmn` | Crunchyroll |
| `jhs`, `hst` | JioHotstar |
| `zee` | Zee5 |
| `vil` | Videoland |
| `clv` | Clarovideo |
| `gop` | Globoplay |
| `hay` | Hayu |
| `nlz` | NLZIET |
| `sst` | SkyShowtime |
| `mgl` | MagellanTV |
| `cts` | Curiosity Stream |
| `cpd` | Canal+ |
| `stz` | Starz |
| `dpe` | Discovery+ |
| `mbi` | Mubi |
| `vik` | Rakuten Viki |
| `sgo` | Sky Go |
| `sonyliv` | Sony Liv |
| `mp9` | Movistar+ |
| `shd` | Shudder |
| `bbo` | BritBox |
| `act` | Acorn TV |
| `itv` | ITVX |
| `bbc` | BBC iPlayer |
| `al4` | Channel 4 |
| `crc` | Criterion Channel |
| `iqi` | iQIYI |
| `sha` | Shahid VIP |

Catalogs with the `netflix-top10-` prefix (e.g. `netflix-top10-global`, `netflix-top10-US`) also originate from this manifest and relate to Netflix. 
Any catalog ID not in this list should be considered an unknown or generic catalog and should not be parsed into a specific service name unless provided separately.

## Add-on Manifest Icons
Stremio-style manifests provide icons under two potential keys in the manifest JSON root:
1. `icon`: Often the preferred squarish or standard add-on icon.
2. `logo`: Sometimes used for banners or as an alternative to `icon`.

When parsing add-on manifests:
- Always prefer `icon` over `logo` if both are present.
- Discard URLs that do not use the `https` scheme.
- Ensure the URL length is reasonable (e.g. capped at 1024 characters) to avoid rendering issues or denial of service through oversized payloads.
