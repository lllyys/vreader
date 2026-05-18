# Feature #61 — Book Details sheet — implementation plan

- **Feature row**: `docs/features.md` #61 (TODO)
- **GH issue**: #800
- **Design source** (committed, rule 51 satisfied):
  `dev-docs/designs/vreader-fidelity-v1/project/vreader-book-details.jsx`
  + `dev-docs/designs/vreader-fidelity-v1/project/design-notes/feature-60-followups.md` §1
- **Author**: feature-cron (Gate 1), 2026-05-18
- **Lineage**: v2 follow-on of feature #60 (VERIFIED). New feature per the
  close gate — not a #60 reopen.

## 1. Problem

The reader More-menu's "Book details" row (`ReaderMoreMenuRow.bookDetails`)
ships, but its host-side handler is a stub: `ReaderContainerView+Sheets.swift`
`case .bookDetails: showSettings = true` — it opens the reader **settings**
panel as an interim because the real surface was undesigned when feature #60
WI-6c landed. The design has since been delivered (#789 handoff →
`vreader-book-details.jsx`). Users tapping "Book details" expect book
metadata (format, size, pages, fingerprint, location) and book-scoped
actions, not the global settings panel. This feature builds the real
surface.

## 2. Surface area

### New files

- `vreader/Views/Reader/BookDetails/BookDetailsViewModel.swift`
  - `struct BookDetailsViewModel` — a testable value type, mirroring the
    `BookInfoViewModel` precedent: a plain struct (no `@Observable`).
  - **`init(book: LibraryBookItem)`** — takes the value DTO, **not** the
    `Book` `@Model`. The reader host already holds a `LibraryBookItem`;
    no new fetch path, no `@Model` actor concern in a foundational type.
  - Fields: `title`, `author: String` (fallback "Unknown Author" — **no
    `· year`**; no publication-year field exists on `Book`/`LibraryBookItem`),
    `formatDisplay` (reuse `BookInfoViewModel.displayFormat`),
    `fileSizeDisplay` (`FileSizeFormatter`), `pagesDisplay: String?`
    (Risk 1), `fingerprintDisplay`/`fingerprintFull` (derived from
    `LibraryBookItem.fingerprintKey` — which already *is* the
    `{format}:{sha}:{bytes}` canonical key; no separate `fingerprint`
    object is needed or fetched), `locationDisplay` (from
    `LibraryBookItem.resolvedFileURL`), `tags: [String]` (mapped
    straight from the existing `LibraryBookItem.collectionNames` —
    feature #34 collection memberships *are* the design's tag chips;
    no new field), `isLongTitle: Bool`, `hasCover: Bool`.
  - **No `DetailsState` enum.** `longTitle` and `missingCover` co-occur,
    so they are two independent `Bool`s the view reads directly. The
    design's `remoteOnly` variant is out of scope — see §3.
- `vreader/Views/Reader/BookDetails/BookDetailsSheet.swift` — the
  half-sheet, "stacked" layout only, presented with
  `.presentationDetents`.
- `vreader/Views/Reader/BookDetails/BookDetailsMetadataRow.swift`,
  `BookDetailsActionRow.swift` — row sub-views (each file well under the
  ~300-line guideline).
- `vreader/Views/Shared/CoverPickCoordinator.swift` — see WI-2 below.

### Modified files

- `vreader/Views/Reader/ReaderContainerView.swift` — add
  `@State private var showBookDetails = false` **here**, with the other
  `@State` vars (~line 43). Swift forbids stored properties in an
  extension, so it cannot live in `+Sheets.swift`.
- `vreader/Views/Reader/ReaderContainerView+Sheets.swift` —
  `case .bookDetails:` → `showBookDetails = true` (was `showSettings`);
  add the `.sheet(isPresented: $showBookDetails)` presenting
  `BookDetailsSheet`; update the stale "interim" doc-comment.
