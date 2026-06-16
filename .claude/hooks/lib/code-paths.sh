#!/usr/bin/env bash
# Feature #103 WI-1 (Android Phase 0 — safety plumbing) — shared
# code-path classification for the Codex-audit merge gate.
#
# `code_paths_touched` reads a newline-separated list of changed paths on
# stdin and exits 0 (true) iff ANY is a CODE path that must run through
# Gate 4 (the Codex audit), 1 otherwise (docs/meta only).
#
# Classification is by ROOT, not just extension (a `contracts/`-only PR,
# an `AndroidManifest.xml`, `gradle.properties`, a `buildSrc/` file, etc.
# must all be audited). Before #103 the predicate was only
# `^(vreader/|vreaderTests/)`, so any `android/`/`contracts/` PR bypassed
# the gate as docs-only — the day-1 blocker ADR-0001 Phase 0 fixes.
#
# Roots / patterns (audit-requiring):
#   iOS (unchanged):  vreader/  vreaderTests/
#   Android/Kotlin:   android/  spikes/  buildSrc/  gradle/
#                     build.gradle[.kts]  settings.gradle[.kts]
#                     gradle.properties  gradlew*  *.kt  *.kts
#                     AndroidManifest.xml  any res/ dir
#   Shared code:      contracts/  (canonical spec + conformance + vectors)
#
# Sourced by `.claude/hooks/check_codex_audit_artifact.sh` and by
# `.claude/hooks/__tests__/check_codex_audit_artifact.test.sh`.

# shellcheck disable=SC2120
code_paths_touched() {
    grep -qE \
'^(vreader/|vreaderTests/|android/|spikes/|contracts/|buildSrc/|gradle/)|(^|/)(build|settings)\.gradle(\.kts)?$|^gradle\.properties$|^gradlew|\.kts?$|(^|/)AndroidManifest\.xml$|(^|/)res/'
}
