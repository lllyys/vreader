# Feature #55 — Tap on annotated text → view note content inline — implementation plan

- **Feature row**: `docs/features.md` #55 (TODO → PLANNED on Gate-2 clean)
- **GH issue**: #619 (already mirrored)
- **Design source** (committed, rule 51 satisfied):
  `dev-docs/designs/vreader-fidelity-v1/project/vreader-note-preview.jsx` —
  delivered 2026-05-18, resolves `needs-design` #865. Two presenter forms:
  - **`NoteCallout`** (canonical) — an anchored card floating above (or
    below) the tapped passage with a pointer notch: a meta row (color
    swatch + "Note" + date + dismiss ×), a 1-line italic excerpt of the
    highlighted passage, the **note body as the hero** (serif, scrollable
    to `maxHeight: 180`), and an edit-handoff row (Edit / Share / Open in
    panel) when a note exists.
  - **`NotePreviewSheet`** (fallback) — a bottom-anchored short sheet for
    very long notes / the VoiceOver path; same content with more room.
  - Plus the **empty / no-note state** ("No note attached. Add one…") — the
    issue spec requires it, and it is depicted in the design.
- **Author**: feature-cron (Gate 1), 2026-05-19
- **Status**: v4 — Gate-2 audit **CLEAN after 3 rounds** (Codex thread
  `019e3e14`). Audit findings + resolutions are in §11; revision history in
  §10. Feature #55 row → `PLANNED`.
- **Lineage**: triage 2026-05-18; distinct from feature #53 (inline
  *delete* action menu for highlights) and feature #60's
  `SelectionPopover` (long-press *selection* surface). #55 is a third,
  separate hit-test → a read-the-note *preview* surface.

## 1. Problem

When a reader adds a note to highlighted text, tapping that annotated
region in the reader **does nothing inline**. The note body is only
reachable via the Annotations panel. There is no tap-to-preview affordance
— the natural "what did I write here?" gesture has no result.

The codebase already has most of the wiring this needs, which sharpens the
problem statement:

- **`.readerHighlightTapped`** (a `Notification.Name` in
  `ReaderNotifications.swift`) **already fires from all five reader formats**
  on a tap inside a highlighted/annotated region — verified at Gate-2
  round 1:
  - **TXT** — `TXTTextViewBridgeCoordinator` (`handleContentTap` →
    `resolveHighlightTap` → posts `.readerHighlightTapped`).
  - **TXT-chunked** — `TXTChunkedReaderBridge` (same pattern).
  - **MD** — uses the TXT text path.
  - **EPUB** — `EPUBWebViewBridgeCoordinator.handleHighlightTapMessage`.
  - **Foliate / AZW3** — `FoliateHighlightTapHandlerModifier` in
    `FoliateSpikeView+HighlightTap.swift` (the **live** AZW3/MOBI path —
    see §2.0 fact 1; the dormant `FoliateReaderContainerView+Highlights.handleAnnotationShow`
    is NOT the production path).
  - **PDF** — `PDFViewBridge.handleTap`.
  Its payload is a `ReaderHighlightTapEvent { highlightID: UUID,
  sourceRect: CGRect }`.
- **`HighlightRecord`** already carries a `note: String?` field.
- What that event currently drives is **feature #53's `HighlightActionPresenter`**
  — a `UIEditMenuInteraction` action menu that is **delete-only today**
  (`HighlightTapAction` has only `.delete`; `HighlightCoordinator.handleTapAction`
  only deletes — §2.0 fact 3). There is **no note-body display path**:
  tapping an annotated highlight, today, either shows the Delete menu (where
  wired) or nothing.

So #55 is **not** "add tap detection" (it exists) — it is "add a
note-preview *presenter* that consumes the already-firing
`.readerHighlightTapped` event, looks up the tapped highlight's `note`, and
shows the designed `NoteCallout` / `NotePreviewSheet`."

## 2. Surface area

All paths/types confirmed by codebase read (2026-05-19) and re-verified
against the Gate-2 round-1 audit.

### 2.0 — Round-1 audit corrections (this plan is built on these facts)

The Gate-2 round-1 audit corrected four model assumptions; v2 incorporates
them (full detail in §11):

1. **The live AZW3/MOBI path is `FoliateSpikeView` + `FoliateSpikeView+HighlightTap.swift`.**
   `ReaderContainerView` dispatches `.foliateWeb` directly to
   `FoliateSpikeView`. Tap handling is `FoliateHighlightTapHandlerModifier`
   (in `FoliateSpikeView+HighlightTap.swift`) — it posts `.readerHighlightTapped`
   and, when a presenter is wired, calls `presenter.present(...)`. The
   `FoliateReaderContainerView+Highlights.handleAnnotationShow(cfi:)` the v1
   plan named is **dormant / not the production path**. All Foliate
   references in v2 target `FoliateSpikeView` + `FoliateSpikeView+HighlightTap.swift`.
2. **There is no existing highlight-note editor sheet.** `AnnotationEditSheet`
   edits `AnnotationRecord.content` (used only from `AnnotationListView`) —
   it is **not** a highlight-note editor. The real highlight-note edit path
   is `HighlightPersisting.updateHighlightNote(highlightId:note:)` (used by
   `HighlightListViewModel.updateNote`). v2's Edit handoff (§2.8) targets
   `updateHighlightNote`, not `AnnotationEditSheet`.
3. **Feature #53 is delete-only.** `HighlightTapAction` has only `.delete`;
   `HighlightCoordinator.handleTapAction` only deletes; Foliate's delete
   bypasses `HighlightCoordinator` entirely (hard-coded in
   `FoliateHighlightTapHandlerModifier.performDelete`). v2's de-conflict
   (§2.7) is written against this reality — #53 is a *delete* surface, not
   "edit/delete".
4. **`.readerOpenNotes` opens the panel's `.highlights` tab**, not the Notes
   tab. `ReaderContainerView` sets `annotationsPanelInitialTab = .highlights`
   for `.readerOpenNotes`. (`AnnotationsPanelTab.annotations` is the tab
   *labeled* "Notes".) v2's "Open in panel" handoff (§2.8) is described
   accurately.

### 2.1 — New value type: `NotePreviewContent`

**New file** `vreader/Views/Reader/NotePreviewContent.swift` (~50 LOC).

```swift
/// The data a note-preview surface renders. Derived from the tapped
/// HighlightRecord; a value type so it can drive a SwiftUI presentation
/// without holding the @Model.
struct NotePreviewContent: Identifiable, Equatable, Sendable {
    let id: UUID                 // == the highlight's id
    let note: String?            // nil / empty ⇒ the empty/no-note state
    let highlightedText: String  // the 1-line italic excerpt
    let colorName: String        // the stored highlight color name (§2.1.1)
    let createdAt: Date          // the "· <date>" meta
    let sourceRect: CGRect       // anchor rect, view-local (from the tap event)

    /// True when there is no note body — drives the design's empty state.
    var isEmpty: Bool { (note ?? "").trimmingCharacters(in: .whitespaces).isEmpty }
}
```

`Sendable` — `CGRect` is `Sendable` in the current SDK, so the struct is
clean. (`ReaderHighlightTapEvent` is itself already `Sendable`, verified.)

#### 2.1.1 — Color mapping uses the real stored palette

