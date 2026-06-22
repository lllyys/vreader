---
branch: feat/feature-117-wi-2-opds-client
threadId: 019eea7e-f117wi2
rounds: 2
final_verdict: ship-as-is
date: 2026-06-22
---

# Codex audit — feature #117 WI-2 (OpdsClient + OpdsAcquisitionService)

Scope: `android/app/.../opds/OpdsClient.kt` (HTTP feed-fetch + blob-download), `.../opds/
OpdsAcquisitionService.kt` (acquisition→import), the connected round-trip test + script, and the
JVM tests. The LIVE connected round-trip passed on the emulator before this audit.

## Round 1 — 2 findings (1 Medium / 1 Low)

| file:line | severity | issue | resolution |
|---|---|---|---|
| OpdsClient.kt (non-2xx) | Medium | A non-2xx response drained `conn.errorStream.readBytes()` unbounded — a hostile catalog could force a huge heap allocation despite the success-body caps. | FIXED — don't read the error body; throw `OpdsError.Http(status)` and let `disconnect()` (finally) tear the connection down (we never reuse it). |
| OpdsModels.kt (formatExtension) | Low | MIME matched case-sensitively, so `type="Application/EPUB+ZIP; charset=…"` was reported unsupported. | FIXED — `type.substringBefore(';').trim().lowercase()` before matching. Test added. |

Codex found NO defects in: relative redirect resolution, the final-redirected-URL propagation
(the recursion passes `next` as `url`, so the returned `finalUrl` IS the post-redirect URL),
303/307/308 GET semantics, redirect connection cleanup, the acquisition preference order, the
HTML/no-content-type rejection via magic bytes, title→storage path-traversal (BookImporter writes
a sanitized key-derived filename, not the displayName), `expectedKey` omission (correct for OPDS),
the gzip-decompressed bounded read, or coroutine/dispatcher use.

## Round 2 — verify pass

Both fixes confirmed; not draining the error stream is fine given the immediate `disconnect()`,
and the MIME normalization only broadens valid case variants. **No new defects.**

Verdict: **ship-as-is.** 24 OPDS JVM tests (parser 12 + client 6 + acquisition 6) + full `:app`
suite green; the LIVE OPDS round-trip (`scripts/run-opds-roundtrip.sh`) passed on emulator-5554.
