# #1483 · AI chat tool-activity affordance (Feature #91)

> Resolves needs-design [#1483](https://github.com/lllyys/vreader/issues/1483) (the visible affordance for **Feature #91** — agentic AI chat / tool-calling).
> Source of truth: `VReader Tool Activity Canvas.html` (every state × paper/dark). Components live in `tool-activity-artboards.jsx` (`ActivityLive`, `ActivityChip`, `ActivityTimeline`, `ActivityError`, `Citations`) + the shared `vreader-ai-shell.jsx` chat-bubble shell — to be lifted into `vreader-panels.jsx`'s `ChatView` assistant bubble.
> Status: **design landed — implementation deferred** (recorded, not built; Swift held for a separate go-ahead per the handoff convention).

## The gap

When the assistant answers about a book it may run tools (Feature #91): search the text, open a specific chapter, look up a highlight. Today that work is **invisible** — the user sees a pause, then an answer, with no sense of what was consulted. #1483 surfaces it.

## Decision (binding) — an in-bubble "activity strip" above the assistant's text

A disclosure pattern, not a wall of logs. Keeps the bubble calm by default (one chip) while making the retrieval auditable on demand.

1. **Live (working)** — a status line replaces the typing dots: spinner + the current tool's verb ("Searching the text…") + a step counter. `ActivityLive`.
2. **Collapsed (done)** — it collapses to a single quiet disclosure chip **"Looked at N sources"** so the answer stays the focus. `ActivityChip`.
3. **Expanded (tap the chip)** — a step timeline: each tool call as a row **verb · target · result** (e.g. *Searched the text · "Mr. Bennet visit Bingley" · 4 passages*; *Opened · Chapter 1 · Vol. I · read*). `ActivityTimeline`.
4. **Error** — when a tool fails (e.g. a chapter isn't downloaded) the timeline marks that step **red** and notes the model answered from what was available — **the answer still ships, the gap is auditable**. `ActivityError`.

### Activity strip vs citations — process vs evidence

The activity strip is the **process** (what the model *did* — searched, opened). The existing footnote **citation chips** below the answer text (the "Drew on" row from #1455 / `Citations`) are the **evidence** (what it *cited*). They stay separate and both remain.

## States the canvas covers

- `A-live` (working · live status), `A-collapsed` (done · one chip), `A-expanded` (chip → timeline) — paper.
- `S-error` (a tool failed → red step), `S-dark-exp` / `S-dark-live` (dark).

## Production wiring (deferred — do NOT build without go-ahead)

- The agentic loop in `AIChatViewModel` (Feature #91, in progress per the cron's `AIChatViewModelAgenticTests`) emits per-tool-call events (verb, target, result, status). The assistant bubble renders the activity strip from that event list: live while the loop runs, collapsed `ActivityChip` on completion, `ActivityTimeline` on expand, red `ActivityError` step on a failed tool.
- Lift `ActivityLive`/`ActivityChip`/`ActivityTimeline`/`ActivityError` into the SwiftUI assistant bubble in `AIChatView`/`vreader-panels.jsx ChatView`; reuse the existing citation chips unchanged.
- Rule 51 satisfied (this note + the committed canvas/artboards are the design).
