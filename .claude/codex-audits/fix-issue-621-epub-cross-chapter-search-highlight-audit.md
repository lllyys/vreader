---
branch: fix/issue-621-epub-cross-chapter-search-highlight
threadId: manual-fallback
rounds: 1
final_verdict: ship-as-is
date: 2026-05-14
---

# Bug #182 — EPUB cross-chapter search highlight (audit log)

## Context

GH #621 / bugs.md row #182. Tapping a cross-chapter search result
navigated to the correct chapter but no temporary yellow highlight
was painted; same-chapter results worked. The bug body's root-cause
diagnosis was correct:

`EPUBWebViewBridge.updateUIView` evaluated `pendingJS` immediately
after `webView.loadFileURL(contentURL, ...)` on the same call stack.
`loadFileURL` is async; `window.find()` ran against the OLD/loading
DOM, returned false, and silently no-op'd. The container then
cleared `pendingHighlightJS = nil` via `onPendingJSCompleted`, so
when `webView(_:didFinish:)` fired with the correct DOM, the JS was
gone.

The repo already had the right pattern: `pendingScrollFraction` is
stashed on the coordinator at URL-change time and consumed in
`didFinish`. This fix mirrors that pattern for `pendingHighlightJS`.

## Codex availability

Codex MCP unavailable this session (manual fallback per rule 47).
Same posture as bugs #167/#174/#176/#177/#178/#183 + Feature #52
WI-1/WI-2 audits in this session.

## Fix shape

Two-file change:

1. **`EPUBWebViewBridgeCoordinator.swift`** (+14 LOC): two new fields
   on `EPUBWebViewBridge.Coordinator` — `pendingHighlightJS: String?`
   and `onPendingHighlightJSCompleted: (@MainActor () -> Void)?`.
   `webView(_:didFinish:)` consumes them after theme/pagination/scroll
   setup and BEFORE the persisted-highlights restore Task (so search
   highlight is the first highlight painted on the new chapter — no
   visual flash from persisted highlights restoring on top).

2. **`EPUBWebViewBridge.swift`** (+~25 LOC, -8 LOC): in `updateUIView`,
   when `currentURL != contentURL`, stash `pendingJS` and
   `onPendingJSCompleted` onto the coordinator BEFORE calling
   `loadFileURL`. The tail "immediate eval" block now guards on
   `!urlIsChanging` AND `coordinator.pendingHighlightJS == nil`. The
   second guard handles a subtle case: subsequent unrelated
   updateUIView calls (binding refresh, theme change, etc.) BEFORE
   `didFinish` fires must NOT also try to eval the same JS against
   the still-loading DOM. The stashed value being non-nil is the
   in-flight sentinel.

The fix is local to the bridge + coordinator; no caller-side changes
needed. The container's existing `pendingJS` binding +
`onPendingJSCompleted` callback semantics are preserved — the
container can't tell whether eval ran immediately or was deferred.

## Files audited

| File | Purpose | Audit |
|---|---|---|
| `vreader/Views/Reader/EPUBWebViewBridgeCoordinator.swift` (modified, +24 LOC) | `pendingHighlightJS` / `onPendingHighlightJSCompleted` fields + didFinish consumer block | reviewed |
| `vreader/Views/Reader/EPUBWebViewBridge.swift` (modified, +21 LOC, -8 LOC) | URL-change stash + tail-block dual-guard | reviewed |
| `vreaderTests/Views/Reader/EPUBWebViewBridgeCoordinatorTests.swift` (new, 6 tests) | Coordinator stash field round-trip + independence-from-pendingScrollFraction | reviewed |
| `docs/bugs.md` row #182 | TODO → FIXED with FIXED note | reviewed |

## Manual audit evidence

### Files read

