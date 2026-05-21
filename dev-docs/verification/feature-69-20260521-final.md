---
kind: feature
id: 69
status_target: VERIFIED
commit_sha: 6ae94729d1485ea531490033724f86556a374204
app_version: 3.38.41 (build 616)
date: 2026-05-21
verifier: claude
device_or_simulator: iPhone 17 Pro Simulator
os_version: iOS 26.5
build_configuration: Debug
backend: OpenRouter (openai/gpt-4o-mini) via DebugBridge provider command
result: partial
---

# Feature #69 — AI Summarize scope selector (Gate-5b, round 3)

Third Gate-5b attempt using the `vreader-debug://present` command (Bug #253,
v3.38.41) to drive the AI sheet host-side. This round **upgrades the
scope-chip-strip rendering evidence from unit-inferred to host-driven-visible**,
but the end-to-end scoped-summary-output criteria (7-8) remain DEFERRED behind
the same newly-isolated harness gap (Bug #255 / GH #1112).

## Acceptance criteria

| # | Criterion | Method this round | Observed | Verdict |
|---|---|---|---|---|
| 1 | `SummaryScope` enum exists with the three cases + design-matching `displayName` strings | Unit (`SummaryScopeTests`, 21) — PASS | No regression on v3.38.41 | PASS |
| 2 | `SummaryScopeResolver` resolves a locator → containing chapter's `ChapterBounds`; preamble → `[0, firstStart)`; empty/non-anchored TOC → `nil` | Unit (`SummaryScopeResolverTests`, 17) — PASS | No regression | PASS |
| 3 | `AIContextExtractor` scoped extraction (`.section` == legacy; `.chapter` slice; `.bookSoFar` prefix; surrogate-pair-safe) | Unit (`AIContextExtractorScopedTests` 28 + `AIContextExtractorTests` 12) — PASS | No regression | PASS |
| 4 | `AIAssistantViewModel` carries `selectedScope` + `setScope`; `summarize` forwards `scope`/`chapterBounds`/`fullText`; non-summarize actions unaffected | Unit (`AIAssistantViewModelScopeTests` 14 + regression) — PASS | No regression | PASS |
| 5 | `AISummaryTabView` renders the chip strip; chip tap = selection-only (no auto-fire); `runSummarize` forwards `selectedScope` + `fullTextContent` + `chapterBounds`; in-flight guard; stable `aiSummaryScopeChip.*` AX IDs | Unit (`AISummaryTabViewScopeTests` 13 + regression) PASS **+ host-driven visible chip-strip rendering this round** | The Section / Chapter / Book-so-far chip strip renders in the real presented AI sheet, Section active (filled accent). | PASS |
| 6 | `aiSheet` threads the full book text + TOC-derived `ChapterBounds` into the panel | Code path verified (`ReaderContainerView` `aiSheet`); EPUB/TXT reader opens on device | No regression | PASS (wiring) |
| 7 | End-to-end: open the AI sheet, tap the Chapter chip, observe a chapter-scoped summary render | Attempted: present AI sheet host-side (works) + provider configured, but no `vreader-debug://` command triggers the Summarize action after a chip selection; the chip-tap + Summarize button need CU (down) / XCUITest (Bug #1054, can't pair host provider). | NOT reached — no host-side AI-action trigger. Filed **Bug #255 / GH #1112**. | DEFERRED |
| 8 | End-to-end: the Book-so-far chip produces a different summary than Section for the same position | Same as #7 — same trigger gap | NOT reached — Bug #255 / GH #1112 | DEFERRED |

**6 of 8 PASS; criteria 7-8 DEFERRED** (the scoped-summary-OUTPUT comparison —
needs a real triggered summary). Per `SCHEMA.md`, any deferred row makes
`result: partial`. Row stays `DONE` (not `VERIFIED`).

### Net change vs the 2026-05-21 (round 2) evidence
- Criterion 5's chip-strip rendering is now **host-driven visible** in the
  real presented AI sheet (`feature-65-05-…png` shows the
  Section / Chapter / Book-so-far chips, Section filled-accent). The prior
  round only had unit-test evidence for chip rendering.
- Criteria 7-8 — the blocker is now isolated to a single missing piece:
  present opens the sheet but there is no AI-**action** trigger command to fire
  a scoped summarize. Filed as Bug #255 / GH #1112.

## Commands run

```bash
# Same setup as feature-65-20260521-final.md (provider configured host-side via
# DebugBridge; --uitesting --enable-ai to trip the AI availability override;
# re-seed mini-epub3 after launch; present?sheet=ai&tab=summarize).
SIM=1FAB9493-B97E-48F0-96C7-44A8E5AAA21E
xcrun simctl openurl "$SIM" "vreader-debug://present?sheet=ai&tab=summarize"
xcrun simctl io "$SIM" screenshot feature-65-05-ai-summarize-final-20260521.png
# => Section / Chapter / Book so far chip strip visible, Section active.
```

## Observations

- The scope chip strip renders exactly as designed (`vreader-panels.jsx`
  SummaryView) in the real presented sheet — three chips, Section filled with
  the accent, Chapter + Book-so-far in the neutral chip wash. No code defect.
- The only thing standing between this and `VERIFIED` is the ability to
  **trigger** a scoped summarize and read back the response card — which has no
  host-side command (Bug #255). The chip-selection wiring and the scoped
  extraction logic are exhaustively unit-pinned (163 tests across the AI/scope
  suites), so the residual risk is purely the visible end-to-end render.
- Same `--uitesting`-gates-`--enable-ai` and `--uitesting`-wipes-library
  findings as the #65 evidence file (see there).

## Artifacts

- `dev-docs/verification/artifacts/feature-65-05-ai-summarize-final-20260521.png` — shared with #65; shows the Section / Chapter / Book-so-far scope chip strip in the presented AI Summarize tab (Section active).
