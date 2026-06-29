---
branch: feat/feature-127-wi-2-collection-repository
threadId: 019f12ae-bb16-7253-aefd-3312d6c6167d
rounds: 1
final_verdict: ship-as-is
date: 2026-06-29
---

# Gate-4 audit — feature #127 WI-2 (CollectionDao full + CollectionRepository)

Independent Codex audit (gpt-5.5, high reasoning, read-only sandbox) of WI-2: the full
`CollectionDao` (interface → abstract class so `@Transaction` create/rename dedup can call
the abstract queries) + `CollectionRepository` (the DTO boundary) wired into `AppContainer`.

## Findings — 2 Medium, both fixed; no Critical/High

| file | severity | issue | resolution |
|---|---|---|---|
| `CollectionDao.renameIfAbsent` | Medium | Reported `Duplicate` before proving the target `id` exists — `rename("ghost", "Beta")` returned `DuplicateName` when "Beta" existed, though a gone id should be `NotFound`. | **Fixed.** Added `existsById(id)` and check it FIRST inside the `@Transaction`, then the duplicate-ownership check, then update. Added a `rename("ghost", existingName) → NotFound` test. |
| `CollectionRepository.normalize` | Medium | Truncated by Kotlin UTF-16 code units, not iOS `String.prefix(100)` (extended grapheme cluster) semantics — a 101-emoji name would store 50 surrogate halves on Android vs 100 emoji on iOS, breaking parity + the backup name identity. | **Fixed.** Truncate to 100 **grapheme clusters** via `BreakIterator.getCharacterInstance()` (matches Swift `Character`). Added a 150-emoji test asserting 100 code points kept. `nameKey` is derived from the truncated stored name. |

## Auditor confirmations (clean)

- The `@Transaction` shape is correct: non-abstract `open suspend fun` on an abstract `@Dao` runs in a
  DB transaction (Room docs), and Room serializes transactions — so `createIfAbsent`/`renameIfAbsent`
  are atomic check-then-write (the unique `nameKey` index is the additional SQL backstop).
- The `LEFT JOIN COUNT(bc.bookKey) GROUP BY c.id` maps cleanly to `CollectionWithCount`, 0 for empty
  collections. DTO boundary respected (no entity leak). `AppContainer` lazy-singleton wiring matches the
  `annotationsRepository` precedent. Flow types + FK cascade sound.

## Test evidence

- `CollectionRepositoryTest` — 11/11 (create, empty/whitespace→EmptyName, dedup case/whitespace/locale-
  invariant/CJK→DuplicateName, truncate-100 ASCII + **grapheme/emoji**, rename success/duplicate/**gone-id
  NotFound**, membership+count incl. empty=0, FK cascade, idempotent delete).
- `CollectionDaoTest` — 3/3.

## Verdict

ship-as-is. WI-2 is foundational; WI-3 wires `LibraryViewModel` collections state + the shelf-bar.
