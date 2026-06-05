# #1478 · Bilingual control on the Summarize tab (Feature #90)

> Resolves needs-design [#1478](https://github.com/lllyys/vreader/issues/1478) — the visible affordance for **Feature #90** (bilingual AI summary).
> Source of truth: `VReader Bilingual Summarize Canvas.html` (every state × themes). Components in `bilingual-summarize-artboards.jsx`. Transcript: `chats/chat20-tool-activity-1483.md`.
> Status: **design landed — implementation deferred** (recorded, not built; Swift held for a separate go-ahead).

## The gap

The Summarize tab has a scope row (Section · Chapter · Book so far) but produces a single-language summary. Bilingual mode (feature #60) is a reading-surface setting. #1478 brings that choice INTO the Summarize tab so a summary can be produced in the reader's own language, the target language, or BOTH stacked interlinear — without leaving the AI sheet.

## Decision (binding) — a second control row under the scope chips

A SEPARATE row (not crowded into the scope row — scope answers "how much", language answers "in what language"; mixing reads as noise):
- **left** — a language control (current target + globe, tap → language popover),
- **right** — a **single ↔ dual** segmented toggle.

**Output modes**: **single** (reader's own language), **target-only**, and **interlinear** (both stacked, like the bilingual reading surface). Plus a **dual-skeleton loading** state for the bilingual case and a **translation-failure recovery** state (the summary still ships in the available language; the failed half is recoverable).

## Production wiring (deferred — do NOT build without go-ahead)

- `AISummaryTabView` gains the language + single/dual row beneath the #69 scope chips; `AIAssistantViewModel.summarize` already takes a `targetLanguage` param — wire the control to it + add the interlinear render (reuse the bilingual/Translate-result presentation). Rule 51 satisfied by this note + canvas.
