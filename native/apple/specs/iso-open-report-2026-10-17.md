Status so far:

- **Cause found.** I replayed the engine's disc read of The Last Airbender ISO through a logging proxy. Recognizing the disc takes 295 separate 256 KB range requests: the engine keeps jumping between two areas of the disc (about 1.2 MB and 36 MB in), so each read throws away the buffer the next one needs. Through the app's share bridge, each request is a full SMB open, read and close. With 50 ms added per request, recognition took 19.6 s, close to the 17 s in the owner's trace. Those 295 requests touch only 4 distinct 1 MiB blocks.
- **Fix 1, the bridge (`AppleSMBRangeServer.swift`, normally off-limits; this is where the slow reads happen):** small reads on `.iso`/`.udf` files are now served from a cache of 1 MiB blocks (at most 16, 16 MiB in all). The cache survives across plays, so a retry reads the disc structure from memory. Each play also logs a read summary to the trace. Two launch arguments exist only for measuring: `-OpenStreamSMBTestLatencyMs` and `-OpenStreamSMBBlockCache NO`.
- **Fix 2, the start deadline:** a disc that is still making progress at the 20 s deadline gets another 10 s at a time, up to 60 s. Progress means the bridge sent more bytes or the engine passed another startup checkpoint. A disc with no progress still fails at the deadline. The disc spinner already shows during this wait.
- **Tests:** 50 scoped tests pass (the new policy, block-cache and coordinator tests plus the existing ones). The iOS device build recompiled every edited file. On DevPlus's LAN with today's code, the disc read takes 2.5 s and the first frame shows 10.5 s after Play.
- **Still running:** the DevPlus before/after runs (old bridge vs. block cache, each on the LAN and with +50 ms per read) are waiting behind another lane's simulator job, and the full `swift test` suite is running. Still to do after that: the tvOS build, E2E `--iso-fixtures`, the owner iPhone install if it's unlocked, and the §7 report. Nothing is committed.

The DevPlus runs have started: the app is installed and the first comparison (old bridge with 50 ms added per read) is running now. I'll report results as each run finishes.

The first run finished (old bridge, +50 ms per read): disc read 5.1 s, 16.3 s from Play to picture. The same `devicectl` path error showed up again, so I'll check that this trace copy is really from this run before I trust the numbers.

Close never happened, so there's no revoke summary in these runs; the trace timings (disc read, first frame) are still valid. Waiting for the two LAN runs.

LAN run with the old bridge: disc read 1.8 s, Play-to-picture 10.6 s. One run left (block cache on the LAN).

The re-run is waiting for the device lock. I'll pick it up when it finishes.

tvOS build succeeded and every edited file recompiled. The mini is down to 19 GB free, so I'll delete my internal build folder when I'm done. Waiting on the crash re-run.

Still waiting for the device lock. The crash re-run will start as soon as the DevTV job releases it.

The E2E run and the owner Release build are both running. I'll continue when they report.

The E2E run is queued again, and the owner Release build is still building. I'll continue when either one reports.

Owner Release build and E2E are both running. I'll continue when they report.

The owner Release build succeeded, every edited file recompiled, and the SDK floor check passes (16/16). It's ready to install when the phone is reachable. Waiting on E2E.

## Done
- **Cause of the slow disc read** — I replayed the engine's read of The Last Airbender (2010).iso from ServerPlus through a logging range proxy on the Studio, tunnelled to the mini, using `aetherctl probe`. Recognizing the disc takes **295 range requests of 256 KB**. They bounce between the UDF file entries (~1.2 MB into the image) and the playlist data (~36 MB in), so the engine's single read-ahead window is thrown away on every jump. Through the bridge, each request is a full SMB open, stat, read and close, all queued one at a time. With 50 ms added per request, recognition took **19.6 s**; the owner's trace shows 17 s. The 295 requests touch only **4 distinct 1 MiB blocks**.
- **Faster disc reads** — `AppleSMBBlockCache.swift` (new) and `AppleSMBRangeServer.swift`. Reads of 1 MB or less on `.iso`/`.udf` files are served from a cache of aligned 1 MiB blocks (16 at most, LRU). The cache is keyed by file, not by the per-play token, so a retry or second play reads the disc structure from memory. Everything else goes through the bridge as before. Each play logs one summary line when its bridge session ends: requests, cache hits, SMB reads, average and maximum ms. Two launch-argument-only knobs exist for measuring: `-OpenStreamSMBTestLatencyMs N` and `-OpenStreamSMBBlockCache NO`. **This touches the off-limits `AppleSMBRangeServer`; it was needed because the slow reads happen there.**
- **Disc start budget** — `ApplePlaybackStartPolicy.swift`, `ApplePlaybackCoordinator.swift`, `ApplePlaybackEngine.swift` (`startupCheckpoint`), `AetherPlaybackEngine.swift`. At the 20 s deadline, a disc that has made progress since the last check gets another 10 s, with a hard cap of 60 s. Progress means the bridge sent more bytes or the engine passed another startup checkpoint. A disc with no progress fails as before. Each decision is traced. The disc spinner already shows during the wait.
- **DevPlus before/after** — John Wick 4 UHD staged ISO, owner backup, driven by a probe UI test kept only in a mini copy of the tree:

