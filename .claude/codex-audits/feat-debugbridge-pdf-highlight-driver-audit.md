---
branch: feat/debugbridge-pdf-highlight-driver
threadId: 019e6998-d845-7543-a512-9bfb28173d56
rounds: 3
final_verdict: ship-as-is
date: 2026-05-27
---

# Codex Audit — pdf-highlight DebugBridge driver (feature #17 verification harness)

Gate-4 audit for `vreader-debug://pdf-highlight?page=<N>&rect=<x,y,w,h>[&color=<name>]` —
injects a PDF highlight at a page + normalized rect via the SAME production creation path
the long-press-drag gesture uses (`handleHighlightAction` → `HighlightCoordinator.create` →
`PersistenceActor.addHighlight` + `PDFAnnotationBridge.createHighlightFromAnchor`), bypassing
the gesture (which needs a real touch / CU). The whole value is FAITHFULNESS: a bridge
highlight must be byte-identical to a gesture one at the same (page, rect). Mirrors the
navigate (Bug #273) + scroll-boundary drivers.

## Round 1 — 2 High + 3 Medium

| file:line | sev | issue | resolution |
|---|---|---|---|
| observer | High | no-render-but-persist: out-of-range/unloaded page → `createHighlightFromAnchor` returns `[]` AFTER `addHighlight` persisted → invisible record | Fixed — guard `isDocumentLoaded`/`totalPages`/page-range before create |
| DebugCommand parser | High | rect validation accepted `x+w>1`/`y+h>1` (production `normalizeRects` clamps) | Fixed — reject overflow rects |
| +Highlights | Medium | `Locator.page` from `makeCurrentLocator()` (currentPageIndex) ≠ anchor page | Fixed — navigate-first (`pageDidChange(to:page)`) so currentPageIndex==page |
| observer | Medium | `selectedText` hard-coded "" vs production `selection.string` | Fixed — derive from page glyphs |
| observer | Medium | explicit `color=` bypassed `handleHighlightAction` + dropped on nil coordinator | Fixed — `handleHighlightAction(color:)` on both paths |

## Round 2 — 1 High + 2 Medium

| file:line | sev | issue | resolution |
|---|---|---|---|
| DebugCommand parser | High | zero-area rects (`0.5,0.5,0,0`) accepted → invisible record | Fixed — reject `w<=0`/`h<=0` |
| observer | Medium | `selectedText` reloaded `PDFDocument(url:)` on @MainActor (perf + fails for password-locked) | Fixed — read the LIVE `highlightRenderer.document`; `PDFViewBridge.updateUIView` binds it unconditionally (idempotent) |
| observer | Medium | empty/whitespace rect persisted a marker + created a highlight (production gates on non-empty selection) | Fixed — `faithfulSelectedText` gate: no-op (no create) when the live selection is empty/whitespace |

## Round 3 — clean

Codex: "Clean for round 3. I don't see remaining correctness issues." Verified: the unconditional
`setDocument` bind is behavior-neutral (idempotent on unchanged identity; harmless before restore;
clears the old map only on a real identity change); `faithfulSelectedText` checks trimmed emptiness
but persists the RAW `selection.string` (matching production); zero-area rejection complete;
`highlightRenderer` private→internal acceptable (renderer still owned by the container; the DEBUG
observer only reads the live document handle); all no-render-but-persist paths closed (unloaded doc,
bad page, missing doc/text, blank rect all no-op before persistence).

## Verdict

**ship-as-is.** Zero open Critical/High/Medium after 3 rounds (5 → 3 → 0). A bridge highlight at
(page, rect) is now byte-identical to a gesture one: navigated page (Locator.page==anchor page),
validated non-zero in-bounds rect, raw live-document selection string, requested color through the
single `handleHighlightAction`, and ONLY created when real glyphs sit under the rect. Full
`vreaderTests` (7333) passes; `verify-release-no-debugbridge.sh` passes (all new code `#if DEBUG`;
the one production change — the idempotent `setDocument` bind — is behavior-neutral, full suite +
PDF highlight render/restore/delete suites confirm no regression).

## Purpose (device verification it unblocks)

Lets `xcrun simctl openurl "vreader-debug://pdf-highlight?page=N&rect=…"` device-verify feature
#17's criterion 1 (selection-driven highlight → PDFAnnotation that renders + persists) at the
create/render/persist level, narrowing #17's residual to the raw long-press-drag text-SELECTION
gesture (real-device/CU-only) — the same pattern scroll-boundary applied to #71.
