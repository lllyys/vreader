---
branch: fix/issue-1629-r2-sentence-granularity
threadId: 019eb4ca-e779-7f93-9478-419f6ba7fbcf
rounds: 3
final_verdict: ship-as-is
date: 2026-06-11
---

# Codex Gate-4 audit — Bug #344 (sentence granularity honored / designed dimmed fallback)

Runner: `scripts/run-codex.sh` (codex exec, gpt-5.4, read-only sandbox).
Sessions: r1 `019eb4c2-098d-7472-b4af-ef69bb6e2829`, r2
`019eb4c7-5757-73f1-926d-82e1ef41ebc5`, r3
`019eb4ca-e779-7f93-9478-419f6ba7fbcf`.

## Round 1 — needs-fixes

| Finding | Severity | Resolution |
|---|---|---|
| `BilingualDisplayPipeline.swift:83` + `BilingualParagraphRanges.swift:109` + `ChapterSegmenter.swift:32` — the new paragraph-path count guard turns a LATENT blank-line divergence (display scanner: any whitespace-only line is blank, incl. U+3000/U+00A0; translation splitter: only `\n[ \t]*\n+`) into deterministic source-only painting on CJK content | Medium | FIXED (20d64bef): `paragraphs(in:)` now derives from the SAME `BilingualParagraphRanges.scan` ranges (substring + trim, no filter — ranges contain non-whitespace by construction); dead `splitOnRegex` removed; 8-input parity tests (U+3000/U+00A0/CRLF blank lines) + ideographic-space split test |

Round 1 also verified clean: `sentenceRanges`↔`sentences` equivalence for
CRLF/U+00A0/U+3000; Swift 6 memberwise-init correctness; `setGranularity`
clears the only granularity-shaped cache and `resetTriggerState()` covers
the rest.

## Round 2 — needs-fixes

| Finding | Severity | Resolution |
|---|---|---|
| The scan-derived `paragraphs(in:)` returned raw `\r\n`/`\r` soft wraps inside paragraph text (the deleted implementation normalized to `\n`; prompts + cached rows carried `\n`) | Low (nit) | FIXED (5cc629fc): normalization restored on the extracted substring before trimming; content tests `a\r\nb → a\nb` + mixed CR/CRLF |

Round 2 confirmed the round-1 Medium resolved and the count-dependent
consumers (`ChapterTranslationService`, `BookTranslationCoordinator`
`cachedUnits`, EPUB count guards) structurally sound.

## Round 3 — clean

"I did not find any new behavioral risk in this delta… only returned
paragraph text is normalized; the underlying scan ranges remain
untouched." VERDICT: clean.

## Summary

3 rounds, 2 findings (1 Medium, 1 Low), all fixed. Suites green:
`ChapterSegmenterTests` (incl. 10-input sentence parity + 8-input
paragraph parity), `BilingualDisplayPipelineTests` (3 sentence-mode
tests incl. the mismatch→source-only guard),
`BilingualSetupSheetTests` (dim state), `PrefetcherGranularityGateTests`,
`ChapterTranslationServiceTests`. Device-verified pre-merge: TXT sheet
offers Sentence selectable; EPUB sheet renders the designed 45%-dimmed
Sentence + footnote; the sentence shape flows end-to-end (stale-count
45→49 log on the live TXT book). Ship as-is.
