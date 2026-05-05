---
branch: fix/issue-236-epub-cover-redundant-prefix-href
threadId: 019df64c-999a-7ee2-8b05-3e09765766e7
rounds: 2
final_verdict: ship-as-is
date: 2026-05-05
---

# Codex audit log — Bug #122 fix (GH #236)

## Round 1 — initial findings

| File | Line | Severity | Issue | Resolution |
|------|------|----------|-------|------------|
| `vreader/Services/MetadataExtractor.swift` | 202 | Medium | Basename fallback was archive-wide and returned the first decodable match in central-directory order. If a same-basename file existed both in the OPF tree (e.g. `OEBPS/Images/cover.jpg`) and outside it (e.g. `backup/cover.jpg`), the wrong one could win silently. | Fixed: `coverPathCandidates` now ranks basename matches by OPF-dir proximity. Entries whose path starts with `<opfDirPath>/` are emitted before entries outside the OPF tree; within each tier, archive order is preserved. Empty `opfDirPath` treats every entry as inside-OPF, so ordering degrades gracefully when the OPF lives at archive root. |
| `vreaderTests/Services/MetadataExtractorTests.swift` | 86 | Low | New tests only verified the pure candidate generator; didn't exercise the actual `extractCoverImage` regression path for bug #122. Failures in ZIP probing order, case-sensitive `entry(forPath:)` lookup, or `UIImage(data:)` validation across the fallback chain would not surface. | Fixed: added `extractCoverImage_redundantPrefixHref` end-to-end test in `vreaderTests/Services/EPUB/EPUBMetadataExtractorTests.swift` using the existing `createMinimalEPUB` + `buildZIP` helpers. Builds a synthetic EPUB matching the "道诡异仙" repro shape (OPF at `OEBPS/content.opf`, `<item href="OEBPS/cover.jpg"/>`, real cover bytes at `OEBPS/Images/cover.jpg`) and asserts `extractCoverImage` returns a non-nil UIImage. Plus a new ranking test in `MetadataExtractorTests.swift` that pins inside-OPF-vs-outside-OPF ordering using `firstIndex(of:)` so the assertion isn't brittle to the spec-path candidate. |

## Round 2 — verification re-pass

Codex confirmed both fixes:

> The spec-compliant path is still tried first, then same-basename image entries under the OPF tree, then same-basename entries outside it, then root-level canonical `cover.*`. That reduces the wrong-image risk without changing the no-regression path for valid EPUBs.

> Now exercises the actual `extractCoverImage` fallback chain end-to-end: OPF at `OEBPS/content.opf`, broken declared `href`, real image only at `OEBPS/Images/cover.jpg`, and success requires the new candidate probing loop rather than a direct hit.

Edge-case checks performed:
- Empty `opfDirPath` — every basename match treated as inside, ordering degrades gracefully.
- Unusual OPF locations — the prefix test is correct for `/`-separated ZIP paths, which is what `ZIPReader` parses and what EPUB packaging expects.
- Backslash paths — would rank as outside-OPF, which is acceptable since EPUB paths are conventionally slash-separated.

## Final verdict

**ship-as-is**

The branch now:
- Solves the reported "道诡异仙" repro shape (redundant-prefix `href`).
- Preserves spec-compliant EPUB behavior (acceptance criterion 2).
- Keeps no-cover degradation clean (acceptance criterion 3).
- Locks in a sane selection policy for same-basename collisions (Codex Round 1 finding).
- Adds the missing end-to-end regression test (Codex Round 1 finding).

32 extractor tests pass: 24 pre-existing + 8 new candidate-generator tests + 1 new end-to-end EPUB regression.
