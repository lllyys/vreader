#!/usr/bin/env bash
# Feature #164 WI-3 — the `android.util.Log` containment gate.
#
# Contract: NO shipped production source under android/app/src may reference
# `android.util.Log`, except the one file that owns the forward — `VLog.kt`. That
# single choke point is what makes "every log entry is captured, categorised and
# redactable" true by construction instead of by convention.
#
# Why this is a SCRIPT and not an acceptance bullet: a grep written into a plan is
# not a gate, because nothing runs it. The 6 sites migrated in WI-3 would drift back
# the first time someone reached for the familiar API.
#
# WHAT IT MATCHES, and why it is a BAN ON THE NAME rather than on call shapes
# (Gate-4 Medium): the first version keyed on the two shapes present in the tree —
# qualified `android.util.Log.w(…)` and short `Log.w(…)` behind a plain import — and
# the auditor produced four one-line evasions: `import android.util.Log as Platform`,
# `import android.util.*`, a qualified call split across lines, and the same inside a
# string template. So the rule is now simply: the literal `android.util.Log` may not
# appear in code, and `import android.util.*` (which pulls Log into scope) is banned
# too. Every listed evasion contains one of those two, including the multi-line split
# (the qualified prefix still sits on one line) and the reflective
# `Class.forName("android.util.Log")`.
#
# Comments are stripped before matching — WI-1/WI-2's KDoc, and this project's own
# convention of explaining decisions in headers, legitimately name the API in prose.
#
# SCOPE: every source set under android/app/src EXCEPT test / androidTest / debug —
# `.kt` AND `.java`, so a Java file or a future `src/release` flavor cannot slip past.
# The three exclusions are not shipped in the release APK; a debug-only launcher
# logging directly is out of this contract's scope.
#
# Run:
#   bash scripts/__tests__/check-android-log-containment.sh          # self-test + real tree
#   bash scripts/__tests__/check-android-log-containment.sh --scan <src-dir> [<allow-regex>] [<exclude-regex>]

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"

DEFAULT_SRC="$ROOT/android/app/src"
DEFAULT_ALLOW='/diagnostics/VLog\.kt$'
DEFAULT_EXCLUDE='/src/(test|androidTest|debug)/'

# The 6 migrated sites: "<file under android/app/src>|<expected VLog origin>".
MIGRATED_SITES=(
    "main/kotlin/com/vreader/app/reader/PdfDocument.kt|PdfDocument"
    "main/kotlin/com/vreader/app/reader/ReaderActivity.kt|ReaderActivity"
    "main/kotlin/com/vreader/app/reader/foliate/FoliateBridge.kt|FoliateBridge"
    "main/kotlin/com/vreader/app/reader/share/BookShareIntent.kt|BookShare"
    "main/kotlin/com/vreader/app/search/SearchIndexCoordinator.kt|SearchIndexCoordinator"
)
EXPECTED_VLOG_CALLS=6

# ---------------------------------------------------------------- the scan

# Print "file:line: text" for every offending reference in <src-dir>.
# Exit 0 = clean, 1 = findings, 2 = error.
scan() {
    local src="$1" allow="${2:-$DEFAULT_ALLOW}" exclude="${3:-$DEFAULT_EXCLUDE}"
    if [ ! -d "$src" ]; then
        echo "CHECK-ANDROID-LOG-CONTAINMENT RESULT: ERROR (no such source tree: $src)"
        return 2
    fi

    local findings=0 file
    while IFS= read -r file; do
        [ -n "$exclude" ] && [[ "$file" =~ $exclude ]] && continue
        [[ "$file" =~ $allow ]] && continue
        local out
        out="$(awk -v f="$file" '
            # A full-line block-comment body (" * …", "/* …", "/** …") is prose, never code.
            /^[[:space:]]*(\*|\/\*)/ { next }
            {
                line = $0
                sub(/\/\/.*/, "", line)                       # strip a trailing line comment
                # The NAME itself is banned — that covers the plain import, an aliased import,
                # a qualified call (even split across lines: the prefix stays on one line), and
                # a reflective Class.forName("android.util.Log").
                if (line ~ /android\.util\.Log/) { printf "%s:%d: %s\n", f, NR, $0; next }
                # A wildcard import pulls Log into scope without ever naming it.
                if (line ~ /^[[:space:]]*import[[:space:]]+android\.util\.\*/) {
                    printf "%s:%d: %s\n", f, NR, $0
                }
            }
        ' "$file")"
        if [ -n "$out" ]; then
            printf '%s\n' "$out"
            findings=$((findings + 1))
        fi
    done < <(find "$src" \( -name '*.kt' -o -name '*.java' \) -type f | sort)

    if [ "$findings" -eq 0 ]; then
        echo "CHECK-ANDROID-LOG-CONTAINMENT RESULT: OK (0 files)"
        return 0
    fi
    echo "CHECK-ANDROID-LOG-CONTAINMENT RESULT: FINDINGS ($findings file(s) outside VLog.kt)"
    return 1
}

