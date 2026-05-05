---
branch: fix/issue-17-ai-buttons-consent-off
threadId: 019df665-8af7-7dc2-a88a-7a0d23e4a7f5
rounds: 2
final_verdict: ship-as-is
date: 2026-05-05
---

# Codex audit log — Bug #90 fix (GH #17)

## Round 1 — initial findings

| File | Line | Severity | Issue | Resolution |
|------|------|----------|-------|------------|
| `vreader/Views/Reader/TXTBridgeShared.swift` | 83 | Medium | The reader's text-selection edit menu added `Translate` unconditionally. Even with the toolbar button hidden by the new consent gate, a consent-revoked user could still invoke AI via long-press → Translate. The fix at the toolbar level was a partial fix only. | Fixed: `buildReaderEditMenu` takes a new `isAITranslateAvailable: Bool` parameter (default `true` for safety in tests/preview). When `false`, the Translate action is omitted from the lookup menu entirely. Both production callers (`TXTChunkedReaderBridge.swift:323` and `TXTTextViewBridgeCoordinator.swift:145`) compute `AIReaderAvailability.isAvailable(featureFlags: .shared, keychainService: KeychainService(), consentManager: AIConsentManager())` at menu-build time and pass the result. |
| `vreader/Views/Reader/ReaderContainerView.swift` | 145 | Medium | The `.readerTranslateRequested` notification handler called `showAIPanel = true` without re-checking AI availability. If the notification was posted from any out-of-tree path (custom view, stale plug-in, test fixture), the sheet would still open with AI VMs left in a half-initialized state. | Fixed: added `guard resolvedAICoordinator.isAIAvailable else { return }` at the top of the handler. Defense-in-depth seam — the toolbar button + edit-menu Translate already gate on availability; this is the sheet-presentation backstop. |

## Round 2 — verification re-pass

Codex confirmed both fixes:

> `TXTBridgeShared.buildReaderEditMenu` now omits `Translate` when `isAITranslateAvailable` is false, and both production callers pass a live `AIReaderAvailability.isAvailable(...)` result, so consent revocation removes the TXT/MD selection-menu entry point before the action can fire. The notification seam is also covered: `ReaderContainerView.onReceive(.readerTranslateRequested)` now guards `resolvedAICoordinator.isAIAvailable` before opening the panel, so a stale or out-of-band `.readerTranslateRequested` post no longer reintroduces the old UX.

> The inline availability check is acceptable. It runs on edit-menu construction, not on scroll/layout hot paths, and the work is small: one feature-flag read, one keychain read, one `UserDefaults` read. At "once per long press" frequency, that is not a meaningful perf risk.

> I did not find other remaining production AI entry points that bypass this gate. Library chat is still gated through `isAIChatAvailable`, reader chrome is gated through `isAIAvailable`, and service-level consent enforcement remains in `AIService` as the final backstop.

## Final verdict

**ship-as-is**

The fix closes bug #90 at three seams:

1. **Toolbar buttons** — `ReaderAICoordinator.isAIAvailable` and `LibraryView.isAIChatAvailable` now check consent in addition to feature flag + API key. ReaderChromeBar and library chat button hide.
2. **Selection menu** — `TXTBridgeShared.buildReaderEditMenu` accepts an `isAITranslateAvailable` parameter; both TXT bridges pass live availability. Long-press → Translate disappears when consent is revoked.
3. **Notification handler** — `.readerTranslateRequested` re-checks availability before presenting the AI sheet, so any stale or out-of-band post is dropped.

`AIService.sendRequest()` / `streamRequest()` continue to enforce consent at request time as the final defense, but users no longer see the dangling "consent required" error mid-task because the entry points are gated upfront.

29 tests pass across the three affected suites:
- `AIReaderIntegrationTests` — 5 existing tests updated to inject explicit consent state; 2 new (`unavailableWhenConsentRevoked`, `availableTransitionsAcrossConsentRevoke`).
- `AIChatGeneralTests` — 3 existing updated; 1 new (`consentOffHidesChat`).
- `TXTBridgeSharedTests` — 1 stale test replaced (`IncludesTranslateWhenAvailable`); 1 new bug-#90 regression (`OmitsTranslateWhenAIUnavailable`).
