All three parts of the spec are coded. Nothing has been built or tested yet: another project's E2E run holds the Dev-Mini build lock (it started at 16:22, should finish around 17:05). A background watcher will tell me when the lock frees, and I'll check again at 17:11 either way. Then I'll run the Swift suite, the tvOS and iOS builds, and the E2E Top Shelf and disc tests.

One thing to flag now: installing a dev build on OfficePlus or DevTV probably isn't possible for me. There's no Apple Development signing identity on the mini, and the ad-hoc route needs `-exportArchive`, which AGENTS.md doesn't allow agents to run. Unless I find another way, the shelf screenshot will come from the Apple TV simulator.

Dev-Mini is still busy, so I haven't run any gates yet. The other project's E2E run is still on its iOS phase (49 minutes in), and the apple-devices lane has a `swift test` queued behind it. I can't estimate when it will finish, so I'll check again at 17:32. The code for all three parts is written but not built or tested yet.

The lock freed, so the Swift test gate is now running on Dev-Mini, queued through `buildlock.sh`. I'll pick up the result when it finishes.

No gates have run yet. When the build lock freed, I started the Swift test gate, but it never reached the mini: Dev-Mini answers ping and has port 22 open, yet its SSH server resets every connection before login. Network latency to it is also high, which points to the machine being overloaded.

A background watcher is retrying SSH every 30 seconds. When it gets through, I'll check the build lock again and start the gate (Swift suite, then the tvOS and iOS builds, then the E2E Top Shelf and disc tests). The code for all three parts is written, but none of it has been compiled or tested yet.

Dev-Mini is still locked by the other E2E run, so no gates have run yet.

- **Lock watcher:** the old watcher fired early because SSH was failing, not because the lock was released. I replaced it with one that only fires when it can actually see the lock is free.
- **Anti-slop pass:** I made the owner's anti-slop pass over my diff. It removed one unused property on the disc start choice (along with the two test lines that checked it) and one comment that only repeated the code.

When the lock frees, I'll run the Swift suite, then the tvOS and iOS builds with the recompile checks, then the E2E Top Shelf and disc tests.

My Swift test gate is now queued on Dev-Mini behind the OpenQR/oDisk job, which took the lock at 17:24. If `buildlock.sh` gives up after its 20-minute wait, the command re-queues itself up to four times.

There's one flaw in that retry loop: it also re-queues when tests actually fail. If the first result shows a failure, I'll stop the loop and fix the code rather than let it re-run. I'll pick up the result when it finishes.

That notification is just the old lock watcher, which I shut down on purpose. The Swift test gate is still queued on Dev-Mini behind the OpenQR/oDisk job, and I'll report when it finishes.

The first Swift test run reached the mini and everything compiled. There were three failures:

- **My two Top Shelf carousel assertions:** the running time was correct (5,880 s), but the test compared it against the expression `98 * 60`, which didn't compare as the number 5,880. I changed it to the literal `5_880`.
- **A Mac captions test** (`choosingALanguageSurvivesRediscoveryAndLateAddonSubtitles`) hit its 60-second limit. It plays a real media fixture, and none of my changes touch captions, so I think it's a load-related timeout rather than a bug. The next run will show whether it repeats.

I've queued one job with the Swift suite, then the tvOS and iOS simulator builds and the checks that my files were recompiled. It's waiting behind the Stage B E2E run, which took the lock at 18:12, and it re-queues only when the lock wait times out. The E2E Top Shelf and disc UI tests come after that.

The tvOS and iOS simulator builds both succeeded, and the logs confirm every file I changed was recompiled. In the second full Swift test run, all of my disc and Top Shelf tests passed, but five tests elsewhere failed:

- a local playback server test, where the connection dropped;
- three checks in the add-on logo refresh test;
- a Mac captions test that hit its 60-second limit.

None of these touch files I changed, and the set of failures differed from the first run. That makes me think they're unreliable or slowed by load on the mini rather than broken by this work, but I haven't shown that yet.

