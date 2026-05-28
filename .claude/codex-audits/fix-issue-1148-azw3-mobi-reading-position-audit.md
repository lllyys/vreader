---
branch: fix/issue-1148-azw3-mobi-reading-position
threadId: 019e603a-3352-7f23-8b4a-1fa9ae368773
rounds: 2
final_verdict: ship-as-is
date: 2026-05-26
---

# Codex audit — Bug #265 / GH #1148 (AZW3/MOBI reading position save/restore)

Independent audit (Codex MCP, separate process) of the fix that wires
cross-session reading-position persistence into the LIVE AZW3/MOBI Foliate path
(`FoliateBilingualContainerView` → `FoliateSpikeView`), which previously had
none (the wiring lived only in dead `FoliateReaderHost`/`FoliateReaderViewModel`).

Files audited:
- `vreader/Views/Reader/FoliatePositionRestoreController.swift` (new)
- `vreader/Views/Reader/FoliateBilingualContainerView+Position.swift` (new)
- `vreader/Views/Reader/FoliateBilingualContainerView.swift` (modified)
- `vreaderTests/Views/Reader/FoliatePositionRestoreControllerTests.swift` (new, 9 tests)

## Round 1 — 3 High, 1 Low

| # | Severity | Finding | Resolution |
|---|---|---|---|
| 1 | High | Restore was triggered on `.foliateBookReadyTOC`, which the spike only posts when `!info.toc.isEmpty` (FoliateSpikeView.swift:671) → TOC-less AZW3/MOBI books never restore + never open the save gate (every change dropped). | **Fixed** — restore now triggers on the **first `.foliateRelocated`** (`handleRelocated`), which the spike posts for every book with a parseable relocate + fingerprintKey (FoliateSpikeView.swift:901). `.foliateBookReadyTOC` reverted to TOC-relay only. |
| 2 | High | The gate opened (in `loadRestoreTarget`'s `defer`) BEFORE the caller posted the seek → window where the open→start relocate gets scheduled for save. | **Fixed** — split the API: `loadRestoreTarget()` no longer opens the gate; new `openSaveGate()` does, called synchronously right after the seek post (no `await` between). |
| 3 | High | `.foliateBookReadyTOC` is posted from the `book-ready` handler BEFORE `readerAPI.init({})` (FoliateSpikeView.swift:731) + `layout-ready` (:742) → an early `goTo` is ignored / overwritten by init's default-start navigation (silent restore failure). | **Fixed** — same change as #1: the first `.foliateRelocated` only fires AFTER init has rendered + navigated, so the restore `goTo` actually takes. |
| 4 | Low | Tests only covered the controller in isolation. | **Partly addressed** — added controller tests for the split gate (`loadRestoreTargetDoesNotOpenGate`, `positionChangeAfterGateOpenPersisted`, `openSaveGateEnablesSaveWithoutSavedPosition`). The relocate-trigger + post-init-readiness wiring is device-verified (not unit-testable without WebKit). |

## Round 2 — 1 Medium

| # | Severity | Finding | Resolution |
|---|---|---|---|
| 5 | Medium | `triggerPositionRestoreIfNeeded` launched an uncancelled `Task` that can outlive the view; a fast dismiss→reopen of the same book lets the stale task post `.foliateRequestSeekTarget` into the NEW reader instance (channel filtered only by `fingerprintKey`). | **Fixed** — task stored in `@State var positionRestoreTask`; `guard !Task.isCancelled` before the post; `.onDisappear` cancels it. |

## Verdict

Round 2 clean: **no remaining Critical/High/Medium. Ship-as-is.** Codex confirmed
the task cancellation closes the fast-reopen leak without reopening the clobber
race. Doc-drift note (header said "first `.foliateBookReadyTOC`") fixed post-verdict.

9 controller tests pass; full `vreaderTests` suite green (see PR).
