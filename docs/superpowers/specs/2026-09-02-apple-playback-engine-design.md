# OpenStream Apple playback engine: design

Date: 2026-09-02 · Status: approved in discussion, pending owner review of this document
Scope: `native/apple` (iOS 18, tvOS 18, macOS 15, visionOS 2)

## 1. Problem

AVFoundation cannot play what most of OpenStream's sources produce: raw MPEG-TS
over HTTP (Xtream and M3U live TV), Matroska (debrid links from Stremio add-ons,
NAS files), and interlaced broadcast video. The app today probes every candidate
with `AVURLAsset`, rejects those formats, and either shows "AVPlayer could not
decode this media" (Live) or "No compatible stream." (Discover). The owner has no
transcode gateway and wants on-device handling, the way Infuse does it.
Reproduction and research: `native/apple/FEEDBACK.md` (playback-engine section),
`native/apple/RESEARCH-playback-engines-2026-09-02.md`.

## 2. Decisions already made

- License posture: LGPL dynamic frameworks embedded in the app with a
  third-party notices screen are acceptable. GPL components are not. (Owner,
  2026-09-02.)
- Phase 1 scope: live TS (Xtream, M3U) and MKV/MP4 from add-ons and SMB, with
  H.264/HEVC video and AAC/AC3/EAC3 audio, must play. Long-tail codecs come for
  free with the chosen engine's software route but are not a phase-1 gate.
- Engine: adopt **AetherEngine** (`https://github.com/superuser404notfound/AetherEngine`),
  LGPL-3.0 with an explicit App Store/DRM exception, FFmpeg built without GPL
  components, no private API, Swift 6 language mode, iOS 16 / tvOS 17 /
  macOS 14 / visionOS 1 floors. Verified in the research brief from a clone of
  tag 6.65.0.
- One player UI and one engine with live and on-demand modes, not a separate
  live player.
- Approach A: the engine is the single playback path; direct AVPlayer remains
  only as an automatic fallback when the engine cannot initialize.

## 3. How AetherEngine fits

The engine is `@MainActor public final class AetherEngine: ObservableObject`
with `public init() throws` and
`load(url:startPosition:options:audioSourceStreamIndex:discTitleID:) async throws`.
`LoadOptions` carries `httpHeaders: [String: String]`, `isLive: Bool`,
`dvrWindowSeconds: Double?`, and `nativeRemoteHLS`. It publishes `state`,
`playbackPhase` (`idle, loading, playing, paused, seeking, rebuffering,
stalled(reconnecting:), ended, error(String)`), `errorInfo`, `videoRoute`
(`none, remoteBypass, loopback, software, audio`), `isSessionReady`,
`hasFirstFrameReadyForDisplay`, `duration`, `audioTracks`, `subtitleTracks`,
and a current `AVPlayer` for the `remoteBypass` and `loopback` routes (see
`docs/api.md` in the engine repo; nil on the `software` route). Rendering on the
software route uses `AetherPlayerView` / `AetherPlayerSurface`.

Routes the engine chooses on its own:

| Input | Route | Presentation |
| --- | --- | --- |
| Remote HLS (`.m3u8`) | `remoteBypass`: AVPlayer plays the origin | `AVPlayerViewController` / `AVPlayerView` |
| MP4, MKV, raw TS, most codecs | `loopback`: libavformat demux → fMP4 HLS on 127.0.0.1 → AVPlayer | `AVPlayerViewController` / `AVPlayerView` |
| Interlaced H.264, VP9, MPEG-2, VC-1, AV1 without hardware | `software`: libavcodec/dav1d → `AVSampleBufferDisplayLayer` | `AetherPlayerSurface` + OpenStream transport overlay |

Consequences to design for: the software route has no AVPlayer, so no
`AVPlayerViewController`, no AirPlay video, and no PiP on tvOS. Interlaced
1080i broadcast channels are common in IPTV, so the software route is a
phase-1 path, not an edge case.

## 4. Architecture

