#!/bin/sh
set -eu

adb_bin=${ADB:-adb}
package_name=${OPENSTREAM_ANDROID_PACKAGE:-com.orgista.openstream}
activity_name=${OPENSTREAM_ANDROID_ACTIVITY:-.NativeAppActivity}
navigate=${OPENSTREAM_SMOKE_NAVIGATE:-1}
remote_ui="/data/local/tmp/openstream-device-smoke-$$.xml"
local_ui=$(mktemp "${TMPDIR:-/tmp}/openstream-device-smoke.XXXXXX")
woke_device=0

cleanup() {
  "$adb_bin" shell rm -f "$remote_ui" >/dev/null 2>&1 || true
  rm -f "$local_ui"
  if [ "$woke_device" -eq 1 ]; then
    "$adb_bin" shell input keyevent KEYCODE_SLEEP >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT HUP INT TERM

fail() {
  printf 'Android device smoke failed: %s\n' "$*" >&2
  exit 1
}

if [ -z "${ANDROID_SERIAL:-}" ]; then
  device_count=$("$adb_bin" devices | awk 'NR > 1 && $2 == "device" { count++ } END { print count + 0 }')
  [ "$device_count" -eq 1 ] || fail "expected exactly one ready device; set ANDROID_SERIAL when more are attached"
fi
[ "$("$adb_bin" get-state 2>/dev/null || true)" = "device" ] || fail "ADB device is not ready"

package_info=$("$adb_bin" shell dumpsys package "$package_name" 2>/dev/null || true)
printf '%s' "$package_info" | grep -Fq 'installed=true' || fail "$package_name is not installed"
printf '%s' "$package_info" | grep -Fq 'targetSdk=37' || fail "$package_name is not the API 37 build"
version_name=$(printf '%s\n' "$package_info" | sed -n 's/^[[:space:]]*versionName=//p' | head -1 | tr -d '\r')
[ -n "$version_name" ] || fail "installed versionName is unavailable"

if ! "$adb_bin" shell dumpsys power | grep -Fq 'mWakefulness=Awake'; then
  "$adb_bin" shell input keyevent KEYCODE_WAKEUP >/dev/null
  woke_device=1
fi

component="$package_name/$activity_name"
launch_output=$("$adb_bin" shell am start -W -n "$component" 2>&1 || true)
printf '%s' "$launch_output" | grep -Fq 'Status: ok' || fail "launcher activity did not start successfully"
sleep 1

dump_ui() {
  "$adb_bin" shell uiautomator dump "$remote_ui" >/dev/null || fail "UI hierarchy capture failed"
  "$adb_bin" exec-out cat "$remote_ui" > "$local_ui" || fail "UI hierarchy transfer failed"
  grep -Fq "package=\"$package_name\"" "$local_ui" || fail "OpenStream is not the visible package"
}

assert_process() {
  pids=$("$adb_bin" shell pidof "$package_name" 2>/dev/null | tr -d '\r')
  [ -n "$pids" ] || fail "OpenStream process stopped during the smoke test"
}

assert_shell() {
  attempts=0
  while [ "$attempts" -lt 8 ]; do
    dump_ui
    if grep -Fq 'text="OpenStream"' "$local_ui" &&
       grep -Fq 'text="Discover"' "$local_ui" &&
       grep -Fq 'text="Library"' "$local_ui" &&
       grep -Fq 'content-desc="Search"' "$local_ui" &&
       grep -Fq 'content-desc="More options"' "$local_ui"; then
      assert_process
      return
    fi
    assert_process
    attempts=$((attempts + 1))
    sleep 1
  done
  fail "app shell did not appear after the native launch sequence"
}

tap_text() {
  label=$1
  bounds=$(grep -o "text=\"$label\"[^>]*bounds=\"[^\"]*\"" "$local_ui" |
    head -1 |
    sed -E 's/.*bounds="([^"]+)".*/\1/' || true)
  coordinates=$(printf '%s' "$bounds" | sed -E 's/^\[([0-9]+),([0-9]+)\]\[([0-9]+),([0-9]+)\]$/\1 \2 \3 \4/')
  set -- $coordinates
  [ "$#" -eq 4 ] || fail "could not locate the $label navigation target"
  x=$((($1 + $3) / 2))
  y=$((($2 + $4) / 2))
  "$adb_bin" shell input tap "$x" "$y" >/dev/null
  sleep 1
}

assert_shell
if [ "$navigate" = "1" ]; then
  tap_text Discover
  dump_ui
  discover_ready=0
  if grep -Fq 'text="Play"' "$local_ui" && grep -Fq 'text="Details"' "$local_ui"; then
    discover_ready=1
  elif grep -Fq 'text="No downloads"' "$local_ui" ||
       grep -Fq 'text="Nothing here yet"' "$local_ui"; then
    discover_ready=1
  fi
  if [ "$discover_ready" -ne 1 ]; then
    fail "Discover did not render a valid online or offline state"
  fi
  tap_text Library
  dump_ui
  library_labels=$(grep -o 'text="Library"' "$local_ui" | wc -l | tr -d ' ')
  [ "$library_labels" -ge 2 ] || fail "Library screen did not render"
  tap_text Discover
  assert_shell
fi

pids=$("$adb_bin" shell pidof "$package_name" | tr -d '\r')
set -- $pids
pid=$1
app_logs=$("$adb_bin" logcat -d --pid="$pid" -t 250 2>/dev/null || true)
system_logs=$("$adb_bin" logcat -d -t 500 2>/dev/null || true)
if printf '%s' "$app_logs" | grep -Fq 'FATAL EXCEPTION' ||
   printf '%s' "$system_logs" | grep -Eq "ANR in $package_name|Process: $package_name"; then
  fail "recent process logs contain a crash or ANR"
fi

model=$("$adb_bin" shell getprop ro.product.model | tr -d '\r')
lock_state=$("$adb_bin" shell dumpsys activity activities | sed -n 's/^[[:space:]]*mLockTaskModeState=//p' | head -1 | tr -d '\r')
printf 'Android device smoke passed: model=%s package=%s version=%s navigation=%s lockTask=%s\n' \
  "$model" "$package_name" "$version_name" "$navigate" "${lock_state:-unknown}"
