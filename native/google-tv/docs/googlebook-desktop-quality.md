# Googlebook / desktop quality checklist (researched 2026-10-09)

OpenStream ships to Googlebook in the **mobile/large-screen AAB** (`native/android-xr`,
versionCode N+1). The TV AAB (`native/google-tv`) is leanback-only. Both compile the same
Kotlin sources from `native/android-xr/app/src/main/java`, so desktop work lands there.

## How the "Made for desktop" label works

On Googlebook, Play shows one of five labels: **Made for desktop** ("built for desktop with
specialized features and controls"), Optimized for desktop, Compatible with desktop, Better on
the website, and Built for mobile.

- Google assigns the labels itself. As of 2026-10-09 there is no Play Console opt-in or
  declaration. That comes from press reports (9to5Google 2026-10-09, Android Authority); Google
  has published no criteria.
- Google's own pages (the Googlebook developer hub and the Android Developers blog, 2026-09-22)
  point developers to the **adaptive app quality guidelines, Tier 1 "Desktop"**.
- Mapping Made for desktop to Tier 1 Desktop and Optimized to Tier 2 is an informed guess, not
  documented.

## Checklist

Tier 3 "Adaptive ready" (the baseline):

- T-Config_Orientation / T-Config_State / T-Config_Combinations: fill the window and keep
  playback, scroll position and input through resizes and rotation.
- T-Multi-Window_Functionality / T-Multi-Window_Focus: keep playing when another window has focus.
- T-Keyboard_Input: text input from a hardware keyboard. T-Mouse_Trackpad_Basic: click, select
  and scroll everywhere.

Tier 2 "Adaptive optimized":

- Responsive layouts (no stretched phone UI). Drawable_Focus: visible focus state.
- Keyboard_Navigation (Tab and arrows), Keyboard_Shortcuts (select, cut, copy, paste), and
  Keyboard_Media_Playback (Space play/pause, seek).
- Keyboard_Exit (Esc closes things), Context_Menus (right-click), Hover_States.

Tier 1 "Desktop" (the likely bar for Made for desktop):

- T-Scrollbar_Display, T-Hover_Parity, T-Desktop_Menus, T-Request_Fullscreen_Mode
  (`Activity#requestFullscreenMode`).
- T-Keyboard_Navigation and T-Keyboard_Parity (Ctrl shortcuts).
- T-Multitasking_PiP (interactive PiP), T-Multitasking_Split-Screen, T-Multi-Instance.
- T-Drag_Drop_Support, T-File_Handlers / T-File_Picker, T-Custom_Cursors, T-Offline_Support.
- Recommended: the Keyboard Shortcuts Helper (Meta+/ via `onProvideKeyboardShortcuts`).

Platform rules:

- On Android 16+ the system ignores orientation and resizability restrictions on sw≥600dp, and
  the opt-out ends at targetSdk 37.
- Manifest: `touchscreen required=false`, and no required hardware features.

## Sources

- Adaptive app quality: https://developer.android.com/docs/quality-guidelines/adaptive-app-quality
  - Tier 3: …/adaptive-app-quality/tier-3
  - Tier 2: …/tier-2
  - Tier 1 Desktop: …/experiences/desktop
- Googlebook hub: https://developer.android.com/develop/adaptive-apps/guides/googlebook/overview
- Desktop windowing: https://developer.android.com/develop/ui/compose/layouts/adaptive/support-desktop-windowing
- Keyboard Shortcuts Helper: https://developer.android.com/develop/ui/compose/touch-input/keyboard-input/keyboard-shortcuts-helper
- Android 16 behavior changes: https://developer.android.com/about/versions/16/behavior-changes-16
- Blog, 2026-09-22: https://android-developers.googleblog.com/2026/09/adaptive-development-scale-app-googlebook.html
- 9to5Google, 2026-10-09: https://9to5google.com/2026/10/09/googlebook-app-situation-messy/
- Android Authority: https://www.androidauthority.com/googlebook-play-store-app-classification-3719945/

Audit results and evidence: `verification-artifacts/googlebook-2026-10-09/REPORT.md`.
