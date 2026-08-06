---
gate: 4
kind: implementation-audit
feature: 142
work_item: WI-3
branch: feat/142-wi-3-foliate-annotation-js
threadId: 019e8c1f-run-codex-r1r2
rounds: 2
final_verdict: follow-up-recommended
---

# Gate 4 — feature #142 WI-3 (foliate annotation JS builders + `evalForResult`)

Auditor: Codex via `scripts/run-codex.sh` (rule 53), read-only sandbox, two rounds.
Raw transcripts: `.reports/audit-r1.txt`, `.reports/audit-r2.txt` (worktree-local, not committed).

Files under audit:

- `android/app/src/main/kotlin/com/vreader/app/reader/foliate/FoliateAnnotationJs.kt` (new)
- `android/app/src/main/kotlin/com/vreader/app/reader/foliate/FoliateBridge.kt` (modified)
- `android/app/src/test/kotlin/com/vreader/app/reader/foliate/FoliateAnnotationJsTest.kt` (new)
- `android/app/src/test/kotlin/com/vreader/app/reader/foliate/FoliateEvalDispatcherTest.kt` (new)
- `android/app/src/test/kotlin/com/vreader/app/reader/foliate/FoliateBridgeAnnotationCallsTest.kt` (new, round-1 fix)
- `android/app/src/test/kotlin/com/vreader/app/reader/foliate/FoliateGoToTest.kt` (extended, round-1 fix)

## Round 1 — verdict: block-recommended

