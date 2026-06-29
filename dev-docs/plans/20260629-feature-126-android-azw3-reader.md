# Feature #126 — Android AZW3 / MOBI / KF8 (Kindle) reader

> Plan author: claude (orchestrator). Gate-1 deliverable per rule 47.
> Platform: **Android** (Kotlin/Compose, `android/`). Test lane:
> `scripts/run-android-tests.sh` / `scripts/run-android-verify.sh`. Version lane:
> `android/version.properties` (+ `android/vX.Y.Z` tags) per rule 40.
> Tracker row: `docs/features.md` #126 (TODO → PLANNED after Gate 2).
> Parity row: `docs/parity/android-checklist.md` "Deferred → AZW3/MOBI/KF8".
> **Status: v4 — Gate-2 round-1 (2C/5H/4M/2L) + round-2 (1C/1H security) + round-3 (1C/1M security) audits applied. Final confirmation pass pending; security completeness empirically gated by the WI-0 blocking spike.**

---

## Problem

The Android app recognizes and **imports** `.azw3 / .azw / .mobi / .prc` files
(they canonicalize to `BookFormat.azw3` and get a source-bytes fingerprint), but
there is **no reader** — tapping such a book shows a toast
`"<format> reading isn't available yet"` (`MainActivity.kt`, the `BookFormat.azw3`
dispatch). iOS reads these; Android does not. Last unstarted parity reader (was
"Deferred"); user flipped go/no-go to **GO** ("the azw3 is needed", 2026-06-29).

## Goal & non-goals

**Goal**: open an imported AZW3/MOBI/KF8 book on Android, paginate/scroll, turn
pages, and **resume position across launches** — rendered by the same **foliate-js**
engine iOS uses, in an Android `WebView`.

**Non-goals (MVP, mirror iOS later):** highlights/annotations/selection; TTS;
bilingual; in-book search; a display-settings panel beyond a minimal default; **any
libmobi/NDK** (reading is pure-JS; identity is source-bytes). **Book-embedded
JavaScript is explicitly NOT supported** (see Security) — an e-reader does not need
to run scripts shipped inside a Kindle file, and disallowing them is the primary
security boundary.

---

## Approach (decided) & rejected alternatives

**Decided — Approach A: an Android `WebView` hosting the foliate-js bundle**,
mirroring iOS `FoliateSpikeView`. foliate-js `mobi.js` decodes MOBI/KF8/AZW3 in
pure JS; the WebView renders it. Readium stays the EPUB engine.

**Rejected:** (1) AZW3→EPUB convert→Readium (converter-fidelity + identity
problems Spike A avoided); (2) NDK libmobi reader (large C port for pure-JS-solved
work — the checklist's original mis-framing); (3) 3rd-party lib (none render
AZW3/KF8 faithfully without WebView+JS).

**Prior art / precedent:**
- **iOS `FoliateSpikeView`** + `vreader/Services/Foliate/` — the pattern. Its
  message contract is the Kotlin host spec. **(audit C1)** the bundle's
  `foliate-host.js:11` hard-codes JS→native to
  `window.webkit.messageHandlers[name].postMessage(...)`; the Android shell installs
  a `window.webkit.messageHandlers` **shim** forwarding to the web-message channel.
- **Anx-Reader** (Flutter foliate-js-in-WebView, MOBI/AZW3) — proves the model.
  Copy the event taxonomy; not the transport (we use `WebViewAssetLoader` +
  `addWebMessageListener`).
- **Readest** (Tauri foliate-js) — lesson: don't marshal the book through the
  bridge; hand foliate a `fetch()`-able URL.
