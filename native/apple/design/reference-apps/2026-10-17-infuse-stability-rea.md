# Infuse stability REA, round 4 (2026-10-17)

Spec: `specs/regression-and-rea-2026-10-17.md`, Job R3. Static reading of Infuse 8.5.6 (`Infuse-arm64`, the Mac Catalyst
slice, plus `StratospherixLibSMB`, `libnfs`, `libbluray`, `libudfread` from `Infuse.app`) against OpenStream `main` 72966f9 and
the pinned AetherEngine 07afad62. No build, no device, no runtime capture; nothing copied. Infuse addresses are virtual
addresses in `Infuse-arm64` (file offset + 0x100000000); `L:n` is a line of its decoded `en.lproj/Localizable.strings`.
Builds on `2026-10-11-infuse-engine-sources.md` (inventory) and `2026-10-17-rea-hero-trailers-disc.md` §3 (disc pipeline);
only what is new or deeper is here.

**Platform caveat.** The binary is the Mac build. Its playback core (FFmpeg demux, VideoToolbox decode, FCMediaPlayer, the
network input streams) is the same code on tvOS and iOS, but UI timings and the memory numbers are not transferable.

## Top 10 stability fixes (ranked)

Each fix names the evidence on both sides and a number to measure it by.

1. **Open a disc in bulk, and remember it.** Infuse reads a disc image through one cached block reader whose read-ahead loader
   preloads the END of the file first, then the start (UDF keeps its anchor at the end), so the whole UDF/BDMV walk costs a
   few large reads (§4). Ours walks it sector by sector: `UDFReader.swift:21,73` reads 2048-byte sectors through
   `HTTPDiscIOReader.swift:102-128`, whose window restarts at 256 KB on every non-contiguous read (`:47-52`), and every window
   is a new loopback HTTP request that opens, reads and closes an SMB file handle (§3). Owner trace: UDF/BDMV recognised 14.1 s,
   13.9 s and 6.8 s after Play on the iPhone (`owner-iphone-1015.log:4703-4810`), 9.7 s on OfficePlus
   (`officeplus-1017b.log:663-665`), inside a 17.1 s Play-to-first-frame. The engine's `DiscRecognitionCache` is per process
   and keyed per title, so the second open of the same disc after relaunch parses again. Targets: cold open ≤ 2 s on the
   iPhone over SMB, warm ≤ 0.3 s; range requests during a disc open ≤ 10 (count them in the trace next to `discFetchedMB`).

