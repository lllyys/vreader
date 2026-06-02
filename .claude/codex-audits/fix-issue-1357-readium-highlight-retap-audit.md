---
branch: fix/issue-1357-readium-highlight-retap
threadId: codex-exec (run-codex.sh)
rounds: 1
final_verdict: ship-as-is
date: 2026-06-03
---

# Codex audit — Bug #302 (GH #1357, REOPENED): Readium highlight re-tap

## Fix summary

The original #302 fix opened the highlight edit popover on the FIRST tap, but a
SECOND tap of the same highlight didn't re-open it (re-arm gap). Root cause: the
popover consumer presents off `.onChange(of: viewModel.presented)`, and only the
in-card CLOSE BUTTON routes dismissal through `dismissEverything()` (which calls
`viewModel.dismiss()` → `presented = nil`). The `.sheet`'s own `onDismiss` — an
interactive SWIPE-DOWN, the normal dismissal for Readium since its highlight tap
resolves to a `.zero` sourceRect → the sheet form — routed to `sheetDidDismiss()`,
which did NOT reset the view model. So `presented` stayed at the dismissed
highlight; a same-highlight re-tap set the same content value → no `.onChange` →
no re-open.

**Fix:** `sheetDidDismiss()` now resets `router.dismiss()` + `viewModel.dismiss()`
when `viewModel.presented != nil` (stale), so every sheet dismissal re-arms. The
share follow-up still works (the stashed `action?()` presents the share sheet
FIRST; the reset is a harmless idempotent state-clear after).

Changed files:
- `vreader/Views/Reader/HighlightPopoverModifierBody.swift` (`sheetDidDismiss`)
- `vreaderTests/ViewModels/HighlightPopoverViewModelTests.swift`
  (`handleTap_afterDismiss_reArmsSameHighlight`)

## Round 1 — CLEAN

Codex confirmed:
- Share follow-up path still works (share action runs before the cleanup).
- The double-dismiss is benign — `router.dismiss()` only drives
  `routePresentation()` into its nil branch (sheet already nil → no-op card
  teardown); `viewModel.dismiss()`'s second `router.dismiss()` is idempotent.
- **No producer-side re-arm bug**: `ReadiumDecorationHighlightAdapter`'s
  `observeDecorationInteractions` observer is stateless and posts
  `.readerHighlightTapped` directly on activation — nothing leaves a decoration
  "one-shot armed". So the consumer fix is complete; there is no second
  (producer) gap.
- Swipe-down-while-share-pending converges through the same single `onDismiss`
  path; ordering stays "share action, then cleanup".
- Residual: the VM test proves the re-arm contract but doesn't drive the
  `sheetDidDismiss()` path itself (coverage gap, not a defect — the modifier
  presentation is verified on device).

I corrected the fix's inline comment (the original "presented == nil on share
teardown" premise was wrong; the share ordering, not that premise, is what makes
it safe).

## Verdict

`ship-as-is` — zero findings; Codex confirmed the fix closes the re-arm gap with
no producer-side counterpart. VM re-arm contract unit-tested. The end-to-end
Readium-decoration re-tap is hard to reproduce CU-free (webview decoration +
`.zero` rect → the app doesn't know the on-screen position), so the GH issue is
merged `awaiting-device-verification` for the verify cron / a keyed pass.
