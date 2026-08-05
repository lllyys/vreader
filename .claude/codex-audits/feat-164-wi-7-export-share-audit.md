---
branch: feat/164-wi-7-export-share
threadId: 019fd076-0824-78c0-b9ee-34790d91c5df
rounds: 3
final_verdict: follow-up-recommended
date: 2026-08-05
---

# Codex Audit Log — Feature #164 WI-7 (GH #2023)

Diagnostics export + share: `DiagnosticsExportWriter`, a SECOND `FileProvider`
scoped to `filesDir/diagnostics`, the share intent + its own path guard, and
falsifiable container wiring (`VLog.install` in `VReaderApp.onCreate`).

## Scope of audit

Nine files: the three new `diagnostics/` sources, the new
`res/xml/diagnostics_paths.xml`, the single new `<provider>` element in
`AndroidManifest.xml`, `VReaderApp.kt`'s diagnostics graph, and the three test
files (JVM writer test, JVM Robolectric container-wiring test, connected share
test). Each round was asked specifically: can any path grant a URI outside
`filesDir/diagnostics`; does the new provider widen anything the book provider
restricted; can an unredacted byte reach disk or a receiver; does the manifest
change alter any existing component's exposure; are the tests falsifiable.

Thread ids: round 1 `019fd05d-4c22-7c02-bd42-15659a26a34e`, round 2
`019fd069-82ef-76e1-bb49-95b3390d9f16`, round 3
`019fd076-0824-78c0-b9ee-34790d91c5df`. Reports:
`.reports/audit-r1.txt`, `-r2.txt`, `-r3.txt` (not committed — long).

## Round 1 — 2 High, 2 Medium, 1 Low

| Finding | Disposition |
| --- | --- |
| **High** — redaction is only a caller convention: `write(text: String)` accepts arbitrary bytes | FIXED — the public API takes `List<DiagnosticsLogEntry>` and renders through an injected `renderPayload`, wired by `AppContainer` to `DiagnosticsLogStore::exportText` |
| **High** — hard links defeat the directory boundary (canonicalisation cannot see a second name for an inode) | FIXED — `Os.lstat` guard rejects non-regular files and any regular file with `st_nlink > 1` |
| **Medium** — prune used `deleteRecursively`, retained a canonical alias, ignored failures | FIXED — entry-NAME matching, non-recursive, `NOFOLLOW_LINKS`, residual reported via `VLog` |
| **Medium** — concurrent writes can invalidate a returned file | FIXED — a `Mutex` spans create → write → promote → prune |
| **Low** — KDoc promised `IOException`, `check` throws `IllegalStateException` | FIXED — both documented |
| **Low** — `VReaderApp.kt` size vs the ~300-line guideline | ACCEPTED — see residuals |

## Round 2 — 2 High, 3 Medium, 2 Low

| Finding | Disposition |
| --- | --- |
| **High** — redaction still *injectable*: a caller can pass a non-redacting `renderPayload` | FIXED — `write` now applies `DiagnosticsRedactor.redact()` to whatever the renderer returns, unconditionally. New test writes through a deliberately naive renderer and asserts the secret is absent from disk; a second test pins `exportText` as a fixed point of the redactor so the extra pass does not rewrite the shipped payload |
| **High** — the share boundary grants any raw file in the directory | NARROWED + residual documented — `shareDiagnosticsIntent` now also requires the export NAME shape (`isExportFileName`, single-sourced with the writer). Round 3 re-rated this as no longer High: the remaining case (same-module code deliberately writing raw bytes under an export's exact name) crosses an already-trusted boundary, and eliminating it needs the facade the WI spec forbids |
| **Medium** — the mutex does not keep a returned file valid across a LATER export | ACCEPTED with explicit semantics — last-write-wins is now documented on `write`; a per-share file contradicts the "at most one export" acceptance criterion. This was one of the auditor's own two offered fixes |
| **Medium** — the concurrency test is not falsifiable | **CONFIRMED BY MUTATION AND FIXED** — deleting the mutex left the original test GREEN. Replaced by `write_concurrentExports_areSerialised`, which measures peak occupancy of the guarded section through the injected renderer; the same mutation now fails it |
| **Medium** — prune does not enforce its stated cardinality; dangling-link report missed | FIXED — `deleteIfExists` for every entry (removes empty dirs, refuses non-empty), residual checked with `NOFOLLOW_LINKS`, KDoc no longer over-claims |
| **Low** — hard-link branch uncovered on API 35 | ACCEPTED — `Os.link` returns EACCES from the app domain on this AVD, so the vector is not constructible; the test `Assume`-skips visibly (skipped=1) rather than asserting it away. The rejection branch itself IS exercised by the symlink-alias test |
| **Low** — file size | ACCEPTED — see residuals |

## Round 3 — 0 High, 0 Medium, 1 Low → **follow-up-recommended**

Auditor verified every round-2 fix as real ("the injectable-renderer leak is
closed", "the replacement concurrency test is falsifiable and directly measures
occupancy", "pruning correctly attempts non-recursive deletion for every entry
and detects dangling links"), and downgraded the share-boundary finding.

The one remaining Low — the byte-neutrality claim was slightly too broad,
because a logcat-sourced entry's CATEGORY is a third-party tag the store inserts
raw — was closed in-lane: the KDoc now states the bound precisely, and
`writerPass_alsoRedactsACredentialShapedThirdPartyCategory` asserts the shipped
behaviour (the writer's pass catches it; the difference runs in the safe
direction).

## Mutation pass (each mutation applied, run, reverted)

| Mutation | Result |
| --- | --- |
| Export written into `books/` (i.e. riding the BOOK provider's grant scope) | **RED ×7** connected, incl. `bookProvider_refusesTheDiagnosticsExport` — the section-6.4 invariant |
| Prune skipped | **RED ×2** (`write_prunesPriorExportsAndStaleTempFiles`, `write_acrossDays_stillLeavesExactlyOneExport`) |
| Write straight into the live name (no temp + rename) | **RED** (`write_replacesAPreviousExportWhoseFileModeIsNotWritable`) |
| `FLAG_GRANT_READ_URI_PERMISSION` dropped | **RED** (`shareDiagnosticsIntent_isAChooserWrappedSendWithGrantAndClipData`) |
| `VLog.install()` removed from `VReaderApp.onCreate()` | **RED** (`vlogEmission_landsInTheContainersRing_withoutTheTestInstallingASink`) — re-verified against the final code |
| Writer accepts + honours a caller-supplied filename | **RED** (`write_takesEntriesOnly_noCallerSuppliedTextOrFileName`) |
| `Mutex` removed | **SURVIVED** the first concurrency test → the test was replaced, not the mutation; **RED** against the replacement |

## Accepted residuals

1. **Share provenance** — `shareDiagnosticsIntent(context, file)` is the WI's
   specified surface, so it validates *properties* of the file (name shape,
   canonical directory, single-link regular file) rather than proving the writer
   produced it. Every byte the writer produces is redacted unconditionally, so
   the residual is same-module code deliberately writing raw bytes under an
   export's exact name.
2. **Last-write-wins** — a later export overwrites or prunes an earlier returned
   file, by design of the one-export policy.
3. **Hard-link branch uncovered on API 35** — the platform refuses the vector.
4. **`VReaderApp.kt` ~430 lines** — a `DiagnosticsServices` holder (the
   `BilingualServices` precedent) would fix it but needs a new file outside this
   lane's write-set. Named as a follow-up.
