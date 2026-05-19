# Feature #57 — AZW3/MOBI TTS

**Status target for this gate:** `TODO` → `PLANNED`
**Workflow:** rule 47, six gates. This document is Gate 1.
**GH issue:** none yet. `GH: TBD` in the row. The issue is created at the `PLANNED` flip (per `file-feature`), not by this plan.
**Size:** Medium (4 WIs). Per rule 47's audit table: 1 plan audit, 1 PR audit per WI.

## Revision history

| Rev | Date       | Change |
| --- | ---------- | ------ |
| v1  | 2026-05-18 | Initial draft (Gate 1). |
| v2  | 2026-05-19 | **Substantive rework** after Gate-2 independent Codex audit (`019e3beb`, verdict NEEDS-REVISION). v1's core path-(a) premise — `document.body.innerText` on the Foliate host page yields book text — was proven WRONG by source inspection. v2 re-bases path (a) on the real DOM seam (`view.book.sections[].createDocument()`, the same walk `view.search()` already uses), adds a JS extraction helper to `foliate-host.js`, re-scopes WI-1 from pure plumbing to a feasibility slice with device verification, corrects the §4/§7/§9 overstatements about features #40/#41, gates AZW3 out of `ensureAIReady()`'s file-load path, makes the concurrency contract explicit, and makes a decisive recommendation on acceptance criteria 5 & 6. See §13 for the full finding-by-finding audit trail. |
| v3  | 2026-05-19 | **Targeted revision** after the round-2 independent Gate-2 audit (verdict NEEDS-REVISION; **no Critical/High** — the round-2 auditor confirmed the v2 core rework is genuine: the `createDocument()` section-walk, the WI-1 feasibility-slice scoping, the criteria-5/6 recommendation, the `ensureAIReady()` gate, and the explicit `@MainActor` `startTTS()` fix). v3 resolves all three round-2 findings: (1, MEDIUM) adds a concrete **in-flight extraction gate** — a `@State private var azw3ExtractionTask: Task<String?, Never>?` on `ReaderContainerView` — so rapid repeated speaker taps before the first whole-book walk completes either no-op or await the same task instead of spawning duplicate `extractPlainText()` walks and restarting speech (§3.1a, §6.4, §6.2 new test, §7 risk row, §12); (2, LOW) corrects §3.3 and §2.3 to describe the **real** build step — `build-bundle.sh` is an `npx esbuild --bundle` build with temporary stub-file writes and cleanup, not a "concatenation"; (3, LOW) corrects §4.1 so the DEBUG `evaluateJavaScript` precedent is described as "same API/channel, with Promise-value marshalling **to be validated in WI-1**" rather than as established prior art that a returned `Promise<string>` already resolves to Swift. §14 is the new round-2 audit trail. v2's §13 round-1 trail is retained unchanged. |

---

## 0. Gate-2 audit summary (why v2 is a rework, not an edit)

The Gate-2 independent audit (Codex `019e3beb`) returned **NEEDS-REVISION** with one CRITICAL and four HIGH findings. The CRITICAL finding invalidated v1's central mechanism, so v2 is a genuine re-design of the core extraction seam, not a light revision. §13 maps every finding to its v2 resolution. The headline correction:

> **v1 assumed `document.body.innerText` on the Foliate host page is the book-text surface. It is not.** The Foliate host page `<body>` contains only `<script>` tags and one `<foliate-view id="view">` custom element (verified: `foliate-reader.html:25-48`, and the inline HTML built in `FoliateSpikeView.swift:171-192`). The `View` custom element does `attachShadow({ mode: 'closed' })` (`view.js:214`), the `Paginator` renderer ALSO does `attachShadow({ mode: 'closed' })` (`paginator.js:429`), and the actual book content is rendered inside an `<iframe>` whose `contentDocument` lives two closed-shadow-roots deep (`paginator.js:213` `#iframe = document.createElement('iframe')`, `paginator.js:250-252` `get document() { return this.#iframe.contentDocument }`). `document.body.innerText` from the top page therefore returns an empty string. Even the corrected `view.renderer.getContents()[0].doc.body.innerText` yields only the **current section** (`paginator.js:1092-1099` — `getContents()` returns exactly one entry, the current `#view.document`), not the whole book.

v2's path (a) is rebuilt on the real seam (§2.2, §3) and the genuine implementation risk is moved to the front of the work-item sequence (§5, WI-1).

**Round-2 note:** the round-2 Gate-2 audit confirmed the v2 rework above is genuine and returned **no Critical/High**. v3 (this revision) is the targeted close-out of the three remaining round-2 findings (one MEDIUM, two LOW) — see §14. The §0 core diagnosis stands unchanged.

---

## 1. Problem

AZW3 and MOBI books render through Foliate-js inside a `WKWebView` (`FoliateSpikeView`). Unlike TXT/MD/PDF/EPUB, the Swift side has no parsed plain-text view of the content: `ReaderAICoordinator.loadBookTextContent` (`ReaderAICoordinator.swift:100-150`) has cases for `txt`, `md`, `pdf`, `epub` and a `default: return nil` — AZW3/MOBI fall through to `nil`.

Consequently `startTTS()` loads no text, its `if let text = ai.loadedTextContent, !text.isEmpty` guard (`ReaderContainerView+Sheets.swift:29` and `:41`) skips `ttsService.startSpeaking(...)`, and the user sees a silent failure: the speaker button does nothing.

Bug #176 / GH #602 mitigated this the cheap way — it removed `.tts` from `FormatCapabilities.capabilities(for: .azw3)` (`FormatCapabilities.swift:111-131`), which hides the speaker button entirely (the `ReaderMorePopover` gates its "Read aloud" row on `formatCapabilities.contains(.tts)` — `ReaderContainerView+Sheets.swift:238`). That stopped the silent failure but left AZW3/MOBI with no read-aloud at all.

This feature reverses that gate by implementing a real TTS path for AZW3/MOBI, so the speaker button works and TTS speaks the book text.

User value: read-aloud for the two formats — AZW3 and MOBI — that currently have none. (Scope of "sentence highlighting and auto-scroll" is addressed honestly in §7.1 and §9 — they are **not** currently wired for Foliate at all, and v2 makes a decisive recommendation on them rather than claiming they "work.")

---

## 2. Path decision: (a), (b), or hybrid

The row offers two options. **The plan chooses path (a): Foliate-webview plain-text extraction feeding the unified `AVSpeechSynthesizer` pipeline.** Path (b) is rejected. The rationale below is grounded in files read, and — unlike v1 — names the *real* DOM seam rather than the invalid `document.body.innerText` one.

### 2.1 Why path (b) is not achievable today

Path (b) is "wire `FoliateTTSAdapter` into a new code path; Foliate-js handles speech internally." Investigation shows it cannot ship against today's codebase without substantial new JS and a new SSML→speech bridge:

- **`FoliateTTSAdapter`'s message contract does not match the shipped JS bundle.** `FoliateTTSAdapter.parseTTSBlock(_:)` (`FoliateTTSAdapter.swift:69-77`) parses a `{ text: String, marks: [{name,start,end}] }` payload — a `tts-text` message. The production bundle `foliate-host.js` posts **`tts-ssml`** (`foliate-host.js:212-225`: `readerAPI.tts.start()` → `post('tts-ssml', { ssml })`), never `tts-text`. `FoliateTTSAdapter.parseTTSBlock` parses a shape nothing emits. (This finding is correct and is retained from v1; the Gate-2 auditor confirmed it as a LOW-severity correct rejection.)
- **Foliate-js TTS is SSML-based, not plain-text.** `view.tts.start()` (`tts.js` class `TTS`, lines 236-241) returns serialized **SSML XML** via `XMLSerializer` (`<speak>…<mark name="…"/>…`). `AVSpeechUtterance(string:)` takes plain text, not SSML — there is no SSML initializer in the iOS SDK surface this app targets. Path (b) would need a brand-new SSML→`AVSpeechUtterance` translator. None exists.
- **Foliate's in-webview TTS still needs an external speech engine.** `view.tts` only *segments and marks* text; it produces SSML for *someone else* to speak. The bundle posts the SSML out to Swift (`post('tts-ssml', …)`) precisely because Foliate-js contains no speech synthesiser. So "Foliate-js handles speech internally" — the row's framing of path (b) — is not what the code does.
- **`view.tts` is per-rendered-section, not whole-book.** `view.initTTS()` (`view.js:580-586`) reads `this.renderer.getContents()[0].doc` — the *currently paginated* section's iframe `contentDocument`. `tts.js`'s `getBlocks(doc)` (lines 123-143) walks exactly that one `doc.body`. Driving a whole-book read-aloud through it would require chaining `tts.next()` across sections with section-boundary state — a non-trivial new state machine.

Path (b) is therefore a much *larger* change than the row implies (new SSML translator + new section-chaining state machine + JS contract rework). And it would *not* improve features #40/#41 — path (b)'s word-mark highlight is a *different* feature using a different rendering surface (the Foliate overlay).

### 2.2 Why path (a) is the right choice — and the REAL seam it uses

Path (a) — extract the rendered book's plain text and feed it to the existing `AVSpeechSynthesizer` pipeline — is achievable today. **But it cannot use `document.body.innerText`.** v2 identifies the correct seam.