- `vreader/Models/LibraryBookItem.swift` — add a `totalPageCount: Int`
  stored field. It must be added to the `struct` *and* its explicit
  memberwise `init` with a back-compat default (`= 0`) — the same
  pattern `fileState`/`blobPath`/`collectionNames`/`progressFraction`
  already use so existing call sites keep compiling. (Cannot be an
  extension — `LibraryBookItem` is a `struct` and this is stored data;
  the file is `vreader/Models/LibraryBookItem.swift`, not under
  `Views/`.)
- `vreader/Services/PersistenceActor+Library.swift` — the
  `Book → LibraryBookItem` projection adds `totalPageCount:
  book.totalPageCount` (the `Book.totalPageCount` field already exists).
- `vreader/Views/Reader/ReaderMoreMenuRow.swift` — remove the stale
  "the Book Details sheet is undesigned" comment at `:25`. No
  enum/behavior change.

### Modified files (WI-2 — cover-pick coordinator extraction)

The library cover-replace flow today is four `@Binding`s threaded
through the `LibraryViewSheets` `ViewModifier` (`coverPickerItem:
PhotosPickerItem?`, `bookForCover: LibraryBookItem?`,
`isShowingCoverPicker: Bool`, `coverVersion: Int`) plus the
`.photosPicker` modifier in `LibraryViewSheets.body` and the
`CustomCoverStore` persist. WI-2 extracts it:

- **New** `vreader/Views/Shared/CoverPickCoordinator.swift` — an
  `@Observable @MainActor` type owning the picker state. API:
  `func present(for book: LibraryBookItem)`; `var coverVersion: Int`
  (observable — bump on a successful pick so cover views refresh);
  and a `ViewModifier`/`.coverPicker(_:)` helper that attaches the
  `.photosPicker` + runs the pick → `CustomCoverStore` persist.
- **Modify** `vreader/Views/Library/LibraryView.swift` — replace the
  four cover `@State` vars with one `@State CoverPickCoordinator`.
- **Modify** `vreader/Views/Library/LibraryViewSheets.swift` — drop the
  four cover `@Binding`s + the inline `.photosPicker`; attach the
  coordinator's modifier instead.
- **Modify** `vreader/Views/Library/LibraryView+Body.swift` — the
  context-menu "Set Cover" row calls `coordinator.present(for: book)`
  instead of setting `bookForCover`; "Remove Cover" is unchanged
  (`CustomCoverStore.removeCover` directly).

### Files OUT of scope

- The **"split" (cover-left) layout** — design note §1: split is a
  Tweak, not the canonical surface. Build `stacked` only.
- The **`remoteOnly` state + Download CTA**. A reader-side sheet cannot
  reach it: `LibraryBookItem.isReadable` is `fileState == .local`, and
  the library opens the reader only for readable books (non-local rows
  divert to `BookDownloadSheet`). The design's remote-only variant
  belongs to a hypothetical library-side details sheet, not this
  feature. `BookFileState` is therefore not read here.
