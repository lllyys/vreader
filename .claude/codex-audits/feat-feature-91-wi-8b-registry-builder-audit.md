---
branch: feat/feature-91-wi-8b-registry-builder
threadId: 019e9331-628b-78e2-b872-cfd24bb31db1
rounds: 2
final_verdict: ship-as-is
date: 2026-06-04
---

# Codex Audit — Feature #91 WI-8b (slice 4: AgenticToolRegistryBuilder)

Gate-4 implementation audit (rule 47). Independent Codex runner via
`scripts/run-codex.sh -e high` (author/auditor separation, rule 48; rule-53
stdin-isolated watchdog).

## Scope

WI-8b slice 4 — assemble the `AIToolRegistry` for an agentic chat turn:

- `vreader/Services/AI/Tools/AgenticToolRegistryBuilder.swift` (new) — pure
  assembly: `search_current_book` only when BOTH an open-book fingerprint AND a
  live `SearchProviding` are present; `search_other_books` (wired with
  `currentBook?.canonicalKey` to exclude the open book) + `get_book_content` always.
- `vreaderTests/Services/AI/Tools/AgenticToolRegistryBuilderTests.swift` (new).

## Round 1 — findings (threadId 019e9331-628b-78e2-b872-cfd24bb31db1)

**No code findings.** The auditor confirmed the builder matches its contract
(current-book tool gated by both inputs; library tools always included;
general-chat non-empty; `SearchOtherBooksTool` excludes the open book at runtime),
and the Swift 6 isolation is clean (stateless enum, all stored existentials
`Sendable`-constrained). Relying on each tool's default caps is fine for v1.

| File:line | Severity | Issue | Resolution |
|---|---|---|---|
| AgenticToolRegistryBuilderTests.swift | **Medium** | The tests proved only the tool NAMES, not the runtime behavior that `search_other_books` is built with `currentBook?.canonicalKey` (excludes the open book). A regression to `nil` would still pass. | **Fixed.** `searchOtherBooksExcludesOpenBook` builds the registry with an open-book fingerprint, runs `search_other_books` via `registry.run(...)` against a `SpyLibraryBackend` (2 indexed epub books), and asserts the OTHER book is searched while the open book is NOT. |

## Round 2 — verification (threadId 019e9343-f5d0-7ea2-89cc-4a438ea35ce8)

**RESOLVED.** No new issues — the runtime test would fail if the builder stopped
passing `currentBook?.canonicalKey` into `SearchOtherBooksTool`.

## Verdict

**ship-as-is.** Zero open Critical/High/Medium after round 2. `AgenticToolRegistryBuilderTests`
green (4 tests: all-three with an open book, no-book omits search_current_book,
book-without-search omits it, and the behavioral open-book exclusion).

The only remaining WI-8b work — the `AIChatViewModel.sendMessage` branch
(driver-via-`sendToolTurn` vs stream) + citation suppression + the dependency-
acquisition wiring at the chat construction site, `docs/architecture.md`, and
Gate-5 device verification — completes Feature #91 to `DONE`/`VERIFIED`.
