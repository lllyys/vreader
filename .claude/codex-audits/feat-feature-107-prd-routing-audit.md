---
branch: feat/feature-107-prd-routing
threadId: 019ed6f4-493b-7bc1-bc0a-0b876ffc14aa
rounds: 3
final_verdict: ship-as-is
date: 2026-06-18
---

# Gate-4 audit — feature #107 PR-D (platform routing + tdd-guardian false-green fix)

PR-D makes the workflow Android-aware: a platform-routing section on the
`/fix-issue` + `/feature-workflow` commands, SKIP-Android-until-ready on the 3
work crons, and — the executable piece — `scripts/tdd-guardian-test.sh`, a
platform-aware wrapper for the TDD Guardian (whose frozen iOS `xcodebuild`
testCommand previously false-greened Kotlin). The audit focused on the wrapper
(the markdown edits are docs).

Codex (gpt-5.4, high), 3 rounds. Sessions: r1 `019ed6f4-…`, r2 `019ed6f7-…`,
r3 `019ed6fa-…`.

## Round 1 — 1 High + 1 Medium

| file | sev | issue | resolution |
|---|---|---|---|
| tdd-guardian-test.sh | High | Detection used only `git diff HEAD` + `--cached` → a NEW untracked `android/Foo.kt` gave an empty diff → stayed `ios` → Kotlin false-green. | Added `git ls-files --others --exclude-standard` to the input; regression test creates an untracked `android/_probe.kt` and asserts refuse-to-green (exit 2). |
| tdd-guardian-test.sh | Medium | `android-app` checked `android/gradlew` OR `./gradlew` but always ran `./gradlew`. | Resolve `gradle_dir` (prefer `android/`, else root) and `cd "$gradle_dir" && ./gradlew`. |

Round 1 confirmed: iOS lane preserved for ios/shared/unknown/empty/classifier-
unavailable; no silent android-app→iOS fallthrough; `eval "$IOS_CMD"` is a static
literal (no injection); exit codes propagate.

## Round 2 — 1 Medium

| file | sev | issue | resolution |
|---|---|---|---|
| tdd-guardian-test.sh | Medium | A rename `android/Foo.kt -> docs/x.md` surfaced only the post-image (`docs/x.md`) → `shared` → iOS false-green. | Added `--no-renames` to both diffs: a rename becomes delete(OLD android path)+add(new path), so the Android pre-image stays in the input → `android-app`. |

Round 2 confirmed both round-1 findings resolved (ls-files doesn't pull ignored
build output; gradle_dir + ANDROID_CMD propagate failures non-green).

## Round 3 — CLEAN

"No findings. The round-2 rename false-green is resolved." No remaining
Critical/High/Medium false-green path in the platform detection.

## Validation

`scripts/__tests__/tdd-guardian-test.test.sh` — ALL PASS (android-app refuse-to-
green, android-spike routes Android, untracked-android-file routes Android, config
wired to the wrapper). PR-A classifier test + PR-B runner test still green.

## Verdict

**ship-as-is.** 3-round real Codex audit; the TDD-Guardian Kotlin false-green is
closed (untracked + rename + staged + working-tree detection), the iOS lane is
byte-for-byte preserved, and the command/cron routing makes every downstream
phase platform-aware without regressing iOS.
