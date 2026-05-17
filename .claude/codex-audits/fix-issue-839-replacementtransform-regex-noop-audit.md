---
branch: fix/issue-839-replacementtransform-regex-noop
threadId: 019e3769-dd2b-7ee0-ac7e-6888e3a2da30
rounds: 2
final_verdict: ship-as-is
date: 2026-05-18
---

# Codex audit — Bug #217 / GH #839

`ReplacementTransform` regex rules silently no-op under dispatch-pool
saturation — `applyRegexRule` dispatched the match to
`DispatchQueue.global()` and blocked on a 1s `DispatchSemaphore`; when the
pool was saturated the work item could not get a thread within the window,
the wait spuriously timed out, and the rule returned the input unchanged.

## Changed files

- `vreader/Services/TextMapping/ReplacementTransform.swift` — removed the
  `DispatchQueue.global()` + `DispatchSemaphore` + `regexTimeoutSeconds`
  timeout machinery; `applyRegexRule` now calls `regex.matches(...)`
  synchronously on the calling thread. Header "Key decisions" updated.
- `vreaderTests/Services/TextMapping/ReplacementTransformTests.swift` —
  added `regexRule_appliesUnderGlobalQueueContention`, the deterministic
  RED (gated opt-in — see round 1).

## Round 1

| file:line | severity | issue | fix |
|---|---|---|---|
| ReplacementTransformTests.swift:111 | Medium | `regexRule_appliesUnderGlobalQueueContention` is a scheduler-contention repro: it CPU-saturates `DispatchQueue.global()` for ~1.6s, which is machine-sensitive and makes the parallel suite hostile (concretely risks `SimpTradTransformTests.performance_1MBText_under500ms`'s wall-clock assertion). | Either extract an injected scheduler seam for a deterministic test, or isolate the contention test (serialize + explicit time limit). |

Codex confirmed everything else correct: removing the dispatch hop fixes
the no-op; synchronous `regex.matches` is right for a synchronous
`TextTransform`; `matches.isEmpty` is the correct early-return now that
"timed out" is no longer a state; dropping the timeout is acceptable
(the old guard was incorrect, never actually bounded a running
`regex.matches`, `DispatchWorkItem.cancel()` could not preempt it, and it
blocked the caller anyway); no actor-isolation / Sendable concern; edge
cases (empty input, no matches, invalid regex, UTF-16/CJK) all sound; no
timeout leftovers; no unused imports.

**Resolution** — gated the contention test opt-in:
`@Test(.enabled(if: env["VREADER_RUN_CONTENTION_TESTS"] == "1"))`. It is
skipped in normal/CI runs (not antisocial, not machine-sensitive in CI)
and preserved as the documented, re-runnable RED. A scheduler-injection
DI seam was rejected: the fix's purpose is to *remove* the dispatch
indirection — re-adding a scheduler abstraction purely for testability
would re-introduce the complexity the fix eliminates. No QoS setting can
both starve the default-QoS pool the buggy code used and spare
default-QoS neighbours, so a faithful repro is inherently antisocial —
gating is the correct isolation. The always-on regression guard remains
the existing `regex_multipleMatches` + `replace_regex_groupCapture` tests
(deterministic post-fix; they were the tests that flaked under the full
parallel suite when #217 was discovered).

## Round 2

Codex verdict: **"Clean. As audited now, I'd ship it."** No remaining
concerns with the fix or the opt-in test. Codex agreed the DI seam would
be "overfitting the production design to a retired failure mode" and that
`.timeLimit` adds little (the test is self-bounded; the opt-in gate is the
substantive safety mechanism).

One sub-finding nit (Codex explicitly "not a finding"): the gate checked
`!= nil` while the comment said `=1`. Fixed — gate now `== "1"`, matching
the comment literally.

## Empirical verification

- **RED** — `regexRule_appliesUnderGlobalQueueContention` run on the
  pre-fix commit FAILED: under the test's deliberate `DispatchQueue.global()`
  CPU-saturation the `\d+`→`#` rule returned `"page 1 of 100"` unchanged
  (expected `"page # of #"`). The two sibling regex tests failed as
  collateral (the saturation also tripped their pre-fix dispatch timeout).
- **GREEN** — post-fix, all 15 `ReplacementTransformTests` pass; with the
  opt-in gate off, the contention test is SKIPPED and the other 14 pass.

## Verdict

**ship-as-is.** Two rounds. Round 1: one Medium (contention test), resolved
by opt-in gating. Round 2: clean. The fix removes a buggy, untested,
weakly-protective timeout band-aid and replaces it with a straightforward
synchronous match — fully fixing the silent no-op and the
cooperative-thread-blocking concurrency hazard.
