---
branch: feat/feature-65-wi-1-summarize-body-reskin
threadId: 019e3ba8-23a8-7a22-9a41-121eed0194ea
rounds: 2
final_verdict: ship-as-is
date: 2026-05-18
---

# Codex audit — feature #65 WI-1 (AI sheet Summarize tab-body re-skin)

Gate-4 implementation audit of WI-1: the re-skinned Summarize tab body
(`AISummaryCard`, `AISummaryTabView`, the `AIReaderPanel` swap, and the
two new test files).

## Round 1 — 3 Medium findings (0 Critical / 0 High)

| # | file:line | severity | issue | resolution |
|---|---|---|---|---|
| 1 | AISummaryTabView.swift | Medium | `runSummarize()` launched a fresh `Task` on every call with no in-flight guard — rapid Regenerate taps could issue duplicate AI requests / let an old response overwrite a newer one. | Fixed — `runSummarize()` is now `internal` with an exhaustive `switch viewModel.state` early-return: `.loading` / `.streaming` no-op, the other four cases proceed. |
| 2 | AISummaryCardTests.swift | Medium | The card tests were wiring-only / tautological — they called stored closures directly and inspected stored properties; `shareCarriesExactSummaryText()` echoed its own input and exercised no production code. | Fixed — the tautological tests were dropped; replaced with real composition tests that materialize the production `body` across the 5 `ReaderThemeV2` cases × representative inputs (empty / long / CJK). |
| 3 | AISummaryTabViewTests.swift | Medium | The tab-view tests covered only the `section(for:)` mapper — none of WI-1's actual production behavior. | Fixed — the mapper tests are kept; added 4 `@MainActor` behavior tests against a stub-backed `AIAssistantViewModel`: `runSummarize()` from `.idle` starts a request; `runSummarize()` while `.loading` / `.streaming` is a verified no-op; `shareText` equals `viewModel.responseText` including CJK. |

Clean-checked areas (round 1): the `AISummaryCard` / `AISummaryTabView`
signatures match the plan §3; all 7 `AIAssistantState` routes are
preserved through the `AIReaderPanel` swap; the scope chips / Save chip
/ suggested-questions list are correctly omitted (not faked); the
share-sheet wiring uses an `Identifiable` item; the expected
accessibility identifiers survive; no orphaned summarize subviews;
`AISummaryTabView` is within the ~300-line guideline; the new view
files use `#if canImport(UIKit)` and the tests use Swift Testing.

## Round 2 — clean

Codex re-verified the three fixes on the updated disk state: all three
findings resolved, no new Critical/High/Medium finding introduced. The
`runSummarize()` guard is compile-time exhaustive; `shareText`
centralizes the share payload; the rewritten card tests force
production `body` composition; the tab-view behavior tests exercise the
real summarize path against a stub-backed VM via a concurrency-sound
`GatedAIProvider` / `GateState` actor harness.

## Verdict

**ship-as-is.** Two audit rounds; round 2 clean — zero open
Critical/High/Medium findings.

## Test-gate note

The WI-1 suites (`AISummaryCardTests` + `AISummaryTabViewTests`, 19
tests) pass. The full `-only-testing:vreaderTests` gate currently exits
non-zero due to two pre-existing failures unrelated to WI-1 — a
`DictionaryLookupTests` test-host crash (via the system
`UIReferenceLibraryViewController`) and a `SelectiveRestoreCoordinatorTests`
cross-test `NotificationCenter`-capture state-leak — both reproduced
identically on a clean `main` baseline with WI-1 fully stashed. WI-1's
five files are all AI-sheet files; none of the failing tests touch
them. These pre-existing failures are flagged for triage as separate
bugs.
