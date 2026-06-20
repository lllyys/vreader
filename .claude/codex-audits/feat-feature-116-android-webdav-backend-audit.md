---
branch: feat/feature-116-android-webdav-backend
threadId: 019ee543-3bed-7ba0-b4b8-e920380d72b4
rounds: 2
final_verdict: ship-as-is
date: 2026-06-20
---

# Codex audit — feature #116 WI-1 (Android WebDAV client)

Scope: `android/app/src/main/kotlin/com/vreader/app/backup/net/WebDavClient.kt`,
its JVM unit test, INTERNET permission, DEBUG-only network-security-config
(cleartext to `10.0.2.2`), and the test-JVM `--add-opens` for the reflective
WebDAV-verb fallback.

## Round 1 — 3 findings (0 Critical / 0 High / 2 Medium / 1 Low)

| file:line | severity | issue | resolution |
|---|---|---|---|
| WebDavClient.kt (verb fallback) | Medium | HTTPS reflective fallback could "succeed" setting only the `HttpsURLConnectionImpl` wrapper's `method`, leaving the real delegate on the old verb. | FIXED — `setRequestMethod` now treats the `delegate` as the REQUIRED target when present (`if (!setMethodField(realTarget, method)) throw e`), sets the wrapper best-effort, and `setMethodField` fails closed on any inaccessible/security exception. |
| WebDavClient.kt (parseMultistatus) | Medium | XXE hardening fail-open — `setFeature(disallow-doctype-decl…)` wrapped in `runCatching`, so a parser ignoring it could still process external entities. | FIXED — `disallow-doctype-decl` + `FEATURE_SECURE_PROCESSING` are now required (let the exception propagate = fail closed); external-entity features remain belt-and-suspenders. ACCESS_EXTERNAL_* dropped (not on all Android API levels and moot once DOCTYPE is rejected outright). |
| WebDavClientTest.kt (propfind test) | Low | Test included a 404 per-resource entry but never asserted it was skipped — masking that the parser did NOT skip non-2xx entries. | FIXED — parser now tracks `<status>` per response and skips a response whose status was reported and never 2xx (servers omitting `<status>` are kept; multi-propstat 200+404 kept). Test asserts `entries.none { it.href.endsWith("/missing") }` and `entries.size == 1`. |

## Round 2 — verify pass

All three round-1 findings confirmed resolved. Codex specifically checked the
new `MultistatusHandler` status-skip logic for false drops (no `<status>` →
kept; pure non-2xx → skipped; mixed 200+404 propstat → kept) and the
fail-closed `setMethodField`. **No findings.**

Verdict: **ship-as-is.**
