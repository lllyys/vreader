---
branch: feat/156-wi-0-spike
threadId: 019fd20c-7719-7b00-b68d-6b96d1bbc766
rounds: 3
final_verdict: ship-as-is
date: 2026-08-05
scope: feature #156 WI-0 — justification measurement spike (M1–M4); no production code
---

# Codex audit — feature #156 WI-0 (measurement spike)

**Final verdict: ship-as-is** (round 3, `gpt-5.6-sol`).

Sessions: r1 `019fd20c-7719-7b00-b68d-6b96d1bbc766`, r2 (same thread family),
r3 `019fd220-c158-79d3-8225-e6ac5101c154`. Raw transcripts in the lane's
`.reports/audit-r{1,2,3}.txt` (not committed — long, path-referenced per rule 55).

## What was audited

The whole WI-0 change set — two Android connected test classes and one test asset.
**No production code exists in this branch by design**: WI-0 is a measurement that
decides whether WI-1/2/3 proceed as written.

- `android/app/src/androidTest/kotlin/com/vreader/app/reader/JustificationMeasurementSpikeTest.kt` (M1, M2)
- `android/app/src/androidTest/kotlin/com/vreader/app/reader/JustificationEpubStyleSpikeTest.kt` (M3, M4)
- `android/app/src/androidTest/assets/latin-justify-sample.txt` (M2's Latin control fixture)

The audit prompt was aimed at the one thing that can make this WI worthless, since
**three of its four results are negatives**:

1. Can any measurement be satisfied without reading a post-layout / post-render number?
2. Does M2 genuinely exercise the same Compose path as M1, so that M2 passing validates M1's harness?
3. Could M1's "no movement" be produced by a **broken harness** rather than by the engine?

## Round 1 — 2 High, 5 Medium, 3 Low

| # | Sev | Finding | Disposition |
|---|---|---|---|
| H1 | High | `settledProbe()` treated the DOM as settled when the `<html>` inline style merely stopped changing — it could return the OLD state before `submitPreferences` / the store collector applied anything, self-fulfilling M4's inert-slider result and M3's negatives | **Fixed** — takes a required-state predicate naming the exact `--USER__*` declarations and the `readium-advanced-on` gate that must be live; a state that never arrives is an explicit failure |
| H2 | High | M3/zh asserted only "not justify", so it could pass while measuring an error object, a stale DOM, the wrong resource, the wrong language or the wrong stylesheet | **Fixed** — asserts positively: `found`, `lang` starts with `zh`, `cjk-horizontal/ReadiumCSS-after.css` resolved, body is a real `start`/`left` value, same resource + element across all three states |
| M1 | Medium | Invalid/error JSON could be reported as a reading; `optString` turns absent values into empty strings, letting M4's `bh2 != bh0` pass on an empty `bh2` | **Fixed** — error objects rejected in the probe loop; every line-height reading asserted to be a real `px` length before comparison |
| M2 | Medium | `submit()` silently no-opped if the navigator lookup failed — submitting nothing then measuring "no change" manufactures the negative | **Fixed** — a missing navigator is a hard failure |
| M3 | Medium | `evalJs` ignored `done.await`'s boolean, so a late completion could surface as a stale reading | **Fixed** — per-call `AtomicReference`, read only on successful await |
| M4 | Medium | The probe re-selected its element every sample with no resource/element identity across states | **Fixed** — `docHref` + `textHead` recorded and asserted identical across states |
| M5 | Medium | M1's positive-control gate was procedural; a filtered run could publish an uninterpretable M1 | **Fixed** — method order pinned, M2 sets a static flag M1 requires |
| L1 | Low | Pixel capture was best-effort and could silently degrade the evidence to one signal | **Fixed** — mandatory in both M1 and M2 |
| L2 | Low | Weak real-TXT identity; no requirement that the measured paragraph is CJK | **Fixed** — ≥80% CJK-script assertion |
| L3 | Low | The anchor substring was not uniqueness-checked | **Fixed** — asserted to match exactly one node |

## Round 2 — all round-1 findings CLOSED; 1 new Medium, 1 Low

| # | Sev | Finding | Disposition |
|---|---|---|---|
| M6 | Medium | The **baselines** (M3's `default`, M4's `before`) still came from the permissive `settledRaw()` sampler via `advanceToProse()`, so a transitional sample could become the value later comparisons are measured against — M4's "slider is inert" could still be harness-produced | **Fixed** — `advanceToProse()` uses the permissive sampler only to navigate, then re-reads the baseline through the strict `settledProbe()` with a caller-supplied predicate (M3: gate OFF; M4: `--USER__lineHeight: 1.5` live AND gate OFF) |
| L4 | Low | EPUB element identity is resource path + 40-char text prefix rather than a stable element handle | **Accepted with rationale** (recorded in code): the probe is deliberately read-only, and minting an id would mutate the very DOM under measurement. Round 3 confirmed the acceptance is reasonable and "does not need fixing" |

## Round 3 — final

Verified M6 closed at `JustificationEpubStyleSpikeTest.kt:292/302` with the M3
predicate at `:359` and the M4 predicate at `:497-499`; confirmed **"no path remains
for the permissive sample itself to become M3's `default` or M4's `before`."**
Confirmed the fix introduced no new defect: navigation bounded to 30 iterations,
settlement to 60 probes, no double-counted page turns, no autonomous page turn
between the navigation sample and the strict re-read, and an unsatisfiable baseline
predicate fails explicitly rather than yielding stale evidence.

Round-3 answers to the three core questions:

- **M1 (CJK does not move)** — "No credible harness-produced false negative remains
  in the inspected code. The alignment request is confirmed in `TextLayoutResult`,
  anchor uniqueness is enforced, M2 mechanically gates M1, and mandatory pixel
  evidence agrees with line geometry."
- **M2 (Latin moves)** — "No material false-positive path found."
- **M3/M4** — post-submit readings strict and positive-valued; baselines now equally strict.

**FINAL VERDICT: ship-as-is.** No blocking or follow-up findings.

## A finding the audit did not have to catch — the control caught it itself

M2 was designed as three "independent" signals. It measured
`getBoundingBox().left` as **completely unchanged on every line while 191,965
pixels demonstrably moved** — i.e. Compose's `getBoundingBox` /
`getHorizontalPosition` do not reflect justification (unlike `getLineRight`,
which resolves through `Layout.getLineExtent` → `TextLine.justify`). Had that
signal been trusted, M1's identical silence would have looked like corroboration
of "CJK is inert" when it was actually an API that cannot report movement at all.
The signal is now pinned by M2 as a known-blind API and explicitly excluded from
M1's evidence. This is the positive control doing precisely the job §7.1 gives it.

## Measurements (all green, 0 skipped, emulator-5554 / API 35)

- **M1** real `黑暗血时代.txt` via the production `TxtBody`: 0 of 19 non-final lines moved; `getLineRight` identical; **0 of 974×1420 pixels differ**.
- **M2** synthetic Latin, identical path: 14/14 non-final lines moved, ragged 804–958px → flush 973–974px at the 974px layout width; 191,965 pixels differ.
- **M3/en**: `textAlign=JUSTIFY` alone → computed `start`; with `publisherStyles=false` → `justify` + `hyphens: auto`.
- **M3/zh**: `cjk-horizontal/ReadiumCSS-*.css` resolved; body `start` in all three states (its `<p>` is already `justify` from the publisher's own CSS).
- **M4**: production slider moved `--USER__lineHeight` 1.5 → 2.0 while computed line-height stayed **24.2109px**; same value with `publisherStyles=false` → **32px** (= 16px × 2.0). **Bug #367 confirmed.**

## Known deviations disclosed

- **Two test classes instead of one.** The Compose (M1/M2) and WebView (M3/M4) lanes need different rules (`createComposeRule` + `setContent` vs `ActivityScenario` + a Readium fragment) and must run as separate connected invocations anyway (one class per run). Splitting also keeps each file focused.
- **File length.** Both files exceed the ~300-line guidance (≈330 and ≈560 lines). For a spike whose deliverable *is* the reasoning, the KDoc carrying the method, the invalidated signal and the acceptance logic is load-bearing; repo precedent for a long connected measurement file is `TxtPaginatorPerfBenchmark.kt` (545 lines).
