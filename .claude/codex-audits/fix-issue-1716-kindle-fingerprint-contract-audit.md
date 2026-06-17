---
branch: fix/issue-1716-kindle-fingerprint-contract
threadId: 019ed4xx-354
rounds: 3
final_verdict: ship-as-is
date: 2026-06-17
---

# Codex Gate-4 audit — bug #354 (converted-Kindle fingerprint contract reconciliation)

Runner: `scripts/run-codex.sh -m gpt-5.4 -e high`. Three rounds. The fix reconciled
the self-contradictory converted-Kindle identity contract to **SOURCE-bytes** (user
decision) across `DECISION.md` + `fingerprint.md` + `backup-format.md` + `README.md`
+ the ADR + trackers, and tracked the migration-sensitive iOS implementation as a
follow-up feature.

## Round 1 — 1 High + 2 Medium + 1 Low (residual contradictions)
README still said Kindle fingerprint = converted EPUB (High); fingerprint.md format
rule could yield `mobi:`/`prc:` keys when only `azw3` is valid (Medium); fingerprint.md
vectors still required libmobi/converter version (Medium); backup-format.md still gated
on libmobi determinism (Low). All fixed.

## Round 2 — contracts/ CLEAN; contradiction propagates OUTSIDE contracts/
BookImporter.swift still fingerprints the converted EPUB (High — the implementation);
ADR / features #102 / feature-42 plan stale (Medium/Low); BookImporterTests asserts the
old model (Medium). Resolution: purged the stale doc cross-refs (ADR/features/plan);
added a DECISION.md "Implementation status" section; filed **feature #108** to own the
migration-sensitive BookImporter+blob-identity+migration change. The auditor confirmed
treating the importer change as tracked follow-up #108 is a LEGITIMATE resolution for a
contract-reconciliation bug.

## Round 3 — identity model CONSISTENT; 2 README staleness items
Verbatim: "I did not find any remaining active contract text that still asserts
converted-EPUB is the canonical cross-platform identity"; "treating the BookImporter
change as tracked follow-up feature #108 is a legitimate resolution for bug #354."
Two README staleness items (the "spec is wrong not the app" line vs the decided-target
model — Medium; a stale dated status block — Low) — both fixed.

## Verdict
ship-as-is. The converted-Kindle identity contract is now self-consistent on
source-bytes across README + 3 identity docs + ADR + trackers; the converted-EPUB
fingerprint is explicitly iOS-platform-local; the iOS source-bytes implementation +
migration is tracked as feature #108. Conformance lane unaffected (Kotlin BUILD
SUCCESSFUL).
