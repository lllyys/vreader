---
branch: docs/triage-bug-247-restore-loses-names
threadId: manual-fallback
rounds: 1
final_verdict: ship-as-is
date: 2026-05-20
---

## Scope

Docs-only triage filing. Adds one new row + one Open-Bug-Details
entry to `docs/bugs.md` for Bug #247 (WebDAV restore loses book
titles for TXT/MD/PDF). Touches `docs/bugs.md` only, plus
`project.yml` / `project.pbxproj` (version bump 3.38.17/592 →
3.38.18/593).

**No Swift source files changed.** The audit-gate hook fires on
`project.pbxproj` — false positive of the Swift-file heuristic.
Manual mini-audit.

## Manual audit evidence

### What changed and why

User reported via `/triage`: "the books from web-dav backups lost
there names". Symptom questionnaire clarified to "A SHA-like string
(e.g. restore_abc123…)" with TXT confirmed and other formats
suspected.

`docs/bugs.md` gains:

- One new summary row at the top of the data table — Bug #247 (TODO,
  High, Backup/Restore, GH #1074).
- One new Open Bug Details entry above Bug #246 (chronological-newest
  order). Sections: Reported / Symptom / Repro / Expected / Actual /
  Root cause / Manifest-carries-title-but-unused / Fix direction /
  Severity / Verification harness.

### Investigation done at triage time

- Confirmed the restore path: `WebDAVProvider.restore` →
  `BookFileMaterializer.materialize` →
  `materializeOneDownload` (`vreader/Services/Backup/BookFileMaterializer.swift:194-196`)
  writes a temp file named `restore_<sha256>.<originalExtension>`,
  then calls `importer.importFile(at: tempURL, source: .restore)`.
- `BookImporter.importFile` (`vreader/Services/BookImporter.swift:192-227`)
  derives the title via `MetadataExtractor.extractMetadata(from:
  fileURL)` and uses it at `title: metadata.title`. No
  titleOverride parameter exists.
- `TXTMetadataExtractor` and `MDMetadataExtractor` use the filename
  (without extension) as the title — confirmed by code-read.
- `BackupLibraryEntry.title: String?` exists in the manifest schema
  (`BackupSectionDTOs.swift:262`) with a doc-comment that explicitly
  defers title round-trip to the materializer's "re-extract from
  imported file" path — which is the broken assumption for
  filename-derived-title formats.

### Correctness checks

1. **Bug-vs-feature distinction** — restore IS implemented and was
   marked VERIFIED for feature #46 and feature #47. The title
   round-trip path is now confirmed broken for filename-derived-title
   formats. Implemented-but-broken = bug, not feature. Correct
   classification.
2. **No open duplicate** — code-checked the bug tracker for
   restore/backup/title patterns. No row covers "restored books show
   SHA-prefixed temp filename as title". This is a new finding.
3. **GH mirror** — issue #1074 created with `bug` + `severity:high`
   labels. `GH: #1074` stamped in Notes column per the
   mechanical-mirror rule.
4. **Bug ID** — max ID on `main` was 246; next free is 247. No
   collision.
5. **No fix attempted** — triage is classification only; the entry
   captures symptom, scope, repro, root cause, and three viable fix
   directions but does not implement any. The fix will go through
   `/fix-issue #1074` with a separate user invocation.
6. **Version bump** — 3.38.18 / build 593 (patch — docs / tracker
   triage). `xcodegen generate` confirmed; `xcodebuild build`
   SUCCEEDED on iPhone 17 Pro Simulator (Debug).
7. **Feature #46 / #47 acceptance gap** — both features carried
   `VERIFIED` status with `dev-docs/verification/feature-46-*.md`
   and `feature-47-*.md` evidence files. Neither's acceptance
   criteria explicitly asserted title round-trip for
   filename-derived-title formats — that's a gap in the original
   acceptance set, noted in the bug entry's "latent since" section.
   Not a verification-rule violation per se; just an acceptance
   pattern to tighten when the fix lands.

## Verdict

ship-as-is — documentation only, one bug filing, no code risk.
Manual fallback used because there is nothing to send to Codex.
