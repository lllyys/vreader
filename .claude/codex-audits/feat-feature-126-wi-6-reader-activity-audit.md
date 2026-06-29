---
branch: feat/feature-126-wi-6-reader-activity
threadId: 019f1194-a7de-7a92-b428-86591ba0982d
rounds: 2
final_verdict: ship-as-is
date: 2026-06-29
---

# Gate-4 audit — feature #126 WI-4+WI-6 (Azw3Document + Azw3ReaderActivity)

The user-facing AZW3/foliate reader. Codex (gpt-5.5/high), 2 rounds.

## Round 1 (threadId 019f118a-e058-7903-85bd-1ac89a05ad89) — **block-recommended** (2H/2M)
| # | sev | finding | fix |
|---|---|---|---|
| 1 | **High** | render-death recovery broken: `reloadKey++` made a new `Holder`/WebView but the `AndroidView` was unkeyed → Compose kept the dead WebView node. | `key(reloadKey) { AndroidView(factory = { holder.webView }) }` swaps the node. |
| 2 | Medium | the message collector launched into `rememberCoroutineScope()` (host lifetime) → a reload retained the old document/bridge/WebView. | `Azw3Document.start(scope)` → `suspend fun run()`; the host collects it in `LaunchedEffect(holder)` (holder-scoped, cancelled on reload/dispose). |
| 3 | **High** | rule-51: the visible reader chrome had no cited committed design. | Cites the committed `dev-docs/designs/vreader-fidelity-v1/project/vreader-reader.jsx` — the SAME shared reader-chrome subset TxtReaderActivity/PdfReaderActivity implement (per feature #106 the iOS fidelity bundle is a valid Android design source; the checklist defines "Design" as exactly that). Not new UI. |
| 4 | Medium | the test proved first-render + save only, not restore. | Added `reopen_restoresSavedPosition` — seeds 0.5, waits until the reader's OWN relocate save replaces the exact seed (a non-restoring reader would overwrite with ~0 → fail), asserts resume > 0.25. Forced render-process-death test deferred to WI-8 (reliably crashing the renderer in CI is flaky; the recreate mechanism = keyed `reloadKey`, and the restore test exercises the recreate→resume path). |

## Round 2 (threadId 019f1194-a7de-7a92-b428-86591ba0982d) — **ship-as-is**
**No findings.** All 4 closed; the auditor accepts deferring the forced render-death test to
WI-8 acceptance ("keep render-death survival in final WI-8 acceptance").

## Verification (on emulator API 35)
`Azw3ReaderActivityTest` **2/2**: a real 6 MB CJK AZW3 imports → renders through the real
FoliateBridge + production bundle (book-ready → init → `blob:` subframe render → relocate →
`azw3` position saved) [discharges the WI-3 deferred render smoke]; and `reopen_restoresSavedPosition`
proves resume. No JS console errors. JVM Foliate suites unaffected.

**Verdict: ship-as-is** (after the round-1 block was cleared).
