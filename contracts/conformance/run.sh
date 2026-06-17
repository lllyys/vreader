#!/usr/bin/env bash
# Feature #104 Spike A — runs BOTH platforms' identity conformance suites
# against the SAME contracts/vectors/. Both green ⇒ the cross-platform
# identity contract holds (the ADR-0001 Risk-1 interop gate, as a CI gate).
#
#   contracts/conformance/run.sh            # run both
#   contracts/conformance/run.sh kotlin     # Kotlin only
#   contracts/conformance/run.sh swift      # Swift only
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WHICH="${1:-both}"
rc=0

# JDK 17 is the Android-standard JDK (rule 40 / ADR). Resolve the brew path.
: "${JAVA_HOME:=/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home}"
export JAVA_HOME

run_kotlin() {
    echo "== Kotlin conformance (contracts/conformance/kotlin) =="
    if [[ ! -x "$JAVA_HOME/bin/java" ]]; then
        # Codex Gate-4 High: a missing JDK is a HARD FAIL, not a silent skip —
        # the lane guarantees BOTH platforms green; skipping Kotlin while
        # printing PASS would be a fail-open.
        echo "FAIL kotlin — no JDK 17 at $JAVA_HOME (install: brew install openjdk@17)"; rc=1; return
    fi
    # Checked-in wrapper (host-independent, pinned Gradle), not a bare PATH
    # `gradle` (Codex Gate-4 Medium).
    ( cd "$ROOT/contracts/conformance/kotlin" && ./gradlew test --console=plain --no-daemon ) || rc=1
}
run_swift() {
    echo "== Swift conformance (vreaderTests/IdentityConformanceTests) =="
    ( cd "$ROOT" && scripts/run-tests.sh vreaderTests/IdentityConformanceTests ) || rc=1
}

# Bug #355: byte-diff the two platforms' ACTUAL canonical Locator output (each
# suite writes conformance/.out/<platform>-locator.txt). Both-vs-the-shared-vector
# is transitive, but this is the DIRECT Swift-vs-Kotlin check the bug asks for.
cross_diff() {
    local sw="$ROOT/contracts/conformance/.out/swift-locator.txt"
    local kt="$ROOT/contracts/conformance/.out/kotlin-locator.txt"
    if [[ ! -f "$sw" || ! -f "$kt" ]]; then
        echo "FAIL cross-diff — missing platform output ($([[ -f "$sw" ]] && echo swift✓ || echo swift✗) $([[ -f "$kt" ]] && echo kotlin✓ || echo kotlin✗))"
        rc=1; return
    fi
    if diff -u "$kt" "$sw" >/tmp/conformance-crossdiff.txt; then
        echo "== cross-diff: Swift == Kotlin canonical Locator output (byte-identical) =="
    else
        echo "FAIL cross-diff — Swift and Kotlin canonical output DIFFER:"; cat /tmp/conformance-crossdiff.txt; rc=1
    fi
}

case "$WHICH" in
    kotlin) run_kotlin ;;
    swift)  run_swift ;;
    both)   run_kotlin; run_swift; [[ "$rc" -eq 0 ]] && cross_diff ;;
    *) echo "usage: run.sh [both|kotlin|swift]"; exit 2 ;;
esac
[[ "$rc" -eq 0 ]] && echo "CONFORMANCE RESULT: PASS" || echo "CONFORMANCE RESULT: FAIL"
exit "$rc"
