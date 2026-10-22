# OpenStream — ship checklist ("common sense check")

Run every line before uploading a TestFlight build, and tick them in the release notes you write to
`DELIVERIES.md`. Owner rule (2026-09-28): these must be clean **before** a build ships, not fixed after.
If a line fails, fix it or stop and ask; never "ship now, fix in the next build".

## 0. One build for everyone (owner decision 2026-10-22)
- OpenStream has no add-ons. **One build** goes to TestFlight (every group) and to App Review; there is no
  separate add-on archive, sideload flavour or compilation condition.
- Load the `app-store-review-hardening` skill and run its pre-submit checklist (binary, metadata and screenshots,
  review notes and demo, legal, TestFlight). Record the evidence in `DELIVERIES.md`.
- Public wording follows Infuse/Plex: OpenStream "plays media you own from your devices, network shares and media
  servers; does not provide any content". No add-on, Stremio, torrent, debrid or catalog-provider words anywhere.
- After each ship, expire the older TestFlight builds on every platform, so testers can only install the current
  build: `asc builds list --app 6807530757 --limit 20` first, then `asc builds expire --build-id <id> --confirm`
  for each older build (or `asc builds expire-all --app 6807530757 --older-than <age> --dry-run`, then without
  `--dry-run`). Driver only, after "ship N".

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
- [ ] `bash scripts/check-no-addons-in-release.sh --build` passes for iOS, tvOS, visionOS and macOS, Debug and Release,
      and again on each archive (`scripts/check-no-addons-in-release.sh <archive>`): no add-on word in any shipped file.
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
- [ ] **GitHub in step with every beta (owner 2026-10-14: "if a new beta goes out github should be updated"; pushes are
      automatic, tell the owner after).** Before archiving: the AetherEngine pin in `Package.swift`, `Package.resolved` and
      the Xcode project's `Package.resolved` names a commit that is already pushed to `cyberbanksy/AetherEngine`
      (`git ls-remote origin <branch>` contains it); push any local fork commit first (bundle from Dev-Mini, push from
      the Studio). After TestFlight: the public repo commit + GitHub release above, and the OpenStream main branch
      pushed to its remote. No ship leaves a commit that exists only on the mini or the Studio.
