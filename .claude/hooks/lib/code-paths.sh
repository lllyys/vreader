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

# Reads paths on stdin (one per line), returns 0 iff any is a code path.
# Implemented as a read-all-stdin `case` classifier (NOT `grep -q`): under
# `set -o pipefail`, `grep -q` exits on the FIRST match and the upstream
# `printf` gets SIGPIPE, flipping a real code list back to a nonzero
# (fail-OPEN) exit (Codex Gate-4 High). This loop consumes ALL input, so
# the result is pipefail-safe. It also applies DOCS/META exclusions FIRST,
# so a `docs/`-prefixed path that happens to end in `.kt` or contain
# `res/` is NOT over-gated as code (Codex Gate-4 Medium).
# shellcheck disable=SC2120
code_paths_touched() {
    local path found=1
    # IMPORTANT: this loop reads stdin to EOF and NEVER `break`s early
    # (Codex Gate-4 round 2 High). An early break leaves the producer's
    # remaining writes unconsumed → SIGPIPE → a nonzero pipeline exit under
    # `set -o pipefail` even though code was found (fail-OPEN). Reading all
    # input makes the pipeline's exit status the classifier's own return.
    while IFS= read -r path; do
        [ -n "$path" ] || continue
        # Docs/meta roots + root-level meta files — never audit-required,
        # regardless of any code-looking suffix. (contracts/README.md is
        # NOT excluded here — it's under the contracts/ CODE root below.)
        case "$path" in
            docs/*|dev-docs/*|.claude/rules/*|.claude/hooks/*|.claude/skills/*|.claude/cron-prompts/*) continue ;;
            README*|LICENSE*|AGENTS.md|CLAUDE.md) continue ;;
        esac
        case "$path" in
            # Code roots (iOS + Android/Kotlin + shared contracts/)
            vreader/*|vreaderTests/*|android/*|spikes/*|contracts/*|buildSrc/*|gradle/*) found=0 ;;
            # Kotlin sources anywhere
            *.kt|*.kts) found=0 ;;
            # Gradle build files anywhere
            build.gradle|build.gradle.kts|settings.gradle|settings.gradle.kts) found=0 ;;
            */build.gradle|*/build.gradle.kts|*/settings.gradle|*/settings.gradle.kts) found=0 ;;
            gradle.properties|gradlew|gradlew.*) found=0 ;;
            # Android manifest + resources anywhere
            AndroidManifest.xml|*/AndroidManifest.xml) found=0 ;;
            res/*|*/res/*) found=0 ;;
        esac
    done
    return "$found"
}
