#!/usr/bin/env bash
# Feature #164 WI-3 — the `android.util.Log` containment gate.
#
# Contract: NO production Kotlin source under android/app/src/main may reference
# `android.util.Log`, except the one file that owns the forward — `VLog.kt`. That
# single choke point is what makes "every log entry is captured, categorised and
# redactable" true by construction instead of by convention.
#
# Why this is a SCRIPT and not an acceptance bullet: a grep written into a plan is
# not a gate, because nothing runs it. The 6 sites migrated in WI-3 would drift back
# the first time someone reached for the familiar API.
#
# Why it matches TWO shapes: 4 of the 6 pre-migration sites used the SHORT form
# (`Log.w(TAG, …)` + `import android.util.Log`) and only 2 used the qualified
# `android.util.Log.w(…)`. A qualified-only check would have passed while missing
# most of what it exists to catch.
#
# Comments are stripped before matching — WI-1/WI-2's KDoc, and this project's own
# convention of explaining decisions in headers, legitimately name the API in prose.
#
# Run:
#   bash scripts/__tests__/check-android-log-containment.sh          # self-test + real tree
#   bash scripts/__tests__/check-android-log-containment.sh --scan <src-dir> [<allow-regex>]

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"

DEFAULT_SRC="$ROOT/android/app/src/main/kotlin"
DEFAULT_ALLOW='/diagnostics/VLog\.kt$'

# The 6 migrated sites: "<file under android/app/src/main/kotlin>|<expected VLog origin>".
MIGRATED_SITES=(
    "com/vreader/app/reader/PdfDocument.kt|PdfDocument"
    "com/vreader/app/reader/ReaderActivity.kt|ReaderActivity"
    "com/vreader/app/reader/foliate/FoliateBridge.kt|FoliateBridge"
    "com/vreader/app/reader/share/BookShareIntent.kt|BookShare"
    "com/vreader/app/search/SearchIndexCoordinator.kt|SearchIndexCoordinator"
)
EXPECTED_VLOG_CALLS=6

# ---------------------------------------------------------------- the scan

