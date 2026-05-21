---
branch: fix/issue-1075-webdav-restore-book-titles
threadId: 019e472f-670b-7082-96c0-5e1c16aca6a3
rounds: 2
final_verdict: ship-as-is
date: 2026-05-21
---

# Codex audit — Bug #247 / GH #1074: WebDAV restore preserves book titles

## Scope

10 changed files (Swift production + Swift Testing + mocks):

- `docs/bugs.md` (tracker IN PROGRESS flip)
- `vreader/Services/BookImporting.swift` (protocol — new `titleOverride` parameter + back-compat extension)
- `vreader/Services/BookImporter.swift` (entry-point normalization + new-row use + dedupe-hit use via `updateBookTitle`)
- `vreader/Services/PersistenceActor.swift` (protocol + impl: `updateBookTitle(fingerprintKey:title:author:)`)
- `vreader/Services/Backup/BookFileMaterializer.swift` (passes `entry.title` in `reimportLocalFile`)
- `vreader/Services/Backup/BookFileImportFinalizer.swift` (passes `entry.title` in `finalize`)
- `vreaderTests/Services/Backup/BookFileMaterializerTests.swift` (+4 Bug #247 tests)
- `vreaderTests/Services/BookImporterTests.swift` (+6 Bug #247 tests, including the audit-driven overlong-title test)
- `vreaderTests/Services/Mocks/MockBookImporter.swift` (parameter wiring + `importedTitleOverrides` recorder)
- `vreaderTests/Services/Mocks/MockPersistenceActor.swift` (`updateBookTitle` impl + state)

## Round 1

### Findings

| file:line | severity | issue | fix |
|---|---|---|---|
| `vreader/Services/BookImporter.swift:95,175,260`; `vreader/Services/PersistenceActor.swift:184,206`; `vreader/Models/Book.swift:126`; `vreader/Services/MetadataExtractor.swift:20` | Medium | `titleOverride` was trimmed but never normalized to the project's existing 255-character title invariant. On the new-row path, `Book.init` truncates internally, but `PersistenceActor.insertBook` returns the pre-save `BookRecord`, so `ImportResult.title` could diverge from what was actually stored. On the duplicate path, `updateBookTitle` wrote the raw override directly, bypassing `Book.init`'s truncation entirely. Long manifest titles would behave inconsistently between insert vs dedupe and `ImportResult.title` would lie about the persisted state. | Normalize the override once before any await using the same rules as `Book`/`MetadataExtractor` (trim + empty-as-nil + `prefix(255)`); use that normalized value for both `record.title` and `updateBookTitle`. Optionally also apply defense-in-depth normalization in `PersistenceActor.updateBookTitle` itself so future direct callers can't silently bypass the invariant. |

### Resolution

Applied in commits on this branch:

1. **`vreader/Services/BookImporter.swift`** — `trimmedOverride` computation in the entry-point closure now applies the three rules in order: trim → empty-as-nil → `String(trimmed.prefix(255))`. The comment block documents each rule and names the divergence the cap prevents (insert vs dedupe vs `ImportResult.title`).
2. **`vreader/Services/PersistenceActor.swift`** — `updateBookTitle` re-applies the same trim + 255 cap as defense in depth. It also throws `PersistenceError.invalidContent("Empty title")` when the trimmed input is empty — programmer-error guard for any future direct caller (the BookImporter live caller already filters empty-after-trim to nil so this is unreachable from the current path).
3. **`vreaderTests/Services/Mocks/MockPersistenceActor.swift`** — mirrors the production normalization so mock-based tests see identical behavior to real SwiftData.
4. **New test** `importFile_overlongTitleOverride_truncatedTo255()` in `BookImporterTests.swift`: 600-char override, asserts `result.title` AND the persisted `Book.title` are both exactly 255 chars.

## Round 2 (verification)

Re-audited the patched diff against all of round 1's questions plus the original 10-point audit checklist:

- Normalization correct in all 3 places (BookImporter, PersistenceActor, MockPersistenceActor)
- `String(trimmed.prefix(255))` matches the existing `Book.init:128` pattern; Swift `Character` semantics preserve multi-byte grapheme clusters (CJK + emoji + combining characters all safe — the cap is on Character count, not byte count)
- No new production failure mode from `PersistenceError.invalidContent`: BookImporter caller filters empty-after-trim to nil before calling, so the throw is unreachable on the live path. Future direct callers benefit from the explicit guard.
- `author: nil` passthrough on the duplicate path remains correct — `book.author` is left untouched.
- `lastOpenedAt`, `fileState`, `blobPath`, `originalExtension`, `addedAt` all preserved across `updateBookTitle` (only `title` + optional `author` mutate).
- No other call sites pass `importFile(.restore)` without a title override. `LazyDownloadFinalizer` intentionally bypasses `BookImporter` (it operates on existing `.remoteOnly` rows; title is not its concern).
- `BookPersisting` conformer set: `PersistenceActor` (production) + `MockPersistenceActor` (tests). No third-party conformer broken by widening the protocol.

### Findings

**None.**

## Summary

**Final verdict: ship-as-is.**

Codex thread `019e472f-670b-7082-96c0-5e1c16aca6a3`, 2 rounds. Round 1 caught 1 Medium (title-length normalization gap). Round 2 clean. Test gate green: `xcodebuild test` runs the targeted 35 Bug #247 + adjacent tests in 0.076s, all pass. The fix solves the user-reported symptom (TXT/MD/PDF book titles after WebDAV restore) and threads cleanly through both production restore paths (`BookFileMaterializer.reimportLocalFile` for already-local files, `BookFileImportFinalizer.finalize` for freshly downloaded blobs).

EPUB / AZW3 / MOBI / PRC are also covered by the same code path — those formats embed titles in their content, so the extractor's title agrees with the manifest title at backup time, and the override is identical to what `Book.init` would have stored anyway. No regression risk.
