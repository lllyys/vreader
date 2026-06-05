# Feature #89 — Back up AI conversation sessions & history via WebDAV (Gate-1 Plan)

## Model Assumptions Verified

Every symbol below was read in the working tree (not assumed). File:line or signature cited.

**Backup schema constants** (`vreader/Services/Backup/BackupSectionDTOs.swift`)
- `let kBackupCurrentSchemaVersion = 2` — line 15. (Row's "bump 2→3" premise confirmed: currently 2.)
- `let kBackupAcceptedSchemaVersions: Set<Int> = [1, 2]` — line 21.
- `protocol BackupVersionedEnvelope { var schemaVersion: Int { get } }` — lines 25–27.
- `enum BackupRestoreError: Error, Sendable, Equatable { case unsupportedSchemaVersion(section:actual:supported:); case partialFailure(section:failed:total:) }` — lines 30–35.
- Reading-history DTOs are split into a sibling file with a pointer comment at lines 278–283 ("live in `BackupReadingHistory.swift` … New in backup schema v2"). The exact sibling-file precedent #89 mirrors.

**Reading-history additive-section precedent (#58 WI-5)** — threads through all four layers, confirmed:
- DTO: `BackupReadingHistoryEnvelope: Codable, Sendable, Equatable, BackupVersionedEnvelope { schemaVersion; sessions: [BackupReadingSession]; stats: [BackupReadingStats] }` — `BackupReadingHistory.swift:19–23` (59 lines, under 300).
- Collector: `func collectReadingHistory() async throws -> Data` — `BackupDataCollector.swift:240–280`; emits `schemaVersion: kBackupCurrentSchemaVersion`.
- Restorer: `func restoreReadingHistory(from data: Data) async throws` — `BackupDataRestorer.swift:103–108`; `decodeAndValidate(...)` then `persistence.restoreReadingHistory(envelope)`.
- PersistenceActor fetch: `fetchAllReadingSessions()` (`PersistenceActor+Stats.swift:65`) + `fetchAllReadingStats()` (`:90`).
- PersistenceActor restore: `restoreReadingHistory(_ envelope:) async throws` — `PersistenceActor+ReadingHistory.swift:35` (separate file — "+Backup.swift already over ~300 lines", :4–6).
- Protocol surface + defaults: `BackupDataCollecting.collectReadingHistory` default at `WebDAVProvider.swift:59–67`; `BackupDataRestoring.restoreReadingHistory` no-op default at `:88–92`.
- Orchestration: collect at `WebDAVProvider.swift:169`/`:176`; restore at `:376` (`("reading-history.json", "reading history", dataRestorer.restoreReadingHistory)` in `restoreFiles`).

**Library-manifest precedent (#46)** — `BackupLibraryManifestEnvelope` (`BackupSectionDTOs.swift:227–230`), `BackupDataCollector.swift:204–230`, `fetchAllBooksForBackup()` (`PersistenceActor+Backup.swift:51`). NOTE: pins `schemaVersion: 1` (own independent rev), NOT `kBackupCurrentSchemaVersion` — see Open Questions.

**#88 ChatSession persistence model (the data to back up):**
- `@Model final class ChatSession` — `vreader/Models/ChatSession.swift:24–82`. Fields: `@Attribute(.unique) var sessionId: UUID` (:26); `var bookFingerprintKey: String` (:29); `var title: String` (:32); `var messagesData: Data?` (:37); `var lastMessageSnippet: String` (:43); `var messageCount: Int` (:46); `var createdAt: Date` (:48); `var updatedAt: Date` (:49); `@Transient var messages: [ChatMessage]` (:55–57); `var book: Book?` (:62). Init `init(sessionId:bookFingerprintKey:title:messages:createdAt:)` (:66–81).
- `Book.chatSessions` — `@Relationship(deleteRule: .cascade) var chatSessions: [ChatSession]` at `vreader/Models/Book.swift:107`. Cascade on the parent (book-delete removes sessions).
- `ChatSessionPayload` envelope CONFIRMED — `vreader/Models/ChatSessionPayload.swift:24`: `struct ChatSessionPayload: Codable { var version: Int; var messages: [PersistedChatMessage] }`, with `PersistedChatMessage` (:30–36), `PersistedChatCitation` (:39–47), `ChatSessionPayloadMapper` (`encode([ChatMessage]) -> Data?` :65; `decode(Data?) -> [ChatMessage]` :86; `isReadable(Data?) -> Bool` :106; `static let payloadVersion = 1` :56). This is the blob stored in `ChatSession.messagesData`.
- `ChatMessage` (NON-Codable domain) — `vreader/Models/ChatMessage.swift:22`: `id, role: ChatRole, content, timestamp, citations: [ChatCitation]`. `ChatCitation` — `vreader/Services/AI/ChatCitation.swift:20`.
- `ChatSessionRecord` DTO — `vreader/Services/ChatSessionRecord.swift:12–21`.
- SchemaV9 registration — `vreader/Models/Migration/SchemaV9.swift:16–34`, `ChatSession.self` at :32. `versionIdentifier = Schema.Version(9, 0, 0)`. In the migration plan (`vreader/Models/Migration/SchemaV1.swift:80` — `VReaderMigrationPlan.schemas`). (Schema files live under `Models/Migration/`, not top-level `Models/`.)

**Existing PersistenceActor+ChatSessions methods** (`PersistenceActor+ChatSessions.swift`):
- `createChatSession(bookFingerprintKey:title:messages:) async throws -> ChatSessionRecord` (:32) — requires an existing `Book` (throws `ImportError.bookNotFound(key)` at :44 if absent).
- `fetchChatSessionSummaries(forBookWithKey:)` (:65), `fetchChatSession(sessionId:)` (:76), `updateChatSession`, `renameChatSession`, `deleteChatSession`.
- **No flat "fetch all sessions across all books", no backup-restore/insert method** — both must be added (grep `fetchAllChatSessions`/`allChatSessions` → no hits).
- `DocumentFingerprint(canonicalKey:) -> DocumentFingerprint?` — `DocumentFingerprint.swift:55` (failable).

**Tests the 2→3 bump WILL BREAK (edit in the same PR):**
- `BackupDataCollectorRestorerTests.swift:714` — `#expect(envelope.schemaVersion == 2)` (literal; :713 asserts `== kBackupCurrentSchemaVersion` and stays green).
- `BackupReadingHistoryTests.swift:105` — `#expect(envelope.schemaVersion == 2)` (literal; :106 asserts `== kBackupCurrentSchemaVersion`).

**Test-container schema gotcha:** existing backup tests build in-memory containers on `SchemaV4`/`V5`/`V6` (`BackupReadingHistoryTests.swift:16` uses V6). `ChatSession` only exists from `SchemaV9` — #89's conversation tests MUST use `Schema(SchemaV9.models)` (convention at `PersistenceActor+ChatSessionsTests.swift:18,348,393`).

---

## Problem

Feature #88 (DONE) persists AI conversations as `ChatSession` rows (SwiftData, SchemaV9), keyed to a book by `bookFingerprintKey`, with messages stored as a versioned `ChatSessionPayload` JSON blob in `ChatSession.messagesData`. The WebDAV backup ZIP currently carries annotations, positions, settings, collections, book-sources, per-book-settings, replacement-rules, library-manifest (#46), and reading-history (#58 WI-5) — but **no AI data** (confirmed: `BackupSectionDTOs.swift` has no chat envelope). So on device loss, a restore reproduces highlights and reading history but silently drops every AI conversation.

Feature #89 closes that gap with one **additive, version-tolerant** backup section — `ai-conversations.json` → `BackupAIConversationsEnvelope` — that round-trips `ChatSession` rows (including their message blob) through the existing collect→ZIP→restore flow, re-associating each session with its book on a fresh device. Purely additive backend work: no UI (Rule 51), no new `@Model` (reuse #88's `ChatSession`). Priority Low.

## Surface area (file-by-file, concrete signatures)

### NEW file: `vreader/Services/Backup/BackupAIConversations.swift` (<300 lines, sibling to `BackupReadingHistory.swift`) — FOUNDATIONAL

```swift
import Foundation

/// The `ai-conversations.json` section envelope — every persisted ChatSession
/// (with its message blob) so a restore reproduces AI history exactly.
/// New in backup schema v3 (feature #89).
struct BackupAIConversationsEnvelope: Codable, Sendable, Equatable, BackupVersionedEnvelope {
    let schemaVersion: Int
    let sessions: [BackupChatSession]
}

/// One persisted ChatSession row. Carries the messages as the SAME versioned
/// `ChatSessionPayload` blob stored in `ChatSession.messagesData` — we do NOT
/// re-derive a parallel Codable mirror of messages/citations (that already lives
/// in ChatSessionPayload.swift). `messagesPayloadData` carries the RAW bytes
/// (Codable serializes `Data` as base64 in JSON), nil when the stored
/// `messagesData` was nil. The denormalized snippet/count are carried so a
/// restore reproduces the Conversations-list projection without a re-decode.
struct BackupChatSession: Codable, Sendable, Equatable {
    let sessionId: UUID
    let bookFingerprintKey: String  // == DocumentFingerprint.canonicalKey of the owning book
    let title: String
    let messagesPayloadData: Data?
    let lastMessageSnippet: String
    let messageCount: Int
    let createdAt: Date
    let updatedAt: Date
}
```

Design choice (carry the raw blob BYTES, not a re-mirrored array, not a String):
`ChatSessionPayload` already is the stable, version-gated Codable representation of
messages+citations. Backing up the raw `Data?` blob means (a) zero risk of a
second Codable mirror drifting from the live one, (b) the `payloadVersion`
forward-compat gate in `ChatSessionPayloadMapper` keeps protecting a future-version
blob through backup→restore, and (c) the collector copies `messagesData` directly
with no domain decode and no lossy transform. **Gate-2 round-1 fix (Medium): the
field is `Data?`, NOT a `String?` UTF-8 transcode** — `messagesData`'s live
contract is raw bytes tolerant of corrupted/legacy/non-UTF8 content, and a UTF-8
string round-trip would collapse non-UTF8 bytes to nil, silently losing the blob.
`Codable` already encodes `Data` as base64 in JSON, so byte-exactness is free.

NOTE on the row's literal naming: features.md row #89 names "`BackupChatSession`/`BackupChatMessage` DTOs". This plan keeps `BackupChatSession` but **drops the separate `BackupChatMessage`** in favor of carrying the existing `ChatSessionPayload` blob as raw `Data?` bytes (`messagesPayloadData`), because re-mirroring `ChatMessage`/`ChatCitation` would duplicate the exact Codable layer #88 deliberately built. Flagged so the Gate-2 auditor sees the intentional divergence rather than a missing symbol.

### `vreader/Services/Backup/BackupSectionDTOs.swift` — FOUNDATIONAL
- Bump `kBackupCurrentSchemaVersion` from `2` to `3` (line 15).
- Add `3` to `kBackupAcceptedSchemaVersions` → `[1, 2, 3]` (line 21).
- Update the doc comments (lines 10–21) to mention the v3 `ai-conversations.json` section and that v1/v2 archives still restore (section simply absent).
- Add a one-line pointer comment after the reading-history pointer (~line 283) noting `BackupAIConversationsEnvelope`/`BackupChatSession` live in `BackupAIConversations.swift`.

### `vreader/Services/Backup/WebDAVProvider.swift` (protocol + orchestration) — FOUNDATIONAL + BEHAVIORAL
- `protocol BackupDataCollecting` (line 24): add `func collectAIConversations() async throws -> Data` with a default impl in `extension BackupDataCollecting` (lines 47–68) returning an empty `BackupAIConversationsEnvelope(schemaVersion: kBackupCurrentSchemaVersion, sessions: [])` (mirrors `collectReadingHistory` default :59–67) so existing mock collectors stay source-compatible.
- `protocol BackupDataRestoring` (line 74): add `func restoreAIConversations(from data: Data) async throws` with a default no-op (lines 88–92), mirroring `restoreReadingHistory`.
- `backup(progress:)` (line 153): `let ai = try await dataCollector.collectAIConversations()` in the collect block (~line 169, after `rh`), append `("ai-conversations.json", ai)` to `collected` (~line 176). Keep `progress(...)` fractions monotonic.
- `restore(backupId:progress:)` (line 288): append `("ai-conversations.json", "AI conversations", dataRestorer.restoreAIConversations)` to `restoreFiles` (~line 376). The loop (:383–392) already handles missing entries (forward compat) + per-section failure isolation — no structural change.

### `vreader/Services/Backup/BackupDataCollector.swift` — BEHAVIORAL
```swift
func collectAIConversations() async throws -> Data {
    let sessions = try await persistence.fetchAllChatSessionsForBackup()  // NEW actor method
    let envelope = BackupAIConversationsEnvelope(
        schemaVersion: kBackupCurrentSchemaVersion, sessions: sessions
    )
    return try encode(envelope)
}
```
Like `collectReadingHistory`, the persistence fetch is NOT `try?`-swallowed — a read failure must fail the backup loudly rather than silently emit an empty section. Reuses the private `encode<T: Encodable>` helper (:284).

### `vreader/Services/Backup/BackupDataRestorer.swift` — BEHAVIORAL
```swift
func restoreAIConversations(from data: Data) async throws {
    let envelope = try decodeAndValidate(
        BackupAIConversationsEnvelope.self, from: data, section: "ai-conversations"
    )
    try await persistence.restoreAIConversations(envelope)  // NEW actor method
}
```
`decodeAndValidate` (:112–132) already enforces `kBackupAcceptedSchemaVersions` and throws `unsupportedSchemaVersion` for v4+.

### NEW file: `vreader/Services/PersistenceActor+ChatSessionsBackup.swift` (mirror `PersistenceActor+ReadingHistory.swift`) — FOUNDATIONAL + BEHAVIORAL

Fetch (collect side) — returns Sendable value types, never `@Model` across the actor boundary:
```swift
func fetchAllChatSessionsForBackup() async throws -> [BackupChatSession] {
    let context = ModelContext(modelContainer)
    let sessions = try context.fetch(FetchDescriptor<ChatSession>(
        sortBy: [SortDescriptor(\.createdAt)]   // deterministic output
    ))
    return sessions.map { s in
        BackupChatSession(
            sessionId: s.sessionId, bookFingerprintKey: s.bookFingerprintKey,
            title: s.title,
            messagesPayloadData: s.messagesData,   // raw bytes, byte-exact (Gate-2 fix)
            lastMessageSnippet: s.lastMessageSnippet, messageCount: s.messageCount,
            createdAt: s.createdAt, updatedAt: s.updatedAt
        )
    }
}
```

Restore (upsert by `@Attribute(.unique) sessionId`, prefetch + update-in-place + insert-if-absent — the reading-history `restoreSessions` shape at `+ReadingHistory.swift:48–96`):
```swift
func restoreAIConversations(_ envelope: BackupAIConversationsEnvelope) async throws {
    let context = ModelContext(modelContainer)
    let existing = try context.fetch(FetchDescriptor<ChatSession>())
    var byId: [UUID: ChatSession] = [:]
    for s in existing { byId[s.sessionId] = s }
    var bookByKey: [String: Book] = [:]
    for b in try context.fetch(FetchDescriptor<Book>()) { bookByKey[b.fingerprintKey] = b }

    for backup in envelope.sessions {
        let blob = backup.messagesPayloadData   // raw bytes, byte-exact (Gate-2 fix)
        let row: ChatSession
        if let existingRow = byId[backup.sessionId] {
            row = existingRow
            if ChatSessionPayloadMapper.isReadable(row.messagesData) {  // never clobber a future-version blob
                row.messagesData = blob
                row.lastMessageSnippet = backup.lastMessageSnippet
                row.messageCount = backup.messageCount
            }
            // Gate-2 round-2 Medium: "backup value wins" — always re-key the row to
            // the backup's book, even on the existing-row path. Otherwise a restore
            // over a session whose local bookFingerprintKey drifted would keep the
            // STALE key, and summaries (fetched by bookFingerprintKey) would surface
            // under the wrong book. The book RELATION is reconciled in the
            // association block below (set if the book exists locally, cleared if not).
            row.bookFingerprintKey = backup.bookFingerprintKey
            row.title = backup.title
            row.createdAt = backup.createdAt
            row.updatedAt = backup.updatedAt
        } else {
            row = ChatSession(
                sessionId: backup.sessionId, bookFingerprintKey: backup.bookFingerprintKey,
                title: backup.title, createdAt: backup.createdAt
            )
            row.messagesData = blob
            row.lastMessageSnippet = backup.lastMessageSnippet
            row.messageCount = backup.messageCount
            row.updatedAt = backup.updatedAt
            context.insert(row)
            byId[backup.sessionId] = row
        }
        if let book = bookByKey[backup.bookFingerprintKey] {  // re-associate if book exists
            if row.book?.fingerprintKey != book.fingerprintKey { row.book = book }
            if !book.chatSessions.contains(where: { $0.sessionId == row.sessionId }) {
                book.chatSessions.append(row)
            }
        } else {
            // Gate-2 round-2 Medium: book-missing → clear any STALE relation so an
            // existing row that previously pointed at a now-wrong book is not left
            // mis-linked. The row stays queryable via its (re-keyed) bookFingerprintKey.
            row.book = nil
        }
    }
    try context.save()
}
```

Key restore decisions (for the auditor):
- **Book-missing edge:** unlike `createChatSession` (which THROWS `bookNotFound`), restore inserts the session even with no matching `Book` — reading-history does the same. The session keeps its `bookFingerprintKey` and renders in the Conversations list (the app queries sessions by `bookFingerprintKey`, not via the `book` relationship). **There is NO automatic reattachment hook today** (Gate-2 round-1 adjudication): if a book with that key is imported later, the existing import path does not re-link the orphan session's `book` back-reference. That is acceptable — the session is still queryable and functional; full re-linking would be a separate follow-up. The plan does NOT claim auto-healing.
- **Cascade safety:** appending to `book.chatSessions` keeps the #88 cascade correct; the append is guarded against double-insert (idempotent).
- **Carry-forward:** honors the #88 `isReadable` never-clobber contract on the existing-row branch.

### Files OUT of scope (explicitly NOT touched)
- **NO new UI** (Rule 51): no `WebDAVSettingsView` / `BackupViewModel` / `ConversationsSheet` / `ChatSessionBar`. The section rides the existing collect/restore flow. An opt-in "include AI history" toggle would be a designed surface — out of scope.
- **NO new `@Model`, NO SchemaV10** — SchemaV9 already contains `ChatSession`. (The backup *schema version* `kBackupCurrentSchemaVersion` is unrelated to the SwiftData `SchemaV*` migration version — do not conflate.)
- **NO `BackupChatMessage`/`BackupChatCitation` Codable mirror** — reuse `ChatSessionPayload`.
- **Selective-restore path (`extractMetadataSections`, `WebDAVProvider.swift:537–550`)** — NOT extended; that path already omits `reading-history.json`, and AI conversations follow the same precedent (full-restore only). See Open Questions.

## Prior art / precedent

- **#58 WI-5 reading-history** is the exact four-layer template (DTO sibling file → collector emit with non-swallowed fetch → restorer ingest via `decodeAndValidate` → PersistenceActor upsert keyed by unique id, in its own file). #89 copies it layer-for-layer.
- **#46 library-manifest** is the second additive-section precedent and where the "older archive lacks the section → restorer skips it" forward-compat behavior is proven (`WebDAVProvider.swift:383–392`).
- **Rejected — re-mirror messages as `BackupChatMessage`/`BackupChatCitation`:** duplicates `ChatSessionPayload.swift`'s Codable layer, creates a second source of truth that can drift, and bypasses the `payloadVersion` forward-compat gate. Rejected in favor of carrying the existing blob as raw `Data?` bytes (`messagesPayloadData`). (The one intentional deviation from the row's literal "`BackupChatMessage`" wording.)
- **Rejected — collector iterates books + `fetchChatSessionSummaries`:** summaries lack the message blob, and iterating books skips sessions whose book was deleted. A single flat `fetchAllChatSessionsForBackup()` (like `fetchAllReadingSessions`) captures every session regardless of book presence.

## Work-item sequencing

**ONE WI, one PR** (Gate-2 round-1 High fix). The original 2-WI split bumped the
global `kBackupCurrentSchemaVersion` 2→3 in WI-1 BEFORE WI-2 emitted/restored the
section. Because the global bump stamps `schemaVersion: 3` on EVERY section, a
backup produced after WI-1 but before WI-2 would (a) be rejected by older apps
(their `kBackupAcceptedSchemaVersions` is `[1,2]`) while (b) carrying no actual AI
data — a strictly-worse intermediate state. The schema bump is only safe to ship
in the SAME PR that actually writes + reads the `ai-conversations.json` section.
The feature is small and additive (one DTO file, one PersistenceActor sibling
file, edits to four existing files, one test file), so a single PR is the right
granularity — the #58 reading-history section was itself one WI.

**WI-1 (BEHAVIORAL — the whole feature):**
- Add `BackupAIConversations.swift` (envelope + `BackupChatSession` with
  `messagesPayloadData: Data?`).
- Add `PersistenceActor+ChatSessionsBackup.swift` (`fetchAllChatSessionsForBackup`
  + `restoreAIConversations(_:)`).
- Add `collectAIConversations` (collector) + `restoreAIConversations` (restorer).
- Add the two protocol methods + default impls in `WebDAVProvider.swift` AND wire
  both into the `backup`/`restore` orchestration arrays (the section is actually
  emitted + delegated).
- Bump `kBackupCurrentSchemaVersion` 2→3 + `kBackupAcceptedSchemaVersions` add 3,
  IN THIS SAME PR (never ahead of the section).
- Fix the two literal `== 2` assertions (`BackupDataCollectorRestorerTests.swift:714`,
  `BackupReadingHistoryTests.swift:105`) → `== kBackupCurrentSchemaVersion` (bump-proof).

**Acceptance (behavioral, full round-trip):** seed sessions on a SchemaV9 source →
`collectAIConversations` (or full `backup`) → restore into a FRESH SchemaV9
container (or full `restore`) → sessions + raw message blob + book re-association
reproduced exactly; provider-orchestration tests confirm `ai-conversations.json`
is in the backup set and delegated on restore (see Test catalogue).

## Test catalogue (mirror `BackupReadingHistoryTests.swift`)

New `vreaderTests/Services/Backup/BackupAIConversationsTests.swift`, containers on `Schema(SchemaV9.models)` (NOT V6 — `ChatSession` requires V9). Reuse `insertBook`/`createChatSession` seeding from `PersistenceActor+ChatSessionsTests.swift:32–52`.

- **DTO Codable round-trip:** encode/decode envelope (session with non-nil `messagesPayloadData`, snippet, count) → byte-stable, `Equatable`.
- **Collector emits the section + schema v3:** `collectAIConversations` → `envelope.schemaVersion == kBackupCurrentSchemaVersion` AND `== 3`; one `BackupChatSession` per seeded session; `ChatSessionPayloadMapper.decode(session.messagesPayloadData)` yields the seeded messages incl. a citation.
- **Empty-store edge:** empty container → `sessions.isEmpty`, valid envelope, v3.
- **Restore round-trip re-associates to book:** seed book+session, collect, restore into a fresh container with the matching book → restored session has correct `bookFingerprintKey`, decoded `messages`, snippet/count, `book?.fingerprintKey == key`, appears in `book.chatSessions`.
- **Messages survive exactly:** session with user+assistant messages where assistant carries `ChatCitation(sourceKind:.scope, sequence:1)` → after restore, `ChatSessionPayloadMapper.decode(restored.messagesData)` equals the original `[ChatMessage]`.
- **Book-missing-on-restore edge:** restore into a fresh container with NO Book rows → session lands with its `bookFingerprintKey`; `row.book == nil`; no throw (contrast `createChatSession`'s `bookNotFound`).
- **Version tolerance — v2 archive restores without the section:** the full-restore loop skips a ZIP with no `ai-conversations.json`; doesn't throw; leaves existing sessions untouched.
- **v3 accepted / v4+ rejected:** `schemaVersion: 3` restores; `schemaVersion: 4` throws `unsupportedSchemaVersion`.
- **Idempotency:** restore twice → no duplicate `ChatSession` rows (unique `sessionId` upsert), no duplicate `book.chatSessions` entries.
- **Restore-over-existing re-keys to the backup's book (Gate-2 round-2 Medium):** pre-seed a local row with `sessionId = S` keyed to book A (and `row.book == A`); restore a backup carrying `sessionId = S` keyed to book B. Assert (i) with book B present locally → `row.bookFingerprintKey == B` AND `row.book?.fingerprintKey == B` (re-keyed + re-linked, NOT left at A); (ii) with book B ABSENT locally → `row.bookFingerprintKey == B` AND `row.book == nil` (stale A relation cleared). Proves "backup value wins" on the existing-row path.
- **Carry-forward / never-clobber:** existing row with a synthetic future-version blob (`isReadable == false`) is NOT overwritten (title may still update).
- **Schema-version bump test:** `kBackupCurrentSchemaVersion == 3` and `kBackupAcceptedSchemaVersions == [1,2,3]`. Update the two existing literal assertions.
- **Protocol default-impl coverage:** a `MinimalCollector`/`MinimalRestorer` compiles + produces a valid empty `ai-conversations.json` / no-op restore (mirrors `BackupReadingHistoryTests.swift:369–407`).
- **Corrupt-JSON throws** (mirrors `corruptJSONThrows`).
- **Non-UTF8 blob byte-exactness (Gate-2 Medium fix):** seed a session whose `messagesData` is deliberately NON-UTF8 / corrupted bytes → collect → restore → the restored `messagesData` equals the original bytes EXACTLY (proves `Data?` transport, not a lossy String transcode that would nil it).
- **Provider-orchestration — backup INCLUDES the section (Gate-2 Medium fix):** drive the full `WebDAVProvider.backup(progress:)` against a capturing mock and assert the uploaded ZIP / `collected` set CONTAINS an `ai-conversations.json` entry with the seeded session — not just the collector in isolation. Add an explicit mock-capture hook for the AI section rather than relying on the current `restoreCallCount == 7` count (which would mask a missing wire). Extend `WebDAVProviderTests` (the existing `restoreCallCount`/section-count assertions at `WebDAVProviderTests.swift:410–423,750–757` must be updated to expect the new section).
- **Provider-orchestration — restore DELEGATES the section (Gate-2 Medium fix):** drive the full `WebDAVProvider.restore(backupId:progress:)` against a ZIP containing `ai-conversations.json` and assert `dataRestorer.restoreAIConversations` was invoked with the section bytes (explicit per-section mock capture), and that a ZIP WITHOUT the section does not throw (forward compat).

## Risks + mitigations

- **Large chat histories inflate the ZIP.** Blobs carried verbatim inside the deflate-compressed ZIP (no re-encode bloat); Low priority — a size guard is a possible later WI. Backup `totalSizeBytes` (`WebDAVProvider.swift:191`) correctly grows.
- **Session referencing a deleted/absent book.** Book-missing edge: session restores with its key + nil `book`, no throw, no cascade corruption.
- **Schema forward-compat (v4+).** Absent from `kBackupAcceptedSchemaVersions` → throws `unsupportedSchemaVersion` via `decodeAndValidate`. Tested.
- **Future-version blob clobber.** Restore honors `isReadable` before overwriting. Tested.
- **Concurrent restore.** Fresh `ModelContext` per method; upsert is prefetch→mutate→save in one context; sections restore sequentially. No new concurrency surface.

## Backward compat

- **v1/v2 archives still restore.** The section is additive/optional: the restore loop `try?`-extracts `ai-conversations.json` and skips it when absent, exactly as a v1 archive lacks `reading-history.json`. Pre-v3 section shapes are byte-identical across v1/v2/v3 (only the integer differs), so `[1,2,3]` keeps every older section restorable.
- **A v3 archive restored on an OLDER app.** The old build's `kBackupAcceptedSchemaVersions` is `[1,2]`, so its `decodeAndValidate` throws `unsupportedSchemaVersion` for any v3-tagged section — the intended forward-incompat guard (too-new archive rejected, not half-restored). The new `ai-conversations.json` entry is unknown to the old loop and skipped. Matches the documented contract at `BackupSectionDTOs.swift:17–21`. No regression.

## Open Questions / adjudicated (Gate-2 round 1)

1. **Global vs independent schema version — RESOLVED: follow the global counter, bump rides the single WI.** Library-manifest pins its own `schemaVersion: 1` (`BackupDataCollector.swift:228`); reading-history uses `kBackupCurrentSchemaVersion`. This plan follows reading-history (emit `kBackupCurrentSchemaVersion` = 3). The auditor confirmed: follow the current global-section contract; do NOT ship the bump ahead of the feature (→ collapsed to one WI). A global bump to 3 means a v3 backup stamps every section `schemaVersion: 3`, so an OLDER app (`[1,2]`) rejects it on the first section — the intended, existing forward-incompat guard, now safe because the bump only ships with the actual AI section.
2. **`BackupChatMessage` divergence — RESOLVED: acceptable, AND use raw `Data?` bytes.** The auditor confirmed reusing `ChatSessionPayload` over a re-mirrored DTO is correct; the only required change was `String?` → `Data?` (the Medium fix, applied).
3. **Selective-restore parity (#47 path) — RESOLVED: defer.** `extractMetadataSections` (`WebDAVProvider.swift:537–550`) omits reading-history today; AI conversations follow the same precedent (full-restore only). A follow-up (touching `SelectiveRestoreMetadataSections` + `SelectiveRestoreCoordinator`) — out of scope.

## Revision history / Audit fixes applied

- **Gate-2 round 1** (Codex `019e98aa`, NOT READY TO BUILD → fixes applied):
  - **High** — WI split shipped the global schema bump ahead of the section (v3 backups rejected by old apps while the feature did nothing). **Fixed**: collapsed to ONE WI; the 2→3 bump now lands in the same PR that emits + restores `ai-conversations.json`.
  - **Medium** — `messagesPayloadJSON: String?` was a lossy UTF-8 transcode of a raw-byte field. **Fixed**: DTO field is `messagesPayloadData: Data?`; collect copies `s.messagesData` directly; restore assigns it directly; added a non-UTF8 byte-exactness test.
  - **Medium** — test catalogue lacked provider-orchestration coverage. **Fixed**: added "backup includes `ai-conversations.json`" + "restore delegates the section" tests with explicit per-section mock capture (not the `restoreCallCount == 7` count), and noted the existing `WebDAVProviderTests` section-count assertions must be updated.
  - **Adjudication nits** — fixed the schema file path (`Models/Migration/`); removed the "book heals later automatically" overstatement (no reattachment hook exists today).
  - Model-assumption verification: **all symbols/fields confirmed to exist** (only the schema path was mis-cited).
- **Gate-2 round 2** (Codex `019e98b1`, NOT READY TO BUILD → fixes applied; the round-1 High + orchestration tests + nits confirmed resolved):
  - **Medium** — the existing-row restore branch never re-assigned `row.bookFingerprintKey` and left a stale `row.book` when the backup's book was absent, so a restore over a drifted local row could keep the wrong key (summaries fetch by `bookFingerprintKey`). **Fixed**: the existing-row branch now always sets `row.bookFingerprintKey = backup.bookFingerprintKey`, and the association block clears `row.book = nil` when no matching `Book` exists; added the "restore-over-existing re-keys to the backup's book" test (both book-present and book-absent).
  - **Medium** — the round-1 `Data?` fix wasn't fully propagated (residual `messagesPayloadJSON` / "blob string" mentions). **Fixed**: every reference now reads `messagesPayloadData` / raw bytes (DTO note, rejected-alternative bullet, DTO round-trip + collector test bullets).
