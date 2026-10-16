The other project's tvOS E2E run still holds the Dev-Mini lock. I'll pick up on my own the moment it frees: first the `swift test` gate, then the DevPlus device build and the disc test.

The simulator build is still waiting on the shared lock; I'll pick up as soon as it lands.

The rebuild is still waiting on the lock. I'll continue when it finishes.

Waiting on the queued simulator build; I'll be notified when it finishes.

The combined rebuild and simulator session is queued behind atv-slowness's E2E; I'll pick up from its progress events.

The retry loop is set and I'll be notified when the simulator session is ready. Until then I'm waiting on atv-slowness, whose jobs keep taking the lock.

The first queued attempt timed out as expected; the retry loop takes over from here. Still waiting for the simulator-ready notice.

Waiting on the final `swift test` gate result.

Waiting on the gate.

atv-slowness has held the lock almost continuously since 02:51, with a new job at 02:58. My gate job is still queued and I'll be notified when it finishes. How long that takes is unknown; my retry loop allows up to about 100 minutes.

## Done
- **Discs don't play: diagnosed and fixed. John Wick 4 UHD now plays on DevPlus.** On the owner's build, Play opened a black player with nothing on it while the disc was read for 12–14 s, so the owner closed it after about 13 s. The "load superseded" lines are just that closed player shutting down, not a second load. On this branch, John Wick 4 UHD plays on DevPlus (iOS 27, Release + add-ons, owner backup). After the fixes, the player is up 94 ms after Play, the first frame lands 10.6 s after the press, nothing is superseded, and the selected title is the right one (10158 s = 2 hr 50 min).
  - No silent wait — `AppleMediaPlaybackView.swift`: the spinning disc (an ordinary spinner for other files) now shows on iOS until the engine starts playing, as tvOS already did.
  - A disc was read twice per Play — `AppleLocalLibraryStore.swift:847`: 71e2f97 added a duration probe before the player opens, and on an ISO that probe reads the whole disc. Disc images now skip it: one read instead of two, and on DevPlus the player opens in 94 ms instead of 4.5 s.
  - Trailer — `AppleDiscoverView.swift`: Play pauses the title trailer, and it no longer starts on its own under a Play that is still loading.
- **Rill https/redirect fix** — `AppleMediaServerClient.swift`, `AppleAddMediaServerView.swift`, `AppleDevSourcesImport.swift`:
  - An address typed without a scheme tries https first, and falls back to http only when https can't connect.
  - Every later call, including sign-in and Quick Connect, uses the address the server redirected to.
  - When a reply can't be read, the trace records method, path, status, content type and the redirected-to path, never the query or body.
- **iOS 18 hero jump** — `AppleAlignedTabTitle.swift`, `OpenStreamRootView.swift`, `AppleHomePhoneHeroLayout.swift`, `AppleDiscoverView.swift`:
  - On iOS below 26, every tab forced an opaque black bar, which hid the top of the Discover hero. Discover now keeps the stock transparent bar, and the hero runs edge to edge as it does on iOS 27.
  - The bar's height still changes between 115 and 97 pt, and each reading used to move and resize the art. The hero now keeps one settled layout. Proven on the 18.6 sim: a tab switch and a scroll produce readings but no redraw.

## Not done / unclear
- **Last Airbender: not tested.** DevPlus's library doesn't have it (its ISOs are staged copies). It needs the owner's phone.
- **Owner's iPhone: no install.** It was locked at 02:42 (passcode required). The Release build is ready at `/Volumes/DevExt/dev/openstream-build/iphone-ios18/dd-device`, but it predates the hero fixes; rebuild first with `iphone-ios18/owner-build.sh`.
- **Rill not checked against the real server.** I don't have the owner's password.
- **Speed and caching: need engine changes**, not app code (the AetherEngine package is a pinned dependency):
  - The engine forgets the parsed disc whenever a new file loads, so a per-file cache keyed by size and mtime has to live in the engine.
  - The reads that take 12–14 s on the owner's phone took about 2 s on DevPlus, which points to the owner's network path.
- **Gates not run:**
  - E2E-iOS on either OS version.
  - The iOS 27 simulator.
  - The full iOS 18 vs 27 walk. Partial findings from the screens I saw:
    - Title page back and search buttons have no round backgrounds on iOS 18.
    - The scrolled bar is the stock blurred bar with an inline title.
    - Settings looks the same.
  - Cause: the Dev-Mini lock was held almost continuously by the atv-slowness lane.
- **Left on DevPlus:**
  - The mobile MCP's Device Kit UI agent, which is needed to drive it; I removed it from the simulator.
  - A John Wick resume point, about 1 minute in.

## Gates run
- code-anti-slop pass → removed 1 dead variable in `resolveBaseURL`; I also replaced a LAN-style test IP with 10.0.0.20.
- swift test → **mid-change run passed, 3436 tests in 426 suites.** The final run failed: 3439 tests in 426 suites, 1 issue. The failure was `AppleLiveZappingTests.supersededLiveProbeCannotSelectOrCacheThePreviousChannel`, a timing test with a 2 s deadline in live-channel code this diff doesn't touch; its suite passed 16/16 on 3 reruns. The full suite has not had a clean pass since the last edits.
- xcodebuild OpenStream iOS, Release + add-ons, signed for DevPlus → BUILD SUCCEEDED, every edited file recompiled. This build does not include the bar and hero changes.
- xcodebuild OpenStream iOS, Debug, iOS 18.6 sim → BUILD SUCCEEDED, `AppleAlignedTabTitle`, `OpenStreamRootView`, `AppleHomePhoneHeroLayout` and `AppleDiscoverView` recompiled. The last change (settle delay 400 → 750 ms) was not rebuilt here; the SwiftPM gate compiled it.
- Release no-add-ons gate → not needed: none of the edits are inside `OPENSTREAM_ADDONS` blocks.
- zero-byte check → clean.

## Diff
```
 M AGENTS.md   (driver's OfficePlus rule — not mine)
 M Sources/OpenStreamApple/{AppleAddMediaServerView,AppleAlignedTabTitle,AppleDevSourcesImport,AppleDiscoverView,AppleHomePhoneHeroLayout,AppleLocalLibraryStore,AppleMediaPlaybackView,AppleMediaServerClient,OpenStreamRootView}.swift
 M Tests/OpenStreamAppleTests/{AppleHeroPortraitArtTests,AppleMediaServerTests}.swift
?? specs/iphone-ios18-discs-2026-10-15.md
 12 files changed, 320 insertions(+), 46 deletions(-)
```

## Notes for the reviewer
- `AppleLocalLibraryStore.swift:847`: disc images are no longer measured before play. A stack made of disc images can't map a resume position across parts; it plays part by part instead.
- `AppleMediaPlaybackView.swift` (`showsRouteSpinner`): the pre-route spinner now draws on iOS and doesn't take taps. Check that the stock player's close button is reachable during the read.
- `AppleDiscoverView.swift` (`measuredPhoneHeroLayout` task): a genuine height change on Discover is drawn after 750 ms.
- `AppleMediaServerClient.swift` (`resolveBaseURL`): only a failure to connect falls back to http. An https error reply, such as a 503, is shown as-is.