```
Detail Play / Live tap / Library tap
        │
        ▼
AppleStremioPlaybackResolver / AppleLiveTVView / AppleLibraryView
  pick candidate (no AVURLAsset probe), build ApplePlaybackRequest
        │
        ▼
ApplePlaybackCoordinator.begin(request)
        │
        ▼
ApplePlaybackEngine (protocol)
  ├─ AetherPlaybackEngine  (default; wraps AetherEngine on the main actor)
  └─ NativePlaybackEngine  (fallback; today's ApplePlayerSession)
        │  publishes ApplePlaybackRoute { .avPlayer(AVPlayer) | .surface }
        ▼                                 and ApplePlaybackPhase
ApplePlayerHost (route-aware)
  ├─ .avPlayer → AVPlayerViewController (iOS/tvOS/visionOS) / AVPlayerView (macOS)
  └─ .surface  → AetherPlayerSurface + AppleTransportOverlay
```

### 4.1 New and changed units

**`ApplePlaybackRequest`** (new, `Sendable` value): `url`, `headers`,
`isLive`, `dvrWindowSeconds`, `resumePosition`, `mediaID`, `title`,
`sourceKind` (stremio, liveTV, files, networkShare), `hints`
(`notWebReady`, `proxyHeaders`, `filename`). It replaces `ApplePreparedPlayback`
plus the hand-threaded `requestHeaders` and is the single input to the engine.

**`ApplePlaybackEngine`** (new protocol, main actor):
`load(_ request: ApplePlaybackRequest) async throws`, `play()`, `pause()`,
`seek(to:)`, `stop()`, `selectAudioTrack(_:)`, `selectSubtitle(_:)`, and
observable `phase: ApplePlaybackPhase`, `route: ApplePlaybackRoute`,
`position`, `duration`, `audioTracks`, `subtitleTracks`, `failure:
ApplePlaybackFailure?`. Implemented by:

- `AetherPlaybackEngine`: owns one `AetherEngine`, maps `LoadOptions` from the
  request (`httpHeaders` ← `headers` merged with `hints.proxyHeaders.request`,
  `isLive`, `dvrWindowSeconds` 1800 for live TV), maps `playbackPhase` and
  `errorInfo` to `ApplePlaybackPhase` / `ApplePlaybackFailure`, maps
  `videoRoute` to `ApplePlaybackRoute`, keeps `ownsVideoNowPlayingSession`
  false, and stops the engine on teardown.
- `NativePlaybackEngine`: wraps today's `ApplePlayerSession`; used only when
  `AetherEngine()` throws or the "Native" engine setting is chosen.

**`ApplePlaybackCoordinator`** (changed): phases become
`idle → resolving → loading → waiting → playing / paused / ended / failed`,
driven by the engine's observables for the whole session, so mid-stream
failures and stalls reach the UI (closes an audit item). `ApplePlaybackFailure.classify`
gains engine error kinds: network, authentication (401/403), unsupported
codec, timeout, source ended.

**`ApplePlayerHost`** (replaces `AppleStremioPlatformPlayerHost` and the four
platform convenience initializers): one `@MainActor` object that takes the
engine, exposes `route`, and vends either the AVKit controller bound to the
engine's current `AVPlayer` or the `AetherPlayerSurface`. `AppleStremioPlayerView`
switches between the two on route changes. `AppleTransportOverlay` (new,
software route only): play/pause, scrubber bound to `position`/`duration`,
audio and subtitle pickers, live indicator, Done. On tvOS it is focusable and
remote-driven.

**`ApplePlaybackPreparer` / `ApplePlaybackRoutePolicy`** (shrunk): no
`AVURLAsset` inspection for engine-routed media; Matroska and TS no longer map
to `.gatewayTranscode` or `.requiresExternalDemux`. The gateway path remains
only behind the existing setting and is invoked when the engine reports an
unsupported codec and a gateway is configured. Local-file `.nativeOfflineExport`
is unchanged.

