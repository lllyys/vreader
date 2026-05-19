---
branch: fix/issue-960-chunked-txt-bridge-search-highlight-clear
threadId: 019e403e-3759-7363-a518-d850ec5c819f
rounds: 1
final_verdict: ship-as-is
date: 2026-05-19
---

# Codex Audit — Bug #232 / GH #960

Chunked TXT bridge (`TXTChunkedReaderBridge`) did not clear a temporary
search/navigation highlight on a **new search** (`.searchHighlightClear`
notification) or a **user scroll** — only the 3 s auto-clear timer ever
cleared it. The non-chunked `TXTTextViewBridge` clears on all three paths.
Pre-existing structural gap (not a regression), surfaced by the Codex Gate-4
audit of the Bug #154 fix and filed separately.

## Changed files

- `vreader/Views/Reader/TXTChunkedReaderBridge.swift` — new `Coordinator`
  state (`activeHighlightIsTemporary`, `weak var tableView`,
  `nonisolated(unsafe) var highlightClearObserver`); `init` registers a
  `.searchHighlightClear` observer; new `deinit` removes the observer +
  invalidates the timer (`MainActor.assumeIsolated`); `scrollViewDidScroll`
  and `scrollViewDidEndDragging` call the new clear helper;
  `makeUIView`/`updateUIView` set `coordinator.tableView`.
- `vreader/Views/Reader/TXTChunkedHighlightHelper.swift` — `applyHighlight`
  records `activeHighlightIsTemporary`; `clearHighlight` resets it; new
  `clearTemporaryHighlightIfNeeded(scrollView:)` — user-scroll-gated clear
  routed through `clearHighlight`, nils `lastHighlightRange`, fires
  `onTemporaryHighlightCleared` once.
- `vreaderTests/Views/Reader/TXTChunkedSearchHighlightClearTests.swift` — new
  12-test Swift Testing suite (new search, user scroll, programmatic-scroll
  preservation, persistent-highlight preservation, callback-once, idempotency,
  end-to-end through `scrollViewDidScroll`).

## Round 1 — thread 019e403e-3759-7363-a518-d850ec5c819f

**Findings: none.** Codex (model_reasoning_effort: high, read-only sandbox)
reported zero Critical/High/Medium/Low defects after reading the changed files
and the non-chunked reference (`TXTTextViewBridgeCoordinator.swift`).

Audit confirmed:
- The fix addresses bug #232's root cause and matches the non-chunked
  coordinator's behavior.
- `clearTemporaryHighlightIfNeeded` clears only temporary highlights,
  invalidates both the live timer and `pendingAutoClearForChunk`, nils
  `lastHighlightRange`, and fires `onTemporaryHighlightCleared` exactly once
  per real clear.
- Clearing in `scrollViewDidScroll` before the throttle is the correct
  placement; later drag/deceleration callbacks become no-ops after the first
  clear.
- Concurrency + cleanup are consistent with the existing non-chunked pattern:
  observer delivered on `.main`, `[weak self]` capture, removed in `deinit`,
  and the `weak var tableView`-nil degenerate path does state-only cleanup
  without leaving stale highlight/timer state.

### Accepted Low note (not a defect in this fix)

`TXTChunkedReaderBridge.swift` remains far over the repo's ~300-line
guideline. **Pre-existing**: the file was already 809 lines before this fix;
this change adds 75 lines for the new observer/state/lifecycle. Splitting an
809-line file would be a drive-by refactor against the "keep diffs focused,
avoid drive-by refactors" working-agreement rule. Accepted as out of scope for
this focused bug fix. Codex explicitly agreed: "real but pre-existing and out
of scope for this bug-fix audit."

## Verdict

**ship-as-is.** Round 1 clean — zero blocking defects in correctness,
concurrency, cleanup, or the scroll/new-search edge cases. One accepted Low
note (pre-existing file size, out of scope). Codex confirmed ship-as-is on the
follow-up reply.
