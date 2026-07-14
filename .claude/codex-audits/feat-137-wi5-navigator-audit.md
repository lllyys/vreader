---
branch: feat/137-wi5-navigator
threadId: run-codex-gpt-5.5-high
rounds: 2
final_verdict: follow-up-recommended
---

# Gate-4 audit — feature #137 WI-5: TxtPageNavigator

Files under review:
- `android/app/src/main/kotlin/com/vreader/app/reader/paged/TxtPageNavigator.kt` (new)
- `android/app/src/test/kotlin/com/vreader/app/reader/paged/TxtPageNavigatorTest.kt` (new)

Contract (read-only): WI-4's `TxtPageIndex.kt`, `TxtPaginator.kt` (same package).

Auditor: Codex `gpt-5.5` / reasoning `high` via `scripts/run-codex.sh` (rule 53).
Full logs: `.reports/wi5-audit.txt` (round 1), `.reports/wi5-audit-r2.txt` (round 2).

## Round 1 — verdict: block-recommended

- **Critical:** none.
- **High:** the "Compose-free" claim was overstated — the navigator imports
  `androidx.compose.ui.text.TextStyle` and exposes it in `reconcileAfterReflow`'s
  public signature. (No `PagerState`/`HorizontalPager`/Compose-state holder leaks,
  which the auditor confirmed.)
- **Medium:** the `CancellationException` swallow was too broad — a parent/job
  cancellation was converted to normal completion and `activeToken` could remain stale.
- **Low ×2:** the generation-number guard was not isolated by a dedicated test;
  `pendingScrollTarget` was not asserted consistently across reflow paths.

### Round-1 fixes applied
- **High** → corrected the KDoc: the navigation LOGIC is Compose-independent; the
  ONLY Compose reference is the `TextStyle` param threaded straight through to WI-4's
  `TxtPaginator.index` (its read-only signature requires `TextStyle` for line
  measurement), never inspected in the navigator. This is a hard, unavoidable
  dependency of the WI-4 contract — accepted as accurate, not a leak.
- **Medium** → narrowed the catch: swallow ONLY on this navigator's own supersession
  (`token.isCancelled` OR stale generation), clear the stale `activeToken`, and rethrow
  any other cancellation so structured concurrency is honored.
- **Low** → added `supersededReflow_generationGuard_dropsAStaleSuccessEvenIfTokenNotTheDropReason`
  and `reflow_setsPendingScrollTarget_toReconciledPage_onEveryReflowPath`.

## Round 2 — verdict: follow-up-recommended

- **Critical / High / Medium:** none. The Compose-scope claim is now accurate and
  acceptable (TextStyle pass-through only); the cancellation narrowing honors
  structured concurrency; reflow reconciliation (capture-offset → await new index →
  clamp to `pageContaining`, grown/shrunk), degenerate/empty safe degrade, injected
  dispatchers, and the thin programmatic-scroll pager seam all verified sound.
- **Low #1:** the *rethrow* path (genuine parent/job cancel) did not clear
  `activeToken` — a minor weakening of the "no stale activeToken" claim, not a
  publish/correctness bug. **Fixed:** `activeToken` is now cleared before either
  branch, so it never points at a no-longer-running pass regardless of cancel source.
- **Low #2:** the generation-guard test under `UnconfinedTestDispatcher` asserts the
  newest-wins end state but doesn't strictly isolate a stale *success* where the token
  isn't the drop vector. **Accepted with rationale:** the auditor confirmed the
  production generation guard is correct; the guard IS exercised (two interleaved
  passes, newest published). A strictly-isolated stale-success test would need a
  controllable-completion measurer whose complexity exceeds a Low finding's warrant.
  The dual guard (token-cancel + generation-number) is defense-in-depth; either alone
  suffices for correctness.

## Test gate
`RUN-ANDROID-TESTS RESULT: SUCCEEDED` — `:app:testDebugUnitTest --tests 'com.vreader.app.reader.paged.*'`
(16 navigator tests + WI-4's 43 = 59 paged tests, 0 failures) after every code change.

## Disposition
Zero open Critical/High/Medium. Round-1 Low pair fixed; round-2 Low #1 fixed, Low #2
accepted with rationale. Ship — `follow-up-recommended` with no open follow-ups
requiring pre-merge action.
