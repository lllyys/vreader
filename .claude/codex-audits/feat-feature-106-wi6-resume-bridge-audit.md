---
branch: feat/feature-106-wi6-resume-bridge
threadId: 019eda-wi6-resume-2rounds
rounds: 2
final_verdict: ship-as-is
date: 2026-06-18
---

# Gate-4 audit — feature #106 WI-6 (resume bridge PLUMBING)

WI-6 ships the UI-free resume plumbing (the reader-host `locationDidChange`/
process-death wiring is design-blocked #1745): `ReadiumLocatorBridge` (Readium
Locator JSON ↔ `VReaderLocator` envelope) + `ResumeResolver` (precise-first /
canonical-fallback, the `contracts/identity/locator.md` resume rule). Pure JVM —
consumes the documented Readium Locator JSON shape, no Readium dependency. Room
save/restore of the envelope already shipped in WI-3.

Codex (gpt-5.4, high), 2 rounds.

## Round 1 — 1 High, 1 Medium, 1 Low (block-recommended)

| file | sev | issue | resolution |
|---|---|---|---|
| ResumeResolver.kt | **High** | `Precise(json)` discarded `legacyLocator`, so if the Readium anchor can't reapply on the device the contract's precise-then-canonical fallback is impossible through this API. | `ResumeTarget.Precise(readiumLocatorJSON, canonicalFallback: Locator?)` now carries the fallback; the resolver passes `envelope.legacyLocator`. Test `precise_carriesCanonicalFallback_forDegradedRestore`. |
| ReadiumLocatorBridge.kt | Medium | `toEnvelope` decoded unguarded — blank/malformed JSON threw a raw `SerializationException` out of the bridge with no defined degraded behavior. | Added typed `ReaderLocatorParseException`; decode wrapped in try/catch. Tests `toEnvelope_blankJSON_throwsTyped`, `toEnvelope_malformedJSON_throwsTyped`. |
| ReadiumLocatorBridge.kt | Low | `readiumLocatorJSON()` treated whitespace JSON as a present anchor, disagreeing with `ResumeResolver` (blank ⇒ absent). | Helper now `?.takeIf { it.isNotBlank() && engine == readium }`. Test `readiumLocatorJSON_nullForBlankAnchor`. |

## Round 2 — all resolved, no new findings (ship-as-is)

Auditor confirmed each fix on inspection; no still-open or new finding.

## Validation

- `scripts/run-android-tests.sh :app:testDebugUnitTest` → **SUCCEEDED**; reader
  tests `ReadiumLocatorBridgeTest` 8 + `ResumeResolverTest` 6 = 14, full `:app`
  suite 40, 0 failures.
- `contracts/conformance/run.sh kotlin` → **PASS** (unchanged — `:identity`
  untouched this WI).
- `android/app/build.gradle.kts` gained `kotlin.plugin.serialization` for the
  local `@Serializable` `ReadiumLocatorDto` (the cross-module `:identity`
  `@Serializable` types compiled there already; the in-`:app` DTO needs the plugin
  in `:app`). Auditor confirmed the addition correct and minimal.

## Verdict

**ship-as-is.** All round-1 findings (High + Medium + Low) resolved with tests;
zero open Critical/High/Medium after 2 rounds.
