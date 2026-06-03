# #1455 · Chat-tab AI scope selector + sources toggle + on-demand retrieval

> Feature [#86](https://github.com/lllyys/vreader/issues/86) parts 2 (annotation sources) & 3 (read-everywhere scope / on-demand retrieval).
> Parent [#1453](https://github.com/lllyys/vreader/issues/1453). WI-1 (chapter-scoped context, no UI) shipped v3.49.9 / PR #1454.
> Source of truth: `VReader Chat Context Canvas.html` (every state across themes). Components live in `chat-context-artboards.jsx` (`ContextBar`, `ScopeMenu`, `SourcesMenu`, `RetrievalCluster`, `CitationRow`) — to be lifted into `vreader-panels.jsx`'s `ChatView`.

**Decision: a persistent CONTEXT BAR docked directly above the Chat composer.** A scope chip on the left (tap → scope menu), a sources chip on the right (tap → sources popover), and the whole-book read rendered as an in-place progress state in the same bar. The answer-level retrieval affordance is a "Drew on" citation row under each reply.

---

## Why a context bar, not the Summarize chips

The Summarize tab already has scope chips (`Section / Chapter / Book so far`). The issue asks for a "Chat-tab equivalent" — but Chat is **not** Summarize:

- **Summarize is a one-shot.** Scope chips sit above the single generated block because they parameterise *that one action*. Pick a scope, get a summary.
- **Chat is a thread.** Scope and sources are properties of *every* message in an ongoing conversation. They must stay on screen and stay legible while the user types question after question.

So the controls belong with the composer, not at the top of the tab. The canonical bar is ~40px, sits between the message scroll and the input (sharing the composer's top rule), and never scrolls away.

### Accent discipline

The reader's accent (`#8c2f2f` paper / `#d6885a` dark) is already spent on the assistant avatar and the send button. A permanently-docked bar can't also be full-accent — it would shout. So:

- **Scope chip** — quiet outline pill; tints to a faint accent wash only while its menu is open.
- **Sources chip** — when sources are on, a soft green wash + a green count badge (green = "on", matching `PillSwitch` across the app); when all off, it collapses to a muted "Off".
- Full accent returns *inside* the menus, for the selected radio / the active state — where selection is transient, not standing.

---

## Scope menu

Opens upward from the scope chip. Four rows, each with a one-line descriptor + a token estimate so the cost/benefit is legible:

| Scope | Reads | Estimate |
|---|---|---|
| **Section** | Just the passage you're reading | ~600 tokens |
| **Chapter** *(default — matches shipped WI-1)* | The whole current chapter | ~4.2k tokens |
| **Book so far** | Everything up to your current page | ~58k tokens |
| **Whole book** | The entire book, **incl. pages ahead** — on demand | retrieves on first use |

- Selected row: accent check + faint tinted background.
- **Whole book** carries an `ON-DEMAND` tag and a **spoiler-aware** footer: *"Whole book can reference pages ahead of you — answers may contain spoilers."* Every other scope is spoiler-safe by construction (it only sees what you've read). This is the one genuinely new behaviour parts 2–3 introduce, so it's the one we caption.
- Footer for the bounded scopes: *"Larger scopes give fuller answers but cost more per message."*

## Sources popover

Opens upward from the sources chip. Three toggle rows over the reader's own annotations, each with a per-book count:

- **Notes** — 18 in this book — on by default
- **Highlights** — 47 in this book — on by default
- **Bookmarks** — 5 in this book — off by default

Footer: *"Included alongside the book text so answers can cite what you marked."* When all three are off the chip reads **Sources · Off** and none of the user's marks leave the device for the model. The sources count on the bar = number of toggled-on kinds.

---

## On-demand retrieval (Whole book)

The only heavy/slow path, so the only one with a progress affordance — and it stays **in the bar, non-blocking**, never a modal.

| State | Bar treatment | Composer |
|---|---|---|
| **Armed** | Scope chip = "Whole book"; caption *"Reads on your next question"* | enabled |
| **Reading** | Spinner + *"Reading the whole book… 38%"* + `23 / 61 ch` + a thin accent progress bar + a Cancel ×. Messages dim. | disabled, placeholder *"Reading… ask once the book is ready"* |
| **Ready** | Green "Whole book" chip + *"Indexed · ready"* check | enabled |

**Cancel keeps what was already indexed** — backing out never throws away the read (same "nothing is lost" principle as the whole-book *translate* cancel in #863).

### Answer-level affordance — the "Drew on" row

Under any reply, a small uppercase **Drew on** label followed by chips naming what was actually read: `Ch. 1`, `your note`, etc. When Whole-book retrieval pulls from a page ahead of the reader, that chip is amber and tagged `Ch. 7 · ahead` so a spoiler is never silent. This doubles as the user's proof that their toggled sources are actually being used.

---

## States the canvas covers (per the issue's checklist)

- **Default** — `A-default` (+ dark `A-dark`).
- **Scope menu / each scope selected** — `A-scope`, and `S-section / S-chapter / S-sofar / S-whole`.
- **Sources on / off** — `src-on` (3), `src-off` (Off), plus the popover `A-sources`.
- **Retrieval-in-progress** — `R-armed / R-reading / R-ready` (+ dark).
- **Rejected / alternate** — `B` top chips (Summarize-parity, rejected), `C` composer tray (kept as fallback).
- **Anatomy** — `D` true-size bar / scope menu / sources popover / retrieval bar.

## Cross-references

| File | Role |
|---|---|
| `VReader Chat Context Canvas.html` | Canvas of every state across themes. Source of truth. |
| `chat-context-artboards.jsx` | `ContextBar`, `ChipScope`, `ChipSources`, `ScopeMenu`, `SourcesMenu`, `RetrievalCluster`, `ReadingBar`, `CitationRow` — #1455 |
| `vreader-panels.jsx` | `ChatView` / `SummaryView` — the existing Chat tab + the Summarize scope-chip precedent these extend. |
