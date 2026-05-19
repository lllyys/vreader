---
branch: feat/feature-57-wi-1-extract-plain-text-seam
threadId: 019e3e6d-d1b1-79f0-9831-5f04c475c117
rounds: 2
final_verdict: ship-as-is
date: 2026-05-19
---

# Codex Audit — feature #57 WI-1 (AZW3/MOBI TTS text-extraction seam)

Gate-4 implementation audit of the WI-1 diff (vs `origin/main`).

## Scope

Files changed:
- `vreader/Services/Foliate/JS/foliate-host.js` — added `readerAPI.extractPlainText()`
- `vreader/Services/Foliate/JS/foliate-bundle.js` — regenerated via `build-bundle.sh` (esbuild output)
- `vreader/Views/Reader/FoliateCoordinatorBox.swift` — NEW
- `vreader/Views/Reader/FoliateSpikeView.swift` — `coordinatorBox:` binding + `extractPlainText()` + constants
- `vreader/Views/Reader/ReaderContainerView.swift` — `@State foliateCoordinatorBox` + wiring
- `vreaderTests/Views/Reader/FoliateSpikeViewTTSTests.swift` — NEW (6 tests)

## Round 1 — findings

| file:line | severity | issue | fix |
|---|---|---|---|
| FoliateSpikeView.swift:600 | High | `extractPlainText()` used `await webView.evaluateJavaScript("readerAPI.extractPlainText()")`. `evaluateJavaScript`'s completion fires when an async expression *creates* its Promise, not when the Promise *resolves* (the file's own `book-ready` handler documents exactly this). The seam would return before the section-walk finished — likely `nil` / an unsupported JS object instead of the extracted whole-book string. | Use `callAsyncJavaScript` (Promise-aware) or a script-message channel. |
| FoliateSpikeView.swift:598 | Medium | No timeout / cancellation path for a hung JS extraction. A malformed Foliate section or a wedged WebKit render would suspend the `async` method indefinitely; `try?` only swallows thrown errors, not hangs. Misses an explicit WI edge case. | Wrap the JS await in a bounded timeout race; return `nil` on expiry so a future TTS caller cannot wedge. |

Clean dimensions (round 1): JS-injection surface (fixed literal, no interpolation); JS helper section guards (empty book, missing `createDocument`, per-section throw); no duplicate/dead code beyond the intentionally-DEBUG-only-callable seam; `@MainActor` correctness; the weak-coordinator hold (no retain cycle).

## Resolutions

**Finding 1 (High) — fixed.** `extractPlainText()` rewritten to use `WKWebView.callAsyncJavaScript` instead of `evaluateJavaScript`. `callAsyncJavaScript` runs its body as an async function and awaits the return value, so a returned `Promise<string>` is resolved before the call completes. The `extractPlainTextScript` constant changed from the expression `readerAPI.extractPlainText()` to the async-function body `return await readerAPI.extractPlainText();`. `contentWorld: .page` (the page main world where `readerAPI` lives), `arguments: [:]`, `in: nil`. This also closes the plan's round-2 Finding 3 "Promise-marshalling feasibility item" at the code level — `callAsyncJavaScript` is the documented Promise-aware API; WI-1's device slice still confirms it end-to-end against a real render.

**Finding 2 (Medium) — fixed.** `extractPlainText()` now races the JS call (a `@MainActor` `Task` with an explicit `[webView]` capture) against a timeout `Task` (`Task.sleep(for:)`, new `extractPlainTextTimeout: Duration = .seconds(12)` constant) inside a `withTaskGroup`. Whichever finishes first wins; on timeout the JS task is cancelled (a cancelled `callAsyncJavaScript` throws → `try?` → `nil`) and `nil` is returned; on JS completion the timeout task is cancelled. A wedged extraction therefore frees the caller after 12s. New unit test `extractPlainText_hasBoundedTimeout` asserts the constant is bounded. (This also makes WI-2's planned `awaitExtraction` timeout wrapper redundant — the bound now lives in the seam itself.)

An earlier `withTaskGroup` shape tripped the Swift 6 region-based isolation checker; resolved by the explicit `[webView]` capture list on the `@MainActor` JS `Task` (both contexts are main-actor isolated — no region crossing).

## Round 2 — verification

Re-reviewed `FoliateSpikeView.swift` + `FoliateSpikeViewTTSTests.swift`. Verdict: **no remaining Critical/High/Medium.** Finding 1 resolved (`callAsyncJavaScript` + page-world await — the correct seam). Finding 2 resolved (bounded timeout race; loser cancelled; no orphaned Task / leak; the `[webView]` capture is the right Swift 6 isolation shape; the timeout path frees the caller). The new test pins the timeout bound.

## Verdict

**ship-as-is.** Zero open Critical/High/Medium after 2 rounds. Build succeeds under Swift 6 strict concurrency; all 6 `FoliateSpikeViewTTSTests` pass.
