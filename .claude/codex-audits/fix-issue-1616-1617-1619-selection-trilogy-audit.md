---
branch: fix/issue-1616-1617-1619-selection-trilogy
threadId: 019eb270-fa6e-7d63-920d-1033313d2cbc
rounds: 3
final_verdict: ship-as-is
date: 2026-06-11
---

# Gate-4 Codex audit — selection-UX trilogy (#338 GH #1616, #339 GH #1617, #340 GH #1619)

Independent audit via `scripts/run-codex.sh` (gpt-5.4, read-only), 3 rounds
(session ids `019eb270…` / `019eb277…` / `019eb27e…`).

## Round 1

| file:line | severity | issue | resolution |
|---|---|---|---|
| SelectionPopoverPresenter.swift:184 | High | The simultaneous tap recognizer also saw taps landing ON the overlay card — dismiss raced the card's action handlers (the EPUB/Readium token cache is cleared by `onDismiss`). | **Fixed** — `SpatialTapGesture(.global)` dismisses only when the tap falls OUTSIDE the card's frame (tracked by a GeometryReader background). Device-verified: tapping the card's quote keeps it up; outside tap dismisses. |
| SelectionPopoverPresenter.swift:184 | Medium | A dismiss tap also executes the reader's tap grammar (page-turn / chrome zones). | Round-1 accepted with rationale; **round 2 rejected the acceptance** — see below. |
| FoliateSpikeView.swift:321 | Medium | Foliate set `tintColor` only in `makeUIView` — a live theme change left stale-accent handles. | **Fixed** — `updateUIView` re-applies (mirrors `EPUBWebViewBridge`). |

Round 1 found no issue in `editingActions: []`, the Readium
selection-callback assumption, or the CSS-color sanitizer.

## Round 2

Confirmed the High + Foliate fixes sound. **Rejected** the round-1
acceptance on the dismiss-tap double-effect: in paged mode a side-zone
dismiss tap can PAGE-TURN away from the selected text via
`ReaderTapZoneRouter` (Medium).

**Fixed** — `ReaderTapZoneRouter` gains `@MainActor selectionPopoverVisible`
+ `dismissGraceDeadline`; `dispatch()` guards on `isSuppressed()` (popover
up, or within a 0.4s one-shot grace armed at dismissal — the bridges' tap
reports arrive asynchronously after the SwiftUI gesture). Unit tests:
suppressed-while-visible, grace-then-resume.

## Round 3

| file:line | severity | issue | resolution |
|---|---|---|---|
| SelectionPopoverPresenter.swift:230 | High | The ACTION close path cleared `pending` but never released the suppression (the round-2 edit for that path had silently failed to apply) — a highlight/translate/Ask-AI tap left tap grammar suppressed across readers. | **Fixed** — the action path clears `selectionPopoverVisible` immediately, with NO grace (the action tap landed on the card; nothing to swallow). Edit applied with anchor assertions; suite re-run green. |
| SelectionPopoverPresenter.swift:176 | Medium | No teardown cleanup — unmounting the reader with the popover visible leaked the global suppression into the next session. | **Fixed** — `.onDisappear` unconditional reset (no grace). |

Round 3 also explicitly confirmed: every tap-driven page-turn path routes
through `ReaderTapZoneRouter.dispatch` (Readium, legacy EPUB, TXT, chunked
TXT, PDF, Foliate — file:line citations in the audit transcript); the
remaining bypasses are chrome-toggle fallbacks / swipe notifications, not
tap page-turns; the 0.4s grace is defensible scoped to the outside-dismiss
tap; no concurrency issues (the new router state is `@MainActor`).

## Round budget note

Rule 47's max-3-rounds is exhausted with the round-3 findings RESOLVED
(two mechanical flag-clear edits, applied with anchor assertions and
covered by the suppression unit tests + a green suite re-run) rather than
open — no escalation required.

## Verdict

**ship-as-is** after 3 rounds.
