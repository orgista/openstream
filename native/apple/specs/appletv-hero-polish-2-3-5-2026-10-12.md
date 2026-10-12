# Apple TV hero polish: items 2, 3, 5 (2026-10-12)

Source: design/reference-apps/2026-10-11-appletv-hero-gui.md "Polish list". Owner: the Apple TV app is the main GUI
reference for heroes; "our design is in a good place", so polish, not redesign. Claude picked these under the
keep-building rule. Item 1 (tvOS posters without titles) is held for the owner: it predates the rule and matches the
Apple TV app, so do not change it.

Read native/apple/AGENTS.md and the report first. Scope:
2. AppleTVBillboardView.swift ~70 / AppleHeroScrim.swift ~119: bright art gets an extra leading fade on top of the
   approved billboard fade. Owner rule: only the approved billboard fade, no extra scrims. Remove the extra path and
   keep title/metadata readable over bright art by the existing means (logo shadow / text treatment already in the
   approved design, not a new gradient). Check the matching iPhone/iPad/Mac paths and apply the same rule.
3. AppleHeroPageGate.swift ~25 / AppleHomeTVHeroCarousel.swift ~75: the page dwell clock runs while the next art is
   still gated/loading, so slow art gets a short visible dwell. Start the dwell when the page is actually shown (title
   and art swap together, as now). Manual paging and the page indicator stay in sync; Reduce Motion unchanged; the
   12-second interval unchanged. Tests for the clock policy.
5. AppleDiscoverView.swift ~1222: Continue Watching has no full-list action when entries are capped. Add the header
   destination using the existing header-button pattern (AppleMediaShelf.swift ~21) only when more entries exist than
   the rail shows; the list shows all resumable entries with the same cards/progress. No new explainer text.

Rules: as specs/todo-finish-2026-10-09.md "Rules", except **do not commit**; the lead reviews and commits. Builds/tests
on Dev-Mini via scripts/mini.sh + buildlock.sh only. Full Swift suite green, count >= 3044 plus new tests (touch edited
files first); build tvOS and iOS. Look at the tvOS hero on a sim with the owner config seeded (scripts/seed-sim.sh,
-OpenStreamMuteAudio YES) and attach before/after screenshots under verification-artifacts/ for item 2. No uploads, no
secrets, no git stash/checkout/reset, don't touch native/google-tv. Keep heavy work out of SwiftUI body. Add one
OWNER-TODO.md Done line per item with evidence. End with done / not done / next.
