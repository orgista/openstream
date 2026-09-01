# HANDOFF — LLM session continuation guide

Read this first when picking up Orgista release/app work in a fresh session.
It covers the whole program (all app repos), not just OpenStream. Update it
whenever you finish a meaningful unit of work. Last updated: 2026-09-01.

## The one-paragraph state

Five Android release AABs are built, signed, audited, and staged in
`Apps/release-aabs/` (openstream-tv v1, openstream-mobile v2, openreader,
openqr, openpdf, openpanelvr). OpenStream is uploaded to Google Play internal
testing (both AABs, one listing). The Apple side has an App Store Connect
record ("OpenStream by Orgista", app id 6807530757, SKU/bundle
`com.orgista.openstream`) and a four-platform Xcode project in
`native/apple/Apps/` — iOS/tvOS/visionOS/macOS — with the macOS target
verified building; the other three need the Xcode platform runtimes
(download was in flight when this was written). No Apple build uploaded yet.

## Standing conventions (owner rulings — do not relitigate)

- **Packages:** every app ships as `com.orgista.<app>`. The `com.cyberbanksy.*`
  ids are retired (`native/android-xr-scene` still carries one; rename when
  next touched). Gradle/Xcode *namespace* (internal code package) may differ.
- **OpenStream is ONE store listing per store** covering TV + mobile.
  Play: two AABs, google-tv = versionCode N (leanback-required), android-xr
  mobile = N+1. Keep the offset on every bump. Apple: one record, all
  platforms, same bundle id.
- **Never hardcode content, providers, or credentials** — see
  `POST_DEPLOYMENT_SOURCES.txt` (operator checklist; secrets live in the
  macOS Keychain service "OpenStream Deployment") and README ~line 69.
- App Store display name is "OpenStream by Orgista" (bare "OpenStream" was
  taken); the icon label stays "OpenStream" via CFBundleDisplayName.
- Play target-API floor (since 2026-08-31): 36 for mobile, 34 acceptable for
  TV-only. OpenQR splits flavors for exactly this (quest=34, play=36).

## Signing & secrets

- Android upload keystore: `Apps/signing/orgista-upload.keystore`; env vars in
  `Apps/signing/credentials.env` (per-app prefixes OPENSTREAM_/OPENREADER_/
  OPENQR_/OPENPDF_/OPENPANEL_QUEST_). `set -a && source … && set +a` INSIDE
  the one-shot build shell only. Never echo values, never put them in argv,
  never commit them. Migrating these into the Keychain is an open should-do.
- Apple: team Raster Inc `2VQ74PD5YG`, automatic signing, set in the Xcode
  project. Archives/uploads need the owner's Apple ID signed into Xcode (or a
  future App Store Connect API key from ASC → Users and Access).

## Build recipes

**Gotcha for everything: the repos live on an SMB share** (`/Volumes/Files`).
Gradle/vite/Xcode deletes fail there. Full workarounds in the memory file
`openpanel-smb-build-quirks`, short version: rename stuck dirs aside
(`mv X X.old.$(date +%s)`), keep Gradle/DerivedData caches on LOCAL disk,
and always `set -o pipefail` when piping build output.

- **OpenStream Android** (this repo): `npm test` (web+server gates), then per
  module: `native/google-tv` and `native/android-xr` build with Homebrew
  Gradle 9.7+, `JAVA_HOME`=JDK21, `ANDROID_HOME=~/Library/Android/sdk`,
  `GRADLE_USER_HOME` under `$TMPDIR`, `:app:bundleRelease` with signing env
  sourced. Native unit tests: `:app:test` (android-xr, 378 tests).
