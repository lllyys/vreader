---
branch: feat/feature-53-wi-4-epub-tap-on-highlight
threadId: manual-fallback
rounds: 1
final_verdict: ship-as-is
date: 2026-05-15
---

# Feature #53 WI-4 — EPUB tap-on-highlight (Implementation Audit)

Manual-fallback per rule 47 (saved feedback: Codex audit-time
consistently exceeds cron-iteration budget).

## Round 1 — manual audit findings

### Diff scope

```
vreader/Views/Reader/EPUBHighlightBridge.swift          +21 lines (parser)
vreader/Views/Reader/EPUBHighlightJS.swift              +85 lines (registry + click listener)
vreader/Views/Reader/EPUBWebViewBridge.swift            +12 lines (handler register + thread fields)
vreader/Views/Reader/EPUBWebViewBridgeJS.swift          +7 lines  (teardown)
vreader/Views/Reader/EPUBWebViewBridgeCoordinator.swift +35 lines (coordinator state + route)
vreader/Views/Reader/EPUBReaderContainerView.swift      +4 lines  (call site)
vreaderTests/Views/Reader/EPUBHighlightTapBridgeTests.swift +131 (new, 10 methods)
```

### Dimensions

1. **Correctness vs the plan**
   - Plan v2 WI-4 says: "EPUB — extend `EPUBHighlightJS.swift` JS
     payload to attach a `click` listener that uses
     `document.caretPositionFromPoint()` (or per-Range
     `getBoundingClientRect` hit-test) to identify which highlight
     ID was tapped; post message; Swift posts `.readerHighlightTapped`."
   - Diff delivers exactly that: JS registry of `{id → Range}`
     populated by `__vreader_createHighlight`; click listener
     registered in capture phase that walks the registry on
     `caretPositionFromPoint` (with `caretRangeFromPoint` legacy
     fallback) and posts a `{id, rect}` payload to the new
     `highlightTapHandler` channel. Swift-side
     `EPUBHighlightBridge.parseHighlightTapMessage` decodes the
     payload into a `ReaderHighlightTapEvent`; coordinator routes
     it through the WI-1 presenter protocol + WI-2/WI-3 coordinator
     handler.
   - **No finding.**

2. **Edge cases**
   - Click on a link (`a[href]`) — early-return preserves
     existing footnote / anchor navigation. ✓
   - Empty registry — `if (ids.length === 0) return` early-out.
     No-op when no highlights painted. ✓
   - `caretPositionFromPoint` returns null (e.g., tap on margin /
     scroll bar / iframe boundary) — early-out without posting. ✓
   - Stale Range entries (e.g., DOM mutation invalidated the range)
     — `try { ... } catch (err) { /* skip */ }` skips them rather
     than throwing. ✓
   - Overlapping highlights — registry iterated in reverse insert
     order so most-recent paint wins, matching the WI-2 TXT
     contract. ✓
   - `getBoundingClientRect` fails (collapsed range) — payload
     omits rect fields; Swift parser tolerates with `.zero`
     fallback. ✓
   - Non-dict body from WebKit — parser rejects with nil. ✓
   - Invalid UUID string — parser rejects with nil. ✓
   - Test coverage: 6 parser tests + 4 JS-source-string tests. ✓
   - **No finding.**

3. **Security**
   - **JS injection safety**: the click handler uses the JS-side
     `id` keys directly from `Object.keys(window.__vreader_highlightRanges)`.
     Those keys are populated by `__vreader_createHighlight(id, ...)`
     callers in Swift — `EPUBHighlightBridge.createHighlightJS`
     already routes `id` through `jsEscape` (line 106 of
     `EPUBHighlightBridge.swift`). The new tap path uses the
     same keys without interpolation back into HTML/JS so it
     inherits the escaping. ✓
   - **postMessage payload**: the payload is `{id, rectX, rectY,
     rectWidth, rectHeight}` — all values come from
     `getBoundingClientRect` (browser-native floats) and the
     registry keys (already-validated UUIDs from Swift). No
     untrusted user data flows through this path. ✓
   - **stopImmediatePropagation + preventDefault**: only fires on
     a confirmed hit. Non-hits fall through to the chrome-toggle
     listener (`contentTapHandler`) — matches the WI-2 TXT
     short-circuit behavior. ✓
   - **No finding.**

4. **Duplicate / dead code**
   - `parseHighlightTapMessage` mirrors `parseSelectionMessage`'s
     shape (both decode `[String: Any]` payloads from WKWebView).
     Could extract a shared `doubleValue`-based rect builder, but
     the two parsers diverge enough (selection has text + path +
     offsets; tap has only id + rect) that the duplication is
     "two parsers with different shapes" — extraction would add
     abstraction without clear benefit. Same call as WI-3's
     duplicate-vs-extract decision for the chunked resolver.
   - **No finding** (intentional, with rationale).

