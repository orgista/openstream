# Repo structure — where OpenStream is, and what comparable projects do

_2026-09-16. Written after the owner asked to clean up the multiplatform layout._

## Where we are

`orgista/openstream` is one repo holding four unrelated things:

| Tree | Tracked files | On disk |
|---|---|---|
| root (`src/`, `server/`, `dist/`) — web + server | — | — |
| `native/apple` | 1347 | 4.0 GB |
| `native/android-xr` | 247 | 479 MB |
| `native/openxr` | 237 | 2.9 MB |
| `native/android-xr-scene` | 15 | 90 MB |
| `native/meta-quest` | 21 | 1.7 MB |
| `native/smart-tv` | 14 | 236 KB |
| `native/google-tv` | 9 | 132 MB |
| `native/roku` | 7 | 124 KB |

Two large apps, one web/server app, and five trees that are still stubs. Everyone who clones it to
work on one platform pays for all of them.

## What comparable projects do

**Jellyfin** is the closest analogue and the most instructive: ~80 repositories, with the server in
`jellyfin/jellyfin` and **each client in its own repo** — `jellyfin-web`, `jellyfin-androidtv`,
`jellyfin-expo`, `jellyfin-vue`. The web client is deliberately *not* vendored into the server
repo; it is built from its own source. That is a project with far more platforms than ours choosing
one-repo-per-client and sticking to it.

**The Swift ecosystem pulls the other way, but only within one platform family.** The current
advice for iOS/tvOS/watchOS/visionOS is a single repo with the shared code as a **local Swift
package** consumed by thin per-OS app targets — because those targets genuinely share code and must
be built and tested together. Splitting an Apple app by OS would be the wrong cut.

Those two are not in conflict. They point at the same line: **split by platform family, not by
platform.**

## Proposal

| Repo | Contents | Why |
|---|---|---|
| `orgista/openstream` | web + server, brand, shared docs | the thing everything else talks to |
| `orgista/openstream-apple` ✅ created | iOS, iPadOS, tvOS, watchOS, visionOS, macOS | one Swift package (`OpenStreamApple`) plus thin app targets — the Swift-world monorepo, correctly scoped |
| `orgista/openstream-android` | `android-xr`, `google-tv`, `meta-quest`, `openxr` | shares Gradle, the Android toolchain and most of its code |
| _leave in place for now_ | `roku` (7 files), `smart-tv` (14 files) | stubs; a repo each would be ceremony around nothing |

Naming follows the org's existing convention — `openpanel` / `openpanel-ui`, lowercase with a dash.

## Done so far

`orgista/openstream-apple` exists (private) and the Apple tree is extracted with
`git subtree split --prefix=native/apple`, which **keeps the history of those files** rather than
starting from a flat snapshot. Branch `apple-only`, 12 commits, `Package.swift` / `Sources` /
`Tests` / `Apps` at the root.

## Not done, and why

The push is refused by the current session's permissions, so the repo is still empty. Once pushed,
the follow-ups are: delete `native/apple` from the main repo in a commit that names the new home,
add a pointer in the main README, and repeat the same split for the Android family.

Nothing here has been removed from `orgista/openstream` yet — the split is additive until the push
lands and you have confirmed the new repo looks right.
