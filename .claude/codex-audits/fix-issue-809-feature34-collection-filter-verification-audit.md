---
branch: fix/issue-809-feature34-collection-filter-verification
threadId: 019e34ac-efb8-77c2-bbc8-1a9671712754
rounds: 3
final_verdict: ship-as-is
date: 2026-05-17
---

# Codex Audit — Issue #809 (Bug #210)

Feature #34 collection-filter verification XCUITest
(`Feature34CollectionsVerificationTests.test_verify_feature_34_add_book_to_collection_filters_library`)
fails after the feature #60 library re-skin.

## Root cause (confirmed by running the failing test + dumping the UI a11y hierarchy)

The test creates a collection, long-presses a book card, taps the
"Add to Collection" context-menu submenu, picks the collection, opens
the sidebar, taps the collection filter row, and asserts
`visibleCards.count > 0`. It failed **before** the assertion, at step 5:

```swift
let filterRow = app.buttons.matching(
    NSPredicate(format: "label CONTAINS[cd] 'Filter Test Collection'")
).firstMatch
filterRow.tap()
```

Feature #60's library re-skin added `LibraryFilterChips` — a
per-collection filter-chip row at the top of the library screen. After
the test creates "Filter Test Collection", that chip's accessibility
**label** is exactly the collection name, so `label CONTAINS 'Filter
Test Collection'` matches **two** buttons: the chip and the sidebar
filter row. `firstMatch` resolved to the chip (enumerated first in the
a11y tree), which sits **behind** the open sidebar overlay → not
hittable → `Computed hit point {-1, -1}` → tap fails after 3 retries →
test crashes before the final `XCTAssertGreaterThan`.

The production tagging flow is **correct** — the failure-snapshot UI
hierarchy showed the sidebar row "Filter Test Collection, **1**", i.e.
the book WAS tagged. This is XCUITest fragility introduced by the
re-skin, not a production bug. Step 3's `'Collection'` predicate was
also latently ambiguous (collides with the "Collections" toolbar
button label + the chip).

## Fix (4 files)

1. `vreader/Views/Library/CollectionSidebar.swift` — added
   `.accessibilityIdentifier("collectionFilterRow_\(collection.name)")`
   to the per-collection sidebar filter-row `Button` (the only
   collection-scoped control lacking an identifier; `filterAllBooks`
   already had one).
2. `vreader/Views/Library/LibraryView+Body.swift` — added
   `.accessibilityIdentifier("addToCollectionMenu")` to the "Add to
   Collection" `Menu` and
   `.accessibilityIdentifier("addToCollectionMenuItem_\(collection.name)")`
   to each per-collection `Button` inside it.
3. `vreaderUITests/Helpers/TestConstants.swift` — added
   `addToCollectionMenu` + `addToCollectionMenuItem(_:)` /
   `collectionFilterRow(_:)` dynamic-identifier helpers (mirrors the
   existing `bookCard(_:)` pattern).
4. `vreaderUITests/Verification/Feature34CollectionsVerificationTests.swift`
   — re-pointed both tests' collection-scoped queries to the stable
   identifiers via `app.buttons[id]` instead of `label CONTAINS`
   substrings.

Adding accessibility identifiers to existing controls is additive /
inert in production — no UI surface change (rule 51 carve-out).

## Round 1 — 2 findings

| File:line | Severity | Issue | Resolution |
|---|---|---|---|
| `Feature34CollectionsVerificationTests.swift:85` | Medium | Sibling test `create_collection_appears_in_sidebar` still used `label CONTAINS 'Verification Suite Collection').firstMatch` — could resolve to the chip, so the test could "pass" without the sidebar actually showing the collection. | **Fixed** — re-pointed the assertion to `app.buttons[AccessibilityID.collectionFilterRow(collectionName)]` with `waitForExistence`; hoisted `collectionName` to a local constant. |
| `Feature34CollectionsVerificationTests.swift:113` | Low | The dynamic-identifier lookup assumed the collection name is persisted byte-for-byte; production trims whitespace + truncates to 100 chars, so a future non-canonical fixture would mismatch. | **Fixed** — `createCollection(named:)` now canonicalizes (`trimmed.prefix(100)`) and asserts equality, failing loudly on a non-canonical fixture. |

## Round 2 — 1 finding

| File:line | Severity | Issue | Resolution |
|---|---|---|---|
| `Feature34CollectionsVerificationTests.swift:48` | Low | `precondition` is the wrong failure mechanism in an XCUITest helper — it traps the whole test process instead of producing a normal XCTest failure tied to the test method. | **Fixed** — replaced with `XCTAssertEqual(canonical, name, ..., file:line:)`; added `file`/`line` forwarding parameters so the failure is attributed to the caller's line. With `continueAfterFailure = false` the test stops cleanly. |

## Round 3 — 0 findings

Codex confirmed all fixes correct: the sibling test now targets
`collectionFilterRow_<name>` directly (chip can no longer satisfy the
assertion); the canonicalization check mirrors production exactly
(`PersistenceActor.createCollection` and `BookCollection.init` both do
`trimmingCharacters(in: .whitespacesAndNewlines)` then `prefix(100)`);
`XCTAssertEqual(..., file:line:)` is the correct XCTest mechanism. No
remaining fragile `label CONTAINS` collection-name queries — the only
remaining `firstMatch` is the `bookCard_`-prefixed card query, which is
appropriately scoped and unrelated to the feature #60 collision.

## Verdict

`ship-as-is` — zero open Critical/High/Medium/Low findings after 3 rounds.
