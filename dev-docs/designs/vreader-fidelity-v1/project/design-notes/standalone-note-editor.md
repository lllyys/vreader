# Standalone-note editor presentation — Edit handoff WI-3 (#1296 · Feature #1121)

> Source of truth (design): `VReader Standalone Note Editor Canvas.html` → `standalone-note-editor-artboards.jsx`.
> Chat transcript: `chats/chat12.md`.
> Resolves the `needs-design` issue [#1296](https://github.com/lllyys/vreader/issues/1296) (design dependency of Feature [#1121](https://github.com/lllyys/vreader/issues/1121) WI-3).
> Status: **design landed — implementation deferred** (recorded, not built; see "Scope reality" below).

## The question

Feature #1121 (Edit handoff). The HIGHLIGHT path (WI-1/WI-2, shipped) opens the editor "after the jump":
tap Edit → dismiss the sheet → navigate to the highlight → the popover modifier auto-opens the editor over
the page. A STANDALONE note has no anchored passage and no reader-level editor mount point, so #1121/#1296
flagged an open presentation question: edit **(A) over the HighlightsSheet (non-dismissing)** or
**(B) after dismissing + navigating to the locator**.

## Decision (binding): Option A — edit over the sheet

When the user taps `⋯ → Edit` on a standalone-note card, present `AnnotationEditSheet` as a sheet stacked
**over** the HighlightsSheet, non-dismissing. After Save, the editor dismisses back to the list, in place.

Rationale:
- The entry context is **triage, not reading** — Edit is a "fix the wording" micro-task; tearing down the
  sheet to fly to the reader is disproportionate. A returns the user exactly where they were (same filter,
  same scroll).
- A standalone note has **no passage to re-anchor to**. The highlight path navigates because a highlight's
  note is *about* a visible passage; for a standalone note the jump reveals ordinary body text the note
  doesn't quote — the jump does no work for the edit.
- Clean gesture grammar: tap the card body = "go read there" (the existing `onJump`, unchanged);
  `⋯ → Edit` = "change the text" (in place). B collapses both into navigate-then-edit.
- The consistency that matters — the **editor surface and the gesture** — is identical in both paths; only
  the container differs, because the data differs.

## Presentation contract (from the spec card)

- **Trigger**: `edit()`'s `.standalone` branch posts an `editAnnotation(id)` request, observed at the
  **HighlightsSheet** level (not the reader). The sheet stays mounted.
- **Present**: the observer presents `AnnotationEditSheet` over the list (`.sheet`, keyboard-anchored),
  seeded with `initialContent: annotation.content`. No dismiss, no navigation.
- **Save**: `onSave` → `updateAnnotation(annotationId:content:)` → dismiss back to the list; the row reflects
  the new text in place; a "Note saved" toast confirms.
- **Cancel**: clean draft → dismiss. Dirty draft → `DiscardNoteAlert` (#914). Empty content is not a valid
  standalone note — Save reads "Clear" and routes through the Delete confirm.
- **Locator strip**: replaces the highlight excerpt — chapter · page + a "Standalone note — no quoted
  passage" hint.
- **States covered**: editing existing · idle, dirty/Save, saving, discard-confirm, long note (scrolls),
  CJK/IME, sepia, dark.

## Scope reality (read before implementing — the design's premise is partly false)

The design/issue call WI-3 "small plumbing" on the basis that the surfaces are **all committed**. A code
audit (2026-05-31) found that is **only partly true**:

| Design assumes committed | Reality |
| --- | --- |
| `AnnotationEditSheet` = the designed editor (locator strip, "Standalone note" hint, word-count footer, Delete-note, cream keyboard-anchored sheet) | A minimal **un-wired stub** — `NavigationStack` + `TextEditor` titled "Edit Annotation", Cancel/Save only. None of the designed chrome. (`vreader/Views/Annotations/AnnotationEditSheet.swift`) |
| `DiscardNoteAlert` (#914) | **Does not exist** in the codebase |
| "Note saved" toast | **Does not exist** |

What *is* ready and small: the flow plumbing. `edit()`'s `.standalone` branch is a `break` stub
(`HighlightsSheet+Delete.swift:122`); `HighlightEditHandoff.action(for:)` already returns
`.openStandaloneNote(annotationID:)`; `updateAnnotation(annotationId:content:)` exists
(`PersistenceActor+Annotations.swift:59`, VM wrapper `AnnotationListViewModel.swift:91`); a RED routing test
exists (`HighlightEditHandoffTests.standaloneRoutesToNoteEditor`).

So implementing the **designed** WI-3 is a real UI slice (build the editor surface to the design + a discard
alert + a toast + the over-the-sheet plumbing), not the few-line plumbing the issue estimated. Treat it as a
feature-workflow effort, not a stub fill-in, when it's picked up.
