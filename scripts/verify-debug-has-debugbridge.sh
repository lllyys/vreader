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

if [[ ",$URL_SCHEMES," != *",vreader-debug,"* ]]; then
    echo "FAIL: vreader-debug URL scheme NOT registered in Debug Info.plist" >&2
    echo "    found schemes: ${URL_SCHEMES:-(none)}" >&2
    echo "" >&2
    echo "Bug #121 regression — see project.yml postCompileScripts" >&2
    echo "\"Inject DebugBridge URL types (DEBUG only)\" and the source" >&2
    echo "vreader/SupportingFiles/DebugBridge.plist" >&2
    exit 1
fi
echo "OK: vreader-debug URL scheme registered in Debug Info.plist"
echo "    schemes: $URL_SCHEMES"

# Bug #123 regression check: if a simulator is booted, also verify that
# the LaunchServices scheme-approval entry is in place. Without it, the
# first `simctl openurl` call hangs on iOS's "Open in 'vreader'?" alert.
# This check is best-effort — no booted simulator means we can only
# verify the bundle-level wiring (bug #121's gate), not the runtime
# delivery path (bug #123's gate).
BOOTED_UDIDS="$(xcrun simctl list devices booted -j 2>/dev/null \
    | python3 -c '
import json, sys
try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(0)
for runtime, devices in data.get("devices", {}).items():
    for d in devices:
        if d.get("state") == "Booted":
            print(d.get("udid", ""))
' 2>/dev/null || true)"

if [[ -z "$BOOTED_UDIDS" ]]; then
    echo "NOTE: no booted simulator; skipping LaunchServices approval check (bug #123)"
    echo "PASS: DebugBridge URL scheme is registered in the bundle (bug #121 gate)"
    exit 0
fi

APPROVAL_KEY="com.apple.CoreSimulator.CoreSimulatorBridge-->vreader-debug"
APPROVAL_FAIL=0
for UDID in $BOOTED_UDIDS; do
    PREF="$HOME/Library/Developer/CoreSimulator/Devices/${UDID}/data/Library/Preferences/com.apple.launchservices.schemeapproval.plist"
    if [[ ! -f "$PREF" ]]; then
        echo "WARN: ${UDID:0:8}…: schemeapproval.plist missing — first openurl will hang on iOS approval prompt" >&2
        echo "      Run: scripts/grant-debug-scheme-approval.sh ${UDID}" >&2
        APPROVAL_FAIL=1
        continue
    fi
    APPROVED="$(/usr/libexec/PlistBuddy -c "Print :${APPROVAL_KEY}" "$PREF" 2>/dev/null || true)"
    if [[ "$APPROVED" != "com.vreader.app" ]]; then
        echo "WARN: ${UDID:0:8}…: vreader-debug not granted in LaunchServices (bug #123)" >&2
        echo "      Run: scripts/grant-debug-scheme-approval.sh ${UDID}" >&2
        APPROVAL_FAIL=1
    else
        echo "OK: ${UDID:0:8}…: vreader-debug pre-granted in LaunchServices"
    fi
done

if [[ "$APPROVAL_FAIL" -eq 1 ]]; then
    echo "PARTIAL: bundle wiring OK (bug #121); approval missing on at least one booted simulator (bug #123)" >&2
    exit 1
fi

echo "PASS: DebugBridge URL scheme is registered (bug #121) and pre-approved on all booted simulators (bug #123)"
exit 0
