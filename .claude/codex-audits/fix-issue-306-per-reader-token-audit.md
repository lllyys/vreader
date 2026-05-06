---
branch: fix/issue-306-per-reader-token
threadId: 019dfc80-61a2-7c61-8c92-b6c98535e272
rounds: 2
final_verdict: ship-as-is
date: 2026-05-06
---

# Codex audit — bug #142 (per-reader instance token)

## Round 1

**Findings**:

| File:Line | Severity | Issue | Resolution |
|---|---|---|---|
| `vreader/Services/DebugBridge/DebugReaderRegistry.swift:141` (and Foliate twin :176) | High | `setActiveEPUBWebView(_:for:token:)` still unconditionally overwrites the slot. A stale `didFinish` from the outgoing reader can clobber `(key, T2)` with `(key, T1)`. The token check on lookup then prevents wrong-webview eval, but degrades to `evalUnsupported` instead. The race is converted, not eliminated. | **Fixed** — added `expectedReaderToken: UUID?` field on the registry. `setExpectedReaderToken(_:)` called from `ReaderContainerView.onAppear` BEFORE `register(probe)`. Both `setActiveEPUBWebView` and `setActiveFoliateWebView` reject writes whose token != expectedReaderToken. `unregister`/`reset` clear the expected token. |
| `vreaderTests/Services/DebugBridge/DebugReaderRegistryTests.swift:198` | Medium | New regression tests prove only that mismatched tokens return nil. They don't drive the actual failure ordering: `new(T2) binds → stale old(T1) didFinish → eval(T2) must still return newWebView`. | **Fixed** — added `test_epubWebView_lateStaleDidFinishCannotClobberCurrentReader` + Foliate twin. Both register newWebView with expectedToken=T2, then call setActive with old T1 (the stale didFinish), then assert lookup with T2 returns newWebView. With round-1 fix this would have returned nil; with round-2 fix it returns newWebView. |

**Verdict round 1**: `block-recommended`.

## Round 2

After applying the round-1 fixes:

**No new findings.**

Codex round-2 confirmation:

> (a) The stale-write guard closes the clobber window. Once `ReaderContainerView.onAppear` calls `setExpectedReaderToken(readerToken)` before `register(probe)`, any later old-reader didFinish carrying T1 is rejected. Preserves the current (key, T2) binding instead of degrading to nil.
>
> (b) `expectedReaderToken == nil` does not introduce a new correctness problem in the current single-reader model. The important transition is protected because the new mount sets the expected token before probe registration, and stale old unregister calls don't clear the new token thanks to the `activeReader === reader` guard.
>
> (c) The new ordering tests model `new(T2) binds → stale old(T1) didFinish fires after → lookup(T2) must still return newWebView`, which is exactly the race that round 1 still failed.

**Verdict round 2**: `ship-as-is`.

## Summary

Bug #142 fully fixed:
- Per-reader UUID token threaded through both EPUB (`EPUBWebViewBridge` → `EPUBWebViewBridgeCoordinator`) and Foliate (`FoliateViewBridge` → `FoliateViewCoordinator` + `FoliateSpikeView` → spike `Coordinator`) paths.
- Registry stores `(token, key, webView)`; lookup requires both key + token to match.
- Stale-write guard: `expectedReaderToken` set by `ReaderContainerView.onAppear` before probe registration; `setActive*WebView` rejects mismatched-token writes.
- 34 tests pass (10 DebugBridge + 24 DebugReaderRegistry, including 5 new tests for the bug #142 regression seam — 3 from round 1 + 2 ordering tests from round 2).

DEBUG gating: `expectedReaderToken` field and the EPUB/Foliate raw test seams are inside the existing `#if canImport(WebKit)` block (which itself is inside `#if DEBUG`). The non-DEBUG `readerToken` `@State` field on `ReaderContainerView` carries an unused UUID through Release — single allocation per reader mount, no behavioral leak.

The Foliate-host path (`FoliateReaderContainerView` via `FoliateViewBridge`) is dead code today; it passes `readerToken: nil` so registration is silently skipped on that path. Live AZW3 path (`FoliateSpikeView` via spike `Coordinator`) gets the real token and registers correctly.
