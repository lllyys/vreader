---
branch: feat/feature-91-wi-8b-registry-wiring
threadId: 019e93... (bsj24zmdp r1 / bmgjglz0t r2 / bxwq161cu r3)
rounds: 3
final_verdict: ship-as-is
date: 2026-06-05
---

# Codex Audit — Feature #91 WI-8b (slice 7: construction-site registry wiring — COMPLETING)

Gate-4 implementation audit (rule 47). Independent Codex runner via
`scripts/run-codex.sh -e high` (author/auditor separation, rule 48; rule-53
stdin-isolated watchdog).

## Scope

WI-8b slice 7 — the **completing** slice that activates the agentic chat:

- `vreader/Services/Search/PersistentSearchIndex.swift` (new) — the Services-layer
  source of truth for the on-disk FTS index location + store construction
  (`makeStore()` in-memory-fallback for the reader; `makeStoreStrict()` throws for
  the agentic path). `ReaderSearchCoordinator` delegates to it (behavior-identical).
- `AgenticToolRegistryBuilder.buildLive` (async) — opens the persistent store
  off-main (strict), gates `search_current_book` on the open book's index
  eligibility + restores TXT/MD offsets, assembles the production adapters.
- `AIChatViewModel` — `agenticRegistry` is now `private(set) var` + `setAgenticRegistry`.
- `ReaderAICoordinator` / `LibraryView` — build the registry OFF-MAIN under the
  `agenticTools` flag and inject it (in-book: current book + library; general: library).
- `LibraryBookSearchGate` — `requiresReindex` exclusion narrowed to TXT-only.
- `docs/architecture.md` — agentic cluster + `agenticTools` flag.

## Round 1 — findings (bsj24zmdp)

Extraction confirmed drift-free. Findings:

| Severity | Issue | Resolution |
|---|---|---|
| **High** | `buildLive` used `makeStore()` → empty in-memory fallback → agentic search against an empty DB (silent coverage loss). | **Fixed.** `makeStoreStrict()` (file-backed, throws, no fallback); `buildLive` uses it via `Task.detached`; the caller's `try?` → nil → non-agentic chat. |
| **High** | `search_current_book` on a fresh `SearchService` had no eligibility gate / no TXT/MD offset restore → hits dropped; unindexed → misleading "No matches". | **Fixed.** `buildLive` reads the open book's index state, runs `LibraryBookSearchGate.evaluate`; `.searchable` → restore TXT/MD offsets + wire the tool; `.excluded` → omit it (search_other_books still excludes the open book by key). |
| **Medium** | Sync `buildLive()` ran the cold SQLite open on `@MainActor`. | **Fixed.** `buildLive` async + `Task.detached` open; `agenticRegistry` settable; both sites build off-main in a `Task { @MainActor [weak vm] }` and inject. |

## Round 2 — verification (bmgjglz0t)

All three round-1 findings RESOLVED. One **new Medium**: the gate excluded both
TXT+MD on `requiresReindex`, but `ReaderSearchCoordinator.setup` force-reindexes
TXT only — so a legacy MD row the reader still searches was silently omitted from
agentic search. **Fixed.** The gate's `requiresReindex` exclusion is now TXT-only
(MD offsets are stable across decode versions), matching the reader. Tests
`txtRequiresReindexExcluded` + `mdRequiresReindexNotExcluded`; search_other_books
(which shares the gate) regression green.

## Round 3 — verification (bxwq161cu)

**PASS, no findings.** The gate matches the reader's source of truth; both agentic
paths (search_other_books + buildLive's search_current_book) consume it.

## Verdict

**ship-as-is.** Zero open Critical/High/Medium after round 3. The agentic chat is
now fully wired: `agenticTools` ON → the registry builds off-main (over the SAME
persisted FTS index the reader uses) and the chat routes through the agentic loop.
Default OFF → byte-for-byte the existing chat. Test gate green (gate + tool +
registry-builder + VM agentic + streaming-regression suites). 

This is the FINAL WI — Feature #91's implementation is complete (DONE). `VERIFIED`
is the post-merge Gate-5 device verification (a human-gated default-ON flip,
symmetric with #42 G2): drive a real Anthropic provider through a live tool-using
chat on the simulator.
