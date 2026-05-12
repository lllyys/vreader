---
branch: feat/feature-48-wi-1-chapter-highlight-display
threadId: 019e1bb7-191c-72e2-8d65-e0f67dbaf6fa
rounds: 1
final_verdict: ship-as-is
date: 2026-05-12
---

## Round 1 findings

| file:line | severity | issue | resolution |
|---|---|---|---|
| TXTReaderContainerView.swift:490 | High | Pre-WI-3 persisted chapter-mode highlights have chapter-local-as-global offsets; WI-1 will drop them (containment fails). | Accepted with rationale: pre-WI-3 behavior was already broken (hardcoded `persistedHighlights: []`); WI-1 doesn't regress. WI-3 fixes creation side; plan BC section explicitly documents that pre-WI-3 highlights need delete+recreate. |
| TXTReaderContainerView.swift:501 | Medium | `uiState.scrollToOffset` not translated to chapter-local; bridge interprets it against chapter text. | Accepted / deferred: scroll offset translation is WI-2's explicit scope per the plan's 3-WI split. |
| TXTReaderContainerView.swift:503 | Medium | Changing `highlightIsTemporary` from hardcoded `true` to `uiState.highlightIsTemporary` could leave stale timer if only the flag changes without `highlightRange` changing. | Accepted with rationale: aligns chapter mode with continuous mode's identical pattern; timer reset requires `highlightRange` to change independently of the flag, which doesn't occur in the existing state machine. |
| TXTChapterHighlightHelper.swift:35 | Low | Helper doesn't guard zero-length or negative-location input ranges before clipping; could emit zero-length NSRanges. | Accepted as pre-existing follow-up: TXTChapterHighlightHelper.swift is unchanged in this PR; rendering currently ignores zero-length ranges. Noted for future cleanup. |

## Round 2

Not required. Codex confirmed: "No remaining Critical or High issues block merging WI-1."

## Summary verdict

All findings accepted with rationale. High finding is a documented BC limitation (WI-3 will fix creation side); both Medium findings are either WI-2 scope or alignment with continuous mode; Low is pre-existing helper behavior. ship-as-is.
