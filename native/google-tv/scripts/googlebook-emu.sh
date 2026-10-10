#!/usr/bin/env bash
# Drive the OpenStream Googlebook AVD (android-desktop 37.1) on Dev-Mini.
#   googlebook-emu.sh start            # boot under the shared buildlock (holds it until stop)
#   googlebook-emu.sh stop             # kill the emulator, which releases the lock
#   googlebook-emu.sh install          # install the mini's latest mobile debug APK
#   googlebook-emu.sh adb <args…>      # adb on the emulator
#   googlebook-emu.sh shot <name> [dir] # screenshot → dir (default verification-artifacts/googlebook-2026-10-09)
set -euo pipefail
here="$(cd "$(dirname "$0")/.." && pwd)"
AVD="${OPENSTREAM_AVD:-OpenStream_Googlebook}"
SERIAL=emulator-5580
ENV='export ANDROID_HOME=/Volumes/DevExt/android/sdk ANDROID_SDK_ROOT=/Volumes/DevExt/android/sdk ANDROID_AVD_HOME=/Volumes/DevExt/android/avd; B=/Volumes/DevExt/android/sdk'
ADB="\$B/platform-tools/adb -s $SERIAL"
cmd="${1:?usage: start|stop|install|adb|shot}"; shift || true
case "$cmd" in
  start)
    ssh dev-mini 'test -f /Volumes/DevExt/.devext-ok' </dev/null
    ssh dev-mini "$ENV; nohup ~/Developer/bin/buildlock.sh \$B/emulator/emulator -avd $AVD -port 5580 -no-snapshot -no-boot-anim -no-audio -memory 4096 >/tmp/openstream-emu.log 2>&1 &" </dev/null
    ssh dev-mini "$ENV; for i in \$(seq 1 180); do [ \"\$($ADB shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')\" = 1 ] && echo booted && exit 0; sleep 5; done; tail -20 /tmp/openstream-emu.log; exit 1" </dev/null
    ;;
  stop) ssh dev-mini "$ENV; $ADB emu kill >/dev/null 2>&1 || true; sleep 5; pkill -f 'avd $AVD' || true" </dev/null ;;
  install) ssh dev-mini "$ENV; $ADB install -r -g ~/Developer/openstream-android/build-mobile/outputs/apk/debug/app-debug.apk" </dev/null ;;
  adb) ssh dev-mini "$ENV; $ADB $(printf '%q ' "$@")" </dev/null ;;
  shot)
    dir="${2:-$here/verification-artifacts/googlebook-2026-10-09}"; mkdir -p "$dir"
    ssh dev-mini "$ENV; $ADB exec-out screencap -p" </dev/null > "$dir/$1.png"
    echo "$dir/$1.png"
    ;;
  *) echo "unknown $cmd"; exit 2 ;;
esac
