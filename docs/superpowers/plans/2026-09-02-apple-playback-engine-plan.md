# Apple Playback Engine Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. In this project the "subagent" for lane tasks is a GLM-5.2 worker launched by `run-lane.sh` (see "Who does what"); each `### Task N` section below is sliced verbatim into that worker's spec.

**Goal:** Every stream OpenStream Apple is handed (Xtream/M3U live TS, HLS, MP4, MKV from add-ons, SMB files) plays on iPhone, iPad, Apple TV, Mac and Vision Pro without a gateway, with Dolby Vision, HDR10/HLG, Dolby Digital/Digital Plus (Atmos) and TrueHD/DTS handled on device the way Infuse does it.

**Architecture:** One engine, AetherEngine (LGPL-3.0 + App Store exception, FFmpeg built without GPL), behind an `ApplePlaybackEngine` protocol. The engine demuxes in-app and chooses a route per stream: `remoteBypass`/`loopback` (AVPlayer plays the origin or a local fMP4-HLS remux, so AirPlay, PiP, Apple's HDR/Dolby Vision pipeline and EAC3-JOC Atmos passthrough are all preserved) or `software` (libavcodec → `AVSampleBufferDisplayLayer` for MPEG-2, interlaced H.264, VP9, VC-1). The existing AVPlayer path survives only as `NativePlaybackEngine`, an automatic fallback. Sources stop inspecting assets and simply build an `ApplePlaybackRequest`.

**Tech Stack:** Swift 6.2 / SwiftPM package `OpenStreamApple` (iOS 18, tvOS 18, macOS 15, visionOS 2), SwiftUI + AVKit, Swift Testing, AetherEngine 6.66.0 (SwiftPM, dynamic xcframeworks), AMSMB2 4.0.3, ffmpeg + dovi_tool + mkvmerge for fixtures.

**Spec:** `docs/superpowers/specs/2026-09-02-apple-playback-engine-design.md` (approved 2026-09-02). Amendments made by this plan: engine pinned to 6.66.0 (README-documented API), Dolby Vision/Atmos/TrueHD/DTS are phase-1 acceptance items (owner requirement 2026-09-02 evening), Liquid Glass is switched off app-wide.

## Global Constraints

- Swift 6 language mode, strict concurrency; package floors iOS 18 / tvOS 18 / macOS 15 / visionOS 2 stay as they are.
- Licensing: LGPL only, embedded as dynamic frameworks, with a notices screen. No GPL code, no private API, nothing that can trip App Store review. Only one new dependency (AetherEngine); AMSMB2 stays; nothing else may be added.
- Copy rules: nothing blue except the brand mark; every failure message names a reason; the strings "No compatible stream." and "Configure the Transcode Gateway" must not survive.
- Files stay in the flat `Sources/OpenStreamApple/Apple*.swift` layout; tests in `Tests/OpenStreamAppleTests/*Tests.swift` using Swift Testing (`@Test`, `#expect`, `#require`), `@MainActor` on tests that touch main-actor types.
- Never weaken or delete an existing test; rewrite an assertion only when the policy table in the task says the behaviour changes.
- Known baseline failure to leave alone: `smbEndpointInputRejectsInvalidValuesAndPreservesBonjourServiceInstances` in `AppleIPTVAndLibraryTests.swift` (149/150 pass at baseline). Do not fix it, do not delete it.
- Build commands (always with the local scratch path; the checkout lives on an SMB share):
  - `swift build --scratch-path "$HOME/Library/Caches/openstream-lane/.build"`
  - `swift test --scratch-path "$HOME/Library/Caches/openstream-lane/.build"`
  - `xcodebuild -project Apps/OpenStreamApps.xcodeproj -scheme "OpenStream iOS" -destination 'generic/platform=iOS Simulator' -derivedDataPath "$HOME/Library/Caches/openstream-lane/DerivedData" -quiet build`
- Workers do not commit, do not touch git beyond status/diff/log, do not bump versions, do not edit CI or deploy config, do not edit `FEEDBACK.md`.

---

## Who does what, the budget, and the loop

| Role | Who | Cost | Used for |
| --- | --- | --- | --- |
| Orchestrator, decisions, spec fixes, patch review, merge back | Fable (this session) | subscription | reads reports and diff-stats only; never reads the tree wholesale |
| Implementation of lane tasks T0–T7 | GLM-5.2 via `or-review implement` (local mode on the Mac Studio, key in `~/.config/openrouter/key`) | ≈$1 per task; $5.25 credits left on 2026-09-02 evening, key cap $9.86/month | one task at a time, in the lane, with the Swift gates allowed as extra Bash tools |
| Hard task rerun when GLM fails twice | Kimi K2.7 (`-m moonshotai/kimi-k2.7-code`, ≈$6) or the `implementer` project agent (Sonnet, subscription) | metered / subscription | T4 is the likely candidate |
| Audit of each landed task | `or-review review` on the lane, model `poolside/laguna-s-2.1:free` | $0, rate-limited (sequential, ~7 min) | findings go to Fable, fixes go back to the next spec |
| Deterministic testing | `run-lane.sh gates` (swift build, swift test, xcodebuild iOS simulator) and the fixture matrix (`PLAYBACK_ENGINE_TESTS=1 swift test`) | $0 | after every task; the lane is committed only when green |
| UI/UX items (glass off, forms, detail page, discover polish) | Codex, in the main tree from `native/apple/FEEDBACK.md` | owner's other subscription | Task 8 below is written for Codex |
| Design research | Antigravity | owner's other subscription | `native/apple/RESEARCH-AND-RECOMMENDATIONS-2026-09-02.md` |
| Hardware validation (Dolby Vision, Atmos, AirPlay, tvOS remote) | Owner with the Task 9 checklist | none | the only step no agent can do |

**Lane:** `/Volumes/Files/Projects/Code, Apps & Websites/Apps/OpenStream-lanes/apple-engine` is a git snapshot of `native/apple` (baseline = main HEAD `f594952` plus Codex's uncommitted work as of 2026-09-02 19:54, commit `3a5c3ab`, plus two test-isolation fixes). Workers edit only the lane; the main tree stays Codex's. Merge-back is the last section of this plan.

**Loop:** `Results/OpenRouter-Reviews/OpenStream/run-lane.sh T0 T1 …` runs each spec through the worker, runs the gates, commits the lane on green, and appends one line per event to `STATUS.md`. A `Monitor` in the Fable session tails `STATUS.md` (TASK START / IMPLEMENT END / GATES PASS / GATES FAIL / STOPPED / ALL DONE); a cron heartbeat every 35 minutes checks the driver is alive; the `RESUME-BOARD.md` entry lets the desktop `resume-after-reset-b` routine carry the queue if the Fable session hits its usage wall.

**Order:** T0 → T1 → T2 → T3 → T4 → T5 → T6 → T7 (each is gate-green on its own), Task 8 in parallel by Codex, Task 9 after merge-back.

---

## File structure

New (all in `Sources/OpenStreamApple/` unless noted):

| File | Responsibility |
| --- | --- |
| `ApplePlaybackRequest.swift` | The one value every source produces: URL, headers, live flags, resume, identity, hints |
| `ApplePlaybackEngine.swift` | Protocol + phase/route/track/event types shared by engines, coordinator, views |
| `AetherPlaybackEngine.swift` | Engine adapter over `AetherEngine` |
| `NativePlaybackEngine.swift` | AVPlayer fallback adapter |
| `ApplePlaybackEngineFactory.swift` | Picks the engine from the setting, falls back, reports the fallback once |
| `ApplePlayerHost.swift` | Vends AVKit controller/view for `.avPlayer` routes or the engine surface for `.surface` |
| `AppleTransportOverlay.swift` | Controls for the surface route (play/pause, scrub, tracks, live badge, Done) |
| `AppleThirdPartyNotices.swift` + `Resources/ThirdPartyNotices/*` | Notice model + bundled license texts |
| `AppleThirdPartyNoticesView.swift` | Settings → About → Third-Party Notices |
| `scripts/apple-license-check.sh` | Fails when the pinned engine's FFmpeg reports GPL |
| `Tests/Fixtures/make-fixtures.sh`, `Tests/Fixtures/serve.py`, `Tests/Fixtures/README.md` | Media matrix generator + loopback fixture server |
| `Tests/OpenStreamAppleTests/Support/FakePlaybackEngine.swift` | Scripted engine for coordinator/view tests |

Changed: `Package.swift`, `Apps/OpenStreamApps.xcodeproj/project.pbxproj`, `Apps/Shared/Info.plist`, `ApplePlaybackCoordinator.swift`, `ApplePlaybackPreparer.swift`, `ApplePlaybackRoute.swift`, `AppleStremioPlaybackResolver.swift`, `AppleStremioPlaybackClient.swift`, `AppleStremioPlaybackView.swift`, `ApplePlayerControllers.swift` (shrinks or goes), `ApplePlayerSession.swift`, `AppleIPTV.swift`, `AppleMediaSourceViews.swift`, `AppleDiscoverView.swift`, `AppleLibrary.swift`, `AppleSettingsStore.swift`, `AppleSettingsViews.swift`, `ApplePlaybackInfoView.swift`, `AppleTranscodeGateway.swift` (copy only).

---

### Task 0: Fixture generator and loopback fixture server

**Files:**
- Create: `Tests/Fixtures/make-fixtures.sh`, `Tests/Fixtures/serve.py`, `Tests/Fixtures/README.md`, `Tests/Fixtures/.gitignore` (contents: `out/` and `private/`)

**Interfaces:**
- Produces: media under `Tests/Fixtures/out/` and an HTTP server on `127.0.0.1:8765` that Task 3's fixture tests use. Route contract below is relied on verbatim by Task 3.

**Policy / behaviour table**

| Request | Today | Required |
| --- | --- | --- |
| `GET /media/<name>` | n/a | static file from `out/`, supports `Range` (206 with `Content-Range`), `Content-Type` by extension (`.ts` → `video/mp2t`, `.mkv` → `video/x-matroska`, `.mp4` → `video/mp4`, `.m3u8` → `application/vnd.apple.mpegurl`) |
| `GET /live/<name>.ts` | n/a | loops the file forever, chunked transfer, no `Content-Length`, paced at about 1.5 MB/s, only `.ts` names |
| `GET /slow/<name>` | n/a | sleeps 12 s, then behaves like `/media/<name>` |
| `GET /protected/<name>` | n/a | 403 with body `referer required` unless header `Referer` begins with `https://fixtures.local/`; then like `/media/<name>` |
| `GET /hls/<path>` | n/a | static from `out/hls/` |
| anything else | n/a | 404 |
| `python3 serve.py --port N` | n/a | binds `127.0.0.1` only, prints `fixtures listening on 127.0.0.1:N` and flushes stdout |

**Implementation requirements**

1. `make-fixtures.sh` (bash, `set -euo pipefail`, runs from any cwd, writes into `Tests/Fixtures/out/`, idempotent, skips a file that already exists unless `--force`). Each artifact is 10–20 s of `testsrc2` video with a 440 Hz sine audio bed. Generate:
   - `mp4-h264-aac.mp4` (`h264_videotoolbox`, AAC stereo, `-movflags +faststart`)
   - `ts-h264-aac.ts` (same codecs, `-f mpegts`)
   - `ts-h264-interlaced-ac3.ts` (`libx264 -flags +ilme+ildct -x264-params interlaced=1`, AC-3 5.1; if `libx264` is missing in this ffmpeg, write `SKIPPED libx264` to `out/SKIPPED.txt` and continue)
   - `ts-mpeg2-interlaced-mp2.ts` (`mpeg2video -flags +ilme+ildct -top 1 -b:v 6M`, MP2 audio)
   - `mkv-h264-aac.mkv`, `mkv-hevc-eac3.mkv` (`hevc_videotoolbox`, EAC3 5.1 via `-af "pan=5.1|FL=c0|FR=c0|FC=c0|LFE=c0|BL=c0|BR=c0"`), `mkv-hevc-truehd.mkv` (`-c:a truehd -strict -2`), `mkv-hevc-dts.mkv` (`-c:a dca -strict -2`), `mkv-vp9-opus.mkv` (`libvpx-vp9` + `libopus`; record in `SKIPPED.txt` if unavailable)
   - `hls/index.m3u8` + `hls/seg%03d.ts` (`-c copy -f hls -hls_time 4 -hls_playlist_type vod` from the MP4)
   - `hdr10-hevc.mp4` (`hevc_videotoolbox -profile:v main10 -pix_fmt p010le -color_primaries bt2020 -color_trc smpte2084 -colorspace bt2020nc -color_range tv -tag:v hvc1`)
   - `dv81-hevc-eac3.mkv` and `dv81-hevc-eac3.mp4`: extract Annex B HEVC from `hdr10-hevc.mp4` (`-c:v copy -bsf:v hevc_mp4toannexb -f hevc`), write `out/tmp/dv81.json` = `{"cm_version":"V29","profile":"8.1","length":<frame count from ffprobe>,"level6":{"max_display_mastering_luminance":1000,"min_display_mastering_luminance":1,"max_content_light_level":1000,"max_frame_average_light_level":400}}`, run `dovi_tool generate -j out/tmp/dv81.json -o out/tmp/rpu.bin`, `dovi_tool inject-rpu -i out/tmp/base.hevc --rpu-in out/tmp/rpu.bin -o out/tmp/dv81.hevc`, then `mkvmerge -o out/dv81-hevc-eac3.mkv out/tmp/dv81.hevc out/tmp/eac3-51.ec3` and `ffmpeg -i out/tmp/dv81.hevc -i out/tmp/eac3-51.ec3 -c copy -tag:v hvc1 out/dv81-hevc-eac3.mp4`. Check `dovi_tool generate --help` / `dovi_tool info -i out/tmp/dv81.hevc -f 0` and adapt the JSON keys if the installed version differs; the requirement is a profile 8.1 RPU on every frame.
   - Real samples live in `Tests/Fixtures/private/` (gitignored; see its README: DV 8.1 + Atmos, DV 8.1, H.264 + Atmos, HDR10, trimmed from the Unraid Media share); the script prints which are present. Merge-back must copy `private/` by hand (it is not in git).
2. At the end print a table: file, container, video codec, audio codec, Dolby Vision profile (from `ffprobe -v error -show_entries stream=codec_name,profile:stream_side_data_list -of json`), size.
3. `serve.py`: `http.server.ThreadingHTTPServer`, routes per the table, `--port` (default 8765), `--root` (default `Tests/Fixtures/out`). Loop pacing for `/live/`: write 64 KiB chunks and sleep to hold ~1.5 MB/s; stop cleanly on client disconnect (`BrokenPipeError`, `ConnectionResetError`).
4. `README.md`: the matrix (file → expected engine route → what it proves), how to run the server, how the tests find it (`PLAYBACK_ENGINE_TESTS=1`, `FIXTURE_BASE_URL` default `http://127.0.0.1:8765`).

**Tests**
- `bash Tests/Fixtures/make-fixtures.sh` produces every non-skipped file; `ffprobe` on `dv81-hevc-eac3.mp4` shows `DOVI configuration record` with `dv_profile=8`, `dv_bl_signal_compatibility_id=1`.
- `python3 Tests/Fixtures/serve.py & curl -sI http://127.0.0.1:8765/media/mp4-h264-aac.mp4` → `HTTP/1.0 200`, `Accept-Ranges: bytes`; `curl -s -o /dev/null -w '%{http_code}' -H 'Range: bytes=0-99' …` → `206`; `/protected/...` without Referer → `403`, with `-H 'Referer: https://fixtures.local/x'` → `200`; `/live/ts-h264-aac.ts` streams for 5 s with `curl --max-time 5` and returns more than 3 MB.

**Out of scope:** Swift code; Dolby Vision profile 5 synthesis (needs a Dolby encoder; owner sample only); anything under `Sources/`.

**Verify:** the two test bullets above, then `swift build --scratch-path "$HOME/Library/Caches/openstream-lane/.build"` still succeeds (nothing in Sources changed).

---

### Task 1: Engine dependency, embed check, license guard, notice resources

**Files:**
- Modify: `Package.swift`, `Apps/OpenStreamApps.xcodeproj/project.pbxproj` (only if the embed check below fails)
- Create: `scripts/apple-license-check.sh`, `Sources/OpenStreamApple/AppleThirdPartyNotices.swift`, `Sources/OpenStreamApple/Resources/ThirdPartyNotices/<component>.txt`, `Tests/OpenStreamAppleTests/AppleThirdPartyNoticesTests.swift`

**Interfaces:**
- Produces: `public struct AppleThirdPartyNotice: Identifiable, Sendable { public let id: String; public let name: String; public let license: String; public let url: String; public let text: String }` and `public enum AppleThirdPartyNotices { public static func all() -> [AppleThirdPartyNotice]; public static let sourceOffer: String }` (Task 7's screen renders these).

**Policy / behaviour table**

| Item | Today | Required |
| --- | --- | --- |
| Engine dependency | none | `.package(url: "https://github.com/superuser404notfound/AetherEngine", exact: "6.66.0")`, product `AetherEngine` on target `OpenStreamApple` for all platforms; if 6.66.0 does not resolve use `exact: "6.65.0"` and say so in the report |
| `AetherEngineSMB` product | n/a | not linked (SMB 2.x only; AMSMB2 stays) |
| Top Shelf extension | does not link the package | unchanged |
| GPL guard | none | `scripts/apple-license-check.sh` exits 1 if any FFmpeg binary in the resolved engine artifacts reports `--enable-gpl`, `--enable-nonfree`, `libx264`, `libx265`, `libxvid`, `libfdk`; exits 1 if no FFmpeg binary was inspected; exits 1 if the engine `LICENSE` lacks the words "App Store" or "application store" |
| Notices | none | one text file per component copied from the checkouts: AetherEngine (LICENSE), FFmpeg (its LGPL text), dav1d, libdovi, zimg, libzvbi (whatever exists in the checkout), AMSMB2 and libsmb2; missing ones listed in the report, not invented |
| `AppleThirdPartyNotices.all()` | n/a | one entry per bundled file, sorted by name, `text` non-empty, `license` short name (`LGPL-3.0 + App Store exception`, `LGPL-2.1-or-later`, `BSD-2-Clause`, `MIT`, `LGPL-2.1`) |
| `sourceOffer` | n/a | "OpenStream embeds these components as replaceable dynamic frameworks. The corresponding source and build instructions are available at the URLs listed above." |

**Implementation requirements**

1. Edit `Package.swift`; run `swift package resolve --scratch-path "$HOME/Library/Caches/openstream-lane/.build"`; read `$HOME/Library/Caches/openstream-lane/.build/checkouts/AetherEngine/README.md` and `docs/api.md` (they are the API reference for Tasks 3–5; note in the report the exact `LoadOptions` initializer, `videoRoute` cases, `PlaybackErrorInfo` fields and the SwiftUI surface type you found).
2. Add `resources: [.copy("Resources/ThirdPartyNotices")]` to the `OpenStreamApple` target and implement `AppleThirdPartyNotices` reading `Bundle.module`.
3. Write `scripts/apple-license-check.sh`: locate binaries under `${OPENSTREAM_SCRATCH:-$HOME/Library/Caches/openstream-lane/.build}/artifacts` and `.build/checkouts/AetherEngine` matching `*.xcframework/*/*.framework/*` executables, run `strings` on each, grep the FFmpeg `configuration:` line, apply the table. Print each binary and its verdict.
4. Embed check: build the iOS target with the xcodebuild command from Global Constraints and list `$HOME/Library/Caches/openstream-lane/DerivedData/Build/Products/Debug-iphonesimulator/OpenStream.app/Frameworks`. If the engine's frameworks are absent, add them to the same embed phase that carries AMSMB2 in `project.pbxproj` for the iOS, tvOS, macOS and visionOS targets (mirror the existing entries exactly), rebuild, and list again. Report the framework names found.

**Tests** (`AppleThirdPartyNoticesTests.swift`): `all()` has at least 5 entries; every `text.count > 200`; names include "AetherEngine" and "FFmpeg"; entries are sorted by name.

**Out of scope:** any playback code; the notices screen (Task 7); changing AMSMB2.

**Verify:** `swift build …`, `swift test …` (149/150 + new tests, only the known Bonjour failure), `bash scripts/apple-license-check.sh` prints PASS, xcodebuild iOS succeeds and the Frameworks listing shows the engine frameworks.

---

### Task 2: Playback request and engine protocol

**Files:**
- Create: `Sources/OpenStreamApple/ApplePlaybackRequest.swift`, `Sources/OpenStreamApple/ApplePlaybackEngine.swift`, `Tests/OpenStreamAppleTests/Support/FakePlaybackEngine.swift`, `Tests/OpenStreamAppleTests/ApplePlaybackRequestTests.swift`
- Modify: `Sources/OpenStreamApple/ApplePlaybackCoordinator.swift` (only `ApplePlaybackFailure.Kind`)

**Interfaces (Produces, used verbatim by Tasks 3–7):**

```swift
public struct ApplePlaybackRequest: Equatable, Sendable {
    public enum SourceKind: String, Sendable, CaseIterable { case stremio, liveTV, files, networkShare }
    public struct Hints: Equatable, Sendable {
        public var notWebReady: Bool
        public var proxyHeaders: [String: String]   // Stremio behaviorHints.proxyHeaders.request
        public var filename: String?
        public init(notWebReady: Bool = false, proxyHeaders: [String: String] = [:], filename: String? = nil)
    }
    public var url: URL
    public var headers: [String: String]
    public var isLive: Bool
    public var dvrWindowSeconds: Double?
    public var resumePosition: Double?
    public var mediaID: String
    public var title: String?
    public var sourceKind: SourceKind
    public var hints: Hints
    public init(url: URL, headers: [String: String] = [:], isLive: Bool = false, dvrWindowSeconds: Double? = nil,
                resumePosition: Double? = nil, mediaID: String, title: String? = nil, sourceKind: SourceKind, hints: Hints = Hints())
    public var effectiveHeaders: [String: String]   // headers merged with hints.proxyHeaders; proxy value wins on a key collision
    public var effectiveDVRWindowSeconds: Double?   // isLive ? (dvrWindowSeconds ?? 1800) : nil
}

public enum ApplePlaybackEnginePhase: Equatable, Sendable {
    case idle, loading, playing, paused, seeking, rebuffering
    case stalled(reconnecting: Bool)
    case ended
    case error(String)
}
public enum ApplePlaybackPresentationRoute: String, Equatable, Sendable { case none, avPlayer, surface, audioOnly }
public struct ApplePlaybackTrack: Identifiable, Equatable, Sendable {
    public let id: Int; public let title: String; public let language: String?; public let codec: String?; public let isDefault: Bool
    public init(id: Int, title: String, language: String? = nil, codec: String? = nil, isDefault: Bool = false)
}
public enum ApplePlaybackEngineEvent: Equatable, Sendable {
    case phase(ApplePlaybackEnginePhase), route(ApplePlaybackPresentationRoute), position(Double), duration(Double?)
    case tracks, failure(ApplePlaybackFailure?)
}
@MainActor public protocol ApplePlaybackEngine: AnyObject {
    var kind: ApplePlaybackEngineKind { get }
    var phase: ApplePlaybackEnginePhase { get }
    var route: ApplePlaybackPresentationRoute { get }
    var position: Double { get }
    var duration: Double? { get }
    var audioTracks: [ApplePlaybackTrack] { get }
    var subtitleTracks: [ApplePlaybackTrack] { get }
    var failure: ApplePlaybackFailure? { get }
    var avPlayer: AVPlayer? { get }            // non-nil only on .avPlayer routes
    var events: AsyncStream<ApplePlaybackEngineEvent> { get }   // a fresh stream per call; every property change is emitted
    func load(_ request: ApplePlaybackRequest) async throws
    func play(); func pause(); func stop()
    func seek(to seconds: Double) async
    func selectAudioTrack(id: Int); func selectSubtitleTrack(id: Int?)
}
public enum ApplePlaybackEngineKind: String, CaseIterable, Sendable { case openStream = "engine", native = "native" }
```

`ApplePlaybackFailure.Kind` gains (add only the ones missing): `authentication`, `unsupportedMedia`, `network`, `timedOut`, `sourceEnded`, `engineUnavailable`, `player`.

**Policy / behaviour table**

| Input | Today | Required |
| --- | --- | --- |
| `effectiveHeaders` with `headers["User-Agent"]="A"` and `proxyHeaders["User-Agent"]="B"` | n/a | `"B"` |
| `effectiveDVRWindowSeconds` for `isLive: true, dvrWindowSeconds: nil` | n/a | `1800` |
| same for `isLive: false` | n/a | `nil` even if `dvrWindowSeconds` is set |
| `FakePlaybackEngine.script([.loading, .playing])` then `load` | n/a | `events` yields `.phase(.loading)`, `.phase(.playing)` in order; `phase == .playing` after |
| `FakePlaybackEngine.failOnLoad = ApplePlaybackFailure(kind: .unsupportedMedia, …)` | n/a | `load` throws that failure and `failure` is set |

**Implementation requirements**

1. Types exactly as above, in the two new files. `ApplePlaybackRequest` is a plain value; no `AVFoundation` import in that file.
2. `FakePlaybackEngine` (test target, `@MainActor final class`): `var scriptedPhases: [ApplePlaybackEnginePhase]`, `var scriptedRoute: ApplePlaybackPresentationRoute = .avPlayer`, `var failOnLoad: ApplePlaybackFailure?`, `var loadedRequests: [ApplePlaybackRequest]`, `var seeks: [Double]`, `var selectedAudio: [Int]`, `var selectedSubtitle: [Int?]`, `var stopCount: Int`; `events` implemented with a continuation list so several consumers can subscribe; `emit(_:)` helper for tests.
3. Keep `ApplePlaybackFailure.classify` behaviour for existing inputs (existing tests must still pass).

**Tests** (`ApplePlaybackRequestTests.swift`): the five policy rows, plus `ApplePlaybackRequest` equality and `Hints` defaults.

**Out of scope:** any engine or coordinator changes beyond the `Kind` cases; UI.

**Verify:** `swift build …`, `swift test …` (only the known Bonjour failure).

---

### Task 3: AetherPlaybackEngine, NativePlaybackEngine, factory, fixture tests

**Files:**
- Create: `Sources/OpenStreamApple/AetherPlaybackEngine.swift`, `Sources/OpenStreamApple/NativePlaybackEngine.swift`, `Sources/OpenStreamApple/ApplePlaybackEngineFactory.swift`, `Tests/OpenStreamAppleTests/ApplePlaybackEngineFixtureTests.swift`, `Tests/OpenStreamAppleTests/ApplePlaybackEngineFactoryTests.swift`
- Read first (and ONLY these; the engine checkout is large and reading it wholesale kills the session): `Sources/OpenStreamApple/ApplePlaybackEngine.swift` and `ApplePlaybackRequest.swift` (Task 2), `Sources/OpenStreamApple/ApplePlayerSession.swift`; in `$HOME/Library/Caches/openstream-lane/.build/checkouts/AetherEngine/`: `docs/api.md` (use `grep -n` to find `LoadOptions`, `videoRoute`, `playbackPhase`, `errorInfo`, `audioTracks`, `selectAudioTrack`, `AetherPlayerSurface`, then read only those sections with `sed -n`), and `Sources/AetherEngine/PlayerState.swift` (`grep -n 'public' | head -80`). Do not open other engine sources. Budget: finish in under 60 tool calls.

**Interfaces:**
- Consumes: Task 2 types.
- Produces: `@MainActor public final class AetherPlaybackEngine: ApplePlaybackEngine { public init() throws }`, `@MainActor public final class NativePlaybackEngine: ApplePlaybackEngine { public init() }`, `@MainActor public enum ApplePlaybackEngineFactory { public static func make(preferred: ApplePlaybackEngineKind) -> (engine: any ApplePlaybackEngine, fellBack: Bool) }`, and `public struct ApplePlaybackSurfaceView: View { public init(engine: any ApplePlaybackEngine) }` that renders the engine's SwiftUI surface (`AetherPlayerSurface`) for the surface route and `EmptyView` for the native engine.

**Policy / behaviour table**

| Engine signal | Required mapping |
| --- | --- |
| `AetherEngine.playbackPhase` idle/loading/playing/paused/seeking/rebuffering/stalled(reconnecting:)/ended/error(msg) | same-named `ApplePlaybackEnginePhase` |
| `videoRoute` `.remoteBypass`, `.loopback` (6.66.0 `VideoRoute` cases: none, remoteBypass, loopback, software, audio; `nativeRemoteHLS` is a `LoadOptions` flag, not a route) | `.avPlayer`, `avPlayer` = the engine's current `AVPlayer` |
| `videoRoute` `.software` | `.surface`, `avPlayer == nil` |
| `videoRoute` `.audio` / `.none` | `.audioOnly` / `.none` |
| `errorInfo` HTTP 401 or 403, or an authentication category | `failure.kind == .authentication`, message "The provider rejected the account or request headers (HTTP <code>)." |
| `errorInfo` unsupported codec/container category | `.unsupportedMedia`, "This stream uses a format OpenStream cannot play on this device." |
| `errorInfo` network/timeout category | `.network` / `.timedOut` with the engine message |
| `playbackPhase == .error(msg)` after `.playing` was reached | `.player` with `msg` |
| `LoadOptions` | `httpHeaders: request.effectiveHeaders`, `isLive: request.isLive`, `dvrWindowSeconds: request.effectiveDVRWindowSeconds`; the engine's own Now Playing ownership option (see api.md) set so the app keeps owning Now Playing |
| `NativePlaybackEngine.load` | `AVURLAsset(url:options:)` with `"AVURLAssetHTTPHeaderFieldsKey": request.effectiveHeaders` when non-empty; `route = .avPlayer`; phases derived from `AVPlayer.timeControlStatus`, `AVPlayerItem.status`, `isPlaybackBufferEmpty`, `AVPlayerItemDidPlayToEndTime`, `AVPlayerItemFailedToPlayToEndTime`; `unsupportedMedia` for `AVFoundationErrorDomain` `-11828`/`-11829`, `.authentication` for HTTP 401/403 in the underlying error, else `.player` |
| Factory `make(preferred: .openStream)` when `AetherPlaybackEngine()` throws | returns `NativePlaybackEngine`, `fellBack == true`, logs once via `os.Logger(subsystem: "com.orgista.openstream", category: "playback")` |
| Factory `make(preferred: .native)` | `NativePlaybackEngine`, `fellBack == false` |

**Implementation requirements**

1. `AetherPlaybackEngine` owns one `AetherEngine`, subscribes to its published properties (Combine `sink`s stored in a `Set<AnyCancellable>`), mirrors them into its own properties and emits `ApplePlaybackEngineEvent`s; `stop()` stops and releases the engine session; `deinit`-safe (no retain cycles: `[weak self]`).
2. `position` updates at most 4×/s; `duration` nil for live.
3. `selectAudioTrack(id:)` / `selectSubtitleTrack(id:)` call the engine's track selection (`selectAudioTrack(index:)`, `selectSubtitleTrack(index:)` per api.md); tracks map from the engine's `TrackInfo` (id, title/name, language, codec).
4. Fixture tests are `@Test(.enabled(if: ProcessInfo.processInfo.environment["PLAYBACK_ENGINE_TESTS"] == "1"))`, base URL from `FIXTURE_BASE_URL` (default `http://127.0.0.1:8765`), each waits for a phase with a helper `await waitFor(engine, phase:timeout:)` that consumes `events`.

**Tests**

`ApplePlaybackEngineFixtureTests.swift` (real engine, macOS `swift test`, server from Task 0 running):
- `/media/mp4-h264-aac.mp4` → route `.avPlayer`, `.playing` within 10 s, `duration` ≈ 10–20 s.
- `/media/mkv-h264-aac.mkv` → `.avPlayer`, `.playing` within 10 s.
- `/media/ts-h264-aac.ts` → `.playing` within 10 s.
- `/live/ts-h264-aac.ts` with `isLive: true` → `.playing` within 15 s, `duration == nil`.
- `/media/mkv-hevc-eac3.mkv` → `.playing`; `audioTracks.first?.codec` contains `eac3` (case-insensitive).
- `/media/ts-mpeg2-interlaced-mp2.ts` → route `.surface`, `.playing` within 15 s.
- `/protected/mp4-h264-aac.mp4` with `headers: ["Referer": "https://fixtures.local/x"]` → `.playing`; without headers → `failure?.kind == .authentication` within 10 s.
- `/slow/mp4-h264-aac.mp4` → `.playing` within 30 s.
- VOD seek: after `.playing`, `seek(to: 5)` → `position >= 4.5` within 3 s.
- `/media/dv81-hevc-eac3.mp4` → `.avPlayer`, `.playing` (the simulator/Mac cannot show Dolby Vision; this proves the remux preserves the DV configuration and the stream loads).

`ApplePlaybackEngineFactoryTests.swift`: the two factory rows (inject a `makeAether: () throws -> any ApplePlaybackEngine` closure parameter with a default so the throwing case is testable).

**Out of scope:** coordinator, views, sources; Now Playing changes; visionOS immersive.

**Verify:** `swift build …`; `swift test …` (known failure only); `python3 Tests/Fixtures/serve.py & PLAYBACK_ENGINE_TESTS=1 swift test --scratch-path … --filter ApplePlaybackEngineFixtureTests` all pass; kill the server.

---

### Task 4: Coordinator, player host, and player view on both routes

**Files:**
- Modify: `Sources/OpenStreamApple/ApplePlaybackCoordinator.swift`, `Sources/OpenStreamApple/AppleStremioPlaybackView.swift`, `Sources/OpenStreamApple/ApplePlayerControllers.swift`, `Sources/OpenStreamApple/ApplePlayerSession.swift`, `Sources/OpenStreamApple/ApplePlaybackInfoView.swift`
- Create: `Sources/OpenStreamApple/ApplePlayerHost.swift`, `Sources/OpenStreamApple/AppleTransportOverlay.swift` (minimal in this task), `Tests/OpenStreamAppleTests/ApplePlaybackCoordinatorTests.swift`
- Read first: `ApplePlaybackCoordinator.swift`, `AppleStremioPlaybackView.swift`, `ApplePlayerControllers.swift`, `AppleAudioSessionCoordinator.swift`, `ApplePlaybackProgressCoordinator` (in `ApplePlayerSession.swift` or its own file), Task 2/3 files.

**Interfaces:**
- Consumes: `ApplePlaybackEngine`, `ApplePlaybackEngineFactory`, `ApplePlaybackRequest`, `ApplePlaybackSurfaceView`.
- Produces:

```swift
public enum ApplePlaybackPhase: Equatable, Sendable { case idle, resolving, loading, waiting(String?), playing, paused, ended, failed(ApplePlaybackFailure) }   // inspecting/preparing removed
@MainActor public final class ApplePlaybackCoordinator {
    public private(set) var phase: ApplePlaybackPhase
    public private(set) var route: ApplePlaybackPresentationRoute
    public let engine: any ApplePlaybackEngine
    public init(engine: any ApplePlaybackEngine)
    public func beginResolving()
    public func begin(_ request: ApplePlaybackRequest) async      // load + observe; never throws, failures land in phase
    public func retry() async                                      // re-load the last request
    public func stop()
    public func update(_ phase: ApplePlaybackPhase); public func reset(); public func fail(_ error: any Error) -> ApplePlaybackFailure   // kept
}
@MainActor public final class ApplePlayerHost {
    public init(coordinator: ApplePlaybackCoordinator, audioSession: AppleAudioSessionCoordinator)
    public var route: ApplePlaybackPresentationRoute { get }
    #if os(macOS) public var playerView: AVPlayerView { get } #else public var viewController: AVPlayerViewController { get } #endif   // bound to engine.avPlayer whenever it changes
    public func teardown()
}
```

**Policy / behaviour table**

| Engine event | Coordinator phase | Player view |
| --- | --- | --- |
| `.phase(.loading)` | `.loading` | waiting overlay "Loading…" |
| `.phase(.rebuffering)` | `.waiting("Buffering…")` | overlay, no alert |
| `.phase(.stalled(reconnecting: true))` | `.waiting("Reconnecting…")` | overlay, no alert |
| `.phase(.playing)` | `.playing` | overlay hidden |
| `.phase(.paused)` | `.paused` | nothing |
| `.phase(.ended)` and `request.isLive == false` | `.ended` | dismiss the player |
| `.phase(.ended)` and live | `.waiting("Stream ended. Reconnecting…")` then `retry()` once after 3 s; second `.ended` → `.failed(.sourceEnded)` | alert "The channel stopped sending data." with Retry / Close |
| `.failure(f)` any time | `.failed(f)` | alert with `f.message`, Retry and Close; the string "No compatible stream." is gone |
| no `.playing` within 20 s of `begin` | `.failed(.timedOut)` | "The player did not become ready in time." + Retry/Close |
| `.route(.avPlayer)` | `route = .avPlayer` | AVKit controller/view from `ApplePlayerHost` (current behaviour, PiP/AirPlay intact) |
| `.route(.surface)` | `route = .surface` | `ApplePlaybackSurfaceView` + `AppleTransportOverlay` |
| route changes mid-session | swap | view swaps without dismissing |
| progress persistence | `.avPlayer`: existing `ApplePlaybackProgressCoordinator` on `engine.avPlayer`; `.surface`: `.position` events throttled to one write per 5 s into the same store | unchanged store format |
| tvOS 26.5+ display criteria | n/a | `viewController.appliesPreferredDisplayCriteriaAutomatically = false` on tvOS |
| Now Playing | app-owned today | still app-owned, both routes |

**Implementation requirements**

1. Rewrite `ApplePlaybackCoordinator` around `begin(_:)`: keeps `lastRequest`, spawns one observation `Task` over `engine.events`, cancels it in `stop()`/`reset()`. `beginInspecting()`/`beginPreparing()` callers become `update(.loading)`.
2. `AppleStremioPlayerPresentation` carries an `ApplePlaybackRequest` instead of `ApplePreparedPlayback`; `AppleStremioPlayerView` builds `ApplePlayerHost`, switches on `coordinator.route`, and hosts the overlay on `.surface`. Until Task 6 lands, keep a temporary initializer `ApplePlaybackRequest(prepared: ApplePreparedPlayback, mediaID:title:sourceKind:)` so existing callers compile; mark it `// Task 6 removes`.
3. `ApplePlayerControllers.swift`: the four platform controllers are reduced to what `ApplePlayerHost` needs (audio session activation, visionOS immersive hooks stay as extensions on the host); delete anything left unreferenced.
4. `ApplePlayerSession` keeps only what `NativePlaybackEngine` and progress persistence use.
5. Minimal `AppleTransportOverlay`: Done button (top-left, dismisses), play/pause toggle, "LIVE" badge when `request.isLive`, waiting text. Task 5 finishes it.
6. `ApplePlaybackInfoView` shows engine kind and route as text rows.

**Tests** (`ApplePlaybackCoordinatorTests.swift`, `FakePlaybackEngine`): every row of the table that does not need a view; the 20 s timeout uses an injected `timeout: Duration` (default `.seconds(20)`, tests use `.milliseconds(50)`); live `.ended` → retry once → second `.ended` → `.failed(.sourceEnded)`; progress write throttling (inject a recording store closure).

**Out of scope:** sources and route policy (Task 6); overlay scrubber/pickers (Task 5); settings.

**Verify:** `swift build …`, `swift test …`, xcodebuild iOS.

---

### Task 5: Transport overlay for the surface route

**Files:**
- Modify: `Sources/OpenStreamApple/AppleTransportOverlay.swift`
- Create: `Sources/OpenStreamApple/AppleTransportOverlayModel.swift`, `Tests/OpenStreamAppleTests/AppleTransportOverlayModelTests.swift`

**Interfaces:**
- Consumes: `ApplePlaybackCoordinator`, `ApplePlaybackEngine`.
- Produces: `@MainActor @Observable public final class AppleTransportOverlayModel { public init(coordinator: ApplePlaybackCoordinator, isLive: Bool); public var isScrubbable: Bool; public var positionText: String; public var durationText: String; public var progress: Double; public func togglePlayPause(); public func scrub(to fraction: Double) async; public func selectAudio(_ id: Int); public func selectSubtitle(_ id: Int?); public var showsAirPlayUnavailableHint: Bool }`

**Policy / behaviour table**

| State | Required |
| --- | --- |
| VOD, duration known | scrubber enabled; `positionText` `m:ss` or `h:mm:ss` when ≥ 1 h; `durationText` likewise |
| live, no DVR window | scrubber hidden, "LIVE" badge, `positionText` empty |
| live with DVR window (`dvrWindowSeconds > 0`) | scrubber over the window; "LIVE" badge tappable → seek to live edge |
| audio tracks > 1 | picker (Menu on iOS/macOS, focusable list on tvOS) listing `title (language)` and marking the selection |
| subtitle tracks > 0 | picker with "Off" first |
| route `.surface` on tvOS | every control is focusable; Menu button on the remote dismisses; play/pause button on the remote toggles |
| route `.surface` and the user opens the AirPlay picker | hint "AirPlay video is unavailable for this stream." |
| controls auto-hide | after 4 s of no interaction while playing; any tap/focus move shows them |
| colors | white on a black gradient; no blue |

**Implementation requirements**

1. Model as above; formatting helpers are pure static functions (`static func timeText(_ seconds: Double) -> String`).
2. View uses the model; tvOS uses `.focusable()` and `onMoveCommand`/`onPlayPauseCommand`; iOS/macOS use gestures.
3. Auto-hide with a cancellable `Task.sleep`.

**Tests**: `timeText(65) == "1:05"`, `timeText(3661) == "1:01:01"`; VOD → `isScrubbable`; live without DVR → not scrubbable; live with DVR → scrubbable; `scrub(to: 0.5)` on a 100 s VOD calls `engine.seek(to: 50)` (assert on `FakePlaybackEngine.seeks`); `selectAudio(2)` forwards; `selectSubtitle(nil)` forwards.

**Out of scope:** AVKit-route UI (untouched); settings.

**Verify:** `swift build …`, `swift test …`, xcodebuild iOS, plus `xcodebuild … -scheme "OpenStream tvOS" -destination 'generic/platform=tvOS Simulator' … build`.

---

### Task 6: Sources build requests; route policy shrinks; IPTV `.m3u8` first

**Files:**
- Modify: `Sources/OpenStreamApple/AppleStremioPlaybackResolver.swift`, `Sources/OpenStreamApple/AppleStremioPlaybackClient.swift`, `Sources/OpenStreamApple/ApplePlaybackPreparer.swift`, `Sources/OpenStreamApple/ApplePlaybackRoute.swift`, `Sources/OpenStreamApple/AppleIPTV.swift`, `Sources/OpenStreamApple/AppleMediaSourceViews.swift`, `Sources/OpenStreamApple/AppleDiscoverView.swift`, `Sources/OpenStreamApple/AppleLibrary.swift`, `Sources/OpenStreamApple/AppleStremioPlaybackView.swift`, `Sources/OpenStreamApple/ApplePlaybackCoordinator.swift` (remove the temporary initializer from Task 4), existing tests `AppleStremioPlaybackTests.swift`, `ApplePlaybackMediaTests.swift`, `AppleIPTVAndLibraryTests.swift`
- Read first: the files above; `ApplePlaybackRequest.swift`.

**Interfaces:**
- Produces: `public struct AppleStremioCandidateRanking { public static func rank(_ candidates: [AppleStremioHTTPPlaybackCandidate]) -> [AppleStremioHTTPPlaybackCandidate] }`, `extension AppleStremioHTTPPlaybackCandidate { public func playbackRequest(mediaID: String, title: String?, resume: Double?) -> ApplePlaybackRequest }`, `extension AppleIPTVChannel { public func playbackRequest() -> ApplePlaybackRequest }`, `public enum AppleXtreamOutputFormat: String { case m3u8, ts; public static func preferred(allowedOutputFormats: [String]) -> AppleXtreamOutputFormat }`.

**Policy / behaviour table**

| Input | Today | Required |
| --- | --- | --- |
| Stremio candidate list | each candidate inspected with `AVURLAsset`; MKV/TS → `.gatewayTranscode`/`.requiresExternalDemux`; slow origins rejected | no inspection; ranking: candidates with `behaviorHints.notWebReady == true` are engine-only (kept, never rejected); order = provider order, then filename/extension preference `.mp4/.m4v` ≥ `.mkv` ≥ `.ts` ≥ unknown, then bitrate hint if present |
| Play tapped on Discover | resolves + inspects, blank white pill | `beginResolving()` → first ranked candidate → `coordinator.begin(request)`; spinner on the pill is `.tint(.black)`; Play disabled while resolving |
| engine reports `.unsupportedMedia` or HTTP failure for candidate N | n/a | try candidate N+1 (max 3 candidates), then `.failed(.unsupportedMedia)` with "None of the N streams for this title plays on this device." |
| `proxyHeaders.request` present | dropped | copied into `hints.proxyHeaders` |
| Xtream live URL | `.m3u8` when allowed else `.ts` (verify) | `AppleXtreamOutputFormat.preferred(allowedOutputFormats:)` → `.m3u8` if the list contains `m3u8` or `hls`, else `.ts`; playlist export uses `output=` under the same rule |
| `#EXTVLCOPT:http-user-agent`, `http-referrer`, `http-origin` | partly dropped | become `headers["User-Agent"]`, `["Referer"]`, `["Origin"]` on the request |
| M3U channel playback | routed through `AppleProtectedHTTPPlaybackServer` (loopback bridge) | direct `ApplePlaybackRequest(url: channel.url, headers: channel.headers, isLive: true, sourceKind: .liveTV)`; the bridge is no longer on the playback path (it remains only for the Test Connection probe) |
| Raw TS detected by the Test Connection sniff | alert tells the user to configure the gateway | success text "Live TV connected. Channels play with the OpenStream engine."; no gateway mention |
| Library / SMB file | `AppleSMBRangeServer` URL → `ApplePreparedPlayback` | same URL → `ApplePlaybackRequest(sourceKind: .networkShare)`; local files → `sourceKind: .files` |
| Offline download (OpenStream Offline library item) | `.nativeOfflineExport` / AVPlayer on the saved file; MKV fails with "could not decode" after showing "Downloaded" (owner, 2026-09-02 21:48, airplane mode) | `ApplePlaybackRequest(url: fileURL, isLive: false, mediaID: item.mediaID, sourceKind: .files)` through the engine; no `AVAssetExportSession` attempt for Matroska/TS; the download record stores the sniffed container (`mkv`, `mp4`, `ts`, `webm` from the first 16 bytes: EBML `1A 45 DF A3`, `ftyp`, `0x47`) so the UI can label it |
| `ApplePlaybackRoutePolicy.route` for Matroska / MPEG-TS | `.gatewayTranscode` / `.requiresExternalDemux` | `.direct(url)` (engine handles it); `.gatewayTranscode` only when the gateway setting is enabled and the engine already reported `.unsupportedMedia` |
| `AppleStremioPlaybackResolutionError.externalDemuxRequired`, `.noCompatibleHTTPStream` | user-facing | no longer produced; keep the cases only if something still references them, otherwise delete them and their messages |
| `AVURLAssetHTTPHeaderFieldsKey` in `ApplePlayerSession` | used | removed (only `NativePlaybackEngine` uses it) |

**Implementation requirements**

1. Implement ranking, request builders and the Xtream format rule as pure functions first, then wire the views.
2. Delete dead inspection code paths (`inspectAndRoute`, `AppleAssetSuitability` users) when nothing references them after the change; keep `ApplePlaybackRoutePolicy.route` for local-file export decisions.
3. Existing tests that asserted the old policy (MKV → gateway, TS → external demux, slow origin rejected) are rewritten to assert the new row; test names and inputs stay, expectations change. Every other existing test stays untouched.

**Tests**
- `AppleStremioPlaybackTests.swift`: ranking order for `[mkv(notWebReady), mp4, ts]` → `[mp4, mkv, ts]`; `proxyHeaders` land in `hints`; candidate fallback after two `.unsupportedMedia` failures picks the third; fourth failure → `.failed(.unsupportedMedia)`.
- `AppleIPTVAndLibraryTests.swift`: `preferred(["m3u8","ts"]) == .m3u8`, `preferred(["ts"]) == .ts`, `preferred([]) == .ts`; `#EXTVLCOPT` mapping; M3U channel request has `isLive == true` and the bridge is not used (assert the URL host is not `127.0.0.1`).
- `ApplePlaybackMediaTests.swift`: Matroska and MPEG-TS route `.direct`.
- Offline: copy `Tests/Fixtures/out/mkv-h264-aac.mkv` into a temp offline library dir, build the request for that item → `sourceKind == .files`, file URL, `isLive == false`; with `PLAYBACK_ENGINE_TESTS=1` the engine reaches `.playing` on it (`.avPlayer` route).

**Out of scope:** settings UI (Task 7); overlay; Top Shelf; Siri; portal.

**Verify:** `swift build …`, `swift test …`, xcodebuild iOS; `grep -rn "No compatible stream\|Configure the Transcode Gateway" Sources` returns nothing.

---

### Task 7: Settings, notices screen, diagnostics, gateway copy

**Files:**
- Modify: `Sources/OpenStreamApple/AppleSettingsStore.swift`, `Sources/OpenStreamApple/AppleSettingsViews.swift`, `Sources/OpenStreamApple/ApplePlaybackInfoView.swift`, `Sources/OpenStreamApple/AppleTranscodeGateway.swift` (copy strings only), `Sources/OpenStreamApple/AppleStremioPlaybackView.swift` (engine from the setting)
- Create: `Sources/OpenStreamApple/AppleThirdPartyNoticesView.swift`, `Tests/OpenStreamAppleTests/AppleSettingsStoreTests.swift` (add to the existing settings test file if one exists instead)

**Interfaces:**
- Consumes: `AppleThirdPartyNotices.all()`, `ApplePlaybackEngineFactory`, `ApplePlaybackEngineKind`.
- Produces: `AppleSettingsStore.playbackEngine: ApplePlaybackEngineKind` (UserDefaults key `openstream.playback.engine`, default `.openStream`), `AppleSettingsStore.engineFellBackToNative: Bool` (runtime, not persisted).

**Policy / behaviour table**

| Setting / screen | Today | Required |
| --- | --- | --- |
| `Settings → Playback → Engine` | absent | picker "OpenStream Engine" / "Native (AVPlayer only)"; footer "Native plays only HLS and MP4. Use it for diagnosis." |
| engine fell back | invisible | `Playback Info` row "Engine: Native (OpenStream Engine failed to start)"; shown once per launch |
| `Settings → About → Third-Party Notices` | absent | list of `AppleThirdPartyNotices.all()` → detail with the full text, monospaced, scrollable; the source-offer sentence as the list footer |
| Gateway section copy | "fallback for media the device cannot decode" | "Optional remote accelerator. Playback works without it." |
| Player creation | hard-coded | `ApplePlaybackEngineFactory.make(preferred: settings.playbackEngine)` at presentation time |

**Implementation requirements**

1. Settings store property with a persisted raw value; invalid stored strings fall back to `.openStream`.
2. Views follow the existing section/row style in `AppleSettingsViews.swift` (labels visible, no blue accents).
3. Notices view works on tvOS (focusable rows, text in a `ScrollView`).

**Tests**: round-trip of the setting through `UserDefaults(suiteName:)`; invalid raw value → default; factory receives the stored preference (assert via injected factory closure).

**Out of scope:** any playback-path change; account/sign-in.

**Verify:** `swift build …`, `swift test …`, xcodebuild iOS and tvOS.

---

### Task 7b (lane, after T7): one Netflix-style transport overlay on both routes

**Files:**
- Modify: `Sources/OpenStreamApple/AppleTransportOverlay.swift`, `Sources/OpenStreamApple/AppleTransportOverlayModel.swift`, `Sources/OpenStreamApple/ApplePlayerHost.swift`, `Sources/OpenStreamApple/AppleStremioPlaybackView.swift`, `Tests/OpenStreamAppleTests/AppleTransportOverlayModelTests.swift`
- Read first: those files, `ApplePlaybackCoordinator.swift`, `ApplePlaybackEngine.swift`; owner reference `design/detail-page-reference-netflix.png` is in the main repo only — the look is: black gradient top and bottom, white glyphs, big centered play/pause, 10 s skip buttons either side, a scrubber with elapsed/remaining labels at the bottom, a row of secondary actions (Audio & Subtitles, Speed, AirPlay, PiP, Next Episode) and Done at the top-left.

**Interfaces:**
- Consumes: Task 4/5 types (`ApplePlaybackCoordinator`, `ApplePlayerHost`, `AppleTransportOverlayModel`).
- Produces: `AppleTransportOverlayModel` gains `public var route: ApplePlaybackPresentationRoute`, `public var showsAirPlay: Bool`, `public var showsPictureInPicture: Bool`, `public var playbackRate: Double` (0.5, 0.75, 1, 1.25, 1.5, 2), `public var nextEpisode: (() -> Void)?`, `public func skip(by seconds: Double) async`, `public func setRate(_ rate: Double)`; `ApplePlayerHost` gains `public var usesCustomControls: Bool` (default true).

**Policy / behaviour table**

| Route / state | Required |
| --- | --- |
| `.avPlayer` (AVKit controller) | `showsPlaybackControls = false` (iOS/tvOS) / `controlsStyle = .none` (macOS); the overlay is hosted in `contentOverlayView` (iOS/tvOS) or above `AVPlayerView` (macOS); PiP, AirPlay routing and Now Playing keep working (`allowsPictureInPicturePlayback` stays true) |
| `.surface` | overlay as in Task 5; `showsAirPlay == false`, `showsPictureInPicture == false` |
| `.avPlayer` on iOS | `showsAirPlay == true` (uses `AVRoutePickerView`), `showsPictureInPicture == true` (button toggles PiP through the AVKit controller) |
| `.avPlayer` on tvOS | `showsAirPlay == true`, `showsPictureInPicture == false` |
| `skip(by: ±10)` | `engine.seek(to:)` clamped to `[0, duration]` for VOD; clamped to the DVR window for live-DVR; no-op for live without DVR |
| `setRate(r)` | `engine.avPlayer?.rate = r` while playing on `.avPlayer`; on `.surface` the engine's rate API if present, else the control is hidden; rate resets to 1 on a new `load` |
| `nextEpisode` non-nil | "Next Episode" button visible; tapping calls it |
| controls auto-hide | 4 s, any tap or remote move shows them; while paused the controls stay visible |
| scrubber | elapsed left, remaining (`-m:ss`) right; drag shows a time bubble; release seeks once |
| tvOS remote | play/pause toggles, left/right skip 10 s, menu = Done, select while hidden = show |
| colors | white on black gradients; no blue (`AVRoutePickerView` tint set to white) |

**Implementation requirements**
1. Keep one overlay implementation; route only changes which secondary buttons render.
2. `ApplePlayerHost` applies `usesCustomControls` when it vends the AVKit controller and re-applies after every rebind.
3. Scrubber and skip use the model only; the view has no direct engine calls.

**Tests** (`AppleTransportOverlayModelTests.swift`, `FakePlaybackEngine`): route `.avPlayer` on iOS → AirPlay and PiP flags true; `.surface` → both false; `skip(by: 10)` from 5 s on a 100 s VOD seeks to 15; from 95 s seeks to 100; live without DVR → no seek recorded; `setRate(1.5)` then `load` → rate back to 1; `nextEpisode` nil hides the action (model flag `showsNextEpisode`). Existing 10 overlay tests keep passing.

**Out of scope:** thumbnails on the scrubber; chapter markers; the detail page.

**Verify:** `swift build …`, `swift test …` (known Bonjour failure only), xcodebuild iOS, `xcodebuild … -scheme "OpenStream tvOS" -destination 'generic/platform=tvOS Simulator' ARCHS=arm64 … build`.

---

### Task 7c (lane follow-up, after merge-back): finish the request-based play paths

Found by the merge review (2026-09-03 06:55): the Live tab still plays through `client.playbackURL(for:)` + `ApplePlaybackPreparer` (bridge first, then the engine), and `AppleStremioCandidateRanking` has tests but no production call site. This task runs on a FRESH lane snapshot of the merged main tree (re-run the snapshot recipe; baseline = merged tree), not on the old lane.

**Files:**
- Modify: `Sources/OpenStreamApple/AppleMediaSourceViews.swift` (Live play path only), `Sources/OpenStreamApple/AppleStremioPlaybackResolver.swift`, `Sources/OpenStreamApple/AppleDiscoverView.swift` (play path only), `Sources/OpenStreamApple/AppleIPTV.swift` (only if `playbackRequest()` needs headers it does not have yet), `Sources/OpenStreamApple/ApplePlaybackEngineFactory.swift`, `ApplePlayerHost.swift`, `ApplePlaybackSurfaceView.swift` (comment artifacts only)
- Tests: `Tests/OpenStreamAppleTests/AppleIPTVAndLibraryTests.swift`, `AppleStremioPlaybackTests.swift`

**Policy / behaviour table**

| Path | Today (merged tree) | Required |
| --- | --- | --- |
| Live channel tap (M3U or Xtream) | `client.playbackURL(for:)` → loopback bridge when the channel has headers → preparer → request → engine | `channel.playbackRequest()` (direct upstream URL, `headers` from `#EXTVLCOPT`/account, `isLive: true`, `sourceKind: .liveTV`) → `coordinator.begin(request)`; the bridge is not used for playback (it stays for the Test Connection probe only) |
| Discover Play | resolver inspects/ranks internally, hands a prepared playback | resolver returns ranked candidates via `AppleStremioCandidateRanking.rank`, the view builds the request from the first, and the coordinator's existing candidate fallback tries the next on `.unsupportedMedia`/HTTP failure |
| `ApplePreparedPlayback` / `AppleStremioPlayerPresentation(prepared:…)` temporary initializer | still present ("Task 6 removes") | removed; all call sites use `request:` |
| Comment artifacts `ApplePlaybackEngineFactory.swift:26`, `ApplePlayerHost.swift:134`, `ApplePlaybackSurfaceView.swift:4` | scrubbed text in comments | plain English comments |

**Tests**: Live channel with `#EXTVLCOPT:http-user-agent` → request headers contain it and the URL host is the upstream host (not 127.0.0.1); Xtream channel → `.m3u8` URL when allowed; Discover: ranked candidate order reaches the coordinator (assert via `FakePlaybackEngine.loadedRequests`); no test weakened.

**Out of scope:** overlay, settings, notices, UI layout.

**Verify:** `swift build …`, `swift test …` (all pass), `PLAYBACK_ENGINE_TESTS=1` fixture run, xcodebuild iOS; `grep -rn "playbackURL(for:" Sources` returns no playback call site (probe only).

---

### Task 7e (lane, right after 7c, BEFORE 7d): native Apple player controls; overlay only on the surface route

Owner decision 2026-09-03 07:25: "the native Apple player buttons were fine, we don't reinvent the player; we don't even need Speed; look at the Apple TV app". Task 7b's custom controls on the AVKit route are reverted.

**Files:**
- Modify: `Sources/OpenStreamApple/ApplePlayerHost.swift`, `Sources/OpenStreamApple/AppleStremioPlaybackView.swift`, `Sources/OpenStreamApple/AppleTransportOverlay.swift`, `Sources/OpenStreamApple/AppleTransportOverlayModel.swift`, `Tests/OpenStreamAppleTests/AppleTransportOverlayModelTests.swift`

**Policy / behaviour table**

| Route | Required |
| --- | --- |
| `.avPlayer` (iOS, tvOS, macOS, visionOS) | the system player UI: `showsPlaybackControls = true` (macOS `controlsStyle = .floating`), `allowsPictureInPicturePlayback = true`, `allowsVideoFrameAnalysis = false` (no Live Text / "Show Text"), `canStartPictureInPictureAutomaticallyFromInline` as before, `appliesPreferredDisplayCriteriaAutomatically = false` on tvOS 26.5+; NO custom overlay, no custom buttons, nothing drawn in `contentOverlayView`; captions, audio, AirPlay and PiP come from the system menus |
| `.surface` (software decode only) | the minimal overlay, styled after the Apple TV app's player: top-left Done, bottom scrubber with elapsed/remaining (hidden for live without DVR; LIVE badge shown), play/pause and 10 s skips centered, one "Audio & Subtitles" button; nothing else — no Speed, no AirPlay, no PiP, no Next Episode |
| Speed control | removed everywhere (`playbackRate`, `setRate`, the Speed menu and its tests are deleted) |
| Live channel on `.avPlayer` | the system UI's live behaviour (scrubbing limited to the DVR window the engine exposes) |
| Waiting / buffering indicator | Owner 2026-09-03 07:45: "no box element for buffering, a standard spinning circle; the live player on the sim looks tacky." On `.avPlayer` routes NO custom waiting/buffering view at all (the system player shows its own spinner; `waiting(_:)` phases only update the coordinator state). Before the player exists (resolving/loading, black screen) and on the `.surface` route: a centered `ProgressView()` with `.progressViewStyle(.circular)`, `.tint(.white)`, `controlSize(.large)`, no text, no background box, no border; the alert for failures is unchanged. Delete the "Buffering…"/"Reconnecting…" label box and its styling; the strings stay only as accessibility labels on the spinner. |
| Done / dismiss | on `.avPlayer` the system Done/X dismisses (existing presentation dismissal path) |

**Tests**: overlay model: `.avPlayer` → `showsOverlay == false` and `showsWaitingIndicator == false` even while `.waiting`; `.surface` while `.waiting` → `showsWaitingIndicator == true`, `waitingText` used only as the accessibility label; no rate API exists (compile-time); existing overlay tests updated to the reduced control set, none weakened beyond removing Speed cases.

**Out of scope:** captions plumbing (7d, revised to fit: on `.avPlayer` subtitles must reach the system menu; on `.surface` the overlay's Audio & Subtitles button).

**Verify:** `swift build …`, `swift test …`, xcodebuild iOS + tvOS (`ARCHS=arm64`), and the fixture run.

---

### Task 7d (lane, after 7c): captions through the engine; no system text controls

**Files:**
- Modify: `Sources/OpenStreamApple/AetherPlaybackEngine.swift`, `Sources/OpenStreamApple/NativePlaybackEngine.swift`, `Sources/OpenStreamApple/ApplePlayerHost.swift`, `Sources/OpenStreamApple/AppleTransportOverlay.swift`, `Sources/OpenStreamApple/AppleTransportOverlayModel.swift`, `Sources/OpenStreamApple/AppleSettingsStore.swift`
- Tests: `Tests/OpenStreamAppleTests/AppleTransportOverlayModelTests.swift`, `Tests/OpenStreamAppleTests/ApplePlaybackEngineFixtureTests.swift`
- Read first: the engine checkout's `docs/api.md` sections on `subtitleTracks`, `selectSubtitleTrack(index:)`, `subtitleCues` (`.text`, `.richText`, `.image`) — `grep -n` then `sed -n` ranges only.

**Policy / behaviour table**

| Case | Required |
| --- | --- |
| MKV with embedded SRT/ASS, TS with DVB/teletext, HLS with WebVTT | `subtitleTracks` lists them with language and codec; "Off" first in the picker; selecting one shows cues |
| `.avPlayer` routes | subtitles must appear in the SYSTEM player's captions menu: verify (engine `docs/api.md`) whether the loopback HLS carries subtitle renditions (WebVTT) for embedded SRT/ASS/DVB tracks; if it does not, the only custom element allowed on this route is a single CC button (top-right, system-style) that opens the engine's subtitle picker and the engine renders cues; no other overlay |
| `.surface` route | cues rendered by the overlay as above; `.image` cues rendered as images |
| Preferred language | `Settings → Playback → Captions` (Off / English / device language / always) stored in `AppleSettingsStore.captionsPreference`; auto-select on load when "always" or the language matches; the existing "Captions Auto-On" toggle migrates to this |
| System text features | `AVPlayerViewController.allowsVideoFrameAnalysis = false`, `showsPlaybackControls = false`, `requiresLinearPlayback` unchanged; no Live Text / "Show Text" surface anywhere |
| CC button | shows filled when a track is selected; long-press opens the picker directly |

**Tests**: model: selecting a track forwards `id`, "Off" forwards nil, CC state flag; fixture: `mkv-h264-aac.mkv` gains an SRT track in `make-fixtures.sh` (`-i subs.srt -c:s srt`) and the engine lists one subtitle track for it; settings round-trip.

**Out of scope:** OpenSubtitles download (later), styling options.

**Verify:** `swift build …`, `swift test …`, `PLAYBACK_ENGINE_TESTS=1` fixture run, xcodebuild iOS.

---

### Task 8 (Codex, main tree, via FEEDBACK.md): Liquid Glass off and iOS 18 navigation

Not a lane task. Done by Codex in `native/apple` on the main tree; Fable already added `UIDesignRequiresCompatibility = YES` to `Apps/Shared/Info.plist` in both trees.

- Remove the custom `topBarLeading` wrappers and floating pills that iOS 26 renders as glass bubbles (Antigravity finding, `RESEARCH-AND-RECOMMENDATIONS-2026-09-02.md` "Restore iOS 18 Navigation"); use `.navigationTitle` + `.navigationBarTitleDisplayMode(.large)` and the standard `TabView`.
- No `.glassEffect`, `GlassEffectContainer`, or `.buttonStyle(.glass…)` anywhere (none today; keep it that way).
- Keep the UX audit order from `UX-AUDIT-2026-09-02.md`: detail page (#1 #2 #4 #3), forms (#10 #12 #15), discover (#5 #6 #7), copy (#8 #9 #13), first run (#17), web management (#11).
- Do not touch the playback files listed under "File structure" above; the engine lane owns them until merge-back.

---

### Task 9 (owner hardware checklist, after merge-back)

Run on an Apple TV 4K connected to a Dolby Vision TV and an Atmos receiver/soundbar, and on an iPhone with a Dolby Vision display. Fixtures from Task 0 served from the Mac (`python3 Tests/Fixtures/serve.py`), plus the private samples.

| Check | Fixture | Pass when |
| --- | --- | --- |
| Dolby Vision profile 8.1 | `private/dv-atmos-thepitt-s02e10.mkv`, `private/dv-freebert-s01e01.mkv` (real), `dv81-hevc-eac3.mkv` (synthetic) | TV shows its Dolby Vision badge; no green/purple tint |
| Dolby Vision profile 5 | still needed: a streaming P5 file (Stremio/debrid WEB-DL with `dv_profile=5`) | Dolby Vision badge; correct colors (P5 wrong = purple/green) |
| Dolby Vision profile 7 (UHD Blu-ray dual layer) | `private/dv7-truehd-atmos-gladiator2.mkv`, `private/hdr10plus-dv7-blackphone2.mkv` | engine plays it as single-layer 8.1: DV badge, no artifacts |
| HDR10 / HLG | `private/hdr10-got-s07e04.mkv`, `hdr10-hevc.mp4` | TV switches to HDR |
| Dolby Digital 5.1 | `ts-h264-interlaced-ac3.ts` | receiver shows Dolby Digital, 5.1 |
| Dolby Digital Plus | `mkv-hevc-eac3.mkv` | receiver shows Dolby Digital Plus |
| Atmos | `private/dv-atmos-thepitt-s02e10.mkv` (HEVC), `private/atmos-1080p-daredevil.mkv` (H.264) | receiver shows Dolby Atmos (EAC3-JOC passthrough) |
| TrueHD Atmos / DTS-HD MA / DTS:X | `private/dv81-truehd-atmos-weapons.mkv`, `private/dv81-dtshdma-oppenheimer.mkv`, `private/dtsx-dv-harrypotter2.mkv` (real), `mkv-hevc-truehd.mkv`, `mkv-hevc-dts.mkv` (synthetic) | multichannel audio plays (passthrough or bridged to EAC3 5.1 / PCM); no silence; TrueHD Atmos falls back to the EAC3 Atmos compat track where present |
| Interlaced broadcast | `ts-mpeg2-interlaced-mp2.ts`, real Xtream 1080i channel | no combing, overlay works, Menu exits |
| Xtream live | real account, 5 channels incl. one `.ts`-only panel if available | zap under 6 s, 10 min without stall alert |
| AirPlay / PiP | `mp4-h264-aac.mp4`, `mkv-h264-aac.mkv` | AirPlay to the TV works on `.avPlayer` routes; PiP on iPhone |
| Background audio | any | audio continues when the app is backgrounded |
| tvOS remote | surface route | every overlay control reachable with the remote |
| Memory | `dv81` 4K sample if available | no jetsam on Apple TV over 20 min |

---

## Known constraint (found by T5, 2026-09-02 23:16)

AetherEngine 6.66.0's `libdovi.a` (LibDovi, static) carries device slices only, so `xcodebuild … -destination 'generic/platform=tvOS Simulator'` fails at link time. iOS simulator, macOS and all device builds are unaffected. Consequence: the tvOS gate is a device build (`-destination 'generic/platform=tvOS'`, automatic signing) and tvOS runtime checks happen on OfficePlus (paired Apple TV 4K, CoreDevice 64833210-BCBB-5CA3-85C8-49B6E490210B). File an upstream issue on AetherEngine asking for a tvOS-simulator slice of libdovi; re-check on the next engine bump.

## Test matrix (every feature, who verifies, how)

| Area | Automated ($0) | Agent walkthrough | Owner |
| --- | --- | --- | --- |
| Package builds, unit tests | `swift build`, `swift test` after every task (driver) | | |
| App targets build | xcodebuild iOS + tvOS (driver) | | |
| License | `scripts/apple-license-check.sh` (driver, every engine bump) | | |
| Engine routes and codecs | fixture tests (Task 3) on macOS | | Task 9 |
| Coordinator states, failures, retries | unit tests with `FakePlaybackEngine` (Task 4) | | |
| Overlay | model tests (Task 5) | simulator screenshots (Sonnet investigator) | tvOS remote |
| Stremio, IPTV, Library request building | unit tests (Task 6) | simulator: add Cinemeta + Xtream account, play a channel and a title | real account |
| Settings, notices, gateway copy | unit tests (Task 7) | simulator screenshots | |
| UI/UX audit items, glass off | none | simulator screenshots per Codex batch | phone in hand |
| Dolby Vision, Atmos, AirPlay, PiP, background audio | none possible | none possible | Task 9 |

Simulator walkthrough script (Sonnet, after merge-back): install the newest `OpenStream.app` on iPhone 17 Pro `4484625E-8588-4486-87C7-CEFA38741137`, start the fixture server, add an M3U source pointing at `http://127.0.0.1:8765/media/…` channels (the simulator shares the Mac's loopback), play `ts-h264-aac`, `ts-mpeg2-interlaced-mp2`, `mkv-hevc-eac3`; screenshot Discover, Detail, Live, Player, Settings → Playback, About → Notices; grep `xcrun simctl spawn <udid> log show --last 10m --predicate 'subsystem == "com.orgista.openstream"'` for `error`.

---

## Merge back to the main tree

1. Wait for a Codex pause (owner says so, or `git -C OpenStream status` stops changing for 30 minutes).
2. `git -C <lane> diff 3a5c3ab..HEAD > lane.patch` (everything the workers landed, on top of the snapshot of Codex's tree at 19:54).
3. `git -C OpenStream apply --3way --directory=native/apple lane.patch`; resolve conflicts (expected in `AppleDiscoverView.swift`, `AppleMediaSourceViews.swift`, `AppleSettingsViews.swift`, `Info.plist`).
4. Run the gates on the main tree; `PLAYBACK_ENGINE_TESTS=1` fixture run; xcodebuild all four schemes.
5. Sonnet simulator walkthrough; Fable reads the diff-stat and the failure-copy grep; commit with the plan's task titles.
6. Owner runs Task 9.
