# Unmatched titles and fixing a match: Infuse, Plex, Jellyfin

Static check, 2026-10-16, for the library "Unmatched" work. Targets: Infuse 8.5.6 and Plex desktop 1.115 (web client
4.160.0) on Dev-Mini, plus public docs. Nothing was launched, no build-lock work ran, and no code, long strings or art
were copied. Builds on `2026-10-14-metadata-artwork.md` (Infuse/Plex/Jellyfin sections) and
`2026-10-16-speed-and-metadata-rea.md` ("Lookup order, thresholds, unmatched items").

## Infuse

- **Where it lives.** Edit Metadata is on the title's detail page. Most platforms put it in the "…" menu at the top
  right. On Apple TV it sits next to Play. ([Fixing Mismatched Titles](https://support.firecore.com/hc/en-us/articles/4405035033495-Fixing-Mismatched-Titles))
- **Flow.** It opens a list of candidate matches, and you pick one. If the right title isn't listed, you search by name.
  For TV you fix one episode, and Infuse rematches the rest of the show (same article). Strings: `tiReloadMeta`
  "Edit Metadata", `tiReloadSearch` "Search", `tiSearchMetadata` "Search metadata"
  (`Infuse.app/Contents/Resources/en.lproj/Localizable.strings` lines 882–883, 904).
- **No online match.** `tiEmbeddedMetadata` "None - use embedded metadata" (line 884) is the "don't match this online"
  choice. It falls back to the file's own tags. The empty and error states are `tiNothingFoundTitle/Message` "Nothing
  Found" / "No matches found for this file." (887–888) and `tiNetworkErrorTitle/Message` (885–886). So a network
  failure has its own state and is never reported as "nothing found".
- **IDs and year.** The help page doesn't mention ID or year entry in the sheet. IDs are documented in filenames
  (`{tmdb-…}`, `{imdb-…}`; [Metadata 101](https://support.firecore.com/hc/en-us/articles/215090947-Metadata-101)).
  Artwork follows the chosen match. Local art and NFO files can override it
  ([Overrides](https://support.firecore.com/hc/en-us/articles/4405042929559-Overriding-Artwork-and-Metadata)).
- **Unmatched shelf.** None that we can find. The strings file has no "unmatched" key (grep 2026-10-16), and the
  help pages describe no such row. Infuse fixes titles one at a time from the detail page. We found no documented
  "revert to automatic" step. Folder-level "Use Online Metadata" / "Use Local Metadata" exist (lines 552–556).

## Plex

- **Match vs Fix Match.** The same dialog is titled "Match" when the item's guid is `com.plexapp.agents.none://`
  (an unmatched item) and "Fix Match" otherwise. Evidence: `main-8792-…-plex-4.160.0-75ddd7b.js` byte ~765258. On
  open it searches automatically (`manual:1`, ~763046). The more-actions menu shows "Fix Match…", "Match…" and
  "Unmatch" behind `isFixMatchVisible` / `isMatchVisible` / `isUnmatchVisible` (~1563106, ~1572062–1572211).
- **Unmatch** is its own action (`metadata/unmatchMetadataItem`, ~771563; executes `unmatch`, ~775428). It sends the
  item back to the unmatched state.
- **Finding unmatched items.** `unmatched` is a boolean library filter key, alongside `unwatched` and `duplicate`
  (`chunk-2641-…js` byte ~6723). It's a filter on the library, not a shelf on Home.
- **Search.** The search options are title, year and language. An exact ID typed into the title field also works:
  `imdb-tt…` for films, `tvdb-…` or `tmdb-…` for shows. TV shows are fixed at the show level only. Picking a result
  downloads its metadata and art. ([Fix Match](https://support.plex.tv/articles/201018497-fix-match-match/))

## Jellyfin

- **Identify** (web `components/itemidentifier/itemidentifier.js:42–70`) collects a name, a year and per-provider ID
  fields. Search results are shown as cards, and choosing one applies it (`:259–279`). A "replace existing images"
  option controls whether the new match's art replaces the current art. NFO files and IDs in the path are read
  before any remote search (see the 10-14 page). Source: jellyfin-web e7a146f.

## What all three share

Fixing happens per title, from the title's own menu. You can search by name and year, and Plex and Jellyfin also
take an exact ID. You pick one result, and its art replaces the current art. Plex alone has an explicit Unmatch, and
it finds unmatched items with a library filter rather than a shelf. None of the three has a multi-select fix flow.

## What OpenStream does

- **Library "Unmatched" shelf.** It shows only when at least one title has a cached *no-match* result. A lookup
  that failed because the provider was unreachable doesn't count, the same split Infuse makes between "Nothing
  Found" and "Network Error". The shelf disappears once nothing is left in it.
- **Tap an item** to open the existing Fix Match sheet (`Sources/OpenStreamApple/AppleLibraryFixMatchView.swift`).
  You search by name and year or paste an ID, then pick a result. The choice is saved as a durable manual
  correction, which always wins over automatic lookups, and the new art appears at once.
- **Matched titles** get "Change Metadata", which opens the same sheet. They also get "Use Automatic Match", which
  removes the manual correction and lets the normal lookup run again. This is like Plex's Unmatch followed by a
  rematch.
- **Not in this pass:** fixing several titles at once (multi-select), and a "no online match / use the file name"
  choice like Infuse's "None".
