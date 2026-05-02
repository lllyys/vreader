#!/usr/bin/env bash
# Purpose: Acceptance gate for feature #44 — verify the DebugBridge has zero
# release surface. Run after a Release build; exits 0 only if neither the
# vreader-debug URL scheme nor any DebugBridge symbol/string leaks into the
# shipped binary or Info.plist.
#
# Usage:
#   scripts/verify-release-no-debugbridge.sh [path/to/vreader.app]
#
# If no path is given, falls back to a default DerivedData location used by
# the local Release build invocation in dev-docs/debug-bridge.md.

set -euo pipefail

APP_PATH="${1:-/tmp/vreader-release-build/Build/Products/Release-iphonesimulator/vreader.app}"

if [[ ! -d "$APP_PATH" ]]; then
    echo "FAIL: app bundle not found at $APP_PATH" >&2
    echo "Build first: xcodebuild build -configuration Release -derivedDataPath /tmp/vreader-release-build" >&2
    exit 2
fi

INFO_PLIST="$APP_PATH/Info.plist"
BIN_PATH="$APP_PATH/vreader"

if [[ ! -f "$INFO_PLIST" ]]; then
    echo "FAIL: Info.plist missing inside $APP_PATH" >&2
    exit 2
fi

if [[ ! -f "$BIN_PATH" ]]; then
    echo "FAIL: binary missing inside $APP_PATH" >&2
    exit 2
fi

FAIL=0

# Pattern matched against bundle file names, file contents, and binary strings.
# Broad enough to catch new DebugBridge files added in the future
# (Debug<anything>) and Swift mangled symbols (which use various separators
# around qualified names), but narrow enough that generic words like "Bridge"
# alone won't trip the gate.
PATTERN='vreader-debug|DebugBridge|DebugCommand|DebugFixture|DebugSnapshot|LoggingDebugBridgeContext|DebugBridgeProvider|RealDebugBridgeContext|DebugBridgeContextError'

# 1. Info.plist must not declare the vreader-debug URL scheme
if plutil -p "$INFO_PLIST" | grep -q "vreader-debug"; then
    echo "FAIL: Info.plist contains vreader-debug URL scheme" >&2
    FAIL=1
else
    echo "OK: Info.plist has no vreader-debug entry"
fi

# 2a. No DebugFixtures directory or fixture file should be present anywhere
# in the .app bundle. Catches accidental copying via build phase changes.
# We check both: (a) the directory itself, and (b) every fixture filename
# at the bundle root (Xcode flat-copies resources, so the dir wouldn't exist
# if the EXCLUDED glob took effect — but the file might still leak by name).
LEAKED_FIXTURES=$(find "$APP_PATH" -type d -name "DebugFixtures" -o -path "*/DebugFixtures/*" 2>/dev/null | head -10)
if [[ -n "$LEAKED_FIXTURES" ]]; then
    echo "FAIL: bundle contains DebugFixtures content:" >&2
    echo "$LEAKED_FIXTURES" >&2
    FAIL=1
else
    echo "OK: no DebugFixtures directory in bundle"
fi

# 2b. Reject every fixture file by name. Driven by the actual contents of
# vreader/Resources/DebugFixtures/, so adding a new fixture is automatically
# checked without editing this script.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FIXTURES_DIR="$SCRIPT_DIR/../vreader/Resources/DebugFixtures"
if [[ -d "$FIXTURES_DIR" ]]; then
    LEAKED_FIXTURE_FILES=()
    while IFS= read -r fixture; do
        name=$(basename "$fixture")
        if find "$APP_PATH" -name "$name" -type f 2>/dev/null | grep -q .; then
            LEAKED_FIXTURE_FILES+=("$name")
        fi
    done < <(find "$FIXTURES_DIR" -type f)
    if [[ "${#LEAKED_FIXTURE_FILES[@]}" -gt 0 ]]; then
        echo "FAIL: catalog fixture files found in bundle:" >&2
        printf '  %s\n' "${LEAKED_FIXTURE_FILES[@]}" >&2
        FAIL=1
    else
        echo "OK: no catalog fixture filenames in bundle"
    fi
fi

# 2b. No file in the .app bundle should be named with DebugBridge identifiers
LEAKED_NAMES=$(find "$APP_PATH" -type f \( -name "*DebugBridge*" -o -name "*vreader-debug*" -o -name "DebugCommand*" -o -name "DebugSnapshot*" -o -name "DebugFixture*" \) | head -10)
if [[ -n "$LEAKED_NAMES" ]]; then
    echo "FAIL: bundle contains DebugBridge-named files:" >&2
    echo "$LEAKED_NAMES" >&2
    FAIL=1
else
    echo "OK: no DebugBridge-named files in bundle"
fi

# 3. Resource files (plists, text resources, anything not the main binary) must
# not embed the pattern. Bundled binary plists (Info.plist) are read via plutil;
# everything else is scanned with grep -a (treat binary as text — adequate for
# short identifiers we'd see if a debug-only file got copied into the bundle).
RESOURCE_HIT_FILES=()
while IFS= read -r f; do
    if [[ "$f" == "$BIN_PATH" ]]; then
        continue  # binary handled in step 4
    fi
    case "$f" in
        *.plist)
            if plutil -p "$f" 2>/dev/null | grep -qiE "$PATTERN"; then
                RESOURCE_HIT_FILES+=("$f")
            fi
            ;;
        *)
            if grep -aqiE "$PATTERN" "$f" 2>/dev/null; then
                RESOURCE_HIT_FILES+=("$f")
            fi
            ;;
    esac
done < <(find "$APP_PATH" -type f -not -path "*/PlugIns/*")

if [[ "${#RESOURCE_HIT_FILES[@]}" -gt 0 ]]; then
    echo "FAIL: bundle resources contain DebugBridge references:" >&2
    printf '  %s\n' "${RESOURCE_HIT_FILES[@]:0:5}" >&2
    FAIL=1
else
    echo "OK: no DebugBridge references in bundle resources"
fi

# 4. Binary must not contain DebugBridge-related strings
LEAKED_BIN=$(strings "$BIN_PATH" | grep -ciE "$PATTERN" || true)
if [[ "$LEAKED_BIN" -gt 0 ]]; then
    echo "FAIL: Release binary contains $LEAKED_BIN DebugBridge-related strings:" >&2
    strings "$BIN_PATH" | grep -iE "$PATTERN" | head -5 >&2
    FAIL=1
else
    echo "OK: Release binary has no DebugBridge strings"
fi

if [[ "$FAIL" -ne 0 ]]; then
    exit 1
fi

echo "PASS: zero DebugBridge surface in Release build"
