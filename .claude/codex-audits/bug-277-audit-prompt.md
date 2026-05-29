You are auditing a small DEBUG-only Swift 6 bug fix in the vreader iOS app (worktree at /Users/ll/workspace/vreader/.claude/worktrees/bug277-settle, branch fix/bug-277-readium-settle-slot). This is a read-only audit — do NOT edit files; report findings only.

## Bug #277 (GH #1241)
The DebugBridge `settle` command's Stage-2 WebView-registration gate
(`DebugReaderRegistry.awaitWebViewRegistered(for:format:)`, added by bug #250)
only knew the legacy EPUB/Foliate WKWebView slots. The Readium EPUB engine
(feature #42, behind the default-OFF `readiumEPUBEngine` flag) registers a
`ReadiumNavigatorEvaluating` in a separate registry slot
(`activeReadiumNavigator`), not the `activeEPUBWebView` slot. Result: with the
flag ON, `settle` always wrote `error=webview not registered` even though the
reader rendered. Fix: teach the `.epub` branch of `hasActiveWebView(for:format:)`
to be satisfied by EITHER the legacy EPUB WebView slot OR the Readium navigator
slot, under the same key+token guard.

## Files changed (review these)
- `vreader/Services/DebugBridge/DebugReaderRegistry+WebViewWait.swift` (the gate + two new private satisfier helpers)
- `vreaderTests/Services/DebugBridge/ReadiumDebugProbeTests.swift` (RED→GREEN tests)
- `docs/bugs.md` (row #277 OPEN→FIXED, tracker only)

Read these for context (DO NOT change them):
- `vreader/Services/DebugBridge/DebugReaderRegistry.swift` (the registry, the slots, expectedReaderToken)
- `vreader/Services/DebugBridge/ReadiumDebugProbe.swift` (Readium slot accessors + setActiveReadiumNavigator + token guard)
- `vreader/Services/DebugBridge/RealDebugBridgeContext+Settle.swift` (the settle Stage-1/Stage-2 caller)

## Audit focus (report Critical/High/Medium/Low with file:line)
1. CORRECTNESS: does the `.epub` branch now resolve when only the Readium navigator slot is registered, AND still resolve for the legacy EPUB WebView slot? Is the OR logic correct?
2. EITHER-SLOT does NOT break the legacy gate: the legacy EPUB WebView path and the Foliate (azw3/azw/mobi/prc) path must behave exactly as before.
3. KEY+TOKEN GUARD: the Readium satisfier mirrors the legacy guard — key match, live weak ref, and slot token == expectedReaderToken. Is the same-key reopen race (bug #142 class) still closed? Could a stale navigator binding under an outgoing token falsely satisfy the gate?
4. DEBUG-GATING: the whole file is `#if DEBUG`. `hasActiveEPUBWebView` is additionally `#if canImport(WebKit)` while `hasActiveReadiumNavigator` is not. Is the new `hasActiveReadiumNavigator` call reachable/compilable in the `#else` (no-WebKit) path? The call site is inside the `#if canImport(WebKit)` block of `hasActiveWebView`; the `#else` returns false directly. Confirm no compile break either way and that the verify-release gate (no DEBUG symbols in Release) is not violated.
5. CONCURRENCY: `DebugReaderRegistry` is `@MainActor`. Any Sendable / isolation hazard introduced? The weak ref nil-check on `readiumNavigatorRefInternal` — any TOCTOU concern given main-actor isolation?
6. TEST ISOLATION: the new tests use `makeIsolatedForTests()` (bug #227/#228 pattern) to avoid shared-singleton flake under parallel Swift-Testing/XCTest. Confirm no test reaches into `DebugReaderRegistry.shared` for the new behavioral assertions. Are the RED tests genuinely failing pre-fix (i.e. they assert the new behavior, not a tautology)?
7. Any dead code, duplicate logic, or simplification opportunity.

Be concise. If clean, say "ship-as-is". If there are findings, list them by severity with concrete file:line and a recommended fix.
