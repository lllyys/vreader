---
branch: fix/issue-451-library-collection-filter-no-effect
threadId: manual-fallback
rounds: 2
final_verdict: ship-as-is
date: 2026-05-09
---

# Codex audit log — bug #155 / GH #451

## Audit context

Codex MCP returned `stream disconnected before completion` on two consecutive
attempts (network/quota), so this is a Phase 4f manual mini-audit per
`.claude/skills/fix-issue` and `.claude/rules/47-feature-workflow.md`.

Manual audit covers the same eight dimensions a Codex audit would target:
correctness, edge cases, SwiftUI reactivity, `.tag`/`.series` stub safety,
DTO call-site impact, concurrency, performance, vreader compliance.

## Diff under audit (HEAD = 91010cc)

```
docs/bugs.md                                       |  4 +-
vreader.xcodeproj/project.pbxproj                  |  4 ++ (xcodegen regen)
vreader/Models/LibraryBookItem.swift               | 14 ++++-
vreader/Services/PersistenceActor+Library.swift    |  3 +-
vreader/Views/Library/CollectionSidebar.swift      | 17 ++++++
vreader/Views/LibraryView.swift                    | 13 ++++-
vreaderTests/Models/LibraryFilterTests.swift       | 83 ++++++++++++++++++ (new)
```

Plus a follow-up commit adding 2 integration tests in
`vreaderTests/Services/CollectionPersistenceTests.swift`.

## Per-dimension findings

### 1. Correctness

| Severity | Finding |
|---|---|
| — | None. The fix tightens the loop: sidebar already wrote `activeFilter` correctly (`CollectionSidebar.swift:66`); the new `displayedBooks` consumes it (`LibraryView.swift`); the projection populates `collectionNames` from `Book.bookCollections` so the matcher has data to filter on. End-to-end chain proven by `CollectionPersistenceTests.fetchAllLibraryBooksProjectsCollectionNames` + `LibraryFilterTests.collectionFilterMatchesMembers`. |

### 2. Edge cases

| Severity | Finding | Resolution |
|---|---|---|
| Low | If the user deletes a collection while it's the active filter, `activeFilter` keeps the stale `.collection("DeletedName")` value. `Book.bookCollections` gets nullified by SwiftData (`deleteRule: .nullify` on `BookCollection.books`), so post-deletion no book has the collectionName. `displayedBooks` returns `[]` — the user sees an empty library until they tap "All Books". | **Accepted as follow-up** — pre-fix behavior was equally broken (filter did nothing); post-fix at least the empty state communicates that the filter is active. Not in scope for this bug; would warrant a small UX bug ("reset filter to .allBooks when its collection is deleted"). Filing optional. |
| — | Empty collection: `book.collectionNames = []`; `.collection(name).matches → false`. Covered by `collectionFilterRejectsBooksWithNoCollections`. |
| — | Books in N collections: `collectionFilterMatchesOneOfMany` covers this. |
| — | Unicode/CJK names: `collectionFilterIsCaseAndUnicodeExact` exercises 読書リスト exact-match + non-match for partial 読書. |
| — | "All Books" reset path: `allBooksMatchesEverything` covers both empty and non-empty book.collectionNames. |

### 3. SwiftUI reactivity

| Severity | Finding |
|---|---|
| — | None. `displayedBooks` reads `viewModel.books` (an `@Observable`-backed property accessed via `@State` viewModel — observation tracking active) and `activeFilter` (`@State`). Both invalidations re-run the body; `displayedBooks` recomputes. Confirmed by the existing tap-zone test (post-fix simulator verification will exercise the actual re-render). |

### 4. `.tag` / `.series` stub safety

| Severity | Finding |
|---|---|
| Low | `LibraryFilter.matches` returns `true` for `.tag` and `.series` — pass-through. The sidebar still shows tag/series filter buttons (`CollectionSidebar.swift:140, 158`), so a user tapping a tag/series filter sees all books rather than the empty list a strict implementation would produce. **Pre-existing limitation**: tag/series filtering was never wired (the DTO has no tag/series field either). Pass-through is the conservative choice; strict-false would feel like a regression to anyone who briefly saw "no filter" before. The matches comment documents the gap. Filing not required for this bug. |

### 5. DTO default-param impact

Searched all callers of `LibraryBookItem(`:

