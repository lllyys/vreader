#!/usr/bin/env bash
# Feature #107 PR-D — verifies the tdd-guardian test wrapper ROUTES by platform
# (the false-green fix: a Kotlin change must not pass the iOS test command).
# Uses TDD_FORCE_PLATFORM to exercise each branch without running the slow iOS
# xcodebuild lane. Run: bash scripts/__tests__/tdd-guardian-test.test.sh

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WRAP="$HERE/../tdd-guardian-test.sh"
fails=0

# android-app with no app shell → must refuse to green (exit 2, explicit msg).
out="$(TDD_FORCE_PLATFORM=android-app bash "$WRAP" 2>&1)"; rc=$?
if [ "$rc" -eq 2 ] && grep -q "refusing to green" <<<"$out"; then
    echo "ok   — android-app (no #106 app) refuses to green (exit 2)"
else
    echo "FAIL — android-app: expected exit 2 + 'refusing to green', got exit $rc"; fails=$((fails+1))
fi

# android-spike → routes to run-android-tests.sh (NO_EMULATOR here, exit 2 from
# the runner — the point is it took the ANDROID lane, not the iOS one).
out="$(TDD_FORCE_PLATFORM=android-spike bash "$WRAP" 2>&1)"
if grep -q "android-spike change" <<<"$out" && grep -q "RUN-ANDROID-TESTS RESULT:" <<<"$out"; then
    echo "ok   — android-spike routes to the Android runner (not iOS xcodebuild)"
else
    echo "FAIL — android-spike did not route to the Android runner:"; echo "$out" | tail -3; fails=$((fails+1))
fi

# Untracked Android file (Codex Gate-4 High): a brand-new, not-yet-`git add`ed
# `android/*.kt` must classify android-app (→ refuse-to-green exit 2), NOT fall to
# the iOS lane via an empty diff. Exercises the real git-detection path (no
# TDD_FORCE_PLATFORM). The probe also proves `ls-files --others` is consulted.
REPO="$(cd "$HERE/../.." && pwd)"
PROBE="$REPO/android/_tdd_guardian_untracked_probe.kt"
mkdir -p "$REPO/android"
printf 'class Probe\n' > "$PROBE"
out="$(bash "$WRAP" 2>&1)"; rc=$?
rm -f "$PROBE"; rmdir "$REPO/android" 2>/dev/null || true
if [ "$rc" -eq 2 ] && grep -q "refusing to green" <<<"$out"; then
    echo "ok   — untracked android/*.kt classifies android-app (no iOS false-green)"
else
    echo "FAIL — untracked android/*.kt did not route Android: exit $rc"; echo "$out" | tail -2; fails=$((fails+1))
fi

# Config wiring: the guardian config invokes the wrapper, not the raw xcodebuild.
CFG="$HERE/../../.claude/tdd-guardian/config.json"
if grep -q "tdd-guardian-test.sh" "$CFG"; then
    echo "ok   — tdd-guardian config routes through the wrapper"
else
    echo "FAIL — tdd-guardian config still hard-codes a raw test command"; fails=$((fails+1))
fi

echo
if [ "$fails" -eq 0 ]; then echo "ALL PASS"; exit 0; else echo "$fails FAILURE(S)"; exit 1; fi
