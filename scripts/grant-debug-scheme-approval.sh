#!/usr/bin/env bash
# Pre-grant the iOS Simulator's LaunchServices approval for the
# `vreader-debug://` URL scheme opened by `simctl openurl`, so the
# system "Open in 'vreader'?" prompt does not block the first call.
#
# Why this exists (bug #123): when CoreSimulatorBridge opens a custom
# URL scheme, iOS LaunchServices presents a one-shot approval alert
# from `lsd`. Until the user taps "Open", `lsd` holds the URL and the
# in-app handler never fires. `simctl openurl` exits 0 because the
# request was queued for approval, not because the app received it.
# A verification harness with no human to tap the alert hangs on the
# first call.
#
# The approval is persisted at:
#   <device-data>/Library/Preferences/com.apple.launchservices.schemeapproval.plist
# with key:
#   "com.apple.CoreSimulator.CoreSimulatorBridge-->vreader-debug" = com.vreader.app
#
# Scope: this approval is for `CoreSimulatorBridge` (i.e. `simctl openurl`)
# opening `vreader-debug://` on the named simulator. Other source apps
# would have their own approval entries.
#
# Usage:
#   scripts/grant-debug-scheme-approval.sh                # booted device (must be exactly one)
#   scripts/grant-debug-scheme-approval.sh <DEVICE-UDID>  # specific device
#
# Exit codes:
#   0  approval granted (or already present)
#   1  no/multiple booted devices, or device not found, or invalid UDID
#   2  plist write failed

set -euo pipefail

SCHEME="vreader-debug"
TARGET_BUNDLE="com.vreader.app"
APPROVAL_KEY="com.apple.CoreSimulator.CoreSimulatorBridge-->${SCHEME}"

# UDID must be a 36-char canonical UUID (8-4-4-4-12 hex). This blocks
# path traversal (`../`) and any character that could break out of the
# PlistBuddy / Python argument string we hand the UDID to below.
udid_is_valid() {
    local u="$1"
    [[ "$u" =~ ^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$ ]]
}

if [ "$#" -ge 1 ]; then
    UDID="$1"
    if ! udid_is_valid "$UDID"; then
        echo "error: invalid UDID format: '${UDID}' (expected 8-4-4-4-12 hex)" >&2
        exit 1
    fi
else
    # Collect all booted UDIDs. If exactly one, use it; otherwise abort
    # so we don't silently grant against the wrong simulator.
    BOOTED="$(xcrun simctl list devices booted -j | /usr/bin/python3 -c '
import json, sys
data = json.load(sys.stdin)
for runtime, devices in data.get("devices", {}).items():
    for d in devices:
        if d.get("state") == "Booted":
            print(d.get("udid", ""))
' 2>/dev/null || true)"
    BOOTED_COUNT="$(printf '%s\n' "$BOOTED" | grep -c . || true)"
    if [ "${BOOTED_COUNT}" -eq 0 ]; then
        echo "error: no booted simulator found" >&2
        exit 1
    fi
    if [ "${BOOTED_COUNT}" -gt 1 ]; then
        echo "error: ${BOOTED_COUNT} booted simulators; pass UDID explicitly:" >&2
        printf '  %s\n' $BOOTED >&2
        exit 1
    fi
    UDID="$BOOTED"
    if ! udid_is_valid "$UDID"; then
        # Defensive: if simctl ever emits a non-UUID, fail loud.
        echo "error: simctl returned non-UUID '${UDID}'" >&2
        exit 1
    fi
fi

DEVICE_ROOT="$HOME/Library/Developer/CoreSimulator/Devices/${UDID}/data"
PREF_DIR="${DEVICE_ROOT}/Library/Preferences"
PREF="${PREF_DIR}/com.apple.launchservices.schemeapproval.plist"

if [ ! -d "${DEVICE_ROOT}" ]; then
    echo "error: device data dir not found: ${DEVICE_ROOT}" >&2
    exit 1
