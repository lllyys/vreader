---
branch: feat/feature-86-wi-3-scope-chip-menu
threadId: codex-exec (run-codex.sh, 2 rounds)
rounds: 2
final_verdict: ship-as-is
date: 2026-06-03
---

# Codex audit — Feature #86 WI-3: Chat scope chip + scope menu (Gate 4)

## Implementation summary

The docked context bar's **scope chip** + the upward **scope menu**, wired to
`AIChatViewModel.scope` and the coordinator's scope-aware re-assembly:

- `ChatContextScope+Menu` — menu copy (`menuDescription` / `tokenEstimate` /
  spoiler-aware `menuFooter`), matching the #1455 design strings.
- `ChatContextBar` — the scope chip (Sparkle + "Context" + scope name + chevron;
  transparent at rest, faint accent wash when its menu is open). The sources chip lands WI-4.
- `ChatScopeMenu` — the popover (radio + label + description + token estimate + spoiler footer).
- `AIChatViewModel.setScope` → `onScopeChanged` (the coordinator's single funnel).
- `ReaderAICoordinator.scopedChatContext(_:)` — section/chapter/bookSoFar map onto the #69
  `AIContextExtractor`; `refreshChatContext` reads `chatViewModel?.scope`.

Plan: `dev-docs/plans/20260603-feature-86-wi2-chat-scope-sources-retrieval.md` (WI-3).

## Round 1 — 1 High + 1 Medium + 2 Low

| severity | issue | resolution |
|---|---|---|
| High | Selecting Whole book immediately reassembled `bookContext` as `.bookSoFar` while the menu showed whole-book/spoiler/on-demand copy — a narrower slice under a broader label. | **Fixed.** The Whole-book row is filtered OUT of the WI-3 menu (`ChatScopeMenu.menuScopes` = the synchronous scopes only); the on-demand row + its retrieval/armed states land in WI-5. The coordinator's `.wholeBook → .bookSoFar` degrade remains only as an unreachable safety net. |
| Medium | The bar added a top rule even though the composer already drew its own → two separators (the design has one shared rule around bar + composer). | **Fixed.** Removed the composer's top rule; the bar's top rule is the cluster's single shared rule. |
| Low | `tokenEstimate(.wholeBook)` was "On-demand"; the #1455 source string is "on-demand". | **Fixed.** Verbatim "on-demand". |
| Low | `AIChatView.swift` is ~389 lines (>300). | **Accepted with rationale.** The file was already >300 before WI-3; a proper composer extraction requires relaxing several `private @State` visibilities (the composer reads `inputText`/`isInputFocused`) and is deferred to WI-4, which adds the sources chip to the same cluster and is the natural place to extract `AIChatView+Composer`. |

Round 1 explicitly cleared: the single-funnel write path, the `@MainActor` callback hop, the
`[weak self]` closure, the `.wholeBook → .bookSoFar` recursion safety, and the required
accessibility identifiers.

## Round 2 — CLEAN

Both the High and Medium confirmed resolved; the on-demand Low fixed; the file-size Low
accepted. Zero open Critical/High/Medium.

## Verdict

`ship-as-is` after 2 rounds.

## Verification

- Unit (3 suites green via `scripts/run-tests.sh`): `ChatContextScopeMenuTests` (menu copy),
  `AIChatViewModelScopeTests` (`setScope` funnel + no-op), `ReaderAICoordinatorScopedContextTests`
  (per-scope extraction; whole-book degrade; no-text fallback).
- Tier: behavioral (new UI + scope re-assembly). Gate-5 slice verification (device) follows
  in the PR — open the reader, tap the scope chip, pick a scope, confirm the chip updates and
  the menu dismisses.
