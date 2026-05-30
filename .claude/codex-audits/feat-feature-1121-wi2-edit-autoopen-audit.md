---
branch: feat/feature-1121-wi2-edit-autoopen
threadId: codex-exec-2026-05-31-feat1121-wi2
rounds: 1
final_verdict: ship-as-is
date: 2026-05-31
---

# Gate-4 audit — Feature #1121 WI-2 (edit-handoff auto-open, behavioral)

`codex exec --sandbox read-only`. The audit confirmed the FORMAT-AGNOSTIC design
works (`HighlightPopoverPresenter.form` returns `.sheet` for `sourceRect == .zero`;
`openInEditMode` flows through `presentedInitialMode` → `router.present`). Findings
(all fixed):

| # | sev | issue | fix |
|---|---|---|---|
| 1 | High | the 250ms delayed edit task wasn't superseded — a real tap (or newer edit) during the window then lost to the late-waking edit (token never checked). | `@State pendingEditTask` + `latestEditToken`: each edit cancels the prior task + records its token; the task fires only if `!isCancelled && latestEditToken == request.token`; a real `.readerHighlightTapped` cancels the pending edit + clears the token; `.onDisappear` cancels. |
| 2 | Medium | `request.bookFingerprintKey` ignored → two same-book readers would both present. | Exposed `viewModel.bookFingerprintKey`; the observer guards `request.bookFingerprintKey == viewModel.bookFingerprintKey` before scheduling. |
| 3 | Medium | 250ms is a heuristic, not a navigation-settled signal — editor could open mid-jump on slow paths. | **ACCEPTED with rationale**: the `.zero`-rect SHEET form is NOT position-anchored, so opening before the jump fully lands is cosmetically tolerable (the editor isn't pinned to the on-page highlight). A deterministic navigation-settled handoff is a documented follow-up (no generic production signal exists today). |
| 4 | Low | doc said per-format bridges observe; actually the modifier does. | Comment corrected to describe the modifier + sheet-form path. |

## Design note

WI-2 deliberately replaces the plan's 5-format async rect-resolution (the audit's
"hard part") with the format-agnostic `.zero`-rect sheet form — one robust slice for
all formats, no per-format wiring. Trade-off: the editor opens as a bottom sheet, not
anchored to the on-page highlight. The anchored-card refinement (per-format rect) is a
cosmetic follow-up, not required for "auto-open the editor in edit mode after the jump."

Tests: `HighlightEditHandoffTests` (routing + `editRequest(from:)` parse),
`HighlightPopoverActionRouterTests` (`present(initialMode:)`). The runtime open-flow is
device/CU-verified (post → settle → resolve → present) — ships awaiting CU.

## Verdict: ship-as-is.
