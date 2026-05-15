---
branch: fix/issue-682-autopage-turner-recursion
threadId: 019e2972-edcd-7762-b62b-0c401993423f
rounds: 2
final_verdict: ship-as-is
date: 2026-05-15
---

# Codex audit log — Bug #191 (GH #682) — AutoPageTurner.interval @Observable recursion

## Round 1 findings

| # | File | Severity | Finding | Resolution |
|---|---|---|---|---|
| 1 | `vreader/Services/AutoPageTurner.swift:129` | Medium | `clampInterval(_:)` `max(1.0, min(60.0, value))` propagates `.nan` because NaN comparisons return false. `Task.sleep(for: .seconds(.nan))` in `scheduleTimer` would hit undefined behavior. | Added `guard value.isFinite else { return 5.0 }` before clamping. Reset-to-default is safer than 1.0-default because it surfaces as a noticeably-but-not-catastrophically-wrong cadence rather than a runaway timer. Added 3 regression tests (`intervalClamped_nan_resetsToDefault`, `_positiveInfinity_`, `_negativeInfinity_`). |
| 2 | `vreader/Services/AutoPageTurner.swift:56` | Low | Manual `withMutation(keyPath:)` always emits an observation transaction, unlike the macro-synthesized setter which can short-circuit identical writes. Repeated writes to the same clamped value would notify observers unnecessarily. | Setter now clamps first, then `guard clamped != _intervalRaw else { return }` before calling `withMutation`. Matches the macro's `shouldNotifyObservers` semantics. |

## Round 2 verdict

Codex confirmed both findings closed correctly. Zero new findings. Verdict: **ship-as-is**.

One residual note (deferred, NOT blocking): "An explicit observation-tracking parity test analogous to `AISettingsViewModelTests.toggleNotifiesObservationTracker()` would be a useful follow-up to pin the new manual observation contract directly." Not added in this PR — the production Settings UI slider exercises the observation surface; the regression test pins the load-bearing crash fix.

## Test gate

`xcodebuild test -only-testing:vreaderTests/AutoPageTurnerTests` — 24 tests in 1 suite, all passing (5.5s).

Pre-fix, the test runner aborted silently after the first `turner.interval = X` call hit ~23.7k-frame stack-guard fault (10 tests reported as passing, then the suite died without naming any of the 11+ remaining tests). The fix doubles the visible test count.

## RED→GREEN proof

Pre-fix: `xcodebuild test -only-testing:vreaderTests/AutoPageTurnerTests/intervalClamped_aboveMax_becomesMax()` → SIGSEGV, no test-name output, `** TEST FAILED **`.

Post-fix: same invocation → test passes in 0.001s. Same shape for all 6 pre-existing clamping tests + 4 start/stop/pause tests that set `interval`.

## Bug context

Filed in this same session at PR #683 (`9f1b83a`); GH #682. Diagnosed during Feature #31 round-5 verify-cron from two crash reports in `~/Library/Logs/DiagnosticReports/vreader-*.ips`. Root cause: `@Observable` macro splits user-written `interval` property into computed wrapper + stored `_interval` backing; the original didSet body wrote to the wrapper, which dispatched to the public setter, which wrote to the backing, refiring its didSet — ~23k-frame stack-guard fault.

Fix: `@ObservationIgnored private var _intervalRaw: TimeInterval = 5.0` + computed `interval` with manual `access(keyPath:)` / `withMutation(keyPath:)` — the documented Apple primitive for adding custom logic to `@Observable` properties.

Also resolves Feature #31 round-4's mysterious dismissal-on-book-open symptom (the reader-open path initialized AutoPageTurner with a stored interval value, triggered recursion, app died silently).
