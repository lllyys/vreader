---
branch: fix/bug-279-epub-viewport-lock
threadId: 019e745e-1d10-73c0-8397-9bdabdb3d940
rounds: 2
final_verdict: ship-as-is
date: 2026-05-29
---

# Gate-4 Codex audit — Bug #279 / GH #1256 (EPUB content pan/zoom lock)

Independent audit (author/auditor separation: Codex `gpt-5.5` via `codex exec --sandbox read-only`,
separate process from the implementing Claude Code session).

Scope of diff audited (`git diff main`):

- `vreader/Views/Reader/EPUBWebViewBridge.swift` — wiring: inject `viewportLockJS` user script + call `applyScrollLock` in `makeUIView`; header `Key decisions` note.
- `vreader/Views/Reader/EPUBWebViewBridgeJS.swift` — new `applyScrollLock(to:)` scroll-view seam + `viewportLockJS` static literal.
- `vreaderTests/Views/Reader/EPUBWebViewBridgeTests.swift` — new scroll-lock + viewport-lock-JS + live-WKWebView DOM-harness suites.

## Round 1 — verdict: follow-up-recommended (0 Critical / 0 High / 0 Medium / 2 Low)

| file:line | severity | issue | resolution |
| --- | --- | --- | --- |
| `EPUBWebViewBridgeJS.swift:80` (scroll-lock seam) | Low | `alwaysBounceHorizontal = false` only suppresses horizontal rubber-band; it does NOT pin the pan axis if a chapter creates real horizontal overflow. The comment + test overstated it as "locks panning to the vertical axis." | **Fixed.** Added `scrollView.isDirectionalLockEnabled = true` — the lever that actually constrains a drag to one axis at a time. Narrowed the comment + test wording so `alwaysBounceHorizontal` is described only as the rubber-band suppressor. New test `applyScrollLockEnablesDirectionalLock` asserts the directional lock; `applyScrollLockIsIdempotent` extended to cover it. |
| `EPUBWebViewBridgeTests.swift:502` (viewport-lock-JS tests) | Low | The `viewportLockJS` tests were string-shape assertions only; they would not catch a DOM regression (duplicate meta, failure to overwrite a permissive viewport, no-`<head>` document). | **Fixed.** Added `EPUBWebViewBridgeViewportLockDOMTests` — a live-`WKWebView` harness that runs the production `viewportLockJS` and asserts the resulting `meta[name=viewport]` content + count across three cases: (a) absent → exactly one meta created with the pinned content; (b) permissive `user-scalable=yes, maximum-scale=5` → overwritten in place, count stays 1; (c) head-less document → still pinned. |

Round-1 non-findings recorded by the auditor: no JS-injection surface (`viewportLockJS` is a fixed literal, well-formed IIFE); no conflict with the bug #167 background / #163 safe-area seams; the unconditional injection into continuous-scroll mode is idempotent/harmless (overwrites the bootstrap viewport with a stricter equivalent); paged-mode JS `scrollLeft` navigation is unaffected because paged mode sets `isScrollEnabled = false` and mutates DOM scroll state directly; `EPUBWebViewBridge.swift` was already over the soft cap but the diff did not materially worsen it (most new code landed in the JS extension + tests).

## Round 2 — verdict: ship-as-is (0 findings)

Re-audited the updated diff. Auditor confirmed:

- Both round-1 Low findings genuinely resolved (not papered over): `applyScrollLock` now uses `isDirectionalLockEnabled = true`; the DOM tests execute the production `EPUBWebViewBridge.viewportLockJS` in a live `WKWebView`.
- No new issues with paged mode, normal vertical scrolling, the `loadHTMLString` → `didFinish` → evaluate sequence, or the Swift 6 continuation wrappers (`run` / `evaluateString` + `@MainActor private LoadWaiter`).

## One-line verdict

Ship-as-is after 2 rounds: the fix locks the legacy EPUB raw-spine path against pinch-zoom + off-axis pan via a scroll-view zoom/directional-lock pin plus a forced non-scalable viewport meta, mirroring the Foliate spike and continuous-scroll bootstrap; full unit suite (7598 tests / 744 suites) green.
