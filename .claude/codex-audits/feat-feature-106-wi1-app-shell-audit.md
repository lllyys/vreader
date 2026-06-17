---
branch: feat/feature-106-wi1-app-shell
threadId: 019ed716-e16e-7443-9f8f-2c97fe4584a2
rounds: 1
final_verdict: ship-as-is
date: 2026-06-18
---

# Gate-4 audit — feature #106 WI-1 (the first real Android app shell)

WI-1: a self-contained Gradle project under `android/` (Kotlin/Compose) — the
first real vreader Android app. Toolchain pinned to the Spike-B-verified set, a
Compose `MainActivity` + empty "Library" screen, `android/version.properties` →
BuildConfig, a Robolectric version-wiring smoke test. Built + tested green
(`:app:testDebugUnitTest` BUILD SUCCESSFUL, directly and via
`scripts/run-android-tests.sh`).

Codex (gpt-5.4, high), 1 round. Session `019ed716-e16e-7443-9f8f-2c97fe4584a2`.

## Findings (both fixed inline + verified green)

| file:line | sev | issue | resolution |
|---|---|---|---|
| VersionWiringTest.kt | Medium | The smoke test hardcoded `0.1.0`/`1` — a version PIN, not a wiring proof; would fail on every legitimate bump and pass if values were hardcoded elsewhere. | Test now READS `../version.properties` at test time (Gradle workingDir = the module dir) and compares the parsed `versionName`/`versionCode` to `BuildConfig.VERSION_NAME`/`VERSION_CODE` — proves the chain, survives bumps. |
| app/build.gradle.kts | Low | `version.properties` read via raw file I/O at configuration time — not a tracked Gradle provider input, so the configuration cache could stale it. | Switched to `providers.fileContents(rootProject.layout.projectDirectory.file("version.properties")).asText.get()` (a tracked provider). |

## Confirmed correct (no findings)

- Toolchain pins match the Spike-B rationale (AGP 8.13.2 / Kotlin 2.3.20 / Gradle
  8.14.4 / JDK 17 / compileSdk+targetSdk 36 / minSdk 26 / core-library
  desugaring) — nothing blocks WI-5's Readium-Kotlin 3.3.0 consumption.
- `MainActivity.kt` is a correct minimal Compose shell (no state leak / misuse).
- `robolectric.properties sdk=34` is sound for a BuildConfig-only smoke (the app
  still targets 36; only the simulated SDK runtime is 34).
- `.gitignore` covers `android/.gradle/`/`local.properties`/build outputs; the
  Gradle wrapper jar is correctly committed; no stray local-only files.

## Verdict

**ship-as-is.** The first Android app builds + tests green from scratch via the
#107 tooling; both audit findings (a tautological smoke test + a config-cache
hazard) fixed inline and re-verified green.
