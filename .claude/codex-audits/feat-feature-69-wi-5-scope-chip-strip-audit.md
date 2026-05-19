---
branch: feat/feature-69-wi-5-scope-chip-strip
threadId: 019e3e6f-a918-7561-ad9e-3037366c56c7
rounds: 2
final_verdict: ship-as-is
date: 2026-05-19
---

# Gate-4 Implementation Audit — Feature #69 WI-5 (final WI)

WI-5: the AI Summarize scope chip strip + `aiSheet` threading — the
final WI that brings feature #69 to `DONE`.

## Files audited

- `vreader/Views/Reader/AISummaryTabView.swift` (modified)
- `vreader/Views/Reader/AISummaryScopeChipStrip.swift` (new — split out)
- `vreader/Views/Reader/AIReaderPanel.swift` (modified)
- `vreader/Views/Reader/ReaderContainerView+Sheets.swift` (modified — `aiSheet` only)
- `vreaderTests/Views/Reader/AISummaryTabViewScopeTests.swift` (new)
- `vreaderTests/Views/Reader/AISummaryTabViewTests.swift` (test migration)

## Round 1 — findings

| file:line | severity | issue | resolution |
|---|---|---|---|
| `ReaderContainerView+Sheets.swift:280` | High | Codex flagged that the Chapter-scope wiring assumes `tocEntries` is populated, and MD has `TOCBuilder.forMD` char-offset TOC — so MD's first AI-sheet open silently degrades Chapter to Section. | **Withdrawn after pushback.** The audited plan (§2.0 fact 2, §9, Gate-2 round-1 finding [2]) deliberately scopes real Chapter/Book-so-far to **TXT only** — MD's locator carries `renderedText` offsets while its loaded text + TOC are raw-source offsets, a coordinate-space mismatch. Even with `TOCBuilder.forMD` offsets, slicing MD by them is wrong; MD's Section-degrade is by design. For TXT (the only format with real Chapter bounds) `ReaderContainerView.swift:339-342` builds TOC eagerly at reader load, so `aiSheet` always has `tocEntries` for TXT. `ReaderContainerView.swift` is also a concurrent sibling agent's file (#54) — outside this WI's write set. Codex withdrew the finding: "Your pushback is correct against the audited plan … non-TXT degrade-to-Section is the designed behavior, not a regression." |
| `AIReaderPanel.swift:70` | Low | `fullTextContent` was made optional with a `?? textContent` fallback — a future caller could omit full text and silently get snippet-based scoped summaries. | **Fixed** — `fullTextContent` is now a required `let String` (and `chapterBounds` a `let`). The single caller (`aiSheet`) passes it explicitly; no previews / other callers / tests break. The `?? textContent` fallback removed. |
| `AISummaryTabViewScopeTests.swift:97` | Low | The WI-5 suite asserted helper methods but never pinned the `aiSummaryScopeChip.*` accessibility IDs the XCUITest depends on. | **Fixed** — added `scopeChipIdentifiersAreStableAndDistinct` (pins the exact IDs + distinctness) and `chipStripIdentifierMatchesTabViewReExport` (pins the tab-view re-export agrees with the chip-strip view post-split). |
| `AISummaryTabView.swift:30` | Low | The file grew to 414 lines, over the ~300 guideline. | **Fixed (partial, accepted).** Extracted the chip strip into `AISummaryScopeChipStrip.swift` (88 lines); `AISummaryTabView.swift` dropped to 371. The remaining overage is the six pre-existing feature-#65 state-section subviews — splitting those would be a drive-by refactor of #65's code in WI-5's PR. Codex accepted: "371 lines … is acceptable for this PR … the remaining overage is inherited feature-#65 state-section code." |

`scopeChipFillColor` (`0.06` dark) vs the existing `chipFillColor`
(`0.07`) — Codex confirmed keeping both is justified: the design's
scope chips and the summary-card `chipBtn` use different washes.

## Round 2 — verification

Codex re-reviewed all four files: "No new Critical/High/Medium
findings. The prior High on MD is withdrawn … The fixes are in place …
`fullTextContent` now requires `String` … closes the contract hole …
The new tests do pin the exact accessibility IDs and the post-split
identifier agreement."

## Verdict

**ship-as-is.** Zero open Critical/High/Medium findings after 2
rounds. 130 tests across 10 AI/summarize suites pass; the app builds.

## Note — full-suite SIGSEGV (environmental, not a #69 regression)

`xcodebuild test -only-testing:vreaderTests` (the whole suite) hits a
SIGSEGV-at-launch flake that taints the run. Confirmed **identical on
the clean WI-4 baseline** (`42908c4`, no WI-5 changes) — `5633x "Test
crashed with signal segv"`, zero real assertion failures. It is a
pre-existing test-runner/environment flake unrelated to feature #69.
Every targeted run of the affected suites passes deterministically
(130 tests, 10 suites). Recorded here for transparency.
