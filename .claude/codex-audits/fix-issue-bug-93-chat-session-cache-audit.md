---
branch: fix/issue-bug-93-chat-session-cache
threadId: 019dfc3e-546e-78c0-8e63-c338d0814c17
rounds: 1
final_verdict: ship-as-is
date: 2026-05-06
---

# Codex audit — bug #93 (Library General-Chat history persistence)

## Round 1

**Findings**:

| File:Line | Severity | Issue | Resolution |
|---|---|---|---|
| `docs/bugs.md:231` | Medium | Bug #93 row still TODO; PR not merge-ready until flipped to FIXED. | **Fixed** — row flipped to FIXED with notes describing the lifecycle bug + cache fix. Filed GH #313 for the mirror; row Notes column updated to `GH: #313`. |
| `README.md:194` | Low | After flipping #93 to FIXED, the bug count becomes 43, not 42 (count needed to bump too). | **Fixed** — `README.md` count updated. (See "Count discrepancy" note below.) |

No blocking code-level issues. The lifecycle change in `LibraryView.swift` (cached `@State private var generalChatVM` + lazy `resolvedGeneralChatVM` getter) mirrors the existing `resolvedAICoordinator` pattern in `ReaderContainerView`. Codex's residual notes (unbounded display history retention; dismiss-during-stream behavior) are follow-up class, not merge blockers.

**Verdict**: `ship-as-is` after tracker updates landed.

## Count discrepancy

While addressing the README count update, post-Codex re-counting revealed the previous "98 fixed" / "43 fixed" claims were both wrong (different forms of grep-mismatch). Real count via `awk -F'|' '/^\| *[0-9]+ *\| /'`:

- 137 FIXED rows + 2 PARTIALLY FIXED = **139 fixed**.
- Features: 36 DONE + 2 VERIFIED = 38.

The "98 fixed" claim in the pre-PR README was stale; "43" was a fresh undercount due to a regex that required `| 93|` (no space) format while many rows use `| 93 |` (space-padded for column alignment). README in this PR updated to the correct **139 fixed**.
