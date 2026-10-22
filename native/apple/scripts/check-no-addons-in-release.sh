#!/bin/bash
# OpenStream has no add-ons. This gate fails when anything add-on shaped is in the tree or in a built product.
#
#   scripts/check-no-addons-in-release.sh <product.app|product.xcarchive> [more…]
#       scans the given products (any platform, any configuration);
#   scripts/check-no-addons-in-release.sh --build
#       builds iOS, tvOS, visionOS and macOS in Debug and Release (simulator/generic, unsigned) and scans all eight.
#
# Runs on Dev-Mini (scripts/mini.sh). Prints the word and the file it was found in, never the surrounding text.
set -euo pipefail
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
dd_root="${OPENSTREAM_CHECK_DD:-$HOME/Developer/openstream-build}"
# Words that must never ship (case-insensitive). Keep in sync with the app-store-review-hardening skill.
words=(stremio strem.io torrentio torrent debrid real-debrid alldebrid premiumize torbox 'magnet:' infohash
       cinemeta metahub 'add-on' addon 'manifest.json' openstream_addons)
pattern="$(IFS='|'; echo "${words[*]}" | sed 's/\./[.]/g')"
failed=0

# 1. Nothing in the sources or the project can turn the old compilation condition back on.
if grep -rIl --include='*.swift' --include='*.pbxproj' --include='*.xcconfig' --include='Package.swift' \
        OPENSTREAM_ADDONS "$repo_root/Sources" "$repo_root/Apps" "$repo_root/Tests" "$repo_root/Package.swift"; then
    echo 'FAIL: OPENSTREAM_ADDONS is still referenced (files above).'
    failed=1
fi

scan() {
    local product="$1" hits=0 file word
    [[ -e "$product" ]] || { echo "FAIL: $product does not exist."; failed=1; return; }
    while IFS= read -r -d '' file; do
        local rel="${file#"$product"/}"
        for word in "${words[@]}"; do
            if [[ "$(printf '%s' "$rel" | tr '[:upper:]' '[:lower:]')" == *"$word"* ]]; then
                echo "  $word in file name $rel"; hits=$((hits + 1))
            fi
        done
        local found
        found="$(LC_ALL=C strings -a -n 4 "$file" 2>/dev/null | LC_ALL=C grep -Eio "$pattern" | tr '[:upper:]' '[:lower:]' | sort | uniq -c || true)"
        if [[ -n "$found" ]]; then
            while read -r count word; do echo "  $word ×$count in $rel"; done <<< "$found"
            hits=$((hits + 1))
        fi
    done < <(find "$product" -type f ! -name '_CodeSignature' ! -name 'CodeResources' -print0)
    if (( hits > 0 )); then
        echo "FAIL: $(basename "$product") ships add-on words (listed above)."
        failed=1
    else
        echo "PASS: $(basename "$product") has none of: ${words[*]}"
    fi
    if [[ "$product" == *.xcarchive || "$product" == *Release* ]]; then
        bash "$repo_root/scripts/sdk-floor-check.sh" "$product" >/dev/null || { echo "FAIL: SDK floors for $(basename "$product")."; failed=1; }
    fi
}

build_and_scan() {
    local platform lane destination config scheme products app log
    for platform in iOS tvOS visionOS macOS; do
        case "$platform" in
            iOS) lane=ios; destination='generic/platform=iOS Simulator'; products=iphonesimulator ;;
            tvOS) lane=tvos; destination='generic/platform=tvOS Simulator'; products=appletvsimulator ;;
            visionOS) lane=visionos; destination='generic/platform=visionOS Simulator'; products=xrsimulator ;;
            macOS) lane=macos; destination='generic/platform=macOS'; products='' ;;
        esac
        scheme="OpenStream $platform"
        for config in Debug Release; do
            log="/tmp/openstream-no-addons-$lane-$config.log"
            xcodebuild -project "$repo_root/Apps/OpenStreamApps.xcodeproj" -scheme "$scheme" -configuration "$config" \
                -destination "$destination" -derivedDataPath "$dd_root/DerivedData-deploy-$lane" \
                CODE_SIGNING_ALLOWED=NO build > "$log" 2>&1 || { echo "FAIL: $platform $config build; see $log"; failed=1; continue; }
            if grep -Eq -- '-D[[:space:]]*OPENSTREAM_ADDONS' "$log"; then
                echo "FAIL: $platform $config compiled with OPENSTREAM_ADDONS."; failed=1
            fi
            app="$(find "$dd_root/DerivedData-deploy-$lane/Build/Products/$config${products:+-$products}" -maxdepth 1 -name '*.app' -type d | head -1)"
            [[ -n "$app" ]] || { echo "FAIL: no $platform $config app"; failed=1; continue; }
            echo "$platform $config:"
            scan "$app"
        done
    done
}

if [[ "${1:-}" == --build ]]; then
    build_and_scan
else
    (( $# )) || { echo "usage: $0 --build | <product.app|product.xcarchive>…"; exit 2; }
    for product in "$@"; do scan "$product"; done
fi
exit "$failed"
