---
branch: fix/issue-340-azw3-exth-metadata-extraction
threadId: 019dff32-f19d-7aa0-af7a-bfbd5a801606
rounds: 3
final_verdict: ship-as-is
date: 2026-05-07
---

# Codex audit log — bug #149 (GH #340)

## Round 1

**Findings:**

| File:line | Severity | Issue | Resolution |
|---|---|---|---|
| `MOBIMetadataParser.swift:66` | Medium | EXTH scan bounded by `record0.count`, not by the declared EXTH region. A corrupt header (`exthLength < 12`, oversized `exthRecordCount`, or recLength running past `exthStart + exthLength` but staying inside record 0) could read non-EXTH bytes and return garbage. | **Fixed** — added `guard exthLength >= 12, exthStart + exthLength <= record0.count`, computed `exthEnd = exthStart + exthLength`, and changed loop guards to `cursor + 8 <= exthEnd` / `cursor + recLength <= exthEnd`. |
| `MOBIMetadataParser.swift:133` | Medium | Decode hard-wired to UTF-8. Older MOBI files commonly store metadata in Windows-1252 / ISO-8859-1; non-UTF-8 author/title payloads silently disappeared. | **Fixed** — added `textEncoding = readUInt32BE(record0, offset: 44)` (MOBI text-encoding field). New `decodeText` selects encoding per codepage: try UTF-8 first; if it fails AND `textEncoding == 1252`, try CP1252. |
| `MOBIMetadataParserTests.swift:37` | Low | Missing coverage for malformed EXTH bounds, repeated EXTH 100 (multi-author), and non-UTF-8 payloads. | **Partially addressed** — added `returnsNil_whenExthLengthTooSmall` (real-fixture-derived corruption test). Multi-author + non-UTF-8 deferred (rare in Kindle exports; synthetic MOBI construction is ~80 lines and out of scope for this PR). |

## Round 2

**Findings:**

| File:line | Severity | Issue | Resolution |
|---|---|---|---|
| `MOBIMetadataParser.swift:167` | Medium (NEW — introduced by round-1 Medium #2 fix) | The CP1252 fallback was unconditional (decode UTF-8 OR CP1252), but CP1252 decodes any byte sequence. Files with codepage 932 / 950 / 1251 etc. would surface mojibake instead of falling back to filename. | **Fixed** — strategy now: (1) always try UTF-8 first; (2) only fall back to CP1252 if `textEncoding == 1252` (declared); (3) for any other unknown codepage with non-UTF-8 bytes, return nil so `AZW3MetadataExtractor` falls back to filename rather than display garbage. |

## Round 3

**Findings:** None.

Codex notes residual risk on multi-author EXTH 100 and non-UTF-8 legacy
codepages beyond CP1252 (Shift-JIS, Big5, etc.), but accepts current
behavior as fail-safe-to-filename. Documented as future work in
`decodeText`'s doc comment.

## Verdict

**ship-as-is** — Round 1 found two real Mediums + one Low. Round 2
caught a regression introduced by the round-1 fix and required a
stricter encoding selection. Round 3 confirms no remaining issues.
Three rounds of judgment-improving feedback before merge.