- **Project precedent**: `PdfReaderActivity` (#115) — the Android reader skeleton.

---

## Foliate rendering model (verified from the bundle — drives the security design)

- Foliate renders each book **section inside an iframe/sub-frame** (`paginator.js:241`
  creates the iframe; `:277` sets `sandbox="allow-same-origin allow-scripts"`;
  `:323` assigns `iframe.src`).
- For MOBI/KF8, section documents are **`blob:` URLs created by SHELL-SIDE JS**
  (`mobi.js:866`, `mobi.js:1185`). **A blob inherits the creating document's origin →
  the section iframe is SAME-ORIGIN to the shell** (the bridge host). (audit round-2)
- **Consequence (audit round-2 Critical):** `isMainFrame` blocks *direct* bridge
  calls from a sub-frame, but a same-origin section **script** can reach
  `parent.vreaderHost` / `parent.webkit.messageHandlers` and post as if from the main
  frame. **`isMainFrame` + two distinct asset origins is NOT a complete boundary**
  while section content is same-origin and `allow-scripts` is set.
- **Restore API (audit round-2 B.1):** `readerAPI.init` accepts `{ cfi: string }`
  (→ `view.init({ lastLocation: cfi })`) and `{ fraction: number }`
  (→ `view.goToFraction(fraction)`). WI-7 restore uses `{cfi}` when present, else
  `{fraction}`.

---

## Security design (the #1 release risk — reworked in round 2)

The book is **untrusted attacker-controlled content**. The boundary is **"book
content cannot run script that reaches native."**

**Primary mitigation — disallow book scripts (leading candidate, WI-0-proven):**
strip **`allow-scripts`** from **EVERY** foliate section-iframe sandbox — both
`paginator.js:277` (reflowable) **and `fixed-layout.js:84`** (`foliate-fxl`, taken
when EXTH `fixedLayout == "true"`: `mobi.js:1047` → `view.js:251`) — plus any other
bundled `sandbox="allow-same-origin allow-scripts"` occurrence (audit round-3
Critical: patching only the paginator left a hostile **fixed-layout KF8** escape).
With no section script, the `parent.vreaderHost` / inline-handler / `javascript:` /
SVG-script escape paths all collapse. Book-embedded JS is a non-goal, so this loses
nothing functional. **Fallback** if a fixed-layout book can't be secured/rendered
without scripts: the reader **rejects fixed-layout Kindle books** (→ a
`Corrupt`/Unsupported state) rather than render them unsafely. Spike #1 proves
foliate still **renders + paginates** the real CJK book with `allow-scripts` removed,
and covers a fixed-layout KF8/AZW3 hostile variant.

This makes the bundle **NOT byte-identical** to iOS (it's a one-attribute security
patch). C1 therefore becomes: ship a **pinned, Android-security-patched bundle**;
the provenance test asserts the **patched** SHA-256 and a checked-in
`assets/foliate/bundle-patch.diff` documents the exact delta vs the iOS bundle
(`vreader/Services/Foliate/JS/foliate-bundle.js`, SHA-256
`3463a2ee41168f1549f5ed49fdcfe9eb521dbb5adab3702c63c429838480503d`).

**Defense in depth (all also applied):**
- `addWebMessageListener("vreaderHost", setOf(SHELL_ORIGIN))` — allow-listed to the
  shell origin only; the listener **also** rejects `!isMainFrame` and
  `sourceOrigin != SHELL_ORIGIN`.
- A strict **CSP** on the shell (`script-src` limited to the shell bundle;
  `object-src 'none'`, `base-uri 'none'`) AND on section documents — to also block
  **passive remote loads** (audit round-3 Medium: remote `img`/CSS `url()`/font/media/
  `meta refresh`/child-frame exfil need no script). Section CSP target:
  `default-src 'none'; script-src 'none'; connect-src 'none'; form-action 'none';
  frame-src 'none'; object-src 'none'; base-uri 'none'; img-src blob: data:;
  media-src blob: data:; font-src blob: data:; style-src 'unsafe-inline' blob:`
  (loosen only as WI-0 proves rendering needs).
- **`WebViewClient.shouldInterceptRequest`** blocks any non-book/off-origin resource
  request (belt-and-suspenders to the CSP, for WebViews that under-enforce it).
- `WebViewAssetLoader` virtual-https origins (never `file://`/`data:`); file +
  universal access OFF; navigation blocking (`shouldOverrideUrlLoading` denies any
  off-origin/`javascript:` navigation, `target=_blank`, form submission, top-nav).
- Book bytes served from a **separate** asset origin (keeps belt-and-suspenders SOP
  separation for the book *file* fetch, even though section blobs are shell-origin).

**WI-0 must return a blocking verdict** proving the chosen mitigation holds (book
section script cannot reach native) AND rendering still works. If `allow-scripts`
removal breaks foliate rendering, the spike falls back to CSP `script-src 'none'` on
section blobs (also a bundle patch) or section-HTML sanitization, and re-tests.

---

## Surface area (file-by-file)

App paths under `android/app/src/main/kotlin/com/vreader/app/reader/`.

### Verified against the codebase (Gate-2)
- Dispatch passes **`book.id`** (= the fingerprint key, `LibraryViewModel.kt:33`);
  `PdfReaderActivity.intent(ctx, fingerprintKey)` extra `"fingerprintKey"`. → new:
  `Azw3ReaderActivity.intent(this, book.id)`.
- **No new contract engine** — `ReaderLocatorEngine` (`:identity`, 2 cases, pinned by
  `contracts/identity/locator.md:74`). → `VReaderLocator.wrapLegacy(locator)`; foliate
  `cfi`+`progression` in `legacyLocator`. No contract change.
- **Resume** — `ResumeResolver.resolve()` returns `Precise` only for `readium`
  (`ResumeResolver.kt:42`); else `Canonical(locator)`. → restore:
  `loadPosition(key) → resolve → Canonical(locator) →` `readerAPI.init({cfi})` if
  `locator.cfi` else `readerAPI.init({fraction = locator.progression})`.
- **Backup** — plain `Locator` JSON, not the envelope
  (`contracts/identity/backup-format.md:42`). → plain-`Locator` round-trip test.
- **`androidx.webkit` NOT on the classpath** → add pinned dep (WI-3).
- **`assets/` doesn't exist** → WI-1 creates it.

### New files

| File | Purpose | Key surface |
|---|---|---|
| `assets/foliate/foliate-bundle.js` | **pinned Android security-patched** copy of the iOS bundle (section sandbox `allow-scripts` removed, or the spike-selected equivalent) | static asset (patched-SHA-pinned) |
| `assets/foliate/bundle-patch.diff` | the exact documented delta vs the iOS bundle | provenance artifact |
| `assets/foliate/reader.html` | Android shell: `window.webkit.messageHandlers` **shim** → web-message port; strict CSP; loads the bundle; `<foliate-view>`; `bridge-ready` | static asset |
| `reader/foliate/FoliateMessageParser.kt` | pure JSON→`FoliateMessage` parser | `object FoliateMessageParser { fun parse(name,json): FoliateMessage? }`; `sealed interface FoliateMessage { BridgeReady; BookReady; Relocate; Error }` |
| `reader/foliate/FoliateAssetServer.kt` | shell-origin loader (bundle/shell) + separate book-origin loader (book bytes via `PathHandler`, file IO off-main) | `fun shellLoader(ctx)`; `fun bookLoader(ctx,bookFile)`; `SHELL_ORIGIN`, `BOOK_ORIGIN` |
| `reader/foliate/FoliateBridge.kt` | **@MainThread** secure transport: `addWebMessageListener` (shell origin only) + `isMainFrame`/`sourceOrigin` reject; CSP + nav-block; `WebViewFeature` gate; outbound `readerAPI.*` via `evaluateJavascript` on Main | `class FoliateBridge`, `fun send(call)`, `val messages: Flow<FoliateMessage>` |
| `reader/Azw3Document.kt` | **@MainThread** WebView controller: open→bridge-ready→book-ready→`readerAPI.init(restore)`; page-turn; relocate callback updates main-owned `latestLocator` | `class Azw3Document`, `fun open/next/prev/destroy`, `var onRelocate` |
| `reader/Azw3LocatorBridge.kt` | `FoliateRelocate` → `VReaderLocator.wrapLegacy(Locator(...))`, NFC `progression`+`textQuote`+platform-local `cfi` | `object { fun toEnvelope(r,key,fmt) }` |
| `reader/Azw3ReaderActivity.kt` | ComponentActivity; Compose `AndroidView { WebView }`; sealed `Azw3UiState` (Loading/WebViewUnsupported/Corrupt/Empty/Loaded); conflated-channel save + onStop `latestLocator` flush; **owns `onRenderProcessGone` recovery**; intent factory | `companion { fun intent(ctx,fingerprintKey) }` |

### Modified files
`MainActivity.kt` (dispatch → `Azw3ReaderActivity.intent(this, book.id)`);
`AndroidManifest.xml` (`<activity .reader.Azw3ReaderActivity exported=false>`);
`android/app/build.gradle.kts` (+`androidx.webkit:webkit`, WI-3);
`android/version.properties`; `docs/architecture.md` (Android Foliate WebView engine
+ the security model).

### Out of scope
All `vreader/` (iOS), Readium/EPUB, libmobi/NDK. `:identity` value types **reused,
not modified** (no `ReaderLocatorEngine` change).

---

## Work-item sequencing

Tier: **F** foundational · **B** behavioral (Gate-5a slice on emulator).

- **WI-0 — Spike #1 (BLOCKING go/no-go + security verdict, throwaway) — F.**
  Instrumented harness (androidTest, not shipped). Proves: (1) the real 6 MB CJK
  AZW3 + a synthetic large book **open/paginate/navigate** with the (patched) bundle
  + shim, peak memory bounded, force-OOM → `onRenderProcessGone` recovers; (2) **the
  security mitigation holds** — the concrete hostile-AZW3 attack list (below) is
  BLOCKED, AND foliate still renders with the chosen patch; (3) locator round-trip
  (`relocate` → wrapLegacy → restore via `{cfi}`/`{fraction}`). Deliverable: a
  **verdict appended to this plan** + the bundle-patch decision. **If (1) or (2) fail
  without mitigation → STOP, escalate.** Small PR.
- **WI-1 — patched bundle + `bundle-patch.diff` + shell (shim+CSP) + provenance test — F.**
  Provenance test asserts the **patched** SHA-256 + that `bundle-patch.diff` applies
  cleanly to the iOS bundle. Small PR.
- **WI-2 — `FoliateMessageParser` + `FoliateAssetServer` (shell + book loaders) — F.** Small–medium PR.
- **WI-3 — `FoliateBridge` security integration (+`androidx.webkit`) — F (own audit).**
  `addWebMessageListener` shell-origin-only + `isMainFrame`/`sourceOrigin` reject;
  CSP; nav-block; feature-gate → `WebViewUnsupported`. **Re-runs the WI-0 hostile-AZW3
  test as a gate.** Medium PR.
- **WI-4 — `Azw3Document` (@MainThread WebView controller) — F.** Medium PR.
- **WI-5 — `Azw3LocatorBridge` (relocate → wrapLegacy) — F.** Small–medium PR.
- **WI-6 — `Azw3ReaderActivity` + Compose host + dispatch + manifest + render-death recovery — B.**
  Owns `onRenderProcessGone` recovery (snapshot `latestLocator` → remove+`destroy` →
  recreate on main → reopen → restore → return `true`). Design check: chrome mirrors
  the committed Android reader surfaces; `WebViewUnsupported` reuses the Pdf
  Corrupt/Empty pattern (else `needs-design`). Medium PR.
- **WI-7 — resume persist/restore + onStop flush — B.** Save per relocate via the
  conflated channel; onStop synchronously enqueues main-owned `latestLocator`, drains
  before close; restore `loadPosition→resolve→Canonical→readerAPI.init({cfi}|{fraction})`;
  **plain-`Locator` backup round-trip test**. Medium PR.
- **WI-8 — final acceptance (real CJK AZW3 e2e) — B (final WI).** Gate-5b on emulator
  with `Bei Tao Yan De Yong Qi - Zi Wo.azw3` (6.0 MB CJK): open/paginate/page-turn/
  resume-across-relaunch/render-death-survival. >10 MB memory-stress = documented gap
  (synthetic fixture in WI-0 only). Evidence file → `VERIFIED`. Small PR.

> 8 WIs + Spike-0 → **Large**: plan audited until clean; one Gate-4 audit per WI
> (WI-1/WI-5 may batch). WI-0's security verdict can reshape WI-1/WI-3.

---

## Test catalogue

| Test (Kotlin) | Tier | Covers |
|---|---|---|
| `androidTest/.../reader/foliate/FoliateSpikeHarnessTest.kt` (WI-0; re-run in WI-3) | instrumented | open real 6 MB CJK + synthetic-large in a WebView w/ patched bundle+shim; book-ready, pageCount>0, nav; peak memory; force-OOM→`onRenderProcessGone` recovers; **BLOCKING hostile-AZW3** in **both reflowable AND fixed-layout (EXTH `fixedLayout=true`) KF8** variants: a synthetic section attempts `parent.webkit.messageHandlers.vreaderHost.postMessage`, `parent.vreaderHost.postMessage`, direct iframe `vreaderHost.postMessage`, `javascript:` link, inline `onload/onerror` handler, `<svg><script>`, `fetch('file://')`/cross-origin fetch, **AND passive exfil — remote `<img>`, CSS `url()`, remote font/media, `<meta http-equiv=refresh>`, form submit, child-frame load** → **ALL blocked**; AND foliate still renders w/ the patch (test FAILS pre-mitigation, PASSES post). If fixed-layout can't be secured+rendered → assert the reader **rejects** it. |
| `test/.../reader/foliate/FoliateMessageParserTest.kt` (WI-2) | JVM | valid/invalid/empty/CJK/oversized; surrogate edges; reject malformed |
| `test/.../reader/foliate/FoliateOriginPolicyTest.kt` (WI-3) | JVM/Robolectric | accept only `sourceOrigin==SHELL_ORIGIN && isMainFrame`; reject sub-frames/foreign |
| `test/.../reader/Azw3LocatorBridgeTest.kt` (WI-5) | JVM | relocate→wrapLegacy: NFC CJK/diacritics, finite progression, textQuote triple, platform-local cfi; canonical conformance |
| `androidTest/.../reader/Azw3ReaderActivityTest.kt` (WI-6/7) | instrumented | import→Loaded; seed position→reopen→restore (cfi & fraction paths); `WebViewUnsupported`; render-death recovery |
| `test/.../reader/Azw3ResumeTest.kt` (WI-7) | JVM | `loadPosition→resolve→Canonical→{cfi}/{fraction}`; **plain-`Locator` backup round-trip** |
| `test/.../reader/Azw3UiStateTest.kt` (WI-6) | JVM | Loading→Loaded/Corrupt/Empty/WebViewUnsupported |

Edge cases: empty/0-byte, truncated/corrupt, large CJK (memory), KF8 vs old-MOBI,
no-spine/empty, rapid open/close, rotation/process-death→resume, WebView-unsupported.

---

## Risks + mitigations

| # | Risk | Mitigation |
|---|---|---|
| R1 | WebView OOM / KF8 decode slow on large books | Spike #1 measures on low-RAM AVD; **Activity-owned** `onRenderProcessGone` recovery; `setRendererPriorityPolicy(BOUND, waived-when-not-visible)`; `fetch()`-able URL, never marshal bytes. Escalate before WI-1 if unworkable. |
| R2 | **Book content reaches native** (section blobs are SHELL-ORIGIN, `allow-scripts` set → `parent.vreaderHost` escape) | **Strip `allow-scripts`** from section iframes (book JS unsupported) → no section script to escape; + CSP `script-src` lock, `isMainFrame`/origin reject, nav-block, file/universal access off. **WI-0 blocking verdict proves it; bundle becomes security-patched (C1).** |
| R3 | `addWebMessageListener` needs WebView 82+ | `WebViewFeature.isFeatureSupported` gate → `WebViewUnsupported` state |
| R4 | CFI lossy cross-platform | `wrapLegacy`; restore `{cfi}` else `{fraction}`+textQuote (the contract anchor) |
| R5 | bundle drift iOS↔Android | WI-1 provenance test asserts patched SHA + `bundle-patch.diff` applies to the iOS bundle |
| R6 | rule-51 `WebViewUnsupported` UI | reuse Pdf Corrupt/Empty pattern; `needs-design` only if judged self-designed |
| R7 | first WebView; lifecycle/rotation | mirror `PdfReaderActivity`; `DisposableEffect` destroy; @MainThread API; file IO off-main; test rotation+process-death |
| R8 | onStop save race | main-owned `latestLocator`; onStop enqueues exact value; drain before close |
| R9 | the security patch breaks foliate rendering | WI-0 falls back to CSP `script-src 'none'` on section blobs or HTML sanitization, re-tests; both also bundle patches |

---

## Backward compatibility
No Room schema change (`BookFormat.azw3` + all `Locator` fields exist). No
backup-format change (plain `Locator`; no new engine value). Cross-platform:
source-bytes identity matches iOS/Android; position restores via
`progression`+`textQuote` (cfi platform-local). WebView-unsupported → graceful state,
no data loss.

---

## Audit fixes applied
**Round 1** (Codex gpt-5.5/high, thread 019f1113…) — 2C/5H/4M/2L all addressed
(C1 shim, C2 webkit dep, C3 wrapLegacy/no-contract, H1 Canonical resume, H2 plain-Locator
backup, H3 two-origin, H4 Activity-owned render-death, M1 @MainThread, M2 latestLocator,
M3 6 MB corpus, M4 WI re-split to 8, L1/L2).
**Round 2** (Codex gpt-5.5/high) — confirmed all 12 round-1 fixes clean; reworked the
remaining 1C/1H:
- **C (security model)** — section blobs are SHELL-origin + `allow-scripts` → `isMainFrame`
  is not a complete boundary. Reworked to **disallow book scripts (strip `allow-scripts`)**
  as the primary boundary; bundle becomes **security-patched** (C1 updated) with a
  provenance hash + `bundle-patch.diff`; WI-0 is now a **blocking security verdict**.
- **H (hostile test)** — made the hostile-AZW3 test a **blocking gate** with the concrete
  attack list; FAILS pre-mitigation, PASSES post; re-run in WI-3.
- **B.1** — restore via `readerAPI.init({cfi})`/`{fraction}` (folded into WI-7).

**Round 3** (Codex gpt-5.5/high) — confirmed the security model directionally sound
(foliate measures sections from the parent; no in-frame script needed) and all
round-1/2 fixes intact; reworked the last 1C/1M:
- **C (fixed-layout escape)** — `allow-scripts` must be stripped from **`fixed-layout.js`**
  too (fixed-layout KF8), not just the paginator; bundle-patch covers every section-iframe
  sandbox; WI-0 adds a fixed-layout hostile variant; reader rejects fixed-layout if it
  can't be secured.
- **M (passive resources)** — added section CSP + `shouldInterceptRequest` blocking remote
  `img`/CSS/font/media/meta-refresh/child-frame; WI-0 hostile test covers passive exfil.

## Open question for WI-0 (chartered to resolve empirically)
Does stripping `allow-scripts` keep foliate's pagination/measurement working (it reads
the section DOM from the parent with same-origin access — should not need section
scripts), or does foliate inject a measurement script INTO the section frame? If the
latter, the patch must keep foliate's own injected script while blocking book script —
WI-0 resolves which mitigation (sandbox vs CSP vs sanitize) satisfies both.

## Revision history
- v1 (2026-06-29) — initial (claude).
- v2 (2026-06-29) — round-1 audit applied (2C/5H/4M/2L); WI re-split to 8; two-origin
  security; no contract change; main-thread discipline.
- v3 (2026-06-29) — round-2 audit applied (claude): reworked the security model around
  shell-origin section blobs (disallow book scripts → security-patched bundle); WI-0 is a
  blocking security verdict; concrete blocking hostile-AZW3 test; restore API concretized.
- v4 (2026-06-29) — round-3 audit applied (claude): patch **all** section-iframe sandboxes
  incl. fixed-layout (+reject-fixed-layout fallback); section CSP + `shouldInterceptRequest`
  for passive-resource exfil; WI-0 hostile test extended. Final confirmation pass pending.
