# Vision Pro on the iPad screens, narrowly (2026-10-18)

Owner: "ipad it is!". Vision Pro gets GUI parity with the iPad by using the iPad screens natively.

The first attempt (branch avp-ipad, Codex, stopped 10-17) is not merged. Its review (design/visionos/avp-ipad-review-2026-10-18.md, summarised in
OWNER-TODO) found:
- shared changes on iPhone, iPad, Mac and tvOS that nobody asked for (a custom iPad sidebar, deleted accessibility
  type caps, removed text shadows, a second clamp implementation)
- an owner decision reversed (the immersive player)

Use avp-ipad and its evidence in design/visionos only as a map of what visionOS lacks.

## Do (branch avp-native, from main)
- Change visionOS code paths only (`#if os(visionOS)`, or the visionOS idiom). The iPad itself must not change. If a
  shared file needs a change, its iPhone/iPad/Mac/tvOS output stays byte-identical: prove it with the existing
  screenshot tests or a before/after on the iPad sim.
- On Vision Pro, use the iPad layout in each tab, with the system tab bar and ornaments as visionOS draws them.
- Add hover effects where the iPad uses pointer hover.
- Set the window's default and minimum size so the iPad's regular layout always applies.
- No immersive player (owner decision pending since 10-07).
- Keep accessibility labels unchanged unless a visionOS-only label is missing.

## Proof
- The iPad parity E2E checkpoints (ApplePadParityUITests) on the Vision Pro sim 46B2DEDC: 7 of 7, in one run.
- A before/after screenshot set of the 5 tabs plus a title page.
- The iPad sim (8939801C) runs the same checkpoints unchanged.
- Hold the sim lock only while tests run, and never more than 30 minutes at a time. Split the runs.

Rules: native/apple/AGENTS.md, code-anti-slop, no commits, never print signing identities.
