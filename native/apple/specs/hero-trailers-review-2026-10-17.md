**FIX** (2 real, 2 trivial), then ship. No ISO or SMB code is in this diff, so the block-cache and disc-budget checks do not apply; the owner's "ISOs failing" is untouched by this lane (REA items 13-16 are out of this review's scope).

1. `Sources/OpenStreamApple/AppleDiscoverView.swift:1415` — the new `prefetchHeroTrailer` was inserted between `featuredHero`'s doc comment ("Not `@ViewBuilder`: it returns one view…") and `featuredHero`, so that comment now documents the wrong function. Move the new function (and its own two-line comment) above the existing comment.

2. `Sources/OpenStreamApple/AppleHomeBillboard.swift:703` + `:725` — launch churn on the owner's device. The worker's own note: on iOS 18.6 the hero list changes three times in the first 3 s, and with the fixed 2 s sleep gone each provisional page now fetches metadata, renders a cover and opens a YouTube web view before being replaced. Three throwaway web views at launch undoes speed-round work. Fix: in `AppleDiscoverView`, add `@State heroesSettled = false` flipped by `.task(id: heroes.map(\.id)) { heroesSettled = false; try? await Task.sleep(for: .seconds(1)); if !Task.isCancelled { heroesSettled = true } }`, pass it into the billboard and add it to `shouldPreview` (`AppleHomeBillboard.swift:569`). Autoplay only; pressed trailers (`trailerRequest != nil`) bypass it.

3. `Sources/OpenStreamApple/AppleHeroRotation.swift:~168` — the "Whether a hero's timer holds still…" doc block is now separated from `cycleIsPaused` by a blank line, so it is attached to nothing. Delete the blank line.

4. `Sources/OpenStreamApple/AppleTrailerPlayerPrefetch.swift:34,54-60` — `prefetchedKey` is never cleared when the load fails, so a key that failed once is never prefetched again this session. Set `prefetchedKey = nil` in the two `didFail…` delegates before `cancel()`.

Verified correct (no change needed):
- Items 1, 3, 4: `dueDate` wraps; `cycleEvent(after:)` + `Cycle.handle` fire once per end/failure; the phone carousel renders one `AppleHomeHeroPreview` at a time (`.id(pageIDs[shown])`), so the preference merge cannot replay a stale failure. Tests cover 0→4→0 with a trailer page.
- Item 2: the 8 s timeout task is keyed on `embedURL:playerStarted`; `stop()` clears `embedURL` and `shouldPreview` does not change, so the `startPreview` task does not restart: no request/timeout loop. `lastFailure` only fires for error, autoplay-blocked and web-content-terminated, not "paused".
- Item 11: `AppleHeroPagePreload` is one view per `page.key` inside a `ForEach`, removed once ready, so `reported` cannot leak to the next page; the task cancels with the view.
- Item 9: `allowsVideo(pressed:)` used by both gates; `wasPressed` reset in the trailer-reset task.
- Item 6: full-bleed 70 % header, decoded still `scaledToFill`, poster card keeps its 16:9 card. The fade is the one approved `AppleHomePhoneHeroFade`, same as the Home hero over its video. No explainer text added.
- iOS 18 APIs fine (`Task.sleep(for:)`, two-arg `onChange`, `Date.now`). tvOS: shared 6 s interval only; the `onPreferenceChange` handle is inert there. Mac: 1 s advance after video is the intended item 3 change.
- Memory: one hidden prefetch web view at a time, torn down at 3 s after load or 10 s cap, `.all` user-action gate so it never plays. The shared `nonPersistent()` store lives for the session (WebKit-bounded in-memory cache); media buffers die with each page's view.

Notes for the owner, not fixes:
- Sound memory is global (REA item 10 as specified): one unmute on a title page makes the Home hero autoplay with sound at the next launch, through `prepareTrailerAudio(pressed: false)`. If that is unwanted, scope the memory to the title page.
- tvOS focus on the hero buttons still holds the cycle (`AppleTVHeroPaging.swift:68`); pre-existing, outside items 1-12.
- Mac prefetch is a no-op (closure is iOS/visionOS only), as the report says; the `.task` in `AppleHomeMacHeroCarousel.swift:100` is dead on macOS.
- Test slop, minor: `theDelayFollowsTheAppleTVAppPerPlatform` and the `artTimeout == .seconds(8)` / `interval == 6` lines only restate constants.