# Print "file:line: text" for every offending reference in <src-dir>.
# Exit 0 = clean, 1 = findings, 2 = error.
scan() {
    local src="$1" allow="${2:-$DEFAULT_ALLOW}"
    if [ ! -d "$src" ]; then
        echo "CHECK-ANDROID-LOG-CONTAINMENT RESULT: ERROR (no such source tree: $src)"
        return 2
    fi

    local findings=0 file
    while IFS= read -r file; do
        [[ "$file" =~ $allow ]] && continue
        local out
        out="$(awk -v f="$file" '
            # A full-line block-comment body (" * …", "/* …", "/** …") is prose, never code.
            /^[[:space:]]*(\*|\/\*)/ { next }
            {
                line = $0
                sub(/\/\/.*/, "", line)                       # strip a trailing line comment
                if (line ~ /android\.util\.Log\./) {
                    printf "%s:%d: %s\n", f, NR, $0; next
                }
                if (line ~ /^import[[:space:]]+android\.util\.Log[[:space:]]*$/) { imported = 1; next }
                if (imported && line ~ /(^|[^A-Za-z0-9_.$])Log\.(v|d|i|w|e|wtf|println|isLoggable)[[:space:]]*\(/) {
                    printf "%s:%d: %s\n", f, NR, $0
                }
            }
        ' "$file")"
        if [ -n "$out" ]; then
            printf '%s\n' "$out"
            findings=$((findings + 1))
        fi
    done < <(find "$src" -name '*.kt' -type f | sort)

    if [ "$findings" -eq 0 ]; then
        echo "CHECK-ANDROID-LOG-CONTAINMENT RESULT: OK (0 files)"
        return 0
    fi
    echo "CHECK-ANDROID-LOG-CONTAINMENT RESULT: FINDINGS ($findings file(s) outside VLog.kt)"
    return 1
}

if [ "${1:-}" = "--scan" ]; then
    shift
    scan "${1:?--scan needs a source dir}" "${2:-$DEFAULT_ALLOW}"
    exit $?
fi

# ---------------------------------------------------------------- self-test

fails=0
ok()   { echo "ok   — $1"; }
fail() { echo "FAIL — $1"; fails=$((fails + 1)); }

echo "== check-android-log-containment =="

FIX="$(mktemp -d -t log-containment.XXXXXX)"
trap 'rm -rf "$FIX"' EXIT
SRC="$FIX/kotlin/com/vreader/app"
mkdir -p "$SRC/diagnostics" "$SRC/reader"

# 1. qualified form — must be flagged.
cat > "$SRC/reader/Qualified.kt" <<'KOTLIN'
package com.vreader.app.reader
class Qualified {
    fun boom() = android.util.Log.w("Qualified", "nope")
}
KOTLIN

# 2. SHORT form + import — must be flagged (the form 4 of the 6 real sites used).
cat > "$SRC/reader/Short.kt" <<'KOTLIN'
package com.vreader.app.reader
import android.util.Log
private const val TAG = "Short"
class Short {
    fun boom() = Log.w(TAG, "nope")
}
KOTLIN

# 3. prose only — must NOT be flagged (WI-1/WI-2 headers do exactly this).
cat > "$SRC/reader/Prose.kt" <<'KOTLIN'
package com.vreader.app.reader
/**
 * Mirrors android.util.Log's priority set; see android.util.Log.w for the shape.
 */
class Prose {
    // android.util.Log.w(TAG, "commented out") — kept for context
    fun fine() = Unit
}
KOTLIN

# 4. the allowed owner — must NOT be flagged even using both forms.
cat > "$SRC/diagnostics/VLog.kt" <<'KOTLIN'
package com.vreader.app.diagnostics
import android.util.Log
object VLog {
    fun w(tag: String, m: String) { Log.w(tag, m); android.util.Log.i(tag, m) }
}
KOTLIN

# 5. an unrelated `Log` type with NO android import — must NOT be flagged.
cat > "$SRC/reader/OtherLog.kt" <<'KOTLIN'
package com.vreader.app.reader
import com.example.telemetry.Log
class OtherLog { fun go() = Log.w("t", "not the android one") }
KOTLIN

OUT="$("$0" --scan "$FIX/kotlin")"; RC=$?

# Assertions are anchored on the "<file>:<line>:" FINDING form, never a bare filename —
# the RESULT summary line itself names VLog.kt, which a loose grep happily matches.
grep -q "Qualified\.kt:3:" <<<"$OUT" \
    && ok "qualified android.util.Log.w flagged" \
    || fail "qualified form NOT flagged"

grep -q "Short\.kt:5:" <<<"$OUT" \
    && ok "short-form Log.w + import flagged (the 4-of-6 case)" \
    || fail "short form NOT flagged — a qualified-only check would ship"

grep -q "Prose\.kt:[0-9]" <<<"$OUT" \
    && fail "KDoc/comment mention was flagged (false positive)" \
    || ok "comment-only mentions ignored"

grep -q "VLog\.kt:[0-9]" <<<"$OUT" \
    && fail "the allowed owner VLog.kt was flagged" \
    || ok "VLog.kt exempted"

grep -q "OtherLog\.kt:[0-9]" <<<"$OUT" \
    && fail "a non-android Log type was flagged" \
    || ok "short form without the android import ignored"

[ "$RC" -eq 1 ] \
    && ok "exit 1 on findings" \
    || fail "expected exit 1 on findings, got $RC"

CLEAN_DIR="$FIX/clean"; mkdir -p "$CLEAN_DIR"
cp "$SRC/reader/Prose.kt" "$CLEAN_DIR/"
CLEAN="$("$0" --scan "$CLEAN_DIR")"; CRC=$?
if [ "$CRC" -eq 0 ] && [ "$(tail -1 <<<"$CLEAN")" = "CHECK-ANDROID-LOG-CONTAINMENT RESULT: OK (0 files)" ]; then
    ok "clean tree exits 0 with RESULT: OK"
else
    fail "clean run wrong (rc=$CRC last='$(tail -1 <<<"$CLEAN")')"
fi

MISSING="$("$0" --scan "$FIX/nope")"; MRC=$?
if [ "$MRC" -eq 2 ] && grep -q "RESULT: ERROR" <<<"$MISSING"; then
    ok "missing source tree exits 2 with RESULT: ERROR"
else
    fail "missing source tree mishandled (rc=$MRC)"
fi

# ---------------------------------------------------------------- the real tree

echo
echo "-- real tree: $DEFAULT_SRC"
REAL="$(scan "$DEFAULT_SRC")"; RRC=$?
printf '%s\n' "$REAL"
[ "$RRC" -eq 0 ] \
    && ok "android/app/src/main is clean of android.util.Log outside VLog.kt" \
    || fail "production sources still reference android.util.Log"

# The other half of the migration: every one of the 6 sites must ROUTE through VLog.
total_calls=0
for site in "${MIGRATED_SITES[@]}"; do
    rel="${site%%|*}"; origin="${site##*|}"
    path="$DEFAULT_SRC/$rel"
    if [ ! -f "$path" ]; then fail "migrated site missing: $rel"; continue; fi
    n="$(grep -c 'VLog\.[wide](' "$path")"
    total_calls=$((total_calls + n))
    if [ "$n" -ge 1 ] && grep -q "\"$origin\"\|TAG" "$path"; then
        ok "$rel routes through VLog ($n call(s), origin \"$origin\")"
    else
        fail "$rel does not route through VLog with origin \"$origin\""
    fi
done
[ "$total_calls" -eq "$EXPECTED_VLOG_CALLS" ] \
    && ok "all $EXPECTED_VLOG_CALLS migrated call sites accounted for" \
    || fail "expected $EXPECTED_VLOG_CALLS VLog calls across the migrated files, found $total_calls"

echo
if [ "$fails" -eq 0 ]; then echo "ALL PASS"; exit 0; else echo "$fails FAILURE(S)"; exit 1; fi
