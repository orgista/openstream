# OpenStream on Googlebook: desktop e2e report (2026-10-09/10)

Round 2 (2026-10-10) closed the gaps round 1 left open: keyboard Down from the top bar,
hover tooltips, several windows, local files (open with, picker, drag and drop) and the
device smoke test with navigation on. Screenshots 44–58 are from round 2.

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
- **Round 2 additions:**
  - The repo's Big Sky clip was copied into the desktop user's Download folder and opened
    from the system Files app.
  - The drag and drop test was a real virtio-mouse press, move and release from Files onto the
    OpenStream window, with the two windows side by side (48).
  - The clip was deleted from the emulator afterwards.

## Badge checklist

| Item | Result | Evidence |
|---|---|---|
| Installs and launches on Android Desktop, targetSdk 37, `touchscreen required=false`, no required hardware | PASS | 01, 17; `android-device-smoke.sh` launch/shell/no-crash pass |
| Resizable freeform window, no restart or state loss on resize (T-Config_State) | PASS | 22–24: small, large and portrait resizes during playback; same PID, no new "app started", still PLAYING |
| No orientation lock; rotation keeps playback (T-Config_Orientation) | PASS | 39, 40; the desktop never gets the tablet landscape lock now |
| Large-screen layouts, nothing stretched (Responsive_adaptive_layouts) | PASS | 11, 31, 35, 40 |
| Multi-window: playback continues while another app has focus (T-Multi-Window_Focus) | PASS | 30: Chrome focused, OpenStream at 196 s and still PLAYING |
| Keyboard text input, Ctrl+A select-all, Tab between fields (T-Keyboard_Input, Keyboard_Shortcuts) | PASS | 07, 08, 19 |
| Keyboard navigation with Tab, arrows and Enter, plus visible focus (Keyboard_Navigation, Drawable_Focus) | PASS | 04, 18 (new focus ring), 42. Round 2: Down from the top bar now enters the screen below (44: brand → hero Details; on Library, brand → first card). Full keyboards only; TV remotes and D-pads are unchanged. |
| Space/K play-pause, ←/→ and J/L seek 10 s, M mute, media keys (Keyboard_Media_Playback) | PASS | 13; media-session state toggled PLAYING/PAUSED; position 0→11.4 s→3.2 s; mute in logcat |
| Esc closes menus, Details and the player, and leaves full screen first (Keyboard_Exit) | PASS after fix | 14 (before the fix), 27, 38; Esc clears the search query first (36). Round 2 fix: Esc on Discover no longer closes the window (it did after round 1); Back from Discover still exits. |
| Ctrl shortcuts: Ctrl+F search, Ctrl+1/2/3 tabs, Ctrl+, settings (T-Keyboard_Parity) | PASS | 09, 36, 43 |
| Keyboard Shortcuts Helper (Meta+/) | PASS | 37: "OpenStream" and "Player" groups. 55: now lists Ctrl+O "Open a video or audio file" and Ctrl+N "New window" (taken before the tooltip fix; the stuck "Search" tooltip behind it is the bug fixed in 7fd28e2) |
| Mouse click and scroll wheel, plus trackpad horizontal scroll on rails (T-Mouse_Trackpad_Basic) | PASS | 06, 41 |
| Hover states and hand cursor on title cards (Hover_States, T-Custom_Cursors) | PASS | 32 vs 33 |
| Right-click context menu, desktop style, opens at the pointer (Context_Menus, T-Desktop_Menus) | PASS | 34, 35 |
| Scrollbars while scrolling with mouse or trackpad (T-Scrollbar_Display) | PASS | 06 |
| Full screen via `requestFullscreenMode`: F key or chrome button (T-Request_Fullscreen_Mode) | PASS | 25, 26; freeform → full screen → freeform |
| Picture-in-picture with media controls: P key, "Mini player" button, auto-enter on leaving (T-Multitasking_PiP) | PASS | 15, 28, 29 (session play/pause, previous/next) |
| Media session for hardware media keys | PASS | `dumpsys media_session`: the OpenStream session is the media-button session |
| Offline support (T-Offline_Support) | PASS (existing) | Offline downloads were already in the app; not re-tested here |
| Stylus | N/A | No text-heavy or drawing surfaces; basic stylus taps work like touch |
| Multi-instance (T-Multi-Instance) | PASS | Ctrl+N (45), More > New window (54) and the system window menu's "New Window" / "Manage Windows", which the multi-instance property enables (58). 58: one window plays a local file while the other has focus (PLAYING at 12.6 s). Stores are process-wide SharedPreferences, so windows share settings; a change shows in the other window when it next refreshes. |
| File handler: Open with OpenStream (T-File_Handlers) | PASS | 46: Files right-click > Open with. The chooser listed OpenStream. 47: the clip plays. |
| File picker (T-File_Picker) | PASS | 51: Ctrl+O (or More > Open file…) opens the system picker filtered to video and audio. 52: the picked clip plays (media session PLAYING). |
| Drag and drop (T-Drag_Drop_Support) | PASS | 49: dragging from Files shows "Drop to play". 50: the dropped clip plays. Video and audio only; Kids Mode blocks local files. |
| Split-screen launch adjacent (T-Multitasking_Split-Screen) | PASS on desktop | New window uses `FLAG_ACTIVITY_LAUNCH_ADJACENT`; the desktop opens it as a second freeform window (45). Works side by side with other apps (48). Not tried in tablet split-screen. |
| Tooltips on icon buttons (T-Hover_Parity) | PASS | 53: hovering Search shows "Search" and it stays while the pointer rests there. It hides when the pointer leaves. 54: no stuck tooltip after passing over Search to open More. All 16 icon-only buttons are covered. The Media3 player controls set `tooltipText` from their labels, but that wasn't checked on the emulator. |

## Tests

- Round 1: 385 unit tests passed on the mobile build and 385 on the TV build.
- Round 2 (final build, commit 7fd28e2):
  - 387 unit tests pass on the mobile build and 387 on the TV build, with 0 failures. This
    includes the new `LocalMediaPolicyTest`.
  - The TV debug build assembles. The TV manifest is unchanged.
- `scripts/android-device-smoke.sh` with navigation on (`OPENSTREAM_SMOKE_NAVIGATE=1`):
  **PASS** for both users.
  - System user, empty Library (56): the heading shows with "No titles" and no explainer
    text.
  - Desktop user, populated Library (57).
  - Library now starts with a "Library" heading in every state. Round 1 failed here because
    the empty state had no heading. A populated Library would have failed too, since it
    had no heading either.
- No FATAL EXCEPTION or ANR in logcat. The log lines checked ("local media
  opened", "local media picked", "new window opened") contain no file names or paths.

## Seen in passing (out of scope)

- In the emulator, a YouTube channel source connects but its refresh fails ("YouTube channel
  refresh failed").
- On this image the emulator can't reach the host at 10.0.2.2; `adb reverse` works.
