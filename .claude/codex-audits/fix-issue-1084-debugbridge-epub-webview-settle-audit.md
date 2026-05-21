---
branch: fix/issue-1084-debugbridge-epub-webview-settle
threadId: 019e4638-0d41-7531-b97a-6d4d56825d45
rounds: 3
final_verdict: ship-as-is
date: 2026-05-21
---

# Codex Gate-4 audit — Bug #250 / GH #1084

Bug #250 ("DebugReaderRegistry WebView registration race for EPUB —
host-driven highlight-create observer can fire before EPUB WebView
registers"). Fix per task brief Direction (1): extend
`vreader-debug://settle?token=opened` to wait for both (a) the existing
probe-level render-complete signal AND (b) `DebugReaderRegistry`
WebView registration for EPUB/AZW3 books.

## Files changed

- `vreader/Services/DebugBridge/DebugReaderRegistry+WebViewWait.swift` (new, 156 lines)
- `vreader/Services/DebugBridge/DebugReaderRegistry.swift` (+15 internal accessors)
- `vreader/Services/DebugBridge/RealDebugBridgeContext+Settle.swift` (+48 two-stage)
- `vreaderTests/Services/DebugBridge/RealDebugBridgeContextTests.swift` (+269, 6 new tests + `SettleOKProbe`)
- `docs/bugs.md` (+1 row)
- `vreader.xcodeproj/project.pbxproj` (xcodegen)

## Round 1 — 4 findings

| File:Line | Severity | Issue | Resolution |
|---|---|---|---|
| `DebugReaderRegistry+WebViewWait.swift:60` | High | Gate was key-only, but production `epubWebView(for:token:)` is key+token-keyed. Same-key reopen race: outgoing reader A's slot persists past A's `unregister` when reader B took over before A's `onDisappear`; A's slot's KEY still matches B's `fingerprintKey` but A's stored TOKEN no longer equals B's. A token-agnostic gate would falsely report "registered" while downstream highlight-create fails. | **Fixed**. `hasActiveWebView(for:format:)` now requires `expectedReaderTokenForTests == activeToken` for both EPUB and Foliate slots. |
| `DebugReaderRegistry+WebViewWait.swift:48` | Medium | `formatRequiresWebView` and `hasActiveWebView` matched lowercase literals only, but `probe.format = book.format` (raw, can be mixed case). The reader dispatch path lowercases via `BookFormat(rawValue: book.format.lowercased())`; this helper did not. | **Fixed**. Both helpers normalize via `.lowercased()` before switching. |
| `RealDebugBridgeContextTests.swift:944` | Medium | Tests didn't exercise the stale-slot regression. Without a stale-slot test, the key-only implementation would have passed Stage 2 incorrectly and the suite would stay green. | **Fixed**. New `test_settle_onEPUBProbe_withStaleTokenWebView_writesWebViewNotRegisteredError` preloads the registry with reader A's WebView slot then advances `expectedReaderToken` to a fresh token B, asserts `webview not registered`. Plus `test_settle_onEPUBProbe_withMixedCaseFormat_stillEntersWebViewGate` to pin the casing fix. |
| `RealDebugBridgeContext+Settle.swift:81` | Low | Stage 2 always waited `Self.webViewWaitSeconds` (5s) — the new tests' comments incorrectly claimed `timeoutSeconds: 0.5` avoids the 5s wait. | **Fixed**. `settleWithTimeout(token:timeoutSeconds:webViewWaitSeconds:)` accepts an optional Stage-2 override, defaulting to `Self.webViewWaitSeconds` for production. All 6 new tests pass `webViewWaitSeconds: 0.2`; suite time dropped from 11.7s → 2.4s. |

## Round 2 — 1 Low finding

| File:Line | Severity | Issue | Resolution |
|---|---|---|---|
| `DebugReaderRegistry+WebViewWait.swift:140` | Low | Poll used wall-clock `Date()`. NTP/manual time changes could make the poll exit early or hang past the intended budget. | **Fixed**. Switched to `ContinuousClock` (`let clock = ContinuousClock(); let start = clock.now; while (clock.now - start) < budget {...}`). `Task.sleep` retained for cancellation-awareness. |

## Round 3 — clean

Codex verdict: `final_verdict: ship-as-is`. Confirmed:

- `ContinuousClock` is the right monotonic primitive on Apple platforms (vs. `SuspendingClock`).
- No overflow risk in `Int64(timeout * 1_000_000_000)` — production max is 5s = 5e9, comfortably in range.
- The tail-check after the loop handles a registration landing at or just after the boundary — no off-by-one.
- Two-stage settle path preserves production semantics: `settle()` continues to call `settleWithTimeout(token:timeoutSeconds:)` which defaults Stage 2 to `Self.webViewWaitSeconds = 5.0`.
- Round-1 fixes still correctly applied: lowercase normalization in both helpers, token-aware gate against `expectedReaderTokenForTests`, stale-token + mixed-case regression tests in place.

## Test evidence

- Focused `vreaderTests/RealDebugBridgeContextTests`: 60 tests / 0 failures in 2.4s (UDID `61149F0E-DC18-4BE2-BB37-52659F1F4F62`).
- Full `vreaderTests`: 6953 tests / 691 suites green in 37s (post-round-1 fixes).
