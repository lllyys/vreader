---
branch: feat/feature-88-wi-1-chat-session-model
threadId: 019e96f1-bb4d-7c81-866e-5be26fa9f552
rounds: 2
final_verdict: ship-as-is
date: 2026-06-05
---

# Gate-4 Implementation Audit — Feature #88 WI-1 (ChatSession @Model + SchemaV9 + Codable envelope)

Independent Codex audit (author = implementer subagent + orchestrator fixes; auditor = Codex via `scripts/run-codex.sh`). 2 rounds → `ship-as-is`.

## Scope
`vreader/Models/ChatSession.swift`, `ChatSessionPayload.swift`, `Migration/SchemaV9.swift`, `vreader/Services/ChatSessionRecord.swift`, `vreader/Models/Book.swift` (cascade), `Migration/SchemaV1.swift` (plan), `vreader/App/VReaderApp.swift` (container), + 2 test files + the SchemaV8MigrationTests ripple.

## Round 1 — Codex `019e96e9-71aa-7a61-95a6-38ccb9e93658`
Migration wiring, the `Book.chatSessions`/`ChatSession.book` cascade + inverse, and the book-delete cascade test all confirmed **correct** (lightweight additive migration; no inverse-ambiguity). 3 Medium:
| file:line | sev | issue | resolution |
|---|---|---|---|
| ChatSessionPayload.swift:60 | Medium | `encode` collapsed any failure to empty `Data()` → a malformed citation could silently wipe a whole conversation on the next save | **Fixed**: `encode` returns `Data?` (nil on failure, never empty); `ChatSession.init` assigns the optional directly; the WI-2 save layer skips the write on nil (contract stated in comments). |
| ChatSessionPayload.swift:24 | Medium | `payloadVersion` written but never read → nominal forward-compat | **Fixed**: `decode` now gates on `payload.version <= payloadVersion`; a future version returns `[]` (not silently flattened); new `isReadable(_:)` lets the WI-2 save layer preserve a future-version blob. Tests added (future-version, readable current/nil/garbage). |
| SchemaV9MigrationTests.swift:77 | Medium | The "V8 store" fixture is synthesized from live model types, not a frozen pre-V9 snapshot | **Accepted with rationale**: a repo-wide migration-test pattern (every `SchemaV*MigrationTests` uses live types); the migration WIRING is Codex-verified correct + the populated-store round-trip + cascade are tested; the real pre-V9 device-store assurance is the planned Gate-5 device-migration verification (plan R3). |

## Round 2 — Codex `019e96f1-bb4d-7c81-866e-5be26fa9f552`
"No remaining or new Critical/High/Medium issues." M1 + M2 resolved; M3 acceptance "reasonable, I would not block WI-1 on the live-types pattern." Verdict: `ship-as-is`.

## Verdict
`ship-as-is`. The schema migration is additive/lightweight (SchemaV9 = V8's 11 + ChatSession; `VReaderMigrationPlan` appends V9; `VReaderApp` builds `Schema(SchemaV9.models)`); the `Book.chatSessions` cascade is parent-side + book-delete-cascade-tested; the Codable persistence envelope is decoupled from the non-Codable domain types, never silently wipes (encode→`Data?`), and is forward-compat-gated (version read). `SchemaV9MigrationTests` (populated V8→V9 round-trip + cascade) + `ChatSessionPayloadTests` (round-trip incl. CJK/citations/version-gate) → `RUN-TESTS RESULT: SUCCEEDED`.

## WI-2 carry-forward (stated for the next WI)
The WI-2 save layer MUST: skip the `messagesData` write when `encode` returns nil; NOT re-encode a session whose stored blob has `isReadable == false` (preserve a future-version blob); maintain the denormalized `lastMessageSnippet`/`messageCount`/`updatedAt` on every save.