2. **One SMB file handle per playback, streamed as it arrives.** Infuse opens the file once (`-[FCSLSMBInputStream open]`,
   0x10008ae9c, "Will open a file with path") and every later read is a positioned async read on that handle
   (`-[FCSLSMBAsyncReader readWithOffset:initialOffset:size:buffer:completion:]`, 0x100200c10) sized to the host's negotiated
   max read size ("[SMB] Max read size for host '%@' = %llu", 0x1ffdeb1) with partial reads handled ("Received only %d bytes
   out of %d", 0x1ffdfc6). Ours: `AppleSMBRangeServer.swift` answers each range GET with `Connection: close` (`:236`) and reads
   4 MiB chunks (`:242`) through `AppleSMBClient.read` (`AppleNetworkShare.swift:490-518`), which calls AMSMB2
   `contents(atPath:range:)`; that call creates a new `SMB2FileHandle` per request (`AMSMB2.swift:964-1012`) and the whole
   4 MiB is collected before the first byte goes to the player (`AppleSMBRangeServer.swift:246-251`). So one Play is
   CREATE + N×READ + CLOSE per 4 MiB, and a new TCP connection per request; Infuse is one CREATE for the session. Targets:
   first byte of a chunk < 50 ms after the request on the LAN; one SMB open per play (log `smb opens` per session).

3. **Short versus full buffering, and count the reloads.** Infuse's `-[FCMediaPlayer startBufferingFull:]` (0x1000bd958) tells a
   "short" buffering from a "full" one: a short one is skipped (no pause, nothing drawn) when the demuxer already has ready
   packets (`hasReadyPacketsOf:`) and the previous skip is less than 0.5 s old (`fmov d9, #0.5` at 0x1000bdaf4,
   `skippedShortBufferingDate`); a full one pauses the synchroniser (`pauseReset`), buffers audio and video and sets the
   demuxer to reduced buffering. Full bufferings are counted into the stats HUD as "Buffer reload count" (`L:251`), next to
   "Buffer status: Healthy/Empty" (`L:252-254`), stream speed and network throughput. Ours surfaces every engine
   `.rebuffering` at once (`ApplePlaybackCoordinator.swift:1083-1086`); the traces show 2 to 8 "rebuffering" lines per
   session on the owner's phone (`owner-iphone-1105.log`), and nothing counts them. Targets: no visible waiting state for an
   underrun under 500 ms; one summary line per session with full-rebuffer count and time spent waiting.

4. **A probe ladder with a hard deadline on every FFmpeg call.** `-[FCFFMPEGDemuxingStream open]` (0x10007f008) opens with
   probesize 10,000,000 (0x10007f110-114), and if the format or streams are missing it frees the contexts, clears the buffer,
   seeks to 0 and retries with 50,000,000 (0x10007f190-194; "[Demuxing] Will try to open with increased probesize").
   `performOpenOperationWithProbesizeLimit:` (0x100080c00) runs the open under `performOperationInTime:60000:` (0x100080c70),
   whose interrupt callback `fcFFMPEGInterruptionCheck` (0x100158b3c) aborts the FFmpeg call at the 60 s deadline ("Reached
   deadline for current FFMPEG operation!!!"). Ours: `Demuxer.swift:84-98` uses 50 MiB probesize for playback and a 35 s AVIO
   request timeout, 2 MiB / 8 s for the side probe, 4 MiB for the probe at `:141`, and a read deadline only on seeks
   (`:1537-1551`, `beginReadDeadline`); `avformat_open_input` / `find_stream_info` (`:406,504,588`) have no interrupt callback,
   so a share that stops answering mid-open holds the pump until the socket times out. Target: no open or find_stream_info
   outlives 60 s; a dead share fails the press with the network message inside 60 s every time.

5. **Fall back to software decoding after 3 failed chunks, mid-play.** `-[FCAVHardwareDecoder decodeFallback:outMediaUnit:]`
   (0x10003f378) marks the chunk failed, increments `chunksFailedInARow`, does a "soft switch" to the software decoder for
   the chunk and, at 3 in a row (`cmp w0, #3` at 0x10003f410) or when `avoidSoftSwitchToSW` is set, a "hard switch"
   ("[Decoder] Hard switch to SW decoder"); `openFallbackDecoderIfNeededWithChunkDecoder:currentChunk:` (0x10003f1c8) opens the
   software decoder at the chunk's start time with the same output format. Ours decides the route at load
   (`CodecRoutePolicy.swift`, `RerouteVerdictMemory.swift`) and a hardware decode that dies mid-play ends the item
   (`NativeAVPlayerHost.swift:750-760` counts `playbackStalled`; `AetherEngine.swift:1899` confirms item death after 3 s).
   Target: a HEVC/DV file whose hardware decode fails after the first frame keeps playing within 1 s, no alert.

6. **Retry reads for 120 s before giving up.** `-[FCRetryingInputStream retryToReadBuffer:ofSize:]` (0x1001feb3c) keeps
   `retryStartDate`, reopens the inner stream at the current position (`reopenWithPosition:`, 0x1001fed24) and retries while
   less than 120.0 s have passed (`0x405e000000000000` at 0x1001feba8), stopping early only for a specific error code (`cmp
   w20, #0xb`). The HTTP stream has the same shape ("[HTTPStream] Will retry reading at …", "exceeded retry deadline",
   0x100ce89a4 / 0x100ce8b50) over a pooled curl connection set (`HTTPStreamConnectionPool.swift`). Ours: the Matilda MKV
   session on the phone died at 273 s of play: `forward prefetch read failed … (Operation not permitted (-1))`, pump
   teardown, `seg28: cache miss after 12865ms`, `early-header serve missed; closing connection for AVPlayer retry`, then an
   `AVAudioSession interruption BEGAN` (`owner-iphone-1015.log:4580-4588`). `AVIOReader.swift:518-532` reconnects on a 20 s
   stall with up to 12 unproductive reconnects, but the prefetch exited on the first failed read. Target: zero
   `early-header serve missed` lines across a 10-minute LAN play; a pulled cable for 30 s resumes without an alert.

7. **A main-thread freeze monitor in every build.** Infuse ships `FCMainThreadMonitor` (0x100035c14): on launch and on every
   return to foreground it starts `FCFreezeMonitoringThread` with a 1.0 s threshold (`fmov d0, #1.0` at 0x100035d0c and
   0x100035df8) and an `FCStackTracer` that captures the main thread's frames (`traceForMainThread`). Ours is
   `AppleDebugMainThreadWatchdog.swift:1`, `#if DEBUG && os(macOS)` only, so the 540-763 ms hangs iOS's Hang Detection HUD
   showed on the owner's phone (`specs/iphone-recording-report-2026-10-16.md:31,35`) have no trace. Target: any main-thread
   stall over 1 s writes one trace line with the top 8 frames, in TestFlight and owner builds.

8. **Measure Play to first frame, and flag the slow ones.** `FCVVCStartupDurationMeter` (`startMeasuring`,
   `considerPlayerState:` at 0x1001c9548, `firstFrameProduced` at 0x1001c971c) keeps `startupDate` and `firstPlayingDate` and
   compares the startup against 3.0 s (`fmov d0, #3.0` at 0x1001c96d0). Ours traces "first frame, route=" per press
   (`ApplePlaybackCoordinator.swift:1061`) and nothing aggregates it. From the traces: live 1.4-3.0 s when it works
   (`owner-iphone-1017.log`), with presses that never produced a frame and were re-pressed after 11 s and 35 s
   (`:2285-2308`, `:934-973`); on-demand 2.8 s for a 4K DV MKV over SMB; 17.1 s for a UHD ISO on OfficePlus. Target: a
   per-session summary (p50/p90 of Play-to-first-frame, count over 3 s) in the trace and in the diagnostics report.

9. **React to memory pressure.** Infuse's read-ahead loader refuses to preload when there is no free memory ("[ReadAhead] No
   free memory to preload", 0x100d015f4) using `os_proc_available_memory` (imported, `nm`), logs free memory when a demuxer
   is torn down ("Deallocating ffmpeg stream … (Free Memory = %@)", 0x1ffbe75), handles `applicationDidReceiveMemoryWarning:`
   (0x10029d9d8) and gives the user a Streaming Cache setting (Legacy / Memory Only / Limited, `L:746-749`). AetherEngine has
   no memory-pressure or memory-warning hook anywhere (grep of `Sources/AetherEngine`), and neither does the app; the
   segment cache is bounded by count only (10 forward, 20 back, `SegmentCache.swift:103`), the disk retention budget is 2 GiB
   or a quarter of free space (`HLSVideoEngine.swift:766-770,1318-1331`), and the engine's own comment puts the tvOS budget
   at 500-800 MB (`:784-785`). Measured: rss 530 MB with cacheMB 535 on the iPhone for Matilda (`owner-iphone-1015.log:4490`),
   319-363 MB on OfficePlus. Target: a memory-pressure source in the engine that halves both windows and stops prefetch;
   rss ≤ 400 MB on the iPhone for the same file.

10. **Crash guards per item, and fixed-priority player threads.** Infuse persists failures per item
    (`com.firecore.infuse.FileFetchingCrashes.plist`, read in 0x100005f04 under a lock; `ShareIndexingCrashes.plist`) and
    refuses a disc that keeps crashing ("Bluray item seems to be crashing, won't open it", 0x100ba0dd8). Its player stages
    run on `FCPlayerThread` (0x1001160d8): `pthread_create`, then `thread_policy_set(THREAD_EXTENDED_POLICY, timeshare = 0)`
    (0x10011618c) and `pthread_setschedparam(SCHED_RR, priority)` (0x1001161b0), i.e. fixed-priority round-robin threads.
    Ours runs the pump as an NSThread at `.userInitiated`, dropped to `.utility` when relaxed
    (`HLSSegmentProducer.swift:2523-2548`), and the software host on `.userInitiated` queues (`SoftwarePlaybackHost.swift:109-226`),
    so a Discover scroll or image decode competes with the demux. Targets: a disc that failed to open twice is not opened a
    third time without a message; dropped frames while scrolling Discover during playback = 0 on DevTV.

## 1. How playback starts

| Step | Infuse (evidence) | OpenStream (file:line) |
|---|---|---|
| Open | `-[FCFFMPEGDemuxingStream open]` 0x10007f008: input stream `open`, `length`, probesize 10 MB then 50 MB; `performOperationWithByteLimit:` (0x100080440) caps bytes read during open (`setHasReadLimit:`); FFmpeg `scan_all_pmts` option (0x1ffc3e6) | `Demuxer.swift:84-98` one probesize (50 MiB) and `avformat_open_input` without an interrupt callback; `AetherEngine+Loading.swift:1047,1700,1774` detach the open off the main actor |
| Deadline | 60,000 ms per FFmpeg operation (0x100080c70) via `fcFFMPEGInterruptionCheck` (0x100158b3c) | AVIO request timeout 35 s; read deadline only around seeks (`Demuxer.swift:1537-1551`); 15 s first-byte waits on the persistent reader (`AVIOReader.swift:954,1042,1054,1062`) |
| Streams | `readFormat`, `setupSubtitlesConverter`, then a check that audio or video descriptors exist, else `dispose` and the 50 MB retry (0x100080a68) | `HLSVideoEngine` builds the loopback HLS session; `StartupReadinessGate.swift:60-66` gives a DV master 2 attempts and 8 × 3 s data waits |
| First frame | `firstFrameIsRendered` / `firstFrameProduced` on the renderer; `FCVVCStartupDurationMeter` with the 3.0 s flag | `applyEnginePhase(.playing)` traces "first frame" (`ApplePlaybackCoordinator.swift:1061`) |
| Seek on open | `FCSeekPacketSkipper checkFarDesyncForPacket:atTime:` (0x1000de35c) treats video more than 180.0 s from the seek point as a far desync (`0x4066800000000000` at 0x1000de370) and re-seeks | Resume seeks while paused (`AetherPlaybackEngine.swift:339-342`); the 8 s scrub-landing watchdog makes resume show a 9 s spinner (`specs/speed-round2-report-2026-10-16.md:66`) |

Our own numbers from the traces (Play press to "first frame"): live 1.4 s, 1.5 s, 2.9 s, 3.0 s (`owner-iphone-1017.log:874-920,
1741-1784, 439-510, 633-701`); on-demand MKV 2.8 s (`:1176-1245`); UHD ISO 17.1 s (`officeplus-1017b.log:658-749`). Presses with
no first frame: MLB re-pressed after 2.5 s, MAGNOLIA after 11.2 s, COMEDY CENTRAL after 34.6 s (`:2230-2251, 2285-2308,
934-973`), one that fell through to the second stream after 21 s (`:2641-2681`).

## 2. Buffering and network stalls

- **Infuse.** Two buffering grades (§ fix 3). `-[FCVideoPlayer videoNeedsBufferization:]` (0x1001a4e80) and
  `decodingStreamDidBuffer:` drive it from the renderer side; `-[FCMediaPlayer playingHandlerNeedsBufferization:]`
  (0x1000bf970) from the clock side ("[Playback] Playing handler requested bufferization"). "[Playback] All data is rendered,
  but demuxer has an error" (0x2004d35) ends the item only after the buffer drains. `videoPlayerIsFarBehindAudio:` → "Will
  pause and synchronize" (0x2004fc4). The stats HUD exposes buffer status, reload count, stream speed and network throughput
  (`L:249-254`); `InputStreamSpeedStatistics(readingSpeed:usageSpeed:)` (0x10077cdb4) with `FCInputStreamSpeedMeter` feeds
  the "You may experience slow or choppy playback" warning (`L:860`) before playback, and `isExtremelySlowBluray`
  (0x1008589c0) is a protocol-plus-Blu-ray-folder rule.
- **Ours.** The engine reports `.rebuffering` for a healthy-connection underrun and `.stalled(reconnecting:)` for a source
  problem (`PlayerState.swift:158-223`); the app maps both to `.waiting` (`ApplePlaybackCoordinator.swift:1083-1091`), shows
  the spinner only on the surface route or for live (`AppleTransportOverlayModel.swift:335-347`), and on the AVKit route lets
  the system spinner stand. Live has an 8 s stall timeout, 3 reconnects at 1/2/4 s inside a 15 s window
  (`AppleLiveReconnectPolicy.swift:50-54`, `ApplePlaybackCoordinator.swift:1399-1421`); on-demand has no stall limit at all
  beyond the engine's 20 s connection stall and 12 reconnects (`AVIOReader.swift:518-532`). AVPlayer keeps
  `automaticallyWaitsToMinimizeStalling` (`NativeAVPlayerHost.swift:290`) with a 4 s forward buffer (`:466`); the engine's
  stall re-engage grace is 6 s (`AetherEngine.swift:1811`). Nothing measures throughput against bitrate before Play.

## 3. SMB and NFS reads, caching

- **Infuse SMB.** `FCSLSMBConnection connectToShare` (0x10007adc8) builds a config dictionary for
  `initWithHostName:username:password:delegate:configDictionary:` (GUEST fallback, `connectionModeForProtocolVersion:`), then
  logs the negotiated dialect and max read size (0x1ffb3c2). The library (`StratospherixLibSMB`) exposes
  `CCSMBConnectionTimeout`, `CCSMBKeepAlivePeriodSecs`, `CCEnableSMBPipelining`, `CCSMBProtocolMode` (smb-strings 0x207f65,
  0x207fa9, 0x207f4f, 0x2077ea), SMB2 credits and `maxOutstandingPackets` (0x22a2d5, 0x229f64), a dedicated network thread
  (`networkThreadFunction:`) and Echo keep-alives. The input stream is one open handle with positioned async reads (§ fix 2),
  wrapped by `FCRetryingInputStream` (§ fix 6) and the Swift `ReadAheadInputStream`/`ReadAheadLoader` on the
  `com.firecore.read_ahead` queue (0x20853d0). The loader waits with a timeout read from its own field ("[ReadAhead] Timeout
  when waiting for …", 0x100d010ac), refuses to preload without free memory (0x100d015f4), and preloads end-then-start
  (0x100cff80c). Exact preload sizes and timeouts were not recovered (Swift, symbols stripped).
- **Infuse NFS.** libnfs with `readahead`, `pagecache`, `dircache`, `autoreconnect` options compiled in (nfs-strings
  0x287cf-0x28815, `rpc_set_readahead`, `rpc_set_pagecache`), reconnect with "all attempts failed" (0x2bced); `[NFS]` logs for
  mount, open, read and seek failures. Whether Infuse sets readahead/pagecache sizes was not recovered.
- **Ours.** No NFS. SMB only through the loopback bridge: AVIOReader open-ended `Range` GET → `AppleSMBRangeServer`
  (`Connection: close`, 4 MiB chunks, 30 s read timeout, ≤ 32 sessions, 10 s request timeout; `AppleSMBRangeServer.swift:43,
  59, 174, 236-251`) → `AppleSMBClient.read` (≤ 8 MiB, 2 attempts, invalidates the connection on error, ≤ 8 connections,
  `manager.timeout = 8`, 5-minute idle prune; `AppleNetworkShare.swift:496-518, 627-631, 683-686, 727`) → AMSMB2 open / lseek /
  read in `maxReadSize` pieces / close per call (`AMSMB2.swift:964-1012`, `FileHandle.swift:198-205`). The speed-round-2 fix
  made a second read wait for the opening connection instead of failing (`:624-628`). No read-ahead beyond AVIOReader's own
  16 MiB window (`AVIOReader.swift:492`), no disc cache across launches, no negotiated-dialect or read-size line in the trace.

## 4. ISO, BDMV and VIDEO_TS

Round 3 §3 has the pipeline (`FCUDFImage`, `FCBlurayFSHandler`, `bd_get_titles(TITLES_RELEVANT)`, `bd_get_main_title`,
gap handler). New here:

- `FCDVDVideoSet videoSetsForDVDItem:streamBuilder:` (0x1ff0d44) parses `VIDEO_TS.IFO` / `VTS_xx_0.IFO` with its own
  `FCIFOFileParser` (PGC tables, cell playback tables, `VTS_VOBU_ADMAP`) and `determineStartOffsetAndMainPGC`; title sets are
  filtered and the filter is dropped if it empties the list ("[DVD] No title sets after filtering, will use unfiltered",
  0x1ff45d5); failure is one message ("Failed to parse a DVD folder", 0x207e2b0).
- Both disc demuxers refuse a bad IO object up front ("Invalid IO for Bluray demuxing", 0x202e2a8) and the Blu-ray stream
  repairs clip-boundary timestamp jumps per stream (0x2033ed2).
- Robustness: a per-item crash counter in `FileFetchingCrashes.plist` (0x100005f04) and the Blu-ray crash guard (0x100ba0dd8).
- Ours: `DiscReader.swift:36-100` enumerates `BDMV/PLAYLIST`, reads every `.mpls`, picks a title and caches the recognition
  per process (`DiscRecognitionCache`); DVD titles come from `VIDEO_TS.IFO` (`:173-186`). The app forces Blu-ray to the main
  title (`AppleDiscPlayback.swift:30-45`). The engine rebase spec already asks for a per-file parse cache
  (`specs/engine-rebase-7.36-2026-10-15.md`, lead note); fix 1 adds the bulk read and the persistence.

## 5. Error recovery and retries

| Layer | Infuse | OpenStream |
|---|---|---|
| Read | 120 s retry window with reopen at position; HTTP pool "Will retry reading at …" until "exceeded retry deadline" | AVIOReader: 20 s stall → reconnect, ≤ 12 unproductive, 512 KiB counts as progress; 429/503/509 ladder (`AVIOReader.swift:505-532, 587-592`) |
| Open | probesize 10 MB → 50 MB; 60 s operation deadline | one open; `AppleEngineOpenRetryPolicy.swift:14-35` retries the same candidate once after 1 s, never for 4xx, timeouts or a truncated file |
| Decode | soft switch per chunk, hard switch at 3 failed chunks | route chosen at load; item death confirmed after 3 s |
| Live | not inspected (Mac build has no IPTV path of ours) | 10 s live deadline + one 15 s extension (`ApplePlaybackStartPolicy.swift:15-22`, coordinator `:1149-1187`); 3 reconnects in 15 s; one quiet reopen of an ended stream after 3 s (`:1123-1130`) |
| Item | per-item crash counters; "won't open it" | `ApplePlaybackFailureHistory` records a failed URL; fallback to other candidates (`:571` 3 for the engine, `:915-926`) |
| User | plain messages per cause (`L:299-313`: auth, host, connection, missing path, overloaded) | `ApplePlaybackFailureRecovery.swift` picks Retry / Sources / Close; `AppleTruncatedMediaProbe.swift` rewrites engine text |

## 6. Threading off the main thread

- **Infuse.** Player stages are `FCPlayerThread`s: fixed-priority (THREAD_EXTENDED_POLICY, timeshare off) with
  `SCHED_RR` and an explicit priority (0x1001160d8-0x1001161c0); the demux, decode, audio and render stages each log "Starting
  a thread". The SMB library has its own network thread; HTTP uses a curl connection pool; read-ahead runs on
  `com.firecore.read_ahead`. The main thread is watched by `FCMainThreadMonitor` at 1.0 s (fix 7). `FCFFMPEGDemuxingStream`
  inherits `UIViewController` metadata only as an ivar reference; nothing in the pipeline waits on the main queue except
  `initializeVideoRendererOnMainThread`.
- **Ours.** The engine is `@MainActor` at the API edge and detaches its heavy opens (`AetherEngine+Loading.swift:1047-1048,
  1700, 1774, 1965`), runs the pump on a 1 MiB-stack NSThread at `.userInitiated`/`.utility`
  (`HLSSegmentProducer.swift:2523-2548`), and uses 12 `.userInitiated`, 5 `.utility` and 1 `.userInteractive` queues. The
  synchronous `seekBounded` form was the cause of 4.4 s and 5.2 s "Fully Blocked" hangs on a WAN source
  (`Demuxer.swift:1606-1616`) and now has an off-actor form; the remaining field hangs (540-763 ms) are untraced because the
  watchdog is DEBUG+macOS only. The SMB bridge and client are actors, so one slow 4 MiB read serialises the next request to
  the same share.

## 7. Memory limits

- **Infuse.** `os_proc_available_memory` before preloading; free memory logged on demuxer teardown; `didReceiveMemoryWarning`
  handlers (FCAppDelegate 0x10029d9d8, the live preview generator 0x10003e368); user-facing Streaming Cache modes
  (`L:746-749`); chunked hardware decoding (`useChunksForHardwareVideo`, `FCChunkedPacketsBuffer`) and `minBufferedChunks`
  bound decode memory per chunk. Values were not recovered.
- **Ours.** No pressure hook in engine or app. Bounds: segment cache 10 forward / 20 back (≈ 300 MB at 4K HEVC per the
  engine's own comment, `SegmentCache.swift:103`), retention budget 2 GiB or ¼ of free disk, AVIO windows 16 MiB (VOD) /
  64 MiB (live) and a 64 MiB stream high water (`AVIOReader.swift:416, 492-493`), subtitle packet store caps
  (`SubtitlePacketStore.swift:52`). Measured in the owner traces: iPhone 530 MB rss / 436 MB footprint / 535 MB cache at
  t = 30 s of Matilda (`owner-iphone-1015.log:4490`); OfficePlus 319-363 MB over 210 s with `discFetchedMB` growing
  799 → 3103 (`officeplus-1017b.log:781-889`), i.e. the UHD ISO is read at ≈ 10.6 MB/s steady.

## 8. What it shows while it waits

- **Infuse.** A delayed activity indicator (`showActivityIndicatorDelayedIn:` on NSObject, 0x10028fb50; the delay is the
  caller's, Swift callers not resolved), `showSpinner:animated:` with 6 call sites, a HUD timer, and short bufferings that
  draw nothing (fix 3). The optional stats HUD (Full / Compact / Off, `L:235-238`) is the only text. Before playback, the
  speed check can warn about choppy playback (`L:860`), and the sign-in / share errors are plain sentences (`L:299-313`).
- **Ours.** Black with one centred spinner until the engine picks a route (`AppleMediaPlaybackView.swift:287-307`, the disc
  spinner for a disc), then AVKit's spinner or the surface overlay's (`ApplePlaybackSpinnerPolicy.swift:14-22`,
  `AppleTransportOverlayModel.swift:335-363`, text for VoiceOver only); "Reconnecting…" is the only waiting message and only
  for live (`ApplePlaybackCoordinator.swift:312,1089`); failure is an alert with Retry / Close
  (`AppleMediaPlaybackView.swift:584-590`). The engine's log into the trace is capped at 30 lines a second and 240 characters
  (`AppleEngineLogBridge.swift:17-21`), and the trace keeps 400 entries (`AppleInteractionTrace.swift:40`): the Matilda session
  dropped 159, 12 and 19 lines inside three seconds (`owner-iphone-1015.log:4901-4965`), exactly where the stall evidence is.

## Our instability, as the evidence shows it

- Disc: three Blu-ray opens on the phone with a 7-14 s silent parse and no first frame before the owner closed the player
  (`owner-iphone-1015.log:4699-4828`); one 17 s open on OfficePlus that then played.
- Mid-play: the Matilda chain at 273 s (fix 6).
- Live: re-presses after 11 s and 35 s without a frame; 2-8 rebuffer events per session.
- E2E: `testCrawlPlayers` "Skip test did not reach an interior position" (`Apps/OpenStreamiOSUITests/AppleiOSUITests.swift:3922`)
  and "playback did not settle with an advancing clock before Play/Pause within 10 s" (`:3967`); `testCrawlLive` AirPlay; all
  listed as the known 39/2 in `specs/ios18-e2e-report-2026-10-16.md` and `specs/flaky-e2e-2026-10-15.md`. Suite flakes under
  load: a local playback server test "where the connection dropped" and a 60 s Mac captions timeout
  (`specs/tv-disc-shelf-report-2026-10-15.md:33-39`), `AppleLiveZappingTests` 2 s deadline (`specs/iphone-ios18-report-2026-10-16.md:55`).
- Resume: a 9 s spinner from the engine's 8 s scrub-landing watchdog (`specs/speed-round2-report-2026-10-16.md:66`).
- Hangs: 540-763 ms main-thread hangs after the full-screen trailer and on Settings › Sources, untraced.

## Not found

- ReadAheadLoader preload sizes, trigger fraction and wait timeout values; HTTP pool size and retry deadline value;
  the short-buffering wait and SMB semaphore timeouts (loaded through globals the annotator did not follow);
  `showActivityIndicatorDelayedIn:` delays (Swift callers); whether Infuse sets libnfs readahead/pagecache; its live/IPTV
  path (not in the Mac build in a form comparable to ours).

## Method and evidence

- Infuse: `strings -t x` of the binary and frameworks (`/tmp/r3/*-strings.txt` on Dev-Mini); `otool -oV` parsed with a
  resolver for relative method lists (`/tmp/r3/resolve_objc.py` → `classes.json`, 3,501 classes / 32,441 methods);
  a string- and selector-xref scanner over `__text` (adrp + add/ldr, with `__cfstring` objects and `__objc_selrefs`;
  `/tmp/r3/xref2.py`); an annotated `llvm-objdump` reader that resolves `__objc_stubs` to `objc_msgSend$selector`
  (`/tmp/r3/fn.py`, `stubsel.py`: 18,331 stubs); callers of a selector by scanning `bl` targets. No Ghidra on the 81 MB
  binary (600 s limit, and the mini was under another job's load), no build lock taken, nothing launched.
- OpenStream: read-only `grep`/`sed` of `Sources/OpenStreamApple`, the pinned engine checkout
  (`/Volumes/DevExt/dev/openstream-build/spm/checkouts/AetherEngine`, HEAD 07afad62) and AMSMB2 4.0.3; the owner traces in
  `/Volumes/DevExt/dev/openstream-build/traces/` (`owner-iphone-1015.log`, `owner-iphone-1017.log`, `owner-iphone-1105.log`,
  `officeplus-1017b.log`); job reports under `specs/`.
- Code anti-slop: no code written, nothing to run it on. This file is the only one written in the tree.
