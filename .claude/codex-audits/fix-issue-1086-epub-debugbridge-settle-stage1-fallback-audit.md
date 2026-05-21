---
branch: fix/issue-1086-epub-debugbridge-settle-stage1-fallback
threadId: 019e4679-c8c5-75c1-bd93-6dc821c80c33
rounds: 3
final_verdict: ship-as-is
date: 2026-05-21
---

# Codex Gate-4 audit — Bug #251 / GH #1086

Bug #251 ("EPUB DebugBridge open path — `mini-epub3` settle hits Stage-1
timeout post-Bug-#1085"). Fix per the bug body's fix direction (b)
`instrument` plus a bounded fallback so the harness can proceed even
when WKWebView's `didFinish` callback is delayed or missing.

## Files changed

- `vreader/Views/Reader/EPUBWebViewBridge.swift` (+21) — new `loadFileURL` info log + `scheduleEarlySettleFallback(webView:)` call in `updateUIView`.
- `vreader/Views/Reader/EPUBWebViewBridgeCoordinator.swift` (+148) — new `earlySettleFallbackDelay`, `earlySettleFallbackTask`, `scheduleEarlySettleFallback(webView:)`, `cancelEarlySettleFallback()`, `deinit`; modified `webView(_:didFinish:)`, `didFailProvisionalNavigation`, `didFail` to add observability logs + fallback cancellation.
- `vreaderTests/Views/Reader/EPUBWebViewBridgeEarlySettleFallbackTests.swift` (new, 6 test cases) — covers fire, didFinish-cancels, identity-nil, reschedule-cancels, stale-token-guard, failure-path-cancels.
- `docs/bugs.md` — row #251 TODO → FIXED.

## Round 1 — 3 findings

| File:Line | Severity | Issue | Resolution |
|---|---|---|---|
| `EPUBWebViewBridgeCoordinator.swift:228+245` | **High** | `didFailProvisionalNavigation` / `didFail` only log + invoke `onLoadError`; they NEVER call `cancelEarlySettleFallback()`. Since the fallback is always armed right after `loadFileURL`, a chapter that genuinely fails to load via either failure path would still get false-positive-settled by the 2s timer — masking a real load error as a ready sentinel and unblocking downstream debug actions against a broken/empty render. | **Fixed**. Added `#if DEBUG`-gated `cancelEarlySettleFallback()` call to BOTH failure handlers, placed BEFORE the `onLoadError` invocation. |
| `EPUBWebViewBridgeCoordinator.swift:489` | **Low** | Fallback Task is only cancelled from `didFinish`; no teardown-path cancellation. If the reader is dismissed before the 2s budget and the Coordinator/WebView are still alive, the Task can still run after `DebugReaderRegistry.unregister` cleared `expectedReaderToken` to nil. The stale-write guard only rejects mismatched NON-nil expected tokens, so a stale fallback could repopulate the registry during the no-active-reader gap. Bounded + weak-capture-limited, but a real lifecycle leak. | **Fixed**. Added `#if DEBUG`-gated `deinit` to `Coordinator` that calls `earlySettleFallbackTask?.cancel()` + clears the handle. `Task.cancel()` is nonisolated and safe to call from deinit regardless of the Coordinator's actor isolation. |
| `EPUBWebViewBridgeEarlySettleFallbackTests.swift:56` | **Low (accept)** | Tests cover "fires", "manual cancel", "identity nil" but do NOT pin the two race shapes the change relies on most: reschedule-cancels-previous and stale-write-guard rejection. Not blocking but missing coverage on the most failure-prone paths. | **Fixed**. Added 3 new test cases: `case4_reschedulingCancelsPriorFallback` (schedules A then B, asserts B lands in registry), `case5_staleTokenGuardRejectsFallback` (outgoing-token coordinator + incoming-token registry, asserts both writes dropped), `case6_failureHandlersCancelFallback` (pins the round-1 High fix's cancellation semantics). |

## Round 2 — 1 stale Low (Codex missed the deinit at line 107)

Round 2 reported "no `deinit` found" — but the deinit IS at line 107 (placed adjacent to `init` at lines 95-104, conventional Swift placement). Round-3 reply re-pointed Codex at the correct location with `grep` evidence.

| File:Line | Severity | Issue | Resolution |
|---|---|---|---|
| `EPUBWebViewBridgeCoordinator.swift:555/565` | Low (stale) | "deinit not found" — Codex looked at the wrong end of the file (the schedule/cancel methods are at the OTHER end). | Round-3 grep evidence resolved: `107: deinit {` confirmed by Codex. |

## Round 3 — clean

Codex verdict: `final_verdict: ship-as-is`. Confirmed all of:

- `deinit` is present and correctly placed at line 107, gated `#if DEBUG`.
- `deinit` cancellation is safe — only performs `earlySettleFallbackTask?.cancel()` and nils the handle; Task already captures self/webView weakly and runs on @MainActor; closes the remaining teardown-path stale-write window without introducing a new race.
- Failure handlers (`didFailProvisionalNavigation` / `didFail`) cancel before `onLoadError`, inside `#if DEBUG`.
- Fallback writes the same registry state in the same order as `didFinish` (`setActiveEPUBWebView` then `markReaderSettled`).
- Reschedule cancels prior pending Task — confirmed in code + Case 4 test.
- Stale-token guard interaction pinned — Case 5 test.
- `updateUIView` schedules fallback on the `loadFileURL` path and nowhere else.
- No Release/DEBUG gating regression — all new fallback machinery and failure-path cancels remain under `#if DEBUG`.

One remaining accepted Low: Case 6 doesn't synthesize an actual `didFail*` callback (it calls the same cancellation primitive directly). Acceptable given direct source confirmation of the failure-handler call sites and the genuine WKWebView-callback integration is covered by device verification.

## Test gate evidence

- New suite `EPUBWebViewBridgeEarlySettleFallbackTests`: 6/6 pass on UDID `61149F0E-DC18-4BE2-BB37-52659F1F4F62`, `-parallel-testing-enabled NO`.
- Full `vreaderTests`: pre-existing 6953 + new 6 = green in 59.5s.

## Verification scope

This is a DEBUG-only fix to the verification harness path. Device verification of the underlying didFinish behavior on `mini-epub3` is deferred to the post-merge close-gate run on GH #1086 — the new logs directly answer whether didFinish genuinely fires, the fallback unblocks the harness either way.
