---
branch: feat/feature-55-wi-4-note-callout-view
threadId: 019e3ed1-11ff-7c62-86ac-a8c2e2a97b88
rounds: 2
final_verdict: ship-as-is
date: 2026-05-19
---

# Codex Audit — feature #55 WI-4 (NoteCalloutView)

## Scope

Files changed:
- `vreader/Views/Reader/NoteCalloutView.swift` (new) — SwiftUI realization of the design's `NoteCallout`
- `vreader/Views/Reader/NoteCalloutAction.swift` (new) — the handoff-row action enum
- `vreaderTests/Views/Reader/NoteCalloutViewTests.swift` (new) — Swift Testing contract tests
- `vreader.xcodeproj/project.pbxproj` — xcodegen regen

## Round 1

Codex thread `019e3ed1-11ff-7c62-86ac-a8c2e2a97b88`, sandbox `read-only`.

| file:line | severity | issue | resolution |
|---|---|---|---|
| NoteCalloutViewTests.swift | Medium | Swatch tests asserted only `!= .clear` — a wrong-hue regression or drift from `NamedHighlightColor.hex` would still pass. | **Fixed** — exact-hex assertions: designed colors against the committed design hex stops, red/orange/purple against intended hues + distinct-from-yellow, unknown/"" exactly the yellow fallback. Test-local `Color(testHexString:)`. |
| NoteCalloutViewTests.swift | Medium | Empty-vs-note tests exercised only `NotePreviewContent.isEmpty`, not the view's branch. | **Fixed** — added `NoteCalloutDisplayMode` enum + `NoteCalloutView.displayMode(for:)` the `body` switches on; tests assert the decision. Added render-smoke tests hosting the view in `UIHostingController` for both states (forces `body` evaluation). |
| NoteCalloutViewTests.swift | Low | Tautology `action != .openInPanel \|\| action == .openInPanel` in `handoffActionsAreReadOnlyHandoffs`. | **Fixed** — removed; replaced with an exact case-set assertion + a per-case no-`edit`/`delete`-rawValue check. |
| NoteCalloutViewTests.swift | Low | Line-count tests missed whitespace/newline-only edge cases. | **Fixed** — added `noteLineCountWhitespaceOnly`: `"   "`→1, `"\n"`→0, `" \n \n "`→3. |

Implementation itself: auditor confirmed "the implementation is mostly aligned
with the plan and rule 51 — the view is read-only, there is no Edit/Delete/
inline editing affordance, the empty state has no 'Add one…', `content.isEmpty`
drives the branch, the six-color palette is covered, `ReaderTypography.body(...)`
→ `Font(...)` is fine, and the duplicate `Color(hexString:)` is acceptable at
the second call site given the existing `SelectionPopoverView` precedent." No
Critical/High at any point, no design/rule-51 violation in the shipped view.

## Round 2

Same thread — verification of the round-1 fixes.

| file:line | severity | issue |
|---|---|---|
| — | — | No findings — Critical / High / Medium / Low all clear |

Auditor confirmed: the swatch tests now genuinely pin the hex contract (a
wrong-hue regression for any of the 6 colors, or drift from the design hex
stops, fails); the `displayMode` extraction is sound and the render-smoke
tests force SwiftUI to build `body` for both branches; the tautology is gone;
the whitespace line-count cases match the helper. Verdict: "WI-4 round-1
findings are resolved."

## Verdict

**ship-as-is** — 2 rounds. Round 1: 2 Medium + 2 Low (all test-strength gaps,
implementation was already correct + rule-51-compliant), all fixed. Round 2:
zero findings.
