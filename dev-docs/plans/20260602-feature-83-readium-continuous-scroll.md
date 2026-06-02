# Feature #83 — Readium EPUB cross-chapter continuous scroll (Gate-1 plan)

Restore Feature #71's VERIFIED cross-chapter continuous scroll on the **Readium**
EPUB engine (`readiumEPUBEngine`, default-ON since 2026-06-01). Today Readium scroll
mode is **per-resource** — content scrolls within a chapter but stops at the spine
boundary; the user must swipe to the next chapter. Resolves **Bug #309 (#1403)**, the
regression of #71 from the Readium default flip (Feature #42 WI-14).

- **Status target**: `TODO` → `PLANNED` (after Gate-2) → … → `VERIFIED`.
- **No new designed chrome** — behavior/rendering only, reuses existing reader chrome
  (like #71 legacy + #76 AZW3). Rule 51 does not gate this.

## Revision history / audit rounds

- **v1** (Gate-1 draft) — recommended approach (B) via observing the resource
  scrollView's overscroll.
- **v2** (Gate-2 round 1 — Codex gpt-5.5/high): **NEEDS REVISION** — Critical: Readium
  3.9.0 does NOT expose the active `WKWebView`/`UIScrollView` publicly and DISABLES
  bounce/overscroll (`scrollView.bounces = false` in `EPUBReflowableSpreadView`), so
  UIKit overscroll is not a viable signal. BUT Readium's public `setupUserScripts`
  hook (vreader already uses it in `ReadiumReaderCoordinator+Transparency`) makes a
  **no-fork JS boundary-intent** variant feasible. Also: `locationDidChange`/
  progression is a guard only (not "tried to scroll past end"); WI-1 must be a
  **feasibility spike**; acceptance is honestly "auto-advance at boundary," not
  pixel-stitched #71. v2 (below) adopts all of this.
- **Gate 2 PASSED** (round 2 — Codex gpt-5.5/high): **READY TO BUILD** as a spike-gated
  feature; all 5 round-1 findings RESOLVED, zero open Critical/High/Medium. Auditor
  confirmed against the vendored Readium 3.9.0 source that `setupUserScripts` is a
  public delegate hook invoked per-spread's `WKUserContentController`. 2 rounds.
  **WI-1 spike is make-or-break — WI-2/WI-3 start only if the spike proves the JS
  boundary signal on device; else escalate.**

## Problem

`ReadiumEPUBHost` mounts Readium's `EPUBNavigatorViewController` (via
`ReadiumNavigatorRepresentable`) with `EPUBPreferences(scroll: true)`. Readium's
navigator is a **per-resource paginator**: each spine item is its own scrollable
resource; crossing a boundary requires `navigator.goForward()`
(`ReadiumEPUBHost+Navigation.swift:96`). "Readium has no multi-spine-stitch API"
(`ReadiumBilingualChapterTracker.swift`). So at a chapter end, scrolling stops and the
user must page-turn — the #309 regression of #71's stitched continuity.

## Prior art / approaches considered

- **#71 legacy** (`EPUBContinuousScrollCoordinator` + `EPUBContinuousScrollJS`) — true
  stitching of spine items into ONE `#vreader-scroll-root` column in vreader's OWN
  `EPUBWebViewBridge` WKWebView. Full DOM control → real seamless continuity. NOT
  portable to Readium (the navigator owns its WKWebViews; no stitch injection point).
- **#76 AZW3** (Foliate windowed `paginator.js`) — windowed K-section mount in the
  vendored Foliate-js paginator. Also depends on owning the paginator; Readium's is
  closed.

### Approaches for the Readium path

- **(A) True cross-resource stitching inside Readium's navigator** — REJECTED as
  primary: Readium's `EPUBNavigatorViewController` is a closed Swift component that
  mounts one resource WebView at a time with no public API to stitch multiple
  resources into one scroll column. Achieving it would require forking/patching
  Readium — high cost, fragile across Readium updates.
