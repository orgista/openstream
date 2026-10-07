#!/bin/zsh
# Build the iOS app with add-ons (TestFlight-equivalent Release), sign it Ad Hoc for the iPhone 16e test device and
# install it. Runs ON Dev-Mini — call it from the Studio through scripts/mini.sh:
#   scripts/mini.sh 'zsh scripts/release/devplus-install.sh [build-number]'
# Needs the "OpenStream AdHoc DevPlus …" profiles installed and the build keychain (see workspace AGENTS.md).
set -euo pipefail
BUILD=${1:-1}
DEVICE=${DEVPLUS_UDID:-00008140-000809A82E89801C}
OUT=$HOME/Developer/openstream-build/devplus
ARCHIVE=$OUT/OpenStream-iOS-devplus.xcarchive
security unlock-keychain -p "$(cat ~/Developer/.build-keychain-pass)" ~/Library/Keychains/build.keychain-db
rm -rf "$ARCHIVE" "$OUT/export"; mkdir -p "$OUT"
xcodebuild -project Apps/OpenStreamApps.xcodeproj -scheme "OpenStream iOS" -configuration Release \
  -destination 'generic/platform=iOS' -archivePath "$ARCHIVE" \
  -derivedDataPath ~/Developer/openstream-build/dd-ios-release \
  CURRENT_PROJECT_VERSION=$BUILD \
  SWIFT_ACTIVE_COMPILATION_CONDITIONS='$(inherited) OPENSTREAM_ADDONS' \
  archive 2>&1 | grep -E "error:|ARCHIVE (SUCCEEDED|FAILED)|Signing Identity" | tail -20
[[ -d $ARCHIVE ]] || { print -u2 "archive failed"; exit 1; }
xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportPath "$OUT/export" \
  -exportOptionsPlist scripts/release/ExportOptions-ios-adhoc-devplus.plist 2>&1 | grep -E "error|EXPORT (SUCCEEDED|FAILED)" | tail -10
IPA=$(ls "$OUT"/export/*.ipa | head -1)
xcrun devicectl device install app --device "$DEVICE" "$IPA" 2>&1 | tail -3
print -r -- "installed $IPA on $DEVICE"
