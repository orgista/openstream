#!/bin/sh

set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
verify_root=$(mktemp -d /tmp/openstream-apple-verify.XXXXXX)
snapshot="$verify_root/apple"

# Xcode and SwiftPM read sources throughout a build. Copy only the package and
# app inputs so editors or another Codex task cannot invalidate an in-flight
# verification by touching the live working tree.
mkdir -p "$snapshot"
ditto "$repo_root/native/apple/Sources" "$snapshot/Sources"
ditto "$repo_root/native/apple/Tests" "$snapshot/Tests"
ditto "$repo_root/native/apple/Apps" "$snapshot/Apps"
cp "$repo_root/native/apple/Package.swift" "$snapshot/Package.swift"
if [ -f "$repo_root/native/apple/Package.resolved" ]; then
  cp "$repo_root/native/apple/Package.resolved" "$snapshot/Package.resolved"
fi

project="$snapshot/Apps/OpenStreamApps.xcodeproj"

echo "Apple verification artifacts: $verify_root"

swift test \
  --package-path "$snapshot" \
  --scratch-path "$verify_root/swiftpm" \
  --jobs 1

build_target() {
  target=$1
  sdk=$2
  slug=$3

  xcodebuild \
    -quiet \
    -project "$project" \
    -target "$target" \
    -sdk "$sdk" \
    -configuration Debug \
    SYMROOT="$verify_root/$slug/products" \
    OBJROOT="$verify_root/$slug/objects" \
    CODE_SIGNING_ALLOWED=NO \
    build
}

build_target "OpenStream iOS" iphonesimulator ios
build_target "OpenStream tvOS" appletvsimulator tvos
build_target "OpenStream visionOS" xrsimulator visionos
build_target "OpenStream macOS" macosx macos

echo "Apple package tests and all four app targets passed."