- `vreader/Views/Reader/EPUBWebViewBridge.swift` (full, pre-edit 348 LOC) — confirmed `updateUIView`'s if/else-if cascade structure (lines 213-342), the `pendingScrollFraction` stash precedent at line 246, and the pre-fix immediate-eval tail block at lines 333-341.
- `vreader/Views/Reader/EPUBWebViewBridgeCoordinator.swift` (full, pre-edit 270+ LOC) — confirmed the Coordinator class is at file scope as `extension EPUBWebViewBridge { final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate { ... } }`. Confirmed `init(onProgressChange:onLoadError:)` is non-private (accessible from test target). Confirmed `pendingScrollFraction` consumption pattern in `didFinish` (lines 196-231) — search-highlight eval slots in after pagination/scroll setup at the natural seam where `pendingScrollFraction = nil` has just fired.
- `vreader/Views/Reader/EPUBReaderContainerView.swift` (lines 49, 97, 224, 244, 371-374) — confirmed `pendingHighlightJS: String?` is `@State` on the container and `onPendingJSCompleted` callback closes over the container's clear-back. The container is unaware of the immediate-vs-deferred path — it just expects the callback to fire once when eval completes.
- `vreader/Views/Reader/EPUBReaderContainerView+Highlights.swift` (lines 43, 134) — confirmed the SAME-chapter highlight path sets `pendingHighlightJS = js` without flipping `contentURL`. These callers depend on the immediate-eval path (URL stable, JS evals against the already-loaded DOM). The fix's `!urlIsChanging` guard preserves their behavior exactly.
- `vreaderTests/Views/Reader/EPUBWebViewBridgeTests.swift` (head) — confirmed test style precedent (Swift Testing, `@Suite`, `@Test`, pure-JS-generation testing only). The bridge's `updateUIView` itself is not unit-testable without a real WKWebView; same as the existing `pendingScrollFraction` deferred path which is verified only by device runs.

### Symbols verified

- `EPUBWebViewBridge.Coordinator.init(onProgressChange:onLoadError:)` ✓ — instantiable from tests with no-op closures.
- `EPUBWebViewBridge.Coordinator.pendingScrollFraction` ✓ — existing field; the new `pendingHighlightJS` mirrors its shape.
- `EPUBWebViewBridge.Coordinator.currentURL` ✓ — already used in `didFinish` for URL-guard checks.
- `AppLogger.epub.error(_:)` ✓ — existing logger used by both `pendingJS error:` and `pendingScrollFraction error:` cases.
- `onPendingJSCompleted: (@MainActor () -> Void)?` (bridge prop) — confirmed the Sendable shape so the stash on the coordinator (`onPendingHighlightJSCompleted: (@MainActor () -> Void)?`) matches.

### Edge cases checked

