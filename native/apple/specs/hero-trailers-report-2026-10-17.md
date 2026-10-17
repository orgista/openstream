Waiting on the mini's compile lane (another project's swift test holds it); I'll pick up as soon as the gate result lands.

I'm waiting on the queued simulator runs (behind the DevTV job on the default lane).

Queued behind the iphone-jank job. I'll be notified when the runs finish.

## Done
- **1 Cycle wraps** — `AppleHeroRotationCycle.swift` — removed f82ef99's `index < count - 1` stop from `dueDate`; the last page goes back to the first.
- **2 Startup timeout (8 s)** — `AppleHomeBillboard.swift`, `AppleTrailerStartPolicy.swift` — if an autoplay trailer hasn't reported "playing" 8 s after it was asked for, the still crossfades back and the page gets a fresh dwell (new `lastFailure` → `Cycle.videoFailed`). YouTube errors take the same path. Pressed trailers keep their 30 s give-up.
- **3 Advance 1 s after a trailer ends, on every platform** — phone/pad, Mac and Vision carousels — the iPhone-only `advancesAfterVideoEnds` flag is gone; all three use `cycleEvent(after:)` → `Cycle.handle`.
- **4 Stills dwell 6 s** — `AppleHeroRotation.interval` 12 → 6.
- **5 Trailer start timed from page appear** — `AppleTrailerStartPolicy` (iPhone 0.5 s, TV 1.0 s, iPad/Mac/Vision 2.0 s). Load time counts against the delay, on the Home hero (iOS and Mac) and the title page. The fixed `sleep(2)` calls are gone.
- **6 iPhone title header** — `AppleDiscoverView.swift` — back to build 15's full-bleed header (70 % of the screen) with `AppleHomePhoneHeroFade`; sound control top-right under Search. The now-dead `exactSlot`/`slotFrame` code and its test are removed. The current art picker (`phoneSlotArtwork`) is kept.
- **9 Pressed trailers play under Low Power / video autoplay off** — new `AppleHeroTrailerGate.allowsVideo(…pressed:)`, used by the Home gate and the title page (`heroTrailer.wasPressed`). Reduce Motion still blocks.
- **10 Mute choice remembered** — `AppleTrailerSoundMemory` (UserDefaults `openstream.trailer.soundChoice.v1`). Set by the iOS hero, title page and Mac hero sound controls; autoplay stays muted until the viewer turns sound on.
- **11 Page-gate art timeout** — `AppleHeroPageGate.swift`/`AppleHeroPageSwap.swift` — art that never reports counts as settled after 8 s; a wordmark that never answered falls back to the text title.
- **12 Next-page trailer prefetch** — `AppleTrailerPlayerPrefetch.swift` (iOS/visionOS) — a hidden web view opens the next page's embed with playback blocked. All trailer web views now share one non-persistent data store so the cache carries over. Skipped under Low Power, Reduce Motion, autoplay off or AirPlay. Wired into the phone/pad and Mac carousels via `prefetchTrailer`.
- **Not touched:** item 7 (YouTube overlay) and the 4.5 s hidden start, which is part of the overlay question. No layout changes to the Home hero.

## Not done / unclear
- **Mac prefetch** is a no-op: the Mac preview has its own web view and data store.
- **Item 12 is partial:** it warms YouTube's player page and scripts, not the video stream. Holding a live paused player per page wasn't attempted (memory, and the jank lane's hero views).
- **iOS 27 shows no picture:** the E2E sim (73E49263) only has stub content with no art, so its frames show layout and dots, not images.

## Gates run
- **code-anti-slop:** removed 1 restating comment, 1 dead path (`exactSlot` + `slotFrame` + its test), 1 tautology test; folded duplicate sound-memory calls into a default argument.
- **swift test** (`--scratch-path /Volumes/DevExt/dev/openstream-build/hero-trailers-spm`, compile lane) → **pass 3482 tests / 432 suites**.
- **xcodebuild Debug, all four platforms → BUILD SUCCEEDED:**
  - iOS sim: all nine edited source files confirmed recompiled by grep.
  - tvOS sim: `AppleHeroPageGate` recompiled.
  - visionOS sim and macOS: `AppleHomeBillboard` recompiled.
- **Sim evidence (video at 1 fps)** in `dev-mini:/Volumes/DevExt/dev/openstream-build/hero-trailers/out/`:
  - **iOS 18.6, 7530ECB2, owner setup:**
    - `hero-…-113453`: the trailer ends at 63.4 s; the next page's trailer is asked for 1.6 s later (1 s advance + 0.5 s delay).
    - `title-…-113641`: full-bleed header with the fade and the trailer up from the top edge.
  - **iOS 27, 73E49263:** the app data was backed up, the public Cinemeta catalog added through `testPublicAddonManifestsInApp`, then the data restored. The plist and the live cfprefsd copy both show no Cinemeta afterwards.
    - `hero-…-113855`: per-second dot crops show each page dwelling about 6 s, going 1→5, then wrapping to 1, about three times in 80 s.
- **New regression tests:**
  - `theCycleAdvancesThroughEveryPageAndWraps` (five pages with a trailer page: visits 0,1,2,3,4,0)
  - `theLastPageWrapsASecondAfterItsTrailer`, `itAdvancesWhenDueAndWrapsFromTheLastPage`
  - `aFailedTrailerGivesTheStillAFullDwell`, `theCarouselSeesEachEndAndFailureOnce`
  - pressed-trailer gate rules, and the new `AppleTrailerStartPolicyTests` suite
- **zero-byte check** → clean.

## Diff
- **Modified:** 12 source files under `Sources/OpenStreamApple` and 4 test files (16 files, +323 / −141).
- **New:** `AppleTrailerPlayerPrefetch.swift`, `AppleTrailerStartPolicy.swift`, `AppleTrailerStartPolicyTests.swift`.
- `design/reference-apps/2026-10-17-rea-hero-trailers-disc.md` was already untracked before I started.

## Notes for the reviewer
- **Launch churn:** on iOS 18.6 the Home hero list changes three times in the first 3 s while catalogs load (Ready or Not → Jennifer's Body → Hope). With the 0.5 s delay each provisional page now asks for its trailer before being replaced. This is the iphone-jank lane's list churn; worth checking after its merge.
- **Remembered sound applies to autoplay:** `allowsSound = true` uses the `.playback` audio session, as a sound tap already did. So autoplay with remembered sound ignores the ringer switch. `AppleDiscoverView.swift` (autoplay task), `AppleHomeBillboard.swift` `startPreview`.
- **Shared data store** (`AppleTrailerPlayerPrefetch.dataStore`): trailers now share cache and cookies within a launch; it is still non-persistent.
- **Trailers hold the cycle:** a page with a trailer holds the cycle for the whole preview (up to the 45–60 s JS cap). That is existing behaviour, now followed by the 1 s advance.
- **Scratch and cleanup:** scratch is on DevExt (`hero-trailers-spm`, logs, `sim.sh`/`ios27.sh`, videos). The internal sim DerivedData folders were deleted. No Terminal or Simulator windows were opened.
