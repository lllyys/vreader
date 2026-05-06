---
branch: fix/issue-26-encoding-offset-mismatch
threadId: 019dfe00-009e-7da1-a67d-f62b1a5cf4b8
rounds: 3
final_verdict: ship-as-is
date: 2026-05-07
---

# Codex audit — bug #99 cause #2 (encoding offset mismatch)

## Round 1

**Findings**:

| File | Severity | Issue | Resolution |
|---|---|---|---|
| `ReaderSearchCoordinator.swift:66-83` + `SearchIndexStore.swift` | High | Stale FTS5 indexes from old decode path not invalidated. On upgrade, books indexed under the old `decodeText`-only search path are treated as `alreadyIndexed` → search-hit offsets stay wrong until manual removal. | **Fixed in round 2**: `decode_version` column added to `search_metadata` (idempotent ALTER). `currentDecodeVersion = "2"` constant. `indexBook` writes the version. New `requiresReindex(fingerprintKey:)` API. `ReaderSearchCoordinator` checks for TXT format and force-removes + reindexes when stale. |
| `TXTService.swift:123-131` + cache wrapper | Medium | Chapter-index cache validation ignored encoding. Cached UTF-16 offsets reused based only on byte count + mtime → stale offsets paired with freshly decoded loader string. | **Fixed in round 2**: cache hit now requires `cachedIndex.detectedEncoding == encodingName`. Mismatch → fresh decode + chapter-index build. |
| `TXTServiceTests.swift:239-283` (GBK regression test) | Low | Structural assertion `segmentBaseSum <= displayUTF16` could pass on a real mismatch if string lengths happened to align. | **Fixed in round 2**: stronger assertion walks each extractor segment, verifies the substring at its claimed UTF-16 offset in the display string EXACTLY equals the segment's `text`. |
| `TXTServiceTests.swift:286-295` (fallback test) | Low | Latin-1 sample is handled by sample-hint path → fallback branch never exercised. | **Fixed in round 3**: extracted `decodeWithHint(_:hintName:)` test seam. New tests pass `hintName: "UTF-16"` over UTF-8 data → forced fallback to `decodeText` + assertion on returned encoding name. |

**Verdict round 1**: `block-recommended`.

## Round 2

After applying round-1 fixes, Codex closed High + Medium + first Low. Remaining Low: fallback branch test still didn't prove the branch ran (Latin-1 data could still pass through sample-hint).

**Verdict round 2**: `follow-up-recommended`.

## Round 3

After adding the `decodeWithHint` test seam:

> The remaining low finding is closed. `decodeForDisplayAndSearch` is now a thin wrapper over `detectEncodingFromSample` + `decodeWithHint`. The new seam in the test file explicitly covers both branches:
> - forced fallback when the injected hint cannot decode the bytes
> - direct success when the hint matches
>
> I do not see a new issue introduced by the seam itself. It is a small pure helper, production callers still enter through the same public path, and the earlier findings remain closed.

**Verdict round 3**: `ship-as-is`.

## Other audit dimensions confirmed

- Cache-encoding check doesn't materially hurt hit rate — only rejects when freshly-detected encoding differs from cached.
- TXT-only reindex gate is appropriately scoped (other formats unaffected by the decode change).
- `indexBook`'s `INSERT OR REPLACE` drops `content_hash` on rewrite, but no live caller depends on `contentHashMatches` today — pre-existing latent code-smell, not regressed by this PR.
- Priority order `sample hint → decodeText` is the right shape — preserves display's existing sample-first behavior while making search conform.

## Summary

Bug #99 cause #2 fixed:
- `TXTService.decodeForDisplayAndSearch(_:)` is the single source of truth for "decode TXT bytes to (String, encoding)" — used by display (`open`, `openChapterBased`) AND search (`TXTTextExtractor.decodeFile`).
- `decodeWithHint(_:hintName:)` test seam exposes the sample-hint vs fallback branches independently.
- Migration: `search_metadata.decode_version` column + idempotent ALTER + `requiresReindex` API + TXT-only invalidation hook in `ReaderSearchCoordinator`.
- Cache: chapter-index reuse requires encoding-name match.

5 files changed:
- `vreader/Services/TXT/TXTService.swift`
- `vreader/Services/Search/TXTTextExtractor.swift`
- `vreader/Services/Search/SearchIndexStore.swift`
- `vreader/Views/Reader/ReaderSearchCoordinator.swift`
- `vreaderTests/Services/TXT/TXTServiceTests.swift` (4 new tests)

Bug #99 row flips from PARTIALLY FIXED → FIXED. All 3 causes now closed (cause #3 in PR #263, cause #1 in PR #328, cause #2 in this PR).
