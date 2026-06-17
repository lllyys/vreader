#!/usr/bin/env bash
# Feature #107 WI-1 (PR-A) — tests the path→PLATFORM classifier
# `code_paths_platform` (workflow routing) AND confirms `code_paths_touched`
# (the Stop-time audit-debt gate, now sourced by check_audit_debt.sh) treats
# Android paths as code. Together these close the two false-green gaps #107
# targets: check_audit_debt.sh no longer ignores `android/`, and routing can
# pick the iOS vs Android lane.
#
# Run: bash .claude/hooks/__tests__/code_paths_platform.test.sh

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB="$HERE/../lib/code-paths.sh"

if [[ ! -f "$LIB" ]]; then
    echo "FAIL: $LIB does not exist"; exit 1
fi
# shellcheck source=/dev/null
source "$LIB"

fails=0

# assert_platform <expected token> <description> <file...>
assert_platform() {
    local expect="$1" desc="$2"; shift 2
    local got; got="$(printf '%s\n' "$@" | code_paths_platform)"
    if [[ "$got" == "$expect" ]]; then
        echo "ok   — $desc ($got)"
    else
        echo "FAIL — $desc: expected $expect, got $got"; fails=$((fails+1))
    fi
}

# assert_touched <expected: code|docs> <description> <file...>
assert_touched() {
    local expect="$1" desc="$2"; shift 2
    if printf '%s\n' "$@" | code_paths_touched; then local got="code"; else local got="docs"; fi
    if [[ "$got" == "$expect" ]]; then
        echo "ok   — $desc ($got)"
    else
        echo "FAIL — $desc: expected $expect, got $got"; fails=$((fails+1))
    fi
}

echo "== code_paths_platform: full ownership set =="
assert_platform android-app   "android/ source"          android/app/src/main/java/Foo.kt
assert_platform android-app   "loose .kt"                 Bar.kt
assert_platform android-app   "loose .kts"                build.gradle.kts
assert_platform android-app   "buildSrc/"                 buildSrc/Deps.kt
assert_platform android-app   "gradle/ wrapper dir"       gradle/wrapper/gradle-wrapper.properties
assert_platform android-app   "root build.gradle"         build.gradle
assert_platform android-app   "settings.gradle"           settings.gradle
assert_platform android-app   "gradle.properties"         gradle.properties
assert_platform android-app   "gradlew"                   gradlew
assert_platform android-app   "AndroidManifest.xml"       android/app/src/main/AndroidManifest.xml
assert_platform android-app   "res/ tree"                 android/app/src/main/res/values/strings.xml
assert_platform android-spike "spikes/ only"              spikes/android-reader-bench/run-bench.sh
assert_platform android-spike "spikes/ Kotlin (root>suffix)" spikes/android-reader-bench/src/Foo.kt
assert_platform android-spike "spikes/ build.gradle.kts"  spikes/android-reader-bench/build.gradle.kts
assert_platform android-spike "spikes/ AndroidManifest"   spikes/android-reader-bench/src/main/AndroidManifest.xml
assert_platform android-spike "spikes/ res/"              spikes/android-reader-bench/src/main/res/values/strings.xml
assert_platform ios           "vreader/"                  vreader/Models/Book.swift
assert_platform ios           "vreaderTests/"             vreaderTests/Services/X.swift
assert_platform ios           "project.yml"               project.yml
assert_platform ios           "*.xcodeproj"               vreader.xcodeproj/project.pbxproj
assert_platform shared        "docs only"                 docs/features.md
assert_platform shared        "contracts only"            contracts/identity/locator.md
assert_platform shared        ".claude only"              .claude/rules/47-feature-workflow.md
assert_platform shared        "scripts only (rule 40)"    scripts/run-android-tests.sh
assert_platform shared        "docs/*.kt (root>suffix)"    docs/snippets/example.kt
assert_platform shared        "docs build.gradle"          docs/sample/build.gradle
assert_platform shared        "docs AndroidManifest"       docs/sample/AndroidManifest.xml
assert_platform shared        "dev-docs res/"              dev-docs/res/notes.md
assert_platform shared        "scripts build.gradle"       scripts/build.gradle
assert_platform shared        "docs/*.xcodeproj"           docs/sample/vreader.xcodeproj/project.pbxproj

echo "== code_paths_platform: precedence =="
assert_platform android-app   "android-app > ios"         vreader/X.swift android/app/Foo.kt
assert_platform android-app   "android-app > shared"      docs/x.md android/app/Foo.kt
assert_platform android-spike "android-spike > ios"       vreader/X.swift spikes/bench/run.sh
assert_platform ios           "ios > shared"              docs/x.md vreader/X.swift
assert_platform shared        "shared-only → shared (routes iOS per rule 40)" docs/x.md scripts/y.sh

echo "== code_paths_touched: android parity (the check_audit_debt gap) =="
assert_touched code "android/ is code"        android/app/Foo.kt
assert_touched code "loose .kt is code"       Foo.kt
assert_touched code "contracts/ is code"      contracts/identity/locator.md
assert_touched docs "docs-only is not code"   docs/features.md
assert_touched docs ".claude/rules is not code" .claude/rules/47-feature-workflow.md

echo
if [[ "$fails" -eq 0 ]]; then echo "ALL PASS"; exit 0; else echo "$fails FAILURE(S)"; exit 1; fi
