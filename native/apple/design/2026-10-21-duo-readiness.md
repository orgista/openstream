# iPhone Duo readiness (2026-10-21)

Read-only audit of `Sources/` and `Apps/`. Line numbers are on branch `cloud/duo-audit` (main 2b9b221
plus the hero-inset cleanup). Not built or run (no Xcode in the cloud
session). Assumed: both Duo screens report the phone idiom; the inner screen is near-iPad size and
reports a regular width; folding changes the window size and size classes live. Real point sizes
need the 27.1 Duo simulator. Supersedes the line numbers in
`verification-artifacts/duo-2026-10-08/AUDIT.md`: patches 02 and 04 still apply cleanly, 01 fails
on `OpenStreamRootView.swift`, 03 fails on `AppleMediaSourceViews.swift` (Live was rewritten).

Root cause behind most rows: **the device idiom stands in for "small screen".** An unfolded Duo
gets phone chrome (idiom checks) mixed with iPad layout (size-class checks). One helper (patch 01's
`AppleAdaptiveCanvas.isLarge`: regular width and short side >= 600 pt) used at each site fixes most of them.

| # | Where | What breaks on the Duo | Sev | Smallest fix |
|---|---|---|---|---|
| 1 | `AppleOrientationLock.swift:7`, `:43`, `:52`; `Apps/Shared/OpenStreamApps.swift:218` | Phone idiom means portrait-only outside the player, so the inner screen is locked too. If its natural hold is wider than tall, the user has to turn the device sideways to use the app. Closing the player forces portrait. | P1 | Mask from the window, not the idiom: `.all`/`.allButUpsideDown` on a large canvas; call `setNeedsUpdateOfSupportedInterfaceOrientations` on fold/unfold (patch 01, rebased) |
| 2 | `AppleHomeHeroCarousel.swift:35`, `AppleHomePresentationPolicy.swift:14` | Unfolded Discover/Library: phone idiom + regular width → `.rotating` hero (the generic one), not the iPad billboard | P2 | Pick `.pad` when the canvas is large (patch 02 applies as is) |
| 3 | `ApplePhoneTitlePageChrome.swift:100`, `AppleAlignedTabTitle.swift:37`, `AppleDiscoverView.swift:423`, `AppleMediaSourceViews.swift:3234` | Landing chrome is chosen by idiom: nav bar hidden, round Search/Refresh drawn over the `.rotating` hero. The iPad toolbar never appears | P2 | Same large-canvas test in place of `idiom == .phone` |
| 4 | `ApplePhoneTitlePageChrome.swift:170` with `AppleHomeHeroCarousel.swift:104` | The landing title bar fades in at the phone hero's computed height (`heroExtent` is never reported off the `.phone` hero), so on the inner screen it appears at the wrong scroll point | P2 | Goes away with 2+3. Otherwise report the extent for every hero |
| 5 | `AppleTabToolbarContext.swift:79`, `AppleDiscoverView.swift:5423`, `:9589`, `:5951` | Title page: `usesPhoneTitlePage` uses the size class (iPad overlay hero) but the toolbar uses the idiom (phone round back button, no bar). Mixed page; the iPad status-bar shield is off (`AppleStatusBarShield.swift:53`) | P2 | Gate the chrome and the shield on `usesPhoneTitlePage` |
| 6 | `AppleTitlePageContent.swift:23` | Folding with a title page open swaps `PhoneContent` ↔ `RegularContent`. New identity: the trailer view reloads and the scroll position resets | P2 | Accept, or keep the trailer/hero host outside the branch. Check on the sim first |
| 7 | `OpenStreamRootView.swift:439`, `:353` | The root viewport is measured on iPad only (`.zero` on phones), so Settings never splits on the inner screen and nothing else size-driven can read it | P2 | Measure on every iOS device. Split on a large canvas (patch 01, rebased) |
| 8 | `AppleMediaSourceViews.swift:1426` (`usesPhoneLiveLayout`), `AppleLiveChannelPickerModel.swift:24` | Live stage already follows the window (`AppleLiveStagePolicy.sideBySide`, keeps the player identity). But the rows, category bar, programme line and full-screen picker follow the idiom: phone rows beside the player, and a narrow picker panel on a big screen | P2 | `usesPhoneLiveLayout = !sideBySide`. Picker `.bottomStrip` on a large canvas |
| 9 | `AppleDiscoverView.swift:9278` (`portraitTabletWidthThreshold`), `AppleDetailMetrics.isLandscapeLayout` | Assumes "phone portrait width < 600" and "wider than tall = rotated". An unfolded Duo in portrait lock that is wider than tall gets `.landscapeIPad` metrics while the idiom chrome is phone | P2 | Goes away with 1 (rotation allowed). Confirm the widths on the sim |
| 10 | `AppleStreamDeviceCapabilities+Current.swift:22` | Automatic quality caps at 1080p on every phone; the inner panel is likely above 1080p | P3 | Cap from the screen's native pixels (`UIScreen.nativeBounds` of the window's screen), not the idiom |
| 11 | `AppleDiscoverHeroLayoutReader.swift:36` (`measuresPad` by idiom, fixed at init) | Once 2 picks `.pad` on a phone, the iPad hero layout is never measured | P2 (after 2) | Measure for both. Cheap |
| 12 | `AppleHomePhoneHeroLayout.swift:74` (`settleDelay` 750 ms) | After a fold, the folded hero is drawn at the unfolded height for 0.75 s | P3 | Skip the settle when the width changes |
| 13 | `AppleDiscoverPhoneRowPolicy.swift:10` (fixed 200/148/248 pt tiles) | Built for a 393 pt screen. On a wider outer screen a whole number of tiles can fit with no peek | P3 | Reuse `AppleDiscoverMacRowMetrics.peekWidth` for the phone rows |
| 14 | `AppleTrailerStartPolicy.swift:39` | Trailer start rules follow the idiom (phone rules on the inner screen) | P3 | Confirm intent. Large canvas → `.padOrMac` |
| 15 | `Apps/OpenStreamWidgets/OpenStreamWidgets.swift:242` | No `.systemExtraLarge`, in case the inner home screen offers it | P3 | Add the family if the 27.1 sim offers it. The views are already size-driven |

Fine as is: no `UIScreen.main` in app code. No `UIRequiresFullScreen`; the iPhone plist
already lists both landscapes. The full-screen players are AVKit + constraints with `.resizeAspect`
and survive a resize. Widget art is sized from the widget context. The phone hero's 70 % art
(`AppleTitlePageSlotArt.swift:76`) follows the live height. Live's `AnyLayout` keeps the channel
playing across shape changes.

Order: 1 → 2/3/5/7/11 (one `AppleAdaptiveCanvas` helper) → 8 → 6 checked on the Duo sim.
Verify folded and unfolded, rotation, mid-playback fold, Discover/title page/Live/player/Settings.