**`AppleStremioPlaybackResolver`** (changed): no per-candidate inspection.
Candidates are ranked by `behaviorHints` (`notWebReady` marks engine-only,
never a rejection), filename/extension, and provider order; the resolver
returns the first candidate as a request and the coordinator tries the next
candidate only on an unsupported-codec or HTTP failure from the engine.
`proxyHeaders.request` is forwarded.

**`AppleIPTVClient`** (changed): Xtream live URLs use `.m3u8` when
`user_info.allowed_output_formats` includes it, otherwise `.ts`; playlist
export uses `output=m3u8` under the same rule. `#EXTVLCOPT` headers become
request headers. `AppleProtectedHTTPPlaybackServer` leaves the playback path
(the engine fetches upstream with headers itself); it stays only for the
Test Connection probe until that probe reads through the engine, then it is
deleted. The `AVURLAssetHTTPHeaderFieldsKey` use in `ApplePlayerSession` is
removed.

**`AppleSMBRangeServer`** (kept): still the SMB3-capable path for network
shares; the engine loads `http://127.0.0.1:PORT/media/<token>/<name>` with
range support. The audit's 416, loopback-bind, and session-cache fixes are
made here because playback now depends on it.

**Third-party notices** (new): `Settings → About → Third-Party Notices`
listing AetherEngine (LGPL-3.0 + App Store exception), FFmpeg (LGPL-2.1+),
dav1d (BSD-2), zimg, libzvbi, libdovi (MIT), AMSMB2 and libsmb2 (LGPL-2.1),
with license texts bundled as resources and a source-offer sentence.

### 4.2 Dependency and build

- `Package.swift`: `.package(url: "https://github.com/superuser404notfound/AetherEngine", exact: "6.65.0")`,
  product `AetherEngine` only (`AetherEngineSMB` is not used: SMB 2.0/2.1 only).
- Xcode: embed and sign the engine's dynamic frameworks in the iOS, tvOS,
  macOS, and visionOS app targets, the same phase that embeds AMSMB2; the tvOS
  Top Shelf extension does not link the engine.
- Guardrails: a script in `scripts/` that fails CI when the pinned engine's
  FFmpeg build reports `--enable-gpl` or a GPL library, and when any second
  FFmpeg symbol set appears in the app (engine symbols are prefixed; a second
  FFmpeg would collide).
- Package tests keep building on macOS with `swift test`; engine-backed
  fixture tests are gated behind a `PLAYBACK_ENGINE_TESTS=1` environment
  variable so the default test run stays fast and offline.

### 4.3 Data flow

1. User taps Play (Discover), a channel (Live), or a file (Library).
2. The source view builds an `ApplePlaybackRequest` (Stremio: resolver ranks
   candidates; Live: channel URL + headers, `isLive`; Library: SMB range URL or
   file URL).
3. `ApplePlaybackCoordinator.begin(request)` → `engine.load(request)`.
4. The engine publishes `route`; the host shows AVKit or the surface.
5. The engine publishes phases; the coordinator mirrors them; the player view
   shows the waiting overlay until `playing`, the alert on `failed` with the
   classified reason, and dismisses on `ended` for VOD.
6. Progress: on `.avPlayer` routes, the existing time observer on the vended
   `AVPlayer`; on `.surface`, the engine's `position` publisher, throttled to
   the same 5-second cadence into `ApplePlaybackStore`.
7. Now Playing: app-owned as today, on both routes.

### 4.4 Error handling

| Engine signal | Coordinator | User sees |
| --- | --- | --- |
| `errorInfo` network / HTTP 401, 403 | `.failed(.authentication)` | "The provider rejected the account or request headers (HTTP 403)." |
| `errorInfo` unsupported codec/container | try next candidate; then `.failed(.unsupportedMedia)` | "This stream uses a format OpenStream cannot play on this device." |
| `playbackPhase == .stalled(reconnecting: true)` | `.waiting("Reconnecting…")` | overlay, no alert |
| `playbackPhase == .error(message)` after playing | `.failed(.player)` with message | alert with Retry and Close |
| No first frame within 20 s | `.failed(.timedOut)` | "The player did not become ready…" (existing) |
| `AetherEngine()` throws | switch to `NativePlaybackEngine`, log once | nothing; native behavior |

