---
branch: feat/feature-126-wi-8-acceptance
threadId: 019f11c6-bee0-79f3-81a0-9ce215a72d54
rounds: 1
final_verdict: ship-as-is
date: 2026-06-29
---

# Gate-4 audit — feature #126 WI-8 (reader hardening + tracked reading-interaction bug)

WI-8 is NOT a feature-completion — Gate-5 acceptance found a BLOCKING reading-interaction
bug (#357 / GH #1860): the AZW3 reader renders + resumes, but next()/scroll do not advance
the content (only `goToFraction` seeks). Exhaustively isolated: NOT the security patch
(unpatched bundle identical), NOT Compose touch-routing (real `UiDevice` swipes also fail),
NOT the WebViewClient (a permissive client also fails), NOT the renderer freezer.

This WI ships only the legit hardening + the tracked bug + the `@Ignore`'d verification target.
Codex (gpt-5.5/high): **ship-as-is**, no findings. Confirmed:
- `setRendererPriorityPolicy(RENDERER_PRIORITY_BOUND, false)` is correct (keeps the renderer
  alive while the reader is open; drops with the app when backgrounded — render-death recovery
  handles a kill).
- The `WebChromeClient` logs only ERROR/WARNING console messages to logcat (no PII/spam) —
  appropriate, mirrors iOS error logging.
- `@Ignore`'ing the scroll test (a documented verification target) over deleting it is correct.
- Filing #357 + keeping #126 not-VERIFIED is the honest outcome.

Verification: `Azw3ReaderActivityTest` render + restore pass on emulator; scroll test `@Ignore`'d (skipped).

**Verdict: ship-as-is.**
