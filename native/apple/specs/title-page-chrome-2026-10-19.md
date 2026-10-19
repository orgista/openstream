# Title (content) page chrome like the Apple TV app on iPhone (rows 76 + 10/11/30, owner 2026-10-19)

Owner on build 1018d: "content page looks not like Apple TV, there is a solid bar at the top; there is a search icon
we don't need. Open Apple TV on iOS — it does not have a bar." Branch `title-page-chrome` from main b8ed703.
Parent plan: specs/stabilize-2026-10-18.md. Build 15 is the look reference; the Apple TV app is the behaviour
reference. This supersedes the ck-visual solid-bar fix (rows 10/11) ON THE TITLE PAGE and the round-button style
(row 30) if the TV app does it differently.

## REA first (≤ 25 lines in design/reference-apps/2026-10-19-tv-app-title-page.md)
- Apple TV app on the iOS 18.6 simulator (`7530ECB2…`, TV.app is preinstalled) via the `mobile` MCP: open a film's
  page; record with element list + screenshots: is there a navigation bar at all? What sits over the art at the
  top (back button only? style: circle material / plain glyph?), how do the bar/buttons behave when scrolling
  (does a title bar fade in?), is there a search control on the page (no), where does the hero art start (under
  the status bar?), gradient at the top for status-bar legibility. Measure: top inset, back-button size and
  style, scrim height. Same for a show's page. Owner screenshots, when the lead appends them below, win over the sim.
- Compare ours on the same sim, same title: screenshot + element list.

## Fix (smallest, iPhone only; tvOS/Mac/visionOS untouched)
- Title page: no solid bar. Back control over the art the way the TV app does it; no search control on the title
  page (remove it; search stays on Discover/Library). If the TV app fades a title bar in on scroll, do the same.
- Status-bar legibility over bright art via a top scrim/gradient, not a bar (owner fix #52 was about icons being
  unreadable; solve it the TV app's way).
- Discover/Library bars: leave as they are in this job (separate row if the owner asks).
- Proof: iOS 18.6 owner-profile sim (protected.py), screenshots of 3 title pages (bright art, dark art, show) at
  rest and after scrolling, side by side with the TV app's; iOS 27 unchanged where iOS 26+ glass applies (say so);
  `swift test` compile lane; iOS build; UI tests that referenced the title-page search button updated with the
  owner's words quoted; code-anti-slop; zero-byte.
Builds/sims only on Dev-Mini via scripts/mini.sh (`OPENSTREAM_MINI_DEST='~/Developer/openstream-build/lanes/title-page-chrome'`).
FIFO locks; never kill other jobs (a batch gate is running). No commit. Report: REA findings, change (file:line),
screenshot paths, gates, `git status --short`.

## Lead 2026-10-19 11:50 — proceed without the simulator observation
The iOS simulator has no runnable TV app and the mobile agent is missing; the owner's screenshots are pending. Do
NOT wait. Build to this reference, which is the Apple TV app's iPhone content page as shipped on iOS 18 (the lead
will append the owner's screenshots and any deltas; adjust then):
- No navigation bar. The hero art bleeds under the status bar; a short dark gradient at the very top keeps the
  status bar legible.
- Top-left: a Back chevron in a small circular translucent (material) button over the art. Top-right: NO search;
  the TV app has at most a "…" (more) control there — ours has no equivalent, so nothing on the right.
- Title treatment (logo or text) over the lower part of the art, then the Play button and metadata line.
- On scroll: once the art has scrolled away, a compact bar with the title fades in (standard inline large-title
  collapse), with the same circular back button.
- Nothing else about the page changes (rows, trailer behaviour, buttons below the hero).
Rows 10/11 (Discover bar) stay as they are; row 30's round button style may be reused for the Back control only.
Proof as in the spec (three title pages at rest and after scrolling on the iOS 18.6 owner sim, iOS 27 note),
gates, UI tests updated for the removed search control with the owner's words quoted: "in the content page
there is a search icon we don't need" (2026-10-19).
