# Feature #105 — Android Spike B: CJK WebView reader benchmark (instrumentation-first)

> Decomposed from the #102 Android-port umbrella per **ADR-0001**
> (`docs/decisions/0001-android-port-strategy.md`), the ADR's **Phase 1
> Spike B**. This de-risks **Risk 2** — the reader's hardest path
> (windowed continuous scroll over 1000+-spine CJK novels, memory /
> eviction, CFI / selection restore) on Android's more-variable System
> WebView, **before** committing to the WebView-engine plan.
>
> **Depends on #103 (Phase 0); independent of #104 (Spike A) once #103
> lands** (Codex Gate-2 High — ADR-0001 requires Phase 0 before ANY
> Android PR, and this spike's harness is Android/Kotlin code under
> `spikes/`, which Phase 0's gate routing + write-owner rules must cover
> first). Different risk from Spike A, so it can run in parallel with #104
> once #103 is merged. **Instrumentation/benchmark-driven, NOT
> UI-automation-dependent** — the cron's ability to drive an Android
> emulator/device is UNVERIFIED and the iOS verification stack (rule 47,
> `cron-prompts/verify.md`, `tdd-guardian`) does not transfer.

## Problem

vreader's hardest, most-bug-bearing surface is the continuous-scroll CJK
reader: the #83/#85 windowed stitching, eviction/compensation (#329
saga), anchor restore (#349/#352), and selection (#338/#350) were brutal
to get right **with full native control over the iOS scroll view +
WKWebView**. Android's System WebView is a *more variable target* than
WKWebView, and Readium-Kotlin's scroll/CFI/selection behavior on
1000+-spine CJK content is **UNVERIFIED**. Committing to the
WebView-engine plan before measuring this risks repeating the entire
#329-class saga on a weaker substrate.

Spike B answers: **can Readium-Kotlin (3.3.0) render a real 1000+-spine
CJK novel with acceptable scroll smoothness, bounded memory, stable
rendering, and working CFI/selection restore — measured, not assumed?**
A secondary deliverable is **standing up a minimally-automatable Android
verification lane** (the iOS one doesn't transfer).

## Scope

**In scope:**

1. A throwaway/harness Android module (instrumentation test or minimal
   benchmark host — NOT the product app) loading Readium-Kotlin 3.3.0.
2. **Two corpora (Codex Gate-2 Medium — one real book is weak for exact
   anchor assertions):** the real 1000+-spine CJK EPUB (道诡异仙 / 1042
   chapters) for the perf/memory/stability legs, PLUS a **tiny synthetic
   CJK EPUB with controlled char offsets** (3-5 short chapters, known
   exact offsets) for the deterministic anchor/selection-restore probes —
   the "controlled tiny structure a real book can't give cheaply"
   exception in the real-books-first rule. Mirrors the iOS `mini-cjk`
   fixture intent.
3. **Instrumented metrics**: scroll smoothness (frame timing / jank),
   memory + eviction behavior over a long sweep, renderer stability
   (crashes / blank frames), CFI + selection anchor restore correctness.
4. A **written viability verdict** + the metric baselines, and the
   **decision** on the Android reader engine (Readium-Kotlin scroll as-is,
   Readium-Kotlin + custom hardening, or a different approach).
5. A **minimally-automatable Android verification recipe** (macrobenchmark
   / instrumentation / `am` + logcat metrics) — the Spike-B process
   output the ADR calls for.

**Explicitly OUT of scope:**

- The product Android app, Compose chrome, library, persistence.
- Porting the iOS continuous-scroll coordinator (that's Phase 3
  "re-hardening", explicitly NOT a port).
- UI-automation-driven verification (the spike is instrumentation-first by
  mandate).
- Bilingual / highlights / TTS (later phases).

## Surface area (file-by-file, concrete)

- **`spikes/android-reader-bench/`** (Codex Gate-2 Medium — root PICKED,
  no longer "TBD"; this is the throwaway-harness root Phase 0 #103 chose,
  keeping `android/` reserved for the Phase-2 app shell). Concrete files:
  `spikes/android-reader-bench/build.gradle.kts` (Readium-Kotlin 3.3.0 +
  androidx.benchmark/macrobenchmark deps), `…/src/androidTest/.../ReaderScrollBenchmark.kt`
  (opens the corpus, drives a long programmatic scroll sweep, records
  `FrameTimingMetric` + memory), `…/src/androidTest/.../AnchorRestoreTest.kt`
  (the controlled anchor/selection probes on the synthetic fixture below),
  and a `settings.gradle.kts` registering the module.
- `dev-docs/verification/spike-b-android-reader-<date>.md` — the metric
  baselines + viability verdict (mirrors the iOS evidence-file shape).
- `docs/decisions/` — if the verdict changes the engine strategy, a short
  follow-up ADR or an ADR-0001 amendment note (the ADR invites this:
  "before committing to the WebView-engine plan").

## Prior art / project precedent / rejected alternatives

- **Precedent**: the iOS side has a mature instrumentation posture — the
  #96 Diagnostics export, the `b329-1px-sweep` harness, the
  continuous-scroll all-formats verification (`dev-docs/verification/…`).
  Spike B is the Android analogue: measure the scroll subsystem directly,
  don't eyeball it.
- **Precedent**: the 道诡异仙 1042-chapter book is already the canonical
  iOS large-CJK stress corpus — reuse it for apples-to-apples.
- **Rejected — assume Readium-Kotlin scroll "just works"**: the ADR
  flags 1000+-spine CJK perf/CFI parity as UNVERIFIED and the reader as
  "exactly where vreader is hardest"; assuming parity is the highest-risk
  move in the whole port.
- **Rejected — UI-automation-driven spike** (Espresso tapping through the
  reader): the ADR mandates instrumentation-first because the cron's
  Android UI-drive capability is unverified and UI automation would
  conflate "can't drive the UI" with "the reader is slow".

## Work-item sequencing

| WI | Deliverable | PR size | Tier |
|---|---|---|---|
| WI-1 | Minimal Gradle harness module loading Readium-Kotlin 3.3.0 + the corpus open path (proves the toolchain + dependency resolve) | Large (toolchain bring-up) | Spike |
| WI-2 | Instrumented scroll-sweep + memory/eviction + renderer-stability metrics over the 1000+-spine corpus | Large | Spike |
| WI-3 | CFI + selection anchor-restore correctness probes | Med | Spike |
| WI-4 | Viability verdict + baselines in a `dev-docs/verification/spike-b-…` evidence file + engine decision (ADR amendment if it changes strategy) + the minimally-automatable verification recipe | Med | Spike |

All WIs gate on an Android SDK + emulator/device + Readium-Kotlin
toolchain being available — a hard prerequisite the plan names explicitly
(shared with Spike A's WI-3+).

## Test catalogue

This spike's "tests" ARE the instrumentation:

- **Scroll smoothness**: frame timing / jank percentile over a sustained
  multi-hundred-chapter sweep (macrobenchmark `FrameTimingMetric` or
  equivalent).
- **Memory / eviction**: heap + native memory trajectory over the sweep;
  confirm bounded (no monotonic growth → the windowing analogue holds).
- **Renderer stability**: zero blank frames / WebView crashes over the
  sweep (logcat scan).
- **Anchor restore**: open at a deep position, scroll, reopen → lands at
  the saved position (the Android analogue of #349/#352); selection
  round-trip.

**Pass/fail rubric (Codex Gate-2 Medium — defined in the PLAN now, not
deferred to WI-1 after seeing results):**

- **Scroll smoothness**: ≤5% of frames over the 16.6ms budget (60fps) AND
  p90 frame time ≤ the iOS baseline × 1.5 over a sustained ≥200-chapter
  sweep. Below that → PASS; worse → engine-decision triggers.
- **Memory**: bounded — no monotonic native+heap growth across the sweep
  (eviction working), and zero OOM kills. Monotonic growth or an OOM →
  FAIL.
- **Renderer stability**: zero WebView crashes and zero blank/missing
  frames over the sweep. Any → FAIL.
- **Anchor/selection restore**: on the synthetic controlled-offset
  fixture, reopen lands within the SAME paragraph as saved (the iOS #352
  bar is exact; sub-paragraph drift is the acceptable Android v1 window),
  and a selection round-trips to the same char range. Larger drift → a
  recorded engine-hardening obligation.

These are measured against the iOS baseline captured in the same run where
feasible; a FAIL on memory/renderer is engine-blocking, a scroll/anchor
miss is a hardening obligation (not necessarily a strategy reopen).

## Risks + mitigations

- **R1 — Readium-Kotlin scroll is jank/memory-unacceptable on 1000+-spine
  CJK.** Outcome-defining (that's the spike). Mitigation paths captured in
  the verdict: custom windowing on top of Readium-Kotlin, a paginated-only
  Android v1, or (worst case) the engine-strategy reopens.
- **R2 — the cron can't drive an Android emulator at all.** Mitigation:
  instrumentation-first (macrobenchmark + `am instrument` + logcat) avoids
  UI automation; standing up that lane is itself a WI-4 deliverable, and a
  negative result ("no automatable Android verification yet") is a
  legitimate, recorded spike output that informs Phase 2 scoping.
- **R3 — toolchain bring-up cost** (Android SDK/NDK, emulator, Gradle,
  Readium-Kotlin) is the bulk of WI-1 and is UNVERIFIED on the build host.
  Mitigation: WI-1 is explicitly a spike (allowed to discover the
  toolchain doesn't cleanly stand up — that itself feeds the go/no-go).

## Backward compatibility

- Fully isolated: throwaway harness module; no product code, no iOS impact,
  no tracker-schema change. If the harness path lands under `android/` or
  `spikes/`, Phase 0's gate routing + write-owner rules apply.

## Acceptance criteria

1. A Readium-Kotlin harness opens the 1000+-spine CJK corpus on Android
   and a sustained scroll sweep is instrumented.
2. Scroll-smoothness, memory/eviction, renderer-stability, and
   anchor/selection-restore metrics are recorded against the iOS baseline.
3. A written **viability verdict + engine decision** lands in a
   `dev-docs/verification/spike-b-…` evidence file (with an ADR amendment
   if the strategy changes).
4. A **minimally-automatable Android verification recipe** is documented.
5. No product Android app, no iOS impact.

## Revision history

- v1 (2026-06-16) — initial Gate-1 draft from ADR-0001 Spike B.
- v2 (2026-06-16) — Gate-2 round 1 (Codex `019ed111`) applied: **High** —
  corrected the dependency (depends on #103; independent of #104 once #103
  lands); **Medium** — picked the harness root (`spikes/android-reader-bench/`)
  + named the module files; **Medium** — moved the pass/fail rubric
  (jank/memory/renderer/anchor thresholds) into the plan instead of
  deferring to WI-1; **Medium** — added a tiny synthetic controlled-offset
  CJK fixture for deterministic anchor/selection probes (keeping the real
  1042-chapter book for perf/memory).
