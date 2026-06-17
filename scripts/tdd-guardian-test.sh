#!/usr/bin/env bash
# Purpose: platform-aware test command for the TDD Guardian (feature #107 PR-D).
# The guardian's config previously hard-coded the iOS `xcodebuild` command, so a
# Kotlin change "passed" tests that never ran (a false-green). This wrapper
# classifies the changed files by platform (`code_paths_platform`) and routes:
#   ios | shared      → the iOS xcodebuild lane (unchanged behavior)
#   android-spike     → scripts/run-android-tests.sh (the spike emulator harness)
#   android-app       → scripts/run-android-tests.sh ./gradlew IF #106's app
#                       exists; ELSE FAIL LOUDLY (exit 2) — an android-app change
#                       must NOT green until the app + its tests are wired.
#
# Safety: anything that doesn't classify cleanly as Android runs the iOS lane, so
# the iOS guardian flow is identical to before.
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=.claude/hooks/lib/code-paths.sh
source "$REPO/.claude/hooks/lib/code-paths.sh" 2>/dev/null || true

IOS_CMD="DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild build-for-testing -project vreader.xcodeproj -scheme vreader -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test-without-building -project vreader.xcodeproj -scheme vreader -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:vreaderTests -disable-concurrent-testing"

# Classify the working-tree + staged changes. If the classifier is unavailable
# or there are no changes, fall through to the iOS lane (preserve old behavior).
# TDD_FORCE_PLATFORM is a test seam (unset in production → git-based detection).
platform="${TDD_FORCE_PLATFORM:-ios}"
if [ -z "${TDD_FORCE_PLATFORM:-}" ] && declare -f code_paths_platform >/dev/null 2>&1; then
    # Tracked-unstaged + staged + UNTRACKED (Codex Gate-4 High: a brand-new
    # `android/Foo.kt` that isn't `git add`ed yet must still classify Android, or
    # a Kotlin change false-greens on the iOS lane via an empty diff).
    # --no-renames (Codex Gate-4 Medium): a rename surfaces as delete(OLD path) +
    # add(NEW path), so a `android/Foo.kt -> docs/x.md` rename keeps the Android
    # source path in the input and still classifies android-app (rather than only
    # the post-image `docs/x.md` → shared → iOS false-green).
    changed="$( {
        git -C "$REPO" diff --no-renames --name-only HEAD
        git -C "$REPO" diff --no-renames --cached --name-only
        git -C "$REPO" ls-files --others --exclude-standard
    } 2>/dev/null )"
    if [ -n "$changed" ]; then
        platform="$(printf '%s\n' "$changed" | code_paths_platform)"
    fi
fi

case "$platform" in
    android-spike)
        echo "[tdd-guardian] android-spike change → scripts/run-android-tests.sh"
        exec bash "$REPO/scripts/run-android-tests.sh"
        ;;
    android-app)
        # Run gradlew from the dir that actually contains it (Codex Gate-4 Medium:
        # if #106 lands the wrapper under android/, invoke it there, not at root).
        gradle_dir=""
        [ -f "$REPO/android/gradlew" ] && gradle_dir="$REPO/android"
        [ -z "$gradle_dir" ] && [ -f "$REPO/gradlew" ] && gradle_dir="$REPO"
        if [ -n "$gradle_dir" ]; then
            echo "[tdd-guardian] android-app change → ./gradlew unit tests (in $gradle_dir)"
            ANDROID_CMD="cd \"$gradle_dir\" && ./gradlew :app:testDebugUnitTest" exec bash "$REPO/scripts/run-android-tests.sh"
        fi
        echo "TDD-GUARDIAN: android-app change but no Android app shell yet (feature #106) — Kotlin tests cannot be asserted; refusing to green." >&2
        exit 2
        ;;
    *)
        eval "$IOS_CMD"
        ;;
esac