Round-1 finding [7]: the design's `NoteCallout` maps four colors
(`yellow/pink/green/blue`), but stored highlights use a broader palette —
`HighlightListView` already renders `yellow/green/blue/red/orange/purple`.
v2 decision: the swatch-color mapper in `NoteCalloutView` (§2.5) is built
against the **real stored highlight palette**, reusing the existing
highlight-color → `UIColor`/`Color` mapping the codebase already has
(`HighlightPaintColor` / the `HighlightListView` swatch logic) rather than
the design's 4-color subset. A stored color the design did not depict
(`red`/`orange`/`purple`) still gets its correct swatch. This is a
faithful-to-data extension, not an invented UI element — the *surface* (a
small color swatch in the meta row) is in the design; only the color set is
widened to match what users actually have.

### 2.2 — New view model: `NotePreviewViewModel`

**New file** `vreader/ViewModels/NotePreviewViewModel.swift` (~110 LOC).

`@Observable @MainActor` (codebase convention for reader-side view models).
Owns present/dismiss state and performs the persistence lookup:

```swift
@Observable @MainActor
final class NotePreviewViewModel {
    private(set) var presented: NotePreviewContent?

    private let persistence: HighlightLookup   // protocol — see §2.3
    private let bookFingerprintKey: String

    /// Monotonic tap token — guards out-of-order async lookups (§2.2.1).
    private var latestTapToken: UInt64 = 0

    init(persistence: HighlightLookup, bookFingerprintKey: String)

    func handleTap(_ event: ReaderHighlightTapEvent) async
    func dismiss()
}
```

#### 2.2.1 — Out-of-order lookup guard (round-1 finding [5])

`handleTap` is `async` and crosses the `PersistenceActor` boundary. Two
rapid taps can have their lookups complete out of order, letting an older
tap's result overwrite a newer tap's. v2 fix: `handleTap` increments
`latestTapToken`, captures it in a local, and **only publishes `presented`
if the captured token still equals `latestTapToken`** after the `await`
returns. (A monotonic token, not task cancellation — simpler, and a
cancelled `PersistenceActor` read is not guaranteed mid-flight.)

```swift
func handleTap(_ event: ReaderHighlightTapEvent) async {
    latestTapToken &+= 1
    let myToken = latestTapToken
    let record = try? await persistence.highlight(
        withID: event.highlightID, forBookWithKey: bookFingerprintKey
    )
    guard myToken == latestTapToken else { return }   // a newer tap won
    guard let record else { presented = nil; return } // deleted-race no-op
    presented = NotePreviewPresenter.content(for: record, sourceRect: event.sourceRect)
}
```

`dismiss()` sets `presented = nil` (and is itself counted by bumping the
token so an in-flight lookup after a dismiss does not resurrect a card).

### 2.3 — New protocol: `HighlightLookup`

**New file** `vreader/Services/HighlightLookup.swift` (~20 LOC).

A narrow read-only protocol at the persistence boundary so
`NotePreviewViewModel` is unit-testable with a mock (codebase convention —
`LibraryPersisting`, `HighlightPersisting`):

```swift
protocol HighlightLookup: Sendable {
    /// Fetches a single highlight by id, or nil if it does not exist.
    func highlight(withID id: UUID, forBookWithKey key: String) async throws -> HighlightRecord?
}
```

Keyed by `(id, bookKey)` so a lookup is scoped to the open book and cannot
leak a highlight from another book. The shape does not leak persistence
concerns — it returns the existing `HighlightRecord` value type and takes
the same `(UUID, String)` identifiers the rest of the highlight API uses.

### 2.4 — `PersistenceActor` — single-highlight lookup

**Modified file** `vreader/Services/PersistenceActor+Highlights.swift`.

Today this extension has `fetchHighlights(forBookWithKey:)` (verified — it
returns the whole book's highlights; there is **no** single-highlight fetch
yet). Add:

```swift
func highlight(withID id: UUID, forBookWithKey key: String) async throws -> HighlightRecord?
```

Implementation: a SwiftData `FetchDescriptor<Highlight>` with a predicate on
the highlight's UUID **and** the owning book's `fingerprintKey`, mapped to
`HighlightRecord` via the existing record-mapping helper this file already
uses for `fetchHighlights`. Returns `nil` on no match. `PersistenceActor`
declares `HighlightLookup` conformance (the method signature matches).

**Decision (§6 R-1)**: a dedicated single-fetch (vs. `fetchHighlights` + a
client-side `first(where:)`) is correct — the note-preview path fires on
every annotated-text tap and must not page the whole book's highlight set
into memory each time.

### 2.5 — New view: `NoteCalloutView`

**New file** `vreader/Views/Reader/NoteCalloutView.swift` (~200 LOC — split
if it grows past ~250).

The SwiftUI realization of the design's `NoteCallout`. Renders, from a
`NotePreviewContent`: the meta row (color swatch from §2.1.1, uppercase
"NOTE"/"HIGHLIGHT" label, "· <date>", circular dismiss ×); the 1-line
italic serif excerpt of `highlightedText` with the color-tinted left rule;
the **note body** as the hero (`Source Serif 4` via `ReaderTypography` —
verified that `AISummaryTabView`/`SelectionPopoverView` use it — scrollable,
capped at the design's `maxHeight: 180`); the empty/no-note state when
`content.isEmpty`; the handoff row when a note exists.

**Handoff row — v1 ships Share + Open-in-panel only.** The design's
`CalloutAction` row depicts Edit / Share / Open-in-panel. v1 renders
**Share** and **Open-in-panel** (both designed, both reachable with no new
UI). **Edit is omitted** — it is a `BLOCKED: needs-design` slice (§2.8) —
and **Delete is not added** (it was never in the design — §2.7.2, round-2
finding [9]). So v1's handoff row is a strict subset of the depicted row:
it shows only actions the design depicts and that need no invented UI.
(Rendering a depicted 3-button row with 2 of its buttons is *narrower* than
the design, which rule 51 permits — it is not an invented surface.)

**Theming**: takes a `ReaderThemeV2` (verified — the v2 token type
`AISummaryTabView` / `AIReaderPanel` / `SelectionPopoverView` already
consume). Light/dark parity falls out of the token set.

### 2.6 — New view: `NotePreviewSheetView`

**New file** `vreader/Views/Reader/NotePreviewSheetView.swift` (~110 LOC).

The SwiftUI realization of the design's `NotePreviewSheet` — the
bottom-anchored fallback for **very long notes**, the **VoiceOver path**,
and **Foliate** (no `sourceRect`, §2.9). Same `NotePreviewContent` input;
presented via `.sheet` with a short detent. Content: the excerpt and the
note body at the larger sheet type size. The design's sheet footer has a
**Done** + **Edit note** pair; v1 ships **Done** only (Edit is the
`BLOCKED: needs-design` slice, §2.8) — again a strict subset of the
depicted footer, no invented UI.

### 2.7 — The presenter: `NotePreviewPresenter` + `NotePreviewModifier` + a UIKit anchor

**New file** `vreader/Views/Reader/NotePreviewPresenter.swift`.

`NotePreviewPresenter` (enum) — the pure parse/build boundary:

```swift
enum NotePreviewPresenter {
    /// Builds the preview content for a tapped highlight. Pure.
    static func content(for record: HighlightRecord, sourceRect: CGRect) -> NotePreviewContent

    /// Pure decision: anchored callout vs bottom sheet. See §2.7.1.
    static func form(
        for content: NotePreviewContent, isVoiceOverRunning: Bool, noteLineCount: Int
    ) -> NotePreviewForm   // enum { callout, sheet }
}
```

#### 2.7.1 — Anchoring the callout (round-1 finding [4])

Round-1 finding [4]: the v1 plan asserted a SwiftUI `.popover(item:)` would
anchor "for free" from `event.sourceRect`, but the codebase has **no
rect-to-popover anchor infrastructure** and the only presenter precedent
(`SelectionPopoverPresenter`) is sheet-based — `.popover` anchors to a
SwiftUI *view*, not a raw `CGRect`. v2 resolves this with an explicit
mechanism, not a hand-wave:

> The anchored callout is presented by a **UIKit presenter** —
> `UIKitNotePreviewPresenter` — that anchors a `UIViewController`
> (hosting `NoteCalloutView` via `UIHostingController`) as a
> `.popover`-style `modalPresentationStyle` whose
> `popoverPresentationController.sourceView` is the reader's content
> `UIView` and whose `sourceRect` is `event.sourceRect`. This is the
> standard, supported UIKit path for "anchor a popover to an arbitrary
> rect in a view" — `UIPopoverPresentationController` gives the pointer
> arrow, auto-flip when there is no room, and outside-tap dismiss. The
> `event.sourceRect` contract (view-local rect in the host view) is
> exactly what `sourceRect` wants.

This mirrors **feature #53's `UIKitHighlightActionPresenter`** — which
already anchors a `UIEditMenuInteraction` to `event.sourceRect.midX/midY`
in a host `UIView`. #55's presenter is the same shape (a UIKit presenter,
protocol-injected for test isolation, anchored to the same `sourceRect`),
just presenting a hosted SwiftUI card instead of an edit menu:

