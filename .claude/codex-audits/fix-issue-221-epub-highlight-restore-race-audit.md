---
branch: fix/issue-221-epub-highlight-restore-race
threadId: 019df2c9-2205-7970-b8d3-bbc51127266c
rounds: 3
final_verdict: ship-as-is
date: 2026-05-04
---

# Codex audit log — fix/issue-221-epub-highlight-restore-race

Bug #103 fix: EPUB highlight created while `restoreHighlightsOnLoad` runs no longer has its JS misrouted to a temporary restore-only callback. Fix threads the page-ready evaluator through `restore(records:forHref:using:)` instead of swapping the renderer's `onInjectJS`.

## Round 1

**Findings**:

| Severity | Where | Issue |
|---|---|---|
| High | `EPUBReaderContainerView+Highlights.swift:145` (recovery) | Original swap-pattern fix only handled the onInjectJS race. Concurrent restores for different chapters still cross-wire through shared mutable `currentHref` — fast page navigation could send chapter-B JS via chapter-A's evaluator. |
| Medium | `EPUBHighlightRendererBug77Tests.swift:80` | Rewritten race test isn't deterministic — `MockPersistence77.fetchHighlights` doesn't suspend, so the @MainActor async-let calls can serialize and the test passes vacuously. |

Verdict: **Block / revert**.

**Resolution**:

- Threaded `forHref` as immutable input through the protocol, coordinator, and call site. EPUB renderer prefers the call's `forHref` over `currentHref`; nil falls back to `currentHref` (preserving the existing handleRemoval path).
- Test rewrite: replaced async-let with an unstructured Task plus `Task.yield()` loop. (Codex round 2 still flagged this as nondeterministic — see round 2.)

## Round 2

**Findings**:

| Severity | Where | Issue |
|---|---|---|
| Medium | `EPUBHighlightRendererBug77Tests.swift:55` | Race test still nondeterministic — `Task.yield()` loop doesn't guarantee restore reaches the await before create runs; `releaseFetchGate()` could win the race and strand the restore Task. |

Verdict: **Follow-up recommended**.

**Resolution**:

- `MockPersistence77` is now @MainActor with explicit `waitForFetchToBeArmed()` handshake. The handshake resolves only after `fetchHighlights` has installed its `pendingFetchGate` AND set `fetchIsPaused = true`. The test waits for that signal before running create + release, so the timing is guaranteed by the handshake protocol, not by yield-loop guesswork.

## Round 3

**Verdict**: **Ship as-is.**

The deterministic handshake closes the round-2 nondeterminism. Production fix is correct, no further findings.

## Files changed

- `vreader/Views/Reader/HighlightRenderer.swift` — protocol gains `forHref` + `using:` parameters; default-impl extension preserves the no-arg `restore(records:)` for existing callers.
- `vreader/Views/Reader/EPUBHighlightRenderer.swift` — `restore` prefers `forHref`, uses provided evaluator when non-nil.
- `vreader/Views/Reader/TextHighlightRenderer.swift` + `PDFHighlightRenderer.swift` — signature updated to match protocol; both ignore `forHref` and `evaluator` (don't filter by chapter, don't use JS).
- `vreader/Views/Reader/HighlightCoordinator.swift` — `restoreAll(forHref:using:)` threads both through.
- `vreader/Views/Reader/EPUBReaderContainerView+Highlights.swift` — drops the `onInjectJS` swap pattern; captures `href` immutably before Task body, calls `restoreAll(forHref: capturedHref, using: evaluateJS)`.
- 3 test files updated for the new signature; bug #77/#103 race test rewritten with deterministic CheckedContinuation handshake.

## Test coverage

| Suite | Tests | Status |
|---|---|---|
| EPUBHighlightRendererBug77Tests | 4 (4 pass) | All green; race test now deterministically exercises the bug path |
| HighlightCoordinatorTests | 9 | All green |
| HighlightIntegrationTests | varies | All green |
| EPUBHighlightActionsTests + EPUBHighlightBridgeTests | varies | All green (no change to action/bridge logic) |

36 tests across 5 suites pass.

## What still might bite us

Codex's round 1 closing observation noted: even with `forHref` threading, two concurrent `restoreHighlightsOnLoad` calls for the SAME href could still both fire (e.g., user navigates back-forward quickly). The renderer's `currentHref` is set before the Task starts but isn't snapshotted into the Task itself. With the fix, the Task uses `forHref` so the inner restore behavior is correct — but if both Tasks emit JS to the same evaluator the page sees duplicate DOM mutations. Acceptable trade-off because the JS is idempotent (CSS Highlight API set-update). Not a blocker; worth noting.
