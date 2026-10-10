# OpenStream on Googlebook: desktop e2e report (2026-10-09/10)

## Setup

- **Build:** mobile/large-screen debug APK (`native/android-xr`, the AAB that serves
  Googlebook), built on Dev-Mini with `native/google-tv/scripts/android-remote.sh`.
- **Emulator:** AVD `OpenStream_Googlebook` on Dev-Mini (android-desktop 37.1 arm64,
  1920×1080 at 160 dpi, hardware keyboard), driven by `scripts/googlebook-emu.sh` under the
  shared buildlock.
- **Source fixture:** an M3U playlist served from the mini's loopback and reached over
  `adb reverse`.
  - Its channels are the repo's `test-media` clips: Big Sky, looped to 4 minutes with
    `ffmpeg -c copy` for the resize and PiP tests, and Glacier Run.
  - The public Cinemeta catalog add-on (no account, no secrets) supplied poster cards for the
    hover and right-click tests.
  - No owner sources or secrets were used.
- **Two sessions:**
  - Screenshots 01–15 come from the image's system user, which runs apps full screen (the
    desktop session had locked).
  - Screenshots 17–43 come from the signed-in desktop user, with OpenStream in a freeform window.
- **Input:** mouse hover and right-click were sent as real virtio-mouse events (`sendevent` as
  root). Taps, wheel and keys went through `adb input`.

## Badge checklist

| Item | Result | Evidence |
|---|---|---|
| Installs and launches on Android Desktop, targetSdk 37, `touchscreen required=false`, no required hardware | PASS | 01, 17; `android-device-smoke.sh` launch/shell/no-crash pass |
| Resizable freeform window, no restart or state loss on resize (T-Config_State) | PASS | 22–24: small, large and portrait resizes during playback; same PID, no new "app started", still PLAYING |
| No orientation lock; rotation keeps playback (T-Config_Orientation) | PASS | 39, 40; the desktop never gets the tablet landscape lock now |
| Large-screen layouts, nothing stretched (Responsive_adaptive_layouts) | PASS | 11, 31, 35, 40 |
| Multi-window: playback continues while another app has focus (T-Multi-Window_Focus) | PASS | 30: Chrome focused, OpenStream at 196 s and still PLAYING |
| Keyboard text input, Ctrl+A select-all, Tab between fields (T-Keyboard_Input, Keyboard_Shortcuts) | PASS | 07, 08, 19 |
| Keyboard navigation with Tab, arrows and Enter, plus visible focus (Keyboard_Navigation, Drawable_Focus) | PASS, one limit | 04, 18 (new focus ring), 42. Arrows move through the hero and rails. Down from the top-nav brand doesn't enter content (Tab does); this is shared TV/mobile code that predates this work. |
| Space/K play-pause, ←/→ and J/L seek 10 s, M mute, media keys (Keyboard_Media_Playback) | PASS | 13; media-session state toggled PLAYING/PAUSED; position 0→11.4 s→3.2 s; mute in logcat |
| Esc closes menus, Details and the player, and leaves full screen first (Keyboard_Exit) | PASS after fix | 14 (before the fix), 27, 38; Esc clears the search query first (36) |
| Ctrl shortcuts: Ctrl+F search, Ctrl+1/2/3 tabs, Ctrl+, settings (T-Keyboard_Parity) | PASS | 09, 36, 43 |
| Keyboard Shortcuts Helper (Meta+/) | PASS | 37: "OpenStream" and "Player" groups |
| Mouse click and scroll wheel, plus trackpad horizontal scroll on rails (T-Mouse_Trackpad_Basic) | PASS | 06, 41 |
| Hover states and hand cursor on title cards (Hover_States, T-Custom_Cursors) | PASS | 32 vs 33 |
| Right-click context menu, desktop style, opens at the pointer (Context_Menus, T-Desktop_Menus) | PASS | 34, 35 |
| Scrollbars while scrolling with mouse or trackpad (T-Scrollbar_Display) | PASS | 06 |
| Full screen via `requestFullscreenMode`: F key or chrome button (T-Request_Fullscreen_Mode) | PASS | 25, 26; freeform → full screen → freeform |
| Picture-in-picture with media controls: P key, "Mini player" button, auto-enter on leaving (T-Multitasking_PiP) | PASS | 15, 28, 29 (session play/pause, previous/next) |
| Media session for hardware media keys | PASS | `dumpsys media_session`: the OpenStream session is the media-button session |
| Offline support (T-Offline_Support) | PASS (existing) | Offline downloads were already in the app; not re-tested here |
| Stylus | N/A | No text-heavy or drawing surfaces; basic stylus taps work like touch |
| Multi-instance (T-Multi-Instance) | NOT DONE | Single-activity app with shared stores; a second window could conflict |
| Drag and drop / file handlers / file picker | NOT DONE | No local-file playback path yet (sources are NAS, add-ons and IPTV) |
| Split-screen launch adjacent (T-Multitasking_Split-Screen) | NOT DONE | Not applicable: no secondary content to open beside the main window |
| Tooltips on icon buttons (T-Hover_Parity) | NOT DONE | Icon buttons have content descriptions but no hover tooltips |

## Tests

- Unit tests: 385 pass on the mobile build and 385 on the TV build. This includes the new
  `PlayerKeyboardPolicyTest` and the desktop case in `DevicePresentationPolicyTest`.
- TV debug build assembles.
- `scripts/android-device-smoke.sh` on the emulator:
  - With `OPENSTREAM_SMOKE_NAVIGATE=0`: PASS (launch, shell, no crash or ANR).
  - With navigation on: FAIL at "Library screen did not render". With no NAS library, Library
    shows its "No titles" empty state, which has no "Library" heading for the script's check.
    That screen wasn't changed here.

## Seen in passing (out of scope)

- In the emulator, a YouTube channel source connects but its refresh fails ("YouTube channel
  refresh failed").
- On this image the emulator can't reach the host at 10.0.2.2; `adb reverse` works.
