#!/usr/bin/env bash
# Feature #164 WI-3 — the `android.util.Log` containment gate.
#
# Contract: NO shipped production source anywhere under android/ may reference
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
# COMMENTS AND STRINGS (Gate-4 round 2): stripping is done by a small state machine,
# not by two line regexes. The naive version skipped any line STARTING with `/*` —
# so `/** doc */ val p = android.util.Log.WARN` was skipped wholesale — and cut every
# line at its first `//`, so `"https://x".length + android.util.Log.WARN` was cut
# inside a string literal. The machine tracks multi-line block comments across lines,
# removes complete inline `/* … */` spans, and honours `//` only OUTSIDE a double-
# quoted string. Prose (WI-1/WI-2's KDoc, this project's decision headers) still does
# not trip the gate.
#
# ACCEPTED LIMITATION: a name assembled at runtime — `Class.forName("android." +
# "util.Log")` — is invisible to any textual gate. This gate stops accidental drift
# and honest reintroduction; it is not an adversarial sandbox. Catching that would
# need bytecode/dependency analysis, which is out of scope for WI-3.
#
# SCOPE: every source set under android/ EXCEPT test / androidTest / debug (matched as
# the source-set segment directly beneath a module, not as a loose substring), and
# excluding generated `build/` output. `.kt` AND `.java`, so a Java file, a future
# `src/release` flavor, or another Gradle module (`:identity`) cannot slip past. The
# three exclusions are not shipped in the release APK; a debug-only launcher logging
# directly is out of this contract's scope.
#
# Run:
#   bash scripts/__tests__/check-android-log-containment.sh          # self-test + real tree
#   bash scripts/__tests__/check-android-log-containment.sh --scan <root> [<allow-regex>]

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"

DEFAULT_SRC="$ROOT/android"
DEFAULT_ALLOW='/diagnostics/VLog\.kt$'
# Applied to the path RELATIVE to the scan root: "<module>/src/<set>/…".
NON_SHIPPED_SET='^[^/]+/src/(test|androidTest|debug)/'

