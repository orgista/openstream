# Development notes

## NAS folders and local transcoding

A NAS folder connection points the loopback gateway at a directory the machine already mounts (for example an SMB share under `/Volumes`). Files stream with HTTP Range support for instant seeking. When the device cannot direct-play a format, the gateway transcodes locally with ffmpeg, using VideoToolbox hardware encoders when available. Output is capped at the device's probed resolution and never upscaled. Playback falls back to the transcode route when a direct route fails, and the player offers a manual Transcode control. Stremio add-on streams proxied by the gateway can be transcoded the same way.

## Logging

The gateway writes redacted JSONL logs, one file per day, to `logs/` by default (set `OPENSTREAM_LOG_DIR` to override). They cover every request, connection test, transcode lifecycle, and the errors the browser ships to `POST /api/logs`. Uncaught client errors are captured automatically.

## Screens

Open the web UI with `?screen=` set to `discover`, `library`, `details`, `live`, `connections`, `search`, `activity`, `settings`, or `player`. The immersive viewer is at `/xr/viewer`.

## Running the dev server

`pnpm dev` starts Vite and the loopback gateway. Open the one-time secure launch URL printed in the terminal. It establishes a per-origin browser session, removes the launch capability from the address bar, and never creates a host-wide loopback cookie. Standalone gateway launches are for controlled integrations and require an explicit high-entropy `OPENSTREAM_GATEWAY_TOKEN` shared only with their trusted proxy.

If the project sits on a slow or network volume, point the Vite cache elsewhere with `OPENSTREAM_VITE_CACHE_DIR`.

The UI supports remote and keyboard focus, pointer input, and compact mobile and XR browser layouts. Signed XR media locators use one-time, owner-bound handoffs, and viewer navigation contains only an opaque fragment identifier.

## QA

`pnpm qa` audits every screen plus the onboarding and Kids Mode flow (rating filter, irreversibility, tamper fail-closed). It needs `CHROME_FOR_TESTING_PATH`.

```bash
node scripts/live-smoke.mjs "<secure launch url>" "<nas folder>"   # onboarding, NAS, direct play, transcode
```

## Design tooling

- Editable Figma file: https://www.figma.com/design/A8dE5NRzjGjwAMVSfdaeBW
- Local concept board and verified 1920x1080 renders: `design/`
- OpenPencil smoke test (`pnpm openpencil:smoke`) needs the OpenPencil desktop app open. It produces an editable `.fig`, a verified PNG, round-trip JSX, and a machine-readable report. Both OpenPencil workflows verify the listener's owner and pinned parent chain before sending MCP traffic, so upgrading OpenPencil means updating the pins in `scripts/openpencil-security.mjs`.
- `pnpm make:new -- "Design a tvOS media dashboard"` and `pnpm make -- "Make the focused card more obvious"` drive the conversational design agent in `design/make-agent/`.