| # | Severity | Finding | Disposition |
| --- | --- | --- | --- |
| 1 | High | `FoliateGoToDispatcher`'s ack collector is an infinite `messages.collect` launched on a scope nobody cancels. `destroy()` tore down the eval dispatcher and the WebView but never that collector, so the collector kept the dispatcher — and through `sendJs`, the bridge and its WebView — reachable for the life of the process. | **FIXED** (30ebf768). The collector's `Job` is retained; a new idempotent `FoliateGoToDispatcher.teardown()` cancels it and completes any awaiting caller as `Superseded`; `FoliateBridge.destroy()` calls it. The passed-in `scope` is deliberately NOT cancelled — it may be owned by the caller (tests inject `runTest`'s). |
| 2 | High | `evalForResult`'s WebView `ValueCallback` closed over the `Pending` entry, which owns `onResult` and everything that lambda captured. A WebView holds its callback until the page answers — never, for a wedged renderer — so removing the entry from the registry freed nothing. The precise leak the class claims to bound. | **FIXED** (30ebf768). Probes are keyed by a monotonic `Long` id in a `LinkedHashMap`; the lambda handed to `sendJs` captures only the id and the dispatcher (already reachable from the bridge). Leaving the registry therefore does make the caller's lambda unreachable. Ids are never reused — pinned by two new stale-callback tests. |
| 3 | Medium | No test proved the BRIDGE calls the builders correctly. Named surviving mutation: `eval(foliateAddAnnotationJs(cssColor, cfi))` — arguments swapped — passed the entire suite. | **FIXED** (30ebf768). `FoliateBridgeAnnotationCallsTest` (Robolectric `ShadowWebView.getLastEvaluatedJavascript`) asserts each public bridge method injects its builder's exact output, with an explicit `assertNotEquals` against the swapped form. Re-running the auditor's mutation now fails two tests. |
| 4 | Low | The hostile corpus omitted U+2028/U+2029 and lone surrogates. kotlinx JSON emits the separators raw; pre-ES2019 engines treat them as line terminators inside a string literal, i.e. a parse error no `try{…}catch{}` can rescue. Not a live vulnerability on current Chromium, but an undocumented compatibility dependency. | **FIXED** (30ebf768). `foliateJsString` escapes U+2028/U+2029 on top of the JSON encoding, removing the dependency on which System WebView the device ships. Both separators and both lone surrogates joined the corpus; surrogate passthrough is pinned as deliberate (neither half is a quote or a backslash, and mangling one would corrupt a CFI). |

**Confirmed by round 1** (recorded so a later round need not re-derive): the annotation object shape matches the vendored bundle — `{value, color}` is consumed correctly, `color` reaches `Overlayer.highlight` verbatim, and delete needs only `{value}`; the no-`addJavascriptInterface` posture is intact; **no bundle change is required**.

## Round 2 — verdict: follow-up-recommended

Round 2 verified each round-1 fix against the code rather than the claim, and confirmed:
the default `CoroutineScope(Dispatchers.Main)` retains a root `Job` but **no live children**
after `destroy()`; `Superseded` is the right resolution for an awaiting goTo; settled and
torn-down probes retain no caller callback; `Long` id wrap is not operationally meaningful;
and the widened escaping preserves decoded values for #129 `setStyles` and #135/#140 `goTo`
(the substitution is inside the literal, so every decode round-trips unchanged).

| # | Severity | Finding | Disposition |
| --- | --- | --- | --- |
| 1 | Low | Nothing proved `FoliateBridge.destroy()` *calls* `goToDispatcher.teardown()`. The dispatcher's own teardown tests stay green if that one line is deleted, which would silently reinstate round-1 H1 in production. Named as a surviving mutation. | **FIXED** (this commit). `destroy_tearsDownTheGoToDispatcher_soAnAwaitedJumpIsReleasedAtOnce` starts an awaited `bridge.goTo` with a ten-minute budget, calls `destroy()`, and asserts it resolves `Superseded` immediately with no time advanced. Deleting the call was re-run and now fails that test. |

## Mutation testing (author-run, three rounds, ten mutations, zero survivors)

Round 1 mutations — all killed:

| Mutation | Killed by |
| --- | --- |
| `foliateAddAnnotationJs` emits the colour unescaped | `addAnnotationJs_escapesTheColourToo` (that test alone — the exact-string and round-trip tests do not cover the colour, which is why the dedicated adversarial-colour case exists) |
| `FoliateEvalDispatcher.eval` drops the timeout `launch` | `noAnswerWithinBudget_deliversNullExactlyOnce`, `anAnswerArrivingAfterTheTimeout_isIgnored`, `oneProbeTimingOut_doesNotSettleTheOther`, `aZeroTimeout_stillSettlesRatherThanHanging`, `pendingCount_tracksInFlightProbes_…` |
| `teardown()` drops its settled latch | `anAnswerAfterTeardown_isDropped` |
| `readerAPI.deselect` renamed to `readerAPI.clearSelection` | `deselectJs_isExactlyThisString` |

Round 2 mutations (on the round-1 fixes) — all killed:

| Mutation | Killed by |
| --- | --- |
| `FoliateBridge.addAnnotation` swaps its arguments (**the auditor's named survivor**) | `addAnnotation_injectsExactlyTheBuilderOutput_withTheArgumentsInThatOrder`, `aHostileCfi_reachesTheWebViewEscaped_notRaw` |
| `foliateJsString` drops the U+2028/U+2029 substitution | `emittedJs_carriesNoRawJsLineTerminator`, both `escapesEveryAdversarialCfi_exactly` |
| `FoliateGoToDispatcher.teardown()` drops `collectorJob.cancel()` | `teardown_isIdempotent_andASubsequentGoToNeverAcks` — note the *first* teardown test cannot see this mutation (`pending` is already null by then, so a live collector has nothing to resolve); the second one, which issues a fresh goTo and emits its ack, can. Recorded because a reader might otherwise assume the first test covers it. |
| Probe ids made constant + the post-teardown `eval` guard removed | `aStaleCallback_cannotSettleALaterProbe`, `aStaleCallback_cannotSettleAProbeIssuedAfterTeardown`, `concurrentProbes_resolveIndependently_…`, `oneProbeTimingOut_…`, `pendingCount_…`, `evalAfterTeardown_injectsNoJs_andNeverCallsBack`, `evalForResult_injectsTheJs_andDropsItsCallbackAfterDestroy` |

Round 3 mutation — killed:

| Mutation | Killed by |
| --- | --- |
| `FoliateBridge.destroy()` drops `goToDispatcher.teardown()` (**round-2's named survivor**) | `destroy_tearsDownTheGoToDispatcher_soAnAwaitedJumpIsReleasedAtOnce` |

## Accepted / out of scope

- **`/` is not escaped**, so `</script>` passes through verbatim. Correct here — the string goes to
  `evaluateJavascript`, never into an HTML `<script>` element, so no HTML parser can terminate it.
  Pinned by a corpus entry and documented on `foliateJsString` so a future caller that *does* build
  HTML is warned.
- **Unpaired surrogates pass through unchanged.** Neither half is a quote or a backslash, so there is
  no break-out; rewriting them would corrupt a CFI. Pinned as a decision, not an accident.
- **`FoliateBridge.kt` is 439 lines**, over the ~300 guideline. Pre-existing (373 before this WI) with
  a filed split follow-up; WI-3 kept its own machinery out of it (`FoliateAnnotationJs.kt`, 181 lines)
  and adds only thin forwarding. The natural split — moving `Azw3GoToResult` / `FoliateGoToTarget` /
  `FoliateGoToDispatcher` into `FoliateGoTo.kt`, same package, no import churn — is proposed in the
  HANDOFF rather than performed here, so it can be judged as the separate change it is.

## Test result

`RUN-ANDROID-TESTS RESULT: SUCCEEDED` — full `:app:testDebugUnitTest`, **2640 tests, 0 skipped,
0 failures, 0 errors** (`--rerun-tasks`, so no task was reported up-to-date). Zero skips is asserted
from the JUnit XML, not inferred from the exit code (bug #369: a skip exits 0 exactly like a pass).
