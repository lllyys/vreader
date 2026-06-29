---
branch: feat/feature-126-wi-3-secure-bridge
threadId: 019f1171-c36a-7f71-9429-f739dd3ef5be
rounds: 2
final_verdict: ship-as-is
date: 2026-06-29
---

# Gate-4 audit — feature #126 WI-3 (secure WebView bridge)

Security-critical WI. Codex (gpt-5.5/high), 2 rounds.

## Round 1 (threadId 019f1166-5d44-77e2-88b5-993414ffa279) — **block-recommended** (1H/3M/1L)
The auditor confirmed the policy has NO prefix-match bypass (sibling-host
`…androidplatform.net.evil.com` and userinfo `…net@evil.com` both rejected by the
exact-origin/`origin + "/"` guard). Findings, all fixed:

| # | sev | finding | fix |
|---|---|---|---|
| 1 | **High** | `shouldOverrideUrlLoading` blocked EVERY off-origin nav, including foliate's `blob:` SECTION SUBFRAMES → would break rendering. (WI-0's bare WebView had no WebViewClient, so it never hit this.) | Only gate `request.isForMainFrame`; allow subframe `blob:`/`about:blank` (their remote subresources are still blocked in `shouldInterceptRequest`). |
| 2 | Medium | Same-origin requests the asset loader didn't handle returned `null` → WebView falls through to network (not fail-closed). | Same-origin miss → bridge **404**; only non-same-origin internal schemes (`blob:`/`data:`) return `null`. |
| 3 | Medium | `BookFilePathHandler` served the full book for ANY `/book/...` path → a no-script section could force repeated large-book streams. | Serve ONLY `path == BOOK_NAME`; else `null` (→ 404); add `Cache-Control: no-store`. |
| 4 | Medium | `send(js: String)` raw JS exec → a future caller passing a book-derived CFI could inject shell JS. | Removed raw `send`; typed `openBook()/init()/initAtCfi()/initAtFraction()/next()/prev()`; CFI via `Json.encodeToString(String.serializer(), cfi)` (injection-safe literal); `initAtFraction` guards `isFinite()`. |
| 5 | Low | `androidx.webkit:webkit:1.12.1` stale. | → `1.16.0` (minSdk 24, compatible). |

(Also fixed a self-inflicted compile break: a KDoc containing `` `/book/*` `` opened a
nested block comment — Kotlin nests block comments — reworded.)

## Round 2 (threadId 019f1171-c36a-7f71-9429-f739dd3ef5be) — **ship-as-is**
**Findings: none.** All 5 round-1 fixes confirmed closed; no new issue.
`FoliateBridgePolicyTest` 10/10 (added sibling-host/userinfo bypass tests).

## Verification
- JVM: `FoliateBridgePolicyTest` 10/10, `FoliateMessageParserTest` 22/22 (`:app:testDebugUnitTest`).
- On-device: WI-0 already proved the same mechanism (patched bundle + `addWebMessageListener`
  + `isMainFrame`) blocks the hostile-section escape. **The real-bridge render smoke is deferred to
  WI-6's Activity test, which MUST verify: valid AZW3 render through real `blob:` subframes,
  off-origin top-level nav blocked, remote subresource loads blocked** (per the round-2 residual note).

**Verdict: ship-as-is** (after the round-1 block was cleared).
