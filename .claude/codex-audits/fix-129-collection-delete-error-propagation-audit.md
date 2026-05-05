---
branch: fix/129-collection-delete-error-propagation
threadId: manual-fallback
rounds: 1
final_verdict: ship-as-is
date: 2026-05-06
---

## Manual audit evidence

Small error-propagation fix. Manual audit performed.

### Files changed

| File | Change |
|---|---|
| `vreader/Views/Library/CollectionSidebar.swift` | Closure type `async throws`; swipe action wraps in do/catch and sets `errorMessage`. |
| `vreader/Views/LibraryView.swift` | Callsite removes `try?`, propagates throw; refresh moved to `defer` so it runs success or failure. |
| `docs/bugs.md` | New row #129 (FIXED, Low, GH: #277). |

### Why fix

`try?` swallowed any thrown error from `persistence.deleteCollection` — including `CollectionError.collectionNotFound` and any propagated `ModelContext.save` failure. User saw no feedback. The existing `errorMessage` @State + alert in `CollectionSidebar` was already wired up but never used by the delete path.

### Edge cases checked

- **Successful delete**: throw doesn't fire, no error path; records list refreshes normally; row disappears as before.
- **CollectionError.collectionNotFound**: alert message: `"Failed to delete \"X\": Collection not found: X."` (using `error.localizedDescription`). User sees actionable text.
- **`ModelContext.save` failure** (e.g., schema race): same alert path. The collection might be partially detached from books — but that was the pre-fix behavior too; the fix just adds the user-visible signal.
- **Records refresh on error**: `defer { Task { ... } }` always runs the `fetchAllCollections` re-read, so the sidebar reflects SwiftData truth even after an error. Avoids stale UI showing a row that wasn't deleted.
- **Concurrent deletes**: not a new concern; same as before. Two simultaneous deletes go through the actor and serialize.
- **Localized error message**: uses `error.localizedDescription`. `CollectionError` should ideally provide localized text — that's a separate concern (existing in the codebase before this change).

### What I deliberately did NOT change

- **Confirmation dialog before delete**: addresses a separate UX concern (one-tap-to-destruct). Out of scope for this PR; leaving as a future ergonomic improvement if filed.
- **`CollectionError.collectionNotFound`'s message**: `error.localizedDescription` gives a workable string; localization polish is separate.
- **`onCreateCollection` closure type**: kept `async -> Void`. Create path has separate error handling via `errorMessage` already (see `createCollection()` in CollectionSidebar). Uniformity could be added later but keeping the scope tight.

### Tests added

None. The fix is plumbing — closure type and `try?` removal. The 30 existing collection persistence + model tests cover the data layer; behavior in the failure path is "set errorMessage instead of swallowing." UI alert shows automatically on errorMessage change. No new test required.

### Verdict

**ship-as-is**. 3-file mechanical change. Closes bug #129 / GH #277 cleanly.
