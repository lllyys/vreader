# Feature #123 — Android EPUB highlights & notes (Phase 3, #110 driver)

> Part of checklist item **B** in `docs/parity/android-checklist.md`. iOS parity:
> #62 / the iOS `Highlight`/`AnnotationNote` models. Design bundle:
> `dev-docs/designs/vreader-fidelity-v1/project/vreader-android-annotations.jsx`
> (`SelectionPopover`) + `vreader-annotations.jsx`.

> **Scope was narrowed at Gate-2 (v2).** Checklist item B (the full annotation
> capability) decomposes into THREE features; this one is the first:
> - **#123 (this) — EPUB highlighting**: select text in an EPUB → 5-color
>   highlight / note / copy / share → persists → re-renders on reopen → tap an
>   existing highlight to edit/remove. **Fully user-reachable via the selection
>   gesture — needs no reader chrome.**
> - **#124 (follow-on) — TXT/MD highlighting**: a custom Compose selection
>   engine (offset extraction) + the MD source↔render offset map. Split out
>   because it is a standalone engine, not a "generalize TxtBody" task.
> - **review sheet + bookmark creation** ride with item **F** (reader navigation
>   chrome) — they need a chrome entry point F owns; building them here would be
>   dead code with no production route (Gate-2 Critical).
> Box B is checked only when all three land.

## Problem

