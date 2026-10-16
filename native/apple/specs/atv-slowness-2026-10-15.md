# Apple TV general slowness (owner 2026-10-15: "atv has general slowness so something is slowing it down")

Queue job 2 (starts after Stage B + tv-disc-shelf are verified and committed). Devices: OfficePlus (4K 3rd gen) and
DevTV (4K 2nd gen, A12, the floor). Evidence so far, OfficePlus dev build dd8d32d session 2026-10-15 21:29Z
(`/Volumes/DevExt/dev/openstream-build/traces/officeplus-1015.log` on the mini, from line 346):
- **Tab switches take 1.5–2.5 s with a full library:** `tab → search` 87133 ms → `library gone` 89564 ms (2.4 s);
  `tab → search` 95464 → `discover gone` 97009 (1.5 s). With an empty library the same switch took 15 ms.
- **Library metadata resolves 42 s after grouping:** `library grouped: 402 titles` 45674 ms → `eager metadata
  resolved` 88031 ms, overlapping the slow tab switch (suspect main-actor work or view invalidation per resolve).
- **Persisted index thrown away at launch:** `library persisted index unusable: empty after filtering` at 103 ms and
  again at 27366/38217 ms, then a full SMB rescan (`scanned "ServerPlus": 402 files` 7 s). Check whether the filter
  runs before sources load (iCloud sync applying) or the Caches-based index (782bac9) is purged; a TV should open
  with its last index instantly and refresh in the background.
- Recommendation scoring logs ~20 candidates per pass at 1.2 s and 3.0 s (fine, but check it is off-main).

## Do
1. Measure first on DevTV and OfficePlus (dev build via the owner-build recipe in specs/tv-disc-shelf-2026-10-15.md):
   cold launch → first Home frame, hero ready, tab switches (all tabs, both directions), focus move latency in a full
   shelf, title open → art/metadata/Play ready, Play → first frame. Use the trace plus `xcrun xctrace record
   --template "Time Profiler"` (and "Hitches"/"SwiftUI" templates) attached to the device process. p50/p90 over 10.
2. Find the top causes (main-thread work, view invalidation storms, image decode on main, oversized images on the
   A12, repeated index/recommendation recomputes, synchronous disk/keychain on main) with file:line evidence.
3. Fix the top ones, smallest provable changes, each with a test or a trace assertion; keep iOS/iPad/Mac/visionOS
   unchanged unless they share the bug (they likely do: then fix it shared).
4. Re-measure: before/after table. Target on DevTV: tab switch < 300 ms p90, focus move < 100 ms, cold launch to
   usable Home < 2 s with an existing library, no rescan when the index is valid.
Gates: code-anti-slop; serial Swift suite; tvOS/iOS builds; E2E-tvOS (sim) + E2E-tvOS on DevTV; E2E-iOS. Report per
AGENTS.md §7 with the numbers table. No commits.

Lead note 20:05: Fable's Stage B re-review found the launch path rewrote `MediaVersions-v1.json` once per title on the
main actor (AppleLocalLibraryStore.swift:136, AppleMediaVersion.swift:176); being fixed before Stage B commits.
Re-measure with that fix in place before blaming anything else.
