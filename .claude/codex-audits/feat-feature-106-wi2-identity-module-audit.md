---
branch: feat/feature-106-wi2-identity-module
threadId: 019ed723-3590-7241-8639-d03cf27ff897
rounds: 1
final_verdict: ship-as-is
date: 2026-06-18
---

# Gate-4 audit — feature #106 WI-2 (shared :identity module + conformance rewire)

WI-2 resolves the #106 Gate-2 High-1 finding (the Kotlin conformance lane proved
a standalone reference, not app code). Extracts `Identity.kt` (`Identity` +
`CanonicalLocator`) into a pure Kotlin/JVM `:identity` module in the Android
build; `:app` depends on it; the conformance test moved into `:identity:test`;
`contracts/conformance/run.sh` rewired to drive it; the duplicate standalone
`contracts/conformance/kotlin` build deleted.

Codex (gpt-5.4, high), 1 round. Session `019ed723-3590-7241-8639-d03cf27ff897`.

## Findings (3 Low, all fixed inline)

| file | sev | issue | resolution |
|---|---|---|---|
| IdentityConformanceTest.kt | Low | The fallback vectors path `"../../vectors"` was stale after the module move (only matters for ad-hoc/IDE runs; the Gradle lane always injects the sysprop). | Removed the fallback — `vreader.vectors.dir` is now REQUIRED with a clear error pointing at `run.sh kotlin`. |
| contracts/conformance/README.md | Low | Still described the deleted standalone `contracts/conformance/kotlin/` lane. | Updated to the shared `android/identity` `:identity:test` topology. |
| contracts/README.md | Low | Tree + status still referenced `contracts/conformance/kotlin`. | Updated to the shared `:identity` module + the rewired `run.sh`. |

## Confirmed correct (no higher-severity findings)

- **One Kotlin impl left** — `android/identity/.../Identity.kt`; `:app` depends on
  `project(":identity")` and the app smoke test imports it; `run.sh` runs
  `:identity:test`. The conformance lane + app build bind the SAME module, not a
  duplicate reference (the High-1 fix).
- **Pathing correct** — the `:identity` build injects `contracts/vectors` via
  `vreader.vectors.dir`; the test emits to `contracts/conformance/.out` exactly
  where `run.sh` cross-diffs (Swift-vs-Kotlin, bug #355).
- **Purity holds** — `:identity` has no Android/Readium deps; only Kotlin/JDK
  types. `outputs.upToDateWhen { false }` + `cleanTest` is redundant but safe.
- Kotlin/JVM toolchain pinning consistent with the app (2.3.20 / JDK 17).

## Validation

`:identity:test` + `:app:testDebugUnitTest` BUILD SUCCESSFUL;
`contracts/conformance/run.sh kotlin` → CONFORMANCE RESULT: PASS (drives the
shared module, emits the cross-diff output).

## Verdict

**ship-as-is.** The conformance lane now genuinely proves the app's identity code
(the shared `:identity` module `:app` consumes), with no duplicate reference; 3
Low doc/path findings fixed + re-verified green.
