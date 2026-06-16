---
branch: feat/feature-104-wi1-contracts-spec
threadId: 019ed14d-1d4b-7853-8f93-36bc11011601
rounds: 3
final_verdict: ship-as-is
date: 2026-06-17
---

# Codex Gate-4 audit — feature #104 Spike A WI-1 (contracts/ identity spec)

Runner: `scripts/run-codex.sh -m gpt-5.4 -e high`. Sessions: R1
`019ed14d`, R2 `019ed151`, R3 `019ed155`. Audit focus: **fidelity to the
Swift reference** — a wrong spec misleads the future Android impl.

## Round 1 — 3 High + 2 Medium (all fidelity)

| Finding | Sev | Resolution |
|---|---|---|
| `positions` documented as storing a `VReaderLocator` per book; Swift stores `BackupPosition.locatorJSON: String` = plain `Locator` JSON, restore decodes `Locator.self` | High | Corrected the DTO shape. |
| schema v3 omitted `ai-conversations.json` (`BackupAIConversationsEnvelope`, feature #89); `reading-history` is the v2 addition (feature #58) | High | Added both; noted pre-v3 sections are byte-identical. |
| `engine` listed "readium/legacy/foliate"; `ReaderLocatorEngine` is only `epubWKWebView` + `readium` | High | Corrected to the two real cases. |
| over-strengthened validation (progression `0…1`; missing paired-range invariant) | Medium | Limited to exactly `Locator.validate()`: finite progression, paired `charRange` endpoints, non-negative offsets. |
| `page` table said platform-local but the resume rule treated it canonical | Medium | Reclassified `page` canonical (page N is page N on any renderer) — consistent. |

## Round 2 — 1 Medium

| Finding | Sev | Resolution |
|---|---|---|
| "Identity rules" prose still said annotations/positions use the `Locator`/`VReaderLocator` envelope; the backup wire is plain `Locator` JSON | Medium | Corrected — plain `Locator` JSON; `VReaderLocator` is the live persisted envelope, not the backup schema. |

## Round 3 — CLEAN

Verdict verbatim: "CLEAN. I found no Critical/High/Medium issues in the
four `contracts/identity/*.md` files against the Swift reference." All
four (fingerprint, locator, cache-key, backup-format) confirmed faithful
to `DocumentFingerprint.swift`, `Locator.swift`, `VReaderLocator.swift`,
`ChapterTranslationRecord.swift`, `BackupSectionDTOs.swift` + the
collector/restore paths.

## Verdict

ship-as-is. The audit caught real fidelity bugs in a load-bearing spec
before they could propagate to the Android implementation — the exact
value of routing `contracts/` through Gate 4 (Phase 0 WI-1).