**The invalid seam (v1's premise):** `document.body.innerText` on the host page. Disproven above (§0): the host `<body>` holds only scripts + the `<foliate-view>` custom element; book content is two closed-shadow-roots + one iframe deep. Returns `""`.

**The real seam (v2):** `window.readerAPI` runs on the host page and holds a live reference to `view` (`foliate-host.js:7` `const view = document.getElementById('view')`). `view.book` is the parsed book object, and `view.book.sections` is an array where **each section exposes `createDocument()`** — an async function that returns a fully parsed, off-screen DOM `Document` for that section. This is verified for both formats:
- `epub.js:990` — `createDocument: () => this.loadDocument(item)`.
- `mobi.js:718` and `mobi.js:1023` — `createDocument: () => this.createDocument(section)` (MOBI/KF8 both).

**This is exactly the walk Foliate-js itself already uses for whole-book search.** `view.js`'s `#searchBook` (`view.js:528-539`) does:
```js
for (const [index, { createDocument }] of sections.entries()) {
    if (!createDocument) continue
    const doc = await createDocument()
    ...
}
```
So whole-book text extraction is a *known-good pattern in the bundle*, not a new mechanism. v2's JS helper (added to `foliate-host.js` as `readerAPI.extractPlainText()` — see §3) walks `view.book.sections`, calls `createDocument()` per section, reads `doc.body.textContent` (or `.innerText`), joins, and returns the string to Swift. `evaluateJavaScript` is expected to resolve the returned `Promise` to a Swift `String?` — and **that Promise-value marshalling is exactly what WI-1's feasibility slice validates** (§5; the round-2 audit's Finding 3 corrected v2's overstatement that this is already proven — see §4.1 and §14).

Why this is the right choice:

- **It is the genuine whole-book seam, runs entirely inside the page where `readerAPI`/`view.book` live, and needs no shadow-root or iframe traversal.** `createDocument()` produces off-screen documents — independent of what is currently paginated on screen.
- **EPUB is the structural precedent.** `loadBookTextContent`'s `"epub"` case (`ReaderAICoordinator.swift:118-138`) parses the EPUB spine to plain text *Swift-side* via `EPUBParser` + `EPUBTextExtractor.stripHTML`, then `startTTS()` speaks it through the *shared* `TTSService`. AZW3/MOBI has no Swift-side parser (`docs/architecture.md:5` — "AZW3/MOBI is rendered via Foliate-js"; `mobi.js` is the only MOBI parser and it is JS). Path (a) makes AZW3/MOBI structurally identical to EPUB *at the TTS seam* (shared `TTSService`), differing only in *where the text comes from* — a JS `evaluateJavaScript` call into Foliate's already-parsed `book.sections` instead of a Swift spine parse.
- **It is materially smaller and lower-risk than path (b).** No SSML translator, no new speech engine, no section-chaining playback state machine. One JS helper + one `loadBookTextContent`-class branch + one production WKWebView channel from `FoliateSpikeView`.
- **No new visible UI** — see §8 / Rule 51. The speaker button already exists; path (a) only re-adds the capability that ungates it.

**The genuine implementation risk** is no longer "does `innerText` work" — it is "does the `createDocument()` section-walk produce correct, complete plain text for real AZW3 *and* MOBI/KF8 fixtures, and does the returned Promise marshal cleanly across `evaluateJavaScript`." That risk is front-loaded into WI-1 as a feasibility slice with device verification (§5).

### 2.3 The JS-bundle constraint — corrected from v1, build step corrected in v3

v1 claimed path (a) needs **no** JS change (`document.body.innerText` is "a standard DOM property"). That is now moot because that property returns nothing here. **v2 path (a) DOES add a small JS helper** — `readerAPI.extractPlainText()` — to `vreader/Services/Foliate/JS/foliate-host.js`, and the bundle is rebuilt via the existing `build-bundle.sh`.

This is a deliberate, bounded scope expansion, and it is *not* a #42-scale change:
- `foliate-host.js` is the VReader-authored bridge adapter (its header: "Bridge adapter between Foliate-js `<foliate-view>` and VReader Swift host"), not vendored Foliate code. Adding one `readerAPI` method is exactly the kind of edit `foliate-host.js` exists for — it already hosts `readerAPI.search`, `readerAPI.initTTS`, `readerAPI.getState`, etc.
- The helper reuses the *existing* `view.book.sections[].createDocument()` API — no new Foliate-js internals, no edit to any file under `JS/vendor/`, no edit to `view.js`/`paginator.js`/`mobi.js`/`epub.js`.
- **`build-bundle.sh` is an `npx esbuild` *bundle build*, not a concatenation (round-2 Finding 2 correction — v2 incorrectly called it a "concatenation").** Verified by reading `vreader/Services/Foliate/JS/build-bundle.sh:1-17`: the script runs `set -euo pipefail`, `cd`s to its own directory, **writes three temporary stub files** for unsupported formats (`echo 'export const makeComicBook = …' > comic-book.js`, plus `fb2.js` and `pdf.js`), then runs `npx esbuild foliate-host.js --bundle --format=iife --global-name=FoliateHost --outfile=foliate-bundle.js`, then **deletes the temporary stubs** (`rm -f comic-book.js fb2.js pdf.js`) and prints the output byte count. It is deterministic and a single command to run, but it is an esbuild dependency-graph bundle with temp-stub creation/cleanup — not a `cat`-style concatenation. The bundle is then re-embedded — `FoliateSpikeView.makeUIView` loads `foliate-bundle.js` from `Bundle.main` and inlines it (`FoliateSpikeView.swift:165-187`).
- The bundle rebuild is a verification surface, but a contained one: WI-1's slice verification (§5) exercises the rebuilt bundle against real fixtures on device — opening a real book through the rebuilt bundle is the natural place to catch a bad esbuild rebuild (a broken bundle fails the live render loudly).

A `readerAPI.extractPlainText()` helper is *not* the same as the `readerAPI.getText()` the row's #42 dependency note flags. The row severs the #42 dependency only "if pursuing path a via Foliate's helpers" meaning #42-introduced helpers. `extractPlainText()` is a **#57-owned** helper added by this feature to `foliate-host.js`; it does not depend on #42's plan, #42's `readerAPI` additions, or #42's Gate-3 human ratification. #42 and #57 both touch `foliate-host.js`; §3.4 addresses the merge-order coordination.

### 2.4 Hybrid — rejected

A hybrid (path-a audio + path-b's Foliate word-mark highlight for the visual) was considered and rejected for #57: it pulls in the entire `tts-ssml` / `view.tts` section-chaining machinery just for highlighting, which is the bulk of path (b)'s cost. A Foliate word-mark / sentence-highlight overlay is a clean *follow-up feature* and is listed in §10 Deferred. See §7.1 for the decisive recommendation on whether #57 itself must carry visual highlight/scroll.

---

## 3. Surface area (file-by-file)

### 3.1 Files modified

**`vreader/Services/Foliate/JS/foliate-host.js`** — NEW in v2 (v1 declared all of `JS/*` out of scope; the CRITICAL finding forces this in).
Add one method to the `window.readerAPI` object, the whole-book plain-text extractor:

```js
// Feature #57: whole-book plain-text extraction for TTS.
// Walks view.book.sections (the same pattern view.search()'s
// #searchBook uses), builds an off-screen Document per section
// via createDocument(), and concatenates the body text. Runs on
// the host page where `view.book` is in scope — no shadow-root or
// iframe traversal. Returns a Promise<string> that evaluateJavaScript
// is expected to resolve to a Swift String (Promise-value marshalling
// is validated by WI-1's feasibility slice — §5).
async extractPlainText() {
    if (!bookReady || !currentBook?.sections) return ''
    const parts = []
    for (const section of currentBook.sections) {
        if (typeof section.createDocument !== 'function') continue
        try {
            const doc = await section.createDocument()
            const text = (doc?.body?.textContent ?? '').trim()
            if (text) parts.push(text)
        } catch (e) {
            // skip a section that fails to parse; partial text
            // is better than no TTS
            console.warn('[foliate-host] extractPlainText section failed:', e)
        }
    }
    return parts.join('\n\n')
}
```

Notes:
- `bookReady` and `currentBook` are already module-level state in `foliate-host.js` (lines 129-130), set in `readerAPI.open` (lines 137-138). The helper reuses them — no new state.
- `createDocument()` is the verified per-section parser (`epub.js:990`, `mobi.js:718`/`:1023`). The `typeof … === 'function'` guard mirrors `#searchBook`'s `if (!createDocument) continue` (`view.js:531`).
- Returning a `Promise<string>` is the intended contract: `WKWebView.evaluateJavaScript` is expected to await a returned Promise and deliver its resolved value. **That Promise-resolution behavior is the central feasibility item WI-1 verifies (§5)** — it is not asserted here as pre-proven. (The `readerAPI.search` precedent uses message-posting because it streams incrementally; extraction is a single value, so a returned Promise is the simpler shape if the marshalling works.)
- The host's inline `FoliateSpikeView` HTML (`FoliateSpikeView.swift:171-192`) embeds `foliate-bundle.js`; this helper ships once the bundle is rebuilt (§3.3 below).

**`vreader/Services/Foliate/JS/foliate-bundle.js`** — regenerated, not hand-edited.
Produced by re-running `vreader/Services/Foliate/JS/build-bundle.sh` (an `npx esbuild --bundle` build — §3.3) after the `foliate-host.js` edit. The functional diff is the added `extractPlainText` method, though esbuild may also re-emit unrelated minified output; no manual edits to the bundle output.

**`vreader/Models/FormatCapabilities.swift`**
In `capabilities(for:)`, `case .azw3` (lines 111-131): add `.tts` to the capability set and rewrite the bug #176 doc comment to reflect that #57 wired the production TTS path via the Foliate `extractPlainText` JS helper.

```swift
case .azw3:
    // Feature #57: TTS wired via the foliate-host.js `extractPlainText`
    // helper (whole-book section-walk over `view.book.sections`),
    // feeding the shared AVSpeechSynthesizer pipeline. Reverses the
    // bug #176 / GH #602 cap-gate. NOTE: visual sentence-highlight
    // and auto-scroll do NOT render in the Foliate WKWebView — see
    // feature #57 §7.1 and the row Notes. TTS audio works; the
    // #40/#41 visual leg is explicitly out of scope for Foliate.
    var caps: FormatCapabilities = [
        .textSelection, .highlights, .tts,
        .nativePagination, .toc, .annotations, .unifiedReflow,
    ]
    caps.formUnion(universal)
    return caps
```

**`vreader/Views/Reader/FoliateSpikeView.swift`**
Add a production (non-DEBUG) way for `ReaderContainerView` to obtain the rendered book's plain text from the live WKWebView. New `internal` async method on `FoliateSpikeView.Coordinator`:

```swift
/// Feature #57: extract the rendered book's whole-book plain text
/// for TTS by calling the foliate-host.js `readerAPI.extractPlainText()`
/// helper. Returns nil if the webview is gone or the book has not
/// finished rendering. MainActor-isolated — the Coordinator is used
/// on the main actor (its `webView` is touched only from main-actor
/// contexts: `handleMessage` is `@MainActor`, the notification
/// observers hop via `MainActor.assumeIsolated`). WKWebView APIs
/// require the main actor.
@MainActor
func extractPlainText() async -> String?
```

Implementation:
```swift
@MainActor
func extractPlainText() async -> String? {
    guard isBookReady, let webView else { return nil }
    let raw = try? await webView.evaluateJavaScript("readerAPI.extractPlainText()")
    return raw as? String
}
```
- `isBookReady` is the `Coordinator.isBookReady` Bool, flipped only by the `layout-ready` message handler (`FoliateSpikeView.swift:384-390`) — Foliate-js's true render-complete signal (bug #189). Gating on it reuses that hard-won ordering guarantee.
- `webView` is the existing `weak var webView: WKWebView?` (`FoliateSpikeView.swift:227`). `weak` → torn-down webview yields `nil` → safe no-op.
- `evaluateJavaScript("readerAPI.extractPlainText()")` evaluates a JS expression that returns a `Promise<string>`; the contract assumed here is that WKWebView resolves the Promise and delivers the resolved `String` — **WI-1's slice validates that this resolution actually happens** (§5; round-2 Finding 3). The literal is a fixed string — no interpolation, no injection surface.
- `as? String` coercion: a JS error or `NSNull` → `nil` (defensive; the helper returns `''` on the no-book path, not null, but the coercion still guards engine errors and a non-resolving Promise).

The Coordinator must be reachable from `FoliateSpikeView`. Today `FoliateSpikeWebView` (the `UIViewRepresentable`) is `private` and the Coordinator is created in `makeCoordinator()` (`FoliateSpikeView.swift:110-121`). Add a SwiftUI binding so `FoliateSpikeView` can hold a reference to the live Coordinator. New optional parameter on `FoliateSpikeView` and `FoliateSpikeWebView`:

```swift
/// Feature #57: set in makeCoordinator so the parent can request
/// TTS text extraction once the book is ready. Optional → preview/test
/// call sites stay source-compatible (same pattern as fingerprintKey,
/// readerToken, settingsStore, highlightActionPresenter — all already
/// optional on FoliateSpikeView for exactly this reason).
var coordinatorBox: FoliateCoordinatorBox?
```

`FoliateCoordinatorBox` is a tiny new `@MainActor` reference box holding `weak var coordinator: FoliateSpikeView.Coordinator?`, assigned inside `makeCoordinator()`. This avoids exposing the `Coordinator` type publicly while giving the parent a handle. Rationale: `FoliateSpikeView`'s WKWebView is created lazily in `makeUIView`; a box assigned in `makeCoordinator` is the SwiftUI-idiomatic seam — and unlike the DEBUG `DebugReaderRegistry`, it is production-safe, per-reader, and not a global singleton (convention 3: reader bridges receive data via `@State` ownership in the host, not global stores).

**`vreader/Views/Reader/ReaderContainerView.swift`**
- Add `@State` for the coordinator box: `@State private var foliateCoordinatorBox = FoliateCoordinatorBox()`.
- **Add `@State` for the in-flight AZW3 extraction task (round-2 Finding 1 — §3.1a):** `@State private var azw3ExtractionTask: Task<String?, Never>?`. This is the rapid-repeat gate; see §3.1a for why it lives on the host as `@State`.
- In `nativeReaderView`, `case "azw3"` (`ReaderContainerView.swift:679-686`): pass `coordinatorBox: foliateCoordinatorBox` to the `FoliateSpikeView(...)` initializer.
- No new UI. No new chrome. The speaker button already exists in `ReaderMorePopover` and is ungated by the §3.1 `FormatCapabilities` change.

**`vreader/Views/Reader/ReaderContainerView+Sheets.swift`** — two changes, both concurrency-corrected from v1.

*(a) `startTTS()` — the AZW3 text-source branch, with an explicit in-flight extraction gate (round-2 Finding 1).* `startTTS()` (lines 20-49) is the TTS entrypoint. v1 asserted it is `@MainActor`; **it is not annotated** (`ReaderContainerView+Sheets.swift:20`). v2 makes the contract explicit. `ReaderContainerView` is a SwiftUI `View`, so its members are main-actor-isolated by SwiftUI's `View` conformance in practice, but the audit is right that the symbol carries no explicit `@MainActor`. v2 **adds an explicit `@MainActor` annotation to `startTTS()`** so the WKWebView touch (`foliateCoordinatorBox.coordinator?.extractPlainText()`, itself `@MainActor`) has a stated, checkable isolation contract rather than relying on inference.

**Round-2 Finding 1 — the rapid-repeat gap v2 still had, and v3's fix.** Verified against the live code (`startTTS()` lines 20-49): the only re-tap guard in v2's design is `if ttsService.state != .idle { ttsService.stop(); return }` plus the `guard ai.loadedTextContent == nil else { return }` *inside* the AZW3 `Task`. Both only catch a re-tap **after** state has changed: the `ttsService.state` guard catches it once speech is *playing*; the `loadedTextContent` guard catches it once the whole-book walk has *finished and cached*. **Neither covers the window while the first `extractPlainText()` walk is in flight** — during that `await`, `ttsService.state` is still `.idle` (speech has not started) and `loadedTextContent` is still `nil` (the JS walk has not returned). A second speaker tap in that window passes both guards and spawns a *second* `Task { @MainActor in … extractPlainText() }`, re-running the whole-book `createDocument()` section walk and, when it completes, calling `startSpeaking` a second time. Because the whole-book section walk "may take noticeable time" (§7 risk row 2 already says so), this window is real, and AGENTS.md requires rapid repeated actions to be handled. v3 closes it with an explicit **in-flight extraction gate**: a stored `Task<String?, Never>?` on the host (`azw3ExtractionTask`, `@State` on `ReaderContainerView` — §3.1's `ReaderContainerView.swift` entry). The first AZW3 tap stores its extraction task; a subsequent tap before the first completes **awaits the same task** instead of spawning a new walk, and never issues a second `startSpeaking`.

The new branch:

```swift
@MainActor
func startTTS() {
    ensureAIReady()
    let ai = resolvedAICoordinator
    if ttsService.state != .idle {
        ttsService.stop()
        return
    }
    if let text = ai.loadedTextContent, !text.isEmpty {
        let offset = ai.currentLocator?.charOffsetUTF16 ?? 0
        withAnimation(.easeInOut(duration: 0.2)) {
            ttsService.startSpeaking(text: text, fromOffset: offset)
        }
    } else if resolvedBookFormat == .azw3 {
        // Feature #57: AZW3/MOBI text comes from the Foliate
        // WKWebView, not loadBookTextContent (which returns nil
        // for these formats). extractPlainText() is @MainActor;
        // this whole method is @MainActor; the WKWebView touch
        // never crosses onto a detached executor.
        startAZW3TTS(ai: ai)
    } else {
        // TXT/MD/PDF/EPUB: unchanged file-path load.
        Task {
            await ai.loadBookTextContent(
                fileURL: resolvedFileURL,
                format: book.format.lowercased()
            )
            if let text = ai.loadedTextContent, !text.isEmpty {
                let offset = ai.currentLocator?.charOffsetUTF16 ?? 0
                withAnimation(.easeInOut(duration: 0.2)) {
                    ttsService.startSpeaking(text: text, fromOffset: offset)
                }
            }
        }
    }
}

/// Feature #57 (v3, round-2 Finding 1): AZW3/MOBI TTS start with an
/// explicit in-flight extraction gate. The whole-book
/// `extractPlainText()` section walk can take noticeable time; a
/// rapid second speaker tap before it finishes must NOT spawn a
/// duplicate walk or a duplicate `startSpeaking`. The host holds the
/// extraction `Task` in `@State azw3ExtractionTask`; a re-tap awaits
/// that same task. `@MainActor` (inherited — startTTS() is @MainActor;
/// this is called only from it).
@MainActor
private func startAZW3TTS(ai: ReaderAICoordinator) {
    // Post-cache idempotency: a re-tap after a completed extraction
    // uses the cached text and never re-extracts.
    if let text = ai.loadedTextContent, !text.isEmpty {
        let offset = ai.currentLocator?.charOffsetUTF16 ?? 0
        withAnimation(.easeInOut(duration: 0.2)) {
            ttsService.startSpeaking(text: text, fromOffset: offset)
        }
        return
    }
    // In-flight gate: if an extraction walk is already running
    // (rapid repeated taps before the first walk completes), do NOT
    // start a second walk. Awaiting the existing task is harmless and
    // a no-op for speech start (the original task will start speech);
    // simply returning is the minimal correct behavior.
    if azw3ExtractionTask != nil { return }

    let task = Task { @MainActor () -> String? in
        await foliateCoordinatorBox.coordinator?.extractPlainText()
    }
    azw3ExtractionTask = task

    Task { @MainActor in
        // Bound the gate by a timeout — a wedged WKWebView or a Promise
        // that never resolves must not pin azw3ExtractionTask non-nil
        // forever (round-3 Finding). WI-2 adds a small `awaitExtraction`
        // helper that races `task.value` against a `Task.sleep` timeout
        // (~12s) via `withTaskGroup`; whichever finishes first wins and
        // the loser is cancelled.
        let text = await awaitExtraction(task, timeout: .seconds(12))
        azw3ExtractionTask = nil          // cleared on completion OR timeout
        task.cancel()                     // no-op if the walk already finished
        // Re-check state: the user may have tapped stop, or another
        // path may have set loadedTextContent, while the walk ran.
        guard ttsService.state == .idle else { return }
        guard ai.loadedTextContent == nil else { return }
        if let text, !text.isEmpty {
            ai.loadedTextContent = text
            let offset = ai.currentLocator?.charOffsetUTF16 ?? 0
            withAnimation(.easeInOut(duration: 0.2)) {
                ttsService.startSpeaking(text: text, fromOffset: offset)
            }
        }
        // empty/nil → no-op; ttsService stays .idle
    }
}
```

Notes on the in-flight gate:
- `azw3ExtractionTask` is `@State` on `ReaderContainerView` (an `@State`-owned per-reader handle — convention 3, the same ownership model as `foliateCoordinatorBox`). It is **not** a global, **not** on the Coordinator. The gate's lifetime is the reader's lifetime.
- `Task<String?, Never>` — `Never` failure type because `extractPlainText()` is non-throwing (it returns `String?`; a JS error is already coerced to `nil` inside `extractPlainText()`). Awaiting `task.value` therefore needs no `try`.
- The gate is cleared (`azw3ExtractionTask = nil`) exactly once — when the walk's value resolves **or the timeout fires**, whichever is first. A hung extraction therefore frees the gate after ~12s rather than wedging AZW3 TTS permanently (round-3 Finding); a *later* tap can then extract again if `loadedTextContent` is still `nil` (e.g. the first walk genuinely returned empty or timed out). A walk that produced text sets `loadedTextContent`, so subsequent taps take the post-cache fast path above and never re-extract.
- The `guard ttsService.state == .idle` re-check after the `await` is deliberate: between the tap that started the walk and the walk completing, the user could have triggered stop, or a re-tap could have... — actually a re-tap is gated out, but a stop is still possible via the control bar. Re-checking `.idle` means a stop during extraction does not get overridden by a late `startSpeaking`.
- **Idempotency is now total:** (i) re-tap while playing → `ttsService.state != .idle` early-return in `startTTS()`; (ii) re-tap *during* the first extraction walk → `azw3ExtractionTask != nil` → no second walk, no second `startSpeaking`; (iii) re-tap after a completed extraction → cached `loadedTextContent` fast path, no re-extraction. v2 had only (i) and (iii); v3 adds (ii) — the round-2 Finding 1 gap.

Decision — *where* the AZW3 branch lives: keep it in `startTTS()` / its `startAZW3TTS` helper, NOT in `loadBookTextContent`. `loadBookTextContent` does its work inside `Task.detached` (`ReaderAICoordinator.swift:103`) and has no main-actor WKWebView access; threading a webview reference into a detached task is a concurrency hazard. `startTTS()` is now explicitly `@MainActor` and already owns the load-then-speak sequencing. `loadBookTextContent`'s `default: return nil` stays — AZW3 simply never reaches it for TTS.

*(b) `ensureAIReady()` — gate AZW3 out of the detached file-load path.* This is a MEDIUM finding v1 missed. `startTTS()` calls `ensureAIReady()` on its first line. `ensureAIReady()` (lines 54-71) currently routes every non-TXT/MD format — including AZW3 — into `else { await ai.loadBookTextContent(fileURL:format:) }`. For AZW3 that detached task runs `loadBookTextContent`, hits `default: return nil`, and returns having done nothing — a wasted detached task that *also* runs concurrently with the new `extractPlainText()` path. It does no harm (it returns nil, never assigns `loadedTextContent`), but it is dead concurrent work and the audit is right that v1's "concurrency rationale is incomplete" because it ignored this path. v2 gates AZW3 out explicitly:

```swift
func ensureAIReady() {
    let ai = resolvedAICoordinator
    ai.setupIfNeeded()
    guard ai.loadedTextContent == nil else { return }
    Task {
        let format = book.format.lowercased()
        if format == "txt" || format == "md" {
            if let text = await contentCache.getText(for: resolvedFileURL, format: format) {
                ai.loadedTextContent = text
                ai.chatViewModel?.bookContext = ai.currentTextContent
            } else {
                await ai.loadBookTextContent(fileURL: resolvedFileURL, format: format)
            }
        } else if format == "azw3" || format == "azw" || format == "mobi" || format == "prc" {
            // Feature #57: AZW3/MOBI text is extracted from the Foliate
            // WKWebView on first speaker tap (startTTS()'s azw3 branch),
            // not loaded from the file here — loadBookTextContent has no
            // azw3 case and would return nil. Skipping this avoids a
            // dead detached task that otherwise runs concurrently with
            // extractPlainText(). AI-context text for AZW3 is a separate
            // gap tracked outside #57 (see §10).
        } else {
            await ai.loadBookTextContent(fileURL: resolvedFileURL, format: format)
        }
    }
}
```

The format check matches `BookFormat.azw3`'s extension set (`azw3/azw/mobi/prc` — `BookFormat.swift:33`); `book.format` is the raw stored string. (Alternatively, factor a `resolvedBookFormat == .azw3` typed check — see §6.3's preference for a pure helper. Either is acceptable; the typed-enum form is preferred for the same reason `ReaderContainerView.swift:471/495` compares on the typed enum, not raw strings.)

Note this carries one honest consequence, surfaced rather than hidden: AZW3's *AI-context* text (the `chatViewModel.bookContext`, used by the AI panel) was *already* nil before #57 (`loadBookTextContent` already returned nil for AZW3). v2's gate does not regress that — it just stops *pretending* to load it. Wiring AZW3 AI-context text via the same `extractPlainText()` helper is a clean, listed follow-up (§10), out of scope for #57 which is a TTS feature.

**`vreader/Services/Foliate/FoliateTTSAdapter.swift`**
No change in this feature. It stays unwired. Do NOT delete it (out of scope; a future Foliate word-mark / sentence-highlight overlay feature may use it after the `tts-ssml` contract is reconciled). Its existing tests stay green untouched.

**`vreaderTests/Models/FormatCapabilitiesTests.swift`**
- **Remove** `azw3_doesNotSupportTTS()` (lines 120-134) — the regression guard that pinned the bug #176 cap-gate.
- **Add** `azw3_supportsTTS()` — positive assertion.
- **Audit** the two `for format in BookFormat.allCases` loop tests: `only_md_epub_azw3_supportUnifiedReflow_simpleEPUB` (line 48) and `only_md_supportsAutoPageTurn` (line 146). Confirmed by reading the file: neither asserts anything about `.tts` (the first switches on `.unifiedReflow`, the second on `.autoPageTurn`), so neither breaks. `pdf_supportsSelection_..._notTTS_...` (line 100) and `capabilities_pdfAlwaysNative...` (line 201) assert `!.tts` for **PDF only** — unaffected. `azw3_doesNotSupportAutoPageTurn` (line 113) is about `.autoPageTurn`, not `.tts` — unaffected. `hashableConformance` (line 274) uses `.tts` only in synthetic option sets — unaffected. **No other test asserts `azw3` lacks `.tts`.**

### 3.2 Files NEW

**`vreader/Views/Reader/FoliateCoordinatorBox.swift`** (small, ~20 lines)
The reference box described in §3.1. `@MainActor`, holds `weak var coordinator: FoliateSpikeView.Coordinator?`. Lives under `Views/Reader/` next to `FoliateSpikeView.swift`. May alternatively be a nested type inside `FoliateSpikeView.swift` — final placement is an implementation detail; the box type itself is required.

**`vreaderTests/Views/Reader/FoliateSpikeViewTTSTests.swift`** (new test file)
Covers `extractPlainText()`'s contract and `FoliateCoordinatorBox`'s weak-holding (see §6 — what's unit-testable vs. what needs device verification).

### 3.3 Build / bundle step

The `foliate-host.js` edit is not live until `foliate-bundle.js` is regenerated and re-embedded. **The build step is an `npx esbuild` bundle build, not a concatenation** — round-2 Finding 2 corrected v2's wording. Concretely, after editing `foliate-host.js` the implementer runs `vreader/Services/Foliate/JS/build-bundle.sh` (verified present, `build-bundle.sh:1-17`). That script:
1. Runs `set -euo pipefail` and `cd "$(dirname "$0")"` (so it works from any cwd).
2. **Writes three temporary stub files** for unsupported formats — `comic-book.js`, `fb2.js`, `pdf.js` — each an `echo`'d one-line `export const make… = () => { throw new Error("not supported") }`.
3. Runs the actual bundle: `npx esbuild foliate-host.js --bundle --format=iife --global-name=FoliateHost --outfile=foliate-bundle.js` — an esbuild dependency-graph bundle, IIFE format, global name `FoliateHost`.
4. **Deletes the temporary stubs** (`rm -f comic-book.js fb2.js pdf.js`) and prints the resulting byte count.

So the implementer runs one command, but it is an esbuild build with temp-stub scaffolding and cleanup — the plan must not call it a "concatenation." `FoliateSpikeView.makeUIView` then loads `foliate-bundle.js` from `Bundle.main` at runtime and inlines it into the host HTML (`FoliateSpikeView.swift:165-187`) — so once the bundle is regenerated and the app rebuilt, the new `readerAPI.extractPlainText` is available. This bundle rebuild is part of WI-1 and is exercised by WI-1's device slice (§5): opening a real book through the rebuilt bundle is the guard against an esbuild build breakage (a broken bundle fails the live render loudly — book doesn't render, or the `error` message handler fires).

### 3.4 Files OUT of scope

- **`vreader/Views/Reader/FoliateViewBridge.swift`**, **`FoliateViewCoordinator.swift`**, **`FoliateReaderContainerView.swift`** (+ its `+Highlights` / `+Navigation` extensions), **`FoliateReaderHost`** (in `ReaderFormatHosts.swift`), **`vreader/ViewModels/FoliateReaderViewModel.swift`** — the *unwired* Foliate stack (the likely #42 target). `docs/architecture.md:54` and `:82` confirm `FoliateReaderHost`/`FoliateReaderContainerView` "exist but are not currently wired into `ReaderContainerView`"; `ReaderContainerView.nativeReaderView` routes `.azw3` to `FoliateSpikeView` (`ReaderContainerView.swift:679`). Touching the unwired stack would be wasted work and risks colliding with #42. **This feature only touches the live `FoliateSpikeView` path.**
- **`vreader/Services/Foliate/JS/*` EXCEPT `foliate-host.js` + `foliate-bundle.js`** — v2 touches *only* `foliate-host.js` (the VReader-authored bridge) and the regenerated `foliate-bundle.js`. `view.js`, `paginator.js`, `tts.js`, `mobi.js`, `epub.js`, everything under `JS/vendor/`, `build-bundle.sh` itself — **not edited.** The `extractPlainText` helper consumes the *existing* `view.book.sections[].createDocument()` API; it adds no Foliate-js internals.
- **`vreader/Services/Foliate/FoliateTTSAdapter.swift`** — stays unwired (see §3.1). Not deleted, not modified.
- **`vreader/Services/TTS/TTSHighlightCoordinator.swift`**, **`TTSService.swift`** — the shared TTS *audio* pipeline is reused as-is. No changes. (`TTSService` handles UTF-16 offsets, surrogate alignment, pause/resume/stop, and the DebugSnapshot `ttsProbe` — all formats share it.) Note `TTSHighlightCoordinator` is **not wired for Foliate at all** — see §7.1; this is a correction of v1's overstatement, not a code change.
- **`vreader/Views/Reader/TTSControlBar.swift`** — already format-agnostic; renders whenever `ttsService.state != .idle`. No change.
- **DebugBridge** (`DebugCommand.swift`, `RealDebugBridgeContext.swift`, `DebugReaderRegistry.swift`, `DebugReaderProbeAdapter.swift`) — `vreader-debug://tts?action=start|stop` already routes through the `.debugBridgeTTSCommand` observer in `ReaderContainerView`, which calls the shared `startTTS()`. Once `startTTS()` handles AZW3 (§3.1), the debug route works for AZW3 *for free* — acceptance criterion (3) is satisfied by the §3.1 changes with no DebugBridge edit. `DebugReaderProbeAdapter`'s `ttsProbe` already surfaces `ttsState`/`ttsOffsetUTF16` for any format. The DEBUG `jsEvaluator` AZW3 wiring (`ReaderContainerView.swift:495-529`) is **unrelated** — it is a DEBUG-only `vreader-debug://eval` channel; #57's production `extractPlainText()` uses the new `FoliateCoordinatorBox`, not `DebugReaderRegistry`. (The DEBUG `jsEvaluator` *is* useful as the WI-1 instrument to exercise `readerAPI.extractPlainText()` against a live render — see §4.1 and §5 — but #57 does not depend on or modify it.)
- **Feature #42's plan / #42-introduced `readerAPI` additions** — explicitly NOT depended on. The row lists "#42 (PLANNED)" as a dependency *only* "for the readerAPI helpers if pursuing path a via Foliate's helpers." #57 pursues path (a) via its **own** `extractPlainText` helper added to `foliate-host.js`, not a #42-introduced helper — so the #42 *dependency* is severed. **Coordination, not dependency:** both #42 and #57 edit `foliate-host.js`. #42's Gate 3 is BLOCKED on human ratification and is not expected to land before #57. If #42 *does* land first, #57's `extractPlainText` re-applies cleanly onto whatever `foliate-host.js` #42 produces (it is an additive method on `readerAPI`). If #57 lands first, #42's plan absorbs the helper. This is a routine merge-order note; #57's Gate 3 does not wait on #42.
- **Chunked-rendering / unified-mode TTS** — out of scope; AZW3 in unified mode falls back to `UnifiedPlaceholderView` (`docs/architecture.md:53`) and has no TTS surface there. Native-mode `FoliateSpikeView` only.

---

## 4. Prior art / project precedent / rejected alternatives

### 4.1 Prior art we build on

- **EPUB TTS via `loadBookTextContent` + shared `TTSService`** — the *structural* precedent at the TTS seam. `loadBookTextContent`'s `"epub"` case (`ReaderAICoordinator.swift:118-138`) parses spine items to plain text; `startTTS()` speaks that text through the shared `TTSService`. AZW3/MOBI gets the same shared-`TTSService` treatment with a *different* text source. (Difference from v1's framing: EPUB extracts Swift-side via `EPUBParser`; AZW3/MOBI has no Swift parser, so it extracts via JS. The shared part is the audio pipeline, not the extraction mechanism.)
- **Foliate-js whole-book section-walk** — `view.search()`'s `#searchBook` (`view.js:528-539`) already iterates `book.sections.entries()` and calls `createDocument()` per section to build off-screen documents for searching. `extractPlainText` is the *same walk* applied to text concatenation instead of search-matching. v2's core mechanism is a known-good pattern already in the bundle, not an invention.
- **The capability-gate cheap-path pattern** — bugs #156/#157/#158/#176 all gate a broken affordance off via `FormatCapabilities` rather than ship a silent failure. #57 is the documented *reverse* of #176's gate: re-add `.tts` once the real path lands. The current `FormatCapabilities.swift` `case .azw3` doc comment (lines 122-124) literally says "Re-add `.tts` here when the production wire-up ships."
- **Optional-binding-for-source-compat pattern** — `FoliateSpikeView` already threads `fingerprintKey: String?`, `readerToken: UUID?`, `settingsStore: ReaderSettingsStore?`, `highlightActionPresenter: (any HighlightActionPresenting)?` as optionals (`FoliateSpikeView.swift:17-28`) "so legacy call sites (previews, tests) compile." The new `coordinatorBox:` follows the identical pattern.
- **Bug #189's `layout-ready` message** — `FoliateSpikeView` has a *correct* render-complete signal: the Coordinator flips `isBookReady` only on the `layout-ready` message (`FoliateSpikeView.swift:384-390`), posted by the book-ready IIFE *after* `readerAPI.init({})` resolves. `extractPlainText()` gates on `isBookReady`, reusing this ordering guarantee instead of inventing a new one — directly answering the row's path-(a) risk ("which fires DOMContentLoaded when?").
- **`foliate-host.js` as the bridge-edit surface** — `foliate-host.js` is VReader-authored and already hosts the `readerAPI` object with `open`, `init`, `search`, `initTTS`, `getState`, `setLayout`, etc. (lines 132-260). Adding `extractPlainText` is a routine extension of that object, not a Foliate-internals change.
- **`evaluateJavaScript` against the live Foliate webview — same API/channel, with Promise-value marshalling TO BE VALIDATED IN WI-1.** *(Round-2 Finding 3 correction — v2 overstated this row.)* What the codebase *does* establish: the DEBUG `jsEvaluator` AZW3 path (`ReaderContainerView.swift:507-517`) does `let raw = try await webView.evaluateJavaScript(script)` against the **live `FoliateSpikeView` WKWebView** — so it is proven that `evaluateJavaScript` reaches that webview and returns *a* value, and (separately) `FoliateSpikeView`'s own bundle interaction proves completion handlers fire before an async IIFE finishes. What the codebase does **NOT** establish: that a returned JS `Promise<string>` is awaited by `evaluateJavaScript` and its *resolved value* delivered to the Swift `async` call — the `vreader-debug://eval` channel evaluates arbitrary scripts and never specifically exercises Promise-return marshalling. `extractPlainText()` uses the **same `evaluateJavaScript` API and the same live-webview channel**, but its reliance on Promise-value resolution is a **feasibility item that WI-1's device slice validates** (§5), not established prior art. WI-1 already treats it as such; this row is corrected so §4 does not present it as proven.

### 4.2 Rejected alternatives

- **`document.body.innerText` on the Foliate host page (v1's premise).** Rejected — **disproven**. The host `<body>` holds only `<script>` + `<foliate-view>` (`foliate-reader.html:25-48`; `FoliateSpikeView.swift:171-192`); `View` and `Paginator` each `attachShadow({ mode: 'closed' })` (`view.js:214`, `paginator.js:429`); book content renders inside an iframe `contentDocument` (`paginator.js:213/250-252`). Top-page `innerText` returns `""`. This is the CRITICAL Gate-2 finding.
- **`view.renderer.getContents()[0].doc.body.innerText` (the "corrected" innerText).** Rejected — `getContents()` returns exactly ONE entry: the *current* section's iframe doc (`paginator.js:1092-1099`). This yields only the current section / current spread, not the whole book. Acceptable *only* as a deliberately-scoped "current-section TTS" fallback — see §7 risk row 1 — but the whole-book `createDocument()` walk is the chosen primary, because it matches the row's intent ("TTS speaks the AZW3 text", criterion 2) and the EPUB whole-book precedent.
- **Path (b): `FoliateTTSAdapter` + Foliate in-webview SSML TTS.** Rejected — see §2.1. Contract mismatch (`tts-text` vs `tts-ssml`), no SSML→`AVSpeechUtterance` bridge, per-section not whole-book, larger than the row implies.
- **Extract text via a new Swift-side AZW3/MOBI parser, bypassing the webview.** Rejected — there is no Swift AZW3/MOBI parser; `mobi.js` is the only MOBI parser and it is JS (`docs/architecture.md:5`). Building a Swift MOBI text extractor duplicates `mobi.js` and is far larger than #57.
- **Put the AZW3 branch inside `loadBookTextContent`.** Rejected — that method runs inside `Task.detached` (`ReaderAICoordinator.swift:103`); WKWebView is main-actor-only. Keep the webview touch in `startTTS()` / `startAZW3TTS` (now explicitly `@MainActor`). See §3.1.
- **Use a global registry (the DEBUG `DebugReaderRegistry`) to reach the Foliate webview in production.** Rejected — convention 3: reader bridges receive data via `@State` ownership in the host, not global stores. The `FoliateCoordinatorBox` `@State` handle respects that; promoting `DebugReaderRegistry` to a Release symbol would also break `verify-release-no-debugbridge.sh`.
- **Extract text eagerly on book-ready and cache.** Rejected — bug #64's "deferred setup" convention: AI/TTS text loads on first *invoke*, not on open. `extractPlainText()` is called from `startTTS()` (first speaker tap), consistent with EPUB. (A whole-book `createDocument()` walk is also not free — deferring it to first tap avoids paying it on every AZW3 open.)
- **Stream the extracted text via `post('tts-text', …)` messages instead of a returned Promise.** Rejected as the *primary* — extraction produces a single value, not an incremental stream; a returned `Promise<string>` resolved by `evaluateJavaScript` is the simpler shape. (`readerAPI.search` uses message-posting precisely because it streams progressively — a different shape.) **Retained as the named WI-1 fallback** if the slice shows the returned Promise does not marshal cleanly (§5 decision gate, §7 risk row 1) — because Promise-value marshalling is a WI-1 feasibility item (§4.1, round-2 Finding 3), not pre-proven.
- **Rely only on `ttsService.state`/`loadedTextContent` to make rapid taps idempotent (v2's design).** Rejected as *incomplete* — round-2 Finding 1. Those two guards only cover the post-speech and post-cache states; they leave the in-flight-extraction window open, so rapid taps during the first whole-book walk spawn duplicate `extractPlainText()` walks. v3 adds the explicit `azw3ExtractionTask` in-flight gate (§3.1a) on top of those two guards.

---

## 5. Work-item sequencing

4 WIs (v1 had 3 — WI-1 is split-in-spirit: it now carries the JS helper + the feasibility proof, which is genuine engineering risk, not plumbing). Each WI is one PR. The strict dependency chain is WI-1 → WI-2 → WI-3 → WI-4.

### WI-1 — `extractPlainText` JS helper + Swift extraction channel + **feasibility proof** (foundational seam, device-verified)

This is the WI the Gate-2 audit demanded be re-scoped: in v1 a foundational WI-1 (`FoliateCoordinatorBox` + unit tests only) could merge while the actual extraction seam was still invalid. v2's WI-1 **proves the real seam against a live Foliate render before any downstream WI is approved.**

**Scope:**
1. Add `readerAPI.extractPlainText()` to `foliate-host.js` (§3.1).
2. Regenerate `foliate-bundle.js` via `build-bundle.sh` — the `npx esbuild --bundle` build with temp-stub scaffolding/cleanup (§3.3).
3. Add `FoliateCoordinatorBox` (new file or nested type), the `coordinatorBox:` optional binding on `FoliateSpikeView` + `FoliateSpikeWebView`, the box assignment in `makeCoordinator()`, and the `extractPlainText() async -> String?` method on `FoliateSpikeView.Coordinator`.
4. Wire the `@State foliateCoordinatorBox` into `ReaderContainerView` and pass it to `FoliateSpikeView` in `nativeReaderView`'s `case "azw3"` — so the box is *populated* and `extractPlainText()` is *callable* against a real render. (v1 deferred this to WI-2; v2 pulls it forward because WI-1's whole purpose is to prove the seam works against a live render, which requires the box to be wired.)
   - No `startTTS()` change yet, and `FormatCapabilities` is unchanged — the speaker button stays hidden. The only way the extraction path runs in WI-1 is the device slice below.

**Why this tier — behavioral / feasibility, NOT foundational:** WI-1 adds JS that runs in a live WKWebView and an extraction method whose correctness *cannot* be proven by unit tests (no WKWebView/Foliate render in the XCUnit harness). Per rule 47 Gate 5, anything touching "reader rendering" is behavioral and requires slice verification. WI-1 is explicitly **gated on a device slice** before WI-2 is approved.

**Tests (unit):** `FoliateSpikeViewTTSTests.swift` —
- `extractPlainText()` returns `nil` when `isBookReady == false` (the ordering guarantee — no extraction before `layout-ready`).
- `extractPlainText()` returns `nil` when `webView == nil` (teardown safety).
- The JS string evaluated is exactly `readerAPI.extractPlainText()` — assert the literal (no interpolation → no escaping needed, no injection surface).
- `FoliateCoordinatorBox` holds the coordinator weakly (set, release coordinator, expect `nil` — no retain cycle).
- `FoliateCoordinatorBox` fresh instance has `nil` coordinator (so a `startTTS()` before render is a clean no-op).

**Device slice verification (the feasibility gate — REQUIRED before WI-2):** On iPhone 17 Pro Simulator, open a real AZW3 fixture **and** a real MOBI/KF8 fixture (the `extractPlainText` helper and the `BookFormat.azw3` route both cover `azw3/azw/mobi/prc`). Drive `readerAPI.extractPlainText()` via the DEBUG `vreader-debug://eval` channel (the AZW3 `jsEvaluator` is already wired — `ReaderContainerView.swift:507`) and record, in the WI-1 PR description:
- Whether the returned value is a non-empty `String`.
- Its approximate length, and a head/tail excerpt, compared against the known fixture content — to confirm it is **whole-book**, not one section, and not shell chrome.
- **Whether the returned `Promise<string>` marshals cleanly across `evaluateJavaScript`** — i.e. whether the Promise's *resolved value* (not a pending-Promise placeholder, not `NSNull`) is delivered to Swift, with no timeout and no JS error in the `error` message handler. **This is the explicit validation of the §4.1 Promise-marshalling feasibility item (round-2 Finding 3) — WI-1 confirms it; the plan does not assume it.**
- The same three checks for the MOBI fixture.
- Extraction wall-time on each fixture (feeds §7 risk row 2).

**Decision gate:** if the slice shows `extractPlainText` returns correct whole-book text for both formats **and the returned Promise resolves to that text in Swift** → WI-2 proceeds as written. If it shows only partial text, a Promise that does not marshal (pending/NSNull), or a per-format divergence → **stop and escalate to the user** (per rule 47 Gate 2's "escalate after unresolved findings" discipline and Gate 5's evidence requirement). Candidate fallbacks to present at that point: (i) deliberately-scoped current-section TTS via `getContents()[0].doc`; (ii) **message-posting (`post('tts-text', …)`) instead of a returned Promise — the fallback specifically for the case where the Promise does not marshal.** v2 does not pre-commit to a fallback — the slice picks.

**Estimated PR size:** Medium — ~15-25 lines JS (`foliate-host.js`) + regenerated bundle (esbuild output, not hand-written), ~25 lines `FoliateSpikeView.swift`, ~20-line box file, ~5 lines `ReaderContainerView.swift`, ~90 lines tests. The bundle regen inflates the diff but is esbuild-generated, not authored.

### WI-2 — `startTTS()` AZW3 text-source branch + in-flight extraction gate + `ensureAIReady()` AZW3 gate (behavioral)

**Scope:** In `ReaderContainerView+Sheets.swift` and `ReaderContainerView.swift`:
- (a) add the `@MainActor` annotation to `startTTS()` and the AZW3 branch via the `startAZW3TTS(ai:)` helper (§3.1a) — when `resolvedBookFormat == .azw3` and `loadedTextContent` is nil, `await foliateCoordinatorBox.coordinator?.extractPlainText()`, assign to `resolvedAICoordinator.loadedTextContent`, then `ttsService.startSpeaking(...)`.
- (b) **add the in-flight extraction gate (round-2 Finding 1):** the `@State private var azw3ExtractionTask: Task<String?, Never>?` on `ReaderContainerView`, and the `startAZW3TTS` logic that stores the extraction `Task`, makes a rapid second tap before the first walk completes a no-op (`azw3ExtractionTask != nil → return`), clears the gate when the walk's value is awaited, and re-checks `ttsService.state == .idle` before a late `startSpeaking`. This is the three-layer idempotency described in §3.1a (playing / in-flight / post-cache).
- (c) gate AZW3/MOBI out of `ensureAIReady()`'s detached file-load path (§3.1b).

`FormatCapabilities` is still NOT changed in this WI — the speaker button is still hidden; the path is exercised only via `vreader-debug://tts?action=start` (which bypasses the capability gate — the debug observer calls `startTTS()` directly). Empty/nil extraction → no-op (`!text.isEmpty` guard).

**Why behavioral:** changes runtime behavior — TTS now actually speaks for AZW3 when triggered via the debug route. Slice verification required (rule 47 Gate 5 behavioral tier): on iPhone 17 Pro Sim, open an AZW3 fixture, fire `vreader-debug://tts?action=start`, confirm `vreader-debug://snapshot` reports `ttsState: "speaking"` and `ttsOffsetUTF16` advances between two snapshots; then `vreader-debug://tts?action=stop` → `ttsState: "idle"`. **Additionally, exercise the rapid-repeat path:** fire `vreader-debug://tts?action=start` twice in quick succession (before the first whole-book extraction can complete — a large fixture makes this window observable) and confirm via snapshots that exactly one speech session starts (`ttsState` transitions `idle → speaking` once, `ttsOffsetUTF16` advances monotonically, no restart-to-0) — the in-flight gate prevented a duplicate walk and a duplicate `startSpeaking`.

**Tests:** Prefer extracting the format-routing decision into a pure, testable function — e.g. `TTSTextSource.source(for: BookFormat) -> .foliateExtraction | .fileLoad` — so the "which text source for which format" choice is unit-tested directly. `startTTS()` itself is `@MainActor` SwiftUI-view code, not directly unit-instantiable. Tests:
- `ttsTextSource_azw3_usesFoliateExtraction` — AZW3 routes to the Foliate-webview source.
- `ttsTextSource_txtMdPdfEpub_usesFileLoad` — the other four formats still route to `loadBookTextContent` / `contentCache` (regression guard).
- `startTTS_azw3_nilCoordinator_isNoOp` — box never populated (render not mounted) → no crash, `ttsService.state` stays `.idle`.
- `startTTS_azw3_emptyExtraction_isNoOp` — `extractPlainText()` → `""` → `startSpeaking` skipped.
- **`startAZW3TTS_rapidRepeatDuringExtraction_singleWalk` (round-2 Finding 1 — see §6.2 for the exact factoring):** while a first extraction `Task` is in flight, a second invocation does not start a second extraction and does not issue a second `startSpeaking` — covered by exercising the in-flight gate on a pure/seam-testable surface (the gate's `Task<String?,Never>?`-presence check).
- If `ensureAIReady`'s format gate is also factored through the same pure helper, add `ensureAIReady_azw3_skipsFileLoad`.

If the routing or the in-flight gate genuinely cannot be cleanly factored, WI-2's behavior is covered by slice verification instead — but the plan's preference, and the Gate-2/Gate-4 expectation, is the pure helper plus a unit test of the gate.

**Estimated PR size:** Small–Medium — ~70-95 lines source (the `startAZW3TTS` helper + the `azw3ExtractionTask` `@State` + the `ensureAIReady` gate), ~65 lines tests.

### WI-3 — Re-add `.tts` capability + flip the regression test (behavioral)

**Scope:** Add `.tts` to `FormatCapabilities.capabilities(for: .azw3)`; rewrite the `case .azw3` doc comment (§3.1). In `FormatCapabilitiesTests.swift`, remove `azw3_doesNotSupportTTS()`, add `azw3_supportsTTS()`. This is the WI that makes the speaker button visible (the `ReaderMorePopover` gate opens).

**Why behavioral:** flips a user-visible affordance on. Slice verification: on iPhone 17 Pro Sim, open an AZW3 book, open the More-menu, confirm the "Read aloud" row is present, tap it, confirm TTS speaks (snapshot `ttsState: "speaking"`). Also tap the row twice in quick succession and confirm exactly one speech session starts (the in-flight gate from WI-2 applies to the speaker-button entry point too — both entry points call the same `startTTS()`).

**Tests:** `azw3_supportsTTS()` — `#expect(FormatCapabilities.capabilities(for: .azw3).contains(.tts))`. Plus the full existing suite stays green (the §3.1 audit confirmed the loop tests are unaffected — the WI re-runs the suite to prove it).

**Estimated PR size:** Small — ~15 lines source (capability + comment), ~15 lines test delta.

### WI-4 — Full acceptance pass + verification evidence (final WI)

**Scope:** No new code. WI-4 is the final-WI full end-to-end acceptance pass against every criterion in §9, recorded in `dev-docs/verification/feature-57-<YYYYMMDD>.md` per `dev-docs/verification/SCHEMA.md`. The `check_terminal_status_evidence.sh` PreToolUse hook enforces the evidence file before the row can flip to `VERIFIED`. The acceptance pass explicitly includes the rapid-repeat case (tap the speaker button twice in quick succession on a large AZW3 fixture; record that exactly one speech session starts).

Splitting the final acceptance pass into its own WI (rather than folding it into WI-3) keeps WI-3's PR a focused capability flip and gives the final acceptance pass — which must exercise pause/resume/stop, the debug route, both AZW3 and MOBI fixtures, the rapid-repeat path, and explicitly *record* the §7.1 limitation — a clean home. This mirrors how `feature-40` and `feature-41` ran multi-round verification as a distinct activity.

**Why final:** completes the feature; flips the row `DONE` → `VERIFIED`.

**Estimated PR size:** None (verification activity) — or a docs-only PR carrying the evidence file if the repo convention requires the evidence file in a PR.

### Sequencing rationale

WI-1 → WI-2 → WI-3 → WI-4 is a strict dependency chain:
- WI-2's `startTTS()` / `startAZW3TTS` branch calls WI-1's `extractPlainText()` (which needs WI-1's JS helper + Swift channel + populated box).
- WI-3's capability flip is only safe *after* WI-2 makes the speaker button actually work — flipping the capability before the path works would re-introduce the #176 silent failure for any user who taps the button.
- WI-4 verifies the assembled feature.

Each WI leaves the build green and the app shippable: after WI-1 nothing changed for users (button still hidden; new JS is dormant unless called via DEBUG eval); after WI-2 the debug route works (including a verified rapid-repeat path) but the button is still hidden; after WI-3 the feature is functionally complete; WI-4 records the acceptance evidence. The capability gate is *never* open while the path is broken. **And — the v2-critical point — the real extraction seam, including the Promise-marshalling feasibility item, is proven on device in WI-1 before any downstream WI is approved**, so a broken-premise WI cannot merge ahead of the feasibility proof.

---

## 6. Test catalogue

### 6.1 New test file: `vreaderTests/Views/Reader/FoliateSpikeViewTTSTests.swift` (WI-1)

| Test | Covers |
| --- | --- |
| `extractPlainText_returnsNil_whenBookNotReady` | Guard: `isBookReady == false` → `nil` (no extraction before `layout-ready`). |
| `extractPlainText_returnsNil_whenWebViewDeallocated` | Guard: `weak webView == nil` → `nil` (teardown safety). |
| `extractPlainText_evaluatesExactHelperScript` | The evaluated JS literal is exactly `readerAPI.extractPlainText()` — no interpolation, no injection surface. |
| `extractPlainText_coercesNonStringToNil` | `evaluateJavaScript` yielding `NSNull` / a non-String value → `as? String` → `nil` (defensive engine-error path). A *non-resolving* Promise is NOT this case — the `as?` cast is never reached when the await never completes; that hang is bounded by WI-2's extraction timeout, tested separately below. |
| `foliateCoordinatorBox_holdsCoordinatorWeakly` | Box does not retain the Coordinator (release coordinator → box's `coordinator` is `nil`). No retain cycle. |
| `foliateCoordinatorBox_defaultsToNilCoordinator` | Fresh box has `nil` coordinator (so a `startTTS()` before render is a clean no-op). |

**Not unit-tested here (by design):** "real `extractPlainText` output against a rendered AZW3/MOBI book" and "the returned `Promise<string>` resolves to that text in Swift." Both need a live WKWebView + Foliate render, which the XCUnit harness cannot do. They are covered by **WI-1's device slice** (the feasibility gate) and re-confirmed in WI-4's acceptance pass. This split is the audit-honest position — do not fake a WKWebView render in a unit test, and do not assert Promise-marshalling without a real engine. (The Coordinator's existing test pattern — `FoliateSpikeViewCreateOverlayTests.swift` — confirms the Coordinator is constructible in the unit harness via its `init(initialLayoutFlow:onBookReady:onError:)`, so the guard-path tests above are achievable; only the *rendered-content* and *Promise-resolution* assertions need a device.)

### 6.2 `startTTS()` / `startAZW3TTS` / `ensureAIReady()` routing + in-flight-gate tests (WI-2)

| Test | Covers |
| --- | --- |
| `ttsTextSource_azw3_usesFoliateExtraction` | AZW3/MOBI routes to the Foliate-webview source (the pure helper). |
| `ttsTextSource_txtMdPdfEpub_usesFileLoad` | The other four formats still route to `loadBookTextContent` / `contentCache` (regression guard). |
| `startTTS_azw3_nilCoordinator_isNoOp` | Box never populated → no crash, `ttsService.state` stays `.idle`. |
| `startTTS_azw3_emptyExtraction_isNoOp` | `extractPlainText()` → `""` → `startSpeaking` skipped (`!text.isEmpty` guard). |
| `startAZW3TTS_rapidRepeatDuringExtraction_singleWalk` | **Round-2 Finding 1.** While a first extraction `Task` is in flight, a second `startAZW3TTS` invocation is a no-op — it does NOT spawn a second `extractPlainText()` walk and does NOT issue a second `startSpeaking`. Asserts that with the in-flight gate set (`azw3ExtractionTask != nil`), the second invocation returns early. |
| `startAZW3TTS_gateClearedAfterWalk_allowsLaterRetry` | **Round-2 Finding 1.** After a walk completes and the gate is cleared (`azw3ExtractionTask = nil`), a *subsequent* tap is not blocked by a stale gate — if the first walk returned empty (`loadedTextContent` still nil) a later tap may extract again; if it returned text the post-cache fast path is taken. Pins that the gate's lifetime is bounded by one in-flight walk or its timeout. |
| `startAZW3TTS_extractionTimeout_clearsGate` | **Round-3 Finding.** When the extraction `Task` never completes (a wedged walk), `awaitExtraction`'s ~12s timeout fires: it returns `nil`, the gate (`azw3ExtractionTask`) is cleared, the extraction `Task` is cancelled, and a *later* `startAZW3TTS` is not blocked. Pins that a hung extraction cannot wedge AZW3 TTS permanently. |
| `startAZW3TTS_postCacheRetap_usesCachedText_noReextraction` | **Round-2 Finding 1.** A re-tap after a completed, non-empty extraction takes the cached-`loadedTextContent` fast path and does NOT call `extractPlainText()` again. (This is v2's existing post-cache idempotency, kept and explicitly tested.) |
| `ensureAIReady_azw3_skipsFileLoad` | AZW3/MOBI does not enter the detached `loadBookTextContent` path (no dead concurrent task). |

To make the in-flight-gate tests achievable: WI-2 should expose the gate's decision as a small, pure-ish seam — the recommended factoring is that `startAZW3TTS`'s gate check is `func shouldStartExtraction(extractionInFlight: Bool, cachedText: String?) -> Bool` (returns `false` when `extractionInFlight` is true, `false` when `cachedText` is non-empty, `true` otherwise) so the three idempotency layers are unit-testable directly without instantiating the SwiftUI `View`. The `extractPlainText()` walk itself is injected (a closure or the `FoliateCoordinatorBox` handle) so a test can supply a slow/awaitable stub and assert the second invocation does not call it. If this factoring genuinely cannot be done cleanly, the rapid-repeat behavior is covered by WI-2's slice verification (the "fire `vreader-debug://tts?action=start` twice" check) — but the plan's preference, and the Gate-4 expectation, is the unit test of `shouldStartExtraction`.

If `startTTS()`'s branch cannot be cleanly factored into a pure helper at all, WI-2's behavior is covered by slice verification (Gate 5) instead — but the plan's preference is the pure function. The Gate-2 auditor should confirm this is achievable; if not, that is an accepted Low finding with the slice-verification rationale.

### 6.3 `vreaderTests/Models/FormatCapabilitiesTests.swift` (WI-3)

| Change | Detail |
| --- | --- |
| **Remove** `azw3_doesNotSupportTTS()` | The bug #176 regression guard (lines 120-134). |
| **Add** `azw3_supportsTTS()` | `#expect(FormatCapabilities.capabilities(for: .azw3).contains(.tts))`; doc comment cites feature #57. |
| **Re-confirm green** `only_md_epub_azw3_supportUnifiedReflow_simpleEPUB`, `only_md_supportsAutoPageTurn`, `azw3_doesNotSupportAutoPageTurn`, `pdf_supportsSelection_..._notTTS_...`, `capabilities_pdfAlwaysNative...`, `hashableConformance` | None assert `.tts` for `.azw3` (verified by reading the file — §3.1). No edit; the WI runs the full suite to prove it. |

### 6.4 Audit-driven edge cases (per rule 47 — corruption / partial failure / idempotency)

- **Book not yet rendered when `startTTS()` fires** — `extractPlainText()` returns `nil` (guarded on `isBookReady`); `startTTS()` no-ops. (Covered: 6.1 + 6.2.)
- **WKWebView torn down mid-extraction** (user dismisses reader during the `await`) — `weak webView` is `nil` → `nil` result → no-op. (Covered: 6.1.)
- **Empty / whitespace-only extraction** (image-only or malformed AZW3, or a book whose sections all fail `createDocument()`) — the JS helper returns `''` (its no-sections / all-failed path joins an empty array); `startSpeaking`'s existing `!text.isEmpty` guard keeps state `.idle`. (Covered: 6.1, 6.2.)
- **One section fails `createDocument()` mid-walk** — the JS helper's per-section `try/catch` skips it and continues; partial text is returned (better than no TTS). This is a JS-side behavior; the slice verification (WI-1) should, if a fixture with a malformed section is available, confirm partial extraction; otherwise it is a documented JS contract.
- **`evaluateJavaScript` returns a non-String / a non-resolving Promise** (JS error, `NSNull`) — `extractPlainText()` coerces via `as? String` → `nil`. (Covered: 6.1's `extractPlainText_coercesNonStringToNil`. Whether a *resolving* Promise marshals to its value is a WI-1 device-slice item — §5, §4.1.)
- **Idempotency layer 1 — re-tap while TTS is already speaking** — second `startTTS()` while speaking hits the existing `if ttsService.state != .idle { ttsService.stop(); return }` early-return. (Covered: this is `startTTS()`'s own guard.)
- **Idempotency layer 2 — rapid re-tap WHILE the first AZW3 extraction walk is in flight (round-2 Finding 1, the gap v2 missed)** — during the first `extractPlainText()` whole-book section walk, `ttsService.state` is still `.idle` and `loadedTextContent` is still `nil`, so layers 1 and 3 do NOT catch a second tap. v3's **in-flight extraction gate** does: `startAZW3TTS` checks `azw3ExtractionTask != nil` and returns early, so a second tap during the walk does not spawn a duplicate `extractPlainText()` walk and does not issue a second `startSpeaking`. The whole-book section walk "may take noticeable time" (§7 risk row 2), so this window is real; AGENTS.md requires rapid repeated actions to be handled. (Covered: 6.2's `startAZW3TTS_rapidRepeatDuringExtraction_singleWalk` and `startAZW3TTS_gateClearedAfterWalk_allowsLaterRetry`; slice-verified by WI-2's "fire `vreader-debug://tts?action=start` twice in quick succession" check and WI-4's acceptance pass.)
- **Idempotency layer 3 — re-tap after a completed extraction** — the AZW3 branch's post-cache fast path (`if let text = ai.loadedTextContent, !text.isEmpty` at the top of `startAZW3TTS`) means a re-tap after a first successful extraction does NOT re-`evaluateJavaScript` — `loadedTextContent` is cached after the first walk, and `startSpeaking` is called from the cached text. (Covered: 6.2's `startAZW3TTS_postCacheRetap_usesCachedText_noReextraction`; replicates `loadBookTextContent`'s own `guard loadedTextContent == nil` shape — `ReaderAICoordinator.swift:101`.)
- **Stop during extraction** — if the user stops TTS (control bar) while the first walk is in flight, the deferred `startSpeaking` is guarded by a `ttsService.state == .idle` re-check after the `await` (§3.1a) — a stop is not overridden by a late `startSpeaking`. (Covered: behavioral; slice-verified in WI-4.)
- **`ensureAIReady()` does not double-load for AZW3** — the new AZW3 gate makes `ensureAIReady`'s detached task a no-op for AZW3; `startTTS()`'s AZW3 branch is the sole text loader. No race, no double-assignment. (Covered: 6.2's `ensureAIReady_azw3_skipsFileLoad`.)
- **Surrogate-pair / CJK offsets** — `TTSService.startSpeaking` already aligns UTF-16 offsets forward off a surrogate boundary; AZW3 text flows through the *same* method, so CJK AZW3 books inherit that safety with no new code. (No new test — `TTSServiceTests` already covers it; cite, don't duplicate.)
- **`fromOffset` for AZW3** — `startTTS()` reads `ai.currentLocator?.charOffsetUTF16`. For AZW3, `Locator` is CFI-based (`docs/architecture.md:175` — "href+progression+CFI (EPUB/AZW3)"), so `charOffsetUTF16` is `nil` → offset `0`. **Accepted limitation:** AZW3 TTS starts from the *book's* beginning, not the on-screen position. This matches EPUB (EPUB's `currentLocator` is also CFI-based; `charOffsetUTF16` is nil → EPUB TTS also starts at 0). Documented in §10. Not a regression. Note that because `extractPlainText` walks `book.sections` in spine order, offset 0 = start of section 0 = book start, which is consistent.

---

## 7. Risks + mitigations

| Risk | Likelihood | Mitigation |
| --- | --- | --- |
| **`readerAPI.extractPlainText()` does not return correct whole-book text** — a section's `createDocument()` returns an unexpected shape, MOBI/KF8 diverges from AZW3, or the `Promise` does not marshal across `evaluateJavaScript`. | Medium — **this is the central technical risk** (v2 moved it here from v1's misdiagnosed `innerText` risk). | **WI-1 is a feasibility slice** (§5): the helper is exercised against real AZW3 *and* MOBI fixtures on iPhone 17 Pro Sim via `vreader-debug://eval`, and the WI-1 PR description records the observed length + head/tail excerpt + per-format result + **explicit confirmation that the returned `Promise<string>` resolves to that text in Swift** *before WI-2 is approved*. The seam is `view.book.sections[].createDocument()` — already proven in-bundle by `view.search()`'s `#searchBook` (`view.js:528-539`) for both formats (`epub.js:990`, `mobi.js:718`/`:1023`) — so the *mechanism* is known-good; WI-1 verifies the *output* and the *Promise marshalling* (the latter is a feasibility item, not pre-proven — §4.1, round-2 Finding 3). If the slice fails: stop and escalate to the user with two named fallbacks (deliberately-scoped current-section TTS via `getContents()[0].doc`; or message-posting instead of a returned Promise — the latter is the fallback specifically for a non-marshalling Promise). v2 does not pre-commit a fallback. |
| **Whole-book extraction is slow for a large AZW3** — `createDocument()` per section, summed, on first speaker tap. The walk "may take noticeable time." | Low–Medium | Extraction runs on first tap (deferred — §4.2), not on open, so it is never on the open hot path. `createDocument()` is the same per-section parse `view.search()` already does book-wide for search with acceptable UX. **Because the walk is not instant, rapid repeated taps during it are a real edge case — handled by v3's in-flight extraction gate (next risk row).** If WI-1's slice shows a multi-second stall on a large fixture, the mitigation is a brief "preparing" state — but per Rule 51 that would be a *new visible UI state* and must be `needs-design`, not improvised; v2 flags it as a contingency, not a planned surface. The simpler mitigation, if needed, is to extract the first section synchronously and the rest lazily — but that is a current-section-first scope and would also be escalated. **WI-1's slice must record extraction wall-time** so this is decided on data. |
| **Rapid repeated speaker taps before the first extraction completes spawn duplicate `extractPlainText()` walks and restart speech** (round-2 Finding 1 — the gap v2's idempotency story missed). | Medium — the whole-book walk takes noticeable time (row above), so the in-flight window is genuinely tappable; AGENTS.md requires rapid repeated actions to be handled. | **v3 adds an explicit in-flight extraction gate** — `@State private var azw3ExtractionTask: Task<String?, Never>?` on `ReaderContainerView`. The first AZW3 tap stores its extraction `Task`; a second tap before that task completes sees `azw3ExtractionTask != nil` and returns early — no second whole-book walk, no second `startSpeaking`. The gate is cleared when the walk's value is awaited; a late `startSpeaking` is additionally guarded by a `ttsService.state == .idle` re-check (so a stop-during-extraction is not overridden). Three-layer idempotency: playing (`ttsService.state` guard) / in-flight (`azw3ExtractionTask` gate) / post-cache (`loadedTextContent` fast path) — §3.1a, §6.4. Unit-tested via `startAZW3TTS_rapidRepeatDuringExtraction_singleWalk` (§6.2); slice-verified by WI-2's twice-fire check and WI-4's acceptance pass. |
| **The bundle rebuild (`build-bundle.sh`) produces a broken `foliate-bundle.js`** — esbuild bundle error, temp-stub leftover, a stale cache, etc. | Low | `build-bundle.sh` is a deterministic `npx esbuild --bundle` build (it writes three temp stub files, runs esbuild, then `rm -f`s the stubs — §3.3); the `foliate-host.js` edit is one additive `readerAPI` method. WI-1's device slice opens a real book through the rebuilt bundle — a broken bundle fails *that* slice loudly (book doesn't render, or `error` message handler fires). The rebuild + a live-render check are both inside WI-1. |
| **`#42` also edits `foliate-host.js` → merge conflict.** | Low | `extractPlainText` is an additive method on the `readerAPI` object literal; it re-applies cleanly onto any `foliate-host.js` #42 produces. #42's Gate 3 is BLOCKED on human ratification and is not expected to land first. §3.4 records the merge-order coordination. Not a dependency. |
| **`isBookReady` flips but a section still fails to parse** — `layout-ready` fires after `init`, but `extractPlainText` calls `createDocument()` on *all* sections, including ones never paginated. | Low | `createDocument()` parses off-screen and does not depend on pagination state; the per-section `try/catch` in the helper skips a failed section and continues. Empty overall result → no-op (safe). |
| **Concurrency: WKWebView touched off the main actor.** | Low | Mitigated by design — `extractPlainText()` is `@MainActor`; `startTTS()` and `startAZW3TTS` are **explicitly annotated `@MainActor` in v2/v3** (v1 wrongly claimed `startTTS()` already was); the AZW3 branch's `Task { @MainActor in … }` (both the extraction task and the await-and-speak task) stay on the main actor; the branch never crosses into `loadBookTextContent`'s `Task.detached`. `FoliateCoordinatorBox` is `@MainActor`. The `azw3ExtractionTask` `@State` is read/written only from `@MainActor` `startAZW3TTS` code. Only `String?` crosses the `await` — `Sendable`. The `ensureAIReady` AZW3 gate removes the one *other* concurrent path (the dead detached `loadBookTextContent` task). The Gate-4 auditor confirms no actor hop is missing. |
| **`FoliateCoordinatorBox` retain cycle** (box → coordinator → webview → … → box). | Low | Box holds the coordinator `weak`. `FoliateSpikeView.Coordinator` does not reference the box. Tested in 6.1. |
| **`azw3ExtractionTask` `@State` outlives the reader or leaks the `Task`** | Low | The `Task` is a `Task<String?, Never>` capturing the `FoliateCoordinatorBox` handle (which holds the coordinator weakly) and `ai`; it completes when `extractPlainText()`'s `await` returns (the JS walk is finite). The gate is cleared (`azw3ExtractionTask = nil`) on completion. `@State` lifetime is the reader view's lifetime; on reader dismiss the `@State` is released and any in-flight `Task` finishes against a now-`weak`-nil webview → `nil` → harmless. No cancellation handling is required because the task always completes quickly and its result is state-gated; Gate-4 confirms no orphaned-task warning. |
| **Speaker button re-appears (WI-3) before WI-2's path is verified**, re-creating the #176 silent failure. | Low | Strict WI ordering (§5): WI-3 ships *after* WI-2 is slice-verified; the capability gate is never open while the path is unproven. |
| **MOBI vs AZW3 divergence** — `BookFormat.azw3` covers `azw3/azw/mobi/prc` (`BookFormat.swift:33`); `mobi.js` has *two* `createDocument` paths (MOBI line 718, KF8 line 1023). | Low–Medium | The `extractPlainText` walk is format-agnostic at the JS level (it iterates `book.sections[].createDocument()` regardless of which parser built them). **WI-1's feasibility slice explicitly exercises a MOBI fixture in addition to AZW3** — a per-format divergence surfaces there, before WI-2. WI-4's acceptance pass re-exercises both. |
| **Features #40 (sentence highlight) + #41 (auto-scroll) do not render in the Foliate WKWebView.** | High (certain) | **Not a "limitation" — it is unsupported.** `TTSHighlightCoordinator` is instantiated *only* in `TXTReaderContainerView.swift:262` and `MDReaderContainerView.swift:129` (verified) and is documented "TXT/MD only — EPUB/PDF deferred" (`TTSHighlightCoordinator.swift:7-10`). For Foliate it is **never created**, so the #40/#41 pipeline does not run at all. See §7.1 for v2's decisive recommendation. |
| **`startTTS()` is invoked from two entry points** — the `ReaderMorePopover` "Read aloud" row (`handleMoreMenuAction` → `.toggleReadAloud`, `ReaderContainerView+Sheets.swift:268`) and the DEBUG `.debugBridgeTTSCommand` observer. Both must work for AZW3. | Low | Both call the same `startTTS()`; the §3.1 change (including the in-flight gate) is *in* `startTTS()`/`startAZW3TTS`, so one change fixes both — and the rapid-repeat gate protects both entry points equally. Criterion (3) (debug route) and the speaker-button path share the code. |

### 7.1 Features #40 / #41 and acceptance criteria 5 & 6 — DECISIVE recommendation

This is two of the four HIGH Gate-2 findings. v1 was wrong on two counts and lenient on a third; v2 corrects all three and makes a clear, binding recommendation. (The round-2 audit raised **no** new finding here — it confirmed v2's §7.1 recommendation is genuine. §7.1 is retained from v2 unchanged.)

**What v1 got wrong:**
1. v1 §7.1 said the `TTSHighlightCoordinator` "pipeline runs" for Foliate and only its *visual output* is missing. **False.** `TTSHighlightCoordinator` is instantiated *only* in `TXTReaderContainerView.swift:262` and `MDReaderContainerView.swift:129` (verified by repo-wide search). It is documented "TXT/MD only — EPUB/PDF deferred" (`TTSHighlightCoordinator.swift:7-10`). `FoliateSpikeView` never constructs it. For Foliate the #40/#41 pipeline is **not wired at all** — not "visually limited," not "runs but doesn't paint." It does not run.
2. v1 read criteria 5/6 as satisfiable by "pipeline consistency + a documented limitation." That is too lenient: in this repo the feature row's acceptance criteria are the binding source of truth, and the row is unchanged. Criterion 5 says "Sentence highlighting … **renders**"; criterion 6 says "Auto-scroll … **works**." The verbs are binding.

**What is actually true (grounded in code):**
- `TTSHighlightCoordinator` maps a TTS offset → sentence range → writes `TextReaderUIState.highlightRange` / `.scrollToOffset` (`TTSHighlightCoordinator.swift:54-67`). `TextReaderUIState` is consumed by **TextKit** views (`HighlightableTextView`, `TXTTextViewBridge`).
- `FoliateSpikeView` renders in a **WKWebView**, not TextKit. There is no Foliate consumer of `TextReaderUIState`. To make a highlight band / auto-scroll *render* inside the AZW3 WKWebView would require a brand-new Foliate JS-overlay bridge (paint a `<span>`/SVG highlight via the `Overlayer.highlight` API at `overlayer.js:126` + a scroll-to-anchor `evaluateJavaScript`), with TTS-offset → CFI/range mapping. That is a distinct piece of work, not a line-item of #57.
- Feature #41's own VERIFIED row text already states "EPUB/AZW3/PDF intentionally out of scope (different scroll surfaces)." Feature #40's verification fixture was TXT-only. So #41 *already declares AZW3 out of scope*, and #40 was never verified for AZW3.

**v2's decisive recommendation — recommend amending feature #57's row criteria 5 & 6 BEFORE the `PLANNED` flip.**

Criteria 5 and 6 as written ("renders" / "works") bind #57 to make the highlight band and auto-scroll *visibly render inside the Foliate WKWebView*. Doing that is a separate feature (a Foliate TTS-highlight overlay — §10). #57 is a *TTS-audio* feature. v2 therefore recommends, decisively:

> **Amend feature #57's row, at the `PLANNED` flip, to carve the Foliate visual highlight/scroll out of criteria 5 & 6.** Concretely: rewrite criterion 5 to "Visual sentence-highlight inside the Foliate WKWebView is **explicitly out of scope** for #57 — `TTSHighlightCoordinator` is TXT/MD-only and not wired for Foliate; a Foliate TTS-highlight overlay is a tracked follow-up feature" and criterion 6 likewise for auto-scroll. The amended row Notes must state plainly that #57 delivers **TTS audio + pause/resume/stop** for AZW3/MOBI, and that visual highlight/scroll on Foliate is deferred.

This is the honest scope and it keeps #57 a tractable Medium feature. The amendment is a tracker edit the user/author makes when flipping `TODO` → `PLANNED` (the `PLANNED` flip is when the GH issue is also created — §0). **This plan does not flip the row or amend it itself** (read-only planning task); it *recommends* the amendment as a precondition of the `PLANNED` flip.

**The alternative, if the user rejects the amendment:** then criteria 5 & 6 stay binding as written, #57 must render visual highlight/scroll inside the AZW3 WKWebView, that requires a new visible Foliate overlay surface, and per Rule 51 (which explicitly covers "AZW3/Foliate-js … WKWebView injection … when it changes visible chrome" — `51-no-self-designed-ui.md:16`) **#57 must escalate `needs-design` before Gate 3** — a `Design needed: Foliate TTS sentence-highlight overlay for feature #57` issue, labels `enhancement` + `needs-design`. The highlight overlay then becomes part of #57's scope (a 5th/6th WI) and waits on a design bundle.

**v2's position is the amendment, not the escalation** — because visual TTS highlight on Foliate is genuinely a separate feature, EPUB and PDF are *already* in exactly this state (no Foliate/web TTS highlight), and #41's own row already says AZW3 is out of scope. Carving criteria 5/6 aligns #57's row with reality. But the call belongs to the user at the `PLANNED` flip; v2 makes the recommendation explicit and unambiguous so the Gate-2 re-audit has a decision to check rather than a hedge.

§9 reflects this: criteria 5 & 6 are listed as **"recommend amend / out of scope (see §7.1)"**, not as "met to the degree path (a) allows."

---

## 8. Backward compat

- **No persistence / SwiftData change.** `FormatCapabilities` is a computed `OptionSet`, not stored. No migration. No `@Model` touched. No backup-format impact.
- **No `Locator` change.** AZW3 `Locator` stays CFI-based; TTS reads `charOffsetUTF16` (nil for AZW3 → offset 0), see §6.4. Older books, older backups, older clients: unaffected — capability sets are recomputed per launch from `BookFormat`.
- **The speaker button reappears for AZW3/MOBI.** Before #176 it was visible (silently broken); #176 hid it; #57 brings it back *working* (for TTS audio). A user who imported AZW3 books under any prior version simply sees a working speaker button on reopen. No data, no settings, no per-book override is affected. `PerBookSettings` has no TTS field.
- **`foliate-bundle.js` is regenerated.** The bundle is a build artifact embedded at runtime from `Bundle.main`; regenerating it (via the `npx esbuild --bundle` `build-bundle.sh` — §3.3) changes only what JS runs in the AZW3/MOBI WKWebView. No persisted state, no on-disk book file, no backup is touched. Older books re-render under the new bundle exactly as before, plus the dormant `extractPlainText` helper.
- **`FoliateTTSAdapter` stays in the binary, unwired.** No symbol removed; nothing that imported it (only its tests) breaks.
- **DebugBridge contract unchanged.** `vreader-debug://tts?action=start|stop` already accepts AZW3; #57 makes it functional. No URL grammar change, no `DebugCommand` enum change, no `DebugSnapshot` schema change (`ttsState`/`ttsOffsetUTF16` already exist).
- **`ensureAIReady()` AZW3 gate** — for AZW3 this changes a detached task that *already did nothing* (`loadBookTextContent` returned nil for AZW3 pre-#57) into a no-op. No behavior change for users: AZW3 AI-context text was already nil and stays nil. Not a regression — it stops a wasted task. (AZW3 AI-context text is a separate, pre-existing gap — §10.)
- **`azw3ExtractionTask` `@State`** — new in v3; a per-reader in-memory `@State`, not persisted, not exposed. Adds no migration, no schema, no user-visible surface. It only changes internal sequencing (prevents duplicate extraction walks on rapid taps); a user sees a single read-aloud start instead of a possible double-start, which is the intended improvement.
- **Rule 51 — no new visible UI in #57's chosen scope.** Confirmed by file inspection: the only "UI" change is `FormatCapabilities` re-adding `.tts`, which *un-hides an already-existing control* (the `ReaderMorePopover` "Read aloud" row — un-hiding a designed control is explicitly *not* covered by Rule 51, per `51-no-self-designed-ui.md:50`). `TTSControlBar` already renders for any non-idle TTS state, format-agnostic. The `azw3ExtractionTask` in-flight gate is pure sequencing logic — **no visible surface**. No new button, sheet, popover, or chrome. **The one Rule-51 exposure is the visual highlight/scroll of criteria 5/6** — v2's recommendation scopes it OUT (§7.1); if the user rejects that, it becomes a `needs-design` escalation (§7.1). A multi-second extraction "preparing" state (§7 risk row 2) would *also* be a Rule-51 surface — flagged as a contingency, not a planned surface.

---

## 9. Acceptance criteria → verification mapping

Verbatim criteria from the feature #57 row (`docs/features.md:114`), mapped to how each is met and verified. Final pass recorded in `dev-docs/verification/feature-57-<YYYYMMDD>.md` (WI-4).

| # | Criterion (verbatim from row) | v2/v3 disposition | WI | Verification |
| --- | --- | --- | --- | --- |
| 1 | `.tts` re-added to `FormatCapabilities.capabilities(for: .azw3)`; speaker button visible in AZW3/MOBI reader chrome again. | **Met.** | WI-3 | Unit: `azw3_supportsTTS()`. Device: open AZW3, open More-menu, "Read aloud" row present. |
| 2 | Tapping speaker → TTS starts speaking the AZW3 text; `vreader-debug://snapshot` reports `ttsState: "speaking"` and `ttsOffsetUTF16` advances. | **Met** (via the `extractPlainText` whole-book seam — proven in WI-1, exercised end-to-end in WI-4). | WI-1 (seam) + WI-2 (source) + WI-3 (button) | Device on iPhone 17 Pro Sim, AZW3 + MOBI fixtures: tap speaker, snapshot at t+2s → `ttsState: "speaking"`, `ttsOffsetUTF16` advances between two snapshots. **Rapid-repeat sub-check (round-2 Finding 1):** tap speaker twice in quick succession on a large fixture → exactly one speech session starts, `ttsOffsetUTF16` advances monotonically with no restart-to-0. |
| 3 | `vreader-debug://tts?action=start` works for AZW3. | **Met.** The debug observer calls the shared `startTTS()`; no DebugBridge edit needed. | WI-2 | Device: fire the URL after opening an AZW3 book; snapshot confirms `speaking`. Twice-fire confirms single start (the in-flight gate). |
| 4 | Pause/Resume/Stop cycle exercised end-to-end on iPhone 17 Pro Sim. | **Met.** Reuses the format-agnostic `TTSControlBar` + `TTSService` — no #57 code. | WI-4 | Device: start → pause (`paused`) → resume (`speaking`) → stop (`idle`, control bar gone). Stop-during-extraction sub-check: tap stop while the first walk is in flight → no late `startSpeaking`. |
| 5 | Sentence highlighting (if path a) OR Foliate's word-mark highlight (if path b) renders. | **RECOMMEND AMEND / OUT OF SCOPE — see §7.1.** `TTSHighlightCoordinator` is TXT/MD-only (`TTSHighlightCoordinator.swift:7-10`) and **not wired for Foliate at all**. v2 recommends amending this criterion at the `PLANNED` flip to carve out the Foliate visual highlight. If the user rejects the amendment, it becomes a `needs-design` escalation before Gate 3 (Rule 51). | — | n/a under v2's recommended scope; a Foliate TTS-highlight overlay is a tracked follow-up (§10). |
| 6 | Auto-scroll (if path a) OR Foliate's own scroll-on-mark (if path b) works. | **RECOMMEND AMEND / OUT OF SCOPE — see §7.1.** Same as criterion 5. Feature #41's own row already declares "EPUB/AZW3/PDF intentionally out of scope." | — | n/a under v2's recommended scope. |
| 7 | Removed regression-guard `azw3_doesNotSupportTTS()`; replaced with positive `azw3_supportsTTS()` assertion. | **Met.** | WI-3 | Unit: `FormatCapabilitiesTests.swift` diff — `azw3_doesNotSupportTTS()` removed, `azw3_supportsTTS()` added; full suite green. |

Criteria 1–4 and 7 are fully met by this plan. **Criteria 5 & 6 are the substantive open item: v2's clear recommendation is to amend feature #57's row to scope the Foliate visual highlight/scroll OUT before the `PLANNED` flip** (§7.1). The Gate-2 re-audit and the user should treat that recommendation as the decision point — accept the amendment (v2's recommendation), or reject it and accept the `needs-design` escalation it triggers. The `PLANNED` flip should not happen until this is decided, because the row's criteria are the binding contract and v2 will not ship under criteria it knows the chosen scope cannot meet.

---

## 10. Known limitations / deferred (out of scope for #57)

- **Visual sentence-highlight band + auto-scroll inside the AZW3/MOBI WKWebView** — out of scope per v2's §7.1 recommendation. `TTSHighlightCoordinator` is TXT/MD-only and not wired for Foliate. A Foliate TTS-highlight overlay (paint via `Overlayer.highlight` + scroll-to-anchor, with TTS-offset → range mapping) is a distinct follow-up feature. If the user rejects the §7.1 row amendment, this becomes a `needs-design`-gated part of #57 instead (§7.1).
- **TTS starting from the on-screen position for AZW3** — deferred. AZW3 `Locator` is CFI-based (`docs/architecture.md:175`); there is no CFI→UTF-16-offset mapping, so TTS starts at the book's beginning (same as EPUB today). A CFI-anchored TTS start is a separate feature.
- **AZW3/MOBI AI-context text** (`chatViewModel.bookContext`) — pre-existing gap, not introduced by #57. `loadBookTextContent` already returned nil for AZW3 before #57; v2's `ensureAIReady` gate stops the dead detached task but does not fill the gap. Wiring AZW3 AI-context via the same `extractPlainText` helper is a clean follow-up. Out of scope for #57 (a TTS feature).
- **Foliate in-webview SSML TTS (`view.tts` / `tts-ssml`) + a `FoliateTTSAdapter` rewrite to the real `tts-ssml` contract** — deferred; this is path (b), rejected for #57 (§2.1). `FoliateTTSAdapter` stays in the tree unwired for a possible future Foliate-highlight feature.
- **Current-section-only extraction as the shipped behavior** — NOT the chosen scope. v2's primary is whole-book extraction via `book.sections[].createDocument()`. Current-section extraction (`getContents()[0].doc`) is named only as a WI-1 *fallback* if the feasibility slice fails (§5, §7 risk row 1) — and adopting it would itself be a user-escalated scope change.
- **AZW3 TTS in unified reading mode** — deferred; unified mode for AZW3 is `UnifiedPlaceholderView` (`docs/architecture.md:53`) with no reader surface.
- **Large-book extraction performance UI** — if WI-1's slice shows a multi-second extraction stall, a "preparing" state would be needed; that is a Rule-51 visible surface and would require `needs-design`, not improvisation (§7 risk row 2). Flagged as a contingency. (Note: the *correctness* of rapid taps during a slow walk is already handled by v3's in-flight extraction gate (§3.1a) — the "preparing" state is purely a UX-feedback question, not a correctness one.)
- **`Task` cancellation of an in-flight `extractPlainText()` walk on reader dismiss** — v3 does not cancel the `azw3ExtractionTask` on dismiss; the walk completes against a now-`weak`-nil webview (→ `nil` → harmless) and the result is state-gated. Explicit cancellation is a possible micro-optimization but not required for correctness; out of scope.

---

## 11. Files touched — summary

**Modified (6):**
- `vreader/Services/Foliate/JS/foliate-host.js` — add `readerAPI.extractPlainText()` (NEW in v2 — the CRITICAL finding forces a JS edit; v1 wrongly claimed no JS change).
- `vreader/Services/Foliate/JS/foliate-bundle.js` — regenerated via `build-bundle.sh` (an `npx esbuild --bundle` build, esbuild-generated output — not hand-edited; round-2 Finding 2 corrected v2's "concatenation" wording).
- `vreader/Models/FormatCapabilities.swift` — `.tts` re-added to `case .azw3` + doc comment.
- `vreader/Views/Reader/FoliateSpikeView.swift` — `extractPlainText()` Coordinator method + `coordinatorBox:` binding.
- `vreader/Views/Reader/ReaderContainerView.swift` — `@State foliateCoordinatorBox`; **`@State azw3ExtractionTask` (v3 — the in-flight extraction gate, round-2 Finding 1)**; pass the box into `FoliateSpikeView`.
- `vreader/Views/Reader/ReaderContainerView+Sheets.swift` — `startTTS()` AZW3 branch via the `startAZW3TTS(ai:)` helper + explicit `@MainActor`; **the in-flight extraction gate logic in `startAZW3TTS` (v3, round-2 Finding 1)**; `ensureAIReady()` AZW3 gate.

**New (2):** `vreader/Views/Reader/FoliateCoordinatorBox.swift` (or nested in `FoliateSpikeView.swift`); `vreaderTests/Views/Reader/FoliateSpikeViewTTSTests.swift`.

**Test modified (1):** `vreaderTests/Models/FormatCapabilitiesTests.swift`.

**Explicitly untouched:** the unwired `FoliateViewBridge`/`FoliateViewCoordinator`/`FoliateReaderContainerView`/`FoliateReaderHost`/`FoliateReaderViewModel` stack; all of `Services/Foliate/JS/*` **except** `foliate-host.js` + the regenerated `foliate-bundle.js` (`view.js`, `paginator.js`, `tts.js`, `mobi.js`, `epub.js`, `JS/vendor/*`, `build-bundle.sh` — not edited); `FoliateTTSAdapter.swift`; `TTSService.swift`; `TTSHighlightCoordinator.swift`; `TTSControlBar.swift`; all DebugBridge files.

---

## 12. Concurrency contract (explicit — MEDIUM finding)

v1 was vague about isolation and wrongly stated `startTTS()` is already `@MainActor`. v2 states the contract precisely; v3 extends it for the new in-flight extraction gate (round-2 Finding 1).

- **`startTTS()`** — `ReaderContainerView+Sheets.swift:20`, currently carries **no** isolation annotation. v2 **adds explicit `@MainActor`.** It is the TTS entrypoint; it touches `ttsService` (a `@MainActor @Observable`), `resolvedAICoordinator`, and now the `startAZW3TTS` helper. An explicit annotation makes the contract checkable rather than inferred from SwiftUI `View` conformance.
- **`startAZW3TTS(ai:)`** — new in v3; `@MainActor` (it is `private` and called only from the `@MainActor` `startTTS()`; it may inherit or carry the annotation explicitly — explicit is preferred for the same checkability reason). It reads/writes `azw3ExtractionTask`, touches `ttsService`, and `await`s `extractPlainText()`.
- **`azw3ExtractionTask`** — `@State private var azw3ExtractionTask: Task<String?, Never>?` on `ReaderContainerView`. As `@State` on a `@MainActor`-isolated SwiftUI `View`, it is read and written **only** from `@MainActor` contexts (`startAZW3TTS`). The two `Task { @MainActor in … }` blocks inside `startAZW3TTS` (the extraction task and the await-and-speak task) both run on the main actor, so the store-then-clear of `azw3ExtractionTask` is serialized — no data race. The `Task` itself is `Task<String?, Never>`: `Never` failure type because `extractPlainText()` is non-throwing, so `await task.value` needs no `try`. Only a `String?` crosses the task's result boundary — `Sendable`.
- **`extractPlainText()`** on `FoliateSpikeView.Coordinator` — `@MainActor`. It calls `WKWebView.evaluateJavaScript`, which requires the main actor. The `Coordinator` is used on the main actor in practice (its `handleMessage` is `@MainActor`; its notification observers hop via `MainActor.assumeIsolated` — `FoliateSpikeView.swift:298/314`), but its `webView` property is not statically isolated, so `extractPlainText()` carries its own `@MainActor` and is the single, explicit main-actor entry for the production text touch.
- **`FoliateCoordinatorBox`** — `@MainActor`; holds `weak var coordinator`.
- **The AZW3 branch's `Task { @MainActor in … }`** — stays on the main actor end-to-end. Only `String?` crosses the `await` boundary (`Sendable`). The branch never enters `loadBookTextContent`'s `Task.detached` (`ReaderAICoordinator.swift:103`) — the WKWebView reference never reaches a non-main executor.
- **The late-`startSpeaking` re-check** — after `await task.value` returns, `startAZW3TTS` re-checks `ttsService.state == .idle` (and `ai.loadedTextContent == nil`) before calling `startSpeaking`. Because everything runs on the main actor, this re-check sees the true current state — a stop issued during the walk is observed and the late `startSpeaking` is suppressed.
- **`ensureAIReady()`'s AZW3 gate** — removes the one *other* concurrent path for AZW3 (the dead detached `loadBookTextContent` task), so there is exactly one text loader for AZW3: `startTTS()` → `startAZW3TTS`. No race, no double-assignment to `loadedTextContent`. Combined with the `azw3ExtractionTask` gate, there is also at most one *in-flight* extraction walk at any time.
- **Gate-4 must confirm**: no missing actor hop; no `Sendable` violation across the `extractPlainText()` `await` or the `azw3ExtractionTask` result boundary; the `@MainActor` annotation on `startTTS()`/`startAZW3TTS` does not break either caller (`handleMoreMenuAction` and the `.debugBridgeTTSCommand` observer — both already main-actor SwiftUI/observer contexts); no orphaned-`Task` warning for `azw3ExtractionTask` (it always completes and is cleared on completion).

---

## 13. Gate-2 audit trail — round-1 findings → v2 resolutions

Gate-2 independent audit: Codex `019e3beb`, verdict **NEEDS-REVISION**. Round 1 of max 3 (rule 47 Gate 2). All findings resolved in v2 below; v2 went back to the auditor for re-review (round 2 — see §14).

| # | Severity | Round-1 finding | v2 resolution |
| --- | --- | --- | --- |
| 1 | **CRITICAL** | Path-(a) premise wrong: `document.body.innerText` on the Foliate host page is shell-only/empty; book content is in iframe `contentDocument`s two closed-shadow-roots deep; even `getContents()[0].doc.body.innerText` is current-section-only. | **Core reworked.** §0 documents the disproof (`view.js:214`, `paginator.js:213/250-252/429/1092-1099`, `foliate-reader.html:25-48`). §2.2 re-bases path (a) on the **real seam**: `view.book.sections[].createDocument()` — the same whole-book walk `view.search()`'s `#searchBook` already uses (`view.js:528-539`; per-format `createDocument` at `epub.js:990`, `mobi.js:718`/`:1023`). §3.1 adds a `readerAPI.extractPlainText()` JS helper to `foliate-host.js` implementing that walk. The whole-book vs current-section choice is decided: **whole-book** primary, current-section only as a WI-1-escalated fallback. |
| 2 | **HIGH** | WI-1 must be a feasibility slice, not pure plumbing — a plumbing-only WI-1 can merge while the seam is still invalid. | §5 WI-1 re-scoped: it now ships the JS helper + bundle rebuild + Swift channel + a **populated** `FoliateCoordinatorBox` (wiring pulled forward from v1's WI-2), and is classed **behavioral with a mandatory device slice** that exercises `extractPlainText()` against real AZW3 *and* MOBI fixtures and records observed length/excerpt/per-format result in the PR. Explicit **decision gate**: WI-2 is not approved until WI-1's slice proves the seam. |
| 3 | **HIGH** | Acceptance-criteria 5/6 reading too lenient; row criteria are binding and unamended; v1 proposed shipping without visible highlight/scroll and calling it "acceptable." | §7.1 rewritten with a **decisive recommendation**: amend feature #57's row criteria 5 & 6 at the `PLANNED` flip to scope the Foliate visual highlight/scroll OUT; if the user rejects the amendment, escalate `needs-design` before Gate 3 (Rule 51). §9 lists 5 & 6 as "recommend amend / out of scope," not "met." The `PLANNED` flip is gated on this decision. |
| 4 | **HIGH** | v1 overstates what path (a) preserves from #40/#41: `TTSHighlightCoordinator` is TXT/MD-only and only instantiated in TXT/MD containers; for Foliate the #40/#41 pipeline is not wired at all, not "visually limited." | §7.1 and §7's risk table corrected: `TTSHighlightCoordinator` instantiated *only* at `TXTReaderContainerView.swift:262` / `MDReaderContainerView.swift:129` (verified); documented "TXT/MD only" (`TTSHighlightCoordinator.swift:7-10`); **not created for Foliate at all.** §3.4 and §9 say criteria 5/6 are *currently unsupported* on Foliate, not "limited." The row is recommended narrowed (§7.1) rather than #57 carrying new Foliate visual-highlight WIs. |
| 5 | **MEDIUM** | Concurrency rationale incomplete — `startTTS()` calls `ensureAIReady()`, which still spawns `loadBookTextContent` for every non-TXT/MD format including AZW3; that detached nil-returning path runs concurrently. | §3.1(b) adds an explicit AZW3/MOBI gate to `ensureAIReady()` so AZW3 never enters the detached `loadBookTextContent` path (it returned nil for AZW3 anyway). §12 documents that this leaves exactly one text loader for AZW3. New test `ensureAIReady_azw3_skipsFileLoad` (§6.2). |
| 6 | **MEDIUM** | v1 cites `startTTS()` as `@MainActor` but the symbol is not annotated (`ReaderContainerView+Sheets.swift:20-49`). | §3.1(a) and §12: v2 **adds an explicit `@MainActor` annotation to `startTTS()`**. §12 is a dedicated concurrency-contract section stating the isolation of `startTTS()`, `extractPlainText()`, `FoliateCoordinatorBox`, and the AZW3 `Task`, and what Gate-4 must confirm. |
| 7 | **LOW** | Path-(b) rejection substantially correct (`parseTTSBlock` expects `tts-text` at `FoliateTTSAdapter.swift:65-76`; host posts `tts-ssml` at `foliate-host.js:212-225`; `view.initTTS()` binds `getContents()[0].doc`) — but ensure v2 doesn't reject one broken alternative for another broken assumption. | §2.1 retains the path-(b) rejection with verified line refs. The "another broken assumption" risk *was* v1's `innerText` premise — finding #1 — now corrected: v2's path (a) rests on the verified-in-bundle `createDocument()` walk, and WI-1's feasibility slice (#2) exists precisely so v2 does not assert an unproven seam. The whole-book vs current-section ambiguity is resolved (whole-book primary), not left open. |

---

## 14. Gate-2 audit trail — round-2 findings → v3 resolutions

Round-2 Gate-2 independent audit. Verdict **NEEDS-REVISION**. Round 2 of max 3 (rule 47 Gate 2). **No Critical and no High findings** — the round-2 auditor explicitly confirmed the v2 core rework is genuine: the `createDocument()` section-walk rework, the WI-1 feasibility-slice scoping, the criteria-5/6 recommendation, the `ensureAIReady()` gate, and the explicit `@MainActor` `startTTS()` fix were all confirmed as real, substantive resolutions (not reworded). v3 resolves the three remaining findings (one MEDIUM, two LOW) below. None of the v2-confirmed elements is regressed — §13's round-1 resolutions stand unchanged, and §7.1 / §5's WI-1 scoping / §3.1b's `ensureAIReady` gate are preserved verbatim except where a round-2 finding explicitly touches them.

| # | Severity | Round-2 finding (verbatim) | Codebase verification | v3 resolution |
| --- | --- | --- | --- | --- |
| 1 | **MEDIUM** | plan:399 — The plan still misses the rapid-repeat edge case. Its "idempotent" story only covers the post-cache state (`loadedTextContent != nil`), but while first extraction is in flight `startTTS()` still sees `ttsService.state == .idle` and `loadedTextContent == nil`, so repeated taps can queue multiple `Task { @MainActor in ... extractPlainText() }` calls and restart speech redundantly. This matters because the whole-book section walk may take noticeable time, and AGENTS.md requires rapid repeated actions to be handled. FIX: Add an explicit in-flight gate for AZW3 extraction — e.g. a stored `Task<String?, Never>?` / boolean on the host or coordinator — make subsequent taps no-op or await the same task, and add a test plus slice note for repeated speaker taps before first extraction completes. | **Confirmed — auditor is right.** Verified against the live `startTTS()` (`ReaderContainerView+Sheets.swift:20-49`): its only re-tap guard is `if ttsService.state != .idle { ttsService.stop(); return }`, which catches a re-tap only once speech is *already playing*. v2's AZW3 branch adds `guard ai.loadedTextContent == nil else { return }` *inside* the `Task`, which catches a re-tap only once the walk has *finished and cached*. Neither covers the in-flight window: during the `await foliateCoordinatorBox.coordinator?.extractPlainText()` whole-book walk, `ttsService.state` is `.idle` and `loadedTextContent` is `nil`, so a second tap passes both guards and spawns a second `Task` re-running the whole `createDocument()` section walk and re-calling `startSpeaking`. v2's own §7 risk row 2 already says the walk "may take noticeable time," so the window is genuinely tappable. | **Resolved with a concrete in-flight gate, not reworded.** §3.1's `ReaderContainerView.swift` entry adds `@State private var azw3ExtractionTask: Task<String?, Never>?`. §3.1a refactors the AZW3 branch into a `startAZW3TTS(ai:)` helper that: (i) takes a post-cache fast path if `loadedTextContent` is non-empty (layer 3, unchanged from v2); (ii) **returns early if `azw3ExtractionTask != nil`** — a rapid second tap during the in-flight walk is a no-op, no duplicate `extractPlainText()` walk, no duplicate `startSpeaking` (layer 2, NEW); (iii) stores the extraction `Task` in `azw3ExtractionTask`, clears it when the walk's value is awaited, and re-checks `ttsService.state == .idle` before a late `startSpeaking`. §6.2 adds three tests (`startAZW3TTS_rapidRepeatDuringExtraction_singleWalk`, `startAZW3TTS_gateClearedAfterWalk_allowsLaterRetry`, `startAZW3TTS_postCacheRetap_usesCachedText_noReextraction`) with a recommended pure-`shouldStartExtraction(extractionInFlight:cachedText:)` factoring. §6.4 documents the three-layer idempotency (playing / in-flight / post-cache) explicitly. §7 adds a dedicated risk row. §12 extends the concurrency contract for `azw3ExtractionTask` and `startAZW3TTS`. §5 WI-2 adds a "fire `vreader-debug://tts?action=start` twice in quick succession" slice check; WI-4's acceptance pass and §9's criterion-2 row add the rapid-repeat sub-check. |
| 2 | **LOW** | plan:323 — The bundle step is described as "concatenates the sources into `foliate-bundle.js`" / "mechanical", but the actual script is an `npx esbuild` build with temporary stub-file writes and cleanup (`vreader/Services/Foliate/JS/build-bundle.sh:2-17`). FIX: Reword the plan to describe the real build step — esbuild-based bundle rebuild with temporary stubs — and keep WI-1's live-render verification as the guard against build breakage. | **Confirmed — auditor is right.** Verified by reading `vreader/Services/Foliate/JS/build-bundle.sh:1-17` in full. The script is *not* a concatenation: it runs `set -euo pipefail`, `cd "$(dirname "$0")"`, then **writes three temporary stub files** (`echo 'export const makeComicBook = …' > comic-book.js`, plus `fb2.js`, `pdf.js`), runs `npx esbuild foliate-host.js --bundle --format=iife --global-name=FoliateHost --outfile=foliate-bundle.js`, then **deletes the stubs** (`rm -f comic-book.js fb2.js pdf.js`) and prints the byte count. v2 §3.3 said "concatenates the sources" and §2.3 said "concatenates the JS … running it is mechanical" — inaccurate. | **Resolved.** §3.3 rewritten to describe the real build step: an `npx esbuild --bundle` build (IIFE format, global name `FoliateHost`) with a four-step breakdown — `set -euo pipefail`/`cd`, write three temporary stub files, run esbuild, delete the stubs and print the byte count — explicitly stating it is an esbuild dependency-graph bundle with temp-stub scaffolding/cleanup, "not a `cat`-style concatenation." §2.3's bullet corrected the same way. §3.1's `foliate-bundle.js` entry, §5 WI-1 step 2, §8's bundle bullet, and §11's file-summary line all reworded from "concatenated"/"mechanical" to "esbuild-generated." WI-1's live-render verification is kept and explicitly re-stated as the guard against an esbuild build breakage (§3.3 last sentence, §7 risk row "The bundle rebuild … produces a broken `foliate-bundle.js`"). |
| 3 | **LOW** | plan:348 — The plan overstates the Promise-marshalling precedent. Current code proves `evaluateJavaScript` runs against the live Foliate web view and that completion handlers fire before an async IIFE finishes, but it does NOT already prove a returned JS `Promise<string>` resolves back to Swift the way the plan states. WI-1 correctly treats this as a feasibility item; §4.1 should not present it as established prior art. FIX: Reword from "proving the channel works" to "same API/channel, with Promise-value marshalling to be validated in WI-1". | **Confirmed — auditor is right.** Verified against the DEBUG `jsEvaluator` AZW3 path (`ReaderContainerView.swift:507-517`): it does `let raw = try await webView.evaluateJavaScript(script)` against the live `FoliateSpikeView` WKWebView, then `JSONSerialization.data(withJSONObject: raw ?? NSNull(), …)`. This proves the channel reaches the live webview and returns *a* value, but the `vreader-debug://eval` scripts are arbitrary and this path never specifically exercises a returned `Promise<string>` being awaited to its resolved value. v2 §4.1's last bullet said the DEBUG path is "proving the channel works" while §3.1 line 140 asserted `evaluateJavaScript` "awaits a returned Promise and delivers its resolved value" as a flat fact — overstated. WI-1 (§5) does correctly list Promise marshalling as a feasibility item, so the §4.1 overstatement was the only inconsistency. | **Resolved.** §4.1's `evaluateJavaScript` bullet rewritten: retitled "**same API/channel, with Promise-value marshalling TO BE VALIDATED IN WI-1**," and split into what the codebase *does* establish (the channel reaches the live `FoliateSpikeView` webview and returns a value; completion handlers fire before an async IIFE finishes) versus what it does **not** establish (that a returned JS `Promise<string>` is awaited and its resolved value delivered to Swift) — explicitly labeling Promise-value resolution a WI-1 feasibility item, not prior art. §3.1's `foliate-host.js` note and `FoliateSpikeView.swift` `evaluateJavaScript` note reworded from asserting Promise resolution to "expected … validated by WI-1's feasibility slice." §2.2 reworded ("`evaluateJavaScript` *is expected to* resolve the returned `Promise`"). §5 WI-1's device-slice checklist and decision gate, and §7 risk row 1, now explicitly call out Promise-marshalling confirmation as a recorded WI-1 output, with message-posting named as the fallback for a non-marshalling Promise. WI-1's live verification is unchanged — it already owned this; v3 only stops §4 from pre-claiming the result. |

**Round-2 verdict path:** v3 resolves all three round-2 findings with concrete design changes (Finding 1: a real `Task<String?,Never>?` in-flight gate + tests + slice checks; Findings 2 & 3: factual corrections of the build-step and Promise-marshalling descriptions). v3 returns to the round-2 auditor for re-review (round 3 would be the last permitted under rule 47 Gate 2's max-3 discipline; v3 expects to clear, since the two LOW findings are pure accuracy fixes and the one MEDIUM is now a concrete, tested gate). No v2-confirmed element is regressed.

---

## Critical Files for Implementation

- `/Users/ll/workspace/vreader/vreader/Services/Foliate/JS/foliate-host.js` — gains `readerAPI.extractPlainText()` (the whole-book section-walk over `view.book.sections[].createDocument()`); the bundle is regenerated from it via the `npx esbuild --bundle` `build-bundle.sh`.
- `/Users/ll/workspace/vreader/vreader/Views/Reader/ReaderContainerView+Sheets.swift` — `startTTS()` gains the AZW3 branch + explicit `@MainActor`; the new `startAZW3TTS(ai:)` helper carries the in-flight extraction gate (round-2 Finding 1); `ensureAIReady()` gains the AZW3/MOBI file-load gate.
- `/Users/ll/workspace/vreader/vreader/Views/Reader/ReaderContainerView.swift` — adds `@State foliateCoordinatorBox`, the new `@State azw3ExtractionTask: Task<String?, Never>?` in-flight gate (round-2 Finding 1), and threads the box into `FoliateSpikeView` in `nativeReaderView`'s `case "azw3"` (line ~679).
- `/Users/ll/workspace/vreader/vreader/Views/Reader/FoliateSpikeView.swift` — gains the `@MainActor extractPlainText() async -> String?` Coordinator method and the `coordinatorBox:` binding; `FoliateCoordinatorBox` may nest here.
- `/Users/ll/workspace/vreader/vreader/Models/FormatCapabilities.swift` — `case .azw3` re-adds `.tts` and rewrites the bug #176 doc comment.
