---
branch: fix/issue-234-simp-trad-picker-gating
threadId: 019df7b0-ddb8-7941-aa65-4f1268977dfe
rounds: 3
final_verdict: ship-as-is
date: 2026-05-05
---

# Codex audit log — Bug #120 Path B fix (GH #234)

Bug body offered two acceptance paths. Path A (wire conversion into native mode) is a large refactor across native EPUB WKWebView + PDFKit + AZW3/MOBI renderers. Path B (gate the picker so it doesn't claim to do something it can't) is bug-sized. This branch implements Path B.

## Round 1 — initial finding

| File | Line | Severity | Issue | Resolution |
|------|------|----------|-------|------------|
| `vreader/Views/Reader/ReaderSettingsPanel.swift` | 326 | High | First patch gated only on `store.readingMode == .unified` — but readingMode is just a *user preference*, not a runtime predictor of "conversion will visibly apply." `ReaderContainerView` only takes the unified path when both `readingMode == .unified` AND the format has `.unifiedReflow`. So with the first patch, the picker still showed enabled (with affirmative footer) for PDF in unified mode, and other native-rendered paths. Path B's "disable when the current book/format uses native rendering" wasn't fully satisfied. | Fixed in Round 2: added `formatCapabilities: FormatCapabilities? = nil` parameter to `ReaderSettingsPanel`. Gate now: `if let caps, !caps.contains(.unifiedReflow) → .formatUnsupported; else if readingMode != .unified → .nativeMode; else enabled`. ReaderContainerView passes `BookFormat(rawValue: book.format.lowercased())?.capabilities`. PDF now correctly disables regardless of mode. |

## Round 2 — verification re-pass + 1 Low

After round-1 fix, Codex flagged one Low:

| File | Severity | Issue | Resolution |
|------|----------|-------|------------|
| `vreader/Views/Reader/ReaderSettingsPanel.swift:27` | Low | Comment claimed "preserves backward compat for callers (and tests) that don't supply the value" but the property had no default value, so every call site is required to provide it (synthesized memberwise init). | Fixed: added `= nil` default. The optional-call-site claim is now true. |

## Round 3 — clean

Codex confirmed:
> Path B is now implemented coherently for the format/mode information available at settings time. The picker state and copy match the actual supported cases much better, the remaining complex-EPUB false-enable is an explicit and reasonable residual gap, and the `formatCapabilities` parameter design is now internally consistent with the documented backward-compat behavior.

> Residual risk: complex EPUBs can still show the picker enabled in Unified mode and then render natively at runtime, so bug #120 is only partially mitigated, not fully eliminated. That's acceptable for the narrower Path B acceptance path, but feature #28 still needs the full render-path coverage from Path A before it can be considered complete.

## Visual verification

Performed on iPhone 17 Pro Simulator (iOS 26.4) against working-tree v3.13.16+ with war-and-peace.txt opened (TXT format = `.unifiedReflow` capable):

- **Native reading mode** (default): segmented picker `None | Simp → Trad | Trad → Simp` is **dimmed/disabled**. Footer reads `"Available in Unified reading mode only. Native mode does not yet convert Chinese text."` (secondary color).
- **Unified reading mode**: same picker is **enabled** (full color, "Simp → Trad" highlighted as selected). Footer reads `"Convert Chinese text between Simplified and Traditional scripts."` (original active copy).

PDF case wasn't visually tested (no PDF in fixture catalog), but follows the same code path: `caps.contains(.unifiedReflow)` returns false for PDF → `.formatUnsupported` → disabled regardless of readingMode. Codex audited this code path against the FormatCapabilities source.

## Final verdict

**ship-as-is**

The fix:
- Gates the picker on `readingMode == .unified` AND `caps.contains(.unifiedReflow)`.
- Differentiates two disabled reasons in the footer: `.nativeMode` (preference disqualifier) vs `.formatUnsupported` (format never supports — PDF).
- Accessibility hint text differentiates the two reasons too (gives blind users actionable guidance: "switch Reading Mode to Unified" vs "this book's format does not support text conversion").
- Backward-compat: `formatCapabilities` defaults to nil; when nil, falls back to "available everywhere" so older tests/previews don't break.

Residual gap (acknowledged, separate sub-bug): complex EPUBs in Unified mode can still show the picker enabled and silently no-op at render time. The render-time `isComplexEPUB` signal isn't available at panel-open time. False-disable for EPUB would hurt the simple-EPUB-in-unified happy path more than false-enable hurts complex-EPUB. This sub-bug is documented in the row note as remaining for a future iteration that addresses Path A or threads the runtime signal back to the panel.
