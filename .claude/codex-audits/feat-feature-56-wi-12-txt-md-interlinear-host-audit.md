---
branch: feat/feature-56-wi-12-txt-md-interlinear-host
threadId: 019e42df-736a-7a70-9350-0ba6a5623038
rounds: 3
final_verdict: ship-as-is
date: 2026-05-20
---

# Codex Gate-4 audit — feature #56 WI-12a (TXT/MD bilingual host wiring + interlinear renderer foundations)

Author: Claude Opus 4.7 (1M context)
Auditor: Codex MCP, thread 019e42df-736a-7a70-9350-0ba6a5623038
Plan: `dev-docs/plans/20260519-feature-56-bilingual-reading.md` (WI-12 row, split into WI-12a + WI-12b in commit 05f215a)

## Round 1 — initial audit

| # | File:Line | Severity | Issue | Resolution |
|---|---|---|---|---|
| H1 | TXTReaderContainerView+Bilingual.swift:7; MDReaderContainerView+Bilingual.swift:7; TXTReaderContainerView.swift:344; MDReaderContainerView.swift:66 | High | WI-12 does not deliver the plan row it references. The plan says WI-12 includes TXT/MD container consumption of `BilingualTextRenderer` plus display-offset routing for selection/search/highlight/TTS, but these files explicitly defer render injection and the containers still render their old attributed strings. | **Fixed (commit 05f215a)**: re-scoped — plan row WI-12 split into WI-12a (foundational: this PR) + WI-12b (live render injection + display-offset routing). PR title/body re-framed accordingly. |
| H2 | TXTReaderContainerView+Bilingual.swift:84 | High | `makeTextProvider(viewModel:)` is incorrect for paged chapter-mode TXT. It feeds `TXTChapterTextProvider` with `viewModel.textContent`, but in chapter mode `textContent` is only the currently loaded chapter text, while `TXTChapterTextProvider` slices by document-global chapter offsets. | **Fixed in round 1 incorrectly (commit 5cbb78e)** — guarded on `textContent != nil` which was insufficient. **Fixed correctly in round 2 (commit 57eb487)**: explicit mode check `if isChapterMode && !isContinuousMode { return nil }`. Chapter-paged mode is deliberately disabled for WI-12a; WI-12b introduces a loader-backed text provider for that path. |
| M3 | TXTReaderContainerView+Bilingual.swift:126; MDReaderContainerView+Bilingual.swift:83 | Medium | Persisted bilingual-on state is not mirrored into the parent chrome on open. The VM loads `isEnabled` from per-book settings, but `ensureBilingualViewModel()` never publishes an initial `.readerBilingualDidChange`, so reopened books can show the More row/pill in the wrong state. | **Fixed (commit 5cbb78e)**: both TXT and MD extensions now call `vm.postDidChange()` immediately after construction so the parent's `.readerBilingualDidChange` observer sees the loaded-from-persistence state. |
| L4 | BilingualTextRendererTests.swift:153; BilingualDisplaySegmentMapTests.swift:179 | Low | The new tests cover BMP CJK and partial translations, but they do not pin the UTF-16 edge cases this map exists to handle: surrogate pairs/emoji, exact paragraph-separator boundaries, the synthetic leading-newline boundary. | **Fixed (commit 5cbb78e)**: added 4 boundary tests to `BilingualDisplaySegmentMapTests`: exact source-segment boundary semantics, past-display-length clamp, synthetic leading-newline has no source position, non-BMP scalar (emoji surrogate pair) round-trip. Container/integration tests for offset-routing belong to WI-12b. |

Round-1 scope-split rationale: Codex explicitly endorsed the WI-12a/WI-12b split — "Shipping the pure map/renderer is fine, but then this is not WI-12 as defined at plan line 460; it is a prerequisite slice for WI-12. The `displayOffset(forSourceOffset:)` boundary semantics look defensible for selection end-points, and the TXT/MD duplication is acceptable for now."

## Round 2 — verify round-1 fixes

| # | File:Line | Severity | Issue | Resolution |
|---|---|---|---|---|
| R2-H2 | TXTReaderContainerView+Bilingual.swift:104 | High | H2 is not actually resolved. The new guard only requires `viewModel.textContent != nil`, but in chapter-paged TXT `textContent` is chapter-local, not full-book text. `TXTReaderViewModel.swift:376` and `:561` set `textContent = text` on chapter open and navigation. | **Fixed (commit 57eb487)**: explicit `if isChapterMode && !isContinuousMode { return nil }` mode check. Docstring expanded with a mode→textContent semantics table. |

Codex confirmed H1 (resolved by the WI-12a/12b split), M3, and L4 are clean in round 2.

## Round 3 — verify the round-2 H2 fix

> "No further findings.
>
> The new guard in `TXTReaderContainerView+Bilingual.swift:111` is correct against the actual `TXTReaderViewModel` write sites:
>
> - Legacy small-file path writes full-book text at `TXTReaderViewModel.swift:302`.
> - Continuous chaptered mode writes full-book text at `TXTReaderViewModel.swift:500`.
> - Chapter-paged mode writes chapter-local text at `TXTReaderViewModel.swift:376` and again on navigation at `:561`.
>
> I do not see another path that sets `textContent` to chapter-local text beyond those chapter-paged assignments. With the explicit `isChapterMode && !isContinuousMode` rejection, `TXTChapterTextProvider` now only constructs in the two safe full-book modes. No remaining Critical/High/Medium findings from the prior rounds."

## Summary verdict

3 rounds, 4 findings (1 H1 + 1 H2 + 1 M3 + 1 L4) → all resolved. **Verdict: ship-as-is.**

The PR ships WI-12a foundational: pure `BilingualDisplaySegmentMap` + `BilingualTextRenderer` + TXT/MD host wiring (lazy VM, setup sheet, More-menu toggle observer, chrome-pill mirror). The follow-up WI-12b will deliver the live render-injection into the TXT/MD UITextView's `NSAttributedString` plus the offset-routing through every TXT/MD display-offset touchpoint (selection / search-highlight nav / persisted-highlight hit-test / TTS auto-scroll) and add the loader-backed text provider that re-enables bilingual for chapter-paged TXT.