The generic "No compatible stream." message is removed; every failure names a
reason. The Play button spinner becomes visible (black on the white pill) and
the resolving state disables Play until a request exists.

### 4.5 Platform specifics

- tvOS: no PiP on the software route; the transport overlay is the only
  control surface there and must be focusable. AirPlay video is unavailable on
  the software route; the overlay states "AirPlay video unavailable for this
  stream" if the user opens the route picker.
- visionOS: engine supported; AMSMB2 remains excluded there as today.
- macOS: `AVPlayerView` for AVKit routes, `AetherPlayerSurface` (`NSViewRepresentable`) otherwise.
- Memory: the engine reports about 325 MB RSS on 4K HEVC; tvOS runs must
  verify no jetsam on OfficePlus with the default artwork cache present.

### 4.6 Settings and rollout

- `Settings → Playback → Engine`: "OpenStream Engine" (default) or "Native".
  The setting exists for support and diagnosis, not as a product feature.
- Automatic fallback to Native when the engine fails to initialize, surfaced
  once in `Settings → Playback Info`.
- Rollout order: fixture tests green on macOS and simulator → Anthony smoke
  (Xtream channel, Torrentio + debrid MKV, NAS MKV, AirPlay to OfficePlus) →
  OfficePlus run when provisioning allows.

## 5. Testing

- **Fixture server** (already used in the audit): TS live (looped), TS VOD,
  MKV H.264/AAC, MKV HEVC/EAC3, MP4, HLS, a 12-second first-byte delay, and a
  route that returns 403 unless a Referer header is present. Tests drive the
  real engine through `AetherPlaybackEngine` and assert `route`, `phase`
  reaching `playing`, first-frame time under 5 s locally, seek in VOD, and
  header forwarding (the 403 fixture).
- **Unit tests** with a `FakePlaybackEngine`: coordinator phase mapping,
  failure classification, candidate fallback on unsupported codec, request
  construction from Stremio hints, Xtream `.m3u8`-versus-`.ts` selection from
  `allowed_output_formats`, `#EXTVLCOPT` headers landing on the request.
- **UI tests**: Live channel plays (TS fixture), Discover MKV plays, the Play
  pill shows a visible spinner, the failure alert names a reason.
- **Hardware gate**: Anthony and OfficePlus per 4.6.
- **License check**: the CI script from 4.2 runs on every engine bump.

## 6. Out of scope

VLCKit or any second engine; torrent playback and the Stremio streaming
server; gateway remux; Top Shelf, Siri, and portal work; the UI/UX audit items
except the Play spinner and failure alert, which this design touches directly.

## 7. Files expected to change

New, in `Sources/OpenStreamApple/` following the existing flat layout:
`ApplePlaybackRequest.swift`, `ApplePlaybackEngine.swift`,
`AetherPlaybackEngine.swift`, `NativePlaybackEngine.swift`, `ApplePlayerHost.swift`,
`AppleTransportOverlay.swift`, `AppleThirdPartyNoticesView.swift`; plus
`scripts/apple-license-check.sh` at the repo root and a fixture generator under
`native/apple/Tests/Fixtures/`.

Changed: `Package.swift`, `Apps/OpenStreamApps.xcodeproj/project.pbxproj`
(embed phase), `ApplePlaybackCoordinator.swift`, `ApplePlaybackPreparer.swift`,
`ApplePlaybackRoute.swift`, `AppleStremioPlaybackResolver.swift`,
`AppleStremioPlaybackClient.swift` (hints), `AppleIPTV.swift`,
`AppleMediaSourceViews.swift`, `AppleDiscoverView.swift`,
`AppleStremioPlaybackView.swift`, `ApplePlayerControllers.swift`,
`ApplePlayerSession.swift`, `AppleSettingsStore.swift`, `AppleSettingsViews.swift`,
`AppleSMBRangeServer.swift`.

Removed after migration: `AppleProtectedHTTPPlaybackServer.swift`,
`AppleStremioPlatformPlayerHost` and the per-platform convenience initializers.
