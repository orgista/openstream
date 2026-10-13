# Plex 7/8 Stage A build spec: identity alias table and logical ids (Codex, 2026-10-13)

Source: `design/plex-7-8-design-2026-10-13.md` §2, §3.1 (corrected 2026-10-13, read §3.1.1 for the holes it fixes), §5
and §6 "Stage A". Read `native/apple/AGENTS.md` and the workspace `AGENTS.md` ("Apple builds and tests run on the Mac
mini", the concurrency gate, "Clean up after yourself") first. Paths below are relative to `native/apple/`; `S/` is
`Sources/OpenStreamApple/`, `T/` is `Tests/OpenStreamAppleTests/`.

Stage A is **strictly additive**: one new blob, new read paths, no key moved, no value rewritten, no snapshot change,
no index change. An older build must read the same data after a downgrade. None of the owner questions in the design's
§7 apply to this stage; if you find you need one, stop and report instead of guessing.

## 1. What to build

### 1.1 New file `S/AppleLogicalItemKey.swift` (pure, `public enum AppleLogicalItemKey`)
The §2 key builder, used in Stage A only as the class label for local files. Deterministic, lowercases ids.
```
static func title(kind: AppleMediaKind, imdb: String?, tmdb: String?) -> String?      // "li:movie:tt0903747" | "li:series:tmdb:1396"; nil when both ids are nil
static func episode(seriesKey: String, season: Int, episode: Int) -> String             // seriesKey + ":1:2"
static func localFileClass(titleKey: String, season: Int?, episode: Int?, sizeBytes: Int64) -> String?
                                                                                       // titleKey [+ ":S:E"] + ":" + sizeBytes; nil when sizeBytes <= 0
static func legacyEpisodeClass(fileEpisodeID: String) -> String                        // "le:" + fileEpisodeID
```
Nothing in Stage A writes a `li:` key into any playback blob.

### 1.2 New file `S/AppleIdentityAliasStore.swift`
```
struct AppleIdentityAliasTable: Codable, Equatable, Sendable {            // the blob's JSON: {"v":1,"classes":{"<classID>":["sha256:…", …]}}
    static let version = 1
    var classes: [String: [String]]                                        // classID -> sorted, de-duplicated member storage keys
    func members(of storageKey: String) -> [String]                        // [storageKey] when unknown; else the class with storageKey first, rest sorted
    func classID(of storageKey: String) -> String?
    mutating func record(classID: String, members: [String]) -> Bool       // union; never removes; returns whether anything changed
}

@MainActor final class AppleIdentityAliasStore {
    static let enabledKey = "openstream.identity.aliases.enabled"          // absent = on; `false` = every read answers as if the blob were empty
    init(defaults: UserDefaults = .standard, namespace: String = AppleTasteNamespace.local, blobDirectory: URL? = nil)
    var isEnabled: Bool                                                    // defaults.object(forKey: enabledKey) as? Bool ?? true
    var blobData: Data?                                                    // the raw blob for fingerprints (nil when absent)
    func members(of storageKey: String) -> [String]                        // [storageKey] when disabled, absent, malformed or unknown
    func record(classID: String, members: [String])                       // only member keys that pass ApplePlaybackIdentity.isStorageKey; persists only on change
}
```
- Blob key: `AppleTasteNamespace.key("openstream.identity.aliases.v1", namespace:)`, read and written through
  `ApplePlaybackBlobStorage.storage(defaults:directory:)` exactly like `ApplePlaybackStore` (`S/ApplePlaybackStore.swift:203–205`),
  so tvOS keeps it in defaults, iOS/macOS in the app-group `PlaybackState-v1` directory, and the device reset wipes it.
- Decode once per distinct blob data (compare `Data`, N47 style); keep `[member: classID]` alongside the table.
- A malformed blob reads as empty and is **not** rewritten. `record` on a malformed blob replaces it.
- Class ids are opaque strings; members must be `sha256:` storage keys (reject anything else, trace once).

### 1.3 New pure type `AppleIdentityAliasResolution` (put it in `S/AppleIdentityAliasStore.swift`)
Static functions over the maps the store already holds. Each takes the class's keys (first = the asked key).
```
static func progress(keys: [String], in map: [String: ApplePlaybackProgress]) -> ApplePlaybackProgress?    // ApplePlaybackConvergence.freshest over present entries
static func history(keys: [String], watched: [String: Date], tombstones: [String: Date]) -> (watched: Date?, tombstone: Date?)
                                                                                                           // AppleWatchedHistory.merge of every class entry, then that history's answer for the class
static func terminals(keys: [String], in map: [String: ApplePlaybackTerminalEvents]) -> ApplePlaybackTerminalEvents?   // .merging over present entries
static func latestDate(keys: [String], in map: [String: Date]) -> Date?                                     // max
```

### 1.4 `S/ApplePlaybackStore.swift` — read paths and clocks only
- Add `private let aliases: AppleIdentityAliasStore` built in `init` from the same `defaults`, `namespace`, `blobDirectory`.
- Add `private func classKeys(_ storageKey: String) -> [String] { aliases.members(of: storageKey) }`.
- `derivedStateFingerprint()` (`:764–766`) appends `aliases.blobData`.
- Rewire these **public lookups** to resolve over `classKeys`, nothing else:
  - `progress(for mediaID:)` (`:299–302`): `AppleIdentityAliasResolution.progress(keys:in: entries())`.
  - `lastActivity(for:)` (`:246–254`): freshest over class of `entries()` and `activities()`; then `activityIsCurrent` with a
    terminals map whose entry for the asked key is the class-merged terminal (copy the map, replace one key).
  - `completedMediaIDs(among:progress:)` (`:319–337`): per media id, `history(keys:…)` for the tick and tombstone,
    `terminals(keys:…)?.resetAt` for the reset, and "any class entry in `all` is complete" for the progress clause. The
    `#if DEBUG` fixture branch stays on the single key.
  - `isRemovedFromContinueWatching` (`:399–405`): `removedAt` = class-merged terminal's `removedAt`; `lastPlayedAt` = max
    over the class of activity/progress `updatedAt` and `playedAt`.
  - `hasLocalPlaybackState` (`:768–771`): any key of the class.
  - `localPlaybackUpdatedAt` (`:792–797`): max over the class. (`nextLocalEventDate` becomes class-aware through it.)
  - `save(storageKey:…)` (`:440–445`): `clocks` gathers terminals for every class key of `storageKey` plus the part key.
- Leave **raw** (no class merge): `entries()`, `rawActivities()`, `activities()`, `storedWatched*`, `continueWatchingRemovals()`,
  `savedProgress()`, `completionProgress()`, every `configuration*()` and `restore*()` function, `migrateLegacyPlaybackStateIfNeeded`.
  These feed the snapshot, iCloud and backups; their output must not change (test §3.4).
- Writes: unchanged. `save`, `clear`, `markWatched`, `markUnwatched`, `removeFromContinueWatching`, `recordEpisodes` keep
  writing the caller's storage key only.
- Add `func recordIdentityAlias(classID: String, mediaIDs: [String])` → maps each id with `ApplePlaybackIdentity.storageKey(for:)`,
  calls `aliases.record`. This is the only writer the rest of the app uses.

### 1.5 `S/AppleLocalLibraryStore.swift` — the two alias writers
- `AppleLibraryMetadataResolver` (actor) gains
  `func strongMatchIDs(for item: AppleLibraryItem) -> (kind: AppleMediaKind, imdb: String?, tmdb: String?)?`:
  the group's `MatchRecord` when `isManual || confidence >= 0.95` (`S/AppleLibraryMetadataResolver.swift:169–170`),
  ids from `explicitIDs["imdb"]` / `["tmdb"]`, kind from `candidate.type`. Nil otherwise. Read-only.
- New `private func recordIdentityAliases(for group: AppleLibrarySeries) async` in the local store, called at the end of
  `resolve(_:sourceStore:settings:refresh:)` (`:299`) and once per group after the snapshot load path that fills
  `metadata`. For each `file` in `group.items` where `AppleLibraryTitleParser.parse(file).role == .feature`,
  `offlineIDs[file.id] == nil`, `file.sizeBytes > 0`, and `strongMatchIDs` is non-nil:
  `titleKey = AppleLogicalItemKey.title(kind:imdb:tmdb:)`; `classID = localFileClass(titleKey:, season: parsed.season,
  episode: parsed.episodeNumbers.first, sizeBytes:)`; `store.recordIdentityAlias(classID:, mediaIDs: [playbackID(file)])`.
  Dedupe per launch (`Set<String>` of recorded file ids) so a redraw never re-encodes the blob.
- `completedEpisodeIDs` (`:566–597`): after `aliases` is computed (`:572–580`), call
  `store.recordIdentityAlias(classID: AppleLogicalItemKey.legacyEpisodeClass(fileEpisodeID: current), mediaIDs: [current, legacy])`
  for each pair. **Keep the rest of the function exactly as it is** (Stage E retires it).

### 1.6 Not in Stage A (do not do these)
No change to `AppleMediaRecord`/`media-index-v1.json`, `AppleConfigurationSnapshot`, `AppleBackupEnvelope`,
`AppleConfigurationController`, `AppleConfigurationSyncPolicy`, `AppleRemoteProgressOutbox`, match records, `ApplePlexItem`,
`AppleMediaServerLibraryStore`, any view, any `#if os(tvOS)` file. No writes to a `li:` key. No alias for catalog titles,
media-server items or downloads. No merging of two copies of a title (the class carries `sizeBytes` for that reason).

## 2. Order of work (each step gate-green before the next; nothing runs at upgrade time)
1. `AppleLogicalItemKey` + `AppleIdentityAliasTable` + `AppleIdentityAliasResolution` with their tests (§3.1–3.2).
2. `AppleIdentityAliasStore` blob + fingerprint wiring + tests (§3.3).
3. `ApplePlaybackStore` read paths and clocks + the parametrised tests (§3.4). Run the whole suite here: every existing
   playback/convergence/snapshot test must still pass with the blob absent.
4. Snapshot byte-identity test (§3.5).
5. Writers in `AppleLocalLibraryStore` + resolver accessor + tests (§3.6).
6. Flag off ⇒ raw behaviour test (§3.7). Then the full gate (§4).

There is **no data migration**: the table starts empty and fills as the library resolves. A file renamed before Stage A
shipped stays unlinked (design §3.1, last paragraph) — do not try to recover old keys.

## 3. Unit tests (Swift Testing, `@Suite`/`@Test`/`#expect`; fixtures only, no network, no simulator)
Where a case says "both", use `@Test(arguments: [false, true])` for `aliasBlobPresent`; with `false` the store must answer
exactly as today (same values, same `Data` on disk after the same calls).

### 3.1 `T/AppleLogicalItemKeyTests.swift`
- `titleKeyPrefersIMDbLowercasesAndFallsBackToTMDb`: `("TT0903747", tmdb "1396")` → `li:series:tt0903747`; imdb nil → `li:series:tmdb:1396`; both nil → nil.
- `episodeKeyAppendsSeasonAndEpisode`: `episode("li:series:tt1", 1, 2)` == `li:series:tt1:1:2`.
- `localFileClassNeedsPositiveSize`: size 0 → nil; `(titleKey, nil, nil, 734003200)` == `li:movie:tt1:734003200`; `(titleKey, 1, 2, n)` == `li:series:tt1:1:2:n`.
- `legacyEpisodeClassIsPrefixed`: `le:` + id.

### 3.2 `T/AppleIdentityAliasTableTests.swift`
- `roundTripIsStableAndSorted`: encode → decode equals; members sorted; duplicates collapsed; `v` == 1.
- `membersOfUnknownKeyIsItself`; `membersPutsAskedKeyFirst`.
- `recordIsUnionAndNeverRemoves`: recording a subset returns `false` and changes nothing; a new member returns `true`.
- `resolutionProgressIsFreshestOverClass` / `resolutionHistoryAppliesMergeRules` (tombstone later than every watched date
  → unwatched; watched later than tombstone → watched) / `resolutionTerminalsMerge` / `resolutionLatestDate`.

### 3.3 `T/AppleIdentityAliasStoreTests.swift` (temp `UserDefaults(suiteName:)` + temp directory, like `ApplePlaybackBlobStorageTests`)
- `blobKeyIsNamespacedAndStoredThroughBlobStorage`: after `record`, `ApplePlaybackBlobStorage(...).data(forKey: AppleTasteNamespace.key("openstream.identity.aliases.v1", namespace: ns))` decodes to the table; defaults-only (tvOS-shaped, `directory: nil`) and directory-backed both pass.
- `malformedBlobReadsEmptyAndIsNotRewritten`: write `"nope"` under the key; `members(of:)` returns `[key]`; the stored bytes are unchanged after ten reads.
- `recordRejectsNonStorageKeys`: a member `"tt0903747"` is dropped; `"sha256:" + 64 hex` is kept.
- `disabledFlagAnswersRaw`: set `enabledKey` false → `members(of:)` is `[key]` though the blob has a class; `blobData` still returns the bytes (fingerprint stays honest).
- `recordPersistsOnlyOnChange`: same `record` twice → the blob `Data` is identical and the file mtime unchanged.

### 3.4 `T/ApplePlaybackStoreAliasTests.swift` (both)
Fixture: old key `O = storageKey("library-old")`, new key `N = storageKey("library-new")`, class `c` = {N, O}.
- `renamedFileResumesFromOldKey`: `save(mediaID: old, 600/3600)` → alias → `progress(for: new)?.position == 600`; with the blob absent → nil.
- `saveWritesOnlyTheAskedKey`: `save(new, 900/3600)` → raw `configurationProgress()[N]?.position == 900`, `[O]?.position == 600` (old entry bytes unchanged); `progress(for: old)` is 900 with the blob (freshest), 600 without.
- `unwatchHidesTheOldKeysTick`: `markWatched(old)` → `isWatched(new)` true (blob) / false (none); `markUnwatched(new)` → `isWatched(new)` false and `isWatched(old)` false (blob); the tombstone date under N is later than every date under O (read raw maps).
- `unwatchClockBeatsAFutureOldWatchedDate`: `markWatched(old, at: now + 3600)` → `markUnwatched(new)` → `isWatched(new)` false (the class clock advanced past the skewed date).
- `removalHonoursTheOldKeyAndALaterSaveLiftsIt`: `removeFromContinueWatching(old)` → `isRemovedFromContinueWatching(new)` true (blob); `save(new, …)` → false; raw `continueWatchingRemoved.v1` still holds O.
- `lastActivityAndHasStateSeeTheClass`: `lastActivity(for: new)` returns O's activity; `hasLocalPlaybackState(new)` true; absent → nil/false.
- `completedMediaIDsAgreesWithLegacyEpisodeLookup`: build a show group fixture with one numbered and one filename row; mark the legacy positional id watched; assert `AppleLocalLibraryStore.completedEpisodeIDs(...)` == `store.completedMediaIDs(among: rows)` once the `le:` class is recorded (the function and the alias path give the same set).
- `partIDResolvesThroughTheClass`: a show entry under `S` with `partID = "tt1:1:2"`; alias the part's storage key to a renamed episode key; `completedMediaIDs` for the renamed id sees the completion.
- `rawAccessorsNeverMerge`: with the class recorded and state under both keys, `configurationProgress()`, `configurationWatchedHistory()`, `configurationWatchedTombstones()`, `configurationContinueWatchingRemovals()`, `configurationPlaybackTerminals()`, `configurationPlaybackActivity()`, `savedProgress()` equal the same calls on a store built over a copy of the same blobs with the alias blob deleted.
- `fingerprintIncludesTheAliasBlob`: call `configurationPlaybackTerminals()`, then `recordIdentityAlias` in the same store, then `isRemovedFromContinueWatching(new)` must see O's removal (no stale cache).

### 3.5 `T/AppleConfigurationSnapshotTests.swift` (add one case)
- `aliasBlobDoesNotChangeTheSnapshot`: build a controller-free snapshot from a store the way `capture()` does
  (`S/AppleConfigurationController.swift:426–437`) with and without the alias blob; `AppleConfigurationSnapshot.encoder.encode`
  gives identical bytes; `AppleConfigurationSyncPolicy.contentDiffers` is false; a decode of either has no extra keys.

### 3.6 `T/AppleLocalLibraryAliasTests.swift` (resolver with an injected `lookup`, temp match directory; existing fixtures in `AppleLocalLibraryTests`)
- `strongMatchRecordsOneClassPerFile`: manual match `tt0903747` for `Show.S01E01.mkv` (size 734003200) → the store's alias table has class `li:series:tt0903747:1:1:734003200` with the file's record key.
- `renamedFileJoinsTheSameClass`: same size, new relative path → the class now has two members; `continueWatching` lists the group after progress was saved under the old record id.
- `weakMatchRecordsNothing`: a 0.6 match (year mismatch) → table empty. `noMatchRecordsNothing`.
- `twoCopiesStaySeparate`: two files of one dated film with different sizes → two classes, one member each; progress saved on one is not reported on the other.
- `extrasDownloadsAndZeroSizeRecordNothing`.
- `strongMatchIDsReadsOnly`: calling it never creates or rewrites a match file.

### 3.7 `T/AppleIdentityAliasRollbackTests.swift`
- `flagOffReadsAsToday` and `deletedBlobReadsAsToday`: after the §3.4 fixture, set the flag false (or remove the blob key through `ApplePlaybackBlobStorage.removeObject`) → every public lookup equals the blob-absent answers and no blob except the alias blob differs from the pre-alias copy.

## 4. Gate
1. Concurrency gate first (workspace AGENTS.md): on Dev-Mini `cat ~/Developer/.build.lock/owner` and
   `pgrep -fl 'xcodebuild|qemu-system|emulator|gradle|swift-build|swift-test'`. If another project is running, wait as the rule says.
2. Serial SwiftPM suite, before and after your change, through `scripts/mini.sh` (it syncs the tree and takes the build lock):
   ```
   scripts/mini.sh 'swift test --no-parallel --scratch-path ~/Developer/openstream-build/spm 2>&1 | tail -30'
   ```
   Baseline 2026-10-13: `Test run with 3223 tests in 401 suites passed`. After: the same line with N ≥ 3223 + your tests and
   M ≥ 401 + your suites, zero failures. Grep the full log for `Test run with|error:|Expectation failed|freed pointer`.
   The SMB rules in native AGENTS.md §2 apply: `touch` every edited file, wait, then run.
3. App builds on the mini, one at a time, internal DerivedData for simulators:
   ```
   scripts/mini.sh 'cd Apps && xcodebuild -project OpenStreamApps.xcodeproj -scheme "OpenStream tvOS" -destination "id=B251C620-E3AD-4F9E-9911-EF8CBA6C7353" -derivedDataPath $HOME/Developer/sim-dd-internal build 2>&1 | tail -5'
   scripts/mini.sh 'cd Apps && xcodebuild -project OpenStreamApps.xcodeproj -scheme "OpenStream iOS"  -destination "id=6A037503-AF3A-4A22-B900-CF6573B15FB1" -derivedDataPath $HOME/Developer/sim-dd-internal build 2>&1 | tail -5'
   ```
   If `xcrun simctl list devices` on the mini does not show those ids, use `-destination "generic/platform=tvOS Simulator"` /
   `"generic/platform=iOS Simulator"` and say so. Prove recompilation of every edited file with the `SwiftCompile … Compiling` grep
   from native AGENTS.md §2; "BUILD SUCCEEDED" alone is not proof.
4. `find Sources Tests Apps -name "*.swift" -size 0` prints nothing.
5. Do not boot a simulator or the device for this stage; there is nothing to look at. No E2E run needed (no UI change).

## 5. Rules
- **No commits**, no `git add`/stash/checkout/reset (the lead commits). No builds or tests on the Studio.
- Edit only: the four new files, `S/ApplePlaybackStore.swift`, `S/AppleLocalLibraryStore.swift`,
  `S/AppleLibraryMetadataResolver.swift` (one read-only accessor), the test files in §3. Nothing else, no markdown.
- Never print storage keys next to titles or paths in traces; the existing `progress save key=…` line format is the model.
- Clean up after yourself on the mini: nothing left running, no extra DerivedData directory.
- Report in the native AGENTS.md §7 format, with the before/after `Test run with` lines verbatim and the recompile greps.

## 6. Rollback
Stage A moves nothing, so rollback is the diff reversal: revert the source changes and the app reads exactly what it read
before, because every existing blob was written by the same code with the same keys. Field rollback without a build:
set `openstream.identity.aliases.enabled` to `false` (every lookup answers raw) or delete the
`openstream.identity.aliases.v1` blob; the table is rebuilt from the library's match records on the next resolve, so
deleting it loses nothing permanent except links for files renamed while it was gone. A downgrade to an older build needs
no step: that build ignores the one new blob and reads its own keys.
