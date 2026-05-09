---
kind: feature
id: 27
status_target: VERIFIED
commit_sha: 876e4941215337379efb0474a087d8037aa23d55
app_version: 3.14.115 (build 224)
date: 2026-05-09
verifier: claude
device_or_simulator: iPhone 17 Pro Simulator
os_version: iOS 26.4
build_configuration: Debug
backend: bundled DebugFixtures (mini-epub3.epub) + active "Lorem ipsum" → "REPLACED_LOREM" replacement rule
result: pass
---

## Summary

Round-3 verification of feature #27 (Content replacement rules) is the
follow-up to round-2's `blocked` outcome (`feature-27-20260509.md`),
which was gated on bug #158 / GH #468 (Unified TXT renderer broken).
That bug shipped in v3.14.115 via cheap-path capability-gate (TXT no
longer has `.unifiedReflow`; picker hidden for TXT) — see
`bug-158-postmerge-txt-no-reading-mode-picker-20260509.png`.

The round-3 plan pivoted away from TXT (which is now correctly
hidden from Unified) and instead drove the rule against an EPUB —
the format that DOES have a working Unified pipeline. **Result:
PASS.** The rule "Lorem ipsum" → "REPLACED_LOREM" applied at render
time against `mini-epub3.epub` Chapter One in Unified mode.

This closes the long-standing real-render gap that round-1
(2026-05-07, `partial`) and round-2 (2026-05-09, `blocked`) left
open. Status moves DONE → **VERIFIED**.

## Acceptance criteria

