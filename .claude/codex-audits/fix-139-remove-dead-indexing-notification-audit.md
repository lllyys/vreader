---
branch: fix/139-remove-dead-indexing-notification
threadId: manual-fallback
rounds: 1
final_verdict: ship-as-is
date: 2026-05-06
---

## Manual audit evidence

Dead-code removal. Manual audit performed.

### Files changed

| File | Change |
|---|---|
| `vreader/Services/BookImporter.swift` | Removed `indexingNeededNotification` declaration (line 33) and its post call (line 222-226). Replaced with explanatory comments. |
| `vreaderTests/Services/BookImporterTests.swift` | Removed `indexingTriggerPosted` test that observed the now-dead notification. |
| `docs/bugs.md` | New row #139 (FIXED, Low, GH: #298). |

### Why dead

- 1 declaration, 1 post site, 0 production observers. Confirmed by grep across `vreader/`.
- Original WI-2 design comment ("Indexing trigger is a Notification; the indexer is a separate concern") was forward-looking. The indexer landed lazy via `ReaderSearchCoordinator.indexBookContent` on search-panel-open — never wired to this notification.
- The only consumer was a unit test asserting the post fires. Removing the post makes the test fail; removing the test alongside is the clean cleanup.

### Edge cases checked

- **`BookImporterTests` post-removal**: 38 tests in the suite — 1 removed, 37 remain. Other tests cover import-success regression for TXT, EPUB, dedupe, and edge cases.
- **No external consumers**: confirmed via `grep -rn "indexingNeededNotification" --include=*.swift vreader/ vreaderTests/` — only the 3 sites we removed (declaration, post, test).
- **Build**: clean.

### What I deliberately did NOT change

- `ReaderSearchCoordinator.indexBookContent` — current production indexing path, untouched.
- Any other notification or indexing logic.

### Tests added

None. Pure dead-code removal; no new behavior to test.

### Verdict

**ship-as-is**. 3-line declaration removal + 5-line post-site removal + 30-line test removal. No regression risk; the notification was orphaned forward-looking code.
