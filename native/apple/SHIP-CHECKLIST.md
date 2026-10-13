# OpenStream — ship checklist ("common sense check")

Run every line before uploading a TestFlight build, and tick them in the release notes you write to
`DELIVERIES.md`. Owner rule (2026-09-28): these must be clean **before** a build ships, not fixed after.
If a line fails, fix it or stop and ask; never "ship now, fix in the next build".

## 0. Which build is this? (owner decision 2026-10-02)
- **TestFlight** builds keep add-ons: archive with `SWIFT_ACTIVE_COMPILATION_CONDITIONS='$(inherited) OPENSTREAM_ADDONS'`.
  Internal groups only by default — external TestFlight groups go through Beta App Review under the same rules
  as the App Store, so an add-on build there can be rejected.
- **App Store** submissions are a SEPARATE archive and build number WITHOUT the flag (add-ons compiled out);
  `scripts/check-no-addons-in-release.sh` must pass on it. Never submit a TestFlight add-on build for App Store review.
- **Public sideload downloads** include add-ons on every platform. The Mac download is ad-hoc signed and
  unnotarized until a Developer ID certificate exists; document right-click → Open.

## 1. Authorization and numbers
- [ ] The owner said "ship N" (or "push N") for this exact build number. Nothing else authorizes an upload.
- [ ] Every platform goes up on the same N: iOS, tvOS, visionOS **and macOS**.
- [ ] N is higher than the last build on **each** platform, the Mac included. Check before archiving:
      `asc builds list --app 6807530757 --limit 20` (read the platform of each build). Build 14 found
      a Mac build 13 nobody had noted, which made "Mac 1" impossible.

## 2. Source
- [ ] Building from `main` (the canonical branch since 2026-09-28), with its HEAD sha recorded.
- [ ] Build in a local-disk worktree (`git worktree add ~/Developer/openstream-build/wt-bN <sha>`), never on the share.
- [ ] `find Sources Tests Apps -name "*.swift" -size 0` prints nothing.
- [ ] The AGENTS.md §1 gate passes (`swift build` + `swift test`); note the test and suite counts.

## 3. Signing (every bundle, not just the app)
- [ ] List every embedded target: app, Widgets, Watch, **Messages (iMessage)**, Top Shelf, and anything
      new. Each one has a Release `PROVISIONING_PROFILE_SPECIFIER` in the pbxproj **and** a line in
      `scripts/release/ExportOptions-<platform>.plist`. A new target without both is a blocker.
- [ ] Each of those profiles is ACTIVE in `asc profiles list` (not INVALID or expired) and installed in
      `~/Library/MobileDevice/Provisioning Profiles/`. Build 14 found the Top Shelf profile INVALID.
- [ ] Creating or changing a certificate or profile needs the owner's OK first. Say what and why.

## 4. Nothing unfinished goes out
- [ ] `bash scripts/check-no-addons-in-release.sh` passes: Release iOS simulator binaries contain no add-on markers, and `OPENSTREAM_ADDONS` is absent from distribution compile commands.
- [ ] No placeholder assets: every icon set (app, Watch, Widgets, **iMessage**, Top Shelf, Mac) is the
      real artwork, with every required size. `grep -rni placeholder HANDOFF-NEXT-SESSION.md FEEDBACK.md`
      and look at each icon in the simulator.
- [ ] No debug-only UI, test data, or `TODO(ship)` markers in Release code paths.
- [ ] `OWNER-TODO.md`: nothing Open is marked as blocking a release; mention any known issues in the notes.
- [ ] TestFlight/App Store builds start with NO sources: install the Release build on a clean simulator
      with iCloud sync off and confirm No Sources (seeding is DEBUG-only since a6765b2).

## 5. Tracing and groups
- [ ] Traced build: tracing is on by default for TestFlight installs (AppleInteractionTrace.swift
      falls back to `AppleBuildChannel.isTestFlight`). Confirm it hasn't changed.
- [ ] Groups: `Internal,Reddit` (owner 2026-10-08: TraceEnabled was merged into Reddit, which now gets traced builds).

## 6. Archive and verify (one build at a time, `disk-guard.sh` first)
- [ ] On a real Apple TV play the DV fixture/title; the TV shows its Dolby Vision badge (match evidence), and the trace says `source=DV` with a known profile, non-none `preferredDisplayCriteria`, `isDisplayCriteriaMatchingEnabled=true`, and `dynamicRangeRequested=true`. Keep `dynamicRangeMatched=unverified`: public APIs cannot verify HDMI range.
- [ ] `CURRENT_PROJECT_VERSION=N` in the app and **every** embedded bundle (read each Info.plist).
- [ ] `codesign --verify --deep --strict` passes; team 2VQ74PD5YG; `get-task-allow` false.
- [ ] Mac: `pkgutil --check-signature` shows "3rd Party Mac Developer Installer: Raster Inc".
- [ ] `bash scripts/sdk-floor-check.sh` exits 0 on each archive (run with bash, not zsh).
- [ ] The Release build launches once on a simulator per platform and reaches the home screen.
- [ ] Smoke on iPhone + Apple TV: a title plays and resumes, the title-page trailer plays (hero + Trailers shelf),
      and no screen shows duplicate or dead controls.
- [ ] Trailers on a REAL iPhone (not only a simulator): the video must appear over the art within ~2 s. Simulators render video into WKWebView snapshots and devices don't, so build 15's hidden-trailer bug only showed on hardware.

## 7. Upload and record
- [ ] `asc publish testflight --app 6807530757 --ipa <ipa> --platform IOS|TV_OS|VISION_OS --group "Internal,Reddit" --submit --confirm`
      Mac: `--pkg <pkg> --version 1.0 --build-number N --platform MAC_OS` with the same group flags.
- [ ] Read back VALID for each platform; write the build IDs, sha, gate counts and any new profiles to `DELIVERIES.md`.

## 8. GitHub release (after TestFlight)
- [ ] Under the same owner authorization **"ship N"**, run `scripts/release/github-release.sh <version> N` to prepare all four platform downloads, checksums, notes, and the committed public checkout.
- [ ] The lead reviews the scrub/gitleaks gates and every artifact, then runs the printed publish commands
      (`git push` of the public checkout + `gh release create` on orgista/openstream-apple) from the Studio, where `gh`
      is logged in. **Owner 2026-10-12: "yes for all releases" — every "ship N" includes this GitHub release; no
      separate approval.** The preparation script itself still never pushes; the lead runs the printed commands.
- [ ] Build the release from the exact commit that went to TestFlight (DELIVERIES.md "Source"), not a newer main.
      `github-release.sh` needs a git checkout on `main` and `gitleaks` on Dev-Mini (brew); the public checkout can live
      at `/Volumes/DevExt/dev/openstream-release/` via `OPENSTREAM_PUBLIC_CHECKOUT`.
- [ ] Before running it: add a `## [<version> (<build>)] - <date>` section to the public checkout's CHANGELOG.md (the
      notes come from it; use the What to Test lines). Publish from the Studio: bundle the new public commit from the mini,
      fetch it into a fresh clone, `git push`, then `gh release create` with the assets (verify SHA256SUMS first).
