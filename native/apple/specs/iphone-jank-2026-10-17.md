# iPhone (owner's 15 Pro Max, iOS 18) jank: every reported item, verified on iOS 18 — TOP PRIORITY (owner 2026-10-17)
Owner: "It's on iPhone ... there is just so much jank that you didn't put into account from my feedback" and "I feel
like app has gotten overall worse but better in some ways". Our checks ran mostly on iOS 27 sims and only proved
screens open. This job fixes the method AND the jank.

## 0. The checklist (first deliverable, before code)
Build design/qa/iphone-feedback-checklist.md: EVERY iPhone/iOS item the owner reported, from native/apple/OWNER-TODO.md
(open and closed since build 16), specs/iphone-recording-1015-2026-10-16.md, specs/iphone-ios18-discs-2026-10-15.md,
the owner feedback log on Dev-Mini (/Volumes/DevExt/dev/openstream-build/owner-feedback.log) and today's messages
(ISOs fail, hero cycle gone, title-page trailers worse than build 15 = commit ad66774, general jank). One row each:
item, where reported, current status ON iOS 18 (verified / still broken / not checked), evidence path.

## 1. Evidence from the owner's phone (main 72966f9 installed 09:0x)
Trace /Volumes/DevExt/dev/openstream-build/traces/iphone-1017b.log (session 14:53Z):
- Discover phone hero relayouts continuously: `discover phone hero layout` top inset oscillates 97↔115 pt and
  `hero drawn` fires repeatedly (3.6 s, 4.1 s, 4.9 s, 5.4 s, 5.9 s, 6.3–6.7 s every ~16 ms) — the 750 ms "settled
  layout" fix does not hold on hardware. Find the source (nav bar inset animation, safe-area changes from the
  transparent bar, scroll offset feedback loop) and make the hero layout independent of it.
- ISO: disc read 17 s then 20 s startup timeout (separate job iso-open handles it; just record).
## 2. Verify and fix
For each checklist row: reproduce on the iOS 18.6 sim 7530ECB2 (owner's imported setup) with screenshot sequences
(10 fps around the interaction via simctl io recordVideo + frame extraction) and trace counts; fix; re-verify on
iOS 18.6 AND iOS 27; add a regression test that asserts the owner-visible behaviour (e.g. "hero drawn" ≤ 2 times
per page, no layout oscillation, no blank > 1 s). Hero cycle + title-page trailers: wait for
design/reference-apps/2026-10-17-rea-hero-trailers-disc.md (REA round 3, running) before changing their behaviour;
until then only record the before-state (what build 15 ad66774 did vs now).
## 3. Owner device
Final: install on the owner's iPhone (00008130-000610103443001C) only if unlocked, pull its trace after the owner
uses it; never wipe data. DevPlus (iOS 27) for a second device. Never OfficePlus.
Gates: code-anti-slop; serial swift; iOS 18.6 + iOS 27 builds; E2E-iOS on both (no new failures); the checklist with
evidence. No commits. Report per AGENTS.md §7 with the checklist summary (counts: verified / fixed / still open).
