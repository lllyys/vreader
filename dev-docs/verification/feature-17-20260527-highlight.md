---
kind: feature
id: 17
status_target: DONE
commit_sha: 32181c074d3096b68b95350502e717062e206df4
app_version: 3.39.58 (build 679)
date: 2026-05-27
verifier: claude
device_or_simulator: iPhone 17 Pro Simulator
os_version: iOS 26.4
build_configuration: Debug
backend: n/a
result: partial
---

# Feature #17 — PDF highlight create→render→persist device verification (via the pdf-highlight driver)

Device-verifies #17's criterion 1 (selection-driven highlight → PDFAnnotation that renders +
persists) at the create/render/persist level, using the new `vreader-debug://pdf-highlight`
driver (v3.39.58) that injects a highlight via the SAME production path the long-press-drag
gesture uses (`handleHighlightAction` → `HighlightCoordinator.create` → `addHighlight` +
`PDFAnnotationBridge.createHighlightFromAnchor`). A bridge highlight is byte-identical to a
gesture one at the same (page, rect).

`result: partial` — #17 stays `DONE`. This closes the create/render/persist gap; the sole
residual is the raw long-press-drag touch input (PDFKit's selection gesture firing
`selectionDidChange`), which is real-device/CU-only (analogous to #71's raw-scroll residual).

## Acceptance criteria (the highlight slice)

| # | Criterion | Observed | Result |
|---|---|---|---|
| 1 (create) | Selection → PDFAnnotation on the correct page | `pdf-highlight?page=0&rect=0.1,0.3,0.8,0.4` created a highlight on page 0 (no no-op log) | pass |
| 1 (render) | Highlight renders | Yellow highlight visibly painted over the central text band (artifact `feature-17-pdf-highlight-rendered-20260527.png`) | pass |
| 1 (persist) | Highlight persists | Survived close → reopen (still rendered after re-`open` — restored from `HighlightRecord`) | pass |
| 1 (faithfulness gate) | No highlight where no text | `rect=0.12,0.18,0.7,0.04` (over a line-gap/margin) → log "no text under rect — not creating" (mirrors the gesture's non-empty-selection gate) | pass |
| 8 (theme) | gutter flips light/dark | verified `feature-17-20260527.md` | pass |
| 7 (page round-trip) | page indicator | "Page 1 of 6" verified `feature-17-20260527.md` | pass |
| 2–6 | color map / multi-line / normalized rects / restore-defensive / ViewModel | 157-test slice (`feature-17-20260507.md`) | pass |

## Commands run

```bash
UDID=61149F0E-DC18-4BE2-BB37-52659F1F4F62
xcrun simctl launch "$UDID" com.vreader.app
xcrun simctl openurl "$UDID" "vreader-debug://reset"
xcrun simctl openurl "$UDID" "vreader-debug://seed?fixture=multi-page-pdf"
xcrun simctl openurl "$UDID" "vreader-debug://open?bookId=pdf:8544a14e…:23685"
xcrun simctl openurl "$UDID" "vreader-debug://pdf-highlight?page=0&rect=0.1,0.3,0.8,0.4&color=yellow"  # creates + renders
xcrun simctl openurl "$UDID" "vreader-debug://open?bookId=pdf:8544a14e…:23685"  # reopen → highlight restored
# screenshots before / after / reopen
```

## Observations

- The faithfulness gate works on device: a rect over a line-gap/margin no-ops (no phantom
  highlight); a rect over real glyphs creates + renders + persists.
- The create/render/persist all run through production code (no parallel routine), so a bridge
  highlight equals a gesture highlight.

## Residual (CU / real-device only)

- The raw long-press-drag text SELECTION gesture (UIKit/PDFKit producing the `PDFSelection`
  that `PDFViewBridge.selectionDidChange` consumes). Everything DOWNSTREAM of the selection is
  now device-verified; only the touch→selection platform mechanism is unexercised CU-free.
  Confirm on a real device / with CU to flip #17 → VERIFIED.

## Artifacts

- `dev-docs/verification/artifacts/feature-17-pdf-highlight-rendered-20260527.png`
- Driver: `.claude/codex-audits/feat-debugbridge-pdf-highlight-driver-audit.md` (v3.39.58, 3 rounds).