I've queued one job on Dev-Mini that settles it and covers the remaining E2E checks:
- **Re-run:** those three failing suites again, alongside my disc and Top Shelf suites.
- **tvOS E2E:** the Top Shelf test and the four DVD menu tests (Play Disc and Skip to Movie on both test discs).

I'll report the results, with the shelf screenshot, when it finishes.

The DVD menu E2E tests passed. The Top Shelf E2E test failed, but only because of what it was looking for:

- **Not a code problem:** in carousel mode, tvOS doesn't expose the "Continue Watching" / "Top Picks" labels to accessibility. It does expose the item titles and its own "Swipe up for full screen" affordance, and both are on screen.
- **Test fix:** I changed the test to require the carousel affordance plus a stub title. The re-run of just that test is queued on Dev-Mini.
- **Black backdrop is expected on the simulator:** the stub items' artwork points at `fixture.example`, which can't load there. A screenshot with real full-screen art needs real catalog data on a simulator or an Apple TV.

The mobile MCP can't see the Apple TVs, so once the build is installed on OfficePlus I'll have no remote way to screenshot its shelf. Waiting for the device build and install to finish.

OfficePlus is asleep ("foreground app launch forbidden"), so the install went through but I can't launch the app or look at the shelf. Writing the report.

## Done
- **Blu-ray: no menu promise** — `AppleDiscPlayback.swift`, `AppleDiscoverView.swift`, `AppleLocalLibraryStore.swift`, `AppleLocalFileInspection.swift` (3 lines there).
  - A new `AppleDiscFormat` (DVD or Blu-ray) is decided in this order: the engine's own read of a local file, then a `BDMV` folder, then a Blu-ray release name (BLURAY, UHD, BD50 and similar), then a size over 9 GB.
  - On a Blu-ray, Play goes straight to the main feature and resumes like any film. There is no "Play Disc" or "Skip to Movie" on any platform.
  - The trace says why: `disc start main title (Blu-ray: disc menus are not supported, playing the main feature)`. DVDs are unchanged.
- **Titles list like Infuse** — `AppleDiscPlayback.swift`, `AppleDiscViews.swift`.
  - `AppleDiscTitleList` puts the engine's main title first and labels it "Main Feature".
  - It merges duplicates (same length ±2 s and the same chapter count) and drops titles under 2 minutes.
  - It shows 6 titles, and a More card reveals up to 24 more. Cards read "1 hr 38 min · 16 chapters".
  - Unit tests cover a 28-title disc shaped like the Matilda trace and a 300-playlist obfuscated disc.
- **Top Shelf: full-screen carousel** — `TopShelfProvider.swift`, `AppleTopShelfSnapshot.swift`.
  - The shelf is now `TVTopShelfCarouselContent(style: .details)`: Continue Watching first, then Top Picks, each title once, at most 12 pages.
  - Each page has its backdrop, a context line, the synopsis, genre, year and running time, and Play / More Info with the same deep links as before.
  - No progress bars anywhere, including the row layout, which is now only a fallback for when no title has a backdrop.
  - The snapshot gained optional `summary`, `genre`, `year` and `durationSeconds` fields, so older snapshots still decode. The Caches write path is unchanged.
- **Device install** — OfficePlus has this branch's App Store tvOS Release build (lead's recipe). A test runner app I installed by mistake has been removed again.

## Not done / unclear
- **Shelf and Titles screenshots from OfficePlus** — the device is asleep, so the launch was refused and I couldn't publish a snapshot or look at the shelf. The mobile MCP can't see Apple TVs. To check: wake OfficePlus, open oStream once, go Home, and focus its icon.
- **Titles list screenshot** — there is no Blu-ray fixture in the test corpus. The owner's UHD ISOs on OfficePlus are the real check.
- **Preview video** — skipped. Nothing in the app knows a direct trailer file URL; there's no Plex or Jellyfin local trailer source.
- **"Same clip sequence" duplicate test** — AetherEngine's public API doesn't expose clip IDs per title, so duplicates are matched by length and chapter count only.
- **A Blu-ray ISO streamed over HTTP with no Blu-ray words in its name** — these still ask for the menu first. The engine falls back to the main title, which E2E already checks.
- **DevTV** — not tried.

