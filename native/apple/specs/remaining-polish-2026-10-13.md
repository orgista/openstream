# Remaining polish items: measure Apple TV 4/7/8/10, propose Netflix 8/11 (2026-10-13)

The 2026-10-11/12 REA polish lists (specs/rea-appletv-netflix-polish-2026-10-11.md, rea-deep-dives-2026-10-11.md and
the reports they point to in verification-artifacts/) left these out: Netflix 8 and 11 ("need owner review") and
Apple TV 4, 7, 8, 10 ("measure first"). Apple TV 1 (titles on posters) is done (12aa663). Read AGENTS.md first.

1. Find each item's definition in those specs/reports and quote it in your report.
2. Apple TV 4/7/8/10: measure first, on the tvOS simulator (sim-dd-internal DerivedData, stub fixtures,
   `Tests/Fixtures/run-e2e.py` or a focused UI test + traces). If the measurement shows a real gap and the fix keeps
   the approved look, implement it (smallest change, unit tests). Else report the numbers and stop.
3. Netflix 8 and 11: do NOT implement. Write a one-page proposal each (what, why, the owner choice needed, options
   with a recommendation), using Muse's research in verification-artifacts/muse-2026-10-12/ (103 hero candidates,
   104 badges) and the REA reports. Put both in verification-artifacts/remaining-polish-2026-10-13.md.
4. Gates for anything implemented: serial Swift suite, E2E-tvOS 20/0 and E2E-iOS 40/1 (AirPlay known).
No commits; clean up after yourself; Mac mini disk is tight (~20 GB).
