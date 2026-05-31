#!/usr/bin/env bash
# Purpose: CU-free gesture driver for the booted iOS Simulator, built on
# Facebook's idb (iOS Development Bridge). Lets verification flows tap by
# accessibility label, tap by point coordinate, swipe, press a hardware
# button, dump the accessibility tree, and capture a screenshot — all
# WITHOUT the computer-use MCP server.
#
# Why this exists: the MCP computer-use host enumerates its app catalog
# from LaunchServices at launch and does not surface the Simulator
# (Simulator.app is nested inside Xcode.app), so MCP-CU cannot target the
# simulator. idb talks to the simulator directly over its own companion
# socket and synthesizes real gestures, sidestepping that entirely. Pairs
# with the vreader-debug:// DebugBridge harness and XCUITest.
#
# Requirements (one-time):
#   brew install facebook/fb/idb-companion
#   pip3 install --user fb-idb        # installs the `idb` CLI to ~/Library/Python/3.9/bin
#
# Usage:
#   scripts/sim-tap.sh launch com.vreader.app  # open an app by bundle id (deterministic)
#   scripts/sim-tap.sh label "Settings"        # tap the element whose AXLabel == "Settings"
#   scripts/sim-tap.sh xy 340 434              # tap point (x, y) in POINTS
#   scripts/sim-tap.sh swipe 200 700 200 200   # swipe (x1 y1 -> x2 y2) in POINTS
#   scripts/sim-tap.sh button HOME             # HOME | LOCK | SIDE_BUTTON | SIRI | APPLE_PAY
#   scripts/sim-tap.sh tree                    # dump on-screen elements (label + center)
#   scripts/sim-tap.sh shot [/path/out.png]    # screenshot (default: /tmp/sim-shot.png)
#
# To OPEN an app, prefer `launch <bundle-id>` over hunting its home-screen
# icon — icon position is unstable (App Library, folders, multi-page) while
# the bundle id is deterministic. Use `label`/`xy` for in-app controls.
#
# Env:
#   SIM_UDID   Override the target UDID (default: first booted simulator).
#
# Exit codes: 0 success; 2 setup error (no idb / no booted sim); 1 not found.

set -euo pipefail

# idb's console scripts land in the Python user-bin, which is usually not
# on PATH. Prepend both it and Homebrew so `idb` / `idb_companion` resolve.
export PATH="$HOME/Library/Python/3.9/bin:/opt/homebrew/bin:$PATH"

die() { echo "FAIL: $*" >&2; exit "${2:-2}"; }

command -v idb >/dev/null 2>&1 || die "idb CLI not found. Run: pip3 install --user fb-idb"
command -v idb_companion >/dev/null 2>&1 || die "idb_companion not found. Run: brew install facebook/fb/idb-companion"

# Resolve the target simulator: explicit SIM_UDID, else first booted device.
UDID="${SIM_UDID:-}"
if [[ -z "$UDID" ]]; then
    UDID=$(xcrun simctl list devices | grep -i booted \
        | grep -oE '[0-9A-Fa-f-]{36}' | head -1 || true)
fi
[[ -n "$UDID" ]] || die "no booted simulator (boot one with: xcrun simctl boot 'iPhone 17 Pro')"

# idb needs an explicit connect before the first command on a fresh sim.
idb connect "$UDID" >/dev/null 2>&1 || true

# Print every on-screen element as: label<TAB>centerX<TAB>centerY
dump_tree() {
    idb ui describe-all --udid "$UDID" 2>/dev/null | python3 -c "
import json, sys
try:
    items = json.load(sys.stdin)
except Exception:
    sys.exit(0)
for it in items:
    lbl = (it.get('AXLabel') or '').strip()
    if not lbl:
        continue
    f = it.get('frame', {}) or {}
    cx = f.get('x', 0) + f.get('width', 0) / 2
    cy = f.get('y', 0) + f.get('height', 0) / 2
    print(f'{lbl}\t{cx:.0f}\t{cy:.0f}')
"
}

CMD="${1:-}"; shift || true

case "$CMD" in
    tree)
        dump_tree
        ;;

    shot)
        OUT="${1:-/tmp/sim-shot.png}"
        xcrun simctl io "$UDID" screenshot "$OUT" >/dev/null 2>&1 \
            || die "screenshot failed"
        echo "OK: wrote $OUT"
        ;;

    xy)
        [[ $# -ge 2 ]] || die "usage: sim-tap.sh xy <x> <y>"
        idb ui tap --udid "$UDID" "$1" "$2" >/dev/null 2>&1 \
            || die "tap failed at ($1,$2)"
        echo "OK: tapped ($1,$2)"
        ;;

    swipe)
        [[ $# -ge 4 ]] || die "usage: sim-tap.sh swipe <x1> <y1> <x2> <y2>"
        idb ui swipe --udid "$UDID" "$1" "$2" "$3" "$4" >/dev/null 2>&1 \
            || die "swipe failed"
        echo "OK: swiped ($1,$2)->($3,$4)"
        ;;

    button)
        [[ $# -ge 1 ]] || die "usage: sim-tap.sh button <HOME|LOCK|SIDE_BUTTON|SIRI|APPLE_PAY>"
        idb ui button "$1" --udid "$UDID" >/dev/null 2>&1 \
            || die "button $1 failed"
        echo "OK: pressed $1"
        ;;

    launch)
        [[ $# -ge 1 ]] || die "usage: sim-tap.sh launch <bundle-id>"
        idb launch --udid "$UDID" "$1" >/dev/null 2>&1 \
            || die "launch failed for \"$1\" (installed? check: xcrun simctl listapps $UDID)"
        echo "OK: launched $1"
        ;;

    label)
        [[ $# -ge 1 ]] || die "usage: sim-tap.sh label \"<AXLabel>\""
        WANT="$1"
        COORDS=$(dump_tree | awk -F'\t' -v w="$WANT" '$1 == w {print $2" "$3; exit}')
        [[ -n "$COORDS" ]] || die "label \"$WANT\" not on the current screen (run 'tree' to list)" 1
        # shellcheck disable=SC2086
        idb ui tap --udid "$UDID" $COORDS >/dev/null 2>&1 \
            || die "tap failed for label \"$WANT\" at $COORDS"
        echo "OK: tapped \"$WANT\" at ($COORDS)"
        ;;

    *)
        sed -n '2,40p' "$0" | sed 's/^# \{0,1\}//'
        exit 2
        ;;
esac
