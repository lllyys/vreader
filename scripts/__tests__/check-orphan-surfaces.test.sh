#!/usr/bin/env bash
# Contract tests for scripts/check-orphan-surfaces.sh — the reachability gate
# that catches Compose surfaces shipping in the release APK with no production
# call site (the class of defect that let four Android features reach VERIFIED
# while being unreachable dead code).
#
# Everything runs against a TEMPORARY fixture tree, never the real android/
# dir, so the suite's verdict never moves when app source changes.
#
# Run: bash scripts/__tests__/check-orphan-surfaces.test.sh

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
SCRIPT="$ROOT/scripts/check-orphan-surfaces.sh"
fails=0

ok()   { echo "ok   — $1"; }
fail() { echo "FAIL — $1"; fails=$((fails+1)); }

echo "== check-orphan-surfaces =="

if [ ! -x "$SCRIPT" ]; then
    echo "FAIL — $SCRIPT missing or not executable"; echo "1 FAILURE(S)"; exit 1
fi

FIX="$(mktemp -d -t orphan-fixture.XXXXXX)"
trap 'rm -rf "$FIX"' EXIT
MAIN="$FIX/main/kotlin/com/app"
DEBUG="$FIX/debug/kotlin/com/app"
mkdir -p "$MAIN" "$DEBUG"

# --- fixture: the five classification cases ---------------------------------

# 1. REACHABLE — called from HomeScreen below.
cat > "$MAIN/DetailsSheet.kt" <<'KOTLIN'
package com.app
@Composable
fun DetailsSheet(id: String) { Text(id) }
KOTLIN

# 2. ORPHANED — public surface, zero callers anywhere.
cat > "$MAIN/GhostScreen.kt" <<'KOTLIN'
package com.app
@Composable
fun GhostScreen(state: GhostState) {
    // GhostScreen( in a comment must NOT count as a call site
    Text(state.title)
}
KOTLIN

# 3. DEBUG-ONLY — called solely from the debug source set.
cat > "$MAIN/DebugPanel.kt" <<'KOTLIN'
package com.app
@Composable
fun DebugPanel(onClose: () -> Unit) { Text("debug") }
KOTLIN

# 4. private — must be skipped entirely (never reported, never counted).
cat > "$MAIN/InternalBar.kt" <<'KOTLIN'
package com.app
@Composable
private fun HiddenBar() { Text("hidden") }

@Composable
internal fun AlsoHiddenSheet() { Text("hidden") }
KOTLIN

# 5. ALLOWLISTED — orphaned, but deliberately exempted.
cat > "$MAIN/StagedDialog.kt" <<'KOTLIN'
package com.app
@Composable
fun StagedDialog() { Text("staged") }
KOTLIN

# Non-surface composable (no suffix match) + @Preview + the production entry
# point that makes DetailsSheet reachable.
cat > "$MAIN/HomeScreen.kt" <<'KOTLIN'
package com.app
@Composable
fun HomeScreen() {
    BookRow("a")
    DetailsSheet("id-1")
}

@Composable
fun BookRow(title: String) { Text(title) }

@Preview
@Composable
fun PreviewOnlyScreen() { HomeScreen() }
KOTLIN

# The production entry point — a root screen is reached from an Activity's
# setContent, so the detector must count call sites in ordinary Kotlin too.
cat > "$MAIN/MainActivity.kt" <<'KOTLIN'
package com.app
class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        setContent { HomeScreen() }
    }
}
KOTLIN

cat > "$DEBUG/DebugEntry.kt" <<'KOTLIN'
package com.app
@Composable
fun DebugEntry() { DebugPanel(onClose = {}) }
KOTLIN

ALLOW="$FIX/allow"
cat > "$ALLOW" <<'ALLOWLIST'
# deliberately unwired, tracked separately
StagedDialog
ALLOWLIST

EMPTY_ALLOW="$FIX/allow-empty"
: > "$EMPTY_ALLOW"

run() { # <allowlist> [args...]
    local allow="$1"; shift
    ORPHAN_MAIN_SRC="$FIX/main/kotlin" \
    ORPHAN_DEBUG_SRC="$FIX/debug" \
    ORPHAN_ALLOWLIST="$allow" \
    "$SCRIPT" "$@" 2>&1
}

# --- classification ---------------------------------------------------------

OUT="$(run "$ALLOW")"; RC=$?

grep -q "^ORPHANED GhostScreen (.*GhostScreen.kt) — no production call site$" <<<"$OUT" \
    && ok "ORPHANED surface reported in the required line format" \
    || fail "ORPHANED GhostScreen line missing/malformed"

grep -q "^DEBUG-ONLY DebugPanel " <<<"$OUT" \
    && ok "debug-only surface classified DEBUG-ONLY" \
    || fail "DebugPanel not classified DEBUG-ONLY"

grep -q "DetailsSheet" <<<"$OUT" \
    && fail "reachable DetailsSheet was reported as a finding" \
    || ok "reachable surface (DetailsSheet) not flagged"

grep -qE "HiddenBar|AlsoHiddenSheet" <<<"$OUT" \
    && fail "private/internal composable was reported" \
    || ok "private + internal composables skipped"

grep -q "^ALLOWED  StagedDialog " <<<"$OUT" \
    && ok "allowlisted surface reported as ALLOWED, not as a finding" \
    || fail "allowlisted StagedDialog not surfaced as ALLOWED"