| Criterion | Slice | Result |
|---|---|---|
| `ReplacementTransform` applies rule pipeline (data layer) | 14 unit tests in `ReplacementTransformTests` | PASS (round-1 cross-ref) |
| Production wiring: rule pipeline built when readingMode == .unified | Code-read at `ReaderContainerView.swift:194-197` + `loadReplacementRules` in `+Sheets.swift:97`; capability guard added in v3.14.115 (`ReaderContainerView.swift:252`) | PASS |
| Native-mode no-op (bug #128 documented behavior) | round-2 cross-ref: war-and-peace.txt at 47% in Native mode renders "Pierre" unchanged | PASS |
| Bug #128 banner reachable + correct copy | This round: Settings → Replacement Rules — banner reads "Rules apply only when reading in Unified mode (currently EPUB, MD, AZW3 — not TXT or PDF). Switch from the reader's Settings → Reading Mode." | PASS (post-#158 banner update verified live) |
| Bug #158 capability-gate hides Unified for TXT | This round: war-and-peace.txt → AA → no Reading Mode picker visible | PASS (post-merge verify cross-ref) |
| **Unified-mode end-to-end: rule applied at render time on a fixture containing the pattern** | This round: mini-epub3.epub Chapter One in Unified mode renders "Second paragraph. **REPLACED_LOREM** dolor sit amet…" instead of "Lorem ipsum dolor sit amet" | **PASS** |

## Commands run

```bash
SIM=61149F0E-DC18-4BE2-BB37-52659F1F4F62
# v3.14.115 (commit 876e494) installed from previous bug-158 close-gate iteration.

xcrun simctl terminate $SIM com.vreader.app
xcrun simctl openurl $SIM "vreader-debug://reset"
sleep 2
xcrun simctl openurl $SIM "vreader-debug://seed?fixture=mini-epub3"
sleep 2
xcrun simctl launch $SIM com.vreader.app

# UI driving via computer-use:
# 1. Settings (gear icon) → Replacement Rules
#    — Confirmed banner copy contains "(currently EPUB, MD, AZW3 — not TXT or PDF)"
#    — Pre-existing "Pierre" → "Peter" rule still saved (SwiftData store survives debug reset; rules are per-app, not per-library).
# 2. + → Pattern field: write_clipboard("Lorem ipsum") + cmd+v
#    Replacement field: write_clipboard("REPLACED_LOREM") + cmd+v
#    Save → row "Lorem ipsum → REPLACED_LOREM" appears with Global tag, enabled.
# 3. Done → back to Library → tap mini-epub3 card.
# 4. Reader opens in Native mode (Chapter 1 of 2, bottom chrome visible).
# 5. AA → Reading Settings panel → Reading Mode picker IS shown (EPUB has .unifiedReflow capability).
# 6. Tap Unified — picker switches; visible text in current viewport still shows
#    "Lorem ipsum dolor sit amet" verbatim. (Rule pipeline only loads at .task time
#    in `ReaderContainerView`; switching modes mid-session doesn't re-run .task.)
# 7. Force-quit + relaunch app: `simctl terminate` + `simctl launch`. Unified mode is
#    now persisted; re-opening mini-epub3 triggers .task → loadReplacementRules → pipeline built.
# 8. Open mini-epub3 again → reader renders Chapter One in Unified mode showing:
#    "Second paragraph. REPLACED_LOREM dolor sit amet, consectetur adipiscing elit. ..."
#    "Third paragraph with some emphasized and strong markup..."
#    "Chapter Two — The second chapter exists so navigation between chapters can be tested..."
#    "End of fixture."
#
# Capture evidence
xcrun simctl io $SIM screenshot \
  dev-docs/verification/artifacts/feature-27-r3-unified-epub-rule-applied-20260509.png
```

## Observations

- **Rule applies at render time in Unified+EPUB.** The visible
  "Second paragraph. REPLACED_LOREM dolor sit amet…" confirms the
  `ReplacementTransform` is active in `unifiedCoordinator.activeTransforms`
  for simple-EPUB Unified rendering.
- **Mode-switch UX caveat (NOT a bug, but worth documenting).** The
  rule pipeline is loaded once in `.task` when the reader opens with
  `readingMode == .unified`. Switching modes mid-session does not
  trigger a reload. To make a newly-saved rule apply, the user must
  save the rule, switch to Unified, then close+reopen the book (or
  app). This matches the existing `loadReplacementRules` design and
  is not introduced by the bug #158 fix. If the UX is judged
  problematic, a separate bug/feature should propose `.onChange(of:
  settingsStore.readingMode)` to refresh the rule pipeline when
  the mode flips. Filing as a low-priority follow-up is appropriate
  but **not done in this iteration** (verify-cron scope).
- **Bug #158 fix verified working.** Cross-ref: war-and-peace.txt
  shows no Reading Mode picker. mini-epub3.epub shows the picker
  (capability-gated correctly).
- **Bug #128 banner copy update verified live.** The Settings →
  Replacement Rules banner now reads exactly the post-#158 copy:
  "Rules apply only when reading in Unified mode (currently EPUB,
  MD, AZW3 — not TXT or PDF). Switch from the reader's Settings →
  Reading Mode."
- **No new bugs surfaced this round.** The mode-switch caveat is a
  known limitation, not a defect — and it was correctly handled by
  app-restart in this verification.

## Artifacts

- `dev-docs/verification/artifacts/feature-27-r3-unified-epub-rule-applied-20260509.png`
  — mini-epub3 Chapter One in Unified mode rendering "REPLACED_LOREM
  dolor sit amet" (rule applied at render time).

## Verdict

`pass` for the Unified-mode real-render leg of feature #27 against a
non-TXT fixture. Combined with round-1's data-layer slice (14
`ReplacementTransformTests`) and round-2's Native-mode no-op
confirmation, the feature now has end-to-end coverage of:

1. Data-layer: 14 unit tests for `ReplacementTransform`.
2. Production wiring: rule pipeline gate (`readingMode == .unified
   && capabilities.contains(.unifiedReflow)`).
3. Native-mode no-op (bug #128 documented).
4. Real render: rule visibly substitutes text in Unified+EPUB.

**Feature #27 status: DONE → VERIFIED.** GH #397 close-gate satisfied.
