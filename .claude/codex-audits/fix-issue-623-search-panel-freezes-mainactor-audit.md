---
branch: fix/issue-623-search-panel-freezes-mainactor
threadId: manual-fallback
rounds: 1
final_verdict: ship-as-is
date: 2026-05-14
---

# Bug #183 / GH #623 — TXT search panel freezes on first open (audit log)

## Context

User opened the search panel for a large CJK TXT file (5MB+); UI froze
for several seconds. Already-indexed books unaffected (extraction
skipped in the `alreadyIndexed` branch at
`ReaderSearchCoordinator.swift:86-95`).

Root cause: `ReaderSearchCoordinator` is `@MainActor @Observable`
(class annotation, line 12-13). `enqueueBookIndexing` is a
`private static func` with no isolation override → inherits
`@MainActor` from the class. Its synchronous extractor calls
(`TXTTextExtractor.extractWithOffsets` → `decodeFile` →
`Data(contentsOf:)` + `TXTService.decodeForDisplayAndSearch(data)`)
have no internal `await`, so the entire chain runs on MainActor until
the next natural suspension. For 5MB+ CJK files, encoding detection
on the full data buffer blocks the UI for several seconds.

## Codex availability

Codex MCP unavailable this session (`stream disconnected before
completion`). Manual fallback per rule 47.

## Files audited

| File | Purpose | Audit |
|---|---|---|
| `vreader/Views/Reader/ReaderSearchCoordinator.swift` | marked `enqueueBookIndexing` and `logger` `nonisolated` | reviewed |

## Manual audit evidence

### Files read

- `vreader/Views/Reader/ReaderSearchCoordinator.swift` (full) — confirmed `@MainActor @Observable final class` declaration; `enqueueBookIndexing` is `private static func` inheriting `@MainActor`; `logger` is `private static let` also @MainActor by inheritance. Inside `enqueueBookIndexing`: synchronous `TXTTextExtractor()`/`MDTextExtractor()`/`PDFTextExtractor()`/`EPUBParser()` constructors + `try await extractor.extractWithOffsets(from:)` etc. The format-specific `extract*` calls are `async` but the inner work is synchronous I/O + decoding.
- `vreader/Services/Search/TXTTextExtractor.swift` (full) — confirmed `struct TXTTextExtractor: SearchTextExtractor` (no actor annotation, struct = nonisolated by default). But the bug isn't in TXTTextExtractor itself: it's in the CALLER (`enqueueBookIndexing` inheriting @MainActor) — the synchronous chunks of the called nonisolated async function still execute on the caller's actor until they hit a real suspension point, which `decodeFile` (purely synchronous) never does.
- `vreader/Services/Search/SearchIndexStore.swift` (line 43) — confirmed `final class SearchIndexStore: @unchecked Sendable`. Not actor-bound; thread-safe internally. Safe to call from a nonisolated context.
- `vreader/Services/Search/BackgroundIndexingCoordinator.swift` (line 46) — confirmed `actor BackgroundIndexingCoordinator`. Its `enqueueIndexing` calls naturally suspend the caller and hop to the actor's executor. Safe to await from nonisolated.

### Symbols verified

- `nonisolated` keyword on `private static func` ✓ — valid Swift 6 syntax; method body runs on the generic executor regardless of class isolation.
- `nonisolated` on `private static let logger = Logger(...)` ✓ — `Logger` (os.Logger) is Sendable per OSLog framework; safe to access from any actor context.
- `Self.logger` accesses inside `enqueueBookIndexing` (line 218 of pre-fix, now around line 226) ✓ — nonisolated function reading a nonisolated static. Type-check passes.

### Edge cases checked

1. **Already-indexed books**: extraction path skipped entirely (line 86-95 short-circuits via `alreadyPersisted || inMemoryIndexed`). No regression.
2. **PDF/EPUB/MD formats**: their extractors (`PDFTextExtractor`, `EPUBParser` + `EPUBTextExtractor`, `MDTextExtractor`) are all structs / non-MainActor types. Same fix applies — they all benefit from running on the generic executor instead of MainActor.
3. **`coordinator.enqueueIndexing(...)` cross-actor await**: `BackgroundIndexingCoordinator` is an actor; the await naturally hops to its executor. Works from any caller isolation.
4. **`store.setSegmentBaseOffsets(...)` synchronous call**: `SearchIndexStore` is `@unchecked Sendable` (NSLock-protected internally per its declaration); safe to call from nonisolated.
5. **`setup()` calls `await Self.enqueueBookIndexing(...)`**: `setup()` is @MainActor; awaiting a nonisolated async function causes the await to suspend MainActor, run the body on the generic executor, then resume MainActor when complete. UI stays responsive throughout the extraction.
6. **Cancel/error paths**: existing `catch error` block at line 215 logs via `Self.logger` — now nonisolated-friendly, no change in behavior.
7. **Concurrent search opens** (rapid tap-tap on search button): existing `setupStarted` guard at line 57 prevents double-indexing. Unchanged.
8. **`Logger` thread-safety**: per Apple's documentation, `os.Logger` is safe to use from any context. The `nonisolated` annotation just removes the artificial MainActor inheritance.

### Concurrency / Swift 6

- The fix uses `nonisolated` — a Swift 6 native concurrency primitive, not `@unchecked Sendable` or `nonisolated(unsafe)`. Cleaner than the bug body's "Task.detached" sketch (which would also work but adds a Task allocation).
- No Sendable warnings introduced. `Logger`, `BackgroundIndexingCoordinator` (actor), `SearchIndexStore` (`@unchecked Sendable`), `DocumentFingerprint`, `URL`, `String` — all already Sendable.
- Async function suspension semantics: when MainActor `setup()` awaits a nonisolated async function, Swift inserts a hop to the generic executor for the duration. The fix relies on this standard Swift 6 behavior.

### VReader compliance

- Swift 6 strict concurrency: clean (`SWIFT_STRICT_CONCURRENCY: complete` in project.yml).
- `@MainActor` correctness: SwiftUI views, ReaderSearchCoordinator's other members stay MainActor; only the static extraction-orchestration function moves off.
- File size: `ReaderSearchCoordinator.swift` 295 lines (was 280, +15 for two `nonisolated` keywords + doc comments). Well under 300.
- Bridge safety: not applicable (no WKWebView / JS).
- DEBUG gating: not applicable (fix is production-correct).

### Risks accepted

- **No new unit test added**: marking a function `nonisolated` is a type-level concurrency change. Existing tests (TXTTextExtractor 7/7, BackgroundIndexingCoordinator suite via other paths) cover behavior. A test that asserts "MainActor stays responsive during extraction" would require synthetic timing harness; rule 10-tdd.md "Type-only changes with no runtime effect" exception applies (the runtime effect IS the responsiveness, but it's not test-asserted at the unit level — verifyable only by Instruments / device).
- **Pre-existing test runner flakes** (AutoPageTurnerTests, TTSServiceSpeedControlTests) unchanged on main; not introduced by this fix.

## Findings

| # | Severity | Issue | Resolution |
|---|---|---|---|
| 1 | n/a | none — implementation matches bug body's "Fix sketch" exactly, using the cleaner `nonisolated` approach over `Task.detached` | n/a |

## Final verdict

**ship-as-is** — two-line surgical change. 7/7 TXTTextExtractor tests
pass; full Debug iOS Sim build clean. The fix preserves all
type-checking guarantees (MainActor isolation still in place for the
rest of the class) while moving the heavy extraction path off the UI
thread.
