# Provider Lineup from a user lineup file (2026-10-22)

Owner: "How can I get the channel build up without coding it in? … I can create a file type you can put all the
channels in it and then I can upload it and oStream will recognize it … I want that function with those channels at
launch for me at least, it's okay if it's not coded in." Today `Resources/ChannelLineup/complete-us.json` (361 US
channels) ships in the app — a bundled pay-TV channel list is an App Review / rights-holder red flag. Build the design
below (from a Fable consult), then delete the bundled list. Load app-store-review-hardening, swiftui-pro,
swift-testing-pro, widgets (UTType) skills.

**3) CHANNEL LINEUP WITHOUT BUNDLING IT**
Current code: `AppleChannelLineupPresets` reads `complete-us.json` (361 channels, 6 ZIP-prefix markets, fields number/name/aliases/category/market) from `Bundle.module`; `completeUS()` is called from `AppleLiveChannelPackage.defaultPackage`, `AppleIPTV` (Complete Guide grouping, `isRegional`), `AppleCustomChannelPackage`, `AppleGuideChannelProjection`, Settings/MediaSource views; `AppleStoreCompliancePolicyTests.resourceBundleContainsChannelLineup` asserts the bundle. "Provider Lineup" (`AppleLiveChannelScope`) only means "all channels"; the lineup drives the **Complete Guide** package and numbering.

Design:
- **Format**: keep the existing JSON shape and add a header: `{"format":"ostream-lineup","version":1,"name":"Complete US","region":"US","updated":"2026-10-22","channels":[…],"markets":{…}}`. Extension `.oslineup`, exported UTType `com.orgista.openstream.lineup` conforming to `public.json`, declared in Info.plist `UTExportedTypeDeclarations` + `CFBundleDocumentTypes` (iOS/macOS/visionOS only). Decoder: unknown `version` → "newer lineup, update oStream"; missing header → treat as v1 for the owner's hand-made file.
- **Import paths**: iPhone/iPad/Mac/Vision Pro: Files/AirDrop/share sheet via the new document type (handled in `AppleAppRouter.open` for file URLs, alongside the existing `openstream://` routes) plus a "Import Lineup…" `.fileImporter` in Live settings next to the existing m3u importer in `AppleSourcesSettingsView`. Web management page (`AppleWebManagementServer`, already serves `/` and `/openstream`): add a lineup upload form (POST, 4 MB cap) with the same trust rules. URL import: a "Lineup URL" field, fetched once on demand, never auto-refreshed (no remote feature switching, 2.5.19). Apple TV: no file input, so it receives the lineup through the existing iCloud KV sync and through "Set Up from iPhone" (`AppleSetupReceiveServer`), which already carries the sealed setup; include the lineup in that payload.
- **Storage + sync**: `AppleChannelLineupStore` persists the file in the app-group container (`Lineups/<id>.oslineup`) and mirrors it into the existing `NSUbiquitousKeyValueStore` configuration (one key, 52 KB; the KV store limit is 1 MB per key, so one lineup fits; refuse files over 512 KB). Include it in the JSON backup export/import (`AppleBackupSettingsView`, `openstream-config.json`). `AppleChannelLineupPresets` becomes a façade over the store: `current` replaces `completeUS()`.
- **No lineup imported**: `AppleLiveChannelPackage.available` drops `.completeGuide` (default `.everything`), the Complete Guide group and ZIP-based local matching are hidden, `isRegional` falls back to the keyword heuristics it already has, numbering uses the playlist's own numbers. Live settings show a one-line empty state: "Import a lineup file to organise channels by number and category." No sample lineups, no download link in the app.
- **Owner's first file**: one-off script `native/apple/scripts/export-lineup.py` wraps `complete-us.json` in the header and writes `Complete US.oslineup` to the owner's iCloud Drive (the file is deleted from the repo in the same commit). Keep a copy in the owner's personal files, never on the public share or in a repo.
- **App Review safety**: the file is user data like an M3U, carries no stream URLs and no provider names; the app never fetches lineups unless the user types a URL; the document type is documented on orgista.com/openstream alongside the format spec; no remote config semantics. Update `AppleStoreCompliancePolicyTests` to assert the bundle **does not** contain any `ChannelLineup` resource.
- **Files to touch**: `AppleChannelLineupPresets.swift` (header model, store façade, remove `Bundle.module`), new `AppleChannelLineupStore.swift`, `AppleSettingsStore.swift` (`defaultPackage`, `available`), `AppleIPTV.swift`, `AppleCustomChannelPackage.swift`, `AppleGuideChannelProjection.swift`, `AppleLiveChannelSnapshot.swift`, `AppleSettingsViews.swift` + `AppleMediaSourceViews.swift` (empty state, import button), `AppleSourcesSettingsView.swift` (fileImporter), `AppleAppRouter.swift` + `OpenStreamApps.swift` (file URL open), `AppleWebManagementServer.swift`, `AppleSetupTransferServer.swift`/sender, `AppleConfigurationController.swift` + `AppleBackupSettingsView.swift` (sync/backup), `Apps/Shared/Info.plist` (UTI, document type), `Package.swift` (drop the resource), delete `Resources/ChannelLineup/complete-us.json`, tests: `AppleChannelLineupPresetsTests` (load from a fixture path), `AppleStoreCompliancePolicyTests`, new store/sync/empty-state tests, `check-appstore-compliance.sh` (fail if a lineup resource is in any product). Order: store + format + tests, then UI import, then sync/tvOS, then delete the resource and ship with 19 only if the owner's file is already imported on his devices.


