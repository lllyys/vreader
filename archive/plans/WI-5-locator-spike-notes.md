# WI-5: Locator & Fingerprint Integration Spike - Design Notes

**Date:** 2026-03-05
**Status:** Complete

---

## 1. Summary

Validated locator generation, persistence (JSON round-trip), and restoration for all three formats: EPUB, PDF, and TXT. Built reusable utilities for quote-based recovery as a universal fallback.

## 2. Architecture

### File Layout

```
vreader/
  Utils/
    QuoteRecovery.swift          # Text search with context disambiguation
  Services/Locator/
    LocatorFactory.swift          # Format-specific locator creation
    LocatorRestorer.swift         # Restoration with fallback chains

vreaderTests/
  Utils/
    QuoteRecoveryTests.swift      # 30 tests
  Services/Locator/
    LocatorFactoryTests.swift     # 28 tests
    LocatorRestorerTests.swift    # 28 tests
  Integration/
    LocatorIntegrationTests.swift # 11 end-to-end tests
```

### Restoration Fallback Chains

| Format | Priority 1 | Priority 2 | Priority 3 | Fallback |
|--------|-----------|-----------|-----------|----------|
| EPUB   | CFI (pass-through) | href + progression | Quote recovery | Failed |
| PDF    | Page index | Quote recovery | - | Failed |
| TXT    | charOffsetUTF16 | charRangeStart/End | Quote recovery | Failed |

### Quote Recovery Strategy Cascade

1. Exact unique match -> `.exact` confidence
2. Multiple matches + context disambiguation -> `.contextMatch`
3. Case-insensitive match -> `.fuzzy`
4. Whitespace-normalized match -> `.fuzzy`
5. Not found -> nil (triggers fallback to `.failed`)

## 3. Key Design Decisions

### 3.1 TXT UTF-16 Offsets Are Trusted If In Bounds

The TXT restorer trusts `charOffsetUTF16` if `0 <= offset <= text.utf16.count`. It does **not** verify the text at that offset matches the stored quote. This is intentional:

- **Rationale:** Offset verification would require quote comparison on every restore, adding latency. If the file content hasn't changed (same fingerprint), the offset is correct by definition.
- **When it breaks:** If a file is modified externally but retains the same fingerprint (unlikely — fingerprint is SHA-256 of exact bytes). In practice, if the fingerprint changes, the entire book is treated as a new entity.
- **Future enhancement:** For V2 sync where the same logical book may have slightly different content across devices, add an optional quote-verification step before trusting the offset.

### 3.2 CFI Is a Pass-Through

The EPUB CFI strategy returns immediately without resolving the CFI to a DOM position. Actual CFI resolution requires Readium's runtime, which is not available until WI-6. The restorer confirms CFI presence and delegates resolution to the reader.

### 3.3 Context Window Size

- **Default: 50 characters** before/after for context extraction
- **Default quote length: 30 characters** for cursor-position TXT locators
- These are tunable constants in `LocatorFactory`

### 3.4 Quote Recovery Handles Unicode Correctly

- CJK characters: 1 UTF-16 code unit each, offset math is straightforward
- Emoji (surrogate pairs): 2 UTF-16 code units each, handled correctly via `String.UTF16View`
- Mixed content: All extraction and matching operates on the original `String`, preserving Unicode semantics

## 4. Limitations

### 4.1 No Fuzzy/Levenshtein Matching

Quote recovery currently uses exact substring matching (with case-insensitive and whitespace-normalization fallbacks). It does **not** implement Levenshtein distance or edit-distance matching. This means:

- Minor typo corrections in text will cause quote recovery to fail
- Significant reflow that changes whitespace within quoted text may fail the exact match but succeed via whitespace normalization

**Recommendation for V2:** Add a similarity threshold (e.g., Levenshtein distance <= 3) as a fourth fallback strategy, gated by a flag to avoid false positives.

### 4.2 No Multi-Page PDF Quote Search

PDF quote recovery searches only the provided `pageText` (a single page). It does **not** search across all pages to find the quoted text. This is a deliberate simplification:

- Searching all pages would require extracting text from every page on restore
- For V2, consider a page-range search (e.g., +/- 5 pages from the saved page)

### 4.3 EPUB Quote Recovery Searches a Single Text Blob

The EPUB restorer accepts a `textContent` string for quote recovery. The caller must provide the appropriate text (e.g., from the target spine item or a concatenation of nearby items). The restorer does not know about EPUB structure.

### 4.4 No Anchor Drift Detection

If text is modified but the offset is still in bounds, the restorer silently uses the stale offset. Anchor drift detection (comparing text at restored offset against stored quote) is deferred to reader-specific integration in WI-6+.

## 5. Test Coverage

| Component | Tests | Edge Cases Covered |
|-----------|-------|--------------------|
| QuoteRecovery | 30 | Empty, CJK, emoji, composite emoji, multibyte, context disambiguation |
| LocatorFactory | 28 | All formats, NaN/infinity rejection, UTF-16 boundary, empty source |
| LocatorRestorer | 28 | All fallback chains, boundary pages, offset at text end, empty text |
| Integration | 11 | Full round-trip per format, JSON persistence, CJK, emoji, quote fallback |
| **Total** | **97** | |

## 6. Integration Points for WI-6+

When building readers, integrate as follows:

### EPUB Reader (WI-6)
```swift
// On position change:
let locator = LocatorFactory.epub(
    fingerprint: book.fingerprint,
    href: currentSpineItem.href,
    progression: readiumLocator.locations.progression,
    totalProgression: readiumLocator.locations.totalProgression,
    cfi: readiumLocator.locations.otherLocations["cfi"],
    textQuote: extractQuoteFromDOM(),
    textContextBefore: extractContextBefore(),
    textContextAfter: extractContextAfter()
)

// On reopen:
let result = LocatorRestorer.restoreEPUB(
    locator: savedLocator,
    spineHrefs: publication.readingOrder.map(\.href),
    textContent: extractTextForQuoteSearch()
)
```

### TXT Reader (WI-6A)
```swift
// On position change:
let locator = LocatorFactory.txtPosition(
    fingerprint: book.fingerprint,
    charOffsetUTF16: textView.selectedRange.location,
    totalProgression: calculateProgression(),
    sourceText: decodedSourceText
)

// On reopen:
let result = LocatorRestorer.restoreTXT(
    locator: savedLocator,
    currentText: decodedSourceText
)
// Use result.resolvedUTF16Offset to scroll
```

### PDF Reader (WI-7)
```swift
// On page change:
let locator = LocatorFactory.pdf(
    fingerprint: book.fingerprint,
    page: pdfView.currentPage.pageRef.pageNumber,
    totalProgression: Double(pageIndex) / Double(totalPages),
    textQuote: extractPageText()  // optional
)
```
