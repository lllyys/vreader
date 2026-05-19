---
branch: feat/feature-64-wi-6-txt-md-migration
threadId: 019e40a3-6389-7ba1-9849-ec2f4bf0835d
rounds: 2
final_verdict: ship-as-is
date: 2026-05-19
---

# Gate-4 Implementation Audit — Feature #64 WI-6 (TXT + MD container migration)

## Scope

WI-6 of the unified cross-format highlight-action popover — the first **behavioral** WI. Migrates the native TXT + MD reader containers from feature #55's `notePreviewPresenterIfAvailable` to the unified popover's `unifiedHighlightPopoverPresenterIfAvailable`, and removes the feature #53 highlight long-press `UIMenu` from the TXT / chunked-TXT bridges.

- `TXTReaderContainerView.swift` (MOD) — swapped the attach; removed 4 `highlightActionPresenter:`/`onHighlightTapAction:` bridge wiring blocks.
- `MDReaderContainerView.swift` (MOD) — same; removed 1 bridge wiring block.
- `TXTTextViewBridge.swift` / `TXTTextViewBridgeCoordinator.swift` / `TXTChunkedReaderBridge.swift` (MOD) — removed the `highlightActionPresenter` / `onHighlightTapAction` properties, the `handleHighlightLongPress` method, the long-press gesture registration, the dead `gestureRecognizerShouldBegin`.
- The `.readerHighlightTapped`-posting tap path (`handleContentTap`) is KEPT — the unified popover's trigger.
- `Feature55NativeWiringTests.swift` (DEL) — tested the now-removed wiring.
- `Feature64TXTMDMigrationTests.swift` (NEW) + `PDFHighlightLongPressGateTests.swift` (NEW) + `TXTReaderContainerHighlightCoordinatorWiringTests.swift` (MOD).

The feature #53 types (`HighlightActionPresenter`, `HighlightTapAction`, `HighlightCoordinator.handleTapAction`) are NOT deleted in WI-6 — plan §3.9 defers that to WI-10.

## Round 1 — Codex `019e40a3-6389-7ba1-9849-ec2f4bf0835d`

**Zero production-code correctness findings.** Codex confirmed: WI-6 implements plan §3.8 for TXT/MD; the long-press menu wiring is fully removed from the migrated files; the `.readerHighlightTapped` tap path is preserved in both non-chunked and chunked coordinators; PDF's long-press machinery remains intact for WI-7; the `@ViewBuilder if let` attach helper is correct for the late `highlightCoordinator` assignment (SwiftUI recomputes the body once the `@State` flips non-nil); no `@MainActor` hazard; removing `gestureRecognizerShouldBegin` from the TXT coordinators is correct (it only gated the deleted long-press).

Two test-coverage findings:

| # | File:line | Severity | Issue | Fix |
|---|-----------|----------|-------|-----|
| F1 | `Feature64TXTMDMigrationTests.swift:48` | Medium | The 3 attach-helper tests only assert `host.view != nil` (would pass even if the modifier never attached); no MD source-grep guard. | Add MD source-grep guards mirroring `TXTReaderContainerHighlightCoordinatorWiringTests`. |
| F2 | `Feature55NativeWiringTests.swift:1` | Low | Deleting the whole legacy suite also dropped the only direct regression coverage for PDF's still-live long-press path (kept until WI-7). | Preserve a trimmed PDF-only + shared-helper suite. |

## Resolution

- **F1** — added 4 source-grep tests to `Feature64TXTMDMigrationTests`: `mdAttachesUnifiedHighlightPopoverPresenter` (asserts MD uses `unifiedHighlightPopoverPresenterIfAvailable`, not `notePreviewPresenterIfAvailable`) + `mdFeature53LongPressMenuWiringRemoved` (asserts MD no longer passes `highlightActionPresenter:`/`onHighlightTapAction:`). The migration is now source-grep-fenced for BOTH containers (TXT via `TXTReaderContainerHighlightCoordinatorWiringTests`, MD via the 2 new tests).
- **F2** — added `PDFHighlightLongPressGateTests.swift` preserving the PDF-only + shared-helper tests from the deleted file (`simultaneityPolicyDeniesHighlightLongPressOnly`, the two `PDFViewBridge.Coordinator.gestureRecognizerShouldBegin` tests). Its header documents that WI-7 removes it alongside the PDF long-press code.

20 tests pass across the 3 affected test files; 79 across the full WI-6 + regression sweep.

## Round 2 — Codex `019e40a3-6389-7ba1-9849-ec2f4bf0835d` (re-audit of the fixes)

Verdict: **"The Medium is resolved... The Low is also resolved."** Codex verified the MD source-grep guards genuinely pin the migration and `PDFHighlightLongPressGateTests` restores coverage matching the still-live PDF production code. **No remaining open Critical/High/Medium findings.**

## Verdict

**ship-as-is** — 2 rounds (round 1 found zero production findings + 1 Medium + 1 Low, both test-coverage; round 2 clean).

## Gate-5a verification note

WI-6 is behavioral. The intended full Gate-5a slice — an XCUITest creating a TXT highlight then tapping it to assert the unified popover appears (`Feature64TXTHighlightPopoverVerificationTests`, committed) — is **blocked at the highlight-creation step by a pre-existing harness defect**: a long-press in an XCUITest surfaces no "Highlight" affordance. This reproduces on the repo's own unmodified `TXTHighlightGestureVerificationTests` on `origin/main`, so it is independent of feature #64. Filed as **Bug #234 / GH #986**. WI-6's behavioral delta is verified by the unit-test layer: the `HighlightPopoverActionRouter` action matrix, `Feature64TXTMDMigrationTests`'s `handleContentTap`-posts-`.readerHighlightTapped` test, and the source-grep wiring fences for both containers.
