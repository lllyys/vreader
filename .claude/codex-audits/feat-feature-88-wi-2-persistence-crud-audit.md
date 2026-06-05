---
branch: feat/feature-88-wi-2-persistence-crud
threadId: 019e9703-d024-7d01-8345-7eb3d61bf8dc
rounds: 2
final_verdict: ship-as-is
date: 2026-06-05
---

# Gate-4 Implementation Audit — Feature #88 WI-2 (PersistenceActor+ChatSessions CRUD)

Independent Codex audit (author = implementer subagent + orchestrator fixes; auditor = Codex via `scripts/run-codex.sh`). 2 rounds → `ship-as-is`.

## Scope
`vreader/Services/ChatSessionPersisting.swift` (protocol), `vreader/Services/PersistenceActor+ChatSessions.swift` (CRUD), `vreaderTests/Services/PersistenceActor+ChatSessionsTests.swift` (19 tests), + the `vreader/Models/ChatSessionPayload.swift` `isReadable` refinement.

## Round 1 — Codex `019e96fd-2445-7a93-8afd-f30093756f32`
CRUD verified correct vs the `+Highlights` template (fresh `ModelContext` per call, `#Predicate`/`fetchLimit`, `book.chatSessions.append` for cascade, DTO-only returns, book-not-found throws `ImportError.bookNotFound`); concurrency clean (actor + per-call context, Sendable DTOs, no `@Model` escape); `snippet(for:)` grapheme-safe (`String.prefix` on `Character`s). 2 Medium:
| file:line | sev | issue | resolution |
|---|---|---|---|
| PersistenceActor+ChatSessions.swift:108 | Medium | `isReadable` decoded the FULL `ChatSessionPayload` shape → a future blob with an INCOMPATIBLE message shape fails decode → treated as readable → overwritten (the WI-1 M2 fix was incomplete) | **Fixed in `ChatSessionPayload.swift`**: a minimal `VersionHeader {version:Int}` decode (`headerVersion`); both `decode` and `isReadable` gate on the top-level version ONLY — a future version is protected even when its full shape can't decode. |
| PersistenceActor+ChatSessionsTests.swift:347 | Medium | The future-version test only covered a higher-version blob still decodable by today's shape | **Fixed**: added `updatePreservesFutureVersionBlobWithIncompatibleShape` (version 4242 + an undecodable message shape → `isReadable == false` + byte-identical preserve after `updateChatSession`). |

## Round 2 — Codex `019e9703-d024-7d01-8345-7eb3d61bf8dc`
"No remaining Critical/High/Medium findings." M1 + M2 resolved; the normal v1 decode path + existing `ChatSessionPayloadTests` unaffected. Verdict: `ship-as-is`.

## Verdict
`ship-as-is`. `ChatSessionPersisting` + `PersistenceActor+ChatSessions` mirror the `Highlight` stack; the WI-1 carry-forward contract is fully met (update skips the write on `encode == nil`, preserves a future/undecodable versioned blob via the header-only `isReadable`, maintains denormalized `lastMessageSnippet`/`messageCount`/`updatedAt`, summaries sorted `updatedAt` DESC, book-delete cascade tested). 20 tests at the real `PersistenceActor` + in-memory SchemaV9 boundary → `RUN-TESTS RESULT: SUCCEEDED`.
