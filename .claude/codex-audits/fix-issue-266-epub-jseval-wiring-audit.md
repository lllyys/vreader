---
branch: fix/issue-266-epub-jseval-wiring
threadId: 019dfbda-293f-7d21-a1c8-2f1c58801ca1
rounds: 2
final_verdict: follow-up-recommended
date: 2026-05-06
---

# Codex audit — bug #126 (DebugBridge EPUB eval wiring)

## Round 1

**Findings**:

| File:Line | Severity | Issue | Resolution |
|---|---|---|---|
| `vreader/Views/Reader/ReaderContainerView.swift:266` | High | EPUB eval dereferences a single global `DebugReaderRegistry.activeEPUBWebView` slot with no fingerprint check. A late `didFinish` from an outgoing book can make a new probe evaluate against the wrong book silently. | **Fixed** — replaced single global slot with keyed binding `(weak webView, String key)`. Public API: `setActiveEPUBWebView(_:for:)` + `epubWebView(for:)`. `unregister` and `reset` clear both. Coordinator gained DEBUG-only `fingerprintKey` field threaded from EPUBWebViewBridge → EPUBReaderContainerView → EPUBReaderHost (`fingerprint.canonicalKey`). Eval closure in ReaderContainerView captures `key = book.fingerprintKey` and asks `epubWebView(for: key)`. |
| `vreader/Views/Reader/ReaderContainerView.swift:264` | Low | Raw string match `book.format == "epub"` instead of typed enum. Case/aliasing drift would silently skip the wiring. | **Fixed** — `if resolvedBookFormat == .epub`. Enum is the source of truth. |
| `vreaderTests/Services/DebugBridge/DebugReaderRegistryTests.swift:79` | Low | Tests only prove the property exists. No coverage for the regression seam (stale-webview protection, nil-before-first-load, JSON normalization). | **Fixed** — replaced 2 thin tests with 6 focused tests covering: initial nil for any key, set/read for matching key, **mismatch returns nil (the regression seam)**, replace previous binding, unregister clears when key matches, reset clears unconditionally. 22 tests in DebugReaderRegistryTests + DebugBridgeTests pass. |

**Verdict round 1**: `block-recommended`.

## Round 2

After applying the round-1 fixes, Codex re-audited.

**Findings**:

| File:Line | Severity | Issue | Resolution |
|---|---|---|---|
| `vreader/Services/DebugBridge/DebugReaderRegistry.swift:131` | Medium | Same-book reopen race: after `unregister()` clears the slot, a late `didFinish` from an outgoing webview can re-register the OLD webview under the same fingerprint key, and `epubWebView(for:)` will accept it because the key matches. | **Deferred to follow-up bug #142 (GH #306)**. Damage is narrow: same content, only DOM state differs; requires sub-second close→reopen of the same book. Fix shape (per Codex recommendation) is per-reader instance token threaded alongside the key — non-trivial diff that doesn't belong in this PR. The current keyed fix is materially better than the original global slot; the same-book race is a strictly narrower concern. |

**Verdict round 2**: `follow-up-recommended`.

## Summary

The bug #126 fix shipped in this PR (v3.14.13):
- EPUB JS eval is wired end-to-end via `DebugReaderRegistry.epubWebView(for:)` keyed binding.
- Different-book stale-webview attacks (the original High) are blocked.
- Typed `BookFormat` enum is the source of truth for the wire-up gate.
- Test coverage exercises the regression seam, not just the property's existence.

Two follow-up bugs filed:
- **Bug #141 (GH #305)**: settle 100ms placeholder + AZW3/Foliate eval unwired (originally part of #126's description; split out so the EPUB-eval portion could ship cleanly).
- **Bug #142 (GH #306)**: same-book reopen race (Codex round-2 finding, narrow lifecycle hole).

DEBUG gating verified by inspection in both rounds. Concurrency / actor isolation looks clean (`@MainActor` closure, `WKWebView.evaluateJavaScript` async-throwing on iOS 14+). No new Sendable issues. Release build still hides all new symbols (the existing `verify-release-no-debugbridge.sh` gate continues to pass — not re-run in this read-only Codex session, will be exercised by CI on PR open).
