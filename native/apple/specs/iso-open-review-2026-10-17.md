Review is complete. Everything I needed is in hand: the diff, both new files, the spec and lead note, the bridge internals, and how the disc hint and the shared bridge are used. Writing the verdict now.

**Verdict: FIX** (code is sound and shippable; two spec items from the lead note are missing from both the diff and the report's "Not done", plus three small code fixes).

1. **specs/iso-open-report-2026-10-17.md "Not done"** — add the lead note's two unmet items: libbluray main-title tie-breaks (chapters, video, audio) and crash protection for a bad disc (one disc must not crash the app repeatedly). Neither is in the diff and the report does not say so. Unrelated to this lane: the hero cycle and title-page trailer regressions the owner reported are untouched by this diff.

2. **Sources/OpenStreamApple/AppleSMBRangeServer.swift:299** — cache key is URL plus size only, so a replaced file of equal size serves stale blocks for the app's lifetime. `AppleNetworkShare.swift:85` already carries `modifiedAt`. Add `modifiedAt: Date?` to `Session` and `playbackURL(...)` (caller `AppleLocalLibraryStore.swift:1005` has `file.modifiedAt`), and make the key `"\(absoluteString)#\(sizeBytes)#\(modifiedAt?.timeIntervalSince1970 ?? 0)"`.

3. **Sources/OpenStreamApple/AppleSMBRangeServer.swift:286** — `caches(path:request:)` admits any request of 1 MiB or less, so the title stream's first 256 KB to 1 MiB reads after every seek pull one or two whole 1 MiB blocks over SMB (up to 8x amplification on Wi-Fi) and evict structure blocks. Fix: in `AppleSMBBlockCache.caches`, also require `request.lowerBound < 64 * blockSize` or, better, pass `session.sizeBytes` and exclude requests whose offset is inside the BDMV/STREAM region. Simplest exact fix: lower `largestCachedRequest` to `256 * 1024` (the structure reads are exactly 256 KB per the worker's own measurement) so the 512 KB and 1 MiB ramp reads bypass the cache.

4. **Sources/OpenStreamApple/ApplePlaybackCoordinator.swift:1207** — a disc served over HTTP (media server) or from a local file gets no `bytesServed` and the engine on 07afad62 reports no checkpoint until recognized, so it still fails at 20 s. Report says so. Acceptable for this round; add one sentence to the policy doc comment at `ApplePlaybackStartPolicy.swift:38` saying the budget only helps bridge-served discs on this engine revision.

5. **Tests/OpenStreamAppleTests/AppleDiscStartTests.swift:192-245** — the three deadline tests are wall-clock races (100 ms deadline, 30 ms ticker, 150 ms window, 300 ms sleep) and will flake on a loaded mini. The file matches the pattern in `AppleLiveReconnectTests.swift`, so not a blocker, but widen the margins: deadline 200 ms, ticker 50 ms, window 300 ms, and assert `.loading` at 600 ms.

Checked and clean:
- Block cache thread safety: all state lives on the `AppleSMBRangeServer` actor; reentrancy during a miss can only double-read a block, never corrupt. Memory cap holds at 16 x 1 MiB plus one 4 MiB chunk. Short last block, cross-boundary reads and EOF are handled and tested.
- Deadline task: generation and cancellation are re-checked after the actor hop; re-arming from inside the task is safe. Non-disc paths hit no new suspension. All other engine conformers get `startupCheckpoint = 0` from the protocol extension, so tvOS, macOS, visionOS and watch builds are unaffected.
- No UI change, so owner UI rules are untouched. The two launch-argument knobs read only the argument domain and never persist. Anti-slop: comments say why, no dead paths, naming matches the file. `readStats(playbackURL:)` and `count` exist only for tests, which is acceptable.

That stopped job was my own earlier filesystem-wide search, which I had already replaced with targeted greps. Nothing in the review depended on it, and the verdict above stands unchanged: FIX, with the five numbered items.