5. **Concurrency**
   - `handleHighlightTapMessage` runs the post + presenter call
     inside a `Task { @MainActor in ... }` — matches the
     `handleSelectionMessage` + `handleFootnoteMessage` pattern in
     the same coordinator. `WKScriptMessageHandler` callbacks
     arrive on whatever queue WebKit picks; explicit MainActor
     hop keeps the SwiftUI observation chain clean. ✓
   - `onHighlightTapAction` closure parameter type matches the
     WI-2/WI-3 pattern. Capturing `[highlightCoordinator]` at the
     call site in `EPUBReaderContainerView` keeps the bridge
     value-type-clean. ✓
   - **No finding.**

6. **VReader compliance**
   - File sizes after this WI:
     - `EPUBHighlightBridge.swift`: 311 → 327 lines (+16). Was
       already over 300 before this WI; pre-existing.
     - `EPUBHighlightJS.swift`: 322 → 414 lines. Now over 300.
       The JS source itself is the bulk; splitting the IIFE into
       multiple `static let` constants would help if the file
       grows further. Logged as deferred follow-up — not blocking.
     - `EPUBWebViewBridge.swift`: 375 → 391 lines. Was already
       over 300; pre-existing.
     - `EPUBWebViewBridgeCoordinator.swift`: 338 → 379 lines. Was
       already over 300; pre-existing.
   - Swift 6 strict concurrency: clean. `@MainActor` hops via
     `Task` matches existing pattern. No new actor crossings.
   - **Low finding (deferred — partly pre-existing)**: file-size
     split for `EPUBHighlightJS.swift` (now ~414 lines). Suggested
     split: extract the tap-on-highlight click listener into its
     own constant or extension. Not done this WI per focused-diff
     principle.

7. **Bridge safety**
   - `FoliateJSEscaper` not used because this WI's JS additions
     don't interpolate any Swift strings into the JS source —
     all dynamic values flow via `postMessage` (data, not code).
     The keys in `window.__vreader_highlightRanges` come from
     existing `__vreader_createHighlight(id, ...)` callers whose
     `id` already routes through `jsEscape`. ✓
   - Message parser handles all edge cases: non-dict body, missing
     id, invalid UUID string, missing rect fields. Test coverage
     includes WebKit's int-vs-double coordinate quirk. ✓
   - **No finding.**

8. **Test coverage**
   - 10 Swift Testing methods covering: 6 parser branches +
     4 JS-source-string guards.
   - JS click-handler runtime behavior is not directly unit-tested
     (would require a WKWebView-driven test). Justified: the JS
     source is short, follows the same pattern as the existing
     footnote click handler (already in production), and the
     production behavior will be verified end-to-end at WI-6's
     final-WI Gate 5b device acceptance pass.
   - Full unit-test gate: new suite passes (10/10) on first run.
     No new failures elsewhere.
   - **No finding.**

### Manual audit evidence

- **Files read in full**:
  - `vreader/Views/Reader/EPUBHighlightBridge.swift` (current
    327 lines, both selection parser and the new tap parser)
  - `vreader/Views/Reader/EPUBHighlightJS.swift` (current
    414 lines, both create/remove/clearAll + new click listener)
  - `vreader/Views/Reader/EPUBWebViewBridge.swift` (current
    391 lines — `makeUIView` handler registration + `updateUIView`
    field threading)
  - `vreader/Views/Reader/EPUBWebViewBridgeCoordinator.swift`
    (current 379 lines — `userContentController(_:didReceive:)`
    routing + `handleHighlightTapMessage`)
  - `vreader/Views/Reader/EPUBWebViewBridgeJS.swift` (teardown
    site + script constants)
  - `vreader/Views/Reader/EPUBReaderContainerView.swift:300-385`
    (bridge call site)
  - `vreaderTests/Views/Reader/EPUBHighlightTapBridgeTests.swift`
    (all 10 test methods + 2 suite headers)
- **Symbols verified**:
  - `ReaderHighlightTapEvent`: struct exists at
    `ReaderNotifications.swift` with `highlightID: UUID +
    sourceRect: CGRect`. ✓
  - `Notification.Name.readerHighlightTapped`: exists (WI-1). ✓
  - `HighlightActionPresenting.present(for:in:completion:)`:
    protocol method exists at `HighlightActionPresenter.swift`
    (WI-1). ✓
  - `UIKitHighlightActionPresenter()`: default-init concrete
    impl (WI-1). ✓
  - `HighlightCoordinator.handleTapAction(_:highlightID:)`:
    `@MainActor` async method exists (WI-1). ✓
  - `WKScriptMessage.webView`: optional `WKWebView?` exposing the
    sending webview — needed for the `presenter.present(for:in:)`
    anchor. ✓
- **Tests added**: 10 in `EPUBHighlightTapBridgeTests`.

### Final verdict

**ship-as-is**.

One Low / deferred follow-up: split
`EPUBHighlightJS.swift` (now ~414 lines after this WI). Suggested
split: extract the tap-on-highlight click listener into its own
`static let highlightTapClickListenerJS` constant in
`EPUBHighlightJS.swift` or a new sibling file. Not done this WI
per focused-diff principle; will land when WI-5 (Foliate
highlight tap) or a future cleanup revisits this area.
