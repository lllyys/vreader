---
branch: feat/feature-91-wi-8b-book-content-adapter
threadId: 019e92c8-b107-7221-87ce-6bf43575c6dc
rounds: 3
final_verdict: ship-as-is
date: 2026-06-04
---

# Codex Audit — Feature #91 WI-8b (slice 2: BookContentProvider production path)

Gate-4 implementation audit (rule 47). Independent Codex runner via
`scripts/run-codex.sh -e high` (author/auditor separation, rule 48; rule-53
stdin-isolated watchdog).

## Scope

WI-8b slice 2 — the production `BookContentProvider` the get_book_content tool
(WI-6c) depends on:

- `vreader/Services/AI/Tools/ClosedBookTextExtractor.swift` (new) — off-actor
  file→text per format (EPUB via EPUBParser spine + stripHTML; TXT/MD via the
  canonical decoder; PDF via PDFKit).
- `vreader/Services/AI/Tools/BookContentProviderAdapter.swift` (new) — title
  resolution via `LibraryPersisting` (notFound/found/ambiguous-with-author) +
  extraction; `BookContentInfo.format` derived from the key.
- `vreader/Models/ImportedBookFileURL.swift` (new) — the single source of truth
  for the imported-book sandbox URL; `LibraryBookItem.resolvedFileURL` delegates.
- Tests: `ClosedBookTextExtractorTests` + `BookContentProviderAdapterTests`.

## Round 1 — findings (threadId 019e92c8-b107-7221-87ce-6bf43575c6dc)

| File:line | Severity | Issue | Resolution |
|---|---|---|---|
| ClosedBookTextExtractor.swift `extractPlainText` | **Medium** | A partial decoder (detect-once + UTF-8) — NOT the reader's `TXTService.decodeForDisplayAndSearch` path (UTF-16 BOM / GBK/Big5/Shift_JIS/…) — so it could misdecode non-UTF-8 TXT/MD books the reader opens fine. | **Fixed.** Now decodes via `TXTService.decodeForDisplayAndSearch(data)` (UTF-8 last-resort fallback) — one decoder shared with the reader/search. |
| ClosedBookTextExtractorTests.swift | **Medium** | The TXT test was UTF-8-only. | **Fixed.** `decodesNonUTF8` writes a UTF-16(BOM) temp file and asserts the decode (exact-string in round 2). |
| ClosedBookTextExtractor.swift `importedFileURL` | Low | A 4th copy of the ImportedBooks path convention (drift risk → false file-not-found). | **Fixed.** Extracted `ImportedBookFileURL`; `LibraryBookItem.resolvedFileURL` + the adapter both delegate; the duplicate removed. |
| BookContentProviderAdapterTests.swift | Low | Matrix incomplete (no fetch-throws, no format-drift, no non-local). | **Fixed.** `fetchFailureNotFound`, `formatFromKeyAndLocalityPropagation` (drifted `format` column → format from the key; `.remoteOnly` → `isReadable == false`). |

## Round 2 — verification (threadId 019e92de-c56b-7010-8eaf-ce5815d4372a)

Items 1, 3, 4 **RESOLVED**. Item 2 partial (the UTF-16 test used `contains`). One
**new Medium**: `extractText` resolved the PRIMARY extension only (`.txt`/`.md`),
but restore/lazy-download can materialize TXT/MD under their ORIGINAL extension
(`.text`/`.markdown`) → file-not-found for a readable book. **Both fixed.**
`ImportedBookFileURL.resolveExisting` tries each `BookFormat.fileExtensions`
candidate and returns the one that exists on disk (primary fallback); `extractText`
uses it. The synchronous no-I/O `resolve()` (the `resolvedFileURL` contract) is
unchanged. The UTF-16 test now asserts the exact trimmed string + no `\u{FFFD}`.
Test `resolveExistingTriesCandidateExtensions` writes a real `.text` file and
asserts the `.text` path is returned.

## Round 3 — verification (threadId 019e92f2-db1c-7081-aaa4-ee48ffd2d2cb)

**RESOLVED.** No new issues.

## Verdict

**ship-as-is.** Zero open Critical/High/Medium after round 3. Test gate green:
`ClosedBookTextExtractorTests` (TXT/MD UTF-8 + non-UTF-8 exact decode, unsupported/
missing-file throws, the shared sandbox-URL convention + the `.text` original-
extension resolution) + `BookContentProviderAdapterTests` (found/notFound/blank/
ambiguous-with-author, fetch-failure → notFound, key-derived format under a drifted
column, `.remoteOnly` isReadable propagation, malformed-key throw). EPUB/PDF
extraction is device-verified at the feature's final acceptance pass.

The remaining WI-8b work (the `LibrarySearchBackend` adapter + the registry builder
+ the `AIChatViewModel.sendMessage` branch + citation suppression + Gate-5 device
verification) completes Feature #91 to `DONE`/`VERIFIED`.