# The 6 migrated sites: "<file under android/>|<expected VLog origin>".
MIGRATED_SITES=(
    "app/src/main/kotlin/com/vreader/app/reader/PdfDocument.kt|PdfDocument"
    "app/src/main/kotlin/com/vreader/app/reader/ReaderActivity.kt|ReaderActivity"
    "app/src/main/kotlin/com/vreader/app/reader/foliate/FoliateBridge.kt|FoliateBridge"
    "app/src/main/kotlin/com/vreader/app/reader/share/BookShareIntent.kt|BookShare"
    "app/src/main/kotlin/com/vreader/app/search/SearchIndexCoordinator.kt|SearchIndexCoordinator"
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

    local findings=0 file rel
    while IFS= read -r file; do
        rel="${file#"$src"/}"
        [[ "$rel" =~ $NON_SHIPPED_SET ]] && continue
        [[ "$file" =~ $allow ]] && continue
        local out
        out="$(awk -v f="$file" '
            # Remove comments with a state machine, so neither a block comment sharing a line
            # with code nor a "//" inside a string literal can hide a reference.
            function strip(l,   out, i, c, n, inStr, esc) {
                out = ""; n = length(l); i = 1
                while (i <= n) {
                    c = substr(l, i, 1)
                    if (inBlock) {                                  # inside /* … */
                        if (substr(l, i, 2) == "*/") { inBlock = 0; i += 2 } else { i++ }
                        continue
                    }
                    if (inStr) {
                        out = out c
                        if (esc) { esc = 0 }
                        else if (c == "\\") { esc = 1 }
                        else if (c == "\"") { inStr = 0 }
                        i++
                        continue
                    }
                    if (substr(l, i, 2) == "/*") { inBlock = 1; i += 2; continue }
                    if (substr(l, i, 2) == "//") { break }          # rest of the line is a comment
                    if (c == "\"") { inStr = 1 }
                    out = out c
                    i++
                }
                return out
            }
            {
                line = strip($0)
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
    done < <(find "$src" \( -name '*.kt' -o -name '*.java' \) -type f -not -path '*/build/*' | sort)

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
SRC="$FIX/app/src/main/kotlin/com/vreader/app"
mkdir -p "$SRC/diagnostics" "$SRC/reader" "$FIX/app/src/main/java/com/vreader/app" \
         "$FIX/app/src/test/kotlin" "$FIX/app/src/androidTest/kotlin" "$FIX/app/src/debug/kotlin" \
         "$FIX/identity/src/main/kotlin" "$FIX/app/build/generated" \
         "$FIX/app/src/main/kotlin/nested/src/test/kotlin"

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
cat > "$FIX/app/src/main/java/com/vreader/app/LegacyBridge.java" <<'JAVA'
package com.vreader.app;
import android.util.Log;
public class LegacyBridge { void go() { Log.w("Reader", "escaped"); } }
JAVA

# 11-13. NON-shipped source sets — must be skipped, matched as the segment directly
# beneath a module (so a misleadingly NESTED src/test path, fixture 17, is NOT skipped).
for set in test androidTest debug; do
    cat > "$FIX/app/src/$set/kotlin/Harness.kt" <<'KOTLIN'
package com.vreader.app
import android.util.Log
class Harness { fun go() = Log.w("t", "allowed here") }
KOTLIN
done

# 14. ANOTHER Gradle module — production Kotlin outside :app must still be scanned.
cat > "$FIX/identity/src/main/kotlin/Contract.kt" <<'KOTLIN'
package vreader.contracts
import android.util.Log
class Contract { fun go() = Log.w("t", "escaped via another module") }
KOTLIN

# 15-16. The two comment/string evasions round 2 produced against the line-regex version.
cat > "$SRC/reader/InlineBlock.kt" <<'KOTLIN'
package com.vreader.app.reader
class InlineBlock {
    /** doc */ val priority = android.util.Log.WARN
}
KOTLIN

cat > "$SRC/reader/SlashInString.kt" <<'KOTLIN'
package com.vreader.app.reader
class SlashInString {
    val priority = "https://example".length + android.util.Log.WARN
}
KOTLIN

# 17. a nested, misleading "src/test" path INSIDE a production source set — must be scanned.
cat > "$FIX/app/src/main/kotlin/nested/src/test/kotlin/Sneaky.kt" <<'KOTLIN'
package com.vreader.app
class Sneaky { fun go() = android.util.Log.w("t", "hidden under a fake test path") }
KOTLIN

# 18. generated build output — never scanned.
cat > "$FIX/app/build/generated/Generated.kt" <<'KOTLIN'
package com.vreader.app
import android.util.Log
class Generated { fun go() = Log.w("t", "generated") }
KOTLIN

# 19. a MULTI-LINE block comment whose body has no leading '*' — prose, must NOT be flagged.
cat > "$SRC/reader/LooseBlockProse.kt" <<'KOTLIN'
package com.vreader.app.reader
/*
  historical note: this class used to call android.util.Log directly.
*/
class LooseBlockProse { fun fine() = Unit }
KOTLIN

OUT="$("$0" --scan "$FIX")"; RC=$?

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

# Every evasion the two audit rounds named.
for evasion in Aliased Wildcard SplitCall Reflective InlineBlock SlashInString Sneaky; do
    grep -q "$evasion\.kt:[0-9]" <<<"$OUT" \
        && ok "evasion caught: $evasion" \
        || fail "EVASION NOT CAUGHT: $evasion"
done
grep -q "LegacyBridge\.java:[0-9]" <<<"$OUT" \
    && ok "shipped .java source is scanned" \
    || fail "a Java production file evaded the gate"

grep -q "Contract\.kt:[0-9]" <<<"$OUT" \
    && ok "another Gradle module's production source is scanned" \
    || fail "production Kotlin outside :app evaded the gate"

grep -q "Harness\.kt:[0-9]" <<<"$OUT" \
    && fail "a non-shipped source set (test/androidTest/debug) was flagged" \
    || ok "test / androidTest / debug source sets excluded"

grep -q "Generated\.kt:[0-9]" <<<"$OUT" \
    && fail "generated build/ output was flagged" \
    || ok "generated build/ output excluded"

grep -q "LooseBlockProse\.kt:[0-9]" <<<"$OUT" \
    && fail "a multi-line block comment without leading '*' was flagged (false positive)" \
    || ok "multi-line block-comment prose ignored"

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
