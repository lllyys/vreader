---
branch: feat/feature-105-wi1-android-harness
threadId: 019ed305-9349-7463-8967-d09bff7d8e52
rounds: 1
final_verdict: ship-as-is
date: 2026-06-17
---

# Codex Gate-4 audit — feature #105 Spike B WI-1 (Android instrumentation harness)

Runner: `scripts/run-codex.sh -m gpt-5.4 -e high`. Session `019ed305`.

The change: the FIRST Android module to land in the iOS repo — a minimal
instrumentation harness under `spikes/android-reader-bench/` that builds +
installs + RUNS an `AndroidJUnit4` instrumentation test on the android-35
arm64 emulator. Purpose: prove the cron can drive an Android device
(ADR-0001 Risk, the Spike B precondition) — not a production feature. This
is the first `spikes/` PR through the Phase-0 audit gate (`spikes/` is a
gated code surface per `.claude/hooks/lib/code-paths.sh`).

## Round 1 — CLEAN

Verdict verbatim: "CLEAN. I did not find any audit findings in the
requested scope."

The auditor confirmed each focus area:

| Focus area | Result |
|---|---|
| Gradle/AGP/Kotlin config | `compileSdk 35` / `minSdk 26` / `targetSdk 35`, Java/JVM target 17, `testInstrumentationRunner = androidx.test.runner.AndroidJUnitRunner` all correct. **AGP 8.7.3 ↔ Kotlin 2.0.21 ↔ API 35 compatibility web-verified** against `developer.android.com/build/releases/agp-8-7-0-release-notes` + `/build/kotlin-support`. |
| Supply-chain / trust surface | Plugin versions explicit (no dynamic `+`/`latest.release`), AndroidX test versions explicit, wrapper `distributionUrl` pinned, `distributionSha256Sum` present. |
| Secrets / machine-local leakage | No `local.properties`, no `sdk.dir`, no absolute machine paths, no committed `build/` artifacts. |
| `.gitignore` | Correctly excludes `.gradle/`, `build/`, `local.properties`. |
| `SmokeTest.kt` | Real instrumentation assertion (installed package name + `Build.VERSION.SDK_INT` from the device runtime), not a no-op. |
| Clean-clone risk | None found. |

Independently corroborated before the audit: `gradle-wrapper.properties`
carries `distributionSha256Sum=f1771298…380d` (the official
`gradle-8.14.4-bin.zip` checksum, carried over from #104's R2 hardening),
`git ls-files` shows `local.properties` untracked, and `git grep /Users/ll`
over `spikes/android-reader-bench/` returns nothing.

## Verdict

ship-as-is. The instrumentation-first verification lane the ADR mandates for
Spike B is proven on a real emulator; the harness is the foundation the
Readium-Kotlin 1000+-spine CJK scroll/memory/anchor benchmark builds on.