- **(B) Boundary auto-advance via a JS boundary-intent signal (RECOMMENDED, revised
  v2)** — keep Readium's per-resource scroll, but make the boundary seamless: when the
  user tries to scroll PAST the end of the current resource, auto-`goForward()` to
  land at the TOP of the next (symmetric `goBackward()` → bottom of the previous). The
  user keeps scrolling and the next chapter appears — no manual swipe.
  **Signal mechanism (Gate-2-corrected):** Readium does NOT expose the resource
  scrollView and disables UIKit bounce, so the boundary signal comes from a small JS
  observer injected through Readium's **public `setupUserScripts` hook** (the same
  hook `ReadiumReaderCoordinator+Transparency` already uses). The script watches
  touch/scroll at the document edges and posts a boundary-intent message
  (`{href, edge: top|bottom, dragDelta}`) via a **weak `WKScriptMessageHandler`**
  proxy (gated by coordinator token + scroll layout + a generation counter, no-op
  after `detach()` — `WKUserContentController` strongly retains handlers + Readium
  owns the WebViews). `locationDidChange`/viewport progression is used only as a
  GUARD (current resource progression near the edge), not as the trigger. Auto-advance
  calls `goForward(animated: false)` to minimise the transition feel. Trade-off vs
  #71: NOT pixel-perfect single-column stitching — Readium swaps resources via
  `PaginationView.slideToView`, so there is a resource-transition **seam** at each
  boundary. The read flow is continuous (no manual swipe) but the seam is visible.
- **(C) Hybrid — legacy WKWebView for scroll mode** — keep `ReadiumEPUBHost` for
  paged, route scroll mode to the #71 legacy `EPUBReaderContainerView`. Faithful to
  #71 but ships two EPUB engines for one format (divergent position/highlight/
  bilingual paths) — high maintenance. Held as a fallback if (B) proves infeasible.

## Surface area (file-by-file) — approach (B), JS-signal variant

### New
- **JS boundary-intent observer** (a string injected via `setupUserScripts`, sibling
  of the transparency user-script) — watches `touchmove`/`scroll`/`touchend` at the
  document edges; when the user drags past the top/bottom with the document already
  scrolled to that edge, posts `{href, edge: "top"|"bottom", dragDelta}` to a named
  message handler. Self-gating (no-op outside scroll layout).
- **`vreader/Views/Reader/ReadiumContinuousScrollModel.swift`** — the testable
  decision logic around the REAL signal shape: given `(href, edge, dragDelta,
  viewportProgressionNearEdge, layout, generation)`, decide `advance` / `retreat` /
  `none`. Debounce/generation-guarded so one boundary drag fires once; requires BOTH
  the JS edge-intent AND the `locationDidChange` progression guard (near 1.0 for
  bottom / near 0.0 for top).
- **`vreader/Views/Reader/ReadiumEPUBHost+ContinuousScroll.swift`** — a weak
  `WKScriptMessageHandler` proxy that receives the JS messages, runs them through the
  model, and calls `navCommander.goForward(animated:false)` / `goBackward` on
  `advance`/`retreat`. Gated by coordinator token + scroll layout + generation;
  no-ops after `detach()`.

### Modified
- **`ReadiumReaderCoordinator` / +Transparency** — register the boundary user-script
  via `setupUserScripts` (alongside transparency) + the weak message-handler proxy on
  `attach`; remove it on `detach()`. Reuse the existing `locationDidChange`
  observation as the progression guard.
- **`ReadiumEPUBHost.swift` / +Body** — install/teardown the continuous-scroll
  coordinator on `epubLayout == .scroll`; clear pending/debounce/generation on
  `.paged`, `submitPreferences`, `detach`, and each new `locationDidChange`.

### Files OUT of scope
- Paged mode; the legacy `EPUBWebViewBridge` #71 path; AZW3/Foliate #76; position
  save/restore + highlights + bilingual + TTS-follow (per-spine paths unchanged —
  auto-advance reuses `goForward`, which already drives `locationDidChange`).
- **No reaching into Readium's private WebView/scrollView subviews** (Gate-2 Critical
  — fragile + Readium owns the scrollView delegate + disables bounce). The signal is
  JS-via-`setupUserScripts` ONLY.

## Work-item sequencing

