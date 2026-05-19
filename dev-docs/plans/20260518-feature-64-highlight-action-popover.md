# Feature #64 — Styled highlight-action popover (v2) — implementation plan

> **Document version: v3.** The feature row title in `docs/features.md` is "Styled highlight-action popover (v2)" — the "(v2)" there is the *product* version (this is the v2 re-skin of feature #53's minimal popover). This planning **document** is now at **v3**, revised after the round-2 Gate-2 audit. The two version numbers are unrelated; do not conflate them.

- **Feature row**: `docs/features.md` #64 (TODO) — "Styled highlight-action popover (v2) — replace the bare Delete UIMenu on tap-of-existing-highlight"
- **GH issue**: #822
- **Design source** (committed, rule 51 satisfied): `dev-docs/designs/vreader-fidelity-v1/project/vreader-reader.jsx` — `HighlightActionPopover` (lines 658-790), with its usage block at lines 284-295.
- **Author**: Gate-1 planner, 2026-05-18 (v1); revised 2026-05-19 (v2) addressing Gate-2 Codex audit `019e3be6`; revised 2026-05-19 (v3) addressing the round-2 independent Gate-2 audit.
- **Status**: v3 — revised after Gate-2 round 2 (NEEDS-REVISION). Pending Gate-2 re-audit.
- **Lineage**: Refs feature #60 (visual identity v2, VERIFIED) + feature #53 (bare Delete UIMenu on highlight tap, DONE). This is the v2 re-skin of the feature-#53 minimal popover.

## 0. Revision history & Gate-2 audit trail

| Version | Date | Change |
|---|---|---|
| v1 | 2026-05-18 | Initial draft (Gate-1). Submitted to Gate-2 independent audit. |
| v2 | 2026-05-19 | Revised after Gate-2 round 1 = **NEEDS-REVISION** (Codex `019e3be6`). All 14 findings resolved; see round-1 mapping table below. |
| v3 | 2026-05-19 | Revised after Gate-2 round 2 = **NEEDS-REVISION**. 4 findings (3 HIGH, 1 MED) resolved: coordinator result type, the real Foliate CFI-notification recolor architecture for WI-5, the Foliate-specific JS-delete path, and parent-owned note-editor draft. See round-2 mapping table below. The round-1 F1–F13 fixes are preserved unchanged. |

**Gate-2 round 1 verdict: NEEDS-REVISION (Codex `019e3be6`).** Every finding was independently re-verified against the codebase before resolution — the audit's central value is catching v1's wrong assumptions, so the plan asserts nothing it has not checked against a file/line/symbol.

| # | Sev | Round-1 finding | Resolution (carried into v3 unchanged) |
|---|-----|-----------------|-----------------|
| F1 | HIGH | Foliate is NOT "notification-only" — `FoliateSpikeView.swift:28` takes `highlightActionPresenter`; `ReaderContainerView.swift:685` passes `UIKitHighlightActionPresenter()`; `FoliateSpikeView+HighlightTap.swift:89` presents the delete menu. | **Verified** (`FoliateSpikeView.swift:28,67`; `FoliateSpikeView+HighlightTap.swift:55,73,89`; `ReaderContainerView.swift:680-685`). Re-sequenced: Foliate is folded into the **core** migration as **WI-5 (non-optional)**, and **WI-4 no longer deletes `HighlightActionPresenter.swift`** (§3, §5). The old presenter is kept serving Foliate only until WI-5 migrates it; the **true-final WI-6** removes it. |
| F2 | HIGH | WI-4 finality wrong — deleting `HighlightActionPresenter.swift` before Foliate migrates breaks the build / regresses shipped Foliate behavior. | **Resolved.** WI-4 is no longer final and no longer deletes the presenter. The 6-WI sequence ends with **WI-6** (delete dead presenter), which runs only after WI-5 has migrated Foliate (§5). |
| F3 | HIGH | WI-1 conformer scope incomplete — `fetchHighlight` affects more `HighlightPersisting` conformers/doubles than v1 named. | **Verified** — there are **6** conformers, not 2. WI-1 updates every one: `PersistenceActor+Highlights.swift`, `NoOpPersistenceStores.swift:20`, `MockHighlightStore.swift:9`, `HighlightCoordinatorTests.swift:74`, `HighlightCoordinatorTapHandlerTests.swift:40`, `EPUBHighlightRendererBug77Tests.swift:56` (§3 Modified files, §5 WI-1). |
| F4 | HIGH | Presenter's `@State presented: HighlightRecord?` underspecified — after `changeColor`/`updateNote` the popover UI goes stale. | **Resolved.** §3 specifies a **success-only local-state refresh**: on a successful mutation the presenter rebuilds `presented` from the mutated values (color chip, swatch ring, quote border, note card, Add/Edit label all update). Dedicated tests added (§6 `HighlightActionPopoverPresenterTests`). v3 hardens this — see round-2 R2-F4. |
| F5 | HIGH | Presenter stale-result race — tap A then B; A's slower fetch can overwrite B or reopen after dismiss. | **Resolved.** §3 specifies a **monotonic request token** (`UInt64`) + stored in-flight `Task`; a completion whose token ≠ the current token is dropped; a new request or a dismiss cancels the prior `Task`. Tested (§6). |
| F6 | HIGH | `FireOnceBox` (local to `HighlightActionPresenter.swift`) vs `HighlightActionPresenting` (referenced by 5 bridges + container) conflated — "no other `FireOnceBox` consumers" ≠ "safe to remove the protocol seam." | **Resolved.** §3/§8 keep the two distinct: `FireOnceBox` dies **with the file in WI-6**; protocol removal is a wider migration touching every caller, also in WI-6, after WI-5. The plan enumerates all 5 bridge call sites (§3). |
| F7 | MED | `restoreAll()` mid-session is safe for TXT/MD/PDF but for EPUB depends on the mutable `currentHref` fallback (`EPUBHighlightRenderer.swift:69`), nondeterministic across an `await` if chapter nav races. | **Resolved.** WI-3's `changeColor` **captures the EPUB href before the persistence `await`** and calls `restoreAll(forHref:)` explicitly for EPUB, reusing the Bug-#103 immutable-href pattern already in `EPUBReaderContainerView+Highlights.swift:165-172` (§2.1, §3, §5 WI-3, R2). Confirmed against `EPUBHighlightRenderer.swift:26` (`var currentHref: String?`) and `:69` (`let resolvedHref = href ?? currentHref`). |
| F8 | MED | Bridge audit incomplete — the active Foliate tap path is `FoliateSpikeView+HighlightTap.swift:55`, not `FoliateReaderContainerView+Highlights.swift`. | **Verified & corrected.** `FoliateReaderContainerView+Highlights.swift` is on the **dormant** `ReaderFormatHosts.FoliateReaderHost` route, never reached by `ReaderContainerView` (the only live entry, `LibraryView.swift:106`). The live AZW3/MOBI path is `FoliateSpikeView` (`ReaderContainerView.swift:680`). §3/§5 corrected. |
| F9 | MED | 10-closure callback surface on `HighlightActionPopoverView` too fragmented. | **Resolved.** The plan replaces the 10 closures with a single `HighlightActionPopoverAction` enum (associated values) + `onClose`, mirroring `SelectionPopoverView`'s `onAction:`/`onClose:`. The design JSX itself uses 6 callbacks (§3, §4). |
| F10 | MED | Missing empty/whitespace note normalization — persisting `""` instead of `nil` breaks the three-state note model + Add/Edit label. | **Resolved.** §2.4 + WI-3 normalize a trimmed-empty draft to `nil` before `updateHighlightNote`. Tests cover nil / `""` / whitespace-only / multiline / CJK / RTL (§6). |
| F11 | MED | Missing concurrent-deletion edge case — a Save/Recolor/Delete can target a record deleted after the initial fetch. | **Resolved (and hardened in v3).** §2.3 defines the behavior (no-op + dismiss, consistently). v2 left this defeated by F4's `Bool` collapse; v3's round-2 R2-F1 rework gives the presenter the typed signal it needs. WI-3/WI-4 tests cover it (§6). |
| F12 | MED | Test catalogue does not pin the two highest-risk behaviors (local-state refresh after save/recolor; stale-fetch suppression). | **Resolved.** §6 adds dedicated presenter tests for both, called out explicitly. |
| F13 | LOW | §2.3 silent-persist-failure policy IS acceptable — not a rule-51 / needs-design blocker. Stale line refs (`color/note/createdAt` ≈ 19/20/21; presenter file ≈ 260 lines not 380). | **Resolved.** §2.3 keeps the silent-failure precedent and states explicitly it is **not** a needs-design item (audit-confirmed); the real rule is "do not mutate local UI state on a failed save/recolor; log at the leaf." Line refs corrected: `HighlightRecord.color`=19, `.note`=20, `.createdAt`=21 (verified); `HighlightActionPresenter.swift` = **261 lines** (re-verified by `wc -l` for v3 — v2's "262" was off by one). |

**Gate-2 round 2 verdict: NEEDS-REVISION.** Four findings (3 HIGH, 1 MED). Each was independently re-verified against the codebase before resolution; v3 reworks the underlying mechanism rather than rewording the prose. The root cause shared by R2-F1/F2/F3 is the same: **v2 over-generalized the highlight pipeline and assumed Foliate behaves like the four `HighlightRenderer`-backed formats. It does not — Foliate's create/delete/recolor is a CFI-keyed NotificationCenter bridge into a static JS-builder struct, with no `HighlightRenderer` conformer at all.**

| # | Sev | Round-2 finding (verbatim summary) | v3 resolution |
|---|-----|-----------------|---------------|
| R2-F1 | HIGH | plan:110 — missing-row save/recolor should dismiss, but WI-3/WI-4 reduce `changeColor`/`updateNote` to a swallowed `Bool`. Persistence throws a *distinct* `PersistenceError.recordNotFound` (`PersistenceActor+Highlights.swift:106-123`). As written the presenter can't tell "record deleted → dismiss" from "generic save failure → stay open" — F11 is not genuinely resolved. | **Verified — auditor is correct.** `PersistenceActor.swift:16-17` defines `enum PersistenceError: Error, Sendable { case recordNotFound(String) … }`; `PersistenceActor+Highlights.swift:107` (`updateHighlightNote`) and `:123` (`updateHighlightColor`) both `throw PersistenceError.recordNotFound`. A `Bool` discards which error fired. **v3 replaces the `Bool` return with a typed `HighlightMutationOutcome` enum** (`success` / `notFound` / `failed`) on both `HighlightCoordinator.changeColor` and `.updateNote`. The coordinator maps the caught error: `PersistenceError.recordNotFound` → `.notFound`; any other thrown error → `.failed`; no throw → `.success`. The presenter then implements the documented §2.3 policy verbatim — `.success` → refresh local state; `.failed` → keep popover open, no local mutation; `.notFound` → dismiss. See §2.3, §3 (coordinator signatures + presenter routing), §5 WI-3/WI-4. |
| R2-F2 | HIGH | plan:294,309,378 — WI-5 assumes Foliate migrates by constructing a `HighlightCoordinator` with `FoliateHighlightRenderer` and reusing `restoreAll(forHref:)` "no JS change." `HighlightRenderer` is class-bound `apply/remove/restore` (`HighlightRenderer.swift:22-50`); `FoliateHighlightRenderer` is only a **static JS-helper struct** (`FoliateHighlightRenderer.swift:15-55`). Live Foliate repaint is notification-driven per CFI (`FoliateHighlightRestoreDispatcher.swift:53-76`, `FoliateSpikeView.swift:302-317`). WI-5 neither compiles nor specifies a real recolor path. | **Verified — auditor is correct.** `FoliateHighlightRenderer.swift:15` is `struct FoliateHighlightRenderer` — value type, only `static` methods (`addAnnotationJS`, `removeAnnotationJS`, `restoreAllJS`, `foliateColor`), no `apply/remove/restore`, no `AnyObject`. It **cannot** satisfy `HighlightRenderer` (`HighlightRenderer.swift:23` — `protocol HighlightRenderer: AnyObject`). v2's WI-5 "construct a `HighlightCoordinator` with `FoliateHighlightRenderer`" does not compile, and `restoreAll`→`renderer.restore` has no Foliate target. **v3 completely rewrites WI-5 around the real CFI-notification architecture** (no `HighlightCoordinator`, no `HighlightRenderer` for Foliate): create is `.foliateRequestAnnotationJSCreate` → `FoliateSpikeView.swift:302-317` observer; restore is `FoliateHighlightRestoreDispatcher.dispatch(...)` → per-CFI `.foliateRequestAnnotationJSCreate`; **recolor** = post `.foliateRequestAnnotationJSDelete` then `.foliateRequestAnnotationJSCreate` for the same CFI (Foliate `addAnnotation` is idempotent — `FoliateSpikeView+Restore.swift` header / view.js:387). v3 adds a pure-logic **`FoliateHighlightMutationDispatcher`** that the Foliate presenter path calls; "no JS change" is preserved (it reuses the shipped `FoliateHighlightRenderer.removeAnnotationJS`/`addAnnotationJS` builders the observers already invoke). See §2.5 (new), §3 (new file), §5 WI-5. |
| R2-F3 | HIGH | plan:247,369-370,378 — the generic delete route regresses Foliate. Today Foliate delete posts `.foliateRequestAnnotationJSDelete` with the tapped CFI so the overlay clears immediately (`FoliateSpikeView+HighlightTap.swift:89-133`). `HighlightCoordinator.handleTapAction(.delete,...)` only removes from persistence + posts `.readerHighlightRemoved` (`HighlightCoordinator.swift:101-123`) — no CFI, no Foliate JS hook. | **Verified — auditor is correct.** `FoliateSpikeView+HighlightTap.swift:112-134` `performDelete` posts both `.readerHighlightRemoved` **and** `.foliateRequestAnnotationJSDelete` (with `cfi` + `fingerprintKey`); `FoliateSpikeView.swift:280-301` is the observer that runs `FoliateHighlightRenderer.removeAnnotationJS` on the live `WKWebView`. `HighlightCoordinator.handleTapAction(.delete)` (`:109-123`) has no CFI in scope and posts only `.readerHighlightRemoved`. Routing Foliate delete through the generic coordinator would leave the SVG overlay painted. **v3 keeps a Foliate-specific delete path**: the Foliate presenter recovers the CFI from the fetched `HighlightRecord.anchor` (confirmed: `HighlightRecord.swift` carries `let anchor: AnnotationAnchor?`; `AnnotationAnchor.swift` defines `case epub(href:, cfi:, serializedRange:)` — the CFI is in the record), deletes via persistence, then posts `.readerHighlightRemoved` **and** `.foliateRequestAnnotationJSDelete`. The shared `FoliateHighlightMutationDispatcher` (R2-F2) owns this. See §2.5, §3, §5 WI-5. |
| R2-F4 | MED | plan:179-197,357 — the note editor uses internal `@State` seeded from `highlight.note`. That state will not resync when `presented` changes after a rapid second tap, after a successful save, or when edit mode reopens for a different highlight. v2 fixed `presented` staleness (F4) but left the editor draft stale. | **Verified — auditor is correct.** v2 §3's `HighlightActionPopoverView` spec says "the note editor uses a SwiftUI `TextEditor` with an internal `@State` draft seeded from `highlight.note`." SwiftUI seeds an `@State` exactly once at first appearance; it does **not** re-seed when the parent passes a different `highlight`/`isEditingNote`. After a rapid second tap (different highlight), a successful save, or edit-mode reopening, the editor would show the *previous* highlight's stale draft. **v3 makes the draft parent-owned**: the presenter holds `@State private var noteDraft: String`, `HighlightActionPopoverView` takes `noteDraft: String` + `onDraftChange: (String) -> Void` (a controlled component — exactly the JSX's `value={noteDraft}` / `onChange` shape at jsx 711-712), and the presenter **resets `noteDraft` whenever it (re)opens the editor or swaps `presented`** — keyed on `presented?.highlightId`, `presented?.note`, and the `isEditingNote` false→true transition. See §3 (`HighlightActionPopoverView` signature + presenter state), §5 WI-2/WI-4, §6. |

## 1. Problem

Feature #53 shipped the minimum tap-on-existing-highlight affordance: tapping a rendered highlight pops a bare native `UIEditMenuInteraction` menu with a single "Delete Highlight" item (`UIKitHighlightActionPresenter.buildMenu(for:completion:)` / `present(for:in:)`, `HighlightActionPresenter.swift:80-172`). The row's acceptance bar at the time was explicitly "at minimum a Delete option" (`HighlightTapAction.swift` header) — a deliberate v1.

The committed design replaces that bare menu with `HighlightActionPopover`, a styled card matching VReader's v2 visual identity (feature #60). The card depicts:

- An uppercase **"HIGHLIGHT" header row** with a small rounded color chip (the highlight's color), an optional creation-date string, and a close `✕` button.
- A **quoted serif excerpt** of the highlighted text, italic Source Serif 4, with a colored left border in the highlight's color.
- An **inline note region** with three forms: a read-only note display card (when a note exists), an editing textarea with Cancel/Save (when in note-edit mode), or nothing (when no note exists and not editing).
- A **4-circle color-change row** (yellow / pink / green / blue), the current color shown selected (accent ring + slight scale-up).
- An **action row**: "Edit note" or "Add note" (label depends on whether a note exists), "Copy", "Share", "Delete" (destructive).

The styled popover is a direct sibling of the already-shipped new-selection `SelectionPopoverView` (feature #60 WI-7) and must mirror its presentation pattern, theme handling, and typography. It is a distinct surface from `SelectionPopoverView`: that one acts on a *fresh long-press selection*; this one acts on an *already-persisted highlight*.

## 2. Backing audit — what the design shows vs what is persistence-backed

Per rule 51 and the established feature-#65 / feature-#63 "omit-don't-fake" discipline, every control in `HighlightActionPopover` was checked against the persistence layer. **The two controls the brief flagged as risky — note-editing and color-change — are both fully backed.** Findings:

| Design element (`vreader-reader.jsx` HighlightActionPopover) | Backing status | Disposition |
|---|---|---|
| "HIGHLIGHT" header + color chip | `HighlightRecord.color: String` exists (`HighlightRecord.swift:19`) | **IN** — re-skin |
| Header creation-date string (`highlight.date`) | `HighlightRecord.createdAt: Date` exists (`HighlightRecord.swift:21`) | **IN** — formatted via `DateFormatter` |
| Quoted serif excerpt + colored left border | `HighlightRecord.selectedText` (`:18`) + `.color` (`:19`) exist | **IN** — re-skin |
| Note display card (note present) | `HighlightRecord.note: String?` exists (`HighlightRecord.swift:20`) | **IN** — read-only display |
| Note editing textarea + Cancel/Save | `HighlightPersisting.updateHighlightNote(highlightId:note:)` **exists** (`HighlightPersisting.swift:35`), implemented `PersistenceActor+Highlights.swift:99-113` | **IN — note editing IS cleanly backed** (§2.1) |
| 4-circle color-change row | `HighlightPersisting.updateHighlightColor(highlightId:color:)` **exists** (`HighlightPersisting.swift:38`), implemented `PersistenceActor+Highlights.swift:115-129` | **IN — color change IS cleanly backed** (§2.1) |
| "Add note" / "Edit note" action | same `updateHighlightNote` path | **IN** |
| "Copy" action | no persistence dependency — `UIPasteboard.general.string` | **IN** — copies `selectedText` |
| "Share" action | `ShareActivityView(activityItems:)` exists (`vreader/Views/Library/ShareSheet.swift`) | **IN** — shares `selectedText` |
| "Delete" action | feature #53's existing `.delete` flow | **IN** — keeps the shipped delete behavior; routing differs per format, see §2.5 |

**No control in `HighlightActionPopover` is omitted.** Every control is backed by an existing persistence API — because feature #60 WI-3 and the highlight subsystem already shipped `updateHighlightNote`, `updateHighlightColor`, the `NamedHighlightColor` UI-domain enum, and the colored-fill render pipeline (`HighlightPaintColor`) in anticipation of exactly this UI.

> **Design-source note (corrects a v1 over-count).** The JSX `HighlightActionPopover` signature is `({ highlight, theme, onChangeColor, onEditNote, onSaveNote, onCopy, onDelete, onClose })` — **6 action callbacks**, not 10. The prototype wires "Share" and the editor's "Cancel" both to `onClose` as stubs. The plan's view does **not** reproduce a 10-closure surface (see §3, F9).

### 2.1 — Note-editing and color-change are backed but NOT yet *re-rendered live*

`updateHighlightColor` / `updateHighlightNote` **persist** correctly, but a highlight already drawn on screen will not visually change color until the highlights are re-rendered. The existing rendering paths differ by format — and **this difference is the root cause of the round-2 findings**:

- **TXT/MD/EPUB/PDF** route highlight visuals through a `HighlightRenderer` conformer (`TextHighlightRenderer`, `EPUBHighlightRenderer`, `PDFHighlightRenderer`) owned by a `HighlightCoordinator`. `HighlightCoordinator.restoreAll(forHref:using:)` fetches all `HighlightRecord`s and calls `renderer.restore(records:forHref:using:)` (`HighlightCoordinator.swift:91-99`). For TXT/MD, `HighlightPaintColor.fill(for:)` maps the stored color name to a translucent `UIColor` at paint time. For EPUB, `EPUBHighlightActions.createHighlightJS` / `restoreHighlightsJS` inject the color via JS.
- **Foliate (AZW3/MOBI)** has **no `HighlightRenderer` conformer**. `FoliateHighlightRenderer` (`FoliateHighlightRenderer.swift:15`) is a `struct` with only `static` JS-builder methods. Foliate highlight visuals are driven entirely by **NotificationCenter messages keyed on CFI**: `.foliateRequestAnnotationJSCreate` and `.foliateRequestAnnotationJSDelete` are observed inside `FoliateSpikeView.Coordinator` (`FoliateSpikeView.swift:280-317`), which evaluates `FoliateHighlightRenderer.addAnnotationJS` / `.removeAnnotationJS` on the live `WKWebView`. Restore is fanned per-CFI by `FoliateHighlightRestoreDispatcher.dispatch(...)` (`FoliateHighlightRestoreDispatcher.swift:53-77`).

So changing a highlight's color from the popover must, after persisting, trigger a **re-render** — and **the re-render mechanism is format-dependent**:

- For TXT/MD/EPUB/PDF the coordinator removes the old visual and restores from persistence (mirroring `handleRemoval`, `HighlightCoordinator.swift:66-73`). **WI-3 owns it.**
- For Foliate there is no coordinator; the recolor must be expressed as CFI notifications. **WI-5 owns it** (§2.5).

**EPUB-specific correction (F7).** `restoreAll()` is safe to call mid-session for TXT/MD/PDF — those renderers do not depend on a chapter context. **For EPUB it is not unconditionally safe**: `EPUBHighlightRenderer.restore` resolves the target chapter as `href ?? currentHref` (`EPUBHighlightRenderer.swift:69`). `currentHref` is a *mutable* property (`EPUBHighlightRenderer.swift:26` — `var currentHref: String?`); across the persistence `await` inside `changeColor`, a racing chapter navigation could mutate it, so a bare `restoreAll()` (no `forHref:`) could re-render against the wrong chapter. **WI-3's `changeColor` therefore captures the EPUB renderer's current href *before* the persistence `await` and calls `restoreAll(forHref: capturedHref)` for EPUB** — the exact immutable-href pattern Bug #103 already established in `EPUBReaderContainerView+Highlights.swift:165-172` ("capture `href` immutably and pass it into the restore call"). TXT/MD/PDF pass `forHref: nil` (their renderers ignore it). Mechanically, `changeColor` is `HighlightCoordinator`-scoped and the coordinator already holds `any HighlightRenderer`; the captured href is read from the renderer when it is an `EPUBHighlightRenderer`, else `nil`. The plan does NOT treat color-change as a pure re-skin; it is a re-skin *plus* a render-refresh wire.

### 2.2 — `HighlightRecord` vs `AnnotationRecord` — which `note` the popover writes

VReader has two distinct note concepts:

- **`HighlightRecord.note: String?`** (`HighlightRecord.swift:20`) — an *inline note attached to a highlight*. This is what `HighlightActionPopover`'s textarea reads and writes.
- **`AnnotationRecord`** (`vreader/Services/AnnotationRecord.swift`) — a *standalone note* with its own `content: String`, its own `@Model`, its own `PersistenceActor+Annotations.swift` CRUD, and its own `AnnotationsPanelView`. This is the "Add Note" flow from the *new-selection* `SelectionPopoverView`.

**The popover writes `HighlightRecord.note` via `updateHighlightNote`.** It does NOT touch `AnnotationRecord`. The design's `onSaveNote` maps 1:1 to `updateHighlightNote(highlightId:note:)`. No model change, no contract change, no migration.

### 2.3 — Failure & concurrent-deletion behavior (rule-51 + F11 + F13 + R2-F1)

`HighlightActionPopover` is in the committed bundle, so the popover surface is designed. Every state v3 ships is depicted in `vreader-reader.jsx:658-790`:

| State to ship | Depicted? | Source |
|---|---|---|
| Default (highlight with no note, not editing) | Yes — the `: null` branch renders no note region; action row shows "Add note" | jsx 743, 770 |
| With-note (read-only display card) | Yes — the `highlight.note ?` branch | jsx 732-743 |
| Note-editing (textarea + Cancel/Save) | Yes — the `editing ?` branch | jsx 702-731 |
| Color selected / unselected swatch states | Yes — `c === highlight.color` ternary: accent ring + `scale(1.08)` | jsx 748-759 |
| Color chip in header reflecting current color | Yes — `colorMap[highlight.color]` | jsx 683-685 |
| Light + dark theme surfaces | Yes — `t.isDark` ternary on background | jsx 670 |

**`HighlightActionPopover` does not depict a persistence-failure state.** Feature #53's `HighlightCoordinator.handleTapAction(.delete)` deliberately handles `.delete` failure by *silently keeping visual state intact* with no UI alert (`HighlightCoordinator.swift:118-122`, comment: "no UI alert here because the inline menu has already dismissed"). The new-selection sibling has the same gap.

**Decision (rule 51, audit-confirmed — F13).** The Gate-2 round-1 audit explicitly ruled the silent-persist-failure policy **acceptable and NOT a needs-design item** — it does not introduce a new visible element; it is the *absence* of a state, matching the established #53 behavior. **v3 mirrors that precedent and files no `needs-design` issue.** The binding rule is restated precisely: **on a failed save/recolor, the presenter must NOT mutate local UI state, and the leaf logs the error** (`Logger`, `.error`, `privacy: .public`). The popover stays consistent with persistence: a failed recolor leaves the swatch where it was; a failed note save keeps the editor open with the unsaved draft so the user can retry.

**Concurrent-deletion edge case (F11) — and the typed outcome v3 introduces (R2-F1).** A Save / Recolor / Delete can target a record that was deleted *after* the popover's initial fetch (e.g., the annotations panel removed it in another sheet). The persistence layer signals this distinctly:

- `updateHighlightColor` / `updateHighlightNote` on a missing row **throw `PersistenceError.recordNotFound`** (`PersistenceActor+Highlights.swift:107,123`; the enum is `PersistenceActor.swift:16-17`).
- `removeHighlight` on a missing row is a **silent no-op** (`PersistenceActor+Highlights.swift:91-93` — `guard … else { return }`, no throw).

**Round-2 finding R2-F1: v2's plan collapsed this signal.** v2 had `HighlightCoordinator.changeColor`/`updateNote` return a bare `Bool` — `true`/`false`. A `false` cannot distinguish "the record is gone" (must dismiss) from "the save failed transiently" (must stay open so the user retries). The documented dismiss policy below was therefore **not implementable** as v2 was written.

**v3 fix — a typed three-state outcome.** WI-3 introduces:

```swift
/// Result of an attempted highlight mutation routed through HighlightCoordinator.
/// Distinguishes a vanished record (caller dismisses the UI) from a transient
/// persistence failure (caller keeps the UI open for retry) — the Bool the v2
/// plan used could not (Gate-2 round-2 finding R2-F1).
enum HighlightMutationOutcome: Equatable, Sendable {
    case success      // persisted; caller refreshes local state
    case notFound     // PersistenceError.recordNotFound — record deleted; caller dismisses
    case failed       // any other thrown error — caller keeps UI open, logs, lets user retry
}
```

`HighlightCoordinator.changeColor` and `.updateNote` return `HighlightMutationOutcome`. The coordinator's `do/catch` maps the result:

- no throw → `.success`
- `catch PersistenceError.recordNotFound` → `.notFound`
- `catch` (any other error) → `.failed`

The presenter then implements the §2.3 policy verbatim:

- **`.success`** → rebuild `presented` from the mutated value (§3 F4); for a note save also set `isEditingNote = false`.
- **`.failed`** → do **not** mutate `presented`; the leaf already logged; the popover stays open (a failed recolor leaves the swatch; a failed note save keeps the editor open with the draft for retry).
- **`.notFound`** → dismiss the popover (the target no longer exists; keeping it open is meaningless). The presenter clears `presented` and cancels the in-flight `fetchTask`.

For **delete**, `removeHighlight`'s missing-row no-op means there is no `recordNotFound` to surface; the delete path simply persists (no-op if already gone), fires the format-appropriate visual-clear (§2.5), and dismisses. The "record concurrently deleted before the initial fetch" case is handled separately: **the initial fetch resolving `nil`** (the highlight was deleted between tap and fetch) → the presenter shows nothing.

All paths are tested (§6).

### 2.4 — Empty / whitespace note normalization (F10)

The design's note model is **three-state**: no-note (action label "Add note"), has-note (read-only card + "Edit note"), editing. That model depends on `HighlightRecord.note` being `nil` vs non-`nil`. If a user opens the editor, clears the text, and taps Save, persisting `""` would create a *fourth, unintended* state — `note == ""` is non-`nil`, so the card would render an empty box and the action label would wrongly say "Edit note."

**v3 normalizes before persisting**: in the presenter, just before it calls `coordinator.updateNote` (TXT/MD/EPUB/PDF) or the Foliate note path (WI-5), the incoming draft is trimmed of `.whitespacesAndNewlines`; if the result is empty, the persisted value is `nil`, not `""`. A whitespace-only draft therefore clears the note (consistent with "the user emptied it"). Non-empty drafts persist verbatim (interior whitespace, newlines, CJK, RTL all preserved — only leading/trailing trim is *tested* against, the *stored* value keeps the user's interior content). Tests cover nil / `""` / whitespace-only / multiline / CJK / RTL (§6).

### 2.5 — The Foliate highlight pipeline is a CFI-keyed notification bridge, NOT a `HighlightRenderer` (R2-F2, R2-F3)

**This section is new in v3.** It exists because round-2 R2-F2/R2-F3 found v2's WI-5 assumed Foliate could be migrated like the four `HighlightRenderer`-backed formats. It cannot. The facts, all verified:

- **`FoliateHighlightRenderer` is not a renderer in the `HighlightCoordinator` sense.** `FoliateHighlightRenderer.swift:15` declares `struct FoliateHighlightRenderer` — a *value type* with only `static` methods: `addAnnotationJS(cfi:color:)`, `removeAnnotationJS(cfi:)`, `restoreAllJS(highlights:)`, `foliateColor(from:)`. The `HighlightRenderer` protocol (`HighlightRenderer.swift:23`) is `protocol HighlightRenderer: AnyObject` with instance methods `apply(record:)`, `remove(id:)`, `restore(records:forHref:using:)`. A `struct` of `static` methods **cannot conform** (no `AnyObject`, no instance methods). v2's WI-5 line "a `HighlightCoordinator` for the Foliate format is constructed with the `FoliateHighlightRenderer`" **does not compile**.
- **Foliate create** = post `.foliateRequestAnnotationJSCreate` with `{cfi, color, fingerprintKey}`. `FoliateSpikeView.swift:302-317` observes it, builds JS via `FoliateHighlightRenderer.addAnnotationJS`, and evaluates it on `self.webView` under `MainActor.assumeIsolated`.
- **Foliate delete** = post `.foliateRequestAnnotationJSDelete` with `{cfi, fingerprintKey}`. `FoliateSpikeView.swift:280-301` observes it, builds JS via `FoliateHighlightRenderer.removeAnnotationJS`, and evaluates it on `self.webView`.
- **Foliate restore** = `FoliateHighlightRestoreDispatcher.dispatch(highlights:fingerprintKey:)` (`FoliateHighlightRestoreDispatcher.swift:53-77`) fans each record out as a per-CFI `.foliateRequestAnnotationJSCreate`. It skips non-`.epub` anchors and empty CFIs. It is called from `FoliateSpikeView+Restore.swift` on `.foliateOverlayReadyForSection`.
- **The CFI is in the record.** `HighlightRecord.swift` carries `let anchor: AnnotationAnchor?`; `AnnotationAnchor.swift` defines `case epub(href: String, cfi: String, serializedRange: EPUBSerializedRange)`. So for any Foliate (EPUB-anchored) highlight, the CFI is recoverable by pattern-matching `record.anchor`.
- **`addAnnotation` is idempotent.** `FoliateSpikeView+Restore.swift`'s header (and view.js:387 — `overlayer.remove(value)` precedes add) confirms re-posting create for an already-painted CFI is a no-op. **Therefore a recolor can be expressed as delete-then-create for the same CFI.**

**v3's Foliate model for #64.** Foliate is migrated to the new popover **without a `HighlightCoordinator` and without a `HighlightRenderer`**. WI-5 introduces a pure-logic helper:

```swift
/// Pure-logic helper that expresses popover-driven highlight mutations for the
/// Foliate (AZW3/MOBI) format as CFI-keyed NotificationCenter messages — the
/// only repaint mechanism Foliate has (there is no HighlightRenderer for it).
/// Sibling of FoliateHighlightRestoreDispatcher; same testable, SwiftUI-free shape.
@MainActor
enum FoliateHighlightMutationDispatcher {

    /// Clears the rendered annotation for `cfi` on the live Foliate WebView by
    /// posting `.foliateRequestAnnotationJSDelete`. The caller persists the
    /// delete separately and posts `.readerHighlightRemoved` for cross-format
    /// observers — exactly what FoliateSpikeView+HighlightTap.performDelete does
    /// today; this just relocates that pair into a testable unit.
    @discardableResult
    static func dispatchDelete(cfi: String, fingerprintKey: String,
                               notificationCenter: NotificationCenter = .default) -> Bool

    /// Recolors the rendered annotation for `cfi`: posts
    /// `.foliateRequestAnnotationJSDelete` then `.foliateRequestAnnotationJSCreate`
    /// with the new color. Foliate's addAnnotation is idempotent (view.js:387),
    /// so delete-then-create cleanly repaints. Reuses the JS builders the
    /// FoliateSpikeView observers already invoke — no JS change.
    @discardableResult
    static func dispatchRecolor(cfi: String, color: String, fingerprintKey: String,
                                notificationCenter: NotificationCenter = .default) -> Bool
}
```

Both methods guard an empty `fingerprintKey` / empty trimmed `cfi` (mirroring `FoliateHighlightRestoreDispatcher`'s guards) and return `false` when they cannot dispatch. The Foliate presenter does **not** rely on that return as its primary guard, though: it recovers and validates the CFI from `presented.anchor` *before* it persists anything (§3 WI-5 / R3-F2), so an invalid CFI fails the mutation without ever touching the store. The dispatcher's `false` is a secondary defensive check — logged, and mapped to `.failed` if it ever fires after a successful persist — never silently swallowed. **Note** carries no rendered Foliate visual (Foliate annotations are color overlays; the note text is not painted into the WebView), so a Foliate note edit needs no CFI notification — only persistence + the local-state refresh. This keeps the "no JS change" property of v2 intact: every JS string still comes from the shipped `FoliateHighlightRenderer` static builders, evaluated by the shipped `FoliateSpikeView.swift:280-317` observers.

`FoliateHighlightMutationDispatcher` is what WI-5's Foliate-format presenter path calls for color-change and delete; create is untouched (the new popover never creates a highlight — that is the new-*selection* flow). See §3 (new file) and §5 WI-5.

## 3. Surface area — file by file with concrete signatures

The current feature-#53 flow: a reader bridge's coordinator detects a tap on a rendered highlight, builds a `ReaderHighlightTapEvent { highlightID: UUID; sourceRect: CGRect }`, posts `.readerHighlightTapped`, and — if a `HighlightActionPresenting` is wired — calls `presenter.present(for:in:) { action in ... }`, routing the resolved `HighlightTapAction` to `HighlightCoordinator.handleTapAction(_:highlightID:)`.

**Five live wired presenter call sites** (all verified):
- `EPUBWebViewBridgeCoordinator.swift:134` (`handleHighlightTapMessage`, `presenter.present(for:event,in:webView)`)
- `TXTTextViewBridgeCoordinator.swift:210`
- `TXTChunkedReaderBridge.swift:380`
- `PDFViewBridge.swift:468`
- `FoliateSpikeView+HighlightTap.swift:89` (`FoliateHighlightTapHandlerModifier.handle`, active path — **F1/F8**)

> **Foliate correction (F1, F8).** v1 §3/§5 claimed Foliate "posts the notification only (no presenter)." **This is wrong.** `ReaderContainerView.swift:680-685` routes `azw3` directly to `FoliateSpikeView(... highlightActionPresenter: UIKitHighlightActionPresenter())`. `FoliateSpikeView.swift:28` declares `var highlightActionPresenter: (any HighlightActionPresenting)?` and `:67` threads it into `.foliateHighlightTapHandler(presenter:)`. `FoliateSpikeView+HighlightTap.swift:55-99` is the live modifier — it fetches highlights, posts `.readerHighlightTapped`, and at `:89` calls `presenter.present(for:event,in:anchorView)` showing the delete menu. The `FoliateReaderContainerView+Highlights.swift` file v1 cited is on a **dormant** route: it belongs to `FoliateReaderHost` in `ReaderFormatHosts.swift`, which `ReaderContainerView` never reaches (the only live reader entry is `LibraryView.swift:106 → ReaderContainerView`). The live AZW3/MOBI host is `FoliateSpikeView`.

> **Foliate architecture correction (R2-F2, R2-F3).** Beyond *who presents the menu* (F1/F8), v2 also got *how Foliate paints/repaints* wrong. There is **no `HighlightRenderer` for Foliate** and **no `HighlightCoordinator` on the AZW3/MOBI path**. Foliate highlight visuals are CFI-keyed NotificationCenter messages observed inside `FoliateSpikeView.Coordinator` (`FoliateSpikeView.swift:280-317`). v3's WI-5 is rewritten around that real architecture — see §2.5 and the new-file `FoliateHighlightMutationDispatcher` below.

**Critical architectural finding (unchanged from v1):** `ReaderHighlightTapEvent` carries only `highlightID` + `sourceRect`. The styled popover needs `selectedText`, `color`, `note`, `createdAt` to render — and, for Foliate, the `anchor` (to recover the CFI). There is currently **no fetch-by-ID method** on `HighlightPersisting` — only `fetchHighlights(forBookWithKey:)` (returns all) + the mutators. **WI-1 adds the fetch-by-ID API.** Because `fetchHighlight` returns a full `HighlightRecord` (which carries `anchor`), the Foliate presenter path gets the CFI for free — no event change needed.

The new popover is a SwiftUI view (a styled card with a textarea — `UIEditMenuInteraction` cannot host that). It mirrors `SelectionPopoverView`: a presentational SwiftUI `View` + a `ViewModifier` presenter that observes a notification and shows it as a sheet. The `UIKitHighlightActionPresenter` is **replaced as the wired presenter on all five paths**; the `HighlightActionPresenting` protocol + the file are **removed in WI-6, after all five bridges (including Foliate) are migrated** (§5, §8).

### New files

All new view files are `#if canImport(UIKit)`-gated (matching `SelectionPopoverView.swift`). Each stays under the ~300-line guideline (rule 50 §9). Symbol-collision check: none of `HighlightActionPopoverView`, `HighlightActionPopoverPresenter`, `HighlightActionRow`, `HighlightActionPopoverAction`, `HighlightActionPopoverRequest`, `HighlightMutationOutcome`, `FoliateHighlightMutationDispatcher` collide with an existing symbol (verified against the `vreader/` tree — `grep` returned no prior declaration for any of them, and `.readerHighlightActionRequested` does not yet exist).

- **`vreader/Views/Reader/HighlightActionRow.swift`** (new, foundational) — UI-presentation enum for the four action-row slots, mirroring `SelectionPopoverActionRow.swift` (which lives in `Views/Reader/`, **not** `ViewModels/` — v1 mis-placed this; corrected). Pins display order, labels, SF Symbols, accessibility identifiers, the destructive slot, the note-label variance (jsx 769-774):
  ```swift
  /// Visible action-button slot in the HighlightActionPopover action row.
  /// Order matches dev-docs/designs/.../vreader-reader.jsx HighlightActionPopover
  /// (jsx 769-774) exactly: edit-note / copy / share / delete.
  enum HighlightActionRow: String, CaseIterable, Equatable {
      case note      // label is "Add note" or "Edit note" — see label(hasNote:)
      case copy
      case share
      case delete

      /// "Edit note" when the highlight already has a note, else "Add note".
      func label(hasNote: Bool) -> String { ... }
      var systemImage: String { ... }   // note.text / doc.on.doc / square.and.arrow.up / trash
      var isDestructive: Bool { self == .delete }
      var accessibilityIdentifier: String { ... }  // highlightPopoverNote / ...Copy / ...Share / ...Delete
  }
  ```

- **`vreader/Models/HighlightActionPopoverAction.swift`** (new, foundational) — the dispatch enum, replacing v1's 10 closures (**F9**). Mirrors `SelectionPopoverAction.swift` (`Models/`, `Equatable, Sendable`, not `Codable` — local-dispatch only):
  ```swift
  /// One value per user-tappable control in HighlightActionPopoverView.
  /// The view funnels every tap through a single `(HighlightActionPopoverAction) -> Void`
  /// — mirroring SelectionPopoverView's `onAction:` — plus a separate `onClose`.
  enum HighlightActionPopoverAction: Equatable, Sendable {
      case changeColor(NamedHighlightColor)
      case beginEditNote          // parent flips isEditingNote → true, seeds noteDraft
      case saveNote               // parent persists the parent-owned noteDraft (R2-F4)
      case cancelEditNote         // parent flips isEditingNote → false
      case copy
      case share
      case delete
  }
  ```
  Rationale for the divergence vs the JSX's 6 callbacks: `cancelEditNote` is split out from `onClose` (the JSX stubs them together) because the editor's Cancel must *not* dismiss the whole sheet — it returns to the read-only/no-note state. `share` is a real case (the JSX stubs it to `onClose`).

  > **Round-2 change (R2-F4): `saveNote` carries no payload.** v2's `case saveNote(String)` passed the draft text as an associated value, which fit a view-owned `@State` draft. v3 makes the draft **parent-owned** (see `HighlightActionPopoverView` below), so the parent already holds the text — `.saveNote` is a bare signal "persist the current `noteDraft`." This matches the controlled-component shape and removes any chance of the action carrying a different value than what the parent thinks is current.

  This is the *minimum* faithful set; it matches `SelectionPopoverAction`'s single-enum shape and keeps `HighlightActionPopoverView`'s action API to **two** funnels (`onAction`, `onClose`) plus the controlled-draft pair, instead of ten closures.

- **`vreader/Views/Reader/HighlightActionPopoverView.swift`** (new, behavioral with WI-2) — the presentational SwiftUI card, mirroring `SelectionPopoverView` (purely presentational; theme passed in; **one action funnel + onClose + a controlled note draft**):
  ```swift
  /// The tap-on-existing-highlight popover — design vreader-reader.jsx
  /// HighlightActionPopover (jsx 658-790). Purely presentational and fully
  /// STATELESS: the parent owns the highlight record, the editing flag, AND
  /// the note draft (Gate-2 round-2 finding R2-F4 — a view-owned @State draft
  /// goes stale when the parent swaps `highlight` or reopens the editor).
  struct HighlightActionPopoverView: View {
      let highlight: HighlightRecord
      /// True when the inline note editor is open. The parent owns this
      /// flag (the design's `editingNote`) so the view stays stateless.
      let isEditingNote: Bool
      /// The note editor's current text — PARENT-OWNED (controlled component;
      /// mirrors the JSX `value={noteDraft}` at jsx 711). The view renders it
      /// and reports edits via `onDraftChange`; it holds NO @State draft of
      /// its own. The parent re-seeds it on every editor (re)open / record swap.
      let noteDraft: String
      /// Reports each keystroke in the editor back to the parent — the JSX
      /// `onChange={e => setNoteDraft(e.target.value)}` (jsx 712).
      let onDraftChange: (String) -> Void
      let theme: ReaderThemeV2
      /// Single funnel for every user tap (mirrors SelectionPopoverView.onAction).
      let onAction: (HighlightActionPopoverAction) -> Void
      /// Close `X`; distinct so the parent can dismiss with no side-effect.
      let onClose: () -> Void
      var body: some View { ... }
  }
  ```
  Renders: header (color chip + "HIGHLIGHT" + formatted `createdAt` + close), serif quoted excerpt with colored leading border, the note region (three forms keyed on `isEditingNote` / `highlight.note`), the color row (hidden while editing, jsx 746), the action row (hidden while editing, jsx 764). Reuses the file-private `Color(hexString:)` helper pattern and `ReaderTypography.body(for:.sourceSerif4/.inter,size:)` typography from `SelectionPopoverView`. **The note editor is a SwiftUI `TextEditor` bound to a controlled value**: `TextEditor(text:)` is fed a `Binding` that reads `noteDraft` and writes through `onDraftChange` (a custom `Binding(get:set:)`), so the view holds no `@State` of its own. Save emits `.saveNote` (the parent persists its own `noteDraft`); Cancel emits `.cancelEditNote`.

  > **Why parent-owned (R2-F4).** SwiftUI seeds an `@State` exactly once, at first appearance of the view identity. If the editor's draft were the view's `@State` seeded from `highlight.note`, then after a rapid second tap (a *different* highlight resolves into `presented`), after a successful save, or when edit-mode reopens, the editor would still show the *first* highlight's text. Making the draft a parent-owned controlled value, with the parent re-seeding it on every editor open / record swap (see the presenter below), eliminates the stale-draft class entirely — the same reason the parent owns `presented` and `isEditingNote`.

- **`vreader/Views/Reader/HighlightActionPopoverPresenter.swift`** (new, behavioral with WI-4) — the wire format + SwiftUI presenter modifier, mirroring `SelectionPopoverPresenter.swift`:
  ```swift
  /// Typed payload carried as notification.object on `.readerHighlightActionRequested`.
  struct HighlightActionPopoverRequest: Equatable, Sendable {
      let event: ReaderHighlightTapEvent   // highlightID + sourceRect
  }

  @MainActor
  enum HighlightActionPopoverRequestBus {
      static func post(event: ReaderHighlightTapEvent,
                       on center: NotificationCenter = .default)
      nonisolated static func request(from note: Notification)
          -> HighlightActionPopoverRequest?
  }

  /// View modifier: observes `.readerHighlightActionRequested`, fetches the
  /// HighlightRecord by ID, presents HighlightActionPopoverView as a sheet,
  /// owns isEditingNote AND the note draft, routes a HighlightActionPopoverAction.
  extension View {
      func highlightActionPopoverPresenter(
          theme: ReaderThemeV2,
          persistence: any HighlightPersisting,
          mutationRoute: HighlightPopoverMutationRoute
      ) -> some View
  }
  ```

  > **Round-2 change (R2-F2/R2-F3): `mutationRoute` replaces `coordinator`.** v2's modifier took a `coordinator: HighlightCoordinator`. That works for the four `HighlightRenderer`-backed formats but is *meaningless for Foliate*, which has no coordinator. v3 introduces a small enum the container picks at attach time, so one presenter type serves all five formats:
  > ```swift
  > /// How a given reader format applies popover-driven highlight mutations.
  > /// TXT/MD/EPUB/PDF route through HighlightCoordinator (HighlightRenderer-backed);
  > /// Foliate has no coordinator — it routes through CFI notifications (§2.5).
  > enum HighlightPopoverMutationRoute {
  >     case coordinator(HighlightCoordinator)              // TXT, MD, EPUB, PDF
  >     case foliate(fingerprintKey: String)                // AZW3, MOBI
  > }
  > ```
  > The presenter's action handlers branch on `mutationRoute`. For `.coordinator`, color-change/note-save call `HighlightCoordinator.changeColor`/`.updateNote` and delete calls `coordinator.handleTapAction(.delete,…)`. For `.foliate`, the CFI is **recovered and validated from `presented.anchor` before any persistence (R3-F2)**: an `.epub(…)` anchor whose CFI is empty/missing maps straight to `.failed` with **no** `persistence` call, so the SwiftData store and the Foliate overlay never diverge. With a valid CFI — color-change persists via `persistence.updateHighlightColor` then calls `FoliateHighlightMutationDispatcher.dispatchRecolor(cfi:color:fingerprintKey:)`; delete persists via `persistence.removeHighlight`, posts `.readerHighlightRemoved`, then calls `FoliateHighlightMutationDispatcher.dispatchDelete(cfi:fingerprintKey:)`. The dispatcher still returns `Bool`; because the CFI was pre-validated its `false` is only a defensive belt — a `false` *after* a successful persist is logged and mapped to `.failed`, so the presenter never reports `.success` over a stale overlay. note-save persists via `persistence.updateHighlightNote` (no CFI notification — note text is not painted, §2.5). Both routes funnel through the same `HighlightMutationOutcome` decision (R2-F1) so the dismiss/refresh/retain policy (§2.3) is identical across formats.

  **Presenter state model (F4 + F5 + R2-F1 + R2-F4) — fully specified:**

  The modifier holds:
  ```swift
  @State private var presented: HighlightRecord?      // the record currently shown
  @State private var isEditingNote: Bool = false
  @State private var noteDraft: String = ""           // parent-owned editor draft (R2-F4)
  @State private var requestSeq: UInt64 = 0           // monotonic request token
  @State private var fetchTask: Task<Void, Never>?    // in-flight fetch, cancellable
  ```

  - **Stale-fetch suppression (F5).** On each `.readerHighlightActionRequested`: increment `requestSeq` → capture it as `token`; cancel any existing `fetchTask`; start a new `fetchTask` that does `persistence.fetchHighlight(highlightId:)`. When the fetch completes, the closure checks `token == requestSeq` **and** `!Task.isCancelled` — if either fails, the result is dropped (it belongs to a superseded tap). Only a current, non-cancelled result sets `presented`, resets `isEditingNote = false`, and **re-seeds `noteDraft` from the fetched record's `note`** (`?? ""`). Tapping highlight A then B quickly therefore cannot let A's slower fetch overwrite B or reopen the sheet after a dismiss — *and* cannot leave B showing A's note draft. Sheet dismissal (close button, drag-down, post-action) also cancels `fetchTask`, bumps `requestSeq`, clears `presented`, and resets `isEditingNote`/`noteDraft` so a late completion is inert.

  - **Note-draft seeding (R2-F4).** `noteDraft` is re-seeded at exactly three moments, so it can never go stale:
    1. **A new record resolves into `presented`** (the fetch completion above) → `noteDraft = record.note ?? ""`.
    2. **The editor opens** — on `.beginEditNote`, set `isEditingNote = true` and `noteDraft = presented?.note ?? ""` (covers reopening the editor on the *same* highlight after an earlier Cancel left a half-typed draft).
    3. **A note save succeeds** — `noteDraft` is set to the normalized saved value and `isEditingNote = false`.
    `HighlightActionPopoverView` receives `noteDraft` as a plain `let` and reports edits through `onDraftChange` (which writes the `@State`). Because the view holds no draft `@State` of its own, there is no second source of truth to drift.

  - **Local-state refresh after a successful mutation (F4 + R2-F1).** The presenter does **not** leave `presented` stale after `changeColor` / `saveNote`. `HighlightRecord` is an immutable `struct`; the presenter branches on the `HighlightMutationOutcome` the coordinator/Foliate path returns:
    - `.changeColor(c)` → run the route's recolor; **on `.success`**, set `presented = presented.with(color: c.rawValue)` so the header color chip, the selected swatch ring, and the quote's left border all update immediately. **On `.notFound`**, dismiss. **On `.failed`**, leave `presented` untouched (the leaf logged).
    - `.saveNote` → normalize `noteDraft` (§2.4) → run the route's note-update; **on `.success`**, set `presented = presented.with(note: normalized)`, `noteDraft = normalized ?? ""`, and `isEditingNote = false` so the note card / "Add note"↔"Edit note" label flip correctly. **On `.notFound`**, dismiss. **On `.failed`**, leave `presented` and `isEditingNote` untouched — the editor stays open with the user's draft for retry.

    Mechanism: a small file-private helper `HighlightRecord.with(color:)` / `.with(note:)` returning a copy with one field replaced (all other fields — including `anchor`, `highlightId`, `locator` — carried verbatim). This is a pure value-type copy, not a re-fetch — cheaper, and avoids a second race. (A refetch is the audit-named alternative; the copy-with-mutated-field is chosen because the mutation result is already known and a refetch would re-introduce an async window. If a future control mutates a field the presenter cannot compute locally, refetch becomes the right tool — flagged, not pre-built.)

  Color/note/delete actions route per `mutationRoute` (above); copy/share are local (`UIPasteboard.general.string` / a `ShareActivityView` sheet) and identical for all formats.

- **`vreader/Views/Reader/FoliateHighlightMutationDispatcher.swift`** (new, foundational — **WI-5**) — the pure-logic CFI-notification helper for Foliate popover-driven recolor + delete. Full rationale and signatures in §2.5. Sibling of `FoliateHighlightRestoreDispatcher.swift`; `@MainActor enum`; SwiftUI/WKWebView-free so it is unit-testable against a stub `NotificationCenter`. It reuses no new JS — the `FoliateSpikeView.swift:280-317` observers it triggers already call the shipped `FoliateHighlightRenderer` static builders.

- **`vreader/Models/HighlightMutationOutcome.swift`** (new, foundational — **WI-3**) — the typed three-state mutation result (`success` / `notFound` / `failed`), full rationale in §2.3 (R2-F1). `Equatable, Sendable`, not `Codable` (local-dispatch only). Placed in `Models/` next to `HighlightActionPopoverAction.swift`.

- **Test files** — see §6.

### Modified files

- **`vreader/Services/HighlightPersisting.swift`** (43 lines) — WI-1. Add one protocol method:
  ```swift
  /// Fetches a single highlight by its ID, or nil if no such highlight exists.
  func fetchHighlight(highlightId: UUID) async throws -> HighlightRecord?
  ```
- **`vreader/Services/PersistenceActor+Highlights.swift`** (169 lines) — WI-1. Implement `fetchHighlight(highlightId:)` via a `#Predicate<Highlight> { $0.highlightId == id }` `FetchDescriptor` with `fetchLimit = 1`, mapping through the existing private `highlightToRecord(_:)` (which already copies `anchor`, `:156-168`). Mirrors the existing `removeHighlight` lookup shape (`:84-97`) exactly.
- **Every `HighlightPersisting` conformer + test-double (F3) — WI-1.** v1 named only `PersistenceActor` + `MockHighlightStore`. There are **six** conformers; `fetchHighlight` is a protocol requirement so **all six** must implement it or the build breaks:
  1. `vreader/Services/PersistenceActor+Highlights.swift:10` — the real implementation (above).
  2. `vreader/Views/Reader/NoOpPersistenceStores.swift:20` (`NoOpHighlightStore`) — returns `nil`.
  3. `vreaderTests/Services/Mocks/MockHighlightStore.swift:9` (`MockHighlightStore`, an `actor`) — backed by its in-memory store; add a `fetchHighlight` that looks up its store + a throw-injection switch so WI-3/WI-4 failure tests can drive it (the switch must be able to throw `PersistenceError.recordNotFound` *and* a generic error, so the `HighlightMutationOutcome` mapping can be exercised — R2-F1).
  4. `vreaderTests/Views/Reader/HighlightCoordinatorTests.swift:74` (`MockPersistence`) — add `fetchHighlight` honoring its `shouldThrow` / `stubbedHighlights`; extend its throw injection so a test can make `updateHighlightColor`/`updateHighlightNote` throw `PersistenceError.recordNotFound` specifically (R2-F1 outcome-mapping tests).
  5. `vreaderTests/Views/Reader/HighlightCoordinatorTapHandlerTests.swift:40` (`TapMockPersistence`) — add `fetchHighlight` (return `nil` or a stub).
  6. `vreaderTests/Views/Reader/EPUBHighlightRendererBug77Tests.swift:56` (`MockPersistence77`) — add `fetchHighlight` (return from `stubbedHighlights`).
- **`vreader/Views/Reader/HighlightCoordinator.swift`** (127 lines) — WI-3. Add two methods returning the typed `HighlightMutationOutcome` (R2-F1 — **not `Bool`**):
  ```swift
  /// Persists a new color for an existing highlight, then re-renders it.
  /// Returns .success if persisted, .notFound if the record was deleted
  /// (PersistenceError.recordNotFound — caller dismisses), .failed for any
  /// other error (caller keeps the popover open for retry). For EPUB the
  /// current chapter href is captured BEFORE the persistence await and passed
  /// to restoreAll(forHref:) so a racing chapter nav cannot misroute the
  /// re-render (Bug #103 pattern; §2.1).
  func changeColor(highlightID: UUID, to color: NamedHighlightColor) async -> HighlightMutationOutcome

  /// Persists an edited note. The caller passes the already-normalized value
  /// (trimmed-empty → nil, §2.4). Note text is not body-rendered, so no
  /// re-render. Returns .success / .notFound / .failed (see changeColor).
  func updateNote(highlightID: UUID, note: String?) async -> HighlightMutationOutcome
  ```
  `changeColor`: captures `(renderer as? EPUBHighlightRenderer)?.currentHref` into `capturedHref` *before* `await`; calls `persistence.updateHighlightColor`; on no-throw `renderer.remove(id:)` + `restoreAll(forHref: capturedHref)` then returns `.success`; `catch PersistenceError.recordNotFound` → log at the leaf + leave visual unchanged + return `.notFound`; `catch` any other error → log + leave visual unchanged + return `.failed`. `updateNote`: calls `persistence.updateHighlightNote`; no-throw → `.success`; `catch PersistenceError.recordNotFound` → `.notFound`; other `catch` → `.failed`. Both log the swallowed error at the leaf (rule 50 §6 — the acceptable swallow), matching `handleTapAction(.delete)`. The `.notFound`/`.failed` split is the entire point of R2-F1: a `do/catch` that pattern-matches `PersistenceError.recordNotFound` as a distinct `catch` clause.
- **Four reader-bridge coordinators** — WI-4. Each currently calls `presenter.present(...)`. WI-4 changes each to post `HighlightActionPopoverRequestBus.post(event:)` instead (the `.readerHighlightTapped` post stays unchanged). Affected:
  - `vreader/Views/Reader/EPUBWebViewBridgeCoordinator.swift` (`handleHighlightTapMessage`, line 124-142)
  - `vreader/Views/Reader/TXTTextViewBridgeCoordinator.swift` (line ~205-218)
  - `vreader/Views/Reader/TXTChunkedReaderBridge.swift` (line ~375-390)
  - `vreader/Views/Reader/PDFViewBridge.swift` (line ~463-478)
  The `highlightActionPresenter` / `onHighlightTapAction` properties on `EPUBWebViewBridge`, `TXTTextViewBridge`, `TXTChunkedReaderBridge`, `PDFViewBridge` and their coordinators become unused on the present-path. WI-4 removes the `present(...)` call; since the popover presenter modifier is attached at the container level and is handed a `HighlightPopoverMutationRoute.coordinator(...)`, the per-bridge `onHighlightTapAction` plumbing for the tap-present path is removed too. (See §7 R7.) **Foliate's `FoliateSpikeView` is NOT touched in WI-4** — it keeps `UIKitHighlightActionPresenter` until WI-5.
- **Four reader container views** — WI-4. Each attaches the new presenter modifier and drops the `highlightActionPresenter:`/`onHighlightTapAction:` arguments it passes into its bridge:
  - `vreader/Views/Reader/EPUBReaderContainerView.swift` (presenter passed at line ~458; container has `settingsStore?.theme`, `highlightCoordinator`, a `HighlightPersisting`)
  - `vreader/Views/Reader/PDFReaderContainerView.swift` (line ~102)
  - `vreader/Views/Reader/TXTReaderContainerView.swift` (lines ~552, ~613, ~655 — three bridge variants)
  - `vreader/Views/Reader/MDReaderContainerView.swift` (line ~339)
  Each container holds `highlightCoordinator` as **optional `@State`** (`HighlightCoordinator?`, populated after reader setup completes — `EPUBReaderContainerView.swift:66`, `TXTReaderContainerView.swift:79`, `MDReaderContainerView.swift:45`, `PDFReaderContainerView.swift:66`). The `HighlightPopoverMutationRoute.coordinator` case takes a **non-optional** `HighlightCoordinator`, so `.coordinator(highlightCoordinator)` does not type-check directly (R3-F1). The fix is to **defer the mount**: attach the modifier inside `if let highlightCoordinator { … }`. A rendered highlight cannot be tapped before reader setup completes, so the presenter has no work before the coordinator exists — deferring the mount loses nothing. Inside the `if let`, `.highlightActionPopoverPresenter(theme:persistence:mutationRoute: .coordinator(highlightCoordinator))` receives a non-optional value; `theme` (`settingsStore?.theme ?? .paper`) and the `HighlightPersisting` are already non-optional in scope.
- **`vreader/Views/Reader/FoliateSpikeView.swift` + `FoliateSpikeView+HighlightTap.swift`** — **WI-5**. See the WI-5 entry in §5 for the full, rewritten plan (the v2 description here was the source of R2-F2/R2-F3 and is replaced). In brief: `FoliateSpikeView+HighlightTap.swift:89` (`presenter.present(...)`) is swapped to `HighlightActionPopoverRequestBus.post(event:)`; the `highlightActionPresenter` parameter is removed from `FoliateSpikeView` (`:28,67`) and `FoliateHighlightTapHandlerModifier` (`:55,73,138-146`); `ReaderContainerView.swift:680-685` drops the `highlightActionPresenter:` argument and attaches `.highlightActionPopoverPresenter(theme:persistence:mutationRoute: .foliate(fingerprintKey:))`. **No `HighlightCoordinator` and no `HighlightRenderer` are constructed for Foliate** — the recolor/delete go through `FoliateHighlightMutationDispatcher` (§2.5). The existing `FoliateSpikeView.swift:280-317` JS-create/JS-delete observers and `FoliateSpikeView+Restore.swift` are **untouched** ("no JS change" preserved). `FoliateSpikeView+HighlightTap.swift`'s own `performDelete` (`:112-134`) — which posts `.readerHighlightRemoved` + `.foliateRequestAnnotationJSDelete` — is **superseded** by the presenter's Foliate delete path (which does the same pair via `FoliateHighlightMutationDispatcher.dispatchDelete`); WI-5 removes the now-dead `performDelete` and the closure that called it.
- **`HighlightActionPresenter.swift`** (**261 lines** — re-verified by `wc -l`; v1's "380" and v2's "262" were both wrong) — **WI-6** (not WI-4). The `UIKitHighlightActionPresenter` class + `HighlightActionPresenting` protocol + `FireOnceBox` + `PresenterDelegate` become dead **only after WI-5 migrates Foliate** — the last consumer. WI-6 **deletes `HighlightActionPresenter.swift`** + its test `UIKitHighlightActionPresenterTests.swift`. `project.yml` globs `vreader/` by folder, so the deletion needs no `project.yml` source-list edit; WI-6's `xcodegen generate` regenerates `project.pbxproj` without the files.

  > **`FireOnceBox` vs `HighlightActionPresenting` (F6) — kept distinct.** `FireOnceBox` is referenced **only** inside `HighlightActionPresenter.swift` and `UIKitHighlightActionPresenterTests.swift` (verified by grep — no other consumer). It therefore dies *with the file* in WI-6, no separate migration. `HighlightActionPresenting` is **different**: it is referenced by all five bridges + `ReaderContainerView` (`EPUBWebViewBridge.swift`, `TXTTextViewBridge.swift`, `TXTChunkedReaderBridge.swift`, `PDFViewBridge.swift`, `FoliateSpikeView.swift`, `FoliateSpikeView+HighlightTap.swift`, `ReaderContainerView.swift`, plus `HighlightTapAction.swift`'s doc comment + a `FakePresenter` in `TXTBridgeHighlightTapSubscriberTests.swift`). Removing the *protocol* is a wider migration: WI-4 strips the four primary bridges, WI-5 strips Foliate, and **only WI-6** — after every caller is gone — deletes the protocol declaration itself. The plan does not conflate "`FireOnceBox` has no other consumer" with "the protocol seam is safe to remove."
- **`vreader/Views/Reader/ReaderNotifications.swift`** — WI-4. Add the `.readerHighlightActionRequested` name (verified absent today). The existing `.readerHighlightTapped` / `.readerHighlightRemoved` / `.foliateRequestAnnotationJSCreate` / `.foliateRequestAnnotationJSDelete` (`:115`) are **unchanged** — WI-5 reuses the last two as-is.
- **`docs/architecture.md`** — WI-6 (docs-sync, rule 24). Update any description of the highlight-tap flow to name the new SwiftUI popover instead of the UIEditMenu, once the UIEditMenu path is fully gone.
- **`project.yml`** — version bumps per rule 40 (one bump commit per PR).

### Files explicitly OUT of scope

- **`vreader/Views/Reader/SelectionPopoverView.swift`, `SelectionPopoverPresenter.swift`, `SelectionPopoverActionRouter.swift`, `SelectionPopoverActionRow.swift`, `Models/SelectionPopoverAction.swift`** — the *new-selection* popover is a separate, already-shipped surface. #64 does not touch it. The two popovers are visually similar siblings but functionally distinct; they are not unified.
- **`vreader/Models/Highlight.swift`, `Services/HighlightRecord.swift`, `AnnotationAnchor.swift`** — **no model change**. `note`, `color`, `createdAt` already exist on `HighlightRecord` (`:20,:19,:21`) and on `Highlight` (`@Model`); `anchor` already exists on `HighlightRecord` and is already copied by `highlightToRecord`. Storage stays a raw `String` for color (per `NamedHighlightColor.swift` header). No SwiftData migration. (The `HighlightRecord.with(color:)/.with(note:)` value-copy helper is a file-private struct extension on the *value type*, not a stored-property or schema change.)
- **`vreader/Services/AnnotationRecord.swift`, `AnnotationNote.swift`, `PersistenceActor+Annotations.swift`, `AnnotationsPanelView.swift`** — standalone notes are a different concept (§2.2). Untouched.
- **`vreader/Models/NamedHighlightColor.swift`, `HighlightPaintColor.swift`** — the named-color enum and the TXT/MD colored-fill renderer already exist (feature #60 / Bug #208). #64 consumes them; it does not change them.
- **`vreader/Views/Reader/FoliateReaderContainerView.swift`, `FoliateReaderContainerView+Highlights.swift`, `FoliateReaderContainerView+Navigation.swift`, `ReaderFormatHosts.swift` `FoliateReaderHost`** — the **dormant** Foliate container, not on the live `ReaderContainerView` route (§3 F8). #64 does not touch it; the live AZW3/MOBI path is `FoliateSpikeView`.
- **`FoliateHighlightRenderer.swift`** — the **static JS-builder struct** (`:15`) is **consumed unchanged**. WI-5's Foliate recolor/delete go through `FoliateHighlightMutationDispatcher`, which posts the CFI notifications that the *existing* `FoliateSpikeView.swift:280-317` observers turn into `FoliateHighlightRenderer.addAnnotationJS`/`.removeAnnotationJS` calls. **No JS string is added or changed.** (v2 also listed this file as out-of-scope but mis-described it as if it were a `HighlightRenderer` — see R2-F2; v3 keeps it out of scope for the *correct* reason.)
- **`vreader/Views/Reader/FoliateSpikeView+Restore.swift`, `FoliateHighlightRestoreDispatcher.swift`, the `.foliateRequestAnnotationJSCreate`/`.foliateRequestAnnotationJSDelete` observers in `FoliateSpikeView.swift:280-317`** — the Foliate **restore + JS-create/JS-delete** machinery is reused as-is. WI-5 *posts into* `.foliateRequestAnnotationJSCreate`/`.foliateRequestAnnotationJSDelete` via the new dispatcher; it does not modify the observers or the restore handler.
- **EPUB/Foliate highlight JS, `EPUBHighlightJS.swift`** — color *rendering* JS already exists. #64's color-change re-render reuses `HighlightCoordinator.restoreAll(forHref:)` for the four `HighlightRenderer` formats and the CFI-notification path for Foliate. No JS change.
- **Backup DTOs, `ExportedAnnotation`, export/import** — color stays a `String`; no serialized-format change.

## 4. Prior art / project precedent / rejected alternatives

**Precedent — feature #60 WI-7 `SelectionPopoverView` + `SelectionPopoverPresenter`.** The new-selection popover is the exact pattern #64 mirrors: a presentational SwiftUI `View` (stateless, `theme: ReaderThemeV2` injected, **a single `onAction:` enum funnel + `onClose`** — `SelectionPopoverView.swift:49,54`), a `ViewModifier` presenter that observes a notification and presents a `.sheet` with `.presentationDetents` + `.presentationBackground(.clear)` (`SelectionPopoverPresenter.swift:215`), a typed `…Request` wire-format struct with `post(...)` + `nonisolated …(from:)` parse helpers, and a `…ActionRow` UI-presentation enum pinning the action slots with contract tests. #64 reuses every shape — including, per the audit (F9), the **single-enum action funnel** rather than a fan of closures. It also reuses `SelectionPopoverView`'s file-private `Color(hexString:)` helper pattern and its `ReaderTypography` typography choices. **One deliberate divergence from the sibling (R2-F4): `HighlightActionPopoverView` exposes a parent-owned note draft (`noteDraft` + `onDraftChange`) because it hosts an editable `TextEditor` — `SelectionPopoverView` has no text field, so it had no draft to own. The presenter-owns-the-draft choice keeps the highlight popover as stateless as its sibling.**

**Precedent — feature #65 / #63 "omit-don't-fake" discipline.** Feature #65's plan §2 omitted four unbacked controls. #64 applied the same audit (§2) and found — favorably — that **nothing needs omitting**.

**Precedent — feature #53's tap infrastructure.** `ReaderHighlightTapEvent`, `.readerHighlightTapped`, `HighlightTapAction`, `HighlightCoordinator.handleTapAction`, and per-bridge tap-detection are reused unchanged for the *detection* half. #64 swaps only the *presentation* half.

**Precedent — feature #53's silent-failure handling.** `HighlightCoordinator.handleTapAction(.delete)` swallows a persist failure with no UI alert (`HighlightCoordinator.swift:118-122`). #64's `changeColor` / `updateNote` follow the same *leaf-logs-and-swallows* pattern (§2.3) — and the Gate-2 round-1 audit explicitly confirmed this is acceptable, not a needs-design item (F13). **v3 refines it (R2-F1): the swallow still happens, but the coordinator now also classifies the swallowed error into `HighlightMutationOutcome` so the presenter can dismiss-vs-retain correctly.**

**Precedent — Bug #103 immutable-href capture.** `EPUBReaderContainerView+Highlights.swift:165-172` already captures `href` immutably before an `await` and passes it to `coordinator.restoreAll(forHref:)` so a racing chapter nav cannot misroute restore JS. #64's WI-3 `changeColor` reuses exactly this pattern for EPUB (§2.1, F7).

**Precedent — `FoliateHighlightRestoreDispatcher` (Bug #207 / GH #765).** The Foliate restore path is *already* a pure-logic enum that fans `HighlightRecord`s out as per-CFI `.foliateRequestAnnotationJSCreate` notifications (`FoliateHighlightRestoreDispatcher.swift`). #64's new `FoliateHighlightMutationDispatcher` (§2.5) is a direct sibling — same `@MainActor enum`, same testable `NotificationCenter`-injectable shape, same CFI-keyed contract — extended to *recolor* (delete+create) and *delete*. This is the established Foliate pattern, not a new abstraction.

**Precedent — `FoliateSpikeView+HighlightTap.performDelete` (Bug #199).** Foliate delete *today* already posts `.readerHighlightRemoved` **and** `.foliateRequestAnnotationJSDelete` together (`FoliateSpikeView+HighlightTap.swift:112-134`). v3's Foliate delete path does exactly this pair — it just relocates it from a private static method on the tap modifier into the testable `FoliateHighlightMutationDispatcher` so the new popover presenter can call it. **The shipped Foliate delete *behavior* is preserved bit-for-bit** (R2-F3).

**Rejected — keep `UIEditMenuInteraction` and restyle it.** `UIEditMenuInteraction` renders a system menu; it cannot host a serif excerpt, a color-circle row, or an editable textarea. SwiftUI sheet presentation is the only way. The UIEditMenu presenter is replaced.

**Rejected — extend `ReaderHighlightTapEvent` to carry `selectedText`/`color`/`note`/`createdAt`/`cfi`.** Every bridge (EPUB JS, TXT, PDF, Foliate) would have to source the full highlight content at tap time; EPUB's JS `highlightTapHandler` only knows the `id` + DOM rect. Far simpler: the presenter fetches the `HighlightRecord` by ID once — and the record *already carries `anchor`*, so the Foliate CFI comes for free. This is why **WI-1 adds `fetchHighlight(highlightId:)`**. The event stays a thin `{id, rect}` locator.

**Rejected — reuse `SelectionPopoverView` for both flows.** The two popovers differ structurally (header row; three-form note region; selected-color indicator; different action set). The design ships them as two separate components; #64 keeps them separate.

**Rejected — keep the `HighlightActionPresenting` protocol as the abstraction.** The protocol was introduced (feature #53) so tests could inspect the `UIMenu` without presenting. The new SwiftUI popover is tested differently — `HighlightActionPopoverView` is unit-tested directly, and `HighlightActionPopoverRequestBus` + the `HighlightCoordinator` methods + `FoliateHighlightMutationDispatcher` are pure-logic testable. The protocol no longer earns its keep. **WI-6 removes it — after WI-5, not WI-4** (F1/F2/F6).

**Rejected — a 10-closure `HighlightActionPopoverView` API (v1's design).** The Gate-2 round-1 audit (F9) flagged this as over-fragmented and divergent from the `SelectionPopoverView` sibling. The plan collapses it to one `HighlightActionPopoverAction` enum + `onClose` (plus the controlled `noteDraft`/`onDraftChange` pair).

**Rejected — a view-owned `@State` note draft (v2's design).** v2 §3 had `HighlightActionPopoverView` hold an internal `@State` draft seeded from `highlight.note`. The Gate-2 round-2 audit (R2-F4) flagged that a SwiftUI `@State` seeds only once and does not resync when the parent swaps the highlight or reopens the editor. **v3 moves the draft to the parent** (controlled component), with the presenter re-seeding it on every record swap / editor open / successful save — see §3.

**Rejected — a `Bool` return from `changeColor`/`updateNote` (v2's design).** v2 had the coordinator methods return `Bool`. The Gate-2 round-2 audit (R2-F1) showed a `Bool` cannot distinguish `PersistenceError.recordNotFound` (must dismiss) from a transient failure (must stay open). **v3 returns the typed `HighlightMutationOutcome`** (`success`/`notFound`/`failed`) — see §2.3.

**Rejected — migrate Foliate by giving it a `HighlightCoordinator` + a `HighlightRenderer` (v2's WI-5).** The Gate-2 round-2 audit (R2-F2) showed `FoliateHighlightRenderer` is a `static`-only `struct` that **cannot conform** to the class-bound `HighlightRenderer` protocol, and that Foliate repaint is CFI-notification-driven with no coordinator. **v3 rewrites WI-5 around the real CFI-notification architecture** (`FoliateHighlightMutationDispatcher`, §2.5) — no coordinator, no renderer, no JS change.

**Rejected — route Foliate delete through `HighlightCoordinator.handleTapAction(.delete)` (v2's implicit assumption).** The Gate-2 round-2 audit (R2-F3) showed `handleTapAction(.delete)` posts only `.readerHighlightRemoved` and has no CFI — routing Foliate delete through it would leave the SVG overlay painted. **v3 keeps a Foliate-specific delete path** that recovers the CFI from `HighlightRecord.anchor` and posts `.foliateRequestAnnotationJSDelete`, preserving the shipped Bug-#199 behavior.

**Rejected — refetch the record after every mutation to refresh the popover.** The audit (F4) named refetch-or-optimistic as the two options. The plan chooses the **success-only local value-copy** (`HighlightRecord.with(...)`): the mutation result is already known, so a refetch would re-open an async window the F5 token machinery just closed. Refetch is the right tool only if a future control mutates a field the presenter cannot compute locally — flagged, not pre-built.

**Rejected — bundle color-change and note-edit into one WI with the view.** Color-change carries a real behavioral surface (the live re-render, §2.1). Keeping it as its own WI (WI-3) isolates the one genuinely behavioral coordinator change.

## 5. Work-item sequencing

**Six WIs, each one PR** (v1 had five; F1/F2 require Foliate as a non-optional core WI and a separate true-final cleanup WI). Feature size = Large (6 WIs) → 1 plan audit (this gate) + 1 PR audit per WI (rule 47 audit table). WI-1 is independently auditable; WI-2 is independently auditable; WI-3/WI-4/WI-5/WI-6 share the highlight-popover surface and run sequentially on one feature branch. Version-bump tier per `/feature-workflow`: foundational/behavioral-not-final → `patch`, final WI → `minor`.

| WI | Title | Tier | Final? | PR size | RED test |
|----|-------|------|--------|---------|----------|
| WI-1 | `fetchHighlight(highlightId:)` on `HighlightPersisting` + **all 6 conformers/doubles** | foundational | no | small | fetch returns the record for a known ID; `nil` for an unknown ID; `nil` after remove |
| WI-2 | `HighlightActionRow` + `HighlightActionPopoverAction` enums + `HighlightActionPopoverView` presentational card (parent-owned note draft) | foundational | no | medium | the three note forms render per `isEditingNote`/`note`; the editor renders the injected `noteDraft` and reports edits via `onDraftChange`; each tap emits the right `HighlightActionPopoverAction`; close fires `onClose` |
| WI-3 | `HighlightMutationOutcome` + `HighlightCoordinator.changeColor` + `.updateNote` (persist + EPUB-safe re-render + typed outcome) | behavioral | no | small | `changeColor` persists + re-renders (EPUB via `forHref:`); `updateNote`; both return `.success`/`.notFound`/`.failed` mapped from the thrown error |
| WI-4 | `HighlightActionPopoverPresenter` (+ `HighlightPopoverMutationRoute`) + wire the **4 primary** bridges/containers (EPUB/TXT/TXT-chunked/PDF) | behavioral | no | large | the presenter fetches by ID + presents; stale-fetch suppression; note-draft re-seed on record swap / editor open; local-state refresh after save/recolor; `.notFound` dismiss; actions route; the bare UIMenu no longer appears for the 4 formats |
| WI-5 | Migrate **Foliate** (`FoliateSpikeView`) to `.readerHighlightActionRequested` + the new presenter; add `FoliateHighlightMutationDispatcher` (CFI-notification recolor/delete) | behavioral | no | medium | `FoliateSpikeView+HighlightTap` posts `.readerHighlightActionRequested`; `FoliateHighlightMutationDispatcher.dispatchRecolor`/`dispatchDelete` post the right CFI notifications; popover presents over the Foliate container; the bare UIMenu no longer appears for AZW3/MOBI |
| WI-6 | Delete the dead `UIKitHighlightActionPresenter` + `HighlightActionPresenting` protocol + `FireOnceBox`; docs-sync | behavioral | **yes** | small | build is green with `HighlightActionPresenter.swift` removed; no symbol references the deleted protocol |

### WI-1 — `fetchHighlight(highlightId:)` (foundational)

Add the protocol method to `HighlightPersisting`; implement it in `PersistenceActor+Highlights.swift` (a `#Predicate<Highlight>` lookup, `fetchLimit = 1`, mapped via the existing `highlightToRecord` which already carries `anchor`); add the conformance to **all six** conformers (§3 Modified files — `NoOpHighlightStore`, `MockHighlightStore`, `MockPersistence`, `TapMockPersistence`, `MockPersistence77`). `MockHighlightStore` and `MockPersistence` also gain a throw-injection switch capable of throwing **both** `PersistenceError.recordNotFound` and a generic error (so WI-3's outcome-mapping tests can drive each branch — R2-F1). No UI, no behavior. RED: `PersistenceHighlightTests` (extend) — fetch a just-added highlight by ID returns it (and the returned record's `anchor` matches); fetch a random UUID returns `nil`; fetch after `removeHighlight` returns `nil`. **PR size: small (~8 files — 1 protocol + 1 real impl + 4 production/test conformers updated + 1 test file; ~80 LOC).** Foundational → unit tests sufficient, no device verify (rule 47 Gate 5).

### WI-2 — `HighlightActionRow` + `HighlightActionPopoverAction` + `HighlightActionPopoverView` (foundational)

Build the `HighlightActionRow` UI-presentation enum (`Views/Reader/`, mirroring `SelectionPopoverActionRow`), the `HighlightActionPopoverAction` dispatch enum (`Models/`, mirroring `SelectionPopoverAction` — `.saveNote` is a **bare case, no payload**, R2-F4), and the presentational `HighlightActionPopoverView` SwiftUI card. **The view is fully stateless** — it holds *no* `@State`, not even for the note editor. The note editor's `TextEditor` is bound to a controlled `Binding(get: { noteDraft }, set: { onDraftChange($0) })`; the parent owns `noteDraft` and `isEditingNote`. All wiring is via the single `onAction` funnel + `onClose` + the `onDraftChange` reporter. Renders all designed states (§2.3). No production presenter wired yet — the view ships standalone, exactly as `SelectionPopoverView` shipped in feature #60 WI-7a before its presenter. RED: `HighlightActionRowTests` (contract: 4 cases, order, labels incl. `label(hasNote:)` variance, SF Symbols, a11y ids, destructive slot) + `HighlightActionPopoverViewTests` (composition: the `editing` state hides the color+action rows per jsx 746/764; the `note`-present state renders the display card; the no-note state renders neither; **the editor renders exactly the injected `noteDraft` string**; typing in the editor invokes `onDraftChange` with the new text; each tap emits the matching `HighlightActionPopoverAction`; Save emits bare `.saveNote`; Cancel emits `.cancelEditNote`). **PR size: medium (~5 files, ~310 LOC).** Foundational (dormant view, no behavior) → unit tests sufficient.

### WI-3 — `HighlightMutationOutcome` + `HighlightCoordinator.changeColor` + `.updateNote` (behavioral)

Add the `HighlightMutationOutcome` enum (`Models/`, §2.3) and the two coordinator methods (§3). `changeColor`: capture `(renderer as? EPUBHighlightRenderer)?.currentHref` into `capturedHref` **before** the `await`; `persistence.updateHighlightColor` → on no-throw `renderer.remove(id:)` + `restoreAll(forHref: capturedHref)` so the on-screen highlight re-renders in the new color (TXT/MD/PDF get `forHref: nil`, which their renderers ignore; EPUB gets the captured href so a racing chapter nav cannot misroute, §2.1/F7) → return `.success`; `catch PersistenceError.recordNotFound` → log at the leaf + leave visual unchanged + return `.notFound`; `catch` any other error → log + leave visual unchanged + return `.failed`. `updateNote`: the caller passes the already-normalized value; `persistence.updateHighlightNote`; map no-throw/`recordNotFound`/other to `.success`/`.notFound`/`.failed` the same way. (The trimmed-empty→nil normalization itself, §2.4/F10, lives in the presenter just before it calls `updateNote` — tested at both layers.) RED: `HighlightCoordinatorTests` (extend) — `changeColor` calls `updateHighlightColor` with the right args, then invokes `renderer.restore` with the captured href (assert via the existing renderer test double's `lastRestoreHref`); `changeColor` returns `.success` on no-throw; **returns `.notFound` when the mock throws `PersistenceError.recordNotFound`** and **`.failed` when the mock throws a generic error** — and in both failure cases leaves the renderer untouched; `updateNote` returns `.success`/`.notFound`/`.failed` mapped the same way; idempotency — `changeColor` to the *same* color still persists + re-renders + returns `.success`. **PR size: small (~3 files, ~110 LOC).** Behavioral, not final → slice-verify the color-change re-render on the iPhone 17 Pro Simulator (create a highlight, drive `changeColor`, confirm the rendered highlight changes color) — verify EPUB specifically since it is the format with the href-capture nuance.

### WI-4 — `HighlightActionPopoverPresenter` + 4-primary-bridge/container wiring (behavioral)

Build `HighlightActionPopoverPresenter.swift`: the `HighlightActionPopoverRequest` wire struct, the `HighlightActionPopoverRequestBus` post/parse enum, the `HighlightPopoverMutationRoute` enum (§3 — `.coordinator` is the only case exercised in WI-4; `.foliate` lands wired in WI-5), the `HighlightActionPopoverPresenterModifier` + `.highlightActionPopoverPresenter(...)` extension. The modifier observes `.readerHighlightActionRequested`, fetches the `HighlightRecord` by ID (WI-1) with the **request-token + cancellable-Task** machinery (§3 F5), owns `isEditingNote` **and `noteDraft`** (re-seeding `noteDraft` on every record swap / editor open / successful save — §3 R2-F4), presents `HighlightActionPopoverView` (WI-2) as a sheet, and routes a `HighlightActionPopoverAction`:
- `.changeColor` → run the route's recolor (for `.coordinator`: `await coordinator.changeColor(...)`, WI-3) → branch on `HighlightMutationOutcome`: `.success` → rebuild `presented` with the new color (§3 F4); `.notFound` → dismiss; `.failed` → leave `presented` untouched.
- `.beginEditNote` → `isEditingNote = true`; `noteDraft = presented?.note ?? ""` (R2-F4).
- `.saveNote` → **normalize `noteDraft`** (trim; empty→`nil`, §2.4) → run the route's note-update (for `.coordinator`: `await coordinator.updateNote(...)`, WI-3) → branch: `.success` → rebuild `presented` with the normalized note, set `noteDraft` to the normalized value, `isEditingNote = false`; `.notFound` → dismiss (§2.3); `.failed` → leave editor open with the draft for retry.
- `.cancelEditNote` → `isEditingNote = false` (does **not** dismiss the sheet).
- `.delete` → for `.coordinator`: `coordinator.handleTapAction(.delete, highlightID:)` then dismiss.
- `.copy` → `UIPasteboard.general.string = highlight.selectedText`.
- `.share` → present a `ShareActivityView(activityItems:[highlight.selectedText])`.

Swap the **four primary** bridges (EPUB / TXT-nonchunked / TXT-chunked / PDF) from `presenter.present(...)` to `HighlightActionPopoverRequestBus.post(event:)`; attach `.highlightActionPopoverPresenter(theme:persistence:mutationRoute: .coordinator(highlightCoordinator))` on the four primary container views; remove the now-dead per-bridge `onHighlightTapAction`/`highlightActionPresenter` tap-present plumbing on those four. Add `.readerHighlightActionRequested` to `ReaderNotifications.swift`. **Foliate's `FoliateSpikeView` is untouched here** — it keeps `UIKitHighlightActionPresenter` until WI-5, so the build and shipped AZW3/MOBI delete behavior stay intact (F1/F2). RED: `HighlightActionPopoverPresenterTests` — the `…RequestBus` post/parse round-trip; `.request(from:)` returns `nil` for a malformed `object`; **stale-fetch suppression** (a second request supersedes the first; the first's late fetch completion does not set `presented`); **note-draft re-seed** (after a second tap resolves a different record, `noteDraft` equals the *new* record's note, not the previous draft; on `.beginEditNote` `noteDraft` equals `presented.note`); **local-state refresh** (after a `.success` `changeColor` the `presented` color updates; after a `.success` `saveNote` the note + `noteDraft` + `isEditingNote` update); **`.notFound` dismiss** (a `changeColor`/`saveNote` returning `.notFound` clears `presented`); **`.failed` retain** (a `.failed` mutation leaves `presented` and `isEditingNote` unchanged); a fetch resolving `nil` yields no presentation; the dismiss policy (a delete clears `presented`; `.cancelEditNote` only flips `isEditingNote`). **PR size: large (~13 files, ~460 LOC).** Behavioral, not final → end-to-end acceptance on the iPhone 17 Pro Simulator for **TXT, MD, EPUB, PDF** (Foliate verified in WI-5): tap a highlight → styled card → change color (verify re-render) → add a note → reopen, confirm note shows → edit → copy → share → delete.

### WI-5 — Migrate Foliate (`FoliateSpikeView`) to the new presenter, via the CFI-notification architecture (behavioral)

**This WI is fully rewritten in v3** — v2's WI-5 was the source of round-2 R2-F2/R2-F3 and did not compile. v3's WI-5 is built on the *real* Foliate architecture (§2.5): a CFI-keyed NotificationCenter bridge, **no `HighlightCoordinator`, no `HighlightRenderer`**.

Steps:

1. **New file `FoliateHighlightMutationDispatcher.swift`** (§2.5, §3) — the `@MainActor enum` with `dispatchRecolor(cfi:color:fingerprintKey:)` (posts `.foliateRequestAnnotationJSDelete` then `.foliateRequestAnnotationJSCreate`) and `dispatchDelete(cfi:fingerprintKey:)` (posts `.foliateRequestAnnotationJSDelete`). Both guard empty `fingerprintKey` / empty trimmed `cfi`, return `false` on a guard miss, and take an injectable `NotificationCenter`. It reuses no new JS — the existing `FoliateSpikeView.swift:280-317` observers turn these notifications into `FoliateHighlightRenderer.removeAnnotationJS`/`.addAnnotationJS` calls.
2. **Wire the `.foliate` route in the presenter.** `HighlightActionPopoverPresenterModifier` (built in WI-4) already branches on `HighlightPopoverMutationRoute`; WI-5 implements the `.foliate(fingerprintKey:)` branch:
   - `.changeColor(c)` → recover the CFI by pattern-matching `presented?.anchor` for `.epub(_, cfi, _)`; if no CFI (a non-EPUB-anchored record — should not happen for a Foliate book, but defended), treat as `.failed`. Persist via `persistence.updateHighlightColor(highlightId:color:)`; map the thrown error to `HighlightMutationOutcome` exactly as the coordinator does (no-throw → `.success`, `recordNotFound` → `.notFound`, other → `.failed`); **on `.success`** call `FoliateHighlightMutationDispatcher.dispatchRecolor(cfi:color:fingerprintKey:)` then rebuild `presented` with the new color. `.notFound` → dismiss; `.failed` → retain.
   - `.saveNote` → normalize `noteDraft` (§2.4); persist via `persistence.updateHighlightNote(highlightId:note:)`; map to `HighlightMutationOutcome`. **No CFI notification** — Foliate annotations paint color only, the note text is not rendered into the WebView (§2.5). `.success` → rebuild `presented` + reset `noteDraft` + `isEditingNote = false`; `.notFound` → dismiss; `.failed` → retain.
   - `.delete` → recover the CFI from `presented?.anchor`; persist via `persistence.removeHighlight(highlightId:)` (a missing-row delete is a silent no-op — `PersistenceActor+Highlights.swift:91-93`); post `.readerHighlightRemoved`; call `FoliateHighlightMutationDispatcher.dispatchDelete(cfi:fingerprintKey:)`; dismiss. This reproduces, bit-for-bit, the shipped `FoliateSpikeView+HighlightTap.performDelete` pair (R2-F3).
   - `.copy` / `.share` are format-agnostic — identical to the four primary formats.
   The mutation-route-specific logic stays small; if it pushes the presenter file over the ~300-line guideline, the `.foliate` branch is extracted into a `HighlightActionPopoverPresenter+Foliate.swift` sibling (decided at implementation time by `wc -l`).
3. **Swap the Foliate tap path.** `FoliateSpikeView+HighlightTap.swift:89` (`presenter.present(...)`) → `HighlightActionPopoverRequestBus.post(event:)`. Remove the `highlightActionPresenter` parameter from `FoliateSpikeView` (`:28,67`) and `FoliateHighlightTapHandlerModifier` (`:55,73`, the `extension View` helper `:138-146`). Remove the now-dead `performDelete` static method (`:112-134`) and the `present`-completion closure (`:89-99`) — the popover presenter now owns delete (step 2). The `.readerHighlightTapped` post (`:82`) and the `FoliateHighlightTapResolver` fetch (`:77-80`) **stay** — other observers (annotations panel) still depend on `.readerHighlightTapped`, and the resolver is how the tap becomes a `highlightID`.
4. **Attach the presenter on the AZW3 route.** `ReaderContainerView.swift:680-685` drops `highlightActionPresenter: UIKitHighlightActionPresenter()` and attaches `.highlightActionPopoverPresenter(theme:persistence:mutationRoute: .foliate(fingerprintKey: book.fingerprintKey))`: the `azw3` case has `settingsStore` (→ `theme = settingsStore?.theme ?? .paper`), `modelContext.container` (→ `PersistenceActor(modelContainer:)` for `HighlightPersisting`), and `book.fingerprintKey` in scope. **No `HighlightCoordinator` and no `HighlightRenderer` are constructed** — the `.foliate` route needs neither.

The existing `FoliateSpikeView.swift:280-317` JS-create/JS-delete observers, `FoliateSpikeView+Restore.swift`, and `FoliateHighlightRestoreDispatcher.swift` are **untouched** — "no JS change" is preserved (R2-F2). Because the popover is presented as a detented sheet (not anchored to a rect), Foliate's `.zero` `sourceRect` is not a blocker. **Foliate is NOT optional** (F1) — leaving it on `UIKitHighlightActionPresenter` while WI-6 deletes that file would break the build; WI-5 is a required step before WI-6.

RED: `FoliateSpikeViewHighlightPopoverTests` — `FoliateHighlightTapHandlerModifier` posts `.readerHighlightActionRequested` (not `present(...)`) on an annotation-tap, carrying the resolved `highlightID`. `FoliateHighlightMutationDispatcherTests` (new) — `dispatchRecolor` posts a `.foliateRequestAnnotationJSDelete` **then** a `.foliateRequestAnnotationJSCreate` for the same CFI with the new color and the `fingerprintKey`; `dispatchDelete` posts exactly one `.foliateRequestAnnotationJSDelete` with the CFI + `fingerprintKey`; both return `false` and post nothing for an empty `fingerprintKey` or an empty/whitespace CFI (mirroring `FoliateHighlightRestoreDispatcher`'s guard tests). **PR size: medium (~6 files, ~200 LOC).** Behavioral, not final → slice-verify on the simulator with an AZW3 fixture: tap a Foliate highlight → styled card → change color (confirm the overlay repaints in the new color) → add a note → reopen, confirm note shows → delete (confirm the overlay clears immediately).

### WI-6 — Delete the dead `UIKitHighlightActionPresenter` (behavioral, final)

After WI-5, **no caller** references `HighlightActionPresenting` or `UIKitHighlightActionPresenter`. WI-6 deletes `vreader/Views/Reader/HighlightActionPresenter.swift` (the `UIKitHighlightActionPresenter` class, the `HighlightActionPresenting` protocol, `FireOnceBox`, `PresenterDelegate` — all 261 lines) and its test `vreaderTests/Views/Reader/UIKitHighlightActionPresenterTests.swift`. Update `HighlightTapAction.swift`'s header doc comment (it references `HighlightActionPresenting`). Update or remove `FakePresenter` in `TXTBridgeHighlightTapSubscriberTests.swift` if it still references the protocol (verify at implementation time — that suite asserts the bridge's *notification* behavior, so it should survive with the fake dropped). `project.yml` is folder-glob-based; WI-6's `xcodegen generate` regenerates `project.pbxproj` without the deleted files — WI-6 confirms the `pbxproj` diff before committing. Docs-sync `architecture.md` (rule 24) to describe the SwiftUI popover instead of the UIEditMenu. RED: this WI is a deletion — its "test" is the **build + the full existing regression suite passing green** with the files gone (no symbol resolves to the deleted protocol). **PR size: small (~4 files touched, net negative LOC).** Behavioral + final WI → full end-to-end acceptance pass on the iPhone 17 Pro Simulator for **TXT, MD, EPUB, PDF, AZW3** confirming the styled card still appears and the bare UIMenu is gone everywhere. Record in `dev-docs/verification/feature-64-<YYYYMMDD>.md` per `dev-docs/verification/SCHEMA.md`. **This WI flips the feature row to `DONE`.**

## 6. Test catalogue

Swift Testing (`import Testing`, `@Suite`, `@Test`) — the default for the existing highlight + selection-popover suites. SwiftUI views are tested for composition/behavior (the right sub-view renders per input; the right action is emitted), not pixels — as `SelectionPopoverPresenterTests` does.

- **`vreaderTests/Services/PersistenceHighlightTests.swift`** (extend, WI-1) — `fetchHighlight(highlightId:)` returns the record for a known ID (and the returned `anchor` matches what was stored); `nil` for an unknown UUID; `nil` after the highlight is removed; an in-memory `ModelContainer` per test (rule 50 §8).
- **The 5 non-real conformers** (extend, WI-1) — `NoOpHighlightStore`, `MockHighlightStore`, `MockPersistence`, `TapMockPersistence`, `MockPersistence77` each gain `fetchHighlight`; `MockHighlightStore` and `MockPersistence` get a throw-injection switch that can throw **`PersistenceError.recordNotFound` and a distinct generic error** + a stub-lookup, so WI-3's outcome-mapping and WI-4's failure-path/fetch tests can drive every branch.
- **`vreaderTests/Views/Reader/HighlightActionRowTests.swift`** (new, WI-2) — contract: exactly 4 cases in declared order (note/copy/share/delete); `label(hasNote: false)` == "Add note", `label(hasNote: true)` == "Edit note"; SF Symbol per case; accessibility identifier per case; `isDestructive` true only for `.delete`.
- **`vreaderTests/Models/HighlightActionPopoverActionTests.swift`** (new, WI-2) — `HighlightActionPopoverAction` `Equatable`/`Sendable` smoke + the associated-value carry (`.changeColor(.pink) != .changeColor(.blue)`); `.saveNote` is a bare case (no payload — R2-F4) and equals itself.
- **`vreaderTests/Models/HighlightMutationOutcomeTests.swift`** (new, WI-3) — `HighlightMutationOutcome` `Equatable`/`Sendable` smoke; the three cases are mutually distinct (`.success != .notFound != .failed`).
- **`vreaderTests/Views/Reader/HighlightActionPopoverViewTests.swift`** (new, WI-2) — composition/behavior: with `isEditingNote == true` the color row and action row are absent (jsx 746/764) and the textarea + Cancel/Save are present; with a non-nil `note` and `isEditingNote == false` the read-only note card renders; with `note == nil` and not editing, neither note form renders; the action row's note slot label tracks `note` presence; **the editor renders exactly the injected `noteDraft` string** (pass `noteDraft: "seed"`, assert the editor shows `"seed"` — R2-F4); **typing invokes `onDraftChange`** with the edited text and the view holds no draft `@State` of its own; tapping a color swatch emits `.changeColor` with the right `NamedHighlightColor`; tapping close fires `onClose`; tapping each action row emits the matching `HighlightActionPopoverAction`; Save emits bare `.saveNote`; Cancel emits `.cancelEditNote`; the header renders a formatted `createdAt`.
- **`vreaderTests/Views/Reader/HighlightCoordinatorTests.swift`** (extend, WI-3) — `changeColor(highlightID:to:)` calls `updateHighlightColor` with the stored color name, then re-renders (assert the renderer double's `restore`/`remove`); `changeColor` passes the captured EPUB href to `restore` (assert `lastRestoreHref`); **`changeColor` returns `.success` on no-throw, `.notFound` when the mock throws `PersistenceError.recordNotFound`, `.failed` when the mock throws a generic error** — and in both failure cases leaves the renderer untouched; `updateNote(highlightID:note:)` calls `updateHighlightNote` and returns `.success`/`.notFound`/`.failed` mapped from the thrown error (R2-F1); **concurrent-deletion** — `updateHighlightColor`/`updateHighlightNote` throwing `recordNotFound` makes the coordinator return `.notFound` (the presenter's dismiss trigger); idempotency — `changeColor` to the *same* color still persists + re-renders + returns `.success`.
- **`vreaderTests/Views/Reader/HighlightActionPopoverPresenterTests.swift`** (new, WI-4) — **the highest-risk behaviors are pinned here per F12 + R2-F1 + R2-F4:**
  - **Stale async-fetch suppression after rapid taps (F5):** a request for highlight A followed by a request for highlight B — when A's (slower) fetch completes, `presented` is B's record, not A's; a fetch that completes *after* the sheet was dismissed does not re-present.
  - **Note-draft re-seed (R2-F4):** after a second tap resolves a *different* record into `presented`, `noteDraft` equals the new record's `note ?? ""`, not the prior draft; on `.beginEditNote`, `noteDraft` is re-seeded from `presented.note` (so reopening the editor after an earlier Cancel discards the abandoned half-typed draft); after a `.success` `saveNote`, `noteDraft` equals the normalized saved value.
  - **Local popover-state refresh after save/recolor (F4):** after a `.success` `changeColor`, the `presented` record's `color` reflects the new color (header chip / swatch / border would update); after a `.success` `saveNote`, the `presented` record's `note` reflects the saved value and `isEditingNote` is `false`; after a **`.failed`** mutation, `presented` and `isEditingNote` are unchanged (no optimistic mutation, §2.3).
  - **Typed-outcome dismiss policy (R2-F1):** a `changeColor`/`saveNote` returning `.notFound` clears `presented` (dismiss); a `.failed` mutation leaves `presented` (and, for a note save, the open editor + draft) intact for retry; a delete clears `presented`.
  - Plus: `HighlightActionPopoverRequestBus.post` → `.request(from:)` round-trips the `ReaderHighlightTapEvent`; `.request(from:)` returns `nil` for a malformed `object`; `.cancelEditNote` only flips `isEditingNote` (does not dismiss); a fetch resolving `nil` (highlight concurrently deleted before the fetch) yields no presentation.
  - **Note normalization (F10):** `.saveNote` with `noteDraft == ""`, `"   "`, `"\n\n"` all reach `updateNote` with `nil`; `noteDraft == "  hi  "` reaches it with a non-`nil` value; multiline, CJK (`"メモ"`), and RTL (`"ملاحظة"`) drafts persist non-`nil` with interior content preserved.
- **`vreaderTests/Views/Reader/FoliateHighlightMutationDispatcherTests.swift`** (new, WI-5) — `dispatchRecolor(cfi:color:fingerprintKey:)` posts a `.foliateRequestAnnotationJSDelete` followed by a `.foliateRequestAnnotationJSCreate` for the same CFI, carrying the new `color` and the `fingerprintKey`; `dispatchDelete(cfi:fingerprintKey:)` posts exactly one `.foliateRequestAnnotationJSDelete` with the CFI + `fingerprintKey`; both return `false` and post nothing when `fingerprintKey` is empty or the CFI is empty/whitespace-only (mirrors `FoliateHighlightRestoreDispatcher`'s guard tests). Uses an injected `NotificationCenter` and an observer-spy.
- **`vreaderTests/Views/Reader/FoliateSpikeViewHighlightPopoverTests.swift`** (new, WI-5) — `FoliateHighlightTapHandlerModifier` posts `.readerHighlightActionRequested` (not `present(...)`) on an annotation-tap; the resolved `highlightID` is carried in the `ReaderHighlightTapEvent`.
- **Gate-5 verification UITest** — `vreaderUITests/Verification/Feature64HighlightPopoverVerificationTests.swift` (WI-6): open a seeded TXT fixture with a pre-created highlight → tap it → assert `highlightActionPopover` resolves → change color → add a note → reopen → assert the note card → delete. DebugBridge-drivable, CU-free.
- **Existing regression guards re-run every WI PR** — `HighlightCoordinatorTapHandlerTests`, `HighlightCoordinatorTests`, `HighlightIntegrationTests`, `ReaderHighlightTapEventTests`, `HighlightTapActionTests`, `EPUBHighlightTapBridgeTests`, `TXTBridgeHighlightTapTests`, `TXTBridgeHighlightTapSubscriberTests`, `TXTChunkedBridgeHighlightTapTests`, `PDFHighlightTapResolverTests`, `FoliateHighlightTapResolverTests`, `FoliateSpikeViewTapTests`, `FoliateHighlightRestoreDispatcherTests`, `HighlightPaintColorTests`, `PersistenceHighlightTests`, `TXTReaderContainerHighlightCoordinatorWiringTests`. These pin that the tap-*detection* half (feature #53), the Foliate restore path (Bug #207), and the colored-fill render path (Bug #208) are unbroken by the presentation swap. **Two existing tests change with the migration:** `TXTReaderContainerHighlightCoordinatorWiringTests.swift:117-121` asserts the literal string `highlightActionPresenter: UIKitHighlightActionPresenter()` is passed 3× in `TXTReaderContainerView` (Bug #202) — WI-4 updates it to assert the new presenter modifier instead; `UIKitHighlightActionPresenterTests.swift` is **deleted in WI-6** alongside `HighlightActionPresenter.swift`.

## 7. Risks + mitigations

- **R1 — the popover needs the highlight's content, the tap event carries only an ID.** Mitigation: WI-1 adds `fetchHighlight(highlightId:)`; the presenter fetches once at present time. The fetched `HighlightRecord` carries `anchor`, so the Foliate CFI comes for free. A `nil` fetch (highlight deleted between tap and present) shows nothing (§2.3, tested).
- **R2 — color change persists but the on-screen highlight does not visually update; EPUB re-render can misroute across a chapter-nav race.** Mitigation: WI-3's `changeColor` does `renderer.remove(id:)` + `restoreAll(forHref:)` after the persist, reusing the proven `handleRemoval` re-render shape, and **captures the EPUB href before the `await`** so a racing chapter nav cannot cross-wire the re-render (§2.1, F7 — the Bug-#103 pattern). The RED test asserts the captured href reaches `restore`. `restoreAll` is safe mid-session for TXT/MD/PDF; EPUB is made safe by the explicit `forHref:`. **For Foliate** (no coordinator) the recolor is the `FoliateHighlightMutationDispatcher.dispatchRecolor` delete-then-create CFI pair (§2.5, R2-F2), tested in `FoliateHighlightMutationDispatcherTests`.
- **R3 — `SelectionPopoverView` and `HighlightActionPopoverView` are both sheets; could both present at once.** A tap-on-highlight and a long-press-new-selection are mutually exclusive gestures on the same content, and the bridges post one notification or the other. Mitigation: WI-4's RED test confirms the highlight popover presents on `.readerHighlightActionRequested`; `SelectionPopoverPresenter` is unchanged. If a hard guarantee is wanted later, the two modifiers can share a dismiss — gesture exclusivity makes this likely unnecessary.
- **R4 — deleting `HighlightActionPresenter.swift` while a consumer remains breaks the build.** This is the F1/F2 finding. Mitigation: the six-WI sequence does **not** delete the file until **WI-6**, after **WI-5** has migrated Foliate (the fifth and last consumer). `FireOnceBox` has no consumer outside the file (verified) so it dies with the file; the `HighlightActionPresenting` *protocol* is removed in the same WI-6 step after every bridge call site is gone (F6).
- **R5 — note editor + sheet keyboard interaction.** A `TextEditor` inside a `.presentationDetents`-sized sheet can be clipped by the keyboard. Mitigation: WI-2 uses a detent set that accommodates the keyboard — `SelectionPopoverPresenter` uses `[.fraction(0.30), .medium]`; the highlight popover's editing state needs more room, so `.medium`/`.large`. The note editor is a designed state (jsx 702-731); this is layout tuning within the designed surface. Slice-verify keyboard behavior in WI-4's device pass.
- **R6 — `sourceRect` is unused by a sheet-based popover.** The feature-#53 `ReaderHighlightTapEvent.sourceRect` Bug-#203 coordinate-space contract was for `UIEditMenuConfiguration.sourcePoint`. A `.sheet` does not anchor to a rect. Mitigation: the event keeps `sourceRect` (other observers / future popover-anchoring may use it; removing it would be a gratuitous contract break) — the sheet presenter ignores it. Documented in WI-4.
- **R7 — per-bridge `onHighlightTapAction` removal scope.** Four primary bridges thread a `onHighlightTapAction` callback that #64 makes redundant (the presenter routes via `HighlightPopoverMutationRoute`). Mitigation: WI-4 removes the now-dead `highlightActionPresenter` + `onHighlightTapAction` tap-present properties from the four primary bridges + their coordinators; WI-5 does the same for Foliate (and removes the dead `performDelete`). `TXTBridgeHighlightTapSubscriberTests` asserts the bridge's *notification* behavior (not the callback), so it survives — its `FakePresenter` is dropped in WI-6.
- **R8 — stale async fetch / sheet re-open after rapid taps.** This is the F5 finding. Mitigation: WI-4's presenter uses a monotonic `requestSeq` token + a stored cancellable `fetchTask`; a completion whose token is stale, or whose task is cancelled, is dropped; a new request or a dismiss cancels the prior task. Dedicated RED test (§6).
- **R9 — the popover goes stale after a successful color/note mutation.** This is the F4 finding. Mitigation: WI-4's presenter rebuilds `presented` from the known-good mutated values (`HighlightRecord.with(color:)/.with(note:)`) **only on a `.success`** `changeColor`/`updateNote`; on `.failed` it leaves `presented` untouched (§2.3/F13); on `.notFound` it dismisses (R2-F1). Dedicated RED test (§6).
- **R10 — empty/whitespace note draft persisted as `""` corrupts the three-state model.** This is the F10 finding. Mitigation: §2.4 — the presenter trims and maps an empty result to `nil` before calling `updateNote`; tested for nil/`""`/whitespace-only/multiline/CJK/RTL.
- **R11 — Foliate `.zero` rect / flaky tap detection.** A detented sheet does not need the rect, so `.zero` is harmless (unlike the old `UIEditMenuInteraction`, which anchored to it). Foliate tap-detection itself is feature-#53-shipped and regression-guarded by `FoliateHighlightTapResolverTests` / `FoliateSpikeViewTapTests`. WI-5 slice-verifies on an AZW3 fixture.
- **R12 — the missing-row save/recolor cannot be distinguished from a transient failure (R2-F1).** v2's `Bool` return collapsed `PersistenceError.recordNotFound` and generic failures. Mitigation: WI-3's `changeColor`/`updateNote` return the typed `HighlightMutationOutcome` (`success`/`notFound`/`failed`) by pattern-matching `PersistenceError.recordNotFound` as a distinct `catch` clause; the presenter dismisses on `.notFound`, retains on `.failed`, refreshes on `.success`. Dedicated RED tests at both the coordinator (`HighlightCoordinatorTests`) and presenter (`HighlightActionPopoverPresenterTests`) layers (§6).
- **R13 — Foliate has no `HighlightRenderer`/`HighlightCoordinator`; v2's WI-5 did not compile (R2-F2/R2-F3).** Mitigation: v3's WI-5 is rewritten around the real CFI-notification architecture (§2.5). The new `FoliateHighlightMutationDispatcher` posts `.foliateRequestAnnotationJSDelete`/`.foliateRequestAnnotationJSCreate` (the existing `FoliateSpikeView.swift:280-317` observers consume them — no JS change); the presenter's `.foliate` route persists then dispatches; delete recovers the CFI from `HighlightRecord.anchor` and reproduces the shipped Bug-#199 `performDelete` notification pair bit-for-bit. The dispatcher is pure-logic and fully unit-tested (`FoliateHighlightMutationDispatcherTests`); WI-5 slice-verifies the live overlay repaint/clear on an AZW3 fixture.
- **R14 — the note editor's draft goes stale after a record swap / editor reopen (R2-F4).** v2's view-owned `@State` draft seeded once. Mitigation: v3 makes the draft parent-owned; `HighlightActionPopoverView` is a controlled component (`noteDraft` + `onDraftChange`, no `@State`), and the presenter re-seeds `noteDraft` on every record swap, every `.beginEditNote`, and every successful save (§3 R2-F4). Dedicated RED tests in `HighlightActionPopoverViewTests` (the editor renders the injected draft, typing reports via `onDraftChange`) and `HighlightActionPopoverPresenterTests` (re-seed on swap / editor open / save).

## 8. Backward compatibility

- **No schema change, no SwiftData migration.** `HighlightRecord` already has `note`, `color`, `createdAt`, `anchor` (`:20,:19,:21` + the `anchor` field); `Highlight` (`@Model`) already has `note: String?`, `color: String`, `createdAt: Date`. #64 reads and writes existing columns. Existing highlights — including legacy ones with `note == nil` or a non-named legacy color string — render correctly: the no-note popover state handles `nil`, and `NamedHighlightColor.from(storageString:)` returning `nil` for a legacy hex falls back to yellow in `HighlightPaintColor` (the established Bug-#208 behavior). A legacy-colored highlight tapped in the new popover shows no swatch as "selected" (none of the four match) — acceptable and consistent with `SelectionPopoverView`'s handling; the user can pick a named color to normalize it. The `HighlightRecord.with(color:)/.with(note:)` value-copy helper is a file-private extension on the *value type* — not a stored property, not a schema field.
- **No serialized-format change.** Color stays a raw `String` (`NamedHighlightColor.swift` header pins this). Backups and `ExportedAnnotation` are unaffected.
- **Notification surface is additive.** `.readerHighlightActionRequested` is a new name; `.readerHighlightTapped` is unchanged and still posted by every bridge (any other observer keeps working). `.readerHighlightRemoved` (the delete-render path) is unchanged. **`.foliateRequestAnnotationJSCreate` and `.foliateRequestAnnotationJSDelete` (`ReaderNotifications.swift:115`) are reused as-is** — WI-5's `FoliateHighlightMutationDispatcher` posts into them; the existing `FoliateSpikeView.swift:280-317` observers and `FoliateHighlightRestoreDispatcher` are untouched. No notification name is renamed or removed.
- **`HighlightPersisting.fetchHighlight` is an additive protocol method** — but it is a *requirement*, so **all six conformers** are updated in WI-1 (§3 F3). No external (out-of-repo) conformer exists.
- **`HighlightCoordinator.changeColor`/`.updateNote` return `HighlightMutationOutcome`** — these are *new* methods (no prior caller), so the typed return is not a breaking change to any existing call site. The pre-existing `handleTapAction`/`create`/`restoreAll`/`handleRemoval` signatures are unchanged.
- **Deleted code (`HighlightActionPresenter.swift`, `UIKitHighlightActionPresenterTests.swift`) — in WI-6, after Foliate is migrated.** `HighlightActionPresenting` / `UIKitHighlightActionPresenter` / `FireOnceBox` are removed; `HighlightTapAction` **stays** (still used by `HighlightCoordinator.handleTapAction` and the new presenter for the delete action). `project.yml` is folder-glob-based, so `xcodegen generate` (WI-6's version-bump step) regenerates `project.pbxproj` without the deleted files; WI-6 confirms the `pbxproj` diff before committing. **The deletion is sequenced last on purpose (F1/F2): every one of the five wired consumers — four primary bridges (WI-4) and Foliate (WI-5) — is migrated off the protocol before the protocol and its sole implementation are removed, so no intermediate WI ever leaves the build red or regresses shipped behavior.**
- **The shipped Foliate delete behavior is preserved bit-for-bit (R2-F3).** Before #64, a Foliate highlight delete posts `.readerHighlightRemoved` + `.foliateRequestAnnotationJSDelete` (`FoliateSpikeView+HighlightTap.performDelete`). After WI-5, the popover's Foliate delete path posts the *same* pair via `FoliateHighlightMutationDispatcher.dispatchDelete`. The old `performDelete` method is removed only because its caller (the old `present`-completion closure) is removed — the *behavior* it encoded moves into the dispatcher, it is not dropped.
- **User-visible behavior change is intentional and is the feature.** Pre-#64: tapping a highlight shows a bare one-item native menu. Post-#64: it shows the styled card. The delete action's *outcome* is identical (TXT/MD/EPUB/PDF: the same `handleTapAction(.delete)` path; Foliate: the same `.readerHighlightRemoved` + `.foliateRequestAnnotationJSDelete` pair); color-change and note-edit are *new* capabilities surfaced by the design. **During the migration window (after WI-4, before WI-5 ships), AZW3/MOBI still shows the old bare menu while TXT/MD/EPUB/PDF show the new card — an intentional, temporary per-format split; each WI PR is independently shippable and regression-free.** No data written by an older app version is invalidated.
- **a11y identifiers** — the new popover ships `highlightActionPopover` + per-row ids (`highlightPopoverNote` / `…Copy` / `…Share` / `…Delete` / `highlightPopoverClose` / `highlightPopoverColor-<name>`), mirroring the `selectionPopover*` id scheme so the verify-cron and XCUITest harnesses can drive it. The deleted `UIKitHighlightActionPresenter.deleteItemTitle` ("Delete Highlight") string is no longer an observable surface; any harness asserting it is updated in WI-6.

---

### Critical Files for Implementation

- /Users/ll/workspace/vreader/vreader/Views/Reader/HighlightCoordinator.swift
- /Users/ll/workspace/vreader/vreader/Views/Reader/FoliateSpikeView.swift
- /Users/ll/workspace/vreader/vreader/Views/Reader/FoliateSpikeView+HighlightTap.swift
- /Users/ll/workspace/vreader/vreader/Views/Reader/FoliateHighlightRestoreDispatcher.swift
- /Users/ll/workspace/vreader/vreader/Services/PersistenceActor+Highlights.swift