fi

# Ensure the Preferences/ directory exists. On a freshly initialized
# simulator the directory may not exist yet, in which case PlistBuddy
# can't create the plist.
mkdir -p "${PREF_DIR}"

# Create an empty-dict plist if it doesn't exist (fresh simulator state).
if [ ! -f "${PREF}" ]; then
    # Pass the path via argv, not via shell interpolation into Python
    # source — keeps the path out of the source string so it can't
    # affect parsing (defense against `'` or newlines in $PREF).
    if ! /usr/bin/env python3 - "${PREF}" <<'PY'
import plistlib, sys
with open(sys.argv[1], "wb") as f:
    plistlib.dump({}, f)
PY
    then
        echo "error: cannot create ${PREF}" >&2
        exit 2
    fi
fi

# Idempotent set. PlistBuddy's `Set` errors when the key doesn't exist,
# so try `Set` and fall back to `Add`. The key contains `-->` and a
# colon-prefixed key path can't contain spaces in PlistBuddy syntax —
# we control both sides of the key (constant string built from $SCHEME),
# and $TARGET_BUNDLE is also a hardcoded constant, so no quoting hazard.
if /usr/libexec/PlistBuddy -c "Set :${APPROVAL_KEY} ${TARGET_BUNDLE}" "${PREF}" 2>/dev/null; then
    :
else
    /usr/libexec/PlistBuddy -c "Add :${APPROVAL_KEY} string ${TARGET_BUNDLE}" "${PREF}" \
        || { echo "error: failed to write approval entry" >&2; exit 2; }
fi

# Verify by reading back.
ACTUAL="$(/usr/libexec/PlistBuddy -c "Print :${APPROVAL_KEY}" "${PREF}" 2>/dev/null || true)"
if [ "${ACTUAL}" != "${TARGET_BUNDLE}" ]; then
    echo "error: verification failed — expected ${TARGET_BUNDLE}, got '${ACTUAL}'" >&2
    exit 2
fi

echo "Granted (legacy plist): ${SCHEME}:// → ${TARGET_BUNDLE}"
echo "  ${PREF}"

# Bug #140: iOS 26.4 reads scheme approvals from a SQLite store, not the
# user-prefs plist above. The plist write is kept for compatibility with
# older iOS Simulator versions; the SQLite write below is what unblocks
# `simctl openurl` on iOS 26.x.
#
# The store lives under <device>/Containers/Data/InternalDaemon/<id>/
#   Library/Caches/com.apple.LaunchServices.SettingsStore.sql
# with two tables (Election, LegacyElection). An identifier of just the
# scheme name with userElection=1 is sufficient to mark the scheme as
# user-approved — see GH #300 for the reverse-engineering trail.
SQL_STORE_GLOB="${DEVICE_ROOT}/Containers/Data/InternalDaemon/*/Library/Caches/com.apple.LaunchServices.SettingsStore.sql"
SQL_STORE=""
for candidate in ${SQL_STORE_GLOB}; do
    if [ -f "${candidate}" ]; then
        SQL_STORE="${candidate}"
        break
    fi
done

if [ -z "${SQL_STORE}" ]; then
    echo
    echo "warning: no LaunchServices.SettingsStore.sql found for this device — skipping SQLite grant."
    echo "         The legacy plist above may be sufficient on older iOS versions; on iOS 26.4+"
    echo "         this means scheme-approval will NOT be granted, and openurl will return error 115."
else
    if sqlite3 "${SQL_STORE}" \
        "INSERT OR REPLACE INTO Election (identifier, userElection) VALUES ('${SCHEME}', 1);" \
        2>/dev/null; then
        echo
        echo "Granted (LSD SQLite): ${SCHEME} → userElection=1"
        echo "  ${SQL_STORE}"
    else
        echo
        echo "warning: could not write to LSD SQLite store at ${SQL_STORE}"
        echo "         openurl may still return error 115 on iOS 26.4+."
    fi
fi