```swift
@MainActor
protocol NotePreviewPresenting: AnyObject {
    /// Presents the anchored note callout for `content` at
    /// `content.sourceRect` in `view`. The v1 callout has two handoff
    /// actions — `onOpenPanel` and `onShare` (Edit is the BLOCKED:
    /// needs-design slice, §2.8 — not in the v1 surface).
    func presentCallout(
        _ content: NotePreviewContent, theme: ReaderThemeV2, in view: UIView,
        onOpenPanel: @escaping (UUID) -> Void,
        onShare: @escaping (NotePreviewContent) -> Void,
        onDismiss: @escaping () -> Void
    )
}
```

The **bottom-sheet** form (`NotePreviewSheetView`) is presented the SwiftUI
way — `NotePreviewModifier` drives a `.sheet(item:)` off
`NotePreviewViewModel.presented` when `form(...) == .sheet`. So: callout =
UIKit popover anchored to the rect; sheet = SwiftUI `.sheet`. Both forms,
two mechanisms, each matched to what it needs.

`NotePreviewModifier` (a `ViewModifier`, same file — mirrors
`SelectionPopoverPresenterModifier` living in `SelectionPopoverPresenter.swift`)
observes `.readerHighlightTapped`, drives `NotePreviewViewModel.handleTap`,
and routes `presented` to either the UIKit callout presenter or the SwiftUI
sheet per `NotePreviewPresenter.form(...)`.

#### 2.7.2 — Coexistence with feature #53's delete menu (round-1 finding [3]; central risk R-2)

Both #53's delete menu and #55's note preview observe the same
`.readerHighlightTapped` event. They must not both fire on one tap.
Round-1 finding [3] corrected the framing: **#53 is delete-ONLY today**
(`HighlightTapAction.delete` is the only case), and **Foliate's delete
bypasses `HighlightCoordinator`** (hard-coded in
`FoliateHighlightTapHandlerModifier.performDelete`). v2's de-conflict,
written against that reality:

> Today a tap on an annotated highlight opens a **delete menu** in
> TXT/MD/EPUB/PDF (via `UIKitHighlightActionPresenter`) and a
> **Foliate-specific delete flow** in AZW3/MOBI (via
> `FoliateHighlightTapHandlerModifier`). **#55 replaces that tap
> behavior**: a single tap → the #55 note preview.

Where delete goes after the change — **v4 decision (rule-51-compliant +
honest per-format scope)**:

Round-2 finding [9] established that adding a **Delete** button to the
callout's action row is *self-designed UI* — the committed
`vreader-note-preview.jsx` `CalloutAction` row depicts **only** Edit /
Share / Open-in-panel; Delete is not in the bundle. Rule 51 forbids
inventing it. So #55 does **not** add Delete to the callout.

Round-3 finding [10] then established that "re-home #53 onto long-press on
**all five** formats" is not uniformly feasible: TXT/MD/PDF can add a native
`UILongPressGestureRecognizer` and reuse their existing highlight hit-test
helpers, but **EPUB** highlight taps arrive from a **JS `highlightTapHandler`
message** (no native long-press recognizer for an EPUB highlight), and
**Foliate** highlight taps likewise arrive from a JS event. So v4 narrows
the guarantee to what is real:

- **All five formats** — a **single tap** on an annotated highlight → the
  **#55 note preview** (the designed surface). This is the feature; it ships
  everywhere. The bridges already post `.readerHighlightTapped` on a tap; #55
  consumes it.
- **Native formats (TXT / MD / PDF)** — #53's existing delete menu is
  **re-homed from the tap gesture to a native long-press gesture**. #53's
  `UIEditMenuInteraction` is iOS menu chrome (out of rule-51 scope) and is
  unchanged — same presenter, same `HighlightTapAction.delete`, same
  `HighlightCoordinator.handleTapAction`; only the triggering gesture moves.
  These hosts can add a `UILongPressGestureRecognizer` and reuse the
  highlight hit-test helper their tap path already uses. Nothing
  user-visible is invented.
- **EPUB and Foliate** — there is **no native long-press recognizer for a
  web-rendered highlight**, and adding a JS long-press → menu path is its
  own slice. For v1, **EPUB/Foliate highlight deletion remains reachable via
  the already-shipped Annotations panel** (the **Highlights tab**'s
  swipe-to-delete — `HighlightListView`, which ships today). The callout's
  **Open-in-panel** action is the in-reader route to it. This is honest: a
  tap on an EPUB/Foliate highlight shows the #55 preview; deleting that
  highlight is one tap away via Open-in-panel → swipe-delete. **No EPUB/JS
  or Foliate/JS change, no new UI.**
- A **native EPUB/Foliate long-press → #53 menu** (a JS long-press event
  source feeding the existing presenter) is a clean **follow-up** — recorded
  in §9. It is not required for #55's acceptance criteria (a/b/c are about
  the *preview*, not delete).

Concretely:

- **WI-6 (native, TXT/MD/PDF)**: each native bridge/coordinator stops
  calling `HighlightActionPresenter.present(...)` from the *tap* handler and
  calls it from a *long-press* handler instead; the tap posts
  `.readerHighlightTapped` (already does) which `NotePreviewModifier`
  consumes. Acceptance: preview on tap; #53 delete menu on long-press.
- **WI-7 (EPUB + Foliate)**: each removes the *tap-time*
  `HighlightActionPresenter.present(...)` call (`EPUBWebViewBridgeCoordinator.handleHighlightTapMessage`,
  `FoliateHighlightTapHandlerModifier`) so the tap is owned by #55's
  preview. #53's tap-time menu is **dropped** on EPUB/Foliate for v1 — its
  delete capability is preserved by the panel swipe-delete (above), not by a
  long-press. Acceptance: preview on tap; highlight delete still reachable
  via Open-in-panel → Highlights-tab swipe-delete.

