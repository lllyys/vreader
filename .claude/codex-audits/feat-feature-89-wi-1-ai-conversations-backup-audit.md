---
branch: feat/feature-89-wi-1-ai-conversations-backup
threadId: 019e98c4-99da-74b3-8e67-c4b6d1978e44
rounds: 1
final_verdict: follow-up-recommended
date: 2026-06-06
---

# Gate-4 audit — Feature #89 WI-1 (ai-conversations.json WebDAV backup section)

The single WI of feature #89 — an additive `ai-conversations.json` backup section
that round-trips the #88 `ChatSession` rows (with their raw message blob) through
the existing collect→ZIP→restore flow, mirroring the #58 reading-history precedent.
Implemented per the 3-round Gate-2-audited plan
(`dev-docs/plans/20260606-feature-89-backup-ai-conversations.md`).

## Verdict

**No production correctness defects.** The audit confirmed the implementation
matches the approved plan on every main point: raw `Data?` blob round-trip
(byte-exact), existing-row `bookFingerprintKey` re-keying, `row.book = nil` on
missing book, `ChatSessionPayloadMapper.isReadable` never-clobber on the
existing-row path, fresh `ModelContext(modelContainer)` on both actor methods (no
`@Model` leak across the actor boundary), schema `3` stamping with accepted
`[1,2,3]`, and the provider collect/restore wiring. Three **Low** test-quality
findings, all fixed.

## Round 1 (`019e98c4`) — 3 Low, all fixed

| # | Finding | Fix |
|---|---|---|
| Low | `WebDAVProviderTests` `restoreCallCount` omitted `reading-history.json` (mock used the protocol-default no-op) and the "all restored" assertion expected `8` while the provider delegates `9` sections — a stale guard that could miss a dropped wire. | Added `restoredReadingHistory` capture + count + `restoreReadingHistory` override; assertion → `9`. Re-verified: `WebDAVProviderTests` 35 tests green (the count-9 passes, proving reading-history IS delegated). |
| Low | `v2ArchiveWithoutSectionRestoresViaProvider` did not test its named contract — it fed a PRESENT v2-tagged AI envelope, not a ZIP MISSING the section. | Renamed to `v2TaggedAIEnvelopeIsAccepted` with an honest doc comment; noted the real "absent section → loop skips it" forward-compat is a generic provider-loop concern exercised in `WebDAVProviderTests`, not at the restorer level (the restorer method is only invoked when the section is present). |
| Low | The re-key tests asserted the NEW `row.book` / target `book.chatSessions` but not that the OLD book released the moved session — relying on SwiftData inverse cleanup unverified. | Added, to both re-key tests, a post-restore assertion that book A's `chatSessions` no longer contains the session (book-present re-link AND book-absent `row.book = nil` cases). Re-verified GREEN → SwiftData's inverse cleanup auto-fires; the assumption holds, no production bug. |

## Tests

- `BackupAIConversationsTests` — **18 tests** green (DTO round-trip, collector emits + schema 3, empty store, restore round-trip re-associates, messages survive, non-UTF8 byte-exactness, book-missing edge, restore-over-existing re-keys [present + absent, incl. old-book release], v2-tagged accepted, v3 accepted / v4 rejected, idempotency, never-clobber, schema-bump, protocol defaults, corrupt-JSON throws).
- `WebDAVProviderTests` — **35 tests** green (incl. the new backup-includes / restore-delegates orchestration tests + the corrected 9-section count).
- `BackupReadingHistoryTests` (16) + `BackupDataCollectorRestorerTests` green with the 2→3 bump.
- `** BUILD SUCCEEDED **`.

`follow-up-recommended` — clean implementation, 1 round, 0 open Critical/High/Medium; the 3 Lows fixed + re-verified.