- `BookInfoSheet.swift` — a different surface (library "Info", feature
  #9); reused only as a pattern precedent, not modified.
- Cover-extraction, Share, Export-annotations *engines* — already
  shipped (features #30 / #9 / #35); wired in, not rebuilt.

## 3. Prior art / project precedent / rejected alternatives

- **Precedent — `BookInfoSheet` / `BookInfoViewModel`**: the established
  testable-struct-VM-over-`LibraryBookItem` pattern; `displayFormat` and
  `FileSizeFormatter` reused verbatim.
- **Precedent — Share / Export annotations**: feature #9 `ShareSheet`,
  feature #35 export action — WI-4 routes to both.
- **Precedent — cover swap**: feature #30 + `CustomCoverStore`; WI-2
  extracts the existing library PhotosPicker flow into a shared
  coordinator rather than duplicating it.
- **Rejected — `init(book: Book)`**: drags the SwiftData `@Model` into a
  foundational formatter. Rejected for the `LibraryBookItem` boundary.
- **Rejected — reuse `BookInfoSheet` directly**: its `Form` layout does
  not match the v2 cover-on-top design.
- **Rejected — split layout / remote-only state**: see §2 OUT of scope.

## 4. Work-item sequencing

| WI | Title | Tier | PR size |
|----|-------|------|---------|
| WI-1 | `BookDetailsViewModel` + `LibraryBookItem.totalPageCount` projection | **foundational** | small |
| WI-2 | Extract `CoverPickCoordinator` from the library cover-replace flow | **foundational** | small–medium |
| WI-3 | `BookDetailsSheet` view (stacked) + More-menu rewire | **behavioral** | medium |
| WI-4 | Actions wiring (cover-swap via WI-2 / share / export) + Fingerprint-copy + Location-reveal | **behavioral** (final WI) | medium |

- **WI-1** — add `totalPageCount` to `LibraryBookItem` + its projection,
  and the `BookDetailsViewModel` mapping. No user-observable change. RED:
  `BookDetailsViewModelTests`. Foundational → `patch`.
- **WI-2** — extract `CoverPickCoordinator`. The library cover-swap must
  behave **identically** afterward — that is what makes WI-2
  foundational. RED: `CoverPickCoordinatorTests` pinning the
  pick→persist contract; the existing library cover-swap tests re-run
  green in the WI-2 PR. Foundational → `patch`.
- **WI-3** — the sheet renders and replaces the settings interim. RED:
  `BookDetailsRouteTests` — the `.bookDetails` route sets
  `showBookDetails`, not `showSettings`. Behavioral, not final →
  `patch`.
- **WI-4** — the three Actions rows + two inline mini-actions go live;
  completes the feature. Behavioral, final WI → `minor`.

## 5. Test catalogue

- `vreaderTests/Views/Reader/BookDetails/BookDetailsViewModelTests.swift`
  (WI-1): parameterized over format → `formatDisplay`; `fileSizeDisplay`;
  `fingerprintDisplay` middle-truncation + `fingerprintFull` round-trip
  against the real `fingerprintKey` form; `pagesDisplay` non-nil when
  `totalPageCount > 0`, nil at `0` (Risk 1); `isLongTitle` boundary +
  CJK / very-long titles; `hasCover` from `coverImagePath`; `tags` from
  `collectionNames`; `author` nil → fallback.
- `vreaderTests/Views/Shared/CoverPickCoordinatorTests.swift` (WI-2): the
  pick → `CustomCoverStore` persist contract + `coverVersion` bump; the
  existing library cover-swap tests are named in the WI-2 PR as
  must-stay-green regression guards.
- `vreaderTests/Views/Reader/BookDetails/BookDetailsRouteTests.swift`
  (WI-3): the `.bookDetails` row drives `showBookDetails`, not
  `showSettings`.
- WI-4: the Actions list exposes exactly three rows; the cover row label
  is "Add cover…" when `hasCover == false` else "Replace cover…";
  fingerprint-copy writes `fingerprintFull` to the pasteboard.
- UI verification (Gate 5) —
  `vreaderUITests/Verification/Feature61BookDetailsVerificationTests.swift`:
  open a seeded book → More ⋯ → Book details → assert `BookDetailsSheet`
  present, metadata + Actions rows resolve. DebugBridge-drivable, CU-free.

## 6. Risks + mitigations

1. **Page count for reflowable formats.** `Book.totalPageCount` exists;
   `LibraryBookItem` gains it via WI-1. It is meaningful only where the
   format paginates fixedly (PDF); reflowable formats may store `0`.
   *Mitigation*: `pagesDisplay` is `String?`, derived purely from the
   already-projected `totalPageCount` (no `PDFDocument` recompute, no
   file I/O in VM init); WI-3 omits the Pages row when nil.
2. **"Location reveal" has no iOS equivalent.** The `[↗]` mini-action
   presents the system share sheet for the file URL — the closest
   meaningful "here is the file" affordance. WI-4 owns it.
3. **Cover-swap reentrancy.** WI-2's coordinator is presented from a
   sheet itself presented from the reader. WI-4 verifies the
   PhotosPicker presents over the details sheet and the swapped cover
   refreshes (the `coverVersion` bump drives it).
4. **WI-2 blast radius.** WI-2 deliberately edits three already-VERIFIED
   library files. *Mitigation*: it is strictly behavior-preserving; the
   WI-2 PR re-runs the existing library cover-swap tests as named
   regression guards, and `CoverPickCoordinator` is additive (the
   library adopts it; no semantics change).

## 7. Backward compatibility

- No schema change, no migration. `LibraryBookItem.totalPageCount` is a
  new value-type field with a `= 0` default init param — existing call
  sites compile unchanged.
- Behavior changes: the More-menu "Book details" destination (settings
  interim → real sheet). WI-2 is behavior-preserving for the existing
  library cover-swap. No persisted state, no older-client / older-backup
  impact. Fully additive.

## 8. Revision history / Gate-2 audit trail

| Version | Date | Change |
|---|---|---|
| v1 | 2026-05-18 | Initial draft (feature-cron, Gate 1). |
| v2 | 2026-05-18 | Gate-2 round-1 (Codex `019e39e3`): 8 findings applied — `@State` moved to `ReaderContainerView.swift` (Critical); VM takes `LibraryBookItem` not `Book` (High); `remoteOnly`/Download descoped (High); `Book.totalPageCount` exists, no `PDFDocument` recompute (Medium); `DetailsState` enum → two `Bool`s (Medium); cover-swap reuse → dedicated extraction WI-2 (Medium); `· year` removed (Medium); `BookFileState` not read (Low). 3 WIs → 4. |
| v3 | 2026-05-18 | Gate-2 round-2 (Codex `019e39e3`): 2 Medium findings applied — WI-1 surface tightened (`totalPageCount` is a stored field added to `vreader/Models/LibraryBookItem.swift` + projected in `PersistenceActor+Library.swift`; `tags` map from the existing `collectionNames`; `fingerprint` uses the existing `fingerprintKey` — no new object); WI-2 surface made explicit (the `CoverPickCoordinator` API + the three library files — `LibraryView.swift`, `LibraryViewSheets.swift`, `LibraryView+Body.swift` — that adopt it). |

### Gate 2 — Independent plan audit

**Round 1** — Codex MCP, thread `019e39e3-729c-7bc1-b308-3d394015c17e`,
2026-05-18. 1 Critical + 2 High + 4 Medium + 1 Low — all legitimate,
all applied in v2. Codex confirmed the verified-correct assumptions
(`Book` fields, `DocumentFingerprint.canonicalKey`, `BookInfoViewModel`,
`FileSizeFormatter`, `ReaderMoreMenuRow.bookDetails`, the `showSettings`
handler, `ShareSheet`, the library cover-picker all exist).

**Round 2** — Codex MCP, same thread, 2026-05-18. v2 confirmed: all 8
round-1 findings genuinely resolved. 2 Medium findings remained — both
plan-precision gaps (WI-1's `LibraryBookItem` field surface; WI-2's
library-file modification list) — applied in v3. Codex confirmed WI-2
as `foundational` is acceptable given behavior-preservation + regression
coverage, and the 4-WI sequencing + foundational/foundational/
behavioral/behavioral + patch/patch/patch/minor tiers are right.

**Round 3** — Codex MCP, same thread, 2026-05-18. Verdict: **"v3 is
Gate-2 clean."** Both round-2 findings genuinely resolved (WI-1 names the
real stored-data change + projection point; WI-2 names the extraction
API + the three adopting library files). No new Critical/High/Medium
findings. The 4-WI split and tiers remain sound.

**Gate 2 PASSED** (3 rounds — within the rule-47 cap). Zero open
Critical/High/Medium findings. Plan ready for Gate 3 (TDD
implementation), starting at WI-1.