## Extra requirements
- The owner's first file: write `scripts/export-lineup.py` that wraps the current complete-us.json in the header and
  writes `Complete US.oslineup`; RUN it once and put the output at dev-mini
  `/Volumes/DevExt/dev/openstream-build/owner-lineup/Complete US.oslineup` (NOT in the repo, NOT on a public share);
  then delete complete-us.json from the repo in the same change.
- Prove the owner path end to end on the iOS 18.6 owner sim (protected.py): import the file via the Files importer and
  via the web management upload; Live shows the Complete Guide with the same numbering/categories as before; a
  relaunch keeps it; the iCloud/backup copy carries it. tvOS sim: receives it via the setup payload or iCloud path you
  implement (prove one).
- No lineup imported: Complete Guide hidden, playlist's own numbers/groups, the one-line empty state only.
- `check-appstore-compliance.sh` fails if any lineup resource is in a product; `AppleStoreCompliancePolicyTests`
  asserts it is absent.
Rules: Dev-Mini only (`scripts/mini.sh`, `OPENSTREAM_MINI_DEST='~/Developer/openstream-build/lanes/lineup-file'`), own
sim DerivedData `~/Developer/sim-dd-lineup`, FIFO locks (queue, never kill), owner-data sims only via protected.py,
never Anthony/OfficePlus, internal disk > 15 GB, no commits. Gates: serial swift test; check-appstore-compliance.sh
--build; iOS 18.6 Live UI tests + the import flows; tvOS smoke; code-anti-slop; zero-byte. Report per AGENTS.md §7.

## Round 2 (lead, 16:40): API review — fix first. Your work is uncommitted here. Bounded ~90 min.
1. Keep scripts/export-lineup.py in the tree (it must be in the commit) — confirm.
2. Info.plist preprocessing: build iOS/tvOS/macOS/visionOS and `plutil -lint` each processed Info.plist; UTI +
   document type present on iOS/macOS/visionOS, absent on tvOS. If `#include`/`#if` preprocessing is fragile, use
   per-platform plist entries the project already supports instead.
3. Erase All / device reset must delete the stored lineup (production wipe list includes the lineup directory and the
   fallback path); test against the production list.
4. Move `.fileImporter`/`.alert`/`.onReceive`/`.onDisappear` off the `Section` onto one container (no per-row copies; no
   import cancelled by a row scrolling off).
5. Read `version` first → unsupported version error for != 1, then validate keys (test v2 + extra key).
6. Sync size: guard/compress so a max-size lineup cannot push the iCloud KV snapshot over 1 MB or break the setup
   transfer; test with a max-size file; lower the cap if needed.
7. Revert adding "local" to `regionalIndicators` (no change to heuristics for everyone) and restore the test.
8. Unit tests use the fixture only (not OPENSTREAM_LINEUP_FILE).
9. Restore the deleted unrelated comments; `importData` rewrites the file when the on-disk copy is missing.
Gates as before (serial swift test; 8 builds + compliance; iOS 18.6 import flows via protected.py; tvOS receive).
