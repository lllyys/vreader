---
branch: feat/feature-105-wi3-anchor-restore
threadId: 019ed3xx-multi
rounds: 3
final_verdict: ship-as-is
date: 2026-06-17
---

# Codex Gate-4 audit — feature #105 Spike B WI-3 (anchor / selection restore probes)

Runner: `scripts/run-codex.sh -m gpt-5.4 -e high`. Three rounds. The change: a
synthetic deterministic CJK fixture (`mini-cjk.epub`, 4 chapters x 24 unique CJK
paragraphs) + `AnchorRestoreTest` (3 instrumentation tests) probing whether
Readium-Kotlin 3.3.0 restores a saved reading position faithfully — the Android
analogue of the iOS #349/#352 restore saga. Like WI-2, the audit drove the
measurement from plausible to *sound and honestly reported*.

## Round 1 — 1 High + 2 Medium + 1 Low

| Finding | Sev | Resolution |
|---|---|---|
| `selectionRoundTrip` asserted only the JS textContent readback, not Readium — the "currentSelection reports exact text" claim was unproven | High | Hard-assert `navigator.currentSelection().locator.text.highlight` is non-null and contains the expected paragraph text. |
| Paragraph "drift" used a nearest-top-paragraph proxy — unsound; a correct restore could look 1-2 paras off | Medium | Measure the TARGET paragraph's own `getBoundingClientRect().top` + `visible` after restore (`targetViewport()`), not a proxy. |
| `anchorRestore…` had no scroll-mode guard and over-claimed "within-chapter" | Medium | Assert `navigator.settings.value.scroll`; rename to `chapterRestoreAndJsonRoundTrip` and scope it honestly to CHAPTER + JSON fidelity (Readium scroll-mode progression is resource-coarse, prog~0). |
| Fixture generator baked local wall-clock into the ZIP | Low | Fixed ZIP timestamps + fixed entry order; `mini-cjk.epub` verified byte-identical on regeneration. |

## Round 2 — High + 2 Medium + Low resolved; 1 Medium

| Finding | Sev | Resolution |
|---|---|---|
| `paragraphPreciseRestore`'s load-bearing assert was only `visible` — a several-paragraphs-off restore could still overlap the viewport and pass | Medium | Gate `offsetFrac` to the TOP THIRD ([0.0, 0.34)) in addition to `visible` — excludes above-fold / near-bottom landings. Correct the class rubric to state the MEASURED reality: fragment restore lands the target ~2 paragraphs (~18%) below the top, RECORDED as a #352-class hardening obligation, not over-claimed as same-paragraph-exact. |

R2 confirmed the High + the other 2 Mediums + Low resolved.

## Round 3 — CLEAN

Verdict verbatim: "CLEAN. No Critical/High/Medium findings." The auditor confirmed
the tightened gate "closes the prior loophole where 'visible anywhere' could still
pass a materially wrong restore" and the docs are "honest now … approximate/
top-of-viewport restoration with recorded imprecision, not same-paragraph
exactness", and that `[0.0, 0.34)` is "a defensible 'restore fundamentally works'
gate relative to the measured 0.180 … meaningful jitter headroom while still
rejecting above-fold and near-bottom placements." One Low (comment said exclusive
`< 0.34` but code used inclusive `0.0..0.34`) — fixed to `>= 0.0 && < 0.34`.

## Verdict

ship-as-is. Measured (android-35 arm64 emulator), all asserts green:
- **Chapter-level restore + Locator JSON round-trip: FAITHFUL** — `go(savedLocator)`
  returns to the exact href + progression, and the save→JSON→restore path the
  backup relies on preserves href/progression/totalProgression with faithful
  re-navigation.
- **Selection round-trip: WORKS** — a programmatically-injected DOM selection is
  surfaced by `currentSelection()` with the exact CJK paragraph text.
- **Fragment-level (paragraph-precise) restore: APPROXIMATE** — the target
  paragraph restores on-screen in the top third (~18% / ~2 paragraphs below the
  top), not pinned to the same paragraph. This is the **recorded #352-class
  engine-hardening obligation** for WI-4's engine decision — not engine-blocking
  (restore fundamentally works), but the real-port reader will need position
  re-hardening for exact restore on CJK.
