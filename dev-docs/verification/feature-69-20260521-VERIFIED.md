---
kind: feature
id: 69
status_target: VERIFIED
commit_sha: 48c2b796be46040b2a182bb9984785e9406bd906
app_version: 3.38.42 (build 617)
date: 2026-05-21
verifier: claude
device_or_simulator: iPhone 17 Pro Simulator
os_version: iOS 26.x
build_configuration: Debug
backend: OpenRouter (openai/gpt-4o-mini) via DebugBridge provider?action=add; real network responses
result: partial
---

## Summary

Gate-5b verification of feature #69 — **attempt 3**, re-running on
v3.38.42 after Bug #255 / GH #1112 (the DebugBridge
`vreader-debug://ai?action=summarize&scope=<section|chapter|book>`
command) shipped. That command fires the Summarize action the
**presented** AI sheet exposes through the same `runSummarize` path the
chrome button takes, with the selected scope, driven from the host
shell. It was the prerequisite the 2026-05-21 attempt-2
(`feature-69-20260521.md`, `result: partial`) was blocked on.

Goal this round: unblock criteria **7 / 8** (the end-to-end on-device
acceptance — open AI sheet, select a scope chip, observe a
scope-appropriate summary render).

**Result: `partial` — the scope-selector mechanism is now fully proven
end-to-end, but the *populated Book-so-far* case (criterion 8 as
literally worded) is not observable on this host.**

