# Netflix 8: hero "Mix" (owner decision 2026-10-13)

Owner chose option B from verification-artifacts/remaining-polish-2026-10-13.md ("Netflix 8"). Implement exactly the
"Recommended acceptance rules" there: slot 1 = most recent eligible Continue Watching title; of the remaining four,
reserve up to two for relevant unseen picks (positive taste/relation signal) and one for an unseen recent release
(known release date within 90 days; a year alone is not enough); fill unused slots with today's order. Unseen = no
meaningful progress and not completed; dislikes and inaccessible titles ineligible. Gather eligible sections fairly,
dedupe canonical title+kind, deterministic ties, sparse libraries fall back to today's behaviour. Titles leaving the
hero stay in Continue Watching. Keep the 12 s dwell, focus/offscreen holds, artwork gating, buttons, crop and fade.
Build the deck off the render path (as 1e91143 did). Netflix 11: owner chose no new labels — change nothing there.
Rules: AGENTS.md; unit tests for every rule above; serial Swift suite; E2E-tvOS 20/0 and E2E-iOS 40/1 (AirPlay
known) via Tests/Fixtures/run-e2e.py with sim-dd-internal DerivedData; no commits; clean up after yourself.
