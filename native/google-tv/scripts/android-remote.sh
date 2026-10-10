#!/usr/bin/env bash
# Build/test the OpenStream Android modules on Dev-Mini (never on the Studio).
#   native/google-tv/scripts/android-remote.sh tv     :app:assembleDebug :app:testDebugUnitTest
#   native/google-tv/scripts/android-remote.sh mobile :app:assembleDebug
#   native/google-tv/scripts/android-remote.sh clean  # delete the mini's build outputs
# Copies native/google-tv + native/android-xr (the TV module compiles the
# android-xr sources) over SSH, then runs Gradle under the mini's shared
# buildlock. SDK, Gradle and its cache live on /Volumes/DevExt; build dirs stay
# on the internal disk under ~/Developer/openstream-android/ (clean when done).
set -euo pipefail
module="${1:?usage: android-remote.sh tv|mobile|clean [gradle tasks…]}"; shift || true
native="$(cd "$(dirname "$0")/../.." && pwd)"
R='~/Developer/openstream-android'
ssh dev-mini 'test -f /Volumes/DevExt/.devext-ok' </dev/null || { echo "DevExt not mounted on dev-mini"; exit 2; }
if [ "$module" = clean ]; then
  ssh dev-mini "rm -rf $R/build-tv $R/build-mobile $R/src/*/.gradle $R/src/*/build" </dev/null
  exit 0
fi
case "$module" in tv) dir=google-tv; envvar=OPENSTREAM_GOOGLE_TV_BUILD_DIR ;; mobile) dir=android-xr; envvar=OPENSTREAM_ANDROID_BUILD_DIR ;; *) echo "unknown module $module"; exit 2 ;; esac
ssh dev-mini "mkdir -p $R/src && rm -rf $R/src/google-tv/app/src $R/src/android-xr/app/src" </dev/null
COPYFILE_DISABLE=1 tar -C "$native" --exclude build --exclude .gradle --exclude dist --exclude verification-artifacts \
  -cf - google-tv android-xr | ssh dev-mini "tar -xf - -C $R/src"
ssh dev-mini "export JAVA_HOME=/opt/homebrew/opt/openjdk@21 ANDROID_HOME=/Volumes/DevExt/android/sdk ANDROID_SDK_ROOT=/Volumes/DevExt/android/sdk \
  GRADLE_USER_HOME=/Volumes/DevExt/openstream-android/gradle-home $envvar=\$HOME/Developer/openstream-android/build-$module
  cd $R/src/$dir && ~/Developer/bin/buildlock.sh /Volumes/DevExt/openstream-android/tools/gradle-9.8.0/bin/gradle --console=plain -q $*" </dev/null