if [ "${1:-}" = "--scan" ]; then
    shift
    scan "${1:?--scan needs a source dir}" "${2:-$DEFAULT_ALLOW}" "${3:-$DEFAULT_EXCLUDE}"
    exit $?
fi

# ---------------------------------------------------------------- self-test

fails=0
ok()   { echo "ok   — $1"; }
fail() { echo "FAIL — $1"; fails=$((fails + 1)); }

echo "== check-android-log-containment =="

FIX="$(mktemp -d -t log-containment.XXXXXX)"
trap 'rm -rf "$FIX"' EXIT
SRC="$FIX/src/main/kotlin/com/vreader/app"
mkdir -p "$SRC/diagnostics" "$SRC/reader" "$FIX/src/main/java/com/vreader/app" \
         "$FIX/src/test/kotlin" "$FIX/src/androidTest/kotlin" "$FIX/src/debug/kotlin"

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

# 6-9. The four evasions the Gate-4 audit produced against the first (shape-keyed) version.
cat > "$SRC/reader/Aliased.kt" <<'KOTLIN'
package com.vreader.app.reader
import android.util.Log as PlatformLog
class Aliased { fun go() = PlatformLog.w("Reader", "escaped") }
KOTLIN

cat > "$SRC/reader/Wildcard.kt" <<'KOTLIN'
package com.vreader.app.reader
import android.util.*
class Wildcard { fun go() = Log.w("Reader", "escaped") }
KOTLIN

cat > "$SRC/reader/SplitCall.kt" <<'KOTLIN'
package com.vreader.app.reader
class SplitCall {
    fun go() = android.util.Log
        .w("Reader", "escaped")
}
KOTLIN

cat > "$SRC/reader/Reflective.kt" <<'KOTLIN'
package com.vreader.app.reader
class Reflective { fun go() = Class.forName("android.util.Log") }
KOTLIN

# 10. a JAVA production file — the source set is shipped, so it must be scanned.
cat > "$FIX/src/main/java/com/vreader/app/LegacyBridge.java" <<'JAVA'
package com.vreader.app;
import android.util.Log;
public class LegacyBridge { void go() { Log.w("Reader", "escaped"); } }
JAVA

# 11-13. NON-shipped source sets — must be skipped by the exclude rule.
for set in test androidTest debug; do
    cat > "$FIX/src/$set/kotlin/Harness.kt" <<'KOTLIN'
package com.vreader.app
import android.util.Log
class Harness { fun go() = Log.w("t", "allowed here") }
KOTLIN
done

OUT="$("$0" --scan "$FIX/src")"; RC=$?

# Assertions are anchored on the "<file>:<line>:" FINDING form, never a bare filename —
# the RESULT summary line itself names VLog.kt, which a loose grep happily matches.
grep -q "Qualified\.kt:3:" <<<"$OUT" \
    && ok "qualified android.util.Log.w flagged" \
    || fail "qualified form NOT flagged"

# The 4-of-6 case. Reported at the IMPORT line, not the call: banning the name is what
# makes the aliased and wildcard variants below fall out for free.
grep -q "Short\.kt:2:" <<<"$OUT" \
    && ok "short-form Log.w + import flagged at its import (the 4-of-6 case)" \
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

# The four evasions the audit named, plus the Java source set.
for evasion in Aliased Wildcard SplitCall Reflective; do
    grep -q "$evasion\.kt:[0-9]" <<<"$OUT" \
        && ok "evasion caught: $evasion" \
        || fail "EVASION NOT CAUGHT: $evasion"
done
grep -q "LegacyBridge\.java:[0-9]" <<<"$OUT" \
    && ok "shipped .java source is scanned" \
    || fail "a Java production file evaded the gate"

grep -q "Harness\.kt:[0-9]" <<<"$OUT" \
    && fail "a non-shipped source set (test/androidTest/debug) was flagged" \
    || ok "test / androidTest / debug source sets excluded"

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
