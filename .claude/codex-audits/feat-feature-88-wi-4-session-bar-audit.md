---
branch: feat/feature-88-wi-4-session-bar
threadId: 019e97c3-1503-7a21-9fff-f0c2b55cc3cb
rounds: 3
final_verdict: follow-up-recommended
date: 2026-06-05
---

# Gate-4 audit — Feature #88 WI-4 (Chat-tab session bar)

WI-4 adds the slim session bar at the top of the Chat tab (book chat only): the
active conversation's title + chevron (left) and a "New" compose pill (right),
per the committed `SessionBar` artboard (Rule 51). New SwiftUI view
`ChatSessionBar.swift`, a VM `activeSessionTitle`/`storedActiveTitle`, and the
`AIChatView` wiring (bar at top, toolbar trash gated to general chat).

## Round history

| Round | Findings | Resolution |
|---|---|---|
| 1 (`019e97b4`) | **M1** `activeSessionTitle` always re-derived from `messages` (wrong for renamed / stored-title-differs sessions); **M2** `showConversations` set-true-never-reset → sticky chevron/wash; Lows: test coverage, SF-Symbol fidelity, file size. Plus an orchestrator-caught `UIScreen.main` 74% width. | see below |
| 2 (`019e97bd`) | M2 **resolved**. M1 only partially resolved (display side) — the deeper bug is on the PERSISTENCE side: `_saveSettledTurn` + `sealCurrentSessionIfNeeded` re-derive + overwrite the stored title on every update/seal, so a later turn / transition reverts a renamed title. Two Mediums. | see below |
| 3 (`019e97c3`) | **clean** — both round-2 Mediums resolved; carry-forward contract verified in the real store + mock; create path correct; regression tests pin it; no new Critical/High/Medium. | — |

## Fixes applied

**Orchestrator-caught (pre-round-1 in review)** — `ChatSessionBar` capped the title
at `UIScreen.main.bounds.width * 0.74` (deprecated API + wrong for a non-fullscreen
sheet). Replaced with responsive layout: `Spacer(minLength: 8)` + `.layoutPriority(1)`
on the New pill so a long title truncates (lineLimit 1, tail) instead of pushing
New off — correct at any bar width.

**M2 (sticky open)** — removed the `showConversations` `@State`; the bar is passed
`isOpen: false` + `onTitleTap: {}` (inert) until WI-5 wires the actual
Conversations sheet (then `isOpen` binds to the sheet presentation). No sticky
local state; the New button still works.

**M1 — display side** — added an observed `internal(set) var storedActiveTitle: String?`;
`activeSessionTitle = storedActiveTitle ?? derivedTitle(from: messages) ?? defaultSessionTitle`.
`storedActiveTitle` is set = `record.title` on load / switch / delete-fallback /
first-turn create-adopt, and reset to nil on newConversation + the active-delete
reset. So a loaded/switched session shows its STORED title; a fresh thread derives.

**M1 — persistence side (round 2)** — `_saveSettledTurn` and `sealCurrentSessionIfNeeded`
now pass `title: nil` on the UPDATE branch (existing session), so a later settled
turn / transition seal preserves the stored title via the store's carry-forward
contract (`PersistenceActor+ChatSessions.swift:119` assigns title only when non-nil;
the mock mirrors it). The title is set only at CREATE (derived) + on rename (WI-5).
Pinned by `storedTitle_survivesLaterSettledTurn` + `storedTitle_survivesNewConversationSeal`
(both fail pre-fix).

## Accepted Lows

- **SF-Symbol fidelity** — the bar uses `bubble.left` / `chevron.down` / `plus` SF
  Symbols rather than the artboard's custom outlined glyphs. SF Symbols are the
  app-wide convention (ChatContextBar etc.); the match is faithful. Accepted.
- **File size** — `AIChatView.swift` is ~331 lines (35 over the ~300 soft guideline).
  WI-4's additions are minimal cohesive wiring; a dedicated extraction is deferred
  (not worth a churny split mid-feature). Accepted.

## Verdict

`follow-up-recommended`. The WI-4 surface is clean (3 audit rounds → 0 open
Critical/High/Medium). The follow-up is WI-5: wire the title-tap → Conversations
sheet, bind `isOpen` to the sheet presentation, and add rename (which will set
`storedActiveTitle`). 38 tests across the title + sessions suites pass.
