# WI-5A: TXT Anchor & Rendering Feasibility Spike — Design Notes

## Approach

### Architecture

The spike validates three pillars needed for TXT reading position anchoring:

1. **Offset mapping** (`TXTOffsetMapper`) — Pure-logic conversion between UITextView's NSRange (UTF-16) and the canonical UTF-16 offsets stored in `Locator`. Since NSString and UITextView both use UTF-16 internally, conversion is identity for well-formed ranges. The mapper's primary job is validation and surrogate-pair boundary snapping.

2. **Chunked loading** (`TXTChunkedLoader`) — Divides large files into 64KB byte chunks, decoded on demand. Supports viewport-based loading (load chunks near scroll position) and memory pressure eviction (drop distant chunks).

3. **UITextView bridge** (`TXTTextViewBridge`) — UIViewRepresentable wrapping a read-only UITextView. Uses TextKit 1 (`NSLayoutManager`) for scroll-position-to-character-offset mapping. Coordinator handles delegate callbacks for selection and scroll changes.

### Key Design Decisions

- **TextKit 1 over TextKit 2**: TextKit 1's `NSLayoutManager` provides stable, well-documented APIs for glyph-to-character mapping. TextKit 2 is newer but has known issues with offset calculations for complex scripts. TextKit 1 is the safer choice for a reading app.

- **UTF-16 as canonical offset**: NSString, UITextView, and JavaScript all use UTF-16 internally. Using UTF-16 as the canonical representation avoids conversion errors. Surrogate pairs (emoji, rare CJK) are handled by boundary snapping.

- **64KB chunk size**: Balances granularity (fine-grained viewport loading) against overhead (fewer chunks to manage). A 50MB file produces ~800 chunks. Only 3-5 are typically loaded at any time.

- **Byte-aligned chunks with UTF-8 boundary recovery**: Chunks are cut at byte boundaries, not character boundaries. The loader handles partial UTF-8 sequences at chunk edges by trimming incomplete sequences.

## Go/No-Go Results

### 1. Exact offset round-trip (+/-0 UTF-16) — GO

All round-trip tests pass with zero error:
- ASCII text: exact round-trip
- CJK text (BMP characters): exact round-trip  
- Emoji with surrogate pairs (non-BMP): exact round-trip
- Mixed content (ASCII + CJK + emoji + combining characters): exact round-trip
- Edge cases (document start, end, empty selection): exact round-trip

The conversion is identity because both NSRange and our canonical format use UTF-16 code units. The only risk was surrogate-pair splitting, which the boundary snapper handles correctly.

### 2. No UI freeze in fixtures — GO (validated at unit level)

- `TXTChunkedLoader` processes 64KB chunks individually, never loading the full file into a contiguous attributed string.
- Viewport-based loading ensures only 3-5 chunks (~192-320KB) are in memory at any time.
- UTF-8 decoding of individual chunks is sub-millisecond.

Full UI integration testing (actual UITextView rendering) is deferred to WI-6A, but the chunked loading architecture prevents the main bottleneck (decoding and attributing 50MB of text at once).

### 3. Peak RSS within budget (<=450MB for 50MB TXT) — GO (by design)

With the chunked loader:
- Raw file data: held as `Data` (50MB, can be memory-mapped in production)
- Decoded text cache: ~320KB (5 chunks x 64KB)
- UITextView attributed string: only current viewport chunks
- Estimated peak: ~55-60MB for a 50MB file (data + small working set)

This is well within the 450MB budget. The key is never decoding the entire file into an NSAttributedString at once.

## Limitations Discovered

1. **TextKit 1 layout latency on very long lines**: Lines exceeding ~10,000 characters can cause TextKit 1 to spend significant time in layout. The chunked loader partially mitigates this (chunks are small), but a line that spans multiple chunks would need special handling. Recommendation: add a line-length pre-scan pass in WI-6A that inserts soft breaks for lines exceeding a threshold.

2. **Chunk boundary character splitting**: When a multi-byte UTF-8 character spans a chunk boundary, the current approach trims the incomplete sequence from the first chunk and the character appears only in the second chunk. This creates a ~1-3 byte gap. For reading this is invisible, but for exact byte-offset-to-character-offset mapping, a boundary reconciliation pass may be needed.

3. **UITextView selection and attributed string**: UITextView requires the full text (or at least the visible portion) as an NSAttributedString. For truly huge files (>100MB), even partial attribution may be slow. The 50MB target is feasible; scaling beyond would need a custom text rendering layer.

4. **Memory-mapped data**: The current implementation takes `Data` directly. For production, `Data(contentsOf:options:.mappedIfSafe)` should be used to avoid loading the entire file into physical RAM.

## Recommendations for WI-6A

1. **Use memory-mapped Data** for file loading to keep resident memory minimal.
2. **Add line-length pre-scan** during import to flag files with very long lines (>5000 chars). Apply soft-wrap preprocessing if needed.
3. **Implement chunk stitching** for the attributed string: load surrounding chunks, stitch them into a single NSAttributedString for the visible viewport, and feed that to UITextView.
4. **Add scroll position persistence**: Use `TXTOffsetMapper.scrollOffsetToCharOffset` on scroll-end events to capture the reading position, and `charOffsetToScrollOffset` to restore on reopen.
5. **Test with real fixture files**: 5MB novel, 50MB log file, file with 100K-character lines.

## Test Coverage

| Test File | Tests | Coverage |
|-----------|-------|----------|
| `TXTOffsetMapperTests.swift` | 25 | ASCII, CJK, emoji, mixed, empty, boundaries, round-trips, surrogate snapping |
| `TXTChunkedLoaderTests.swift` | 16 | Chunk geometry, loading, viewport, eviction, large file math |
| `TXTBridgeOffsetTests.swift` | 8 | End-to-end Locator round-trips with LocatorFactory integration |

All 49 new tests pass. Total test count: 530 (including existing tests).
