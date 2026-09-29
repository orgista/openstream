<p align="center">
  <img alt="OpenStream icon" src="docs/assets/icon.png" width="96">
</p>

<h1 align="center">OpenStream</h1>

<h3 align="center">A media player for your NAS, add-ons, and headsets</h3>

<p align="center">
  <a href="#build-from-source">Build</a> ·
  <a href="docs/architecture/media-capability-matrix.md">Capability matrix</a> ·
  <a href="https://orgista.com">orgista.com</a>
</p>

<p align="center">
  <a href="native/android-xr"><img alt="Platform: Android" src="https://img.shields.io/badge/platform-Android%20%7C%20Android%20XR-1c1e20?style=flat-square"></a>
  <a href="native/apple"><img alt="Platform: Apple" src="https://img.shields.io/badge/playback%20core-macOS%20%7C%20tvOS%20%7C%20visionOS-1c1e20?style=flat-square"></a>
</p>

<p align="center">
  <img alt="OpenStream Discover screen on a 16:9 display" src="design/qa-automated/discover-desktop.png" width="720">
</p>

## Features

- Plays from SMB shares on your network, Stremio add-on streams, Jellyfin, and Google Drive connections.
- Direct play first. When a device cannot decode a format, the local gateway transcodes with ffmpeg, capped at the device's resolution and never upscaling.
- Reads real codec and display capabilities (HDR10, HDR10+, HLG, Dolby Vision, HEVC, AV1) and does not claim support from file metadata alone.
- Kids Mode: a rating cap, a title and word blocklist, and no way to turn it off from inside the app.
- Discover, Library, Live, Search, Activity, and Connections screens built for remote control focus, with pointer and keyboard input as well.
- Request handoff to Radarr, Sonarr, SABnzbd, and NZBGet.
- Immersive viewer for spatial media, using signed, one-time media handoffs.
- Redacted daily JSONL logs, so a test session can be replayed from one file.

## Kids Mode

First launch asks who is watching. Choosing Kids Mode walks a guardian through a rating cap (Little kids G/TV-Y, Big kids PG/TV-PG, or Teens PG-13/TV-14), an optional blocklist of titles or words, and an explicit confirmation that it cannot be undone.

- Titles above the cap, blocklist matches, and all unrated content are hidden from Discover, Library, Live, and Search, and refuse to play.
- Connections, activity, request handoff, and add-on management are hidden.
- There is no PIN, setting, or hidden exit. The lock lives in the app data. Editing or deleting the stored profile makes the app fall back to the strictest cap. The only reset is uninstalling OpenStream and setting it up again.

## Download

There are no tagged releases yet. Build from source below.

## Platforms

| Platform | Minimum | Notes |
| --- | --- | --- |
| Android, Android XR | Android 8.0 (API 26) | Native Kotlin and Jetpack Compose app on Media3. Direct SMB playback, Stremio add-ons, Kids Mode. See [native/android-xr](native/android-xr/README.md). |
| macOS, tvOS, visionOS | macOS 15, tvOS 18, visionOS 2 | Swift package with the playback and capability layer. The full Apple apps live in [orgista/openstream-apple](https://github.com/orgista/openstream-apple). |
| Web (tvOS-first UI) | Node and pnpm | React UI with a loopback gateway for NAS access and local transcoding. Run from source. |

## Build from source

Web UI and gateway (needs Node and pnpm):

```bash
pnpm install
pnpm dev     # starts Vite and the loopback gateway
pnpm test
```

`pnpm dev` prints a one-time secure launch URL. Open it to start a per-origin browser session. The gateway keeps connection credentials and LAN access out of browser state.

Android (needs JDK 17 and the Android SDK):

```bash
cd native/android-xr
gradle test assembleDebug
```

Apple playback core:

```bash
cd native/apple
swift test
```

| Command | Description |
| --- | --- |
| `pnpm build` | Typecheck and build the web UI |
| `pnpm gateway` | Run the gateway on its own (needs `OPENSTREAM_GATEWAY_TOKEN`) |
| `pnpm qa` | Audit every screen and the Kids Mode flow (see [development notes](docs/development.md)) |

## Security

OpenStream does not bypass DRM or extract protected media or keys. Private-network connections need explicit consent, credentials stay on the gateway side, and gateway records and media capabilities are bound to their owner.

## Documentation

- [Media capability matrix](docs/architecture/media-capability-matrix.md)
- [Functional audit](docs/audits/functional-audit-2026-07-16.md) and [design audit](docs/audits/design-audit-2026-07-16.md)
- [Development notes](docs/development.md): NAS and transcoding, logging, QA, design tooling
- Design renders and QA captures: [design/](design/)

## Contributing

Issues and pull requests are welcome. Run `pnpm test` and `pnpm qa` before opening a pull request.
