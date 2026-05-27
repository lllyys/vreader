---
branch: verify/feature-17-pdf-fixture-render-theme
threadId: 019e6920-5950-7dc1-800a-1121a5448f4c
rounds: 1
final_verdict: ship-as-is
date: 2026-05-27
---

# Codex Audit — Feature #17 PDF fixture (render/theme verification harness)

Gate-4 audit for the `multi-page-pdf` DebugFixtureCatalog fixture that unblocks
Feature #17 PDF render/theme CU-free verification.

Change: new `multi-page-pdf.pdf` (6-page text-layer PDF via cupsfilter) +
one `DebugFixtureCatalog` entry (`format: .pdf`) + `DebugFixtureCatalogTests`
name-set update + the `DebugFixtures/README.md` provenance row.

## Round 1 — findings

| file:line | severity | issue | resolution |
|---|---|---|---|
| DebugFixtures/README.md:8 | Low | New fixture not listed in the provenance/licensing table (README requires a row per fixture). | Fixed — added the `multi-page-pdf.pdf` row + backfilled two pre-existing gaps (`mini-markdown.md`, `multi-chapter-epub.epub`). |

Codex confirmed the catalog entry name/resource/extension + `.pdf` enum case
are correct, the directory-wide `rsync` Debug-only bundle-copy needs no extra
Xcode resource registration, and the Release gate
(`verify-release-no-debugbridge.sh`) still rejects any leaked fixture.

## Verdict

**ship-as-is.** Zero Critical/High/Medium; the one Low (README provenance) is
fixed. Round-1 reply: "Clean to ship … The README provenance table now covers
the new PDF fixture and the two existing gaps." Full `vreaderTests` suite passes
(7294 tests).

## Device verification (Feature #17, partial)

Seeded + opened `multi-page-pdf` on iPhone 17 Pro Sim: renders 6 pages with a
"Page 1 of 6" indicator (criterion 7); theme gutter background flips light→dark
via snapshot (criterion 8, per Bug #198's gutter-only scoping). Residual
CU-gate: criterion 1's gesture-driven PDF highlight (no DebugBridge driver;
real text-selection gesture only). Evidence:
`dev-docs/verification/feature-17-20260527.md` (result=partial).
