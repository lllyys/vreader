---
branch: feat/165-wi-1-mapper
threadId: 019fd204-814b-7bf2-a003-d200ee4fc94e
rounds: 1
final_verdict: ship-as-is
---

# Gate 4 — implementation audit, feature #165 WI-1 (`AnnotationBackupMapper`)

- **Item**: `feat:#165/WI-1` — extract the `annotations.json` record→wire mapping out of
  `BackupCollector`'s privates so the #165 exporter (WI-2) and the backup collector share one copy.
- **Commit audited**: `269222af`
- **Auditor**: Codex `gpt-5.6-sol`, read-only sandbox, via `scripts/run-codex.sh` (rule 53).
  Raw transcript: `.reports/audit-r1.txt` (worktree-local, not committed).
- **Rounds**: 1. No code changed in response to the audit, so no re-test was required.

## Files audited

- `android/app/src/main/kotlin/com/vreader/app/backup/AnnotationBackupMapper.kt` (new, 89 lines)
- `android/app/src/main/kotlin/com/vreader/app/backup/BackupCollector.kt` (250 → 202 lines)
- `android/app/src/test/kotlin/com/vreader/app/backup/AnnotationBackupMapperTest.kt` (new, 291 lines)

## Prompt focus

The audit was asked to disprove the "pure extraction" claim specifically: any change to key
order, field set, null handling, number formatting, timestamp serialisation, the `locatorJSON`
form, or `schemaVersion`; to **name any line that is not a straight relocation**; to say whether
visibility widened; and to look for ways the byte-identity proof could be circular or vacuous.

## Findings

| # | Severity | Finding | Disposition |
|---|---|---|---|
| 1 | Low | Visibility of the **aggregate** surface widened: `envelope()` / `json()` were unreachable outside `BackupCollector`, and are now module-`internal`. The three per-record mappers remain `private`. | **Accepted — this is the deliverable.** WI-2's exporter must call the same mapping; module-`internal` is the narrowest visibility that permits it. Nothing became reachable outside the `:app` module, and no per-record mapper became callable, so a caller still cannot reassemble the wire shape with a different sort. |

**No Critical, High, or Medium findings.**

## Audit conclusions on the load-bearing questions

1. **Wire shape** — unchanged. Envelope key order (`schemaVersion`, `highlights`, `bookmarks`,
   `notes`) is fixed by the DTO declaration order and is untouched; field sets and per-record field
   order unchanged; `schemaVersion` still `BackupSchema.CURRENT_SCHEMA_VERSION`; null highlight
   `note` / bookmark `title` still omitted via `explicitNulls=false`; timestamps still
   `Instant.ofEpochMilli(...)` → ISO8601 UTC second-precision; `locatorJSON` still the PLAIN
   `BackupJson.encode(locator)` — **no** `Locator.canonicalJson()` anywhere.
2. **Non-relocation lines** — the new object + its two entry points; the rename
   `toBackupHighlight`/`toBackupNote`/`toBackupBookmark` → private overloaded `toWire`; and the
   split of `filter(P).sortedWith(C).map(M)` so the filter runs at the collector call site and the
   sort+map run in the mapper. The auditor proved this reordering observationally identical for
   every input — same predicate, comparator and mapping; argument evaluation preserves the
   highlights→notes→bookmarks read order; empty lists stay empty; out-of-scope rows are removed
   before the mapper; duplicate `(bookKey, id)` pairs compare equal and Kotlin's **stable** sort
   preserves their relative order in both forms; a locator whose `fingerprintKey` disagrees with
   `bookKey` behaves identically (filter/sort use `bookKey`, the locator serializes unchanged).
   Only noted difference: intermediate-list lifetime for very large inputs — peak memory
   composition, not output.
3. **Golden-test soundness** — sound. `GOLDEN_SECTION` is a compile-time literal, not regenerated
   by production code; the seeding path uses **independent** local wire builders (not the code
   under test), so the golden is not self-fulfilling; it covers all three kinds, every wire field,
   present and omitted optionals, CJK, ordering and timestamp strings.
   The auditor correctly noted that the literal's provenance cannot be established from the commit
   history alone (the test did not exist in the parent commit). It was established **empirically in
   the lane**, in two runs against unmodified production code: a first run with a placeholder
   golden failed and printed the collector's exact bytes, and a second run with the literal in
   place passed — both before `AnnotationBackupMapper` existed. The auditor additionally confirmed
   by reading the parent source that the literal is exactly what the parent's constructors and
   serializers produce.
4. **Edge cases** — no introduced defect for unsorted input, CJK/RTL, null optionals, sub-second
   timestamps, empty lists, duplicate sort keys, excluded book keys, or locator/book mismatch.
5. **Conventions** — all three files under the ~300-line guidance; `BackupCollector`'s header and
   method KDoc accurately describe the delegation (rule 22); no unused imports left behind; the
   `backup` → `annotations` direction of coupling is correct for a backup adapter and introduces
   no reverse dependency.

## Mutation evidence (lane-run, beyond the audit)

Four deliberate mutations were applied and reverted; **all four were killed**, none survived:

| Mutation | Killed by |
|---|---|
| Emit a reordered (alphabetically canonicalised) key set | `collector_annotationsSection_isByteIdenticalToGolden`, `envelope_emptyInput_isValidEmptyEnvelope` |
| Drop the highlight `note` field from the wire shape | `collector_annotationsSection_isByteIdenticalToGolden`, `envelope_highlight_mapsEveryWireField` |
| Change timestamp serialisation (`ofEpochMilli` → `ofEpochSecond`) | `json_timestamps_areIso8601SecondPrecision`, `envelope_note_mapsEveryWireField`, `collector_annotationsSection_isByteIdenticalToGolden` |
| Remove the deterministic `(bookKey, id)` sort | `envelope_sortsEveryKindBy_bookKeyThenId`, `mapperJson_isByteIdenticalToCollectorSection` |

Notably, the pre-existing `BackupAnnotationsCollectorTest` stayed **green through all four**
mutations — its byte-stability test compares two collects of the *same* build, so it pins
determinism but not the bytes. That is precisely the gap the new golden closes.

## Verdict

**ship-as-is** — behaviour-preserving extraction; the single Low finding is the intended,
module-confined API widening that the extraction exists to provide.
