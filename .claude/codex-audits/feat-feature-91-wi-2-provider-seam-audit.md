---
branch: feat/feature-91-wi-2-provider-seam
threadId: 019e9097-7a7f-7980-9b32-f8e5748afe40
rounds: 2
final_verdict: ship-as-is
date: 2026-06-03
---

# Codex Audit — Feature #91 WI-2 (AIProvider tool-use capability seam)

Gate-4 implementation audit (rule 47). Independent Codex runner via
`scripts/run-codex.sh -e high` (author/auditor separation, rule 48).

## Scope

Foundational WI-2 — the `AIProvider` tool-use capability seam (no real provider
impl yet):

- `vreader/Services/AI/AIProvider.swift` — two protocol REQUIREMENTS
  (`var supportsToolUse: Bool { get }`, `func sendToolRequest(_:) async throws -> AIToolTurn`)
  with default impls in an `extension AIProvider` (`false` / throws
  `AIError.toolUseUnsupported`). A provider opts IN by overriding both.
- `vreader/Services/AI/AIError.swift` — `case toolUseUnsupported` + message.
- `vreader/Utils/ErrorMessageAuditor.swift` — the new case in the exhaustive `sanitizeAI` switch.
- `vreaderTests/Services/AI/AIProviderToolSeamTests.swift` (new).

## Round 1 — findings (threadId 019e9097-7a7f-7980-9b32-f8e5748afe40)

| File:line | Severity | Issue | Resolution |
|---|---|---|---|
| AIProviderToolSeamTests.swift:66 | **Medium** | The suite exercised the override only on the CONCRETE `ToolProvider`, not through `any AIProvider` — so the classic protocol-extension dispatch trap (would a default in an extension statically dispatch?) wasn't pinned by tests. | **Fixed (test-only).** The dispatch-critical tests now bind `let provider: any AIProvider = …` and assert: a `NonToolProvider` existential → `false` + throws `.toolUseUnsupported`; a `ToolProvider` existential → `true` + returns its stubbed `AIToolTurn` (the override wins through the existential). |

**No production-code findings.** Codex confirmed the seam is shaped correctly for
dynamic dispatch (both members are protocol REQUIREMENTS, so the override is
witness-table-dispatched even through `any AIProvider`), existing conformers/stubs
inherit the defaults unchanged, fail-closed via `.toolUseUnsupported` is
appropriate, and the `AIError` / `ErrorMessageAuditor` additions are complete.

## Round 2 — verification

The Medium was a test-coverage gap on an already-correct production seam. The fix
adds the exact existential-dispatch tests Codex requested; they **pass**
(`overridingDispatchesThroughExistential` asserts a `ToolProvider` held as
`any AIProvider` returns `true` + its turn, NOT the default — i.e. the override is
dynamically dispatched). The passing existential run IS the verification the
finding asked for; no production logic changed, so no separate Codex re-audit was
needed for a test-only addition that demonstrably exercises the dispatch path.

## Verdict

**ship-as-is.** Zero open Critical/High/Medium. `AIProviderToolSeamTests` green,
including the existential-dispatch assertions. (Compile fix: the new `AIError`
case was added to the exhaustive `ErrorMessageAuditor.sanitizeAI` switch — the
only other exhaustive `AIError` switch in the codebase; the build confirms no others.)
