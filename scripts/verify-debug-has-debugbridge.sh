#!/usr/bin/env bash
# Purpose: Companion to scripts/verify-release-no-debugbridge.sh.
# Asserts that a Debug build's Info.plist contains the vreader-debug
# URL scheme. Exits 0 only if CFBundleURLTypes contains "vreader-debug"
# (so external callers can reach the DebugBridge handler via
# `simctl openurl vreader-debug://...`).
#
# This is the regression check for bug #121.
#
# Usage:
#   scripts/verify-debug-has-debugbridge.sh [path/to/vreader.app]
#
# If no path is given, falls back to the standard xcodebuild-CLI Debug
# build location.

set -euo pipefail

APP_PATH="${1:-}"

if [[ -z "$APP_PATH" ]]; then
    # Discover the most recent Debug build under the standard
    # DerivedData location.
    # Exclude Xcode's Index.noindex builds (used for indexing, no Info.plist).
    # `find … -print` order is not by mtime; sort candidates by mtime so we
    # pick the actual most-recent build instead of an arbitrary stale one.
    APP_PATH=$(find ~/Library/Developer/Xcode/DerivedData -type d \
        -path "*Build/Products/Debug-iphonesimulator/vreader.app" \
        -not -path "*/Index.noindex/*" \
        -print 2>/dev/null \
        | while read -r p; do
            stat -f "%m %N" "$p"
          done \
        | sort -rn \
        | head -1 \
        | cut -d' ' -f2-)
fi

if [[ -z "$APP_PATH" || ! -d "$APP_PATH" ]]; then
    echo "FAIL: Debug app bundle not found at \"$APP_PATH\"" >&2
    echo "Build first with:" >&2
    echo "  xcodebuild build -configuration Debug \\" >&2
    echo "    -project vreader.xcodeproj -scheme vreader \\" >&2
    echo "    -destination 'platform=iOS Simulator,name=iPhone 17 Pro'" >&2
    exit 2
fi

INFO_PLIST="$APP_PATH/Info.plist"

if [[ ! -f "$INFO_PLIST" ]]; then
    echo "FAIL: Info.plist missing inside $APP_PATH" >&2
    exit 2
fi

# Use plutil to convert Info.plist to JSON and check the URL types
# array contains the vreader-debug scheme.
URL_SCHEMES=$(plutil -convert json -o - "$INFO_PLIST" \
    | python3 -c "
import json, sys
d = json.load(sys.stdin)
types = d.get('CFBundleURLTypes', [])
schemes = []
for t in types:
    schemes.extend(t.get('CFBundleURLSchemes', []) or [])
print(','.join(schemes))
")

if [[ ",$URL_SCHEMES," == *",vreader-debug,"* ]]; then
    echo "OK: vreader-debug URL scheme registered in Debug Info.plist"
    echo "    schemes: $URL_SCHEMES"
    echo "PASS: DebugBridge URL scheme is reachable from outside the app"
    exit 0
else
    echo "FAIL: vreader-debug URL scheme NOT registered in Debug Info.plist" >&2
    echo "    found schemes: ${URL_SCHEMES:-(none)}" >&2
    echo "" >&2
    echo "Bug #121 regression — see project.yml postCompileScripts" >&2
    echo "\"Inject DebugBridge URL types (DEBUG only)\" and the source" >&2
    echo "vreader/SupportingFiles/DebugBridge.plist" >&2
    exit 1
fi
