**Verdict: FIX** (one spec gap, the rest nits). Build/test gates per the report are credible; the 513-safe Caches write path (`AppleTopShelfSnapshot.swift:288-393`) is untouched.

1. **tvOS focus after More** — `Sources/OpenStreamApple/AppleDiscViews.swift:66-78`. Pressing More removes the focused card, so the focus engine re-seeds (usually the row's first card, scrolling back to Main Feature). Spec asks for "focus-friendly on tvOS". Fix: add `@FocusState private var focusedTitleID: Int?`, put `.focused($focusedTitleID, equals: title.id)` on each title button, and in the More action set `showsMore = true; focusedTitleID = titles.more.first?.id`. Unverified on OfficePlus, so this must land before the owner tries it.

2. **Double trace** — `AppleDiscoverView.swift:3173` appends " (Blu-ray, no disc menu)" and `AppleDiscPlaybackChoice.traceLine` (`AppleDiscPlayback.swift:53-56`) appends the same explanation on the next line. Drop the suffix at 3173; the choice's line is the one the spec asked for.

3. **Comment about absent code** — `Apps/OpenStreamTopShelf/TopShelfProvider.swift:139` "// No progress bar (owner 2026-10-15…)". Delete; the doc comment on `Snapshot.Item` and the carousel comment already cover it.

4. **One-line wrapper** — `AppleDiscPlayback.swift:142` `AppleDiscTitle.rowTitles` just calls `AppleDiscTitleList(_:)`. Either delete it and call the init at `AppleDiscoverView.swift:3161` and in tests, or keep and say so; it is the only remaining use of the old name.

Checked and fine:
- **Detection order** `AppleDiscPlayback.swift:87-102, 213-216`: engine read of a local image → BDMV folder → VIDEO_TS → name tokens → size > 9 GB. BDMV over HTTP resolves by folder. A DVD named "UHD" is theoretical. 9 GB clears DVD-9 (8.54 GB). An HTTP ISO with a plain name goes `.menu` and the engine falls back to the main title (worker flagged; the engine publishes no disc kind after play, `AetherEngine.swift:527`, and `TitleInfo.name` is "Title N" for both, so nothing more to mine).
- **Titles list** `AppleDiscPlayback.swift:168-180`: id 0 leads, dedupe ±2 s + chapter count, < 120 s dropped, 6 visible + 24 More. Tests cover the 28-title trace shape and 300-playlist decoys; the decoy case with differing lengths is capped at 30, finite.
- **Carousel**: `.details` is the right style for Play + More Info with details. Deep links unchanged. No `playbackProgress` anywhere. Images only https/http without credentials, same guard as before. Series get no duration. `seen` dedupe and the image guard short-circuit identically in builder and provider. Legacy snapshots decode (test covers it).
- **12-page cap hand-copied** `TopShelfProvider.swift:120` vs `AppleTopShelfContentBuilder.carouselLimit`: the extension already mirrors `Snapshot.Item` by hand, so this follows the existing pattern; the comment at 79-81 points at the twin. Acceptable.
- **iOS/Mac/visionOS**: every menu-only affordance (Play Disc label, Skip to Movie, menu item, startsFromBeginning exclusion) moved from `isDiscTitle` to `discOffersMenu`; a Blu-ray gets a plain Play/Resume with Start from Beginning, as the spec wants. `AppleSourcesSettingsView.swift:435` keeps the default `.dvd`, which is right for the fixture.
- **UI test** `AppleTVTopShelfUITests.swift:75`: relies on PineBoard's private `top-shelf/swipe-up-affordance/label` identifier. Passed on the tvOS 27 sim; may break on a future tvOS. Not blocking.
- Zero-byte check: clean. Snapshot fields are optional `let`s, so the writer/reader stay compatible.