| Site | Status |
|---|---|
| `PersistenceActor+Library.swift:32` | **Updated** — populates `collectionNames` from `book.bookCollections.map { $0.name }`. |
| `LibraryBookItemFileStateTests.swift:14, 73` | OK — uses default `[]`; tests don't depend on `collectionNames`. |
| `LibraryTestHelpers.swift:77` | OK — `.stub()` factory uses default `[]`; pre-fix tests don't depend on `collectionNames`. |
| `LibraryFilterTests.swift:20` | OK — explicitly passes `collectionNames` (this PR's own tests). |

No call site silently misses the field in a way that breaks correctness.

### 6. Concurrency / Sendable

| Severity | Finding |
|---|---|
| — | `LibraryBookItem` adds `let collectionNames: [String]` — `Sendable`/`Hashable`/`Equatable` derivation continues to hold (`String` and `[String]` are Sendable + Hashable). No new actor crossings. `book.bookCollections.map { $0.name }` reads SwiftData `@Relationship` from inside `PersistenceActor.fetchAllLibraryBooks`'s context; same context owns both `Book` and `BookCollection` instances, so the map is safe. The resulting `[String]` is value-typed and Sendable across the actor boundary. |

### 7. Performance

| Severity | Finding |
|---|---|
| — | `displayedBooks = viewModel.books.filter { activeFilter.matches($0) }` is O(n) per body re-evaluation. For a 1000-book library: ~1000 string-equality checks per render — single-digit microseconds on iPhone 17 Pro. SwiftUI re-evaluates body only when observed state changes (not per frame). Caching via `@State` would add complexity without measurable benefit. Accept. |

### 8. vreader compliance

| Severity | Finding |
|---|---|
| — | Swift 6 strict concurrency: clean (no new `Sendable` warnings; `LibraryFilter` already `Sendable`). File sizes: `LibraryView.swift` 743 → 752 lines (already over the 300-line guideline pre-fix; not made worse by 9-line addition; splitting is out of scope for this bug). FoliateJSEscaper / WKWebView bridge safety: not relevant (no JS surface touched). DEBUG gating: no DEBUG-only code added. |

## Test additions vs. plan

Plan: 7 unit tests on `LibraryFilter.matches`. Round 1 audit identified that
the fix has *two* halves (view-side filter + persistence projection), and only
the view-side half had unit coverage. Added 2 integration tests in
`CollectionPersistenceTests` to lock in the projection through real SwiftData:

- `fetchAllLibraryBooksProjectsCollectionNames` — book in 2 collections → DTO carries both names.
- `fetchAllLibraryBooksEmptyCollectionNames` — book with no collection memberships → empty array.

Total: 9 new tests, all passing under `xcodebuild test` (28 tests in 2 suites
when CollectionPersistenceTests + LibraryFilterTests are run together,
including the existing 19 collection-persistence tests).

## Manual audit evidence (Phase 4f)

Per `.claude/rules/47-feature-workflow.md` manual-fallback rules:

**Files read**:
- `vreader/Models/LibraryBookItem.swift` (full)
- `vreader/Models/Book.swift:109` (`bookCollections` relationship)
- `vreader/Models/BookCollection.swift:31` (inverse relationship + nullify rule)
- `vreader/Services/PersistenceActor+Library.swift` (full)
- `vreader/Views/Library/CollectionSidebar.swift` (full)
- `vreader/Views/LibraryView.swift` (full, 743 lines)
- `vreaderTests/Models/LibraryFilterTests.swift` (this PR's own)
- `vreaderTests/Models/LibraryBookItemFileStateTests.swift` (call-site sweep)
- `vreaderTests/ViewModels/LibraryTestHelpers.swift` (stub factory)
- `vreaderTests/Services/CollectionPersistenceTests.swift` (added integration tests)

**Symbols / signatures verified**:
- `Book.bookCollections: [BookCollection]` — confirmed at `Book.swift:109` with `.nullify` deleteRule on the inverse side.
- `BookCollection.name: String` — confirmed at `BookCollection.swift` (canonical lowercased dedup at create time per `CollectionPersistenceTests.createCollectionRejectsDuplicate`).
- `LibraryBookItem` `Sendable + Identifiable + Equatable + Hashable` — derivation continues to hold with `let collectionNames: [String]` added.
- `LibraryFilter` already `Equatable, Hashable, Sendable` — `.matches(_:)` adds nothing that would break those.

**Edge cases checked**: see Dimension 2 above.

**Risks accepted**:
- Stale `activeFilter` after collection deletion — Low severity, follow-up candidate, not in scope.
- `.tag`/`.series` pass-through — pre-existing, documented in the `matches` comment.

**Tests added or intentionally deferred**:
- Added: 7 helper-level tests + 2 integration tests.
- Deferred: full LibraryView ForEach-render test would require XCUITest harness; the slice is covered indirectly by simulator pre-FIXED verification (Phase 6a) and explicitly by the device verification gate post-merge (Phase 9b).

## Round 2 — pre-FIXED simulator verification finding

The Phase 6a pre-FIXED simulator verification (per `/fix-issue` skill — re-run
the original repro with the working-tree binary BEFORE the FIXED flip) caught
an issue the static manual audit missed:

| Severity | Finding | Resolution |
|---|---|---|
| **High** | `bookContextMenu`'s "Add to Collection" branch (`LibraryView.swift:625-643`) writes to persistence but does NOT refresh `viewModel.books`. The `LibraryBookItem.collectionNames` stays stale (`[]`) in memory. Tapping the now-populated collection in the sidebar then shows an empty library because the stale rows don't match `.collection(name).matches`. The persistence-side projection is correct; it's the in-memory snapshot that goes stale. Diagnosed by relaunching the app — after relaunch the row had the right `collectionNames` (proving persistence was correct, only the in-memory cache was stale). | **Fixed in commit 6f2eebb** — added `await viewModel.refresh(force: true)` immediately after the existing `collectionRecords` refresh. Re-verified end-to-end: add EPUB to TestCollection → tap TestCollection → only EPUB shown; tap All Books → both books restored. |

This finding doesn't invalidate the static audit (it focused on the matcher
helper and the persistence projection, both of which are correct in
isolation); it sits in the integration seam between context-menu mutation and
view re-render that wasn't covered by the audit dimensions. Pre-FIXED verify
exists for exactly this class of issue.

### Round 2 evidence

- `/tmp/bug155-verify/05-fresh-seed.png` — fresh library with 2 books after seed.
- `/tmp/bug155-verify/06-filter-narrowed-to-epub.png` — after Add-to-Collection + filter tap, ONLY the EPUB is visible (war-and-peace correctly hidden).
- `/tmp/bug155-verify/07-all-books-reset.png` — tap All Books → both books restored.

## Verdict

**ship-as-is** — zero Critical/High/Medium findings remaining after Round 2.
Two Low findings documented as accepted with rationale; both are
pre-existing-class issues that the fix does not worsen. Round 2's High
finding was caught by pre-FIXED simulator verification and fixed before
the FIXED flip.
