# Vision Pro: real end-to-end coverage and a fast device pass (owner 2026-10-15)

Owner: "we need e2e testing on avp cause its not great rn its probably the worse out all ... we gotta keep trying now
we have a full time ap tv iphone and [avp]". Today the visionOS suite is 5 player tests
(`Apps/OpenStreamVisionUITests/AppleVisionPlayerUITests.swift`); iOS has ~7,800 lines of UI tests and tvOS ~2,300.
The Vision Pro **VP** (`00008112-001150E40C41A01E`) is paired with Dev-Mini, but it sleeps unless worn, so the bulk
runs on the Vision Pro simulator (`46B2DEDC…`) and the device gets a short owner-worn pass.

Read native/apple/AGENTS.md first. Use the `rea` MCP to see how Apple's TV app and Infuse lay out the visionOS app
window, tab ornament, title page, player, docking and environments (design notes only; never copy code or assets).
Codex/agy: run to 100% of your window (owner rule).

## 1. E2E-visionOS (simulator), the main deliverable
Grow `OpenStreamVisionUITests` into a crawl matching what E2E-iOS/E2E-tvOS cover, using the same fixture server and
owner-content seeding (`scripts/seed-sim.sh`):
- first launch → No Sources → add a share/Direct URL; every tab in the ornament; Discover/Library/Live rows load
  with art and titles (no blank buttons: the 2026-10-08 Live category bug); search; settings pages open and close;
- title page: hero, metadata, versions, episodes, Play/Resume, trailer;
- player: window takes the film's shape and gives it back; transport, scrub, audio/subtitle menus, skip, next
  episode, end of clip, failed stream stays in the window; one window after relaunch; resume point saved;
- every screen: an accessibility audit (`performAccessibilityAudit`) and a screenshot through
  `OPENSTREAM_VISION_CAPTURE_URL` (XCUIScreen returns 1×1 on this runtime) saved for review;
- glass/hover/legibility: text on glass meets contrast, nothing clipped at the default and smallest window size.
Fix the app bugs the crawl finds (small, tested, one at a time); list larger ones in the report.
Gate: 3 consecutive full E2E-visionOS runs at 0 fails, through buildlock, foreground, internal
`-derivedDataPath $HOME/Developer/sim-dd-internal`. Add the run to the scripts that run E2E-iOS/E2E-tvOS.

## 2. Device pass the owner can do in 5 minutes
`scripts/vp-device-pass.sh` (on the mini, under buildlock): builds scheme `AppStore-visionOS` Debug for
`id=00008112-001150E40C41A01E` with automatic signing (`-allowProvisioningUpdates`, the ASC key in ~/.asc config,
team 2VQ74PD5YG; the device is registered as of 2026-10-15), **before** the owner puts the headset on, then waits
for the device to be awake (`devicectl list devices` state), installs, launches, and after the pass copies
`Library/Caches/openstream-trace.log` from the app data container (`devicectl device copy from --domain-type
appDataContainer --domain-identifier com.orgista.openstream`). Also try the XCUITest suite on the worn device and
report what works. Printed checklist (≤6 lines): environments docking, closing the window stops audio, one window
on reopen, real NAS file with Atmos/HDR, Digital Crown, look-and-tap targets.

## Report
Per AGENTS.md §7: tests added, bugs fixed (with trace/screens), bugs left, the run log of the 3 green runs, and the
device-pass result if the owner wore it. Workers never commit.