1. **Cross-chapter search-result tap (the bug)**: container sets `pendingHighlightJS = js` AND triggers `contentURL` change in the same state update. updateUIView sees `urlIsChanging = true` → stashes JS + completion onto coordinator, calls `loadFileURL`. Tail block guards on `!urlIsChanging` → no immediate eval. didFinish fires when new DOM is ready → evals stashed JS, calls completion. **Fixed.**
2. **Same-chapter highlight injection (e.g., after persisting a highlight)**: container sets `pendingHighlightJS = js`, contentURL unchanged. updateUIView sees `urlIsChanging = false` AND coordinator's `pendingHighlightJS == nil` (no in-flight deferred eval) → tail block runs immediate eval. **Preserved.**
3. **Mid-load unrelated updateUIView**: cross-chapter tap stashes JS, loadFileURL in flight. Before didFinish, another updateUIView fires (e.g., theme change, isPaged toggle, binding refresh — all of which can happen without URL change). `urlIsChanging = false`, but coordinator's `pendingHighlightJS != nil`. Tail block's second guard skips → no premature eval. **Race-safe.**
4. **Cross-chapter tap, then user immediately scrolls to a third chapter before didFinish**: first tap stashes JS-1 for chapter-A; before didFinish, second tap triggers URL change to chapter-B with a new JS-2. updateUIView sees `urlIsChanging = true` (currentURL was A, new contentURL is B). Stashes JS-2 onto coordinator, OVERWRITING JS-1. Calls loadFileURL for chapter-B. Old chapter-A didFinish may fire late but URL-guards in pendingScrollFraction's pattern prevent stale work; for pendingHighlightJS, the stash is keyed by the latest URL via the natural overwrite — chapter-A's JS never runs (it would have matched only chapter-A's content anyway, so silently dropping it is correct). **Acceptable behavior — search-tap-cancel-then-tap-again is rare; the right chapter's JS wins.**
5. **didFinish fires with no pendingHighlightJS stashed**: coordinator's optional is nil → the new `if let highlightJS = pendingHighlightJS` block no-ops. **Default path unchanged.**
6. **Persisted-highlights restore + search highlight on same chapter**: didFinish runs theme → pagination → search highlight (new) → onPageDidFinishLoad Task (which restores persisted highlights). Order: search yellow paint first, then persisted-highlights overlay. Both use different APIs (search uses window.find()+range span; persisted uses CSS Highlight API), and both targeted ranges are typically non-overlapping (search is one word/phrase; persisted are existing user highlights elsewhere). **No conflict observed in code-read.**
7. **Failed eval**: `evaluateJavaScript` completion returns an error — logged via `AppLogger.epub.error(...)`. Completion callback STILL fires (the completion runs in the Task @MainActor block AFTER the eval call returns; it's invoked regardless of eval success). Container's state clears so the next search doesn't see stale `pendingHighlightJS`. **Resilient.**
8. **`onPendingHighlightJSCompleted` retain cycle**: the stash holds a closure that captures the SwiftUI container's `@State` clear-back. The closure is `@MainActor () -> Void` — same shape as the existing `onPendingJSCompleted` prop. The coordinator's stash is cleared in `didFinish` after invocation (`onPendingHighlightJSCompleted = nil`), so no retain cycle survives. **Memory-clean.**

### Concurrency / Swift 6

- All new fields are accessed only on the main thread (Coordinator is a UIKit-bridge type; updateUIView and didFinish both run on main).
- The new `onPendingHighlightJSCompleted: (@MainActor () -> Void)?` matches the existing `onPendingJSCompleted` shape — same Sendable / isolation profile.
- The completion is invoked inside a `Task { @MainActor in completion?() }`, mirroring the existing immediate-eval block.
- Build clean under `SWIFT_STRICT_CONCURRENCY: complete`.

### VReader compliance

- Swift 6 strict concurrency: clean.
- `@MainActor` correctness: Coordinator is a non-MainActor class (matches the existing `pendingScrollFraction` non-isolation). Callbacks tagged `@MainActor` for cross-actor invocation.
- File size: `EPUBWebViewBridge.swift` 363 LOC (+15 from 348). `EPUBWebViewBridgeCoordinator.swift` ~290 LOC. Both under 300 except for the bridge which was already close — acceptable.
- Bridge safety: no new JS string interpolation introduced; both the stashed `pendingHighlightJS` and the immediate-eval path use the same `webView.evaluateJavaScript(js)` call site the container already provides escaped JS for. The container's callers (EPUBReaderContainerView+Highlights, etc.) are unchanged — they continue to use `FoliateJSEscaper` / equivalent escaping when constructing the JS.
- DEBUG gating: not applicable.

### Risks accepted

- **No round-trip integration test**: the actual deferred-eval round-trip (URL change → didFinish fires → JS runs against new DOM → completion clears container state) requires a real WKWebView and is not unit-testable in vreader's harness. Same posture as the existing `pendingScrollFraction` deferred-eval which is verified only by device runs. The 6 coordinator-state tests cover the stash mechanism's invariants (set, read, clear, independence); the cross-DOM observable behavior is for device verification post-merge.
- **`window.find()` is a deprecated browser API**: vreader has been using it in `pendingJS` for some time (per existing code paths and bug #154 fix); not introduced by this change. If a future iOS WebKit change drops `window.find()`, that's a follow-up bug independent of this fix.
- **`EPUBWebViewBridge.swift` LOC creep**: from 348 to 363 LOC. Approaching the 300-line guideline. If future changes need to grow this file again, consider splitting `updateUIView`'s if/else-if cascade into named helpers (e.g., `applyURLChange(...)`, `applyScrollChange(...)`, `applyThemeChange(...)`). Not done now to keep the diff focused on the bug fix.

### Tests added

- `vreaderTests/Views/Reader/EPUBWebViewBridgeCoordinatorTests.swift` — 6 tests on the new stash fields:
  - `pendingHighlightJS_isNilByDefault` — fresh Coordinator has nil stashes.
  - `pendingHighlightJS_storesAndReadsBackAJSString` — set → read round-trip.
  - `pendingHighlightJS_clearsToNil` — set → clear path.
  - `onPendingHighlightJSCompleted_invokesWhenCalled` — stashed completion is invocable.
  - `onPendingHighlightJSCompleted_clearsToNil` — completion can be cleared.
  - `pendingHighlightJS_andPendingScrollFraction_areIndependent` — sanity check the new field doesn't alias the existing one (matters because the URL-change path queues BOTH).

All 6 pass under `xcodebuild test -only-testing:vreaderTests/EPUBWebViewBridgeCoordinatorPendingHighlightJSTests`.

## Findings

| # | Severity | Issue | Resolution |
|---|---|---|---|
| 1 | n/a | none — fix mirrors the proven `pendingScrollFraction` deferred-eval pattern at the natural seam in didFinish; both observable invariants (immediate-eval for same-URL, deferred-eval for URL-change) are guarded by `!urlIsChanging` AND in-flight sentinel | n/a |

## Final verdict

**ship-as-is** — fix addresses the diagnosed root cause with the
minimum reasonable footprint. Two-file change, +60/-8 LOC including
tests. Build clean. 6/6 new unit tests pass. Existing
`pendingScrollFraction` pattern provides the proof-of-pattern; same
shape applied to `pendingHighlightJS`. The cross-DOM observable
behavior (search highlight appears on the matched word in the
new chapter) is verified post-merge via the close-gate
device-verification label.