grep -q "PreviewOnlyScreen" <<<"$OUT" \
    && fail "@Preview-annotated composable was reported" \
    || ok "@Preview composable skipped"

grep -q "BookRow" <<<"$OUT" \
    && fail "non-surface composable (BookRow) was reported" \
    || ok "suffix filter excludes non-surface composables"

# --- RESULT line + exit codes ----------------------------------------------

LAST="$(tail -1 <<<"$OUT")"
if [ "$LAST" = "CHECK-ORPHAN-SURFACES RESULT: FINDINGS (1 orphaned, 1 debug-only)" ]; then
    ok "final RESULT line exact: $LAST"
else
    fail "final RESULT line wrong: '$LAST'"
fi

[ "$RC" -ne 0 ] && ok "exit non-zero on findings (rc=$RC)" || fail "exit 0 despite findings"

# Allowlisting every finding must make the run clean and exit 0.
FULL_ALLOW="$FIX/allow-all"
printf 'GhostScreen\nDebugPanel\nStagedDialog\n' > "$FULL_ALLOW"
CLEAN="$(run "$FULL_ALLOW")"; CRC=$?
CLEAN_LAST="$(tail -1 <<<"$CLEAN")"
if [ "$CLEAN_LAST" = "CHECK-ORPHAN-SURFACES RESULT: OK (0 orphaned, 0 debug-only)" ] && [ "$CRC" -eq 0 ]; then
    ok "clean tree exits 0 with RESULT: OK"
else
    fail "clean run wrong (rc=$CRC last='$CLEAN_LAST')"
fi

# An absent allowlist file must not error — it means "nothing exempted".
NOALLOW="$(run "$FIX/does-not-exist")"; NRC=$?
if grep -q "^ORPHANED StagedDialog " <<<"$NOALLOW" && [ "$NRC" -ne 0 ]; then
    ok "missing allowlist file degrades to empty allowlist"
else
    fail "missing allowlist file mishandled (rc=$NRC)"
fi

if grep -q "^ORPHANED StagedDialog " <<<"$(run "$EMPTY_ALLOW")"; then
    ok "empty allowlist exempts nothing"
else
    fail "empty allowlist wrongly exempted StagedDialog"
fi

# --- --quiet ----------------------------------------------------------------

Q="$(run "$ALLOW" --quiet)"
if [ "$(wc -l <<<"$Q" | tr -d ' ')" = "1" ] && grep -q "^CHECK-ORPHAN-SURFACES RESULT: " <<<"$Q"; then
    ok "--quiet prints only the RESULT line"
else
    fail "--quiet printed extra output: $Q"
fi

# --- --json -----------------------------------------------------------------

J="$(run "$ALLOW" --json)"
J_BODY="$(sed '$d' <<<"$J")"
if printf '%s' "$J_BODY" | python3 -c "import json,sys; json.load(sys.stdin)" 2>/dev/null; then
    ok "--json body parses as JSON"
else
    fail "--json body is not valid JSON: $J_BODY"
fi
if printf '%s' "$J_BODY" | python3 -c '
import json,sys
d = json.load(sys.stdin)
by = {s["name"]: s for s in d["surfaces"]}
assert d["result"] == "FINDINGS", d["result"]
assert d["orphaned"] == 1 and d["debug_only"] == 1 and d["allowlisted"] == 1, d
assert by["GhostScreen"]["status"] == "ORPHANED", by["GhostScreen"]
assert by["DebugPanel"]["status"] == "DEBUG-ONLY", by["DebugPanel"]
assert by["DetailsSheet"]["status"] == "REACHABLE", by["DetailsSheet"]
assert by["StagedDialog"]["status"].startswith("ALLOWED"), by["StagedDialog"]
assert "HiddenBar" not in by and "BookRow" not in by, sorted(by)
' 2>/dev/null; then
    ok "--json carries the correct status for all five cases"
else
    fail "--json payload wrong: $J_BODY"
fi
if [ "$(tail -1 <<<"$J")" = "CHECK-ORPHAN-SURFACES RESULT: FINDINGS (1 orphaned, 1 debug-only)" ]; then
    ok "--json still ends with the RESULT line"
else
    fail "--json missing the final RESULT line"
fi

# --- cwd independence + error path -----------------------------------------

if (cd / && ORPHAN_MAIN_SRC="$FIX/main/kotlin" ORPHAN_DEBUG_SRC="$FIX/debug" \
        ORPHAN_ALLOWLIST="$ALLOW" "$SCRIPT" --quiet >/dev/null 2>&1); then
    fail "run from / lost its findings"
else
    ok "runs from any cwd (script resolves its own root)"
fi

MISSING="$(ORPHAN_MAIN_SRC="$FIX/nope" "$SCRIPT" 2>&1)"; MRC=$?
if [ "$MRC" -eq 2 ] && grep -q "^CHECK-ORPHAN-SURFACES RESULT: ERROR " <<<"$MISSING"; then
    ok "missing source tree exits 2 with RESULT: ERROR"
else
    fail "missing source tree mishandled (rc=$MRC out='$MISSING')"
fi

echo
if [ "$fails" -eq 0 ]; then echo "ALL PASS"; exit 0; else echo "$fails FAILURE(S)"; exit 1; fi
