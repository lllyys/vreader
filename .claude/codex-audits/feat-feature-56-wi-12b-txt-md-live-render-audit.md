---
branch: feat/feature-56-wi-12b-txt-md-live-render
threadId: 019e430f-e144-74e3-804c-1c2fd4d027d3
rounds: 2
final_verdict: ship-as-is
date: 2026-05-20
---

# Codex Gate-4 audit — feature #56 WI-12b (TXT bilingual interlinear live render + offset routing)

Author: Claude Opus 4.7 (1M context)
Auditor: Codex MCP, thread 019e430f-e144-74e3-804c-1c2fd4d027d3
Plan: `dev-docs/plans/20260519-feature-56-bilingual-reading.md` (WI-12 row, split into WI-12a + WI-12b in commit 05f215a)

WI-12a (PR #1036 / commit 1693d73) shipped the foundational pure types:
`BilingualDisplaySegmentMap`, `BilingualTextRenderer`, and TXT/MD host
wiring (lazy VM construction, first-enable setup sheet, More-menu
toggle observer, chrome-pill mirror) — but explicitly deferred the
live render injection. WI-12b ships the live-render slice for the
chapter-paged + legacy-small-file TXT paths.

Out-of-scope for WI-12b (documented in commit body): TXT continuous-
chaptered + chunked-large-file paths, MD scroll mode. All three are
deferred to follow-up WIs because per-chunk and chapter-range-aware
bilingual rendering require structural changes beyond a single PR.
Bilingual toggle / pill / setup sheet / prefetch all run for those
paths; only the live attrString stays source-only.

## Round 1 — initial audit

Verdict: **block-recommended** (2 High + 1 Low).

| # | File:Line | Severity | Issue | Resolution |
|---|---|---|---|---|
| H1 | TXTReaderContainerView.swift:730 + :809 | High | `restoreOffset` was passed to `TXTTextViewBridge` in source coordinates on both live paths. With bilingual ON, any saved position after an inserted synthetic block would restore too early on reopen. Left the central R-TXT-offsets risk unresolved for persisted-position restore even though `scrollToOffset` was routed. | **Fixed (commit 454f49a)**: both `readerContent` and `chapterReaderContent` now compute `bilingualRestore = initialRestoreOffset.map { BilingualOffsetRouter.displayOffset(forSourceOffset: $0, map: bilingualSegmentMap) }` and pass `restoreOffset: bilingualRestore` to the bridge. Chunked + continuous paths still pass raw `initialRestoreOffset` — those paths are deferred (source-only render) so the identity-fallthrough semantics hold. |
| H2 | TXTBridgeShared.swift:42 | High | Selection-action notifications (Highlight / Add Note / Define / Translate / SelectionPopover) were posted from raw display-space `UITextView` ranges. `postSelectionNotification` built `TextSelectionInfo` from `range.location/length` on the bilingual-rendered text, while the container only routed scroll / highlight paint / lookup / delegate offsets. In bilingual TXT, selecting text after or across a synthetic block produced shifted or out-of-bounds source ranges; the "selection" touchpoint was not routed through `BilingualDisplaySegmentMap`. | **Fixed (commit 454f49a)**: threaded `bilingualSegmentMap` from container → bridge → coordinator → `TXTBridgeShared.postSelectionNotification` + `buildReaderEditMenu`. `TXTTextViewBridge` gains a `bilingualSegmentMap: BilingualDisplaySegmentMap` property (default identity = byte-identical pass-through); `Coordinator.bilingualSegmentMap` is synced from the bridge in both `makeUIView` and `updateUIView`; `editMenuForTextIn` forwards it to `postSelectionNotification`. `postSelectionNotification` maps the display range back to source via `BilingualDisplaySegmentMap.sourceOffset(forDisplayOffset:)` with end-boundary semantics (a selection ending at a synthetic-block start projects to the preceding source segment's `upperBound`; a selection starting in synthetic is dropped). |
| L1 | BilingualTXTBridgeDelegateAdapter.swift:61 | Low | `selectionDidChange` mapped the exclusive selection end with `sourceOffset(forDisplayOffset:)`, which returns `nil` at synthetic starts and at `displayLength`. A valid selection ending exactly at a synthetic boundary therefore collapsed to a caret instead of preserving the source end-point. | **Fixed (commit 454f49a)**: extracted `routeSelectionEnd(displayOffset:start:map:)`. End at `displayLength` → `sourceLength`; end inside synthetic → most recent preceding source segment's `upperBound`; otherwise direct map. Two new boundary tests in `BilingualTXTBridgeDelegateAdapterTests` pin both cases. |

## Round 2 — verification

Verdict: **ship-as-is**.

Codex confirmed all three findings closed without introducing new regressions:

- H1: both live TXT bridge paths now route `initialRestoreOffset` through `BilingualOffsetRouter`. Chunked and continuous remain byte-identical because they don't pass a bilingual map and those deferred paths still render source-only.
- H2: the `bilingualSegmentMap` thread is end-to-end through `TXTTextViewBridge` (lines 81, 130, 178) → `TXTTextViewBridgeCoordinator.editMenuForTextIn` (line 360) → `TXTBridgeShared.postSelectionNotification` (line 52). Chunked path keeps the old behavior by omission (default identity = pass-through), which is correct because that deferred path renders source-only. Define + Translate + Note + Popover all route correctly through the same helper.
- L1: end-boundary semantics now preserve end-points at synthetic boundaries and map `displayLength` to `sourceLength`. New adapter + shared-helper tests pin both cases.

## Manual fallback evidence

N/A — Codex MCP was available; rounds 1 and 2 both ran on thread `019e430f`.

## Summary

Two-round audit. Round-1 caught two High and one Low — all closed in
commit `454f49a` with end-to-end thread-through of the segment map
and end-boundary semantics for selection routing. Round 2 returned
`ship-as-is`. Final WI-12b ships TXT chapter-paged + legacy-small-file
bilingual interlinear live render + offset routing for the central
R-TXT-offsets risk path. Continuous-chunked TXT + MD scroll mode
deferred to follow-up WIs and documented in the PR body.
