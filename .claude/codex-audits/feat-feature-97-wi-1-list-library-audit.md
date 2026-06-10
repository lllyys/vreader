---
branch: feat/feature-97-wi-1-list-library
threadId: feat97-impl-run-codex
rounds: 2
final_verdict: ship-as-is
date: 2026-06-10
---

# Gate-4 Codex audit — Feature #97 WI-1 (`list_library` agentic tool)

Independent audit via `scripts/run-codex.sh` (gpt-5.4), read-only.

## Round 1

| file:line | severity | issue | resolution |
|---|---|---|---|
| ListLibraryTool.swift (empty branch) | Medium | `include_current_book=false` filtering a non-empty library to zero still returned "The library has no books." — factually wrong. | **Fixed** — distinguish `deduped.isEmpty` ("no books") from `filtered.isEmpty` ("No other books in the library (only the currently-open book)."). Test `excludingTheOnlyBookSaysOtherNotNone`. |
| ListLibraryTool.swift (progress) | Medium | `progressFraction > 1` rendered "134%"; a non-finite `+.infinity` would TRAP in `Int(_:)`, violating the never-crash `AITool` contract. | **Fixed** — `guard progress.isFinite, progress > 0` + `min(progress, 1)`. Test `progressIsClampedAndNonFiniteSafe`. |

Round-1 also confirmed: the system-prompt edit keeps the untrusted-data framing; the
restore regex is anchored + ReDoS-safe; the static `NSRegularExpression` is fine; no
new egress beyond the existing library-backed agentic tools.

## Round 2

Both Medium findings confirmed **RESOLVED**; no new issues. `run()` still satisfies
the `AITool` non-throwing contract for any input (nil-safe decode, caught backend
failure → `isError`, no input-driven crash path).

## Gate-5 verification note (verification-exception)

The full acceptance — a real tool-use LLM choosing `list_library` for a "what's in
my library?" query — cannot be reproduced with the deterministic `MockAIProvider`
(it does NOT implement `supportsToolUse`, so the agentic gate falls back to
streaming and never calls a tool). Only real Anthropic / OpenAI-compatible
providers support tool-use, and none is configured for an autonomous run. Verified
instead at the real subsystem boundaries:
- `ListLibraryToolTests` (15) — the tool's logic against a real `LibrarySearchBackend`.
- `AgenticToolRegistryBuilderTests.listLibraryDispatchesThroughRegistry` — a
  `list_library` `ToolCall` dispatched through the ASSEMBLED registry (the SAME
  `registry.run(call)` boundary `AgenticChatDriver` invokes per turn) reaches the
  real tool and enumerates the library (incl. CJK).
- The existing #91 `AgenticChatDriverTests` cover the driver↔registry tool-call loop.
- `AIChatAgenticSupportTests` — the system prompt advertises listing.

Evidence: `dev-docs/verification/feature-97-20260610.md`.

## Verdict

**ship-as-is.** Both Medium fixed + pinned; 26 tests green across the 3 suites;
2-round audit clean.
