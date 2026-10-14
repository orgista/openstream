# iPhone hero follow-up: the still before the trailer must never crop titled art (2026-10-14)

The uncommitted iPhone hero work (specs/iphone-hero-trailers-2026-10-14.md; files listed in its report) is in the
tree. Lead review of `verification-artifacts/iphone-hero-2026-10-14/AFTER-ios27-discover-still.png`: in the new
full-bleed frame the still is an aspect-fill crop of key art that has the title printed on it — a giant cut-off "SOU"
fills the top half, and the logo overlay then repeats the title below. That brings back owner item 6 ("cut off / too
zoomed") and must not ship.

## Do
- Full-bleed still: textless art only (TMDB null-language poster/backdrop, textless item art). If only titled art
  exists, use the b354bd1 treatment (titled poster as a card on a blurred copy, logo/text title suppressed) inside the
  full-bleed frame; never aspect-fill titled art. Never show the logo over art that already carries the title.
- The trailer cross-fade and gating stay as they are.
- Unit tests for the choice (textless poster, textless backdrop, titled only, nothing). Screenshots AFTER for: a title
  with textless art, a title with only titled art (the sim without a TMDB key reproduces it), iOS 18 and iOS 27.
  Save as `AFTER2-*.png` in `verification-artifacts/iphone-hero-2026-10-14/`.
- Library hero art takes ~12 s to appear (before and after): find why and fix if small; else report the cause.

## Gates
Serial Swift suite, iOS + tvOS builds with recompile greps, E2E-iOS 40/1 (AirPlay) + E2E-tvOS 20/0, all via
`scripts/mini.sh`/buildlock; simulator builds with `-derivedDataPath $HOME/Developer/sim-dd-internal`. Another job
(Codex, metadata resolver/parser/title-page Fix Match) and agy (network-share folders) share the tree: do not touch
their files. Dev-Mini internal disk is at ~6 GB free: delete your own test results/xcresults when done. No commits.
Report per AGENTS.md §7.