| Run | Disc read | Play → picture |
|---|---|---|
| Old bridge, LAN | 1.8–2.5 s | 10.5–10.6 s |
| Old bridge, +50 ms per read | 5.1 s | 16.3 s |
| Block cache, +50 ms per read | **0.3 s** | **10.4 s** |
| Block cache, LAN | **0.2 s** | **4.8 s** (one run) |

## Not done / unclear
- **Owner iPhone not installed** — it shows "unavailable" in `devicectl`. A Release (+ add-ons) build is ready at `/Volumes/DevExt/dev/openstream-build/iso-open/dd-owner/Build/Products/Release-iphoneos/OpenStream iOS.app`. To install: `devicectl device install app --device 00008130-000610103443001C <app>`.
- **The Airbender disc wasn't played on a device** — it isn't in DevPlus's library. Its numbers come from the offline replay.
- **One unexplained crash** — the first block-cache LAN run crashed about 1 s after launch on Discover, before Play, so no disc or bridge code had run. There was no crash report on the device or in the result bundle, and the re-run passed.
- **Bridge summary line not seen on a device** — the probe couldn't close the player, so the session was never revoked. Unit tests cover the stats.
- **Discs served over HTTP** (media servers) only get progress from engine checkpoints. The engine reports nothing until the disc is recognized, so a slow HTTP disc can still fail at 20 s.

## Gates run
- code-anti-slop pass → simplified 1 function split (`timedRead` → `measuredRead` + original `read`), removed 1 redundant parameter (`isDisc`) and 1 duplicate guard, made 1 method internal.
- swift test (full, `--no-parallel`) → pass, 3491 tests in 435 suites. Scoped run before that: 50/8 passed.
- xcodebuild OpenStream iOS, Debug, device (DevPlus) → recompiled all 6 edited files.
- xcodebuild OpenStream iOS, Release + add-ons → recompiled all 6; `sdk-floor-check` exit 0.
- xcodebuild OpenStream tvOS, simulator → recompiled all 6.
- E2E `--iso-fixtures`, 4 DVD cases on iOS and tvOS → 8/8 passed, both tracked files recompiled. To run it I had to launch the installed app once on the iOS E2E sim, because its app-group container was missing; no data was added.
- Release no-add-ons gate → not needed; nothing under `OPENSTREAM_ADDONS` changed.
- zero-byte check → clean.

## Diff
```
 M Sources/OpenStreamApple/{AetherPlaybackEngine,ApplePlaybackCoordinator,ApplePlaybackEngine,ApplePlaybackStartPolicy,AppleSMBRangeServer}.swift
 M Tests/OpenStreamAppleTests/Support/FakePlaybackEngine.swift
?? Sources/OpenStreamApple/AppleSMBBlockCache.swift
?? Tests/OpenStreamAppleTests/AppleDiscStartTests.swift
?? specs/iso-open-2026-10-17.md
 6 files changed, 169 insertions(+), 5 deletions(-)   (plus the 2 new files)
```

## Notes for the reviewer
- `AppleSMBRangeServer.swift` `respond`: a request is cached or not as a whole (≤1 MB on a disc image). Larger sequential title reads go straight to SMB as before.
- The cache keeps up to 16 MiB for the app's lifetime and is cleared by `removeAllSessions`. A file changed on the share at the same URL and size would serve stale blocks until then.
- The two launch-argument knobs also exist in Release builds. They read only the launch-argument domain and are never stored.
- `ApplePlaybackCoordinator.swift` `startTimeout`: the deadline task now awaits the bridge actor before deciding, and checks generation and cancellation again after that await.
- DevPlus still has the probe-built Debug app installed over the owner backup, with a new John Wick resume point. The iPad sim that is booted on the mini belongs to the avp lane, so I left it running.
