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

# Feature #107 WI-1 (PR-A) — path→PLATFORM classifier for workflow routing.
#
# Reads a newline-separated changed-path list on stdin and emits ONE platform
# token on stdout — the routing lane resolved by precedence:
#
#     android-app  >  android-spike  >  ios  >  shared
#
# This is DISTINCT from `code_paths_touched` (a boolean Gate-4 audit gate, per
# AGENTS.md "a boolean gate, not a full ownership taxonomy"). Routing is PURELY
# PATH-BASED — no tracker metadata field (Gate-2 r3 resolution): write-isolation
# (rule 48) guarantees an Android-app PR's path set already contains `android/`/
# `*.kt`/Gradle files (→ `android-app`); a shared-only PR returns `shared`, which
# consumers route to the iOS lane (rule 40: "shared → iOS while Android is
# pre-foundation"). `scripts/` is `shared` (iOS bump/gate, correct per rule 40).
#
# Ownership matches the full AGENTS / rule-40 set:
#   android-app  : android/ buildSrc/ gradle/ *.kt[s] build.gradle[.kts]
#                  settings.gradle[.kts] gradle.properties gradlew* res/
#                  AndroidManifest.xml
#   android-spike: spikes/
#   ios          : vreader/ vreaderTests/ *.xcodeproj project.yml
#   shared       : everything else (docs/ contracts/ .claude/ scripts/ root docs)
#
# Sourced by `.claude/skills/{fix-issue,feature-workflow}` + commands + crons
# (PR-D) and by `.claude/hooks/__tests__/code_paths_platform.test.sh`.
# shellcheck disable=SC2120
code_paths_platform() {
    local path has_app=1 has_spike=1 has_ios=1
    while IFS= read -r path; do
        [ -n "$path" ] || continue
        # ROOT-FIRST ordering (Codex Gate-4): classify by ROOT before any generic
        # suffix/name match, so a `spikes/Foo.kt` is `android-spike` (not
        # `android-app` via its `.kt` suffix) and a `docs/example.kt` /
        # `scripts/build.gradle` is `shared` (not mis-shaped as code by suffix).
        case "$path" in
            # Shared / docs / meta roots FIRST — never a platform, any suffix.
            docs/*|dev-docs/*|.claude/*|scripts/*|contracts/*) continue ;;
            README*|LICENSE*|AGENTS.md|CLAUDE.md) continue ;;
            # Spike root — exclusive, before the generic Android suffix matches.
            spikes/*) has_spike=0 ;;
            # iOS roots.
            vreader/*|vreaderTests/*|project.yml) has_ios=0 ;;
            *.xcodeproj|*.xcodeproj/*) has_ios=0 ;;
            # Android-app roots.
            android/*|buildSrc/*|gradle/*) has_app=0 ;;
            # Rootless Android-shaped files (only reached when no root above hit).
            *.kt|*.kts) has_app=0 ;;
            build.gradle|build.gradle.kts|settings.gradle|settings.gradle.kts) has_app=0 ;;
            */build.gradle|*/build.gradle.kts|*/settings.gradle|*/settings.gradle.kts) has_app=0 ;;
            gradle.properties|gradlew|gradlew.*) has_app=0 ;;
            AndroidManifest.xml|*/AndroidManifest.xml) has_app=0 ;;
            res/*|*/res/*) has_app=0 ;;
            # else → shared (rootless non-code / unknown)
        esac
    done
    if [ "$has_app" -eq 0 ]; then echo "android-app"
    elif [ "$has_spike" -eq 0 ]; then echo "android-spike"
    elif [ "$has_ios" -eq 0 ]; then echo "ios"
    else echo "shared"; fi
}
