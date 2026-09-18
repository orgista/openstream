# Deliveries

## Apple build 12 source publication — September 17, 2026

Published to https://github.com/orgista/openstream-apple, branch main and tag build-12, commit
4a7c402. Verified the remote references and project path. Source baseline bf6988e plus accepted
Watch icon packaging, with documented publication/configuration adjustments. Local source copy:
`~/Developer/openstream-build/publish-apple-b12`. Tests 986/96 pass; unsigned iOS Release build passes.
Cloud repair completed September 17: `orgista/openstream-apple` is connected and Apple Build
Checks is enabled. Its four BUILD actions all passed in **run 5**, ID
`3a431b39-00a5-47b7-8b72-891a435db678`, commit `ba066e3b77150bedd5a7279b240f1781f426d0e1`.
Run 4 reached the correct source but exposed two iOS ActivityKit isolation errors. The follow-up
retains Activity identifiers on MainActor and resolves ActivityKit objects in nonisolated async
helpers; no unsafe Sendable suppression. Local iOS compilation and Cloud iOS both passed.
The build-12 tag still identifies the original baseline. Old failed runs are retained. The
separate TestFlight workflow stays paused; no new binary was uploaded.


## OpenStream iOS TestFlight delivery — September 17, 2026 (builds 11 and 12)

Both builds of OpenStream 1.0 are uploaded, processed VALID, unexpired, and IN_BETA_TESTING for
internal and external testers, verified through live App Store Connect reads after submission.

| Build | App Store Connect build ID | Tester groups | Source snapshot |
|---|---|---|---|
| 11 | ec6ec0bc-db74-4005-bbe1-b3c3d163f7c1 | Reddit, Internal, TraceEnabled | 3055de2 + signing/Watch icon packaging |
| 12 | a173faf4-49ce-42f3-9de2-c07ff664e0d6 | Internal, TraceEnabled | bf6988e + signing/Watch icon packaging |

Internal receives all builds automatically; external group assignments and testing states were
read back. Both apps support iPhone and iPad on iOS 18 or later. Installation on the owner's
device has not been observed. Existing public group links: Reddit
https://testflight.apple.com/join/z9wmEWyh and TraceEnabled https://testflight.apple.com/join/m8pMpW7H.

Owner enabled the Widgets App Group; regenerated profile 5ZP6L8ACKH includes
`group.com.orgista.openstream`. The first build-11 upload failed Apple validation because the
embedded Watch app lacked icons. Added the existing OpenStream icon to the Watch target in both
release worktrees and main, rebuilt, and successfully retried build 11 without changing its number.
Build 12 then processed successfully on its first upload.

Validation: fresh Swift build/test gates passed (11: 981 tests / 94 suites; 12: 985 / 96), both signed
Release archives and exports passed, and archive inspection verified iPhone/iPad device families,
all three bundle versions and signatures, embedded widget App Group, and compiled Watch icon metadata.
No new simulator session was run for these signing/packaging changes. Artifact pairs are
`~/Developer/openstream-build/OpenStream-iOS-b11-icons.xcarchive` / `.ipa` and
`OpenStream-iOS-b12-icons.xcarchive` / `.ipa`; logs `codex-ios11-*` / `codex-ios12-*`, final API receipt
`codex-ios11-12-final-state.json`. Export kept `manageAppVersionAndBuildNumber=false`.
No commits, certificate creation, macOS upload, or build-13 upload occurred.

### Tester notes — September 17 follow-up

Updated en-US What to Test for both iOS builds above, and verified exact text through fresh API
reads. Notes were grounded in the shipped snapshots and edited with the article-writing and
marketing copy-editing skills. Receipt: `~/Developer/openstream-build/codex-ios11-12-test-notes.json`.

Build 11 notes:

> Added automatic download source selection, with fallback when a source is unavailable.
> Added live progress and cancel controls for episode downloads.
> Added M3U playlist import by pasting text or choosing a file. Imports merge into one playlist and skip duplicate streams.
> Fixed search ordering so exact title matches appear before partial matches.
> Fixed download failures being hidden on series pages.
> Fixed clipped detail-page content and overlapping headings in iPhone settings.
>
> Please test episode downloads, cancellation, playlist import and title searches. When reporting an issue, include your device, the title or channel, and what happened.

Build 12 notes:

> Added automatic diagnostic logging for TestFlight to help investigate playback, navigation and download issues. Your existing choice in Settings is respected, and you can turn logging off there.
>
> Includes build 11's automatic download source selection, episode download progress, M3U playlist import, and fixes for search ordering, hidden download errors and iPhone layouts.
>
> Please retry any playback or download issue you previously reported. Include your device, the title or channel, what happened, and the approximate time.

## OpenStream iOS TestFlight delivery — 4 September 2026
**OpenStream 1.0 (6) is available to Anthony in TestFlight.** Apple processed the upload successfully and reports `VALID` and `IN_BETA_TESTING`. The existing Internal group includes Anthony and automatically receives all builds; build 6 is explicitly present in that group. Installation of this particular build on Anthony’s device has not been observed.

## OpenStream iOS TestFlight delivery — September 10, 2026
**OpenStream 1.0 (7) is available to Anthony in TestFlight.** Apple completed processing and reports `VALID` and `IN_BETA_TESTING`. Build 7 is present in the existing Internal group, which still includes Anthony. Installation of build 7 on his phone has not been observed; build 6 was installed when checked during this review.

## OpenStream iOS TestFlight delivery — September 11, 2026 (build 9)
**OpenStream 1.0 (9) is available to Anthony in TestFlight.** Apple processing `VALID`; internal state `IN_BETA_TESTING`; present in the existing Internal group (`ca5595ab-44fd-4063-bb55-89a053bf2736`) alongside builds 7 and 8. Build ID `5aad4dbc-0515-4d48-a397-c0c22033dc24`. What to Test notes set and read back (en-US localization `03538f2f-6d70-45be-880d-b5121d8b6e96`).

Export rule: use the App Store profile with Group Activities (`75afc0e9-11e3-4236-b7e4-95c4b8d7bc79`, ExportOptions-Manual.plist in artifacts/testflight/2026-09-10/shareplay-build-8-final); `manageAppVersionAndBuildNumber` assigns the next build number. Signing identity lives in `~/Developer/openstream-build/openstream.keychain-db`.
