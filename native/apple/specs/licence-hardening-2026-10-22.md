# Licence + repo hardening (lead, 2026-10-22 19:35) — Codex, bounded ~2 h

Guardrails: no git state changes (no commit/stash/checkout/reset), no uploads, no pushes, never print credentials or
signing identifiers (no cat of sign*.zsh, .asc, ExportOptions). Heavy work through ~/Developer/bin/buildlock*.sh.
Foreground jobs. Read AGENTS.md first; use code-anti-slop and app-store-review-hardening skills.

## Do
1. Engine (AetherEngine fork / FFmpeg build config used by this repo): remove `--enable-encoder=eac3` (Dolby encoder;
   we only need decoders, and Dolby decode goes through Apple frameworks where possible). Find every FFmpeg configure
   line the build uses; list the enabled encoders after the change (should be none we don't need — justify any kept).
   Rebuild the engine artefact the app links, confirm the app builds and a fixture plays (E-AC-3 fixture decodes or
   falls back to AVPlayer). If the rebuild is >1 h, stop after the config change + a written plan.
2. scripts/check-appstore-compliance.sh: exclude *.dSYM bundles from the string scans (they caused false hits); keep
   every real binary/extension scanned. Test that it still fails on a planted add-on string in the app binary.
3. Repo hygiene files (repo root): LICENSE (Apache-2.0 full text — confirm it matches the licence the README/About
   screen states; if they disagree, stop and report), CONTRIBUTING.md (short: build, swift test, PR rules), 
   CODE_OF_CONDUCT.md (Contributor Covenant 2.1, contact support@orgista.com), .github/ISSUE_TEMPLATE (bug + feature),
   .github/pull_request_template.md, .github/dependabot.yml (swift + github-actions, weekly), .github/workflows/codeql.yml
   (Swift, macOS runner, manual build of the package `swift build`). Wording: plain, Infuse/Plex style, no add-on words.
4. Public-scrub prep: scripts/release/public-scrub.py blocks test files with /Volumes/ or /Users/ paths. Replace those
   paths in tests/fixtures with neutral ones (env var or relative paths) without changing what the tests check; run the
   scrub in dry-run mode and report it passes.
Gates: serial swift test; compliance --build (8 builds); the scrub dry run; zero-byte + git diff --check.

## Report
## Done / ## Not done / ## Gates run / ## Diff (git status --short + stat) / ## Notes for the reviewer