- **Criterion 7 (Chapter chip → chapter-scoped summary renders):
  PASS.** `ai?action=summarize&scope=chapter` switched the selected
  chip to Chapter (accent), showed the loading state ("Generating
  summary…"), then rendered a `.complete` SUMMARY card with a real
  `openai/gpt-4o-mini` Chapter-scoped War-and-Peace summary.
- **Scope-changes-the-summary intent: PROVEN.** Section vs Chapter at
  the same reading position produce **visibly different populated
  summaries** — Section returns scene-level detail ("In Chapter 1 …
  Anna Pavlovna Scherer … refers to him as 'Antichrist' … In Chapter
  2, Anna's drawing room fills with …"), Chapter returns a higher-level
  thematic overview ("a historical novel … intertwines the lives of
  several characters … themes of fate, free will …"). This demonstrates
  the chip strip functionally changes the extraction extent through the
  real `runSummarize` → `AIContextExtractor` path.
- **Criterion 8 (Book-so-far ≠ Section, *populated*): NOT
  observable.** The Book-so-far chip selects (accent) and fires
  correctly, but at the only reachable reading position (offset 0 —
  the title page), `extractBookSoFar` correctly returns `""`
  (`AIContextExtractor.swift:274` — `guard offset > 0 else { return ""
  }`), which surfaces as the "Could not extract text context for AI."
  card. That is **correct boundary behavior** (nothing read "so far" at
  the very start), not a defect. To observe a *populated* Book-so-far
  summary differing from Section, the reading position must be advanced
  past the start — and there is no CU-free way to do that on this host:
  `open?bookId=…&position=N` parses the offset but the host-side TXT
  seek is a deferred follow-up (the bridge's `open` resolves the
  position via `DebugPositionResolver` but does not yet move the reader
  — confirmed: snapshot `position` stayed `null` after
  `open?…&position=800`), and CU paging/scrolling is structurally
  unavailable (`mcp__computer-use__screenshot` → `CU display
  unavailable`). The four DEBUG fixtures all seed at offset 0.

Per `SCHEMA.md` partial semantics, criterion 8 not being observed in
its populated form → `result: partial`; the row stays `DONE` (not
`VERIFIED`).

## Acceptance criteria

| # | Criterion | Method this round | Observed | Verdict |
|---|---|---|---|---|
| 1 | `SummaryScope` enum (3 cases + display names) | Unit (`SummaryScopeTests`) — shipped green in v3.38.42 merge gate | No regression | PASS |
| 2 | `SummaryScopeResolver` (locator → ChapterBounds; preamble; empty/non-anchored TOC → nil) | Unit (`SummaryScopeResolverTests`) | No regression | PASS |
| 3 | `AIContextExtractor` scoped extraction (.section legacy; .chapter slice; .bookSoFar prefix; surrogate-safe) | Unit (`AIContextExtractorScopedTests` + `AIContextExtractorTests`) + observed: .section and .chapter produce different populated summaries; .bookSoFar at offset 0 returns "" per `:274` | No regression; runtime behavior matches | PASS |
| 4 | `AIAssistantViewModel` carries `selectedScope`/`setScope`; `summarize` forwards scope/bounds/fullText | Unit (`AIAssistantViewModelScopeTests`) | No regression | PASS |
| 5 | `AISummaryTabView` renders chip strip; chip-tap = selection-only (no auto-fire); `runSummarize` forwards scope+fullText+bounds; in-flight guard; stable a11y ids | Unit (`AISummaryTabViewScopeTests`) + observed: chip strip renders (Section/Chapter/Book so far), `ai?action=summarize&scope=` flips the accent without re-firing other tabs | No regression; chip strip + selection observed | PASS |
| 6 | `aiSheet` threads full book text + TOC-derived `ChapterBounds` into the panel | Code path (`ReaderContainerView+Sheets.swift` aiSheet); TXT reader opened on device; Chapter scope produced a chapter-bounded (not section-window) summary, confirming bounds are threaded | Wiring confirmed by the Chapter-vs-Section output delta | PASS |
| 7 | End-to-end: open AI sheet, tap Chapter chip, observe a chapter-scoped summary render | `present?sheet=ai&tab=summarize` → `ai?action=summarize&scope=chapter` → loading → `.complete` Chapter SUMMARY card with real model text | Chapter-scoped summary card rendered | **PASS** |
| 8 | End-to-end: the Book-so-far chip produces a *different* (populated) summary than Section for the same position | `ai?action=summarize&scope=book` selects the chip + fires, but at offset 0 (only reachable position) returns the correct empty-boundary "Could not extract text context" card. Populated Book-so-far needs a non-zero position; host-side TXT seek deferred + CU paging unavailable. Section≠Chapter proves the scope-changes-summary mechanism, but Book-so-far specifically is unobserved in populated form. | NOT observed (populated form); empty-boundary behavior is correct | deferred |

**6 of 8 PASS (+ scope mechanism proven via Section≠Chapter); criterion
8's populated Book-so-far case unobserved.**

## Commands run

```bash
SIM=1FAB9493-B97E-48F0-96C7-44A8E5AAA21E

# (Same v3.38.42 build/install/launch/seed/open/provider recipe as
#  feature-65-20260521-VERIFIED.md — shared run, same session.)

# Scope sweep, same reading position (TXT war-and-peace title page,
# Chapter 1 of 4):
xcrun simctl openurl "$SIM" "vreader-debug://present?sheet=ai&tab=summarize"
xcrun simctl openurl "$SIM" "vreader-debug://ai?action=summarize&scope=chapter"  # → .complete (thematic)
xcrun simctl openurl "$SIM" "vreader-debug://ai?action=summarize&scope=section"  # → .complete (scene detail) — DIFFERENT
xcrun simctl openurl "$SIM" "vreader-debug://ai?action=summarize&scope=book"     # → empty-boundary card at offset 0

# Confirm the host-side seek is deferred (position stays null):
xcrun simctl openurl "$SIM" "vreader-debug://open?bookId=$ENC&position=800"
xcrun simctl openurl "$SIM" "vreader-debug://snapshot?dest=pos800.json"
# → snapshot position: null  (open?position parses but doesn't move the TXT reader yet)

xcrun simctl io "$SIM" screenshot /tmp/<name>.png   # headless capture (CU down)
```

## Observations

- **The scope chips work end-to-end through the production path.** Each
  of the three `ai?action=summarize&scope=…` calls flips the selected
  accent chip and re-runs `runSummarize` at that scope — confirmed in
  OSLog (`aiAction observer: action=summarize scope=…`) and visually
  (Section→Chapter→Book-so-far chip accent transitions). Selecting a
  scope does not auto-fire the other tabs.
- **Section ≠ Chapter is the strongest available proof of criterion-8's
  intent.** Two populated summaries at the same locator, one
  scene-level (Section) and one thematic-overview (Chapter), prove the
  scope selector materially changes what the model summarizes. The
  Book-so-far slice uses the identical `selectedScope` →
  `AIContextExtractor` mechanism with a different slice function
  (`extractBookSoFar`), unit-covered by `AIContextExtractorScopedTests`.
- **Book-so-far at offset 0 is correct, not broken.** The empty-context
  card is the designed boundary response when no text precedes the
  reading position. The gap is purely that this host cannot place the
  reader anywhere *but* offset 0 without a gesture (CU down) or a
  not-yet-shipped host-side seek.
- **Path to flip → VERIFIED** (any one of): (a) CU restored so the
  reader can be paged into the book before firing Book-so-far; (b) a
  DebugBridge TXT seek that actually moves the reader (consumes the
  already-parsed `open?position=` offset — the wiring is stubbed in
  `RealDebugBridgeContext.open`); (c) a fixture seeded with a saved
  mid-book reading position. Then `ai?action=summarize&scope=book`
  would render a populated prefix summary distinct from Section.

## Artifacts

- `dev-docs/verification/artifacts/feature-65-69-summarize-chapter-20260521.png` — Chapter `.complete` summary card (criterion 7)
- `dev-docs/verification/artifacts/feature-69-summarize-chapter-loading-20260521.png` — Chapter chip selected + "Generating summary…" loading state
- `dev-docs/verification/artifacts/feature-69-summarize-section-20260521.png` — Section `.complete` summary card (scene-level — different from Chapter)
- `dev-docs/verification/artifacts/feature-69-summarize-booksofar-empty-20260521.png` — Book-so-far chip selected → correct empty-boundary card at offset 0
- `dev-docs/verification/artifacts/feature-65-ai-sheet-idle-20260521.png` — AI sheet idle: all three scope chips render (Section selected)
- `dev-docs/verification/artifacts/feature-65-69-reader-open-20260521.png` — TXT reader open at Chapter 1 of 4
