## Done
- **Real-Plex check on DevTV: all three checks pass.**
  - `testServerTrailersWithRealServers` passed (134 s, `OPENSTREAM_REAL_SOURCES=1`).
  - **Hero:** The Karate Kid's Plex trailer played muted on page 5. The trace says `server trailer start muted`.
  - **Title page:** it shows a Trailer button. Pressing it opened the full-screen player, and the trace says `server trailer start with sound`. The test passes `-OpenStreamMuteAudio`, which silences Debug test runs, so nothing was actually audible. Menu went back to the title page.
  - **Top Shelf:** `testTopShelfShowsRealContentWhenTheAppIconIsFocused` passed. The app group's `Library/Caches/topshelf-trailers/` held a 37.9 MB `.mp4` while Plex was added.
  - Screenshots are in `design/2026-10-17-server-trailers/`: `devtv-plex-hero-muted.png`, `devtv-plex-title-page-trailer.png`, `devtv-plex-trailer-player.png`.
- **Debug-only way to add and remove the source** — `AppleDevSourcesImport.swift`, `AppleDevSourcesPolicy.swift`. Both files are already `#if DEBUG && OPENSTREAM_ADDONS`.
  - `-OpenStreamDevSources` now also takes a path relative to the app's home folder, so the file can be copied in with `devicectl device copy to`. The app still reads the file once and deletes it.
  - New `-OpenStreamDevSourcesRemove YES` removes the file's sources through `AppleSourceStore.remove(id:)`. `alreadyAdded` now wraps a new `saved(_:in:)` lookup. New test: `aRemoveRunFindsTheSavedServerByKindAndAddress`.
- **Token handling:** the token was read only inside the step that writes the file for the device. That file was a 0600 file in the mini's `/private/tmp`, deleted right after the copy. The app deleted its copy on launch (checked: not in the container). A search of everything copied back from DevTV found the token in 0 files. Nothing was printed.
- **Plex removed from DevTV:** the trace shows `remove source "Plex"` and `sources saved: 9`, the same count as before. The `topshelf-trailers` folder is empty again and the app was terminated. OfficePlus was not touched.
- **Test fixes** (`AppleTVFocusUITests.swift`):
  - Focus starts on the tab bar, so Right changed tabs instead of hero pages. The test now goes Down and back Up into the hero first, like N12.
  - The Trailer button is now found by `detail.icon-row` plus the label "Play Trailer".
- **Trace** (`AppleServerTrailerView.swift`): `server trailer start muted|with sound (test mute on)`, so the trace shows muted vs. with sound.

## Not done / unclear
- I didn't capture `shelfVideo` in the Top Shelf snapshot while Plex was added. The copy in `devtv.sh run` failed, and the read after removal had none because the shelf had been republished. The evidence is the downloaded file plus the passing Top Shelf test.

## Gates run
- code-anti-slop pass → removed 0. The diff is small and matches the files' style.
- `swift test --no-parallel` (compile lane) → pass 3485/435 after the last source edit (3484 before, +1 new test).
- xcodebuild AppStore-tvOS Debug build-for-testing, DevTV, signed → TEST BUILD SUCCEEDED. Recompiled AppleDevSourcesImport=1, AppleDevSourcesPolicy=1, AppleServerTrailerView=1, AppleTVFocusUITests=1.
- xcodebuild AppStore-tvOS Release, no add-ons → BUILD SUCCEEDED, same 3 files recompiled.
  - Every binary in the `.app` has 0 hits for `OpenStreamDevSources`, `OpenStreamRestoreBackup` or `plex-dev-sources`.
  - Control: the new trace string is there. The Debug build's `OpenStream tvOS.debug.dylib` does contain the remove key.
- zero-byte check → clean

## Diff
```
 M Apps/OpenStreamTVUITests/AppleTVFocusUITests.swift          | 15 +++-
 M Sources/OpenStreamApple/AppleDevSourcesImport.swift          | 17 ++++-
 M Sources/OpenStreamApple/AppleDevSourcesPolicy.swift          | 27 +++++---
 M Sources/OpenStreamApple/AppleServerTrailerView.swift         |  1 +
 M Tests/OpenStreamAppleTests/AppleDevSourcesPolicyTests.swift  | 11 ++++
?? design/2026-10-17-server-trailers/devtv-plex-{hero-muted,title-page-trailer,trailer-player}.png
```
Nothing is committed.

## Notes for the reviewer
- `AppleDiscoverView.swift:4692` and `:5916`: `detail.serverTrailer` never reaches XCUITest, because the row's `.accessibilityIdentifier("detail.icon-row")` (`:4703`) replaces it. I left the app alone, since other tests rely on `detail.icon-row`.
- After Menu closes the trailer, the trace says `detail focus: trailer corrected to play`, so focus comes back on Play rather than Trailer. Check whether that's intended.
- The trace said `top shelf trailer skipped for Interstellar: size unknown or too large`, so only one Top Shelf trailer was saved.
- The trace shows pairs of `start muted` about 0.9 s apart. That's the test turning through two trailer pages quickly, not a bug.
- On the mini, `/Volumes/DevExt/dev/openstream-build/server-trailers-devtv/` has `realplex.sh` (seed/remove/trace) and `job.sh`. Neither contains a secret.
- Dev-Mini warned it was down to 19 GB free during the gate. I deleted my runs' large recordings.
- The first run left the token file in the container for about 1 minute, because the launch failed (arguments need `--`). The remove step overwrote it with a placeholder, and the next app launch deleted it.
