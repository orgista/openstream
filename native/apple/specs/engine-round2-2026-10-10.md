# Engine round 2 (OWNER-TODO "Engine lab" + finish-spec #34) — 2026-10-10

The AetherEngine fork is NOT missing: a full checkout (branches main, dvd-menus, engine-lab; origin = the owner's GitHub fork)
is in the ServerPlus backup root@serverplus:/mnt/galatic/backups/studio-openstream-build-2026-10-06/AetherEngine-fork
(use `git -c safe.directory='*'` there; read-only — never modify the backup).

1. Restore it to Dev-Mini at ~/Developer/openstream-build/AetherEngine-fork (rsync/tar over ssh from ServerPlus; keep .git).
   Push both branches to origin: `git push -u origin dvd-menus engine-lab` (owner authorised pushes to their own repos).
   If push auth fails on the mini, try from the Mac Studio with a fresh clone of the backup; report if both fail.
2. Corpus: Scripts/engine-lab/fetch_corpus.py + corpus.json rebuild the 98-file lab (~4.4 GB). Put it on the external drive
   /Volumes/DevExt/engine-lab/corpus (check /Volumes/DevExt/.devext-ok first; public test media only, nothing secret) and
   point lab.py there (symlink ~/Developer/openstream-build/engine-lab -> /Volumes/DevExt/engine-lab). The mini's internal disk
   is tight (~27 GB) — do not put the corpus on it.
3. Run the lab baseline (scoreboard), then fix the next round in the fork on engine-lab: AV1 stutter after seek, truncated
   files stalling 12 s, interlaced TV freezes, VC-1 ending early. Before/after scoreboard numbers for each. Commit in the fork
   (small commits; you MAY commit in the fork repo) and push engine-lab.
4. Integrate into OpenStream: see how native/apple pins AetherEngine (Package.swift / Package.resolved / xcodeproj). Point
   it at the pushed fork revision only if that is how it is already wired; otherwise write exactly what change is needed.
   Run the full swift test gate on the mini (scripts/mini.sh + buildlock) — must stay >= 3018 green. Do NOT commit in
   OpenStream (its AGENTS.md forbids it); leave the diff and the lead commits.
5. #21 native-HLS measurement: use Apple's public HLS test streams (developer.apple.com bipbop / advanced examples) as the
   native HLS sample; do the measurement. A12 Apple TV hardware stays an owner check.
6. Update OWNER-TODO.md: close "Engine lab" and the #34 owner-action line with evidence, or leave one plain owner line.
Rules: builds/tests only on Dev-Mini through buildlock; never print secrets; usage board before long steps; at the end:
done / not done / owner actions.
