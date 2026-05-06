---
branch: fix/issue-305-foliate-eval-wiring
threadId: 019dfc08-bea5-7f41-806b-e184514e2599
rounds: 2
final_verdict: follow-up-recommended
date: 2026-05-06
---

# Codex audit — bug #141 partial (Foliate eval wiring)

## Round 1

**Findings**:

| File:Line | Severity | Issue | Resolution |
|---|---|---|---|
| `vreader/Views/Reader/ReaderContainerView.swift:419` | Critical | Live AZW3 path dispatches to `FoliateSpikeView`, not `FoliateReaderHost` / `FoliateReaderContainerView` / `FoliateViewBridge`. The new Foliate registry wiring is never exercised on the actual native AZW3 path because nothing in `FoliateSpikeView` calls `DebugReaderRegistry.setActiveFoliateWebView`. The new `probe.jsEvaluator` branch resolves nil and `eval` remains unsupported in practice. | **Fixed** — confirmed `FoliateReaderHost` is dead code (`grep -rn 'FoliateReaderHost(' vreader/` returns nothing). Threaded `fingerprintKey` through `FoliateSpikeView` → `FoliateSpikeWebView` → its private `Coordinator` (DEBUG-only field). Added `webView(_:didFinish:)` to the spike `Coordinator` that calls `setActiveFoliateWebView(webView, for: key)`. `ReaderContainerView.swift:419` now passes `book.fingerprintKey` to `FoliateSpikeView`. The `FoliateViewBridge` wiring stays in place for when the spike eventually gets replaced — both paths register through the same registry API. |
| `vreader/Views/Reader/ReaderContainerView.swift:281` | Medium | Same-book reopen race for Foliate (mirror of bug #142 for EPUB). | **Deferred** — widened bug #142 (GH #306) to cover both EPUB and Foliate. Single fix-shape (per-reader instance token) applies to both bindings. |
| `vreaderTests/Services/DebugBridge/DebugReaderRegistryTests.swift:136` | Medium | 7 new tests cover the registry seam only — they pass even if the shipping reader never registers a Foliate webview. | **Partially deferred** — registry tests are right for the contract they cover. Higher-level live-dispatch test requires an AZW3 fixture. **Filed bug #143 (GH #310)** to bundle a small DRM-free AZW3 fixture, unblocking end-to-end device-verification of the eval path. |

**Verdict round 1**: `block-recommended` (live path was unwired).

## Round 2

After threading the spike-side registration:

**Findings** (all Low):

| File:Line | Severity | Issue | Resolution |
|---|---|---|---|
| `vreaderTests/Services/DebugBridge/DebugReaderRegistryTests.swift:136` | Low | 7 Foliate registry tests cover the keyed-binding regression seam. Sufficient for the registry contract. | No change needed; AZW3 fixture follow-up (#143) tracks the higher-level test. |
| `vreader/Views/Reader/FoliateSpikeView.swift:61` | Low | Live AZW3 spike path now threads `fingerprintKey` into the actual coordinator used by the shipping host. Closes the dead-code hole. | No change needed. |
| `vreader/Views/Reader/ReaderContainerView.swift:419` | Low | Live dispatch passes `book.fingerprintKey`; lookup in `probe.jsEvaluator` can succeed on the active host. | No change needed. |

**Verdict round 2**: `follow-up-recommended`.

Notes:
- `BookFormat.azw3` covers azw3/azw/mobi/prc per `FormatCapabilities` and is the canonical format string set by `BookImporter` / `Book.format`. The single `.azw3` branch in `ReaderContainerView` is correct (no aliasing concern).
- `FoliateViewCoordinator` is `@MainActor` so `webView(_:didFinish:)` is main-actor isolated already; no extra annotation needed.
- DEBUG gating is functionally intact. `FoliateViewBridge.fingerprintKey` and `FoliateSpikeView.fingerprintKey` are compiled in Release as plain optional fields, but they're inert without the DEBUG-gated coordinator setters and registry calls. Low-risk; no Release symbol leak.
- The `FoliateViewBridge` path (FoliateReaderContainerView → FoliateViewBridge → FoliateViewCoordinator) is currently dead code at runtime but kept wired for the future spike-replacement migration. Both paths share the same `setActiveFoliateWebView(_:for:)` API, so the eval lookup site is path-agnostic.

## Summary

Bug #141 partially fixed (eval-for-Foliate portion):
- Spike-path AZW3 eval is now wired via `setActiveFoliateWebView(_:for:)` from `FoliateSpikeView.Coordinator.webView(_:didFinish:)`.
- Future-host (FoliateViewBridge) AZW3 eval is also wired via the same API — single registry, two registration sources.
- Eval closure in `ReaderContainerView.onAppear` for `.azw3` format pulls from `foliateWebView(for: key)` at call-time with stale-protection.

Two follow-ups filed:
- **Bug #143 (GH #310)**: add AZW3 fixture to DebugFixtureCatalog (mechanical) — unblocks end-to-end device-verification of the wiring.
- **Bug #142 (GH #306)**: widened to cover Foliate same-book reopen race alongside the existing EPUB scope. Single fix-shape (per-reader instance token).

Settle 100ms placeholder portion of bug #141 remains open (separate work — needs `relocate`-event listener for Foliate, page-load completion for EPUB).