## Gates run
- code-anti-slop pass → removed 1 dead property (`menuUnsupported` and its 2 test lines) and 1 comment that repeated the code.
- swift test, full suite (3392 tests in 414 suites) → my suites pass. Five other tests failed in this run (a local playback server test, three add-on logo refresh checks, one Mac captions timeout), and the failures differed from the first run. Re-running those suites with mine gave 62 tests in 5 suites, all passing. The Mac captions suite only runs when its fixture is present.
- xcodebuild tvOS and iOS simulator → BUILD SUCCEEDED. Recompiled, confirmed by grep: AppleDiscPlayback, AppleDiscViews, AppleDiscoverView, AppleLocalFileInspection, AppleLocalLibraryStore, AppleTopShelfSnapshot on both, and TopShelfProvider on tvOS (it's tvOS-only).
- xcodebuild App Store tvOS Release for the device → BUILD SUCCEEDED, the changed files recompiled.
- Release no-add-ons builds → not run: every edit sits outside `#if OPENSTREAM_ADDONS`.
- E2E tvOS:
  - The four DVD menu tests (Play Disc and Skip to Movie on menu-test and menu-features) → pass.
  - Top Shelf → passes after the test update: `TOPSHELF carousel: true matched: ["Stub Movie"]`. In carousel mode tvOS doesn't expose the context titles to accessibility, so the test now checks for the system's "Swipe up for full screen" affordance plus a stub title.
  - On the simulator the backdrop is black because stub art lives on `fixture.example`.
- zero-byte check → clean.

## Diff
```
 M AGENTS.md                                  (not mine: lead's anti-slop rule)
 M specs/tv-disc-shelf-2026-10-15.md          (not mine: lead's device-install note)
 M Apps/OpenStreamTVUITests/AppleTVTopShelfUITests.swift          8 +-
 M Apps/OpenStreamTopShelf/TopShelfProvider.swift                57 ++-
 M Sources/OpenStreamApple/AppleDiscPlayback.swift              124 ++-
 M Sources/OpenStreamApple/AppleDiscViews.swift                  32 +-
 M Sources/OpenStreamApple/AppleDiscoverView.swift               41 +-
 M Sources/OpenStreamApple/AppleLocalFileInspection.swift         6 +-
 M Sources/OpenStreamApple/AppleLocalLibraryStore.swift           7 +-
 M Sources/OpenStreamApple/AppleTopShelfSnapshot.swift           91 ++-
 M Tests/OpenStreamAppleTests/AppleDiscPlaybackTests.swift      119 ++-
?? Tests/OpenStreamAppleTests/AppleTopShelfCarouselTests.swift
```

## Notes for the reviewer
- `AppleDiscPlayback.swift`, `AppleDiscImagePolicy.format`: the name tokens include `UHD`, and any ISO over 9 GB counts as Blu-ray. A DVD release name that happens to contain "UHD" would lose its menu.
- `AppleDiscViews.swift`: on tvOS, pressing More removes the More card, so focus falls to the neighbouring card. It's worth a look on OfficePlus.
- `TopShelfProvider.swift`: the 12-page cap and the Continue Watching / Top Picks order are copied by hand from `AppleTopShelfContentBuilder.carouselItems` (the extension can't import the package). Keep the two in sync.
- `.details` style was picked because the SDK describes it as action buttons plus item details, which matches the Apple TV app. Compare it on OfficePlus.
- Scratch on the mini: `~/Developer/openstream-build/tv-disc-shelf-spm` and `/Volumes/DevExt/dev/openstream-build/dd-tv-disc-shelf` can be rebuilt and deleted once the branch merges. No simulators are left booted.