The auditor must confirm: tap→preview ships on all five formats; the #53
long-press menu is correctly scoped to TXT/MD/PDF; and EPUB/Foliate delete
is genuinely reachable via the panel in v1.

### 2.8 — Edit + Open-in-panel handoffs (round-1 findings [1], [6]; round-2 finding [9])

**Edit handoff** — round-1 finding [1] established that `AnnotationEditSheet`
is NOT the highlight-note editor (it edits `AnnotationRecord.content`); the
real path is `HighlightPersisting.updateHighlightNote(highlightId:note:)`.
Round-2 finding [9] then established that a *new* `HighlightNoteEditSheet`
is itself a user-visible surface NOT in the committed design bundle — rule
51 forbids inventing it.

**v3 decision (rule-51-compliant default path)**: the design's `NoteCallout`
*does* depict an **Edit** action and even an inline `editing` textarea
state — but #55's v1 ships the **read-only preview only**. The Edit action
on the callout's handoff row is a **design-blocked slice**:

- The **default #55 deliverable is the read-only note preview** — tap →
  see the note body (`NoteCallout` / `NotePreviewSheet`), the empty/no-note
  state, dismiss. This is fully designed and ships without any invented UI.
- The callout's **Edit** action and the inline `editing` state are **NOT
  built in v1**. The design depicts an Edit button, but the *editor surface
  it opens* (whether the inline textarea or a separate sheet) is not a
  committed, buildable design for #55 — and `HighlightNoteEditSheet` would
  be self-designed. Per rule 51, this slice is **`BLOCKED: needs-design`**:
  a `needs-design` GitHub issue is filed (title `Design needed:
  highlight-note edit surface for feature #55`, labels `enhancement` +
  `needs-design`), and the Edit action is **omitted from the v1 callout**
  (the callout renders the meta row, excerpt, note body, empty state, and
  the **Share** + **Open-in-panel** handoff actions — all of which the
  design depicts and none of which need new UI).
- Note editing is **not lost** — the existing Annotations-panel Highlights
  tab already edits highlight notes (`HighlightListView` →
  `HighlightListViewModel.updateNote` → `updateHighlightNote`). The
  callout's **Open-in-panel** action routes there.
- When the user delivers the edit-surface design through `claude.ai/design`
  and it lands under `dev-docs/designs/`, a **follow-up WI** adds the Edit
  action + the designed editor. #55's row is NOT itself blocked — only the
  Edit slice is; the read-only preview (the feature's stated acceptance
  criteria a/b/c) ships in full.

**Open-in-panel handoff** — round-1 finding [6]: `.readerOpenNotes` opens
the panel's **`.highlights`** tab (`ReaderContainerView` sets
`annotationsPanelInitialTab = .highlights`). v3 text is correct: the
callout's "Open in panel" posts `.readerOpenNotes`, opening the Annotations
panel on the **Highlights** tab — existing behavior, no new UI. (Deep-linking
the panel to scroll to the tapped highlight is out of scope — a follow-up,
§9.)

### 2.9 — Container wiring (all five formats)

Each format's container attaches `NotePreviewModifier` and constructs a
`NotePreviewViewModel`:

- **TXT** — `TXTReaderContainerView.swift`.
- **MD** — `MDReaderContainerView.swift`.
- **EPUB** — `EPUBReaderContainerView.swift`.
- **Foliate / AZW3** — `FoliateSpikeView.swift` + `FoliateSpikeView+HighlightTap.swift`
  (the live path — §2.0 fact 1).
- **PDF** — `PDFReaderContainerView.swift`.

