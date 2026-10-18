# Stabilize to build-15 quality (owner 2026-10-18)

Owner: "I had a decent app around build 15 and recently it's all gone to shit… use lower usage models, clean up
the code." Build 15 = 27c831f (2026-10-03). Since then: 301 source files, +28.9k/−3.5k lines in Sources, +14.6k in
Tests, in 15 days. Forensics (design/qa/regression-forensics-2026-10-17.md §4) found the causes: unrequested
features, tests that asserted the wrong thing, iOS-27-only proof, merges undoing fixes, judging on no-add-on builds.

## Rules from now on (replace the 10-16 process)

1. **Make what exists work before adding more.** Owner 2026-10-18: "I'm okay with the new features, they are welcomed,
   I just want the app to work." Nothing added since build 15 is removed for being new. Jobs are: (a) rows marked
   *still broken* in design/qa/iphone-feedback-checklist.md, (b) the owner-rejected UI bits in §Removals, (c) new
   owner feedback. REA round-4 feature gaps wait until the broken rows are closed.
2. **Target = build 18's reliability with build 15's cleanliness.** Owner 2026-10-18: "15 was not that reliable either
   but less things were jank; 18 was more reliable but way more jank (metadata wouldn't load, Live added some weird
   pop-up, AI went ham with slop); 15 was more in the correct direction." The owner's 2026-10-16 recording is the
   reference for "jank": Live popup/import card, no metadata, Watching pill, cut-off poster/trailer, word mark below
   the trailer, Open Season unmatched, one-folder-only, duplicated Setup rows, camera alert, IPTV box, Top 10 default,
   health bar stuck, 749-second stream label. Every one is a checklist row; none closes without a phone screenshot.
   **Build 15 is the look reference.** Before fixing a regressed area, diff it against 27c831f. If build 15's behaviour was
   right, restore build 15's code for that area instead of patching the new code (311a53b did this for the title header).
3. **One lane, one row.** One job at a time on the sim lock, one compile-only job beside it. A job = one checklist row
   or one removal. Nothing else may change (anti-slop + Fable review reject any extra file).
4. **Proof = iOS 18.6 sim run of the scoped test once + the owner-phone trace line named in the row.** No 3× repeats
   per job; repeats only at the batch gate. No job may edit a UI test to make it pass; a test change needs the row's
   owner evidence quoted in the commit body.
5. **Models.** Implementation: Codex (`codex exec`, to 100 %) or a Sonnet `implementer` agent. Opus/Fable: lead
   triage, the row's root cause (investigator digest first), and the review. Work Claude only for reviews and 18.6 proof
   jobs. Stop any model at 85 % except Codex/agy.
6. **Owner build after every 3 merged rows** (owner-build.sh with OPENSTREAM_ADDONS, iPhone + OfficePlus 09–17), not
   after a batch of 6–10 branches. The owner's phone is the judge.
7. **Ship only on "ship N".**

## Removals (owner rejected on record, recording 2026-10-16 + forensics §3.9)

- WATCHING pill ("AI sloppy").
- Three of the four Set Up / Send Setup entry points + the "Open the Camera" alert → one "Transfer Setup" row.
- Tappable Recently Added header chevron ("I didn't ask for this").
- Channel Health box on the Settings root ("I never asked for it"); keep it under Live TV.
- Live import card except for a user-started first import ("where this box is coming from").
- Top 10 rows default OFF (owner: "these shouldn't be default").
- Kept (owner 2026-10-18): Live extras, Netflix/Apple TV polish, Plex lessons, PiP, EPG mapping. They must work.

## REA, done properly (owner: "there's a ton of app samples that don't have any of these issues")

Samples on Dev-Mini (`/Volumes/DevExt/dev/rea/targets/`): Apple TV app (TV.app), Infuse 8.5.6, Plex desktop,
Netflix (mobile xapk + Android TV apk), Paramount+ (mobile + Android TV). REA so far produced feature gap lists.
From now on REA is **per broken row, before the fix**:
1. Name the reference that does this exact thing right (trailer reveal → TV.app; bar over art → Netflix/Paramount+
   mobile; disc/local playback → Infuse; Live errors → Plex/Paramount+ Live).
2. Record how it behaves, with numbers (reveal ≤ x s, what shows while loading, what the error state looks like,
   when it retries) using `rea` and the `mobile` MCP on the installed app where possible.
3. That behaviour becomes the row's acceptance measure. The fix copies the behaviour, never the code.
4. Output: ≤ 20 lines appended to the row in the checklist; no new reports.

## Order

1. Finish the four running jobs (b18afix2, ck-visual, ck-data, avp-native2); merge what passes; owner build.
2. Removals above (cheapest, biggest cleanup) → owner build.
3. Still-broken rows by owner damage: 3/21 trailer reveal, 10/11 iOS 18 bar + contrast, 44–46 Live "Can't reach",
   20 metadata, 14 Top-10 shelf shift, 30 title buttons, N7 Channel Health, 61 e2e-18 gate.
4. Full verification spec, RC, "ship 19" on the owner's word.