- **OpenStream Apple** (this repo): project at
  `native/apple/Apps/OpenStreamApps.xcodeproj`, schemes "OpenStream iOS/
  tvOS/visionOS/macOS", shared entry `Apps/Shared/OpenStreamApps.swift`,
  core code in the `OpenStreamApple` local Swift package (`native/apple`).
  Verify-build: `xcodebuild -project … -scheme "<scheme>" -destination
  "generic/platform=<iOS Simulator|tvOS Simulator|visionOS Simulator|macOS>"
  -derivedDataPath "$TMPDIR/openstream-dd" build CODE_SIGNING_ALLOWED=NO`.
  Platform runtimes install with `xcodebuild -downloadPlatform iOS` (etc.).
  TestFlight: open the project in Xcode → Archive → Distribute (owner's
  login required). macOS target has sandbox entitlements at
  `Apps/Shared/OpenStreamMacOS.entitlements`.
- **OpenQR**: `Apps/QR Code reader`, flavors quest/play; play release:
  `:app:bundlePlayRelease` (signing guard enforces env). Unit tests:
  `:app:testPlayDebugUnitTest`.
- **openReader / OpenPDF / OpenPanel quest**: each repo's release config is
  env-driven the same way; quest project is `OpenPanel/quest` (own gradlew).

## Devices on hand

- ONN 11 Pro tablet (Android 14): usually USB serial `ONN11PRO00156016`,
  sometimes wireless adb (port changes; ask owner). Runs the kids-provisioned
  `com.orgista.openstream` (debug keystore) — do NOT overwrite with
  release-signed builds, and never re-provision content by hand; see
  POST_DEPLOYMENT_SOURCES.txt. `input text` corrupts >~100-char strings —
  chunk to 40.
- Apple devices paired to this Mac: iPhone "Anthony", iPhone "Camera+",
  Apple TV "Kitchen". Quest 3S sometimes on USB. TCL Google TV at
  192.168.1.189 (OpenPanel kiosk — treat as production).

## Store state & blockers

- **Google Play (OpenStream)**: internal testing release with both AABs;
  needs a tester list + rollout. Listing assets ready in
  `Apps/release-aabs/store-assets/openstream/` (icon, feature graphic, TV
  banner, listing-copy.txt). BLOCKERS: 2–8 phone screenshots (16:9, ≥1080p —
  capture from the ONN once it is back on Wi-Fi), TV screenshots, and a
  privacy policy URL. Declare general audience, NOT child-directed.
- **Google Play (others)**: openqr play-AAB is targetSdk-36 compliant and
  crash-fixed (verify a real QR scan once; camera pipeline verified live).
  openreader AAB smoke-tested on-device (R8+Readium renders EPUB). openpdf +
  openpanelvr are Quest/sideload targets, not Play.
- **Apple**: App ID registered (iCloud/CloudKit ticked; container
  `iCloud.com.orgista.openstream` — create it if not present before adding
  the entitlement to the project; the project deliberately ships WITHOUT the
  iCloud entitlement until CloudKit code lands). ASC record exists for all
  four platforms at version 1.0 (project MARKETING_VERSION matches). Next:
  archive + upload from Xcode → TestFlight internal. Same privacy-policy URL
  blocker at submission. Watch-history sync design: CloudKit private DB,
  per-profile scoping (kids devices!), no Sign in with Apple (no accounts).

## Open items queue (in rough priority order)

1. Play screenshots (ONN online + provisioned Discover) → finish Play listing.
2. Privacy policy page (draft + host on Cloudflare; one URL for both stores).
3. Apple platform runtimes finish → verify iOS/tvOS/visionOS builds → owner
   archives in Xcode → TestFlight internal testing.
4. Live QR-scan test of OpenQR play build; quest flavor smoke on Quest 3S.
5. Native-symbols gradle config is in place — next OpenStream Android bump
   (versionCodes 3/4) uploads with symbols.
6. credentials.env → Keychain migration; kids-mode cert matching tightening
  (title-only today); `android-xr-scene` package rename.

## Conduct notes for the next session

- Verify on hardware before claiming success; screenshots or it didn't happen.
- The owner's family uses the ONN — check `mCurrentFocus` before driving it,
  back off if a human is using it.
- Don't commit/push/deploy without the owner saying so, in every repo.
- Superpowers + agent-ops skills are installed at user scope; use
  systematic-debugging and verification-before-completion by name.
