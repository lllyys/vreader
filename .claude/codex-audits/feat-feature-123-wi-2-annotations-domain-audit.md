---
branch: feat/feature-123-wi-2-annotations-domain
threadId: codex-exec-f123-wi2
rounds: 2
final_verdict: ship-as-is
date: 2026-06-28
---

# Feature #123 WI-2 (foundational) — annotations domain

Adds `AnnotationColor` (5 colors), `AnnotationAnchor` (sealed Text/Epub + hash),
the `HighlightRecord`/`NoteRecord`/`BookmarkRecord` DTOs + entity mappers +
`profileKey`/`anchorKey` derivation, and `AnnotationsRepository` (DTO boundary)
+ the `AppContainer` DI singleton.

## Round 1 — findings

| # | file:line | severity | issue | resolution |
|---|---|---|---|---|
| 1 | AnnotationsRepository.addHighlight | **High** | On a dedupe the upsert keeps the EXISTING row's id, but `addHighlight` returned the freshly-generated (discarded) id — WI-3 callers would apply decorations/listeners against a dead highlightId. | FIXED — `AnnotationDao.upsertHighlight` now returns the PERSISTED entity (`findHighlightByKey(profileKey, anchorKey)` after insert-or-update); the repo returns `persisted.toRecordOrNull()`. New test asserts `second.id == first.id` and `findHighlight(second.id)` is live. |
| 2 | AnnotationsRepository (all add*) | Medium | No `locator.fingerprintKey == bookKey` guard — a caller could file an annotation under one book with a locator pointing at another (poisons backup/restore; iOS rejects this). | FIXED — `requireSameBook(bookKey, locator)` = `require(locator.fingerprintKey == bookKey)` in addHighlight/addNote/addBookmark + a rejecting test. |
| 3 | Annotation.kt / Entities.kt | Medium | Storage-contract inconsistency: mapper writes full `Locator` JSON but the entity doc/plan said `canonicalJson()`. | FIXED — Room stores the FULL round-trippable plain `Locator` (the position precedent); `profileKey` derives from `canonicalJson()` for cross-platform-stable dedup; the entity doc now states the #113 backup collector MUST convert to `record.locator.canonicalJson()` (don't copy verbatim). |

## Round 2 — verify

High + the two Medium confirmed resolved. One remaining Medium: stale inline
comments still said "canonical" on the field + the note doc — **FIXED** (the
`locatorJSON` field comment + the `AnnotationNoteEntity` doc now match the
round-trippable-form contract). Zero open Critical/High/Medium.

## Tests
- `AnnotationColorTest` (5), `AnnotationAnchorTest` (6), `AnnotationsRepositoryTest` (12 incl. dedupe-returns-persisted-id + cross-book-rejected) — **SUCCEEDED** (Robolectric/JVM).
- `AnnotationDaoTest` re-run green with the returning upsert.

## Verdict
**ship-as-is.** The dead-id dedupe bug (the one that would have bitten WI-3) is
fixed and regression-tested; the book/locator guard mirrors iOS; the storage
contract is documented consistently.
