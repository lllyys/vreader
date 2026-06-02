---
branch: fix/issue-1357-readium-highlight-tap-edit
threadId: 019e86d9-4b12-78c1-bb45-900d0862267e
rounds: 1
final_verdict: ship-as-is
date: 2026-06-02
---

# Codex audit — Bug #302 (GH #1357): Readium EPUB highlight-tap → edit popover

Independent Codex audit (cc-suite via `scripts/run-codex.sh`, model `gpt-5.5`,
effort `high`, read-only) of the fix that wires BOTH missing ends of the Readium
highlight-tap path: the producer (`observeDecorationInteractions` on the
`"highlights"` group → `.readerHighlightTapped`) and the consumer (the host
attaches the unified highlight-action popover).

## Scope audited

- `vreader/Services/Reader/ReadiumDecorationHighlightAdapter.swift` (observer
  registration in `attach` + new pure `tapEvent` helper)
- `vreader/Views/Reader/ReadiumEPUBHost+Body.swift` (`.unifiedHighlightPopoverPresenterIfAvailable`)
- `vreaderTests/Services/Reader/ReadiumDecorationTapEventTests.swift` (new)

## Findings (round 1) — 1 Low, zero Critical/High/Medium

| File:line | Severity | Issue | Resolution |
|---|---|---|---|
| `ReadiumDecorationTapEventTests.swift` | Low | Tests covered the pure UUID/rect mapping but not the producer wiring — that `attach` registers `observeDecorationInteractions` for `"highlights"` exactly once. A regression dropping the observer call would still pass. | FIXED — extended the existing `FakeDecorableNavigator` (in `ReadiumDecorationHighlightAdapterTests`) to record `observedGroups`, and added `attach_registersHighlightsTapObserverOnce` asserting `observedGroups == ["highlights"]`. |

## Auditor confirmations (clean on the requested risks)

- **ID round-trip correct**: `Decoration.id = record.highlightId.uuidString`; `tapEvent`
  parses it back via `UUID(uuidString:)` and posts `ReaderHighlightTapEvent`.
- **Consumer wired**: `+Body` attaches `unifiedHighlightPopoverPresenterIfAvailable(... mutating: highlightCoordinator ...)`, matching legacy EPUB (`EPUBReaderContainerView.swift:432`).
- **No duplicate-callback bug**: `attach` is called only from `makeUIViewController`
  (once per navigator); `updateUIViewController` does not reattach. Confirmed
  independently — `highlightAdapter.attach` appears only at `ReadiumNavigatorRepresentable.swift:110`.
- **`setActivable` timing OK**: Readium marks current loaded spreads at registration
  and future spreads on load; registering after `rebuildAndApply` does not leave
  the first set permanently non-tappable.
- **No Sendable / main-actor / retain-cycle issue**: the `onActivated` closure
  captures only `Self` static methods and posts a `Sendable` event.
- **No tap conflict**: Readium handles decoration activation distinctly from a
  generic tap, so a highlight tap doesn't also page-turn / toggle chrome.
- **Rule 51**: reuses the existing designed popover — no new UI. Files < 300 lines.

## Verdict

**ship-as-is.** The single Low (test coverage of the registration) is fixed;
build + 4 (`tapEvent`) + 30 (adapter, incl. the new registration test) GREEN.
