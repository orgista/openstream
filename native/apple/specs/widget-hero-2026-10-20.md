# iPhone widget: edge-to-edge hero art with the wordmark overlaid (owner 2026-10-20)

Owner: "the widget for iPhone — I'd like it to look better; it works, but if someone wants to use it, the size I
put now is landscape [the medium / wide widget]; that size should be more hero, edge to edge, with the wordmark
overlaid." Branch `widget-hero` from main a2ea95d. Code: Apps/OpenStreamWidgets/OpenStreamWidgets.swift.
Load the `openstream-reference-patterns` skill (hero-apple / hero-swiftfin) and the `widgets` skill first.

Do:
1. Screenshot the current widget at every supported family on the iOS 18.6 owner sim (owner data, inside
   protected.py) and iOS 27; list what each family shows.
2. systemMedium (the wide one the owner uses) — and systemLarge if supported — becomes a hero: the title's
   landscape art (backdrop, textless when available, from the same art pipeline the app's heroes use; cached in the
   app group the widget already reads) filling the widget edge to edge (`containerBackground` with the image,
   `.contentMarginsDisabled()`), a subtle bottom gradient, the title's wordmark (logo image when the app has one,
   else the title in the app's display font) overlaid bottom-leading, and a small secondary line (e.g. "Resume ·
   38 min left" or the row it came from). Tap opens that title (existing deep link). Keep the small family's
   behaviour unless it clearly benefits from the same treatment (say what you did). Widget images must stay under
   WidgetKit's size limits (downscale on write in the app, not in the widget).
3. Respect StandBy / tinted / accented rendering modes (accented: the art hidden or desaturated as WidgetKit does,
   wordmark legible), light/dark, Dynamic Type for the secondary line.
4. Proof: screenshots of every family before/after on 18.6 and 27 (simctl widget previews or a host screen with
   the widget added), the tinted/accented mode on 27, the deep link opening the title. `swift test` (compile lane)
   if shared code changed; iOS build incl. the widget extension; code-anti-slop; zero-byte.
Dev-Mini only (scripts/mini.sh, `OPENSTREAM_MINI_DEST='~/Developer/openstream-build/lanes/widget-hero'`); FIFO
locks (three lanes share the sims — queue, never kill); never OfficePlus; mini > 12 GB free; no commits. Report:
before/after per family, change (file:line), proof paths, gates.

## Lead 2026-10-20 10:35 — use the owner's real setup, not fixtures
The owner's own setup is on Dev-Mini: `~/Developer/openstream-build/devplus/OpenStream-owner-backup.json` (an
encrypted OpenStream backup envelope, AppleBackupEnvelope / AppleConfigurationController; its password is the
`owner-*` file next to it — read it into a variable, never print it). Restore it into the app on the iOS 18.6
owner sim (7530ECB2…) inside protected.py so the sim is put back afterwards: the app's own Import path
(Settings › Backup & Sync › Import, driven by a UI test with the file placed in the sim's Files, or the
configuration controller's import entry if a DEBUG hook exists — check before adding any). Then play 1–2 titles a
few minutes so Continue Watching has entries, and the widget shows the owner's real titles and art. If import
needs anything that would touch the owner's real iCloud or the owner's real devices, stop and say so. Never copy
the backup off Dev-Mini, never into the repo, never into screenshots' names or the report.

## Fable review (2026-10-20 13:30) — FIX FIRST: apply findings 1–4 and 6; 5 optional
1. `Sources/OpenStreamApple/AppleWidgetArtwork.swift:246` — `backdropPixels = 1_024` is too small for systemLarge. On a 6.7"/6.9" iPhone the large widget is about 1092×1146 px at 3x, and `scaledToFill` of a 1024×576 backdrop upscales it roughly 2x, so the large hero will look soft, which defeats the spec's "look better" goal. 1600 on the long edge (decoded ~5.8 MB) stays comfortably under the limit; medium is fine at 1024.
2. `Sources/OpenStreamApple/AppleTopShelfSnapshot.swift:593-597` — `store.prepare` runs inline before the snapshot file is written and `notify()` fires, so on a cache miss every publish waits on up to two downloads (10 s timeout each in `AppleWidgetArtworkStore.download`) and a failed fetch is not remembered, so each later publish retries it. Either write and notify the snapshot first and rewrite once the art lands, or record failures (a tombstone file per name) so a dead URL costs one attempt.
3. `Apps/OpenStreamWidgets/OpenStreamWidgets.swift:101-110` — `entry(artwork:)` reads both hero files from the app group for every family, including systemSmall and the gallery preview, which never draw them. Gate the reads on `family != .systemSmall` (the provider already has `layout.family` in `loadedEntry`; pass it through) so the small timeline stays a single snapshot read.
4. `Apps/OpenStreamWidgets/OpenStreamWidgets.swift:185` — the secondary line is the static "Continue Watching". The spec asked for a resume cue such as remaining time, and `AppleTopShelfSnapshot.Item` already carries progress and `durationSeconds`, so a "Resume · N min left" line is available without new data. Low severity since the spec says "e.g.", but worth doing while the view is open.
5. `Sources/OpenStreamApple/AppleHeroArtworkUpgrade.swift:57-64` — `cachedArtwork` rebuilds the cache key with the same string formula as `artwork` at line 111. Factor one private `cacheKey(kind:imdbID:)` so the two cannot drift. Also note it ignores the entry's freshness, which is fine here (stale art beats none) but say so in a one-line comment.
6. `Apps/OpenStreamWidgets/OpenStreamWidgets.swift:131` — behaviour change not in the spec summary: the old small widget only had a `Link`, which WidgetKit ignores in systemSmall, so the new `.widgetURL` makes the small widget open the title for the first time. That is an improvement with the same URL, but it should be stated in the report and screenshot-proven on the small family too.
Lead: 1) backdrop 1600 px long edge; 2) write + notify the snapshot first, prepare art after and rewrite; remember
failed fetches for the session; 3) gate the hero reads on family != .systemSmall; 4) secondary line "Resume · N
min left" from the snapshot item's progress/duration (fall back to "Continue Watching"); 6) state and
screenshot-prove the small widget's tap. Then the same proofs (medium/large/small, 18.6 owner data + 27, tinted),
serial swift test, iOS build, code-anti-slop. Move design/2026-10-20-widget-hero/ to
OpenStream-lanes/evidence/widget-hero-2026-10-20/ when done. No commits.