- **WI-1 (behavioral) — FEASIBILITY SPIKE (make-or-break).** Inject the JS
  boundary-intent observer via `setupUserScripts` + the weak message-handler proxy;
  confirm on-device that a boundary-intent message FIRES reliably when the user drags
  past a resource's bottom/top in Readium scroll mode (and not mid-resource). **If the
  spike fails** (Readium's WebView swallows the edge gesture, or no reliable signal) →
  STOP, fall back to approach (C) hybrid or escalate to the user. Only on spike
  success do WI-2/WI-3 proceed.
- **WI-2 (foundational)** — `ReadiumContinuousScrollModel` pure decision logic +
  tests, built around the REAL signal shape the spike validated.
- **WI-3 (behavioral, final)** — wire signal → model → `goForward(animated:false)`/
  `goBackward`; install in scroll mode with full lifecycle teardown; device-verify
  cross-chapter auto-advance + position/highlights/bilingual continuity across the
  seam.

## Acceptance (honest — Gate-2 corrected)

The acceptance bar is **"scroll auto-advances across the chapter boundary (no manual
swipe), continuously"** — NOT pixel-continuous single-column stitching. A
resource-transition seam at each boundary is expected (Readium's `slideToView`). If
device verification finds the seam unacceptably jarring (large chapters / images /
bilingual / theme), escalate to approach (C) hybrid or back to the user. This honest
framing is recorded on the GH issue + #1403 so "VERIFIED" means auto-advance, not
stitching.

## Test catalogue

- `ReadiumContinuousScrollModelTests` — `(edge=bottom, dragDelta past, progression≈1)`
  → advance; `(edge=top, …, progression≈0)` → retreat; mid-resource → none; paged
  layout → none; debounce (one drag → one advance); generation guard.
- Reuse `ReadiumEPUBReaderViewModel` navigation tests for `goForward/goBackward`.
- Device verification: scroll past a chapter end → next chapter auto-loads + scroll
  continues; position save/restore across the seam; no double-advance.

## Risks + mitigations

- **JS boundary signal reliability (PRIMARY RISK — WI-1 spike).** Whether a
  `setupUserScripts`-injected observer reliably detects "dragged past the edge" inside
  Readium's scroll WebView (which disables UIKit bounce) is the make-or-break. The
  Critical was: do NOT use private scrollView access. Mitigation: WI-1 is a device
  spike; if it fails → (C) hybrid or escalate.
- **Premature advance** (reading near the end ≠ wanting to advance). Mitigation:
  require BOTH the JS edge-drag-intent AND the `locationDidChange` progression guard
  (near the edge), debounced + generation-guarded so one drag fires once.
- **Script-handler lifecycle leaks / stale messages.** `WKUserContentController`
  strongly retains handlers + Readium owns the WebViews. Mitigation: weak proxy, gated
  by token/layout/generation, removed on `detach()` + no-op after.
- **Jarring resource-transition seam.** (B) is auto-advance, not stitching. Mitigation:
  `goForward(animated:false)`; honest acceptance (above); escalate to (C) if the seam
  is unacceptable on device.
- **Position/highlight/bilingual continuity across auto-advance.** Mitigation:
  goForward drives the existing `locationDidChange` → those per-spine paths handle the
  spine change; device-verify.
- **Default-flip interaction.** Closes the #42 WI-14 parity gap #309 exposed; keep the
  legacy #71 path intact as the reversible fallback.

## Backward compat

- No schema change. Scroll-mode-only + Readium-engine-only behavior; paged mode,
  legacy EPUB engine, AZW3, PDF unaffected. The `readiumEPUBEngine`-OFF path (legacy
  #71 continuous scroll) is untouched.

## Audit fixes applied (Gate-2 round 1)

| Finding | Severity | Resolution |
|---|---|---|
| Approach (B) via private scrollView/overscroll is infeasible (Readium hides the WebView/scrollView + disables bounce) | Critical | Signal switched to a JS boundary-intent observer via the PUBLIC `setupUserScripts` hook + a weak `WKScriptMessageHandler`; no private subview access (explicitly out of scope). |
| `locationDidChange`/progression insufficient as the trigger | High | Used only as a GUARD (progression near edge); the trigger is the JS edge-drag-intent. |
| WI-2 model shape `(scrollOffset, contentHeight, viewHeight)` assumes unavailable geometry | High | Model rebuilt around the real signal `(href, edge, dragDelta, viewportProgressionNearEdge, layout, generation)`; the FIRST WI is now a feasibility spike for the JS signal. |
| (B) is auto-advance, not true #71 stitching (seam) | Medium | Honest acceptance section added ("auto-advance, not stitching"); `goForward(animated:false)`; escalate to (C) if the seam is unacceptable. |
| Script-handler retention/teardown | Medium | Weak proxy, token/layout/generation gating, removed on `detach()`. |
| Layout-change lifecycle | Medium | Reset pending/debounce/generation on `.paged`/`submitPreferences`/`detach`/`locationDidChange`. |

## Make-or-break (WI-1 spike)

The whole feature hinges on the WI-1 device spike: does a `setupUserScripts`-injected
boundary observer reliably fire "dragged past the edge" in Readium scroll mode? **If
the spike fails, STOP and escalate** (approach (C) hybrid, or revert the flip per the
user's earlier #309 options). Gate-3 of WI-2/WI-3 does not start until the spike
succeeds on device.
