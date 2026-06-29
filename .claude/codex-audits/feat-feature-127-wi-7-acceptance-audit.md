---
branch: feat/feature-127-wi-7-acceptance
threadId: bxvj41tse
rounds: 1
final_verdict: ship-as-is
date: 2026-06-29
---

# Gate-4 audit — feature #127 WI-7 (acceptance)

WI-7 is the acceptance gate, a **test-only** change (no production code). It extends the live-WebDAV
connected round-trip `WebDavRoundTripConnectedTest.backup_then_restore_overLiveWebDav` to also exercise
collections: wires the `CollectionDao` into `BackupCollector` + `WebDavBackupService`, creates a
UUID-named collection containing the imported book + assigns it, backs up, wipes the book AND the
collection, performs a SELECTIVE restore (the one book), and asserts exactly one restored collection
(same name) with the book's membership.

## Round 1 (Codex `bxvj41tse`, gpt-5.5/high) — No findings

The auditor confirmed:
- The diff correctly proves collection round-trip behavior (create → assign → backup → wipe both →
  selective restore → assert exactly one collection with the same name + the book's membership).
- **False-positive risk is low**: if collections are not backed up, not restored, or membership is not
  restored, the final assertions fail. The wipe is adequate (deleting the book cascades the membership;
  deleting the collection removes the parent; the test asserts NO collections remain before restore).
- Resource cleanup is unchanged from the existing live-WebDAV test (local DB/cache/preferences cleaned
  up; no extra remote resources beyond the existing backup zip).

## Verdict

**ship-as-is.** Test-only acceptance change, one round, zero findings. The connected test passed 1/1
(0 skipped, 1.537s) on the vreader-test AVD against a live rclone WebDAV server — the feature's final
end-to-end acceptance. Evidence: `dev-docs/verification/feature-127-20260629.md`.
