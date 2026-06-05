---
branch: feat/feature-88-wi-5-conversations-sheet
threadId: 019e9800-580a-7f51-a66e-5e5d3aa8c22a
rounds: 2
final_verdict: follow-up-recommended
date: 2026-06-05
---

# Gate-4 audit — Feature #88 WI-5 (Conversations sheet — FINAL WI)

WI-5 completes feature #88: the nested **Conversations** bottom sheet behind the
Chat-tab session bar's title pill — a "New conversation" row, the saved-session
list (title + 2-line snippet + "N messages · when", current row accent-tinted with
a green "Active" pill), per-row tap = switch, trailing swipe = inline rename /
delete, and a first-chat empty state. New `ConversationsSheet.swift` +
`ConversationsSheetRows.swift`; VM `loadSessionSummaries()` + `renameSession(id:to:)`
(+ `renameActiveSession` now sets `storedActiveTitle`); the `AIChatView` chevron →
`.sheet` wiring.

## Round history

| Round | Findings | Resolution |
|---|---|---|
| 1 (`019e97f9`) | **M1** the sheet only refreshed on its own actions → stale list if the active session settles under an open sheet (most visible: a new conversation's first-turn create). **M2** tapping the ALREADY-active row called `switchToSession`, cancelling its in-flight stream + snapping to the settled snapshot. Lows: empty-state dropped the design's book sentence; `AIChatView` 344 lines. | see below |
| 2 (`019e9800`) | **clean** — both Mediums resolved; no new Critical/High/Medium. (Nit: a redundant inner `contentShape`, harmless.) | — |

## Fixes applied

**M2 (active-row tap)** — `ConversationsSheet.rowContent` now calls
`switchToSession` only when `summary.id != viewModel.activeSessionId`; tapping the
active row just dismisses (never reaches `cancelStreamingForTransition`). Added
`.contentShape(Rectangle())` so the whole row is tappable (non-active rows have a
transparent background).

**M1 (stale list)** — added `.onChange(of: viewModel.activeSessionId) { Task { await reload() } }`.
`reload()` only writes the local `summaries` `@State` from the read-only
`loadSessionSummaries()`, so there is no self-triggering loop; the
new-conversation first-turn case is covered because `saveSettledTurn` flips
`activeSessionId` nil → the created id. (Residual: an existing active session's
snippet/count updating on a settled turn with no id change leaves a slightly stale
snippet until reopen — cosmetic, accepted.)

**Low (empty-state copy)** — restored the design's first sentence ("This is your
first chat about this book…"). The book TITLE is not on the VM (only
`bookFingerprint` / `bookContext`); the personalized book name is a deferred
nicety (would need threading the title from the AI panel host).

## Accepted Lows / follow-ups

- **`AIChatView` 344 lines** — over the ~300 soft guideline. The file has
  accumulated several features' wiring (context-bar menus, Ask-AI seed, session
  bar, Conversations sheet); a holistic `AIChatView` decomposition is its own
  refactor, not WI-5's scope. Accepted.
- **Redundant inner `contentShape`** — harmless (audit r2 nit). Left as-is.
- **Empty-state book name** — render "this book"; personalize later if the host
  threads the title.

## Verdict

`follow-up-recommended`. WI-5 is clean (2 audit rounds → 0 open Critical/High/Medium).
This is the FINAL WI of #88 — the session switcher is now usable end-to-end
(browse / new / switch / rename / delete / empty state). 46 tests across the
summaries + title + sessions suites pass. The follow-ups above are minor (file
decomposition, empty-state personalization). Gate-5b device acceptance (the
switcher driven end-to-end) flips the row DONE → VERIFIED.
