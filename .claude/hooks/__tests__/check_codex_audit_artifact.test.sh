#!/usr/bin/env bash
# Feature #103 WI-1 — tests the code-path classification the
# check_codex_audit_artifact.sh merge gate uses to decide whether a PR
# touches CODE (audit required) vs docs/meta only (audit not required).
#
# The classification is factored into `.claude/hooks/lib/code-paths.sh`
# (`code_paths_touched` reads a newline-separated file list on stdin and
# exits 0 iff any path is a code path). This test asserts the contract,
# incl. the Android/Kotlin + shared-`contracts/` roots added by #103 so an
# `android/`/`contracts/` PR can no longer bypass Gate 4 as docs-only.
#
# Run: bash .claude/hooks/__tests__/check_codex_audit_artifact.test.sh

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB="$HERE/../lib/code-paths.sh"

if [[ ! -f "$LIB" ]]; then
    echo "FAIL: $LIB does not exist (WI-1 not implemented)"; exit 1
fi
# shellcheck source=/dev/null
source "$LIB"

fails=0
# assert_code <expected: code|docs> <description> <file...>
assert_code() {
    local expect="$1" desc="$2"; shift 2
    local list; list="$(printf '%s\n' "$@")"
    if printf '%s\n' "$list" | code_paths_touched; then
        local got="code"
    else
        local got="docs"
    fi
    if [[ "$got" == "$expect" ]]; then
        echo "ok   — $desc ($got)"
    else
        echo "FAIL — $desc: expected $expect, got $got"; fails=$((fails+1))
    fi
}

# iOS (unchanged behavior)
assert_code code "iOS Swift source"        "vreader/Views/Reader/Foo.swift"
assert_code code "iOS test source"         "vreaderTests/Foo.swift"
# Android / Kotlin roots + extensions (the High fix: roots, not just ext)
assert_code code "android/ Kotlin source"  "android/app/src/main/Foo.kt"
assert_code code "spikes/ Gradle harness"  "spikes/android-reader-bench/build.gradle.kts"
assert_code code "root gradle.properties"  "gradle.properties"
assert_code code "buildSrc Kotlin"         "buildSrc/src/Foo.kt"
assert_code code "AndroidManifest.xml"     "android/app/src/main/AndroidManifest.xml"
assert_code code "Android resources"       "android/app/src/main/res/values/strings.xml"
assert_code code "loose .kts script"       "tools/foo.gradle.kts"
# Shared cross-platform code surface (the Critical fix)
assert_code code "contracts/ spec"         "contracts/identity/fingerprint.md"
assert_code code "contracts/ vectors"      "contracts/vectors/locator.json"
# Mixed
assert_code code "mixed iOS + Android"     "vreader/A.swift" "android/B.kt"
# Docs / meta only — must NOT require an audit (the negative guard)
assert_code docs "docs only"               "docs/features.md" "docs/bugs.md"
assert_code docs "dev-docs plan only"      "dev-docs/plans/foo.md"
assert_code docs "rule + hook only"        ".claude/rules/40-version-bump.md" ".claude/hooks/foo.sh"
assert_code docs "README only"             "README.md"
# Codex Gate-4 Medium — docs/-prefixed paths that LOOK code-y must stay docs
assert_code docs "docs/ path ending .kt"   "docs/snippets/example.kt"
assert_code docs "docs/ with res/ segment" "docs/res/notes.md"
assert_code docs "docs/ build.gradle"      "docs/sample/build.gradle"
assert_code docs "docs/ AndroidManifest"   "docs/sample/AndroidManifest.xml"
# ...but contracts/ (a CODE root) is NOT excluded even for .md
assert_code code "contracts/ README.md"    "contracts/README.md"

# Codex Gate-4 High — pipefail/SIGPIPE: a code path FIRST followed by a
# huge docs list must still classify as code under `set -o pipefail`
# (grep -q would early-exit and SIGPIPE the producer → fail-open).
pipefail_check() {
    # Assert the actual PIPELINE EXIT STATUS (not captured output) under
    # `set -o pipefail` — the producer must not SIGPIPE (Codex round-2:
    # the output looked right while the pipeline still exited 141).
    set -o pipefail
    { printf 'vreader/A.swift\n'; for i in $(seq 1 20000); do printf 'docs/file-%05d.md\n' "$i"; done; } | code_paths_touched
    local status=$?
    set +o pipefail
    if [[ "$status" -eq 0 ]]; then
        echo "ok   — pipefail: code-first + 20k docs → pipeline exit 0 (CODE, no SIGPIPE)"
    else
        echo "FAIL — pipefail: pipeline exit $status (SIGPIPE/fail-open!)"; fails=$((fails+1))
    fi
}
pipefail_check

if [[ "$fails" -gt 0 ]]; then
    echo "RESULT: FAILED ($fails)"; exit 1
fi
echo "RESULT: PASSED"