Each already has `modelContext` / a `modelContainer` + the book's
`fingerprintKey` in scope (they construct `UIKitHighlightActionPresenter()`
for #53 today). `NotePreviewModifier` attaches at the same layer.

**Per-format `sourceRect`**: TXT/MD/EPUB/PDF emit a real view-local rect.
**Foliate emits `sourceRect == .zero`** (`FoliateHighlightTapHandlerModifier`
posts the event with `.zero` because the foliate-host.js bridge does not
forward the annotation screen-rect). v2 decision (§6 R-5): when `sourceRect
== .zero`, `NotePreviewPresenter.form(...)` returns `.sheet` — the bottom
sheet needs no anchor. Foliate/AZW3 gets the note preview via the sheet
form until foliate-host.js rect-forwarding lands (deferred, §9).

### 2.10 — Files OUT of scope

- **`HighlightActionPresenter.swift` / `HighlightTapAction.swift` /
  `HighlightCoordinator.swift`** — #55 does not modify #53's presenter,
  its action enum, or its delete logic. It only **re-homes the call to
  `HighlightActionPresenter.present(...)` from the tap gesture to a
  long-press gesture** in the bridges/modifiers (§2.7.2, WI-6/WI-7); the
  presenter itself, `HighlightTapAction`, and `HighlightCoordinator` are
  untouched.
- **`AnnotationEditSheet.swift`** — NOT reused (round-1 finding [1]); it
  edits `AnnotationRecord`, not highlight notes. #55 v1 also does **not**
  add a new highlight-note edit sheet — the Edit slice is `BLOCKED:
  needs-design` (§2.8).
- **`foliate-host.js` / the Foliate-js bundle** — no JS change. The Foliate
  `sourceRect`-forwarding is deferred (§9); v1 uses the sheet fallback.
- **`SelectionPopoverView.swift` / `SelectionPopoverPresenter.swift`** —
  feature #60's long-press *selection* surface; a different gesture. #55
  mirrors its *pattern* (a typed enum + a modifier) but shares no code.
- **`AnnotationsPanelView.swift` / `HighlightListView.swift` /
  `HighlightListViewModel.swift`** — the panel is the existing access path;
  #55 adds the *inline* path. The callout's "Open in panel" uses the
  existing `.readerOpenNotes` notification. (`HighlightListViewModel` is
  *referenced* as the precedent for `updateHighlightNote` usage, not
  modified.)
- **Schema / `Highlight` `@Model` / `AnnotationNote`** — no persistence
  change; `HighlightRecord.note` already exists.

## 3. Prior art / project precedent / rejected alternatives

**Project precedent followed:**

- **`UIKitHighlightActionPresenter`** (feature #53) — the established
  pattern for "anchor a UIKit presentation to `ReaderHighlightTapEvent.sourceRect`
  in a host `UIView`, protocol-injected for test isolation".
  `UIKitNotePreviewPresenter` (§2.7.1) is the same shape — a UIKit
  presenter anchored to the same `sourceRect`, hosting a SwiftUI card.
- **`SelectionPopoverPresenter` / `SelectionPopoverPresenterModifier`**
  (feature #60 WI-7c1) — "a reader bridge posts a notification; a SwiftUI
  `ViewModifier` observes it; a small typed enum keeps the wire format
  local + unit-testable". `NotePreviewPresenter` + `NotePreviewModifier`
  follow it (for the sheet form; the callout form uses the #53-style UIKit
  presenter).
- **`.readerHighlightTapped` + `ReaderHighlightTapEvent`** (feature #53) —
  the cross-format tap event #55 consumes. #55 is the *second consumer* of
  an event #53 established and that fires from all five formats.
- **`HighlightLookup` as a narrow persistence protocol** — mirrors
  `LibraryPersisting` / `HighlightPersisting`.
- **`ReaderThemeV2` + `ReaderTypography` serif body** — exactly how
  `AISummaryTabView` / `SelectionPopoverView` realize the v2 tokens.
- **The existing Annotations-panel Highlights tab** (`HighlightListView` →
  `HighlightListViewModel.updateNote` → `HighlightPersisting.updateHighlightNote`)
  — the already-shipped highlight-note editor. #55's callout routes to it
  via "Open in panel" rather than forking a new editor; the designed
  in-callout editor is a `needs-design`-gated follow-up (§2.8).

**Industry prior art:**

- Apple Books / Kindle iOS: tapping highlighted text shows a small inline
  bubble; if the highlight has a note, the note text is the bubble's hero,
  with edit/delete one level deeper (long-press / a secondary affordance).
  The design's `NoteCallout` (note-as-hero) matches this; the v3
  tap→preview / long-press→#53-delete-menu split (§2.7.2) is the same UX
  hierarchy — destructive/edit actions sit behind a deliberate gesture, not
  on the casual tap.

**Rejected alternatives:**

1. **SwiftUI `.popover(item:)` anchored "for free" from `sourceRect`** —
   rejected (round-1 finding [4]). `.popover` anchors to a SwiftUI *view*,
   not a raw `CGRect`; the codebase has no rect-to-popover plumbing. v2 uses
   a `UIPopoverPresentationController`-based UIKit presenter — the supported
   path for "anchor to an arbitrary rect", and the exact mechanism family
   #53 already uses.
2. **Add a new `Notification.Name` for the note-preview tap** — rejected.
   `.readerHighlightTapped` already fires from every format with the exact
   payload needed.
3. **Make #55 a new `HighlightTapAction` case in #53's menu** — rejected.
   #53's presenter is a `UIEditMenuInteraction` *menu*; a note *preview
   card* is content, a different surface + lifecycle.
4. **Reuse `AnnotationEditSheet` for an Edit handoff** — rejected (round-1
   finding [1]); it edits `AnnotationRecord.content`, not
   `HighlightRecord.note`.
5. **Build a new `HighlightNoteEditSheet` for the Edit handoff in v1** —
   rejected (round-2 finding [9]). A new edit sheet is a user-visible
   surface not in the committed design bundle — rule 51 forbids inventing
   it. v1 ships the read-only preview; the Edit slice is `BLOCKED:
   needs-design` (§2.8). Note editing stays reachable via the panel.
6. **Add a Delete button to the callout's handoff row** — rejected (round-2
   finding [9]). The design's `CalloutAction` row depicts only Edit / Share
   / Open-in-panel; a Delete button is self-designed UI. v3 instead re-homes
   #53's existing delete menu onto a long-press gesture (§2.7.2) — no new UI.
7. **Drop the bottom-sheet form, callout only** — rejected. The design
   *requires* `NotePreviewSheet` for long notes + VoiceOver, and #55 *needs*
   it for Foliate (no `sourceRect`).
8. **Keep #53's tap→delete-menu AND show #55's preview on the same tap** —
   rejected (R-2): two surfaces from one tap. The de-conflict is mandatory.
9. **Treat Foliate as mechanical parity with TXT/MD/EPUB/PDF** — rejected
   (round-1 finding [8]). Foliate is a separate host with a separate,
   hard-coded delete pipeline; it gets its own WI (§4).

## 4. Work-item sequencing

Seven WIs. WI-1..WI-3 foundational (pure types, a persistence method, a
view model — no user-observable behavior). WI-4..WI-7 behavioral.

| WI | Tier | Scope | Est. PR size |
|---|---|---|---|
| **WI-1** | Foundational | `NotePreviewContent` value type + `NotePreviewPresenter.content(for:sourceRect:)` + `NotePreviewPresenter.form(...)` pure decision + `HighlightLookup` protocol. + Swift Testing: `content(for:)` mapping; `isEmpty` for `nil`/`""`/`"  "`/real note; `form(...)` decision table. | 2 new files + 1 test file, ~160 LOC |
| **WI-2** | Foundational | `PersistenceActor.highlight(withID:forBookWithKey:)` + `PersistenceActor: HighlightLookup`. + actor tests (in-memory `ModelContainer`): found / not-found / cross-book isolation / `note` round-trips non-nil + nil. | ~1 file modified + 1 test file, ~120 LOC |
| **WI-3** | Foundational | `NotePreviewViewModel` (`@Observable @MainActor`) — `handleTap` / `dismiss` / `presented` + the monotonic-tap-token out-of-order guard (§2.2.1). + ViewModel tests with a mock `HighlightLookup`: `handleTap` publishes content; not-found → `presented` stays nil; lookup-throws → no crash; `dismiss` clears; **out-of-order: an older slow lookup does not overwrite a newer tap's result** (inject a mock that delays the first lookup); double-tap. | 1 new file + 1 test file, ~170 LOC |
| **WI-4** | Behavioral | `NoteCalloutView` — the card (meta row, swatch from the real palette, excerpt, note-body hero, empty state, handoff row = **Share + Open-in-panel only** — Edit omitted as the `BLOCKED: needs-design` slice, Delete never added, §2.5/§2.7.2), `ReaderThemeV2`-themed, light/dark. + view-logic tests: empty-state vs note-state branch; the note-line-count helper boundary; accessibility identifiers. | 1 new file + 1 test file, ~230 LOC |
| **WI-5** | Behavioral | `NotePreviewSheetView` (bottom-sheet fallback, Done-only footer) + `NotePreviewPresenter`/`NotePreviewModifier` wiring + `UIKitNotePreviewPresenter` (the rect-anchored callout presenter, §2.7.1) + `NotePreviewPresenting` protocol. + tests: the callout-vs-sheet picker (short+anchored→callout; long→sheet; VoiceOver→sheet; `sourceRect==.zero`→sheet); a non-`ReaderHighlightTapEvent` object is ignored. | 2 new files + the modifier + 1 test file, ~240 LOC |
| **WI-6** | Behavioral | **Native formats (TXT / MD / PDF)** — wire `NotePreviewModifier` into `TXTReaderContainerView` / `MDReaderContainerView` / `PDFReaderContainerView`; **re-home the `HighlightActionPresenter.present(...)` call from the tap handler to a native `UILongPressGestureRecognizer` handler** in each (the §2.7.2 de-conflict — tap → #55 preview, long-press → #53 delete menu). + the acceptance pass for TXT/MD/PDF (preview on tap; #53 delete menu on long-press). | ~5-7 files modified + 1 test file, ~220 LOC |
| **WI-7** | Behavioral (final) | **EPUB + Foliate** — wire `NotePreviewModifier` into `EPUBReaderContainerView` and `FoliateSpikeView`; **remove the tap-time `HighlightActionPresenter.present(...)` call** in `EPUBWebViewBridgeCoordinator.handleHighlightTapMessage` and `FoliateHighlightTapHandlerModifier` so the tap → #55 preview. #53's tap-time menu is dropped on EPUB/Foliate for v1 — highlight delete stays reachable via the already-shipped Annotations panel Highlights-tab swipe-delete (the callout's Open-in-panel routes there); a JS long-press → #53 menu is a follow-up (§9). + the EPUB + Foliate acceptance pass (preview on tap; Foliate sheet-form `sourceRect==.zero`; delete reachable via Open-in-panel → swipe-delete). Flips the row to DONE. | ~5-6 files modified + 1 test file, ~220 LOC |

Round-1 finding [8] / round-3 finding [10] resolution: the v1 plan's WI-6
lumped all five formats. v2 split native vs Foliate. v4 re-draws the split
along the *real* capability line — **WI-6 = TXT/MD/PDF** (native hosts that
can take a `UILongPressGestureRecognizer`, so #53's delete menu re-homes to
long-press); **WI-7 = EPUB + Foliate** (web-rendered hosts whose highlight
taps come from JS — no native long-press for a highlight, so #53's tap-time
menu is dropped for v1 and delete stays reachable via the panel). WI-7 is
the final WI. Round-2 finding [9] also dropped the Delete affordance + the
`HighlightNoteEditSheet`, shrinking WI-4/WI-5.

Linear dependency: WI-3 needs WI-1+WI-2; WI-4 needs WI-1; WI-5 needs
WI-1+WI-3+WI-4; WI-6 needs WI-1..WI-5; WI-7 needs WI-1..WI-6. No
intra-feature parallelism.

## 5. Test catalogue

Concrete files (mirror the source tree):

- `vreaderTests/Views/Reader/NotePreviewPresenterTests.swift` —
  `content(for:sourceRect:)` field mapping; `isEmpty` for `nil`/`""`/`"   "`/
  a real note; `form(...)` decision table (short+anchored→callout;
  long-note→sheet; VoiceOver→sheet; `sourceRect==.zero`→sheet).
- `vreaderTests/Services/PersistenceActor+HighlightLookupTests.swift` —
  in-memory `ModelContainer`: `highlight(withID:)` returns the inserted
  record; unknown id → `nil`; **a highlight under book A is not returned
  for book B's key**; `note` round-trips a non-nil note and a `nil` note;
  a highlight with one of the broader-palette colors (`red`/`orange`/
  `purple`) round-trips its `color`.
- `vreaderTests/ViewModels/NotePreviewViewModelTests.swift` — mock
  `HighlightLookup`: `handleTap` with a found highlight publishes
  `NotePreviewContent`; missing id → `presented == nil` (deleted-race
  no-op); lookup `throws` → no crash, `presented` nil; `dismiss` clears;
  **out-of-order guard** — a mock that delays the *first* lookup and
  resolves the *second* fast; assert the first (older) result does NOT
  overwrite the second; a `handleTap` after a `dismiss` does not resurrect
  a card.
- `vreaderTests/Views/Reader/NoteCalloutViewTests.swift` — behavior not
  pixels: empty-state branch for `content.isEmpty`; note-body + handoff-row
  branch otherwise; the note-line-count threshold helper (boundary, just
  under, just over); the handoff row renders **Share + Open-in-panel** and
  **no Edit, no Delete** (v1 surface, §2.5/§2.7.2); accessibility identifiers
  for dismiss / Share / Open-in-panel; the color-swatch mapper resolves all
  stored palette colors incl. `red`/`orange`/`purple`.
- `vreaderTests/Views/Reader/Feature55NotePreviewVerificationTests.swift` —
  the cross-format acceptance harness (mirrors `Feature11EPUBHighlightVerificationTests`
  / `Feature40…`): for each of TXT/MD/EPUB/PDF/Foliate — seed a book + a
  highlight with a note via the DebugBridge, drive a tap on the annotated
  range, assert the note body is presented; a highlight *without* a note →
  the empty state; dismiss clears it. **TXT/MD/PDF**: assert a long-press
  still opens #53's delete menu (the §2.7.2 native split). **EPUB/Foliate**:
  assert the tap shows the #55 preview and that #53's tap-time menu no
  longer fires (the v4 scope — delete moves to the panel). Foliate: assert
  the sheet-form preview (`sourceRect==.zero` path).

**Edge cases explicitly enumerated** (per `AGENTS.md`):

- Empty note (color-only highlight) → the empty/no-note state.
- Whitespace-only note → treated as empty (`isEmpty` trims).
- **CJK / very long note** → scrollable callout body (`maxHeight: 180`) or
  the sheet form past the line threshold.
- **RTL note text** → the serif body honors natural alignment (no forced
  `.leading`).
- Highlight deleted between paint and tap → lookup `nil` → no-op.
- **Out-of-order async lookups** from rapid taps → the monotonic-token
  guard (§2.2.1); latest tap wins.
- Tap on a second highlight while a preview is open → replace.
- `sourceRect == .zero` (Foliate) → sheet fallback, no broken anchor.
- VoiceOver running → sheet form.
- A stored highlight color outside the note-preview design's depicted color
  set (`red`/`orange`/`purple`) → correct swatch (§2.1.1).
- Tapping non-annotated text → no `.readerHighlightTapped` → no preview;
  chrome-toggle unaffected (#53 WI-2 acceptance criterion d, preserved).
- A `.readerHighlightTapped` whose `object` is not a `ReaderHighlightTapEvent`
  → ignored.

Audit-driven additions filled after Gate 2.

## 6. Risks + mitigations

| ID | Risk | Mitigation |
|---|---|---|
| R-1 | Per-tap lookup performance — `handleTap` hits `PersistenceActor` on every annotated-text tap. | A dedicated `highlight(withID:forBookWithKey:)` single-fetch with a predicate, not paging the whole book's highlights. `PersistenceActor` serializes; one indexed fetch is cheap. §2.4. |
| **R-2** | **Two consumers of `.readerHighlightTapped`** — #53's delete menu and #55's preview would both fire on one tap. | **The central Gate-2 question.** Resolution: tap → #55 preview on all five formats. #53's delete menu: on **TXT/MD/PDF** it is re-homed from tap to a native long-press (still works, just on long-press — no new UI); on **EPUB/Foliate** (web-rendered, JS-driven taps, no native long-press for a highlight) the tap-time menu is dropped for v1 and delete stays reachable via the Annotations panel swipe-delete (Open-in-panel routes there). A JS long-press → #53 menu for EPUB/Foliate is a follow-up (§9). §2.7.2. |
| R-3 | Picking callout vs sheet wrong. | A pure decision helper `NotePreviewPresenter.form(...)`: line-count threshold OR VoiceOver OR zero-`sourceRect` → sheet; else callout. Unit-tested as a table. |
| **R-4** | The design's `NoteCallout` depicts an **Edit** action, but the edit *surface* it opens is not a committed buildable design, and a new `HighlightNoteEditSheet` would be self-designed UI (rule 51). | v1 ships the **read-only preview only**; the Edit action is OMITTED from the v1 callout and the Edit slice is `BLOCKED: needs-design` — a `needs-design` issue is filed for the highlight-note edit surface (§2.8). Note editing stays reachable via the callout's **Open-in-panel** → the Annotations panel's Highlights tab (already ships). #55's row is NOT blocked — only the Edit slice. §8. |
| R-5 | Foliate emits `sourceRect == .zero` — an anchored callout would point nowhere. | `NotePreviewPresenter.form(...)` returns `.sheet` when `sourceRect == .zero`. Foliate/AZW3 gets the preview via the bottom sheet; foliate-host.js rect-forwarding deferred (§9). §2.9. |
| R-6 | Gesture conflict — preview-tap vs selection long-press vs chrome-toggle. | No new gesture — #55 reuses the existing `.readerHighlightTapped`, which the bridges already fire only on a confirmed highlight hit-test (already `require(toFail:)` long-press, already skip chrome-toggle on a hit, per #53 WI-2/3). #55 changes *what the event drives*, not *when it fires*. |
| R-7 | The callout's UIKit `UIPopoverPresentationController` renders as a sheet on a compact-width iPhone (adaptive popover behavior). | Acceptable — it degrades to a sheet-like presentation, the same family as the intended fallback. WI-5 sets the adaptive-presentation delegate explicitly so the behavior is tested, not incidental. |
| R-8 | Out-of-order async lookups let an older tap overwrite a newer result. | The monotonic-tap-token guard in `NotePreviewViewModel.handleTap` (§2.2.1) — publish only if the captured token is still latest. Unit-tested (§5). |

## 7. Backward compat

- **No schema change.** `HighlightRecord.note` already exists; #55 reads it.
  `NotePreviewContent` is an in-memory value type.
- **No notification-contract change.** `.readerHighlightTapped` /
  `ReaderHighlightTapEvent` unchanged — #55 adds a *consumer*.
- **Feature #53 behavior change is intentional and scoped** — the
  de-conflict (§2.7.2, R-2) changes the *gesture* that opens #53's delete
  menu: was a single tap, becomes a long-press. #53's menu, action enum,
  presenter, and delete logic are all unchanged — only the gesture that
  triggers it moves. The tap is freed for #55's preview. Recorded in the PR
  body, ported to both feature rows. No data affected.
- **Older highlights** (`note == nil`) → tap shows the empty/no-note state.
  No migration.
- **No older-client / older-backup concern** — reader-session-local UI.

## 8. Design status (rule 51)

**The read-only preview surfaces — the v1 deliverable — are fully designed;
Gate 3 for them is NOT design-gated.** The committed bundle
`dev-docs/designs/vreader-fidelity-v1/project/vreader-note-preview.jsx`
(delivered 2026-05-18, resolves `needs-design` #865) — verified at plan
time: the file exists under `dev-docs/designs/vreader-fidelity-v1/project/`
and exports `NoteCallout` + `NotePreviewSheet` on `window` — depicts, by
name and visual content: the anchored `NoteCallout` (meta row, excerpt,
note-body hero, the `CalloutAction` handoff row, pointer notch), the
`NotePreviewSheet` fallback, the **empty/no-note state**, and light/dark via
the theme tokens. Everything in #55's v1 surface (§2.5, §2.6) is a faithful
or **narrower** realization of that bundle.

**One slice IS design-gated — the Edit action (round-2 finding [9]):**

The design's `CalloutAction` row depicts an **Edit** action, and the design
also shows an inline `editing` textarea state. But the *editor surface* — a
committed, buildable design for editing a highlight's note — is not in the
bundle in a form #55 can implement, and a new `HighlightNoteEditSheet` would
be **self-designed UI**, which rule 51 forbids. Therefore:

- **v1 ships the read-only preview only.** The callout's handoff row renders
  **Share + Open-in-panel** (both depicted, both need no new UI); the
  **Edit** action is **omitted** from the v1 callout.
- The **Edit slice is `BLOCKED: needs-design`**: a `needs-design` GitHub
  issue is filed — title `Design needed: highlight-note edit surface for
  feature #55`, labels `enhancement` + `needs-design` — so the user can
  carry the edit-surface design through `claude.ai/design`. A follow-up WI
  adds the Edit action once a bundle lands.
- **#55's row itself is NOT `BLOCKED`** — only the Edit slice is. The
  feature's stated acceptance criteria (a: tap shows the note body without
  the panel; b: dismissible; c: consistent across formats) are entirely
  satisfied by the read-only preview, which is fully designed. The row
  proceeds to `PLANNED` and through Gate 3 for WI-1..WI-7 as scoped.

**No Delete affordance is invented.** v1's earlier draft proposed adding
Delete to the callout row; round-2 finding [9] correctly flagged that as
self-designed UI (the design's row has no Delete). v3 instead **re-homes
#53's existing delete menu from the tap gesture to a long-press** (§2.7.2)
— #53's menu is iOS context-menu chrome (out of rule 51's scope) and is
unchanged; only the triggering gesture moves. Delete is fully preserved
with zero new UI.

So the only design-loop action this plan triggers is the **one
`needs-design` issue for the Edit surface**; it does not block the feature.

## 9. Known limitations / deferred (accepted at Gate 1, re-confirmed rounds 1-2)

- **In-callout Edit action + inline note editor** — `BLOCKED: needs-design`
  (§8). v1 ships the read-only preview; the Edit action is omitted and a
  `needs-design` issue is filed for the highlight-note edit surface. Note
  editing stays available via the callout's **Open-in-panel** → the
  Annotations panel's Highlights tab (`HighlightListView` already edits
  highlight notes). A follow-up WI adds the designed in-callout Edit once a
  bundle lands.
- **EPUB / Foliate long-press → #53 delete menu** — v1 drops #53's
  tap-time menu on the two web-rendered formats (their highlight taps come
  from JS, with no native long-press recognizer for a highlight); delete
  stays reachable via the Annotations panel swipe-delete. A follow-up adds a
  **JS long-press event source** (a `mousedown`/`touchstart` held >~500 ms
  in the EPUB / foliate-host.js highlight overlay) that feeds the existing
  `HighlightActionPresenting` presenter — restoring the in-reader
  long-press → delete menu on EPUB/Foliate to parity with TXT/MD/PDF.
- **Foliate anchored callout** — Foliate/AZW3 uses the bottom-sheet form
  because foliate-host.js does not forward the annotation screen-rect. A
  follow-up adds the rect to the JS `annotation-show` message so the
  Foliate tap handler can emit a real `sourceRect`.
- **"Open in panel" deep-link** — the callout's Open-in-panel opens the
  Annotations panel on the Highlights tab (existing behavior); scrolling the
  panel to the tapped highlight is a follow-up.
- **Share action** in the callout handoff row — wired to the existing reader
  share path; if that surface does not accept a note payload cleanly, the
  Share action is deferred (the callout still renders Open-in-panel).
  Flagged for Gate 2 — the Share *button* IS in the design, so wiring it
  later is not a design-loop issue, only an integration question.

## 10. Revision history

- **v1** (2026-05-19, feature-cron) — initial Gate-1 draft.
- **v2** (2026-05-19, feature-cron) — revised after Gate-2 round-1 Codex
  audit (thread `019e3e14`). Corrections: target `FoliateSpikeView+HighlightTap`
  as the live Foliate path (not the dormant `handleAnnotationShow`); #53
  framed as delete-only; explicit `UIPopoverPresentationController`-based
  callout presenter (not a hand-waved `.popover`); monotonic-tap-token
  out-of-order guard in `NotePreviewViewModel`; "Open in panel" → Highlights
  tab (not Notes); color swatch built against the real stored palette; WI-6
  split into WI-6 (native) + WI-7 (Foliate). See §11.
- **v3** (2026-05-19, feature-cron) — revised after Gate-2 round-2 Codex
  audit (same thread `019e3e14`). Round-2 left one High: v2's proposed
  Delete affordance on the callout row AND its new `HighlightNoteEditSheet`
  are both user-visible UI not in the committed design bundle (rule 51).
  v3 makes the default path rule-51-compliant: NO Delete affordance —
  instead #53's existing delete menu is re-homed from the tap gesture onto
  a long-press (no new UI); NO `HighlightNoteEditSheet` — the Edit slice is
  `BLOCKED: needs-design` with a `needs-design` issue filed, v1 ships the
  read-only preview only, note editing stays reachable via Open-in-panel.
  WI-4/WI-5 shrank accordingly. See §11.
- **v4** (2026-05-19, feature-cron) — revised after Gate-2 round-3 Codex
  audit (same thread `019e3e14`). Round-3 left one Medium: v3 overstated
  "#53 delete re-homes to long-press on all five formats" — EPUB and
  Foliate highlight taps come from JS, with no native long-press recognizer
  for a highlight. v4 narrows the guarantee honestly: tap → #55 preview
  ships on all five; #53's long-press delete menu is **TXT/MD/PDF-scoped**;
  on **EPUB/Foliate** the tap-time menu is dropped for v1 and delete stays
  reachable via the Annotations panel swipe-delete (a JS long-press → #53
  menu is a §9 follow-up). WI-6/WI-7 re-drawn along the native-vs-web
  capability line. See §11.

## 11. Audit fixes applied — Gate-2 rounds 1-2 (Codex thread `019e3e14`)

### Round 1 findings

| # | Severity | Finding | Resolution in v2 |
|---|---|---|---|
| 1 | High | `AnnotationEditSheet` edits `AnnotationRecord.content`, not highlight notes — it is NOT the highlight-note editor. The real path is `HighlightPersisting.updateHighlightNote(highlightId:note:)` (used by `HighlightListViewModel.updateNote`). | §2.0 fact 2, §2.8, §2.10, §3 rej. 4: `AnnotationEditSheet` is no longer claimed as the path. (v2 proposed a new `HighlightNoteEditSheet`; round-2 finding [9] then ruled that out as self-designed UI — v3 makes the Edit slice `BLOCKED: needs-design` instead. See finding [9] below.) |
| 2 | High | The live AZW3/MOBI path is `FoliateSpikeView` + `FoliateHighlightTapHandlerModifier` (`FoliateSpikeView+HighlightTap.swift`) — `ReaderContainerView` dispatches `.foliateWeb` straight to `FoliateSpikeView`. `FoliateReaderContainerView+Highlights.handleAnnotationShow` is dormant. | §2.0 fact 1, §1, §2.9, WI-7: all Foliate references retargeted to `FoliateSpikeView` + `FoliateSpikeView+HighlightTap.swift`. `sourceRect == .zero` kept as a real constraint, attributed to the live path. |
| 3 | Medium | #53 is **delete-only** (`HighlightTapAction.delete` only; `HighlightCoordinator.handleTapAction` only deletes; Foliate delete bypasses the coordinator via `FoliateHighlightTapHandlerModifier.performDelete`). The plan called it "edit/delete". | §2.0 fact 3, §2.7.2: de-conflict text rewritten — #53 is a *delete* surface. (v2 re-homed delete to a callout Delete affordance; round-2 finding [9] ruled that out — v3 instead re-homes #53's existing menu onto a long-press, no new UI. See finding [9].) |
| 4 | Medium | SwiftUI `.popover(item:)` cannot anchor to a raw `CGRect`; no rect-to-popover infra exists; `SelectionPopoverPresenter` is sheet-based. | §2.7.1, §3 rej. 1: v2 specifies a UIKit `UIPopoverPresentationController`-based presenter (`UIKitNotePreviewPresenter`) anchored to `event.sourceRect` in the host `UIView` — the same mechanism family as #53's `UIKitHighlightActionPresenter`. |
| 5 | Medium | `NotePreviewViewModel.handleTap(_:) async` does not guarantee "latest tap wins" — concurrent lookups can finish out of order. | §2.2.1: a monotonic `latestTapToken` — `handleTap` publishes `presented` only if its captured token is still latest. Unit-tested (§5). |
| 6 | Medium | `.readerOpenNotes` opens the panel's `.highlights` tab, not the Notes tab. | §2.0 fact 4, §2.8: "Open in panel" text corrected — opens the Highlights tab (existing behavior). |
| 7 | Low | The design's 4-color swatch map is narrower than stored highlight data (`HighlightListView` handles `yellow/green/blue/red/orange/purple`). | §2.1.1: the swatch mapper is built against the real stored palette, reusing the existing highlight-color mapping. |
| 8 | Low | WI-6 (5 containers + 5 coordinators) is too broad — Foliate is not mechanical parity work. | §4: WI-6 = the four native formats (mechanical, identical de-conflict); WI-7 = Foliate (separate host + delete pipeline + sheet-only). |

**Gate-2 round 2** (Codex thread `019e3e14`) — verified all 8 round-1 fixes
present and technically correct (`UIPopoverPresentationController` with
`sourceView`/`sourceRect` confirmed correct; `HighlightPersisting.updateHighlightNote`
confirmed to exist; the monotonic-token guard confirmed correct for an
`@MainActor` view model; the five tap-time `present(...)` call sites
confirmed). Left one new High:

| # | Severity | Finding | Resolution in v3 |
|---|---|---|---|
| 9 | High | v2 introduced two **user-visible surfaces not in the committed design bundle** — a **Delete** affordance on the `NoteCallout` action row (the design's row depicts only Edit/Share/Open-in-panel), and a new **`HighlightNoteEditSheet`** (no committed design). Rule 51 forbids inventing visible UI; v2's "reviewer can confirm / defer if judged undesigned" hedge is too weak for a Gate-1 plan — the proposed default path was design-blocked. | §2.5, §2.7.2, §2.8, §8, §4, §6 R-4, §3 rej. 5/6: **no Delete affordance** — #53's existing delete menu is re-homed from the tap gesture to a **long-press** (iOS context-menu chrome, out of rule-51 scope, unchanged). **No `HighlightNoteEditSheet`** — v1 ships the **read-only preview only**; the callout's handoff row renders Share + Open-in-panel (both depicted); the **Edit slice is `BLOCKED: needs-design`** with a `needs-design` issue filed. The feature row itself proceeds (acceptance criteria a/b/c are met by the read-only preview); only the Edit slice is gated. |

### Round 3 finding

**Gate-2 round 3** (Codex thread `019e3e14`) — confirmed the v3 rule-51 fix
(no Delete affordance, Edit slice `BLOCKED: needs-design`, only the Edit
slice blocked not the whole row) is correct. Left one new Medium:

| # | Severity | Finding | Resolution in v4 |
|---|---|---|---|
| 10 | Medium | v3 claimed "#53's delete menu re-homes from tap to long-press on **all five formats**", but EPUB highlight taps come from a JS `highlightTapHandler` message and Foliate's from a JS event — neither has a native long-press recognizer for a highlight. The plan overstated the completeness of long-press delete preservation, and §2.7.2/WI-7 already half-admitted a Foliate panel-delete fallback, contradicting the uniform claim. | §2.7.2, §4 WI-6/WI-7, §6 R-2, §5, §9: v4 narrows the guarantee to the real capability line. **Tap → #55 preview ships on all five formats.** #53's **long-press delete menu is TXT/MD/PDF-scoped** (native hosts that take a `UILongPressGestureRecognizer`). On **EPUB/Foliate** the tap-time menu is dropped for v1; highlight delete stays reachable via the already-shipped Annotations panel Highlights-tab swipe-delete (the callout's Open-in-panel routes there). A JS long-press → #53 menu for EPUB/Foliate is a §9 follow-up. WI-6 = TXT/MD/PDF, WI-7 = EPUB+Foliate. |

**Gate-2 outcome: CLEAN after 3 rounds** (the round-3 Medium [10] resolved
in v4 — a scope-narrowing within the same gate, no new findings introduced).
Zero open Critical/High/Medium findings. Feature #55 row → `PLANNED`.
