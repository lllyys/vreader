---
branch: feat/feature-120-wi-2-opds-sources-ui
threadId: 019f0405-wi2
rounds: 2
final_verdict: ship-as-is
date: 2026-06-26
---

# Feature #120 WI-2 — Codex audit (OPDS source-list + add/edit UI)

Changed files audited:
- `opds/ui/OpdsSourcesUiState.kt` — list/edit UI state.
- `opds/ui/OpdsSourcesViewModel.kt` — list flow, add/edit, test-connection (origin-scoped, live form), save/delete.
- `opds/ui/OpdsSourceListScreen.kt` — empty onboarding + suggested catalogs + populated rows.
- `opds/ui/OpdsAddSheet.kt` — Name/URL, auth toggle revealing username/password, Test Connection, edit-mode Remove.
- `opds/ui/OpdsSourcesViewModelTest.kt` (Robolectric, 9), `OpdsSourceListScreenTest.kt` + `OpdsAddSheetTest.kt` (instrumented, 7).

## Round 1 — 1 High, 4 Medium, 2 Low

| file:line | severity | issue | resolution |
|---|---|---|---|
| OpdsSourcesViewModel test() | High | a stale Test result for catalog A could land after the user edited the live form to catalog B (testGen only bumped on open/close/new-test) | FIXED — `test()` snapshots `TestSignature(trimmed url, requiresAuth, username, password)` and applies the result only if `signatureOf(current)` still matches; else resets to idle. Setting test/testMessage doesn't touch those fields, so the `testing` mutation can't self-invalidate. Regression test `staleTestResult_discardedWhenFormEditedMidTest` added |
| OpdsSourcesViewModel:80 | Medium | edit-mode test decrypted the stored password even when username blank (no auth header usable) | FIXED — `pass = if (user != null) resolveTestPassword(s) else null` |
| OpdsSourcesViewModel:82 | Medium | `originOf(s.url)` untrimmed while `fetchFeed(s.url.trim())` trimmed → a leading/trailing space nulls authOrigin and silently drops auth | FIXED — `val url = s.url.trim()` once; both `originOf(url)` and `fetchFeed(url)` use it |
| OpdsSourcesViewModel:124 | Medium | auth-status row showed the amber dot but a plain host detail — status meaning unclear | FIXED — a requiresAuth source shows `"Sign-in required · <host>"` (honest; no fabricated 401) |
| OpdsSourceListScreen:143 | Medium | long names/URLs could wrap into a tall row | FIXED — `maxLines = 1` + `TextOverflow.Ellipsis` on source name, detail, and suggested-row name |
| OpdsAddSheet:104 | Low | Test chip enabled regardless of `canTest` (misleading on a blank URL) | FIXED — `TestChip(enabled = state.canTest, …)` dims + disables when false |
| OpdsSourceListScreen:69 | Low | design's `back={false}` vs NavScreen's mandatory back | ACCEPTED — in the Android app the Catalogs screen is PUSHED from Settings, so a back affordance is correct here (unlike the standalone design canvas) |

## Round 2

Clean — no new or still-open findings. Re-audit confirmed every round-1 fix is correct and complete
(signature check, blank-username no-decrypt, consistent trimmed URL, honest auth detail, ellipsis
constraints, canTest-gated chip) and the accepted Low's rationale holds.

## Summary

All High/Medium findings fixed + covered by tests; both Lows resolved (one fixed, one accepted with
rationale). 9 VM (Robolectric) + 7 instrumented Compose tests green on emulator-5554. **Verdict: ship-as-is.**