The Android app reads EPUB/TXT/MD/PDF and tracks reading time (#122) but a reader
cannot mark up a book. This feature delivers the core annotation interaction on
the best-supported Android reader (EPUB via Readium): select text → highlight in
one of 5 colors / attach a note / copy / share, see highlights re-render on
reopen, and tap an existing highlight to edit its note, change color, or remove
it. The selection popover IS the entry point, so the feature is self-contained
and end-to-end verifiable without any reader-chrome work.

## Surface area

### New — data layer (`com.vreader.app.data`)

- `Entities.kt` — three `@Entity` (bookmarks included now so the schema migration
  happens once; only highlights+notes are UI-wired in #123, bookmarks are wired
  by item F):
  - `HighlightEntity(highlightId: String PK, bookKey, profileKey, anchorKey: String, color: String, selectedText: String, note: String?, locatorJSON: String, anchorJSON: String?, createdAt: Long, updatedAt: Long)` — `@Index("bookKey")`, `@Index(value=["profileKey","anchorKey"], unique=true)`, FK→`books(fingerprintKey)` ON DELETE CASCADE. **`anchorKey` is NON-NULL** = `anchorHash ?: "__nil_anchor__"` (a sentinel, NOT nullable) — SQLite treats NULLs as distinct in a unique index, so a nullable column would let repeated null-anchor highlights bypass dedupe; the sentinel makes all null-anchor highlights for one `profileKey` collide, matching the iOS "dedupe nil-anchor by profileKey alone" behavior. (#123 EPUB highlights always carry a CFI anchor, so `anchorKey` is real here; the sentinel is the correctness backstop + the #124 path.)
  - `AnnotationNoteEntity(noteId, bookKey, profileKey, content, locatorJSON, anchorJSON?, createdAt, updatedAt)` — `@Index("bookKey")`, FK CASCADE. (standalone notes.)
  - `BookmarkEntity(bookmarkId, bookKey, profileKey, title: String?, locatorJSON, createdAt, updatedAt)` — `@Index("bookKey")`, FK CASCADE.
  - **`locatorJSON` is unambiguously `vreader.contracts.Locator.canonicalJson()`** (plain canonical `Locator`, NOT `VReaderLocator` or Readium JSON) — required by the #113 backup contract (`BackupSections.kt` annotation sections). Readium's precise CFI/range lives in `anchorJSON` only.
- `Daos.kt` — `AnnotationDao` (abstract class, like `ReadingStatsDao`): `@Transaction upsertHighlight` (INSERT-OR-IGNORE on the unique `(profileKey,anchorHash)` then UPDATE — the iOS `PersistenceActor+Highlights` dedupe analog, minSdk-26-safe); per-type upsert/delete; `observeHighlights(bookKey)/observeNotes(bookKey)` Flows; `allHighlights()` for later library-wide review; `countsForBook`.
- `VReaderDatabase.kt` — `@Database` v3 → **v4**; add the 3 entities + `annotationDao()`; append `MIGRATION_3_4` (CREATE TABLE ×3 + indices, byte-exact to Room's generated schema) to `ALL_MIGRATIONS`.

### New — domain (`com.vreader.app.annotations`)

- `AnnotationColor.kt` — `enum AnnotationColor(key, dotHex, washHex, ruleHex)` with the design's **5** colors (yellow/green/blue/pink/red). **This is DESIGN parity, not iOS-model parity** — iOS `NamedHighlightColor` has 4 (no `red`); a test asserts iOS would treat Android `red` as an unknown-color string (graceful, non-corrupting) per `NamedHighlightColor.from`. `from(storage): AnnotationColor?` is nil-tolerant. Stored as the `key` string.
- `AnnotationAnchor.kt` — sealed `AnnotationAnchor`, mirroring the iOS `AnnotationAnchor` field shape for cross-platform durability: `Text(sourceUnitId: String, startUTF16: Int, endUTF16: Int)` and `Epub(href: String, cfi: String, serializedRange: EpubSerializedRange?)` where `EpubSerializedRange(startContainerPath, startOffset, endContainerPath, endOffset)`. `@Serializable`; `anchorHash` = SHA-256 of canonical JSON. **Note**: Readium's `Selection.locator` yields `href` + a `locations.fragments`/CFI; `serializedRange` is populated only if Readium exposes it (else null — the CFI in `cfi` is the durable anchor). This is an explicitly Android-originated anchor whose backup migration is the same path as #113's reserved annotation sections.
- `Annotation.kt` — `HighlightRecord`/`NoteRecord`/`BookmarkRecord` DTOs (mirror iOS `…Record`); `profileKey = "$bookKey:${locator.canonicalHash}"` (the iOS profile-key analog).
- `AnnotationsRepository.kt` — CRUD + Flow reads, returns DTOs only: `highlights(bookKey)`, `notes(bookKey)`, `addHighlight`, `updateHighlight` (color/note), `removeHighlight`, `addNote`. DI singleton in `AppContainer` (the #122 `statsRepository` precedent).

### New — reader integration (EPUB / `com.vreader.app.reader`)

- `ReaderActivity` — wire Readium selection + decorations (the verified 3.3.0 API):
  - Selection actions via `EpubNavigatorFragment.Configuration(selectionActionModeCallback = callback)` (positional constructor arg, or build-then-`.apply { selectionActionModeCallback = … }` — NOT a trailing-lambda DSL), passed through `EpubNavigatorFactory.createFragmentFactory(..., configuration = …)`. On the custom action, read `nav.currentSelection()` (a **suspend, NULLABLE** call → `?: return`) → `Selection(locator, rect)`, selected text = `selection.locator.text?.highlight?.takeUnless { it.isBlank() } ?: return` (text may be absent/blank); then `nav.clearSelection()`.
  - Show the `SelectionPopover` anchored at `selection.rect`.
  - Render highlights: on open, build `Decoration(id=highlightId, locator, style=Decoration.Style.Highlight(tint=colorInt, isActive=true))` list and `nav.applyDecorations(decorations, group="highlights")` (**suspend**).
  - Existing-highlight tap: `nav.addDecorationListener(group="highlights", listener)` → map the tapped decoration id → `HighlightRecord` → open the popover in existing-highlight mode (Note/Copy/Share/Remove).
- The EPUB chrome stays as-is (back/title); the popover floats over content. No new chrome.

### New — UI (`com.vreader.app.annotations` Compose)

- `SelectionPopover.kt` — the design `SelectionPopover`: color row (5 dots + "+" deferred-noop in #123), action row (just-selected: Highlight/Note/Copy/Share; existing: Note/Copy/Share/Remove), note-compose row. Reuses `VReaderColors`/`VReaderFonts`. (Translate action: OUT — routes to #119 when present; omitted, not a placeholder.)
- `SelectionPopoverViewModel.kt` — popover mode (just-selected vs existing) + note draft + the selected `Selection`/`HighlightRecord`.

### Files OUT of scope (with destination)

- **Annotations review sheet** + **bookmark creation UI** → item **F** (needs the chrome entry F owns; building here = dead code, Gate-2 Critical). Bookmark *table+repo* ship here (foundational); its create/list UI is F's.
- **TXT/MD highlighting** → follow-on **#124** (a standalone Compose selection engine + MD source↔render offset map; `MarkdownRenderer` drops source markers so render offsets ≠ source offsets).
- **PDF highlighting** — no text layer.
- **Live translate** — #119 AI-gated.
- **Annotations-in-WebDAV-backup** — #113 reserves the sections; wiring is a later follow-on.
- **iOS code** — untouched (rule 48).

## Prior art / precedent / rejected alternatives

- Reader→Room wiring: #122 `TxtReaderActivity` precedent (process-singleton repo, `appScope` must-finish writes).
- iOS parity: entity fields mirror iOS `Highlight`/`AnnotationNote` + `HighlightRecord` + `AnnotationAnchor`; dedupe mirrors `PersistenceActor+Highlights.swift` (profileKey + anchorHash in a transaction), NOT locator-hash-alone (Gate-2 High).
- Readium decorations (native) over a custom JS WebView highlighter (iOS's EPUB approach) — Readium 3.3.0 gives it natively; rejected forking.
- Compose `SelectionContainer` for TXT — rejected (no offset access); that engine is #124's job, deliberately not in #123.

## Work-item sequencing

| WI | Tier | Scope | PR size |
|---|---|---|---|
| WI-1 | foundational | Room: 3 entities + `AnnotationDao` (transactional dedupe) + DB v4 + `MIGRATION_3_4`. Tests: DAO CRUD/observe/cascade/dedupe, migration 3→4 + 1→4 chain. | M |
| WI-2 | foundational | `AnnotationColor` + `AnnotationAnchor` + records + `AnnotationsRepository` + DI. Tests: color round-trip/unknown(+iOS-red-unknown), anchor hash, repo CRUD/observe/dedupe/profileKey. | M |
| WI-3 | behavioral | Readium **selection spike→production**: `selectionActionModeCallback` + `currentSelection()` → `SelectionPopover` (just-selected) → create highlight/note + `applyDecorations` render on open. Tests: selection→record mapper, decoration build, popover VM; emulator slice w/ real EPUB. | L |
| WI-4 | behavioral (final) | Existing-highlight mode: `addDecorationListener` → id→record → popover (Note/Copy/Share/Remove) → edit color/note + remove (re-apply decorations). Full emulator acceptance + evidence file. | M-L |

WI-3 begins with a compile-spike confirming the Readium 3.3.0 symbols resolve
(`selectionActionModeCallback`, `currentSelection`, `applyDecorations`,
`addDecorationListener`, `Decoration.Style.Highlight`) before building on them.

## Test catalogue

- `AnnotationDaoTest` (connected): per-type CRUD/observe; FK cascade on book delete; transactional dedupe on `(profileKey,anchorHash)`; counts.
- `VReaderDatabaseMigrationTest` (extend): 3→4 + 1→4 chain.
- `AnnotationColorTest` (JVM): 5-color round-trip; unknown→null; **iOS `red` treated as unknown** (parity guard).
- `AnnotationAnchorTest` (JVM): Text/Epub round-trip; hash stability; null serializedRange.
- `AnnotationsRepositoryTest` (connected): CRUD; per-book observe; dedupe; profileKey derivation; update color/note; remove.
- `EpubSelectionMapperTest` (JVM): Readium `Selection`→`HighlightRecord` (href/cfi/text/locator canonicalJson); empty/whitespace selection rejected; selection with no `text.highlight`.
- `SelectionPopoverViewModelTest` (JVM): just-selected↔existing mode; note draft; very long note.
- `AnnotationsConnectedTest` (emulator): create highlight on a real EPUB → persist → re-load → decoration re-applies; edit color/note; remove.

**Edge cases (Gate-2 Medium)**: empty/whitespace selection, emoji surrogate-pair
boundaries, CJK no-space text, overlapping highlights (two decorations same range),
rapid repeated highlight taps (dedupe idempotent), very long notes, locator parse
failure (corrupt JSON → skip, don't crash), FK book deletion during a write,
ambiguous EPUB href, Readium selection with no `text.highlight`.

## Risks + mitigations

- **R1 — Readium API surface** (highest now): WI-3 opens with a compile-spike against 3.3.0; if a symbol differs, fix the mapper before UI. The Gate-2 audit already corrected the names (suspend `currentSelection`/`applyDecorations`; `selectionActionModeCallback`; `addDecorationListener`; text = `selection.locator.text.highlight`).
- **R2 — popover anchoring** over the Readium fragment (Android View) from Compose: anchor at `selection.rect` via a Compose overlay positioned in the host; spike in WI-3.
- **R3 — anchor durability** (CFI re-pagination): store the Readium `Locator` (in `anchorJSON`) + canonical `Locator` (`locatorJSON`); Readium re-applies decorations by `Locator`, robust to font/layout changes.
- **R4 — dedupe race**: unique index `(profileKey,anchorHash)` + transactional upsert.

## Backward compat

Additive: new tables, DB v3→v4 via `MIGRATION_3_4`. Existing data untouched. No
backup-format change (annotations-in-backup deferred). Single app, monotonic DB.

## Revision history

- v1 (2026-06-28) — initial plan (full B capability in one feature).
- v3 (2026-06-28) — **Gate-2 round-2 fixes** (Codex, gpt-5.5/high; 2 Medium, no
  Critical/High): `anchorKey` is now a NON-NULL sentinel (`anchorHash ?: "__nil_anchor__"`)
  with the unique index on `(profileKey, anchorKey)` (SQLite NULL-distinctness would
  break null-anchor dedupe); corrected the Readium `Configuration` construction
  (positional/`.apply`, not a DSL lambda) + explicit nullable handling of
  `currentSelection()` and `selection.locator.text?.highlight`. **Gate-2 clean.**
- v2 (2026-06-28) — **Gate-2 round-1 fixes** (Codex, gpt-5.5/high): narrowed to
  EPUB-only (TXT/MD→#124, review-sheet/bookmark-create→F) per the entry-point
  Critical; corrected the Readium 3.3.0 API (suspend `currentSelection`/
  `applyDecorations`, `selectionActionModeCallback`, `addDecorationListener`,
  text=`selection.locator.text.highlight`); fixed dedupe to profileKey+anchorHash
  in a transaction; `locatorJSON` pinned to canonical `Locator` (backup contract);
  reworded the color claim (design-parity ≠ iOS-model-parity) + added the
  iOS-red-unknown test; mirrored the iOS `AnnotationAnchor` field shape; expanded
  edge-case tests. Pending Gate-2 round-2 re-audit.
