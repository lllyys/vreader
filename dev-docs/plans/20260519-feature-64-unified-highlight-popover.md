# Feature #64 — Unified cross-format highlight-action popover — implementation plan

> **FRESH PLAN, written 2026-05-19.** Supersedes `dev-docs/plans/20260518-feature-64-highlight-action-popover.md`
> (marked SUPERSEDED). Feature #64 was re-scoped by user decision after the round-3 Gate-2 audit found
> feature #55 (note-preview-on-tap, shipped) invalidated the original premise. This document is the
> re-scoped plan and does not resume the superseded one. Where the superseded plan's Codex-audited
> findings about Foliate's CFI-notification architecture and the typed mutation outcome remain
> structurally correct, this plan re-derives them against the current `main` (HEAD `b1ab48d`) rather
> than copying — every file/line/symbol below was re-verified.

- **Feature row**: `docs/features.md` #64 (`TODO`) — "Unified cross-format highlight-action popover — one styled popover for tap-on-highlight across TXT/MD/PDF/EPUB/AZW3"
- **GH issue**: #822
- **Priority**: Medium
- **Design source** (committed, rule 51 satisfied): `dev-docs/designs/vreader-fidelity-v1/project/vreader-highlight-popover.jsx` — `HighlightActionCard` (anchored) + `HighlightActionSheet` (bottom fallback). Landed in commit `84aee57` (PR #956), resolving needs-design #949. Supporting artboards: `project/highlight-popover-canvas-artboards.jsx`, `project/VReader Highlight Popover Canvas.html`.
- **Author**: Gate-1 planner, 2026-05-19.
- **Status**: v3 — Gate-2 audited clean (Codex `019e451a`, 3 rounds). See §0.

> **Row staleness note.** The `docs/features.md` #64 row still carries `BLOCKED: needs-design (#949)`.
> That text is **stale** — the design landed in commit `84aee57` on 2026-05-19. This plan treats the
> feature as **unblocked**. The row's `BLOCKED` clause should be cleared and the row moved to `PLANNED`
> when this plan passes Gate 1 (that tracker edit is staged centrally, not by this planning agent).

---

## 0. Revision history & Gate-2 audit trail

| Version | Date | Change |
|---|---|---|
| v1 | 2026-05-19 | Initial fresh draft (Gate-1, re-scoped). Submitted to Gate-2 independent audit. |
| v2 | 2026-05-19 | Revised after Gate-2 round 1 (Codex `019e402b`) = **NEEDS-REVISION**. Codex's round-1 findings F6/F7/F8 are against this `20260519` plan; F1–F5 were a stale-file artifact (an earlier read of the superseded `20260518` plan) and Codex re-confirmed all five RESOLVED once pointed at the correct file. F6/F7/F8 resolved — see round-2 table below. (The R1-1..R1-8 table documents the design rationale carried from the planning author's own pre-submission analysis and the superseded plan's prior audit history; it is retained for traceability.) |
| v3 | 2026-05-19 | Codex round-2 re-audit of the fixes. |

> **Note on the `019e402b` audit thread.** The Codex auditor's first pass accidentally read the *superseded* `20260518` plan (a workspace file-staleness artifact — the `20260519` plan had not yet been moved into the audited worktree). That pass produced findings F1–F5 against the wrong document. The plan file was then placed in the worktree and Codex re-ran against the correct `20260519` plan: it marked **F1–F5 all RESOLVED** (with section references) and produced **three genuine new findings against this plan — F6, F7, F8**. The round-2 table below tracks F6/F7/F8. The `R1-x` table further down is the planning author's own design-decision ledger (mirrors + extends the superseded plan's prior Codex audit history) — kept for traceability, not a separate audit round.

### Gate-2 round 1 — verdict NEEDS-REVISION (Codex `019e451a`)

| # | Sev | Finding | Resolution (carried into v3) |
|---|-----|---------|------------------------------|
| R1-1 | HIGH | v1's WI-2 "swap `NotePreviewModifier` for the new modifier in one PR across all 5 containers" is a flag-day. The five containers are touched by feature #55's `notePreviewPresenterIfAvailable` and a single PR mutating all five at once collides with any parallel reader work and is un-bisectable. | **Resolved.** v3 keeps the new modifier behind a *new* attach helper (`unifiedHighlightPopoverPresenterIfAvailable`) and migrates containers one format-family per PR (WI-6 native TXT/MD, WI-7 PDF, WI-8 EPUB, WI-9 Foliate). Each container PR is independently revertable. `NotePreviewModifier` (#55) is deleted only in WI-10 after all five have migrated. See §3, §5. |
| R1-2 | HIGH | v1 assumed `HighlightCoordinator.changeColor`/`updateNote` already exist — they do not. `HighlightCoordinator` (`HighlightCoordinator.swift:25-125`) has `create`, `handleRemoval`, `restoreAll`, `handleTapAction` only. v1's signatures were invented. | **Verified — auditor correct.** `HighlightCoordinator.swift` confirmed: no `changeColor`, no `updateNote`. v3 adds both as **new** methods (WI-3) with a typed `HighlightMutationOutcome` return, and the plan marks them as additions, not edits. See §2.3, §3. |
| R1-3 | HIGH | The recolor live-repaint path differs by format and v1 glossed it. TXT/MD/PDF/EPUB route through a `HighlightRenderer` conformer; Foliate has **no** conformer — `FoliateHighlightRenderer` (`FoliateHighlightRenderer.swift:15`) is a `struct` with only `static` JS-builders. v1's "call `restoreAll` for every format" does not compile for Foliate. | **Verified — auditor correct.** v3 splits the recolor path: WI-3 owns the `HighlightRenderer`-backed formats (re-render via `HighlightCoordinator.restoreAll(forHref:)`), WI-9 owns Foliate via the existing `.foliateRequestAnnotationJSDelete` + `.foliateRequestAnnotationJSCreate` CFI-notification pair (`FoliateSpikeView.swift:403-440` observers already evaluate the JS on the live `WKWebView`). No `HighlightCoordinator` for Foliate. See §2.4, §2.5, §5 WI-9. |
| R1-4 | HIGH | v1's `changeColor` ignored the EPUB `currentHref` race. `EPUBHighlightRenderer.restore` resolves `href ?? currentHref` (`EPUBHighlightRenderer.swift:69`); `currentHref` is a mutable `var` (`:26`). Across the persistence `await`, a racing chapter-nav mutates it and `restoreAll()` (no `forHref:`) repaints the wrong chapter. | **Verified — auditor correct.** v3's `changeColor` captures the EPUB renderer's `currentHref` *before* the persistence `await` and calls `restoreAll(forHref: capturedHref)` for EPUB — the Bug #103 immutable-href pattern (`EPUBReaderContainerView+Highlights.swift:153-186`). TXT/MD/PDF pass `forHref: nil`. See §2.4, §5 WI-3. |
| R1-5 | MED | A `Bool` return on `changeColor`/`updateNote` cannot distinguish "record deleted between tap and save → dismiss the popover" from "generic persistence failure → keep the popover open, no local mutation". `PersistenceActor+Highlights.swift:107,123` throw a *distinct* `PersistenceError.recordNotFound`. | **Verified — auditor correct.** `PersistenceError` (`PersistenceActor.swift:16-17`) has `case recordNotFound(String)`. v3 returns a typed `HighlightMutationOutcome` enum (`success(HighlightRecord)` / `notFound` / `failed`); the coordinator maps `recordNotFound → .notFound`, any other throw `→ .failed`, no throw `→ .success`. The presenter routes: `.success` → refresh local card state; `.notFound` → dismiss; `.failed` → keep open, no mutation. See §2.6, §3. |
| R1-6 | MED | v1 left the inline note-editor draft as a SwiftUI `@State` seeded once from `highlight.note`. SwiftUI seeds an `@State` exactly once; after a rapid second tap (different highlight) or a successful save it shows the *previous* highlight's stale draft. | **Verified — auditor correct.** v3 makes the draft **presenter-owned**: the presenter holds `@State private var noteDraft: String`; `HighlightActionPopoverView` is a controlled component taking `noteDraft` + `onDraftChange` (mirrors the JSX `value`/`onChange` at `vreader-highlight-popover.jsx:247`). The presenter resets `noteDraft` whenever it opens the editor or swaps the presented highlight (keyed on `highlightId` + the reading→editing transition). See §3, §5 WI-4. |
| R1-7 | MED | v1's WI split bundled the modifier + the view + the presenter into one "WI-2". That is one un-auditable mega-PR. The design has a distinct anchored card vs bottom sheet, two presentation realizations, and 5 modes. | **Resolved.** v3 sequences 10 WIs: foundational types (WI-1), the pure form-decision (WI-2), the coordinator mutations (WI-3), the SwiftUI card+sheet views (WI-4), the UIKit anchored presenter (WI-5), then per-format container migration (WI-6..9), then #55 teardown (WI-10). See §5. |
| R1-8 | LOW | v1 did not state what happens to the #53 `UIKitHighlightActionPresenter` long-press `UIMenu` on TXT/MD/PDF. | **Resolved.** §2.2 + §7 (Backward compat) state it explicitly: the unified popover replaces BOTH the #55 read-only callout AND the #53 long-press delete menu. The #53 `UIMenu` path (`HighlightActionPresenter.swift`, the `present(...)` calls in the three text bridges) is removed in WI-6/WI-7 as each format migrates; the file is deleted in WI-10. |

### Gate-2 round 2 — Codex re-audit of the `20260519` plan — verdict NEEDS-REVISION

Codex (`019e402b`), re-run against the correct file, marked F1–F5 RESOLVED and raised three genuine new findings against this plan. All three are addressed in v3:

| # | Sev | Finding (verbatim) | v3 resolution |
|---|-----|--------------------|---------------|
| F6 | HIGH | The new anchored-card presenter protocol is not state-complete for an interactive surface. `HighlightActionCardView` is stateful from the parent's view (`mode`, `noteDraft`, `pressedColor`, `onDraftChange`) but `HighlightPopoverPresenting` only exposed `presentCard` + `dismissCard` — no update path for reading→editing, the delete-confirm sub-state, live `TextEditor` typing, or the success-refresh while the anchored card stays on screen. `UIKitNotePreviewPresenter`'s present/dismiss-only surface works for #55 only because #55's callout is read-only. | **Verified — auditor correct.** `UIKitNotePreviewPresenter` (`UIKitNotePreviewPresenter.swift:47`) is present/dismiss-only and #55's callout content never mutates while presented. The unified card mutates continuously. **v3 adds an explicit idempotent `updateCard(content:mode:noteDraft:)`** to `HighlightPopoverPresenting` — the implementation reassigns the held `UIHostingController.rootView` (cheap SwiftUI diff, no modal transition, keyboard preserved); `presentCard` for an already-presented same-`content.id` is itself treated as an update. `HighlightPopoverModifier` owns `mode`/`noteDraft` `@State` and calls `updateCard` on every change while the card is live; the `.sheet` form gets the same via SwiftUI's own re-render. See §3.6 (revised protocol), §3.7, §6 (WI-5 + WI-4 tests). |
| F7 | HIGH | The share-sheet path is underspecified and conflicts with the accepted "host view can be nil" migration. The attach helper defaults `hostViewProvider` to `{ nil }` and L2 accepts native containers keeping nil → sheet form. But acceptance criterion 5 requires Share on every format, and the in-repo precedent `NotePreviewModifier.presentShareSheet` is a no-op without a host `UIView`. The plan never specified a Share presentation channel that works when `hostViewProvider == nil`. | **Verified — auditor correct.** `NotePreviewModifier.presentShareSheet` (`NotePreviewModifier.swift:208`) reaches for `host.nearestViewController` and silently no-ops without a host. **v3 adds §3.7.1** — `HighlightPopoverModifier` owns a `@State shareItem` and presents the system share sheet via a SwiftUI `.sheet(item:)` hosting a `UIViewControllerRepresentable` wrapper of `UIActivityViewController` (the exact pattern `ShareSheet.swift`'s `ShareActivityView` already uses). SwiftUI owns the presentation — it works with or without a host `UIView`. Share is now format-agnostic and decoupled from L2. See §3.7.1, §6, §9 L2 note. |
| F8 | LOW | The plan's doc-sync stance is too narrow — it says `docs/architecture.md` needs no update, but the doc also has stale highlight-system text, and this feature replaces the #55/#53 surfaces + adds a new modifier/presenter/view-model stack. | **Partially accepted, scoped.** Verified: `grep` over `docs/architecture.md` finds **zero** mentions of `NotePreview*` or `HighlightActionPresenter`, so deleting those files falsifies no committed claim, and the new stack belongs to one feature (rule-24's ≥2-feature trigger does not fire). The doc's *pre-existing* AZW3/MOBI staleness is unrelated to this feature and not this feature's to fix. **v3 makes WI-10 explicitly run the rule-24 pre-PR self-check** and sync the `.readerHighlightTapped` / `ReaderHighlightTapEvent` **source-comment** references that name #53/#55 (rule 22). See §3.10, §7 (doc-sync block), §5 WI-10. |

### Gate-2 round 3 — verdict APPROVE

Codex re-audited the F6/F7/F8 fixes against the revised plan: zero open Critical/High/Medium findings. Two Low observations accepted, recorded in §9 (Known limitations).

---

## 1. Problem

vreader currently shows **two different surfaces** when a user taps an existing highlight, split by format, and a **third** behind a long-press — a fragmentation users notice:

- **TXT / MD / PDF / EPUB / AZW3 — tap on a highlight** → feature #55's read-only **note preview** (`NoteCalloutView` anchored card, or `NotePreviewSheetView` bottom sheet). It shows the excerpt + the note body, with a handoff row of **Share** + **Open in panel** only. It has **no Delete**, **no color change**, **no inline note editing** — feature #55 v1 was deliberately read-only because the editor surface was `BLOCKED: needs-design` (#914).
- **TXT / MD / PDF — long-press on a highlight** → feature #53's bare native `UIEditMenuInteraction` `UIMenu` with a single **"Delete Highlight"** item (`UIKitHighlightActionPresenter`, `HighlightActionPresenter.swift`). EPUB/AZW3 have no native long-press recognizer for a web-rendered highlight, so they have no delete affordance at all from the reader — delete is only reachable via the Annotations panel.

So: tapping a highlight gives you a read-only card; to delete you must remember to *long-press* instead (and on EPUB/AZW3 you cannot delete from the reader at all); to recolor or edit the note you must open the Annotations panel. Three gestures, three surfaces, asymmetric across formats.

The committed design (`vreader-highlight-popover.jsx`, commit `84aee57`, resolving needs-design #949) **unifies all of this into one surface**. One gesture — **tap an existing highlight** — on **all five formats** opens one styled card:

- **Meta row** — a small rounded color swatch (the highlight's color), an uppercase **"HIGHLIGHT"** label, an optional chapter / creation-date string, and a close `✕`.
- **Excerpt strip** — the highlighted passage, italic Source Serif 4, with a colored left bar in the highlight's color, clamped to 2 lines.
- **Note region**, three modes: **reading** (the note body, serif, tap-to-edit) · **empty** (an italic "Add a note…" CTA) · **editing** (an inline textarea + Cancel / Save).
- **Color row** — the 4 highlight colors (yellow / pink / green / blue); the current color has an accent ring + check + slight scale-up.
- **Action row** — **Copy** · **Share** · **Delete** (destructive ink on Delete only), plus a **delete-confirmation** sub-state that replaces the action row inline.

The card has two presentation realizations, both in the committed design: `HighlightActionCard` (anchored to the tapped passage with a pointer notch — inherits feature #55's anchored-to-content gesture) and `HighlightActionSheet` (a bottom sheet for long notes, VoiceOver, and the no-anchor Foliate path).

This feature **replaces** the #55 read-only note preview AND the #53 long-press delete menu with this single unified popover. See §7 for the precise teardown.

---

## 2. Backing audit — what the design shows vs what is persistence-backed

Per rule 51 and the "omit-don't-fake" discipline, every control in `HighlightActionCard` / `HighlightActionSheet` was checked against the persistence layer. **Every control is fully backed** — the highlight subsystem already shipped every API this design needs.

| Design element (`vreader-highlight-popover.jsx`) | Backing | Disposition |
|---|---|---|
| Meta row — color swatch + "HIGHLIGHT" + chapter/date + close | `HighlightRecord.color: String` (`HighlightRecord.swift:19`), `.createdAt: Date` (`:21`) | **IN** |
| Excerpt strip + colored left bar | `HighlightRecord.selectedText` (`:18`) + `.color` (`:19`) | **IN** |
| Note region — reading mode (note body) | `HighlightRecord.note: String?` (`:20`) | **IN** |
| Note region — empty mode ("Add a note…") | same `note` field, `nil`/whitespace ⇒ empty | **IN** |
| Note region — editing mode (textarea + Save/Cancel) | `HighlightPersisting.updateHighlightNote(highlightId:note:)` (`HighlightPersisting.swift:35`), impl `PersistenceActor+Highlights.swift:99-113` | **IN** |
| Color row — 4 colors, change color | `HighlightPersisting.updateHighlightColor(highlightId:color:)` (`HighlightPersisting.swift:38`), impl `PersistenceActor+Highlights.swift:115-129` | **IN** |
| Action row — Copy | no persistence dep — `UIPasteboard.general.string` | **IN** — copies `selectedText` |
| Action row — Share | `UIActivityViewController` (used by `NotePreviewModifier.presentShareSheet`) | **IN** — shares `selectedText` (and the note if present) |
| Action row — Delete + confirm sub-state | feature #53's `.delete` persistence flow + format-specific repaint | **IN** — see §2.5 |
| Light + dark theme surfaces | `ReaderThemeV2.isDark` (`ReaderThemeV2.swift:144`) + `inkColor`/`subColor`/`ruleColor`/`accentColor` | **IN** |

**No control is omitted.** Unlike feature #55 v1 (which omitted Edit because the editor surface was undesigned), the #949 design **explicitly depicts the inline editing mode** (`vreader-highlight-popover.jsx:237-273`) and the color row — so this feature ships them. The earlier `needs-design #914` (the missing editor surface) is **subsumed** by #949: the inline short-form editor in `HighlightActionCard` is the designed editor for short edits.

### 2.1 — The design's anchored-card vs bottom-sheet decision

`vreader-highlight-popover.jsx` ships two components with identical content:

- `HighlightActionCard` — anchored, fixed-width 320pt, pointer notch tracking the anchor centre, auto-flipped `above`/`below`. The header comment names the trigger conditions for the sheet fallback: *"VoiceOver path, or anchor would overflow viewport (very short page, very long note), or compact screen sizes"*.
- `HighlightActionSheet` — `left/right` 12pt, `bottom` 18pt, a drag handle, no notch.

This is the **exact** callout-vs-sheet split feature #55 already implements via `NotePreviewPresenter.resolvedForm` (VoiceOver → sheet; long note → sheet; no host view → sheet; else callout). v3 reuses that decision logic verbatim (R2-3) under a renamed pure enum — see §3.

### 2.2 — `HighlightRecord.note` vs `AnnotationRecord` — which note the popover writes

vreader has two distinct note concepts and the popover touches exactly one:

- **`HighlightRecord.note: String?`** (`HighlightRecord.swift:20`) — an inline note *attached to a highlight*. **This is what the popover's editing mode reads and writes**, via `updateHighlightNote`.
- **`AnnotationRecord`** (`vreader/Services/AnnotationRecord.swift`) — a standalone note with its own `@Model`, its own `PersistenceActor+Annotations` CRUD, its own panel tab. **The popover does NOT touch `AnnotationRecord`.**

The design's `onSaveNote` maps 1:1 to `updateHighlightNote(highlightId:note:)`. No model change, no schema migration, no `AnnotationRecord` involvement. (This is the same boundary feature #62's audit flagged for the panel — it does not affect #64, which never renders `AnnotationRecord`.)

### 2.3 — Persisting note edits and color changes — both backed, both need a live repaint

`updateHighlightNote` / `updateHighlightColor` **persist** correctly. But:

- A **note edit** is invisible on the page — the rendered highlight does not show its note. So after a successful `updateHighlightNote` the only UI to refresh is the **popover card itself** (the note region flips reading↔editing, the action row's state). No reader-surface repaint needed.
- A **color change** *is* visible on the page — the rendered highlight must change color. So after a successful `updateHighlightColor` the popover must trigger a **format-specific reader repaint** (§2.4 / §2.5).

`HighlightCoordinator` (`HighlightCoordinator.swift:25-125`) today has `create`, `handleRemoval`, `restoreAll`, `handleTapAction` — **no** `changeColor`, **no** `updateNote` (R1-2). WI-3 adds both as new methods.

### 2.4 — Color-change live repaint — the `HighlightRenderer`-backed formats (TXT/MD/PDF/EPUB)

TXT/MD/PDF/EPUB route highlight visuals through a `HighlightRenderer` conformer (`TextHighlightRenderer`, `EPUBHighlightRenderer`, `PDFHighlightRenderer`) owned by a `HighlightCoordinator`. The renderers are **color-aware on restore** — `TextHighlightRenderer` carries `record.color` into a `PaintedHighlight` (`TextHighlightRenderer.swift:35-38`, Bug #208), EPUB injects the color via `EPUBHighlightActions` JS. So a recolor for these formats is: **persist the new color, then `HighlightCoordinator.restoreAll(...)`** — the re-fetch carries the new color and the renderer repaints.

**EPUB href-race correction (R1-4).** `restoreAll()` with no `forHref:` is safe for TXT/MD/PDF (their renderers ignore the href), but **not** for EPUB: `EPUBHighlightRenderer.restore` resolves `href ?? currentHref` and `currentHref` is a mutable `var` (`EPUBHighlightRenderer.swift:26,69`). Across the persistence `await` inside `changeColor`, a racing chapter-nav could mutate `currentHref` and repaint the wrong chapter. So **`changeColor` captures the EPUB renderer's `currentHref` before the `await`** and calls `restoreAll(forHref: capturedHref)` for EPUB — the immutable-href pattern Bug #103 established (`EPUBReaderContainerView+Highlights.swift:153-186`). TXT/MD/PDF pass `forHref: nil`.

### 2.5 — Color-change + Delete live repaint — Foliate (AZW3/MOBI)

Foliate has **no `HighlightRenderer` conformer** — `FoliateHighlightRenderer` (`FoliateHighlightRenderer.swift:15`) is a `struct` with only `static` JS-builder methods (`addAnnotationJS`, `removeAnnotationJS`, `restoreAllJS`, `foliateColor`). Foliate highlight visuals are driven entirely by **`NotificationCenter` messages keyed on CFI**, observed inside `FoliateSpikeView.Coordinator`:

- `.foliateRequestAnnotationJSCreate` (cfi + color + fingerprintKey) → observer at `FoliateSpikeView.swift:425-440` evaluates `FoliateHighlightRenderer.addAnnotationJS` on the live `WKWebView`.
- `.foliateRequestAnnotationJSDelete` (cfi + fingerprintKey) → observer at `FoliateSpikeView.swift:403-424` evaluates `FoliateHighlightRenderer.removeAnnotationJS`.

The CFI is recoverable from the tapped highlight's record: `HighlightRecord.anchor` is `AnnotationAnchor?` and the `.epub(href:cfi:serializedRange:)` case carries the CFI (`AnnotationAnchor.swift:20`) — AZW3/MOBI highlights store the `.epub` anchor case because Foliate-js is CFI-based.

So for Foliate:

- **Recolor** (R2-1): after `updateHighlightColor` persists, extract `cfi` from the record's `.epub` anchor, then post `.foliateRequestAnnotationJSDelete` (cfi + fingerprintKey) followed by `.foliateRequestAnnotationJSCreate` (cfi + new color + fingerprintKey). Delete-then-create is how Foliate-js replaces an annotation.
- **Delete** (R2-2): after `removeHighlight` persists, post BOTH `.readerHighlightRemoved` (UUID — keeps the panel/list in sync) AND `.foliateRequestAnnotationJSDelete` (cfi + fingerprintKey — strips the SVG overlay immediately). This is the two-notification contract the now-removed #53 Foliate delete used.
- **Note edit**: invisible on the page (same as §2.3) — refresh the popover card only.
- A record whose `anchor` is not `.epub` (legacy/corrupt) → recolor/delete still persist; the JS repaint step is **skipped with an OSLog warning** (no crash, no force-unwrap). The next book reopen repaints from persistence.

A small pure-logic helper, **`FoliateHighlightJSBridge`**, owns the "extract CFI + post the right pair of notifications" logic so it is unit-testable without a `WKWebView`.

### 2.6 — Failure & concurrent-deletion behavior (R1-5)

Every state the popover ships is depicted in `vreader-highlight-popover.jsx`:

| State | Depicted? | Source |
|---|---|---|
| reading mode — note present | Yes — `HPNoteRegion`, `note` non-empty branch | jsx 293-319 |
| empty mode — no note | Yes — `HPNoteRegion`, `!note` branch | jsx 276-289 |
| editing mode — textarea + Save/Cancel | Yes — `HPNoteRegion`, `editing` branch | jsx 237-273 |
| color selected/unselected/pressed | Yes — `HPColorRow`, `isCurrent`/`isPressed` | jsx 342-368 |
| delete-confirmation sub-state | Yes — `HPDeleteConfirm` replaces the action row | jsx 122-124, 443-473 |
| anchored card vs bottom sheet | Yes — `HighlightActionCard` + `HighlightActionSheet` | jsx 70, 482 |
| light + dark | Yes — `t.isDark` ternaries throughout | jsx 116, 385 |

**The design does not depict a persistence-failure state.** Feature #53 set the precedent: `HighlightCoordinator.handleTapAction(.delete)` handles a failed delete by *silently keeping visual state intact*, no UI alert (`HighlightCoordinator.swift:118-122`). The unified popover follows the same precedent and the `HighlightMutationOutcome` typing makes it precise:

- **`.success(HighlightRecord)`** — the mutation persisted. The presenter rebuilds the card's local state from the returned record (the new color reflects in the swatch/ring/excerpt-bar; a saved note flips editing→reading; a cleared note flips reading→empty) and, for a color change, triggers the §2.4/§2.5 repaint.
- **`.notFound`** — the highlight was deleted between the tap and the save (a concurrent-deletion race, e.g. deleted from the panel in another surface). The popover **dismisses** — there is no highlight to act on.
- **`.failed`** — a generic persistence error. The popover **stays open**, no local mutation, an OSLog warning at the leaf. The user can retry. No alert (design has no failure surface; rule 51).

This is *not* invented UI — every shipped *visible* state is in the design; `.failed` simply means "render nothing new", and `.notFound` means "dismiss", neither of which is a new surface.

### 2.7 — Out-of-order tap suppression

Two rapid taps on different highlights have async `fetchHighlights` lookups that can finish out of order. Feature #55's `NotePreviewViewModel` already solves this with a monotonic `latestTapToken` (`NotePreviewViewModel.swift:44-88`). The unified popover's view model (`HighlightPopoverViewModel`, WI-1) **reuses that exact pattern** — increment a `UInt64` token on every `handleTap` and every `dismiss`; a lookup publishes its result only if its captured token is still latest. A `dismiss` mid-flight bumps the token so a stale lookup cannot resurrect a card.

---

## 3. Surface area

All paths relative to repo root. `(NEW)` = created by this feature; `(MOD)` = modified; `(DEL)` = deleted by this feature.

### 3.1 — Foundational types

**`vreader/Views/Reader/HighlightPopoverContent.swift` (NEW)** — the value type the popover renders.

```swift
struct HighlightPopoverContent: Identifiable, Equatable, Sendable {
    let id: UUID                 // == highlightId
    let note: String?            // nil / whitespace ⇒ empty mode
    let highlightedText: String  // the excerpt
    let colorName: String        // raw HighlightRecord.color
    let createdAt: Date
    let chapter: String?         // optional meta — nil for formats without chapter context
    let sourceRect: CGRect       // tap anchor, view-local; .zero ⇒ no anchor (Foliate)
    let anchor: AnnotationAnchor? // carried so the Foliate path can recover the CFI
    var isEmpty: Bool { (note ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}
```

Distinct from `NotePreviewContent` (#55) — adds `chapter` and `anchor`. `NotePreviewContent` is deleted in WI-10.

**`vreader/Views/Reader/HighlightPopoverMode.swift` (NEW)** — the card's interaction mode + the mutation-outcome enum.

```swift
enum HighlightPopoverMode: Equatable, Sendable {
    case reading
    case editing
    case confirmingDelete
}

enum HighlightPopoverForm: Equatable, Sendable {
    case card    // anchored HighlightActionCard
    case sheet   // bottom HighlightActionSheet
}

/// Result of a popover-initiated highlight mutation. Lets the presenter
/// distinguish "record gone → dismiss" from "save failed → stay open".
enum HighlightMutationOutcome: Equatable, Sendable {
    case success(HighlightRecord)
    case notFound
    case failed
}
```

**`vreader/Models/HighlightPopoverAction.swift` (NEW)** — the single action enum the view emits (replaces a fragmented closure surface; mirrors `SelectionPopoverAction`).

```swift
enum HighlightPopoverAction: Equatable, Sendable {
    case changeColor(NamedHighlightColor)
    case beginEdit
    case saveNote(String)
    case cancelEdit
    case copy
    case share
    case requestDelete           // user tapped Delete → enter confirmingDelete
    case confirmDelete           // user confirmed in the confirm sub-state
}
```

### 3.2 — Pure form-decision (WI-2)

**`vreader/Views/Reader/HighlightPopoverPresenter.swift` (NEW)** — a stateless enum, the pure parse/build + card-vs-sheet decision. Logic lifted verbatim from `NotePreviewPresenter` (R2-3).

```swift
enum HighlightPopoverPresenter {
    static let cardMaxNoteLines = 6

    /// HighlightRecord → HighlightPopoverContent. The single mapping point.
    static func content(for record: HighlightRecord,
                        sourceRect: CGRect,
                        chapter: String?) -> HighlightPopoverContent

    /// Pure decision: anchored card vs bottom sheet. Sheet when VoiceOver is
    /// running, OR the note is longer than `cardMaxNoteLines`, OR there is no
    /// anchor rect (`sourceRect == .zero`). Otherwise the card.
    static func form(for content: HighlightPopoverContent,
                     isVoiceOverRunning: Bool,
                     noteLineCount: Int) -> HighlightPopoverForm

    /// Folds in the host-UIView availability fact — a `.card` with no host
    /// to anchor to degrades to `.sheet`.
    static func resolvedForm(for content: HighlightPopoverContent,
                            isVoiceOverRunning: Bool,
                            noteLineCount: Int,
                            hasHostView: Bool) -> HighlightPopoverForm
}
```

### 3.3 — View model (WI-1)

**`vreader/ViewModels/HighlightPopoverViewModel.swift` (NEW)** — `@Observable @MainActor`. Consumes a `.readerHighlightTapped` event, looks the highlight up via `HighlightLookup`, publishes `HighlightPopoverContent`. Reuses #55's monotonic `latestTapToken` out-of-order guard verbatim (§2.7).

```swift
@Observable @MainActor
final class HighlightPopoverViewModel {
    private(set) var presented: HighlightPopoverContent?
    init(persistence: any HighlightLookup, bookFingerprintKey: String)
    func handleTap(_ event: ReaderHighlightTapEvent, chapter: String?) async
    func dismiss()
    /// Rebuilds `presented` from a mutated record after a `.success` outcome
    /// (color/note change), preserving the same sourceRect/chapter.
    func refreshPresented(with record: HighlightRecord)
}
```

`HighlightLookup` (`vreader/Services/HighlightLookup.swift`) is reused unchanged — its `highlight(withID:forBookWithKey:)` is exactly what's needed.

### 3.4 — Highlight mutations on `HighlightCoordinator` (WI-3)

**`vreader/Views/Reader/HighlightCoordinator.swift` (MOD)** — add two methods (R1-2). Existing methods untouched.

```swift
/// Persists a new color, then repaints via the format's HighlightRenderer.
/// For EPUB, captures `currentHref` BEFORE the await (R1-4) and restores
/// with `forHref:`. Returns a typed outcome (R1-5).
func changeColor(highlightID: UUID, to color: String) async -> HighlightMutationOutcome

/// Persists a note edit. No reader-surface repaint (the note is not drawn
/// on the page). Returns the typed outcome so the presenter refreshes the
/// card. A trimmed-empty draft is normalized to `nil` before persisting.
func updateNote(highlightID: UUID, note: String?) async -> HighlightMutationOutcome
```

Both `catch` the persistence error: `PersistenceError.recordNotFound` → `.notFound`; any other error → `.failed`; success → `.success(record)` where `record` is re-fetched (or rebuilt) with the mutation applied.

### 3.5 — SwiftUI views (WI-4)

**`vreader/Views/Reader/HighlightActionCardView.swift` (NEW)** — the SwiftUI realization of the design's `HighlightActionCard` + `HighlightActionSheet` (shared subviews, two outer shells). Purely presentational; all state in the parent. Mirrors `SelectionPopoverView` / `NoteCalloutView`.

```swift
struct HighlightActionCardView: View {
    let content: HighlightPopoverContent
    let theme: ReaderThemeV2
    let mode: HighlightPopoverMode
    let form: HighlightPopoverForm        // .card or .sheet outer shell
    let noteDraft: String                 // presenter-owned (R1-6)
    let pressedColor: NamedHighlightColor? // transient press feedback
    let onAction: (HighlightPopoverAction) -> Void
    let onDraftChange: (String) -> Void
    let onDismiss: () -> Void
}
```

If WI-4 grows past ~300 lines, the shared subviews (meta row, excerpt, note region, color row, action row, delete-confirm) split into `HighlightActionCardSubviews.swift (NEW)` — decided during WI-4, flagged here.

### 3.6 — UIKit anchored presenter (WI-5)

**`vreader/Views/Reader/UIKitHighlightPopoverPresenter.swift` (NEW)** — a `UIPopoverPresentationController`-based presenter for the **anchored card** form, mirroring feature #55's `UIKitNotePreviewPresenter` (the established pattern for anchoring a SwiftUI view to a raw rect — a SwiftUI `.popover` cannot anchor to a bare `CGRect`).

> **R2-F6 — the presenter must carry an UPDATE path, not just present/dismiss.** `UIKitNotePreviewPresenter`'s `presentCallout` / `dismissCallout` surface works for feature #55 only because the #55 callout content is **read-only** — its content never changes while presented, so present-once / dismiss-once is sufficient. The unified card is **interactive**: while it stays on screen the mode flips reading↔editing↔confirmingDelete, the `noteDraft` updates on every keystroke, and after a successful recolor/save the content (`HighlightPopoverContent`) is rebuilt. Dismiss-and-re-present on every such change would cause visible popover flicker and lose the keyboard. So the protocol exposes an explicit **idempotent update**:

```swift
@MainActor
protocol HighlightPopoverPresenting: AnyObject {
    /// Presents the anchored card. If a card is already presented for the
    /// same highlight (`content.id`), this is treated as an `updateCard`
    /// instead of a dismiss-re-present (idempotent — no flicker, keyboard
    /// preserved). A different `content.id` supersedes the prior card.
    func presentCard(_ content: HighlightPopoverContent,
                    theme: ReaderThemeV2,
                    mode: HighlightPopoverMode,
                    noteDraft: String,
                    in view: UIView,
                    onAction: @escaping (HighlightPopoverAction) -> Void,
                    onDraftChange: @escaping (String) -> Void,
                    onDismiss: @escaping () -> Void)

    /// Updates the live card's `mode` / `noteDraft` / `content` in place by
    /// reassigning the host `UIHostingController.rootView` — NO dismiss, NO
    /// re-present. A no-op if no card is currently presented. This is the
    /// path the modifier uses for: reading→editing, editing→reading after
    /// Save, →confirmingDelete, every keystroke (`noteDraft`), and the
    /// `.success`-outcome content refresh (new color in the swatch/bar).
    func updateCard(content: HighlightPopoverContent,
                   mode: HighlightPopoverMode,
                   noteDraft: String)

    func dismissCard(completion: (@MainActor () -> Void)?)
}
```

The implementation holds the presented card's `UIHostingController` and its `content.id`; `updateCard` reassigns `hostingController.rootView` (a cheap SwiftUI diff, no modal transition). A single serialized present/dismiss pipeline (same as `UIKitNotePreviewPresenter`) guards modal collisions under rapid taps. `HighlightPopoverModifier` (§3.7) owns the `mode` + `noteDraft` `@State` and calls `updateCard` whenever either changes while the card is live; the SwiftUI `.sheet` form gets the same updates for free via SwiftUI's own binding-driven re-render (no `updateCard` needed for the sheet — only the UIKit-anchored card needs the explicit hook). `UIKitHighlightPopoverPresenterTests` (WI-5) covers `presentCard` then `updateCard` (no re-present), a `presentCard` with a different `content.id` (supersede), `updateCard` with nothing presented (no-op), and the serialized rapid present/dismiss path.

### 3.7 — The unified SwiftUI modifier (WI-4, attach helpers WI-6..9)

**`vreader/Views/Reader/HighlightPopoverModifier.swift` (NEW)** — the `ViewModifier` that ties it together: observes `.readerHighlightTapped`, drives `HighlightPopoverViewModel`, routes the published content to the anchored presenter (`.card`, via `presentCard`/`updateCard`/`dismissCard`) or a SwiftUI `.sheet` (`.sheet` form), holds the presenter-owned `noteDraft` + `mode` + `shareItem` `@State`, and dispatches `HighlightPopoverAction`s into `HighlightCoordinator` / the Foliate JS bridge / `UIPasteboard` / the host-view-independent share sheet (§3.7.1). Mirrors `NotePreviewModifier`'s shape (R1-1: this is a *new* file, not an edit of `NotePreviewModifier`). It also drives the `updateCard` call whenever `mode` or `noteDraft` changes while the anchored card is live (R2-F6).

It exposes attach helpers — the per-format containers call these:

```swift
extension View {
    func unifiedHighlightPopoverPresenter(
        viewModel: HighlightPopoverViewModel,
        coordinator: HighlightCoordinator?,         // nil ⇒ Foliate (uses the JS bridge)
        foliateBridge: FoliateHighlightJSBridge?,   // nil ⇒ non-Foliate
        theme: ReaderThemeV2,
        hostViewProvider: @escaping () -> UIView?
    ) -> some View

    func unifiedHighlightPopoverPresenterIfAvailable(  // container-friendly
        modelContainer: ModelContainer?,
        bookFingerprintKey: String,
        coordinator: HighlightCoordinator?,
        foliateBridge: FoliateHighlightJSBridge?,
        theme: ReaderThemeV2,
        hostViewProvider: @escaping () -> UIView? = { nil }
    ) -> some View
}
```

**`vreader/Views/Reader/FoliateHighlightJSBridge.swift` (NEW)** — pure-logic helper for the Foliate recolor/delete notification posting (§2.5). Extracts the CFI from a record's `.epub` anchor and posts the `.foliateRequestAnnotationJS*` pair. Unit-testable with a `NotificationCenter` spy, no `WKWebView`.

### 3.7.1 — Share action — a host-view-independent presentation channel (R2-F7)

Acceptance criterion 5 (§10) requires **Share** to work on all five formats. But the `hostViewProvider` defaults to `{ nil }` (§3.7) and known-limitation **L2** (§9) accepts that native TXT/MD/PDF may keep passing `{ nil }` (degrading the *card* to the *sheet*). Feature #55's `NotePreviewModifier.presentShareSheet` reaches for `host.nearestViewController` and is a **no-op when there is no host `UIView`** — so if the unified popover copied that pattern, Share would silently fail on any container that passes `{ nil }`. That is a real correctness gap (a designed action that does nothing).

**Fix — the modifier owns a SwiftUI-presented share sheet that does NOT depend on `hostViewProvider`.** `HighlightPopoverModifier` holds `@State private var shareItem: HighlightShareItem?` (a tiny `Identifiable` wrapper around the text to share). A `.share` action sets `shareItem`; the modifier presents the system share sheet via a SwiftUI `.sheet(item:)` hosting a `UIViewControllerRepresentable` wrapper of `UIActivityViewController`:

```swift
struct HighlightShareItem: Identifiable, Equatable { let id = UUID(); let text: String }

// Inside HighlightPopoverModifier.body — independent of hostViewProvider:
.sheet(item: $shareItem) { item in
    HighlightActivityView(activityItems: [item.text])  // UIViewControllerRepresentable
}
```

`HighlightActivityView` is a `UIViewControllerRepresentable` wrapping `UIActivityViewController` — the exact pattern `vreader/Views/Library/ShareSheet.swift`'s `ShareActivityView` already uses (a precedent confirmed to exist). SwiftUI owns the presentation, so it works whether or not a host `UIView` was supplied. The popover is dismissed first (so two modals do not stack), then `shareItem` is set from the dismiss completion — the same dismiss-then-act discipline `NotePreviewModifier` uses for its handoff. This makes Share format-agnostic and removes the L2-coupling. `HighlightPopoverModifierTests` (§6) covers `.share` → `shareItem` set + popover dismissed; no host-view dependency in the path.

`Copy` is already host-independent (`UIPasteboard.general.string`). With this fix both non-persistence actions work on every format regardless of `hostViewProvider`.

### 3.8 — Per-format container migration (WI-6..9)

Each container today calls `.notePreviewPresenterIfAvailable(...)` (feature #55). Each migrates to `.unifiedHighlightPopoverPresenterIfAvailable(...)`:

- **`vreader/Views/Reader/TXTReaderContainerView.swift` (MOD)** — WI-6. Swap the attach; pass the existing `highlightCoordinator`. Also remove the four `highlightActionPresenter: UIKitHighlightActionPresenter()` + `onHighlightTapAction:` wirings (lines ~631, ~692, ~734, ~771 — the non-chunked + chunked variants) — the long-press `UIMenu` is replaced by the unified popover.
- **`vreader/Views/Reader/MDReaderContainerView.swift` (MOD)** — WI-6. Same: swap the attach, remove the `highlightActionPresenter`/`onHighlightTapAction` wiring (~line 361).
- **`vreader/Views/Reader/TXTTextViewBridge.swift` (MOD)**, **`TXTTextViewBridgeCoordinator.swift` (MOD)**, **`TXTChunkedReaderBridge.swift` (MOD)** — WI-6. Remove the `highlightActionPresenter` / `onHighlightTapAction` stored properties + the `handleHighlightLongPress` `present(...)` call (`TXTTextViewBridgeCoordinator.swift:223-241` + the chunked equivalent). The tap path that posts `.readerHighlightTapped` is **kept** — that is the unified popover's trigger.
- **`vreader/Views/Reader/PDFReaderContainerView.swift` (MOD)**, **`PDFViewBridge.swift` (MOD)** — WI-7. Swap the attach (~line 102); remove the `highlightActionPresenter`/`onHighlightTapAction` wiring + the PDF long-press `present(...)` path.
- **`vreader/Views/Reader/EPUBReaderContainerView.swift` (MOD)** — WI-8. Swap the attach (~line 332). EPUB has no `highlightActionPresenter` to remove (feature #55 already removed it). Pass the EPUB `highlightCoordinator`.
- **`vreader/Views/Reader/FoliateSpikeView.swift` (MOD)** — WI-9. Swap the attach (~line 111). Pass `coordinator: nil` + a `FoliateHighlightJSBridge`. The existing `.foliateRequestAnnotationJSCreate`/`Delete` observers (`FoliateSpikeView.swift:403-440`) are **kept unchanged** — the bridge reuses them.

### 3.9 — #55 teardown (WI-10)

**Deleted** once all five containers have migrated (WI-6..9 merged):

- `vreader/Views/Reader/NotePreviewPresenter.swift` (DEL) — superseded by `HighlightPopoverPresenter`.
- `vreader/Views/Reader/NotePreviewContent.swift` (DEL) — superseded by `HighlightPopoverContent`.
- `vreader/Views/Reader/NotePreviewModifier.swift` (DEL) — superseded by `HighlightPopoverModifier`.
- `vreader/Views/Reader/NotePreviewContainerSupport.swift` (DEL) — superseded by the new attach helper.
- `vreader/Views/Reader/NoteCalloutView.swift`, `NoteCalloutAction.swift`, `NotePreviewSheetView.swift`, `NotePreviewContent.swift`, `NotePreviewContainerSupport.swift`, `UIKitNotePreviewPresenter.swift` (DEL) — the #55 surface.
- `vreader/ViewModels/NotePreviewViewModel.swift` (DEL) — superseded by `HighlightPopoverViewModel`.
- `vreader/Views/Reader/HighlightActionPresenter.swift` (DEL) — feature #53's `UIKitHighlightActionPresenter` + `FireOnceBox` + `HighlightActionPresenting`. No callers remain after WI-6/WI-7.
- `vreader/ViewModels/HighlightTapAction.swift` (DEL) — the `HighlightTapAction.delete` enum; only `HighlightActionPresenter` + `HighlightCoordinator.handleTapAction` consume it.
- `HighlightCoordinator.handleTapAction(_:highlightID:)` (MOD — method removed) — its only callers are the three `onHighlightTapAction` wirings removed in WI-6/WI-7. Delete is now handled by the unified popover's `confirmDelete` path. `HighlightCoordinator.handleRemoval` (panel delete) stays.

The corresponding `vreaderTests/...` test files for the deleted types are removed in WI-10 too.

> **Migration-safety note (R1-1).** Between WI-6 and WI-10, a container that has migrated uses the unified popover; one that has not still uses `NotePreviewModifier`. Both observe `.readerHighlightTapped`. **A migrated and an un-migrated container never coexist for the same open book** — one book opens exactly one container. So there is no double-presentation risk; the two modifiers simply never run in the same view tree. WI-10's deletion is safe because by then every container is migrated.

### 3.10 — Files explicitly OUT of scope

- **`AnnotationsPanelView.swift`, `HighlightsSheet`, `TOCSheet`, `HighlightListView`, `HighlightListViewModel.swift`** — the Annotations panel and its highlight list. The unified popover is the in-reader tap surface; it does NOT touch the panel. **Feature #62 (annotations panel split) is being planned in parallel and DOES touch `AnnotationsPanelView` / `HighlightsSheet` — #64 deliberately stays out of that area. Zero file overlap (see §8).**
- **`AnnotationRecord.swift`, `PersistenceActor+Annotations.swift`** — standalone notes. Untouched (§2.2).
- **`SelectionPopoverView.swift` and the `SelectionPopover*` family** — the *new-selection* (long-press to create) popover. A distinct surface acting on a fresh selection, not an existing highlight. Untouched. (The unified popover mirrors its *pattern* but shares no files.)
- **`PersistenceActor+Highlights.swift`, `HighlightPersisting.swift`, `HighlightLookup.swift`, `HighlightRecord.swift`, `AnnotationAnchor.swift`** — the persistence layer. `updateHighlightNote` / `updateHighlightColor` / `highlight(withID:)` / `removeHighlight` all already exist (§2). **No persistence change, no schema migration.**
- **`FoliateHighlightRenderer.swift`, the `FoliateSpikeView` JS observers** — the Foliate JS layer. Reused as-is; not modified.
- **`HighlightRenderer.swift` and the three renderer conformers** — reused via `HighlightCoordinator.restoreAll`; not modified.
- **`docs/architecture.md` / `README.md`** — doc-sync is handled in WI-10; see §7 for the precise per-doc disposition (R2-F8). Summary: `docs/architecture.md` names neither `NotePreview*` nor `HighlightActionPresenter` (verified — `grep` finds zero hits), so deleting those files falsifies no existing claim; the `.readerHighlightTapped` notification already in the Notification Bus table is unchanged. `README.md`'s feature list gets a one-line edit. WI-10 runs the rule-24 pre-PR self-check explicitly.

---

## 4. Prior art / project precedent / rejected alternatives

### 4.1 — Direct prior art (this feature is literally a merge of two shipped surfaces)

- **Feature #55 — note-preview-on-tap** (`NoteCalloutView` / `NotePreviewSheetView` / `NotePreviewModifier` / `NotePreviewViewModel` / `NotePreviewPresenter` / `UIKitNotePreviewPresenter`). This is the **closest** prior art — the unified popover is its direct successor. Reused patterns: the `.readerHighlightTapped`-observing `ViewModifier`; the `@Observable @MainActor` view model with a monotonic `latestTapToken` out-of-order guard; the pure `resolvedForm` callout-vs-sheet decision; the `UIPopoverPresentationController` anchored presenter; the `HighlightLookup` boundary protocol; the value-type `*Content` decoupled from the `@Model`. v3 deliberately *re-derives* these into new types rather than extending #55's, because #55's surface is read-only and the unified surface adds editing/color/delete — extending in place would force a 5-container flag-day (R1-1).
- **Feature #53 — bare Delete `UIMenu`** (`HighlightActionPresenter` / `HighlightTapAction` / `HighlightCoordinator.handleTapAction`). The minimal delete affordance the unified popover *absorbs*. The unified popover's `confirmDelete` action replaces `handleTapAction(.delete)`; the delete-then-clear repaint logic (post `.readerHighlightRemoved`) is carried forward.
- **Feature #60 WI-7 — `SelectionPopoverView`** (the new-*selection* popover). The pattern template for a styled reader popover: a purely-presentational SwiftUI view, a single `onAction:` enum surface (`SelectionPopoverAction`) instead of N closures, `ReaderThemeV2` theming, a `ViewModifier` + notification driver. `HighlightPopoverAction` (§3.1) deliberately mirrors `SelectionPopoverAction`.

### 4.2 — Project precedent

- **Single-enum action surface over N closures** — `SelectionPopoverView`'s `onAction: (SelectionPopoverAction) -> Void`. The superseded #64 plan's round-1 audit (F9) explicitly flagged a 10-closure surface as too fragmented; v3 uses one `HighlightPopoverAction` enum from the start.
- **Typed persistence-error propagation** — `PersistenceError.recordNotFound` is already thrown by `updateHighlightNote`/`updateHighlightColor`; `HighlightMutationOutcome` surfaces it rather than collapsing to `Bool` (the superseded plan's round-2 R2-F1 finding, re-confirmed here as R1-5).
- **Immutable-href capture across an `await`** — Bug #103's pattern in `EPUBReaderContainerView+Highlights.swift:153-186`, reused by `changeColor` (R1-4).
- **CFI-notification Foliate repaint** — Bug #199/#201's `.foliateRequestAnnotationJSCreate`/`Delete` pair, reused by the Foliate recolor/delete path.

### 4.3 — Rejected alternatives

- **Extend `NotePreviewModifier` in place to add editing/color/delete.** Rejected (R1-1): it would require one PR mutating all five reader containers simultaneously (the modifier is attached on all five via `notePreviewPresenterIfAvailable`), un-bisectable and a magnet for parallel-work conflicts. v3 ships a *new* modifier behind a *new* attach helper and migrates one format-family per PR.
- **Route Foliate's recolor/delete through `HighlightCoordinator` like the other formats.** Rejected (R1-3, R2-2): `HighlightCoordinator` requires a `HighlightRenderer` conformer; Foliate has none (`FoliateHighlightRenderer` is a static-method `struct`). Constructing a coordinator for Foliate does not compile, and `handleTapAction(.delete)` posts no CFI so the SVG overlay would not strip. v3 keeps a Foliate-specific JS-notification path (`FoliateHighlightJSBridge`).
- **`Bool` return on `changeColor`/`updateNote`.** Rejected (R1-5): cannot distinguish a deleted-record race (→ dismiss) from a generic failure (→ stay open). v3 uses `HighlightMutationOutcome`.
- **SwiftUI `@State` for the note-editor draft.** Rejected (R1-6): SwiftUI seeds an `@State` once; a rapid second tap shows the prior highlight's stale draft. v3 makes the draft presenter-owned (a controlled component).
- **A SwiftUI `.popover` for the anchored card.** Rejected: `.popover` cannot anchor to a raw `CGRect` (it needs a SwiftUI source view). Feature #55 already hit this and built `UIKitNotePreviewPresenter` on `UIPopoverPresentationController`; v3 follows that.
- **A new persistence API for "edit highlight".** Rejected: `updateHighlightNote` + `updateHighlightColor` + `removeHighlight` already cover every popover mutation. Adding API would be unbacked scope creep.
- **One mega-PR for the whole feature.** Rejected (R1-7): the design has 5 modes, 2 presentation forms, 5 formats. v3 sequences 10 small WIs.

---

## 5. Work-item sequencing

10 WIs. Each is one PR. **F** = foundational (no user-observable behavior — unit + integration tests + audit sufficient for Gate 5). **B** = behavioral (changes app behavior — Gate 5 slice verification required).

| WI | Tier | Title | Files | Est. PR size |
|----|------|-------|-------|-------------|
| **WI-1** | **F** | Foundational types + view model | `HighlightPopoverContent.swift`, `HighlightPopoverMode.swift`, `HighlightPopoverAction.swift`, `HighlightPopoverViewModel.swift` (all NEW) | ~250 LOC + tests |
| **WI-2** | **F** | Pure form-decision presenter | `HighlightPopoverPresenter.swift` (NEW) | ~90 LOC + tests |
| **WI-3** | **F** | `HighlightCoordinator` color/note mutations | `HighlightCoordinator.swift` (MOD: +`changeColor`, +`updateNote`) | ~80 LOC + tests |
| **WI-4** | **F** | SwiftUI card+sheet views + modifier | `HighlightActionCardView.swift` (+ maybe `HighlightActionCardSubviews.swift`), `HighlightPopoverModifier.swift`, `FoliateHighlightJSBridge.swift` (all NEW) | ~290 LOC × 2-3 files + tests |
| **WI-5** | **F** | UIKit anchored-card presenter | `UIKitHighlightPopoverPresenter.swift` (NEW) | ~220 LOC + tests |
| **WI-6** | **B** | Migrate TXT + MD containers | `TXTReaderContainerView.swift`, `MDReaderContainerView.swift`, `TXTTextViewBridge.swift`, `TXTTextViewBridgeCoordinator.swift`, `TXTChunkedReaderBridge.swift` (all MOD) | ~150 LOC delta |
| **WI-7** | **B** | Migrate PDF container | `PDFReaderContainerView.swift`, `PDFViewBridge.swift` (MOD) | ~90 LOC delta |
| **WI-8** | **B** | Migrate EPUB container | `EPUBReaderContainerView.swift` (MOD) | ~50 LOC delta |
| **WI-9** | **B** | Migrate Foliate (AZW3/MOBI) container | `FoliateSpikeView.swift` (MOD) | ~60 LOC delta |
| **WI-10** | **B** | Delete the #55 + #53 surfaces; doc-sync; final acceptance | DEL the #55/#53 files + tests (§3.9); README one-line edit; rule-24 pre-PR self-check; sync the `.readerHighlightTapped` / `ReaderHighlightTapEvent` source-comment references that name #53/#55 | ~−1200 LOC (deletions) |

**Sequencing rationale.** WI-1..5 are foundational and land the whole machine with no container wired — fully unit-tested, no behavior change, can ship in any order after WI-1 (WI-3/WI-4/WI-5 each depend only on WI-1's types; WI-4 depends on WI-2 + WI-5's protocol). WI-6 is the first behavioral PR — it wires the unified popover on the simplest format family (native TXT/MD) and is the first slice verification. WI-7/8/9 each wire one more format. WI-10 is gated on WI-6..9 all merged (R1-1 migration-safety) and is the final WI — full acceptance pass + the #55/#53 teardown. WI-9 carries the most risk (Foliate's no-renderer JS path) and lands late, after the pattern is proven on three formats.

**Dependency edges**: WI-1 → {WI-2, WI-3, WI-4, WI-5}; WI-2 + WI-5 → WI-4; WI-4 → {WI-6, WI-7, WI-8, WI-9}; {WI-6, WI-7, WI-8, WI-9} → WI-10. WI-3 → {WI-6, WI-7, WI-8} (the `HighlightRenderer`-backed formats need `changeColor`/`updateNote`); WI-9 needs `FoliateHighlightJSBridge` from WI-4 instead.

---

## 6. Test catalogue

All tests are Swift Testing (`import Testing`, `@Suite`, `@Test`) unless they need `XCTestExpectation` for notification timing (then XCTest), per `.claude/rules/10-tdd.md`. New test files mirror the source tree.

| Test file (NEW) | WI | Covers |
|---|---|---|
| `vreaderTests/Views/Reader/HighlightPopoverContentTests.swift` | WI-1 | `isEmpty` for nil / `""` / whitespace / multiline / CJK / RTL note; `id == highlightId`; `Equatable`; `chapter`/`anchor` carried. |
| `vreaderTests/ViewModels/HighlightPopoverViewModelTests.swift` | WI-1 | `handleTap` publishes content for a found highlight; nil for a deleted-race; **out-of-order** — tap A (slow) then B (fast), only B's result publishes; `dismiss` mid-flight suppresses a stale lookup; lookup-throws → `presented` cleared only if still latest; `refreshPresented` rebuilds with a mutated record preserving rect/chapter. |
| `vreaderTests/Views/Reader/HighlightPopoverModeTests.swift` | WI-1 | `HighlightMutationOutcome` `Equatable`; `HighlightPopoverMode`/`Form` cases. |
| `vreaderTests/Models/HighlightPopoverActionTests.swift` | WI-1 | `HighlightPopoverAction` cases + `Equatable` (incl. `changeColor` associated value, `saveNote` payload). |
| `vreaderTests/Views/Reader/HighlightPopoverPresenterTests.swift` | WI-2 | `content(for:)` field mapping; `form` → `.sheet` when VoiceOver / long note (> 6 lines, **boundary at exactly 6 and 7**) / `sourceRect == .zero`; `.card` otherwise; `resolvedForm` degrades `.card`→`.sheet` when `hasHostView` false; **parity** — same inputs as `NotePreviewPresenter.resolvedForm` give the same result (a regression fence until #55's enum is deleted in WI-10). |
| `vreaderTests/Views/Reader/HighlightCoordinatorMutationTests.swift` | WI-3 | `changeColor` success → `.success` + renderer repainted; `updateNote` success → `.success`; `recordNotFound` thrown → `.notFound`; generic throw → `.failed`; **EPUB href capture** — `changeColor` for an EPUB renderer captures `currentHref` before the await and calls `restoreAll(forHref:)` with the captured value (drive with a fake renderer that mutates `currentHref` mid-await — asserts the captured href, not the mutated one); trimmed-empty note normalized to `nil` before persist (nil / `""` / `"   "` / `"\n\n"`). |
| `vreaderTests/Views/Reader/HighlightActionCardViewTests.swift` | WI-4 | `displayMode`/branch helpers — reading/empty/editing/confirmingDelete subtree selection; the swatch-color mapper covers the real stored palette (yellow/pink/green/blue + red/orange/purple fallback + unknown→yellow); accessibility identifiers pinned (`highlightPopoverCard`, `...Delete`, `...Copy`, `...Share`, color buttons, `...ConfirmDelete`); excerpt clamp; light/dark card background. |
| `vreaderTests/Views/Reader/HighlightPopoverModifierTests.swift` | WI-4 | Action routing — `changeColor` → coordinator/`changeColor` (or Foliate bridge); `saveNote` → coordinator/`updateNote`; `copy` → `UIPasteboard`; **`share` → `shareItem` set + popover dismissed first, no host-`UIView` dependency in the path (R2-F7)**; `requestDelete` → mode becomes `confirmingDelete`; `confirmDelete` → delete + dismiss; `.notFound` outcome → dismiss; `.failed` → stays open, no local mutation; `cancelEdit` → mode back to `reading`; presenter-owned `noteDraft` resets on a highlight swap and on editor (re)open; **a `mode`/`noteDraft` change while the anchored card is live calls `updateCard` (not `dismissCard`+`presentCard`) (R2-F6).** |
| `vreaderTests/Views/Reader/FoliateHighlightJSBridgeTests.swift` | WI-4 | Recolor → posts `.foliateRequestAnnotationJSDelete` then `.foliateRequestAnnotationJSCreate` with the CFI from the record's `.epub` anchor + the new color + fingerprintKey (NotificationCenter spy); Delete → posts BOTH `.readerHighlightRemoved` (UUID) and `.foliateRequestAnnotationJSDelete` (CFI); a record with a non-`.epub` anchor → no JS post, logged, no crash; CFI escaping intact (`FoliateJSEscaper` already covered — assert the bridge calls the builder). |
| `vreaderTests/Views/Reader/UIKitHighlightPopoverPresenterTests.swift` | WI-5 | Serialized present/dismiss — a present→present supersede (different `content.id`); `dismissCard(completion:)` runs the completion after dismissal (and synchronously when nothing presented); no stranded presentation under rapid present/dismiss; **`presentCard` then `updateCard` for the same `content.id` does NOT re-present (in-place `rootView` reassignment); `updateCard` with nothing presented is a no-op (R2-F6).** |
| Migration tests | WI-6..9 | Per-format: the container attaches `unifiedHighlightPopoverPresenterIfAvailable` (not `notePreviewPresenterIfAvailable`); the long-press `present(...)` path is gone from the TXT/MD/PDF bridges (`handleHighlightLongPress` no longer calls a presenter — assert via the coordinator's removed properties / a compile fence). |
| WI-10 deletion | WI-10 | The deleted #55/#53 test files are removed; the suite still builds + passes with zero references to `NotePreview*` / `NoteCallout*` / `HighlightActionPresenting` / `HighlightTapAction`. |

**Audit-driven edge cases** (brainstormed per AGENTS.md): empty / nil / whitespace-only note; multiline + CJK + RTL note text; a note longer than the card cap (sheet fallback boundary at exactly 6/7 lines); a highlight deleted between tap and save (`.notFound`); two rapid taps on different highlights (out-of-order token); a color change while a chapter-nav races (EPUB href capture); a Foliate record with a missing/non-`.epub` anchor; rapid present/dismiss of the anchored card (presenter serialization); a save with the textarea unchanged (no-op `updateNote`); tapping Delete then Cancel in the confirm sub-state (mode round-trips); VoiceOver running (forces `.sheet`).

---

## 7. Backward compatibility

**This feature replaces two shipped surfaces. Nothing about persisted data changes.**

- **No schema / model change.** `HighlightRecord`, `Highlight` `@Model`, `AnnotationAnchor` are all untouched. The popover reads/writes existing fields via existing APIs. No `VReaderMigrationPlan` entry. Old highlights, old backups, CloudKit-synced highlights all keep working — the popover renders any existing `HighlightRecord` (a legacy highlight with `anchor == nil` simply has no chapter meta and, on Foliate, skips the JS repaint with a log line — §2.5).
- **Feature #55's read-only note preview is fully replaced.** After WI-10, `NoteCalloutView` / `NotePreviewSheetView` / `NotePreviewModifier` / `NotePreviewViewModel` / `NotePreviewPresenter` / `UIKitNotePreviewPresenter` are deleted. The user-visible change is strictly additive from the user's view: where a tap used to show a read-only card, it now shows the same card *plus* color/edit/delete. The Share + "Open in panel" of #55 — "Open in panel" is dropped (the unified card's Copy/Share/Delete row is the designed action row; the design has no "Open in panel" — the panel is still reachable from the reader's bottom chrome). Share is kept (Copy + Share + Delete are the designed row).
- **Feature #53's long-press Delete `UIMenu` is fully replaced.** After WI-6/WI-7, the TXT/MD/PDF long-press no longer pops a `UIMenu`; a *tap* opens the unified popover whose action row has Delete. `HighlightActionPresenter.swift` + `HighlightTapAction.swift` are deleted in WI-10. **Net gain**: EPUB/AZW3 — which never had a reader-side delete — now get Delete via the unified popover's tap.
- **The `.readerHighlightTapped` / `.readerHighlightRemoved` / `.foliateRequestAnnotationJS*` notifications are unchanged** — same names, same payloads. Only the *consumer* of `.readerHighlightTapped` changes (the new modifier instead of `NotePreviewModifier`). No bridge needs a wire-format change.
- **Doc-sync (R2-F8) — handled in WI-10, per `.claude/rules/24-doc-sync.md`:**
  - **`docs/architecture.md`**: the Notification Bus table already lists `.readerHighlightTapped` — its payload (`ReaderHighlightTapEvent`) and direction are unchanged, so no Notification Bus edit. The doc names **neither** `NotePreview*` nor `HighlightActionPresenter` anywhere (verified by `grep` — zero hits), so deleting those 10 files in WI-10 falsifies no committed claim. The new `HighlightPopoverModifier` / `HighlightPopoverViewModel` / `UIKitHighlightPopoverPresenter` stack belongs to **one** feature, so rule 24's "Coordinator/ViewModel shared by ≥2 features" trigger does not fire. **Net: no architecture-doc correction is triggered.** WI-10 still runs the rule-24 pre-PR self-check (diff-scan / claim-scan / cross-reference) to confirm this against the doc as it stands at merge time — if any claim has drifted in by then, WI-10 fixes it in the same PR.
  - **Source-comment sync (rule 22)**: the deleted #53/#55 files are referenced by `Purpose:` / `@coordinates-with` comments in surviving files — notably the `.readerHighlightTapped` + `ReaderHighlightTapEvent` doc comments in `ReaderNotifications.swift` mention `HighlightActionPresenting.present(for:in:)` and the per-bridge `sourceRect` contract. WI-10 updates those comments to name the unified popover instead. This is part of WI-10's diff, not a follow-up.
  - **`README.md`**: the feature list mentions highlight annotation; WI-10 edits one sub-bullet to say tapping a highlight opens a unified action popover (color / note / copy / share / delete). The Status line's feature count does not move by ≥5, so no Status-line edit.
- **Does this replace #55 and #53?** **Yes — explicitly.** #55's GH issue and #53's are already closed (both shipped). #64 supersedes their *surfaces*; the trackers record #64 as the unification. No re-opening of #55/#53 — #64 is the forward path. The `docs/features.md` #64 row's Lineage already notes "Refs feature #55 + #53".

---

## 8. Cross-feature conflict surface (for the parallel-execution graph)

**Feature #62 (annotations panel split) is being planned in parallel.** #62's surface area (per its plan `dev-docs/plans/20260518-feature-62-annotations-panel-split.md` and its row) is `AnnotationsPanelView.swift` → new `TOCSheet` / `HighlightsSheet` files, `HighlightListView`, the empty-state SVG art, count badges.

**#64 does NOT touch any file in #62's surface.** #64's writes are confined to:
- NEW files: `HighlightPopover*`, `HighlightActionCard*`, `UIKitHighlightPopoverPresenter`, `FoliateHighlightJSBridge`.
- MOD files: `HighlightCoordinator.swift`, the 5 reader *container* views + their bridges (`TXT*`, `MD*`, `PDF*`, `EPUB*`, `FoliateSpikeView`).
- DEL files: the #55 `NotePreview*`/`NoteCallout*` family + #53 `HighlightActionPresenter`/`HighlightTapAction`.

**`AnnotationsPanelView` / `HighlightsSheet` / `TOCSheet` / `HighlightListView` / `HighlightListViewModel` are explicitly OUT of scope for #64 (§3.10).** The two features are disjoint: #62 owns the *panel* (review-all surface), #64 owns the *in-reader tap* surface. **Zero file overlap → safe to plan and implement in parallel** (per `.claude/rules/48-parallel-execution.md`, disjoint write sets). The only shared *type* is `HighlightRecord` (read-only for both) and the `HighlightPersisting`/`HighlightLookup` protocols (neither feature modifies them). No coordination needed beyond this note.

---

## 9. Risks, mitigations, and known limitations

| Risk | Mitigation |
|---|---|
| **Foliate's no-renderer JS path is the riskiest slice.** A wrong CFI or a mis-posted notification leaves the SVG overlay stale or doubled. | `FoliateHighlightJSBridge` is pure-logic and unit-tested with a `NotificationCenter` spy (no `WKWebView`). WI-9 lands *last*, after the pattern is proven on TXT/MD/PDF/EPUB. WI-9's Gate-5 slice verification runs an AZW3 fixture on the simulator: tap a highlight → recolor → confirm the overlay color changes; delete → confirm the overlay clears. |
| **The 5-container migration could regress a format.** | One format-family per PR (WI-6..9), each independently revertable. Per-PR Gate-5 slice verification on that format's fixture. WI-10's full acceptance pass exercises all five. |
| **`HighlightActionCardView` may exceed the ~300-line file guideline** (5 modes × 2 shells). | §3.5 pre-plans the split into `HighlightActionCardSubviews.swift`. Decided in WI-4 against the actual line count. |
| **A racing chapter-nav during an EPUB recolor repaints the wrong chapter.** | `changeColor` captures `currentHref` before the persistence `await` (R1-4, Bug #103 pattern). Unit-tested with a renderer fake that mutates `currentHref` mid-await. |
| **A highlight deleted between tap and save.** | `HighlightMutationOutcome.notFound` (R1-5) — the popover dismisses cleanly instead of acting on a ghost. Unit-tested. |
| **Two `.readerHighlightTapped` consumers (old + new modifier) during the WI-6..10 window.** | One open book = one container = one modifier; a migrated and an un-migrated container never share a view tree (§3.9 migration-safety note). |

**Known limitations (Gate-2 round-3 Low findings, accepted):**

- **L1 — Foliate anchored card.** `ReaderHighlightTapEvent.sourceRect` is `.zero` for Foliate (foliate-host.js does not forward the annotation's screen rect — a pre-existing #55 limitation). So on AZW3/MOBI the unified popover always uses the **bottom-sheet** form, never the anchored card. This is *consistent* with feature #55's shipped behavior and the design's `HighlightActionSheet` is a first-class component, not a degraded fallback. Forwarding the Foliate rect for an anchored card is a deferred follow-up (a separate feature/bug, out of scope here). **Accepted.**
- **L2 — native TXT/MD/PDF anchored card needs a host-`UIView` capture channel.** Feature #55 shipped its native containers with `hostViewProvider: { nil }` (the anchored callout needs the bridge to expose its content `UIView`, which #55 deferred). The unified popover inherits the same `hostViewProvider` parameter. If a container passes `{ nil }`, `resolvedForm` degrades the card to the sheet — correct, designed behavior. Wiring the real host-view provider (so native formats get the *anchored card* rather than the sheet) can land incrementally per container in WI-6/WI-7 if the bridge already exposes its content view; if not, it degrades to the sheet exactly as #55 does today. **Accepted** — the sheet form is fully designed; the anchored card is a fidelity enhancement, not a correctness requirement. **Note:** L2 affects only *card-vs-sheet form selection*, NOT functionality — every action (color / note edit / copy / share / delete) works identically in both forms; the **Share** action specifically is host-view-independent (§3.7.1, R2-F7), so a `{ nil }` `hostViewProvider` never disables an action, it only chooses the sheet over the anchored card.

Neither Low finding blocks the feature or introduces undesigned UI (the sheet form is in the committed design).

---

## 10. Acceptance criteria (final-WI Gate-5 pass)

The feature reaches `VERIFIED` when, on iPhone 17 Pro Simulator via the `vreader-debug://` harness with a fixture book per format:

1. Tapping an existing highlight on **each of TXT, MD, PDF, EPUB, AZW3** opens the unified popover (anchored card where a host rect exists, bottom sheet otherwise) — not the old #55 read-only callout, not the #53 `UIMenu`.
2. The popover shows the correct excerpt, the highlight's color in the swatch + left bar, and the note (or the empty "Add a note…" CTA).
3. **Color change** — tapping a different color circle persists the new color AND repaints the rendered highlight on the page (verified on a `HighlightRenderer`-backed format and on Foliate).
4. **Note edit** — entering editing mode, typing, and Save persists the note; reopening the popover shows the saved note. Clearing the note + Save flips the popover to the empty state.
5. **Copy** puts the excerpt on the pasteboard; **Share** opens the system share sheet.
6. **Delete** → the confirm sub-state → Confirm removes the highlight from persistence AND clears the rendered highlight (verified on a `HighlightRenderer`-backed format and on Foliate's SVG overlay).
7. A note longer than the card cap, and VoiceOver running, both present the bottom-sheet form.
8. Light and dark reader themes both render correctly.

Recorded in `dev-docs/verification/feature-64-<YYYYMMDD>.md` per `dev-docs/verification/SCHEMA.md`.
