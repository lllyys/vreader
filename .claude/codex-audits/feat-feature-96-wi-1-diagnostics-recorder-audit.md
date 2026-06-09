---
branch: feat/feature-96-wi-1-diagnostics-recorder
threadId: 019eacbe-ef47-7fc2-9810-396a5abc2eef
rounds: 1
final_verdict: ship-as-is
date: 2026-06-09
---

# Codex Audit — Feature #96 WI-1 (diagnostics capture layer, foundational no-UI)

## Change

New `vreader/Services/Diagnostics/`: `DiagnosticsLogEntry` (+ `DiagnosticsLevel`
mirroring `OSLogEntryLog.Level`), `DiagnosticsLogSource` protocol, off-main
`OSLogDiagnosticsSource` (real `OSLogStore` reader), pure `DiagnosticsRedactor`,
`@MainActor @Observable DiagnosticsLogStore` (load / filter / redacted exportText).
Current-session scope. Rule 51 N/A (no UI).

## Round 1 findings — all FIXED

| file | severity | issue | resolution |
|---|---|---|---|
| DiagnosticsRedactor (Authorization) | High | The Authorization rule missed serialized/quoted shapes (`"Authorization": "Basic …"`) → creds survive export. | **Fixed** — pattern now accepts quoted key + `:`/`=` + optional quoted scheme/value, consuming to a quote/comma/brace/newline. Test: `redactsSerializedAuthorizationHeader`. |
| DiagnosticsRedactor (keyed secret) | High | Quoted values with whitespace only partially redacted (`"password": "correct horse battery staple"` leaked all but the first word). | **Fixed** — added a QUOTED-value variant that consumes to the closing quote (whitespace/newlines included). Test: `redactsQuotedMultiWordSecret`. (Also surfaced + fixed a raw-string interpolation bug: `\#(keys)` needs a `#"…"#` delimiter, not `##"…"##` — the keyed rules were silently no-op'ing before.) |
| DiagnosticsRedactor (paths) | Medium | Path rules stopped at the first space, leaking the tail of `…/Application Support/x.epub`. | **Fixed** — path rule consumes the whole path (incl. internal spaces) to a quote/comma/paren/newline (over-redacts a trailing word — the safe direction). Test: `redactsPathWithSpaces`. |
| DiagnosticsLogStore.load | Medium | A negative `limit` flowed to `Array.suffix(_:)` → trap. | **Fixed** — `load` clamps `max(0, …)`; the source guards `limit > 0 → []`. Test: `negativeLimitClampsNoCrash`. |
| OSLogDiagnosticsSource | Low | Dead `if out.count >= limit {}` no-op + the fetch materialized the full stream before `suffix`. | **Fixed** — replaced with a rolling window of the last `limit` entries during enumeration. |

## Verification (Gate 5a — foundational tier)

Unit + integration sufficient (no user-observable behavior; no device verify):
- `DiagnosticsRedactorTests` — every secret/cred/path shape redacted (incl. the audit-added
  quoted-multiword + serialized-auth + path-with-spaces cases), hashes/CJK/keychain-label preserved, idempotent.
- `DiagnosticsLogStoreTests` — load/bound/filter/export; `exportText` redacts every message;
  throwing/empty source → no crash; negative-limit clamp.
- `DiagnosticsLogEntryTests` — level mapping mirrors `OSLogEntryLog.Level` (no fabricated `warning`).

## Verdict

ship-as-is — 2 High + 2 Medium + 1 Low all fixed + covered by tests (the regex
fix was caught by the audit-requested tests). WI-2 (viewer) remains design-blocked (#1597).
