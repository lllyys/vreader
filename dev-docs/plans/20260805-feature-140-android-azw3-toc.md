# Feature #140 — Android AZW3 Contents (TOC)

- **Tracker row**: `docs/features.md:192` (parity phase 4, box **G1**, priority Medium, status `TODO`)
- **iOS parity**: feature #38 (hierarchical/tree TOC display) on the Foliate path —
  `vreader/Services/Foliate/FoliateTOCConverter.swift` + `vreader/Services/Foliate/FoliateNavSeek.swift`
- **Platform**: `android-app` (rule 40 → bumps `android/version.properties`; rule 47 Gate-5 → emulator lane)
- **Plan status**: **v2 — Gate-2 round 1 applied** (Codex gpt-5.5/high; 1 High, 1 Medium, 3 Low, all
  closed). Awaiting round 2. Round-1 dispositions in §13.
- **Closest precedent**: feature #139 (TXT/MD TOC, `VERIFIED` 2026-08-05) — same sheet, same
  scaffold rule, same Gate-5 shape. Plan: `dev-docs/plans/20260804-feature-139-android-txt-md-toc.md`;
  evidence: `dev-docs/verification/feature-139-20260805.md`.

---

## 1. Problem

An AZW3/MOBI/KF8 book on Android has **no chapter navigation at all**. The Kindle reader host
hardcodes an empty TOC and a dead jump:

- `android/app/src/main/kotlin/com/vreader/app/reader/Azw3ReaderActivity.kt:11-12` —
  "AZW3 has no reader TOC → Contents is hidden (empty tocEntries / EmptyTocProvider posture)"
- `Azw3ReaderActivity.kt:464` — `tocEntries = emptyList(),  // no TOC → the scaffold hides the Contents control`
- `Azw3ReaderActivity.kt:465` — `currentTocIndex = 0`
- `Azw3ReaderActivity.kt:467` — `onJumpToc = { false },  // unreachable: Contents is hidden with an empty TOC`

`ReaderChromeScaffold.kt:143-144` turns that into a hidden control:

```kotlin
val onOpenContents: (() -> Unit)? =
    if (tocEntries.isEmpty()) null else { { openSheet(ReaderSheet.Toc) } }
```

and — the fact that matters most for scoping (§2.1, claim W4) — the AZW3 host **throws the Contents
open callback away** even if a TOC existed:

```kotlin
// Azw3ReaderActivity.kt:473-476
bottomChrome = { _, onOpenNotes ->
    // AZW3 has no Contents (empty TOC) + no Display control → Notes only.
    Azw3NotesBottomChrome(theme = theme, onOpenNotes = onOpenNotes)
},
```

The `_` is the `onOpenContents` parameter. So this feature is **not** "make `tocEntries` non-empty";
it is that *plus* a bottom-chrome change, or the control still will not appear.

The wasteful part: **the book's real TOC already crosses the bridge on every AZW3 open and is
thrown away in Kotlin.**

- `android/app/src/main/assets/foliate/foliate-bundle.js:7169-7177` — `readerAPI.open()` posts
  `book-ready` with `toc: serializeTOC(currentBook.toc ?? [])`.
- `foliate-bundle.js:7659-7666` — `serializeTOC` emits a **recursive tree** of
  `{ label, href, subitems }`.
- `foliate-bundle.js:3489-3497` — for KF8 the tree is built from the Kindle **NCX** with
  `children`, so nesting is native to the format.
- `FoliateMessageParser.kt:30-33` — Kotlin parses **only** `title` and `sections` out of that
  payload. `toc` is discarded.

The same is true of the current-chapter signal:

- `foliate-bundle.js:7038-7051` — every `relocate` posts `tocLabel` and `tocHref` (foliate's own
  `TOCProgress` result for the visible range).
- `FoliateMessageParser.kt:34-39` — Kotlin parses `cfi` / `fraction` / `sectionIndex` /
  `sectionTotal`. `tocHref` is discarded.

### What "done" looks like

Opening an AZW3/MOBI book whose file carries an NCX shows the **Contents** control in the reader's
bottom chrome; tapping it lists the book's real chapters, nested chapters indented under their
parents, the current chapter highlighted; tapping a chapter navigates the reader there. A book with
no usable TOC behaves exactly as today — the control stays hidden.

---

## 2. Wiring claims — every one verified against the live code

Rule 47 Gate 2 makes an unverified wiring claim a **High** finding, and this repo shipped four
Android features `VERIFIED` with UI no user could reach. Every claim below was checked by opening
the file and finding the call site; the citation is `file:line` at the plan's base commit.

| # | Claim | Evidence | Verdict |
| --- | --- | --- | --- |
| W1 | **The AZW3 reader is production-reachable today.** `MainActivity` is the manifest LAUNCHER; its `openBook` routes `BookFormat.azw3` → `Azw3ReaderActivity`. | `android/app/src/main/AndroidManifest.xml:19-23` (`.MainActivity` + `LAUNCHER`); `MainActivity.kt:90-92` `BookFormat.azw3 -> startActivity(Azw3ReaderActivity.intent(...))`; reached from `LibraryScreen(onOpenBook = { book -> openBook(book.originalFormat, book.id) })` at `MainActivity.kt:104` | **TRUE** |
| W2 | **The AZW3 host already renders the shared chrome scaffold.** `Azw3ReaderChrome` calls `ReaderChromeScaffold`. | `Azw3ReaderActivity.kt:166` (call), `:437-489` (definition), `:459` (`ReaderChromeScaffold(`) | **TRUE** |
| W3 | **The Contents control's show/hide rule is `tocEntries.isEmpty()`, and needs no change.** | `ReaderChromeScaffold.kt:143-144` | **TRUE** |
| W4 | **BUT the AZW3 bottom chrome DISCARDS the Contents callback.** A non-empty `tocEntries` alone would light up **no** control. | `Azw3ReaderActivity.kt:473` `bottomChrome = { _, onOpenNotes ->`; `Azw3NotesBottomChrome` (`:499-527`) takes only `onOpenNotes` | **TRUE — and this is why the row's "reuses #132's sheet" is necessary but not sufficient** |
| W5 | **The two-tab Contents\|Bookmarks sheet is already routed from `ReaderSheet.Toc`,** and the AZW3 host already feeds its Bookmarks tab (#135 WI-7). | `ReaderChromeScaffold.kt:213-222`; `Azw3ReaderActivity.kt:176-210` (bookmarks + `onJumpBookmark`) | **TRUE** |
| W6 | **The bundle already sends the whole TOC tree on `book-ready`; Kotlin discards it.** No bundle change is needed to obtain the TOC. | `foliate-bundle.js:7169-7177`, `:7659-7666`; `FoliateMessageParser.kt:30-33` | **TRUE** |
| W7 | **The bundle already sends `tocHref` on every `relocate`; Kotlin discards it.** No bundle change is needed for the current-chapter highlight. | `foliate-bundle.js:7047-7048`; `FoliateMessageParser.kt:34-39` | **TRUE** |
| W8 | **foliate's `view.goTo(target)` accepts an href** (it is the `else` branch of `resolveNavigation`), so the existing `goTo` seam can navigate by TOC href. | `foliate-bundle.js:6860-6868` (`if (isCFI.test(target)) …; return this.book.resolveHref(target)`), `:6874-6884` (`goTo`), `:7205-7207` (`readerAPI.goTo`) | **TRUE** |
| W9 | **BUT neither the Kotlin target type nor the shell shim can express an href today.** | `FoliateBridge.kt:210-214` `FoliateGoToTarget.from` = cfi → progression, no href leg; `android/app/src/main/assets/foliate/reader.html:60-71` `__vreaderGoTo` handles only `target.cfi` / `target.fraction` | **TRUE — WI-3 exists because of this** |
| W10 | **`reader.html` is NOT SHA-pinned; `foliate-bundle.js` IS.** The shim is our code and may be edited; the bundle must not be touched. | `FoliateBundleProvenanceTest.kt:31` pins only the bundle SHA (`c9b0e101…`); no test hashes `reader.html` | **TRUE** |
| W11 | **The Contents sheet already renders `depth` as indentation and already scales.** | `TocSheetRows.kt:100-112` (`padding(start = (entry.depth.coerceIn(0, 4) * 12).dp)`); `TocContentsSheet.kt:161-181` (`LazyColumn` seeded at `currentTocIndex`, keyed on `fingerprintKey` + size) | **TRUE** |
| W12 | **`ReadiumTocProvider` is a directly reusable structural template** for a recursive flatten with depth + skip-but-recurse. | `ReadiumTocProvider.kt:54-71` | **TRUE** |
| W13 | **The synchronous-sheet / asynchronous-goTo problem is already solved for AZW3** by #135's `azw3JumpDecision` (sync, from target validity) + a scoped awaited `goTo`. | `Azw3ReaderActivity.kt:188-210`, `:301-322` | **TRUE — reused verbatim** |
| W14 | **The real AZW3 fixture is local-only and absent from a lane worktree.** | `android/app/src/androidTest/assets/foliate-spike/.gitignore` contains `book.azw3`; the file exists only in the main checkout (`/Users/ll/workspace/vreader/android/app/src/androidTest/assets/foliate-spike/book.azw3`, 6,288,371 B). Existing tests `assumeTrue(...)`-skip without it (`Azw3ReaderActivityTest.kt:43-44`, `Azw3GoToSliceTest.kt:45-46`) | **TRUE — see §9 R7; a lane that forgets to stage it gets a GREEN run that tested nothing** |

### 2.1 The blunt statement Gate 2 asked for

**Today the AZW3 reader has NO Contents entry point, production or otherwise** — not a hidden one,
not a debug one. `Azw3ReaderChrome` passes `tocEntries = emptyList()` (`:464`) *and* drops the
Contents callback (`:473`). After this feature, the entry point is the **production** bottom-chrome
"Contents" button, on the path `app launch → MainActivity (LAUNCHER) → Library grid → tap an AZW3
tile → Azw3ReaderActivity → bottom chrome → Contents`. Every file on that path lives in
`android/app/src/main` (W1, W2). `android/app/src/debug` contains only `AndroidManifest.xml`, a
`res/` tree, `BackupDebugActivity.kt` and `PreviewBackupService.kt` — none on this path.

---

## 3. Rule-51 assessment — honest, not assumed

The row asserts "Rule-51-clean (reuses #132's sheet)". That is **mostly** right. Three distinct
surfaces need checking, and one of them deserves an explicit Gate-2 ruling rather than an assumption.

| Surface | Committed design | Verdict |
| --- | --- | --- |
| The Contents **sheet** (header, rows, chapter number, title, `p. N`, current-row accent tint) | `dev-docs/designs/vreader-fidelity-v1/project/vreader-panels.jsx:293-340` (`TOCSheet`, Contents tab) — already implemented as `TocContentsSheet`/`TocSheetRows` (#132 WI-3) and already reachable on EPUB and TXT/MD | **Designed. Pure reuse — #140 adds no element, state, or style.** |
| The Contents **toolbar slot** in the bottom chrome | `dev-docs/designs/vreader-fidelity-v1/project/vreader-reader.jsx` toolbar `Contents · Notes · Display · AI`, implemented at `ReaderBottomChrome.kt:130-135` (tag `chrome-contents`, `FormatListBulleted` icon, "Contents" label) and shipped on EPUB + TXT/MD | **Designed.** #140 *un-omits* an existing designed slot on one more host — the exact move `ReaderBottomChrome.kt:1-9` documents #132 WI-5 making. The AZW3 toolbar becomes `Contents · Notes` (still a subset of the designed four, as it already is at one item today). |
| The Contents **empty state** (`TocEmptyState`, `TocSheetRows.kt:127-144`) | Not depicted as an AZW3 state — but **it is not reachable here**: an empty TOC hides the control (W3), so no sheet can be opened. | **Not surfaced. No design needed.** |

### 3.1 The one genuine gap — depth indentation is NOT in the bundle

`vreader-panels.jsx:318-339` renders a **flat** Contents list. The depth-indent treatment
(`TocSheetRows.kt:105`, `depth.coerceIn(0,4) * 12.dp`) was introduced by **feature #132 WI-1**, has
shipped since, and was device-verified by **#139 acceptance criterion 7** ("`docs/architecture.md`
→ 37 entries, depths `[0,1,2,3]`; depth-2 measurably indented past depth-1" —
`dev-docs/verification/feature-139-20260805.md:51`). It is therefore **existing, shipped, verified
behavior**, not something #140 introduces.

**Position taken (for the auditor to confirm or reject):** #140 introduces **no new visible
element** — it feeds `depth > 0` into rows that already render `depth > 0` on MD books today, so
this is rule 51's "pure code change with no visible delta" exclusion. **No `needs-design` issue is
filed by this plan.**

**If the auditor disagrees**, the correct remedy is NOT to change #140's scope: it is a
`needs-design` issue against the **Contents sheet's nested-row treatment**, retroactively covering
#132/#139 as well, with #140's WI-6 marked `BLOCKED: needs-design (#N)` — and NOT "ship AZW3 flat",
which would be a deliberate capability regression against iOS #38. Flagged here so the decision is
made explicitly rather than inherited.

---

## 4. Prior art / precedent / rejected alternatives

### 4.1 iOS #38 — the parity source (`FoliateTOCConverter.swift`, read in full)

The exact semantics to port:

- **Depth-first flatten, parent emitted before children** (`convert` → `flatten(items, level: 0…)`).
- **`level` starts at 0 and increments once per nesting step.**
- **Labels are trimmed** (`trimmingCharacters(in: .whitespacesAndNewlines)`); a blank label yields
  no row.
- **A blank href yields no row EITHER — but its subitems are still walked.** This is iOS bug #262's
  round-1 fix, documented in-file: `serializeTOC` serializes a missing href as `''`, and an empty
  href produces a tappable row whose navigation no-ops. *"Skip emitting an entry for an empty-href
  node, but STILL recurse into its subitems so clickable children of a non-navigable parent (a
  common TOC shape) remain visible."* — **port this verbatim.** It also happens to match Android's
  `ReadiumTocProvider.kt:66-71` skip-but-recurse comment, so both platforms already agree.
- **The row's locator is `LocatorFactory.epub(fingerprint:href:progression: 0.0)`** — i.e. an
  **href-bearing locator whose `format` is the book's real format (`azw3`)**. So iOS already puts an
  href into an AZW3-format locator for TOC rows; Android doing the same is parity, not invention.

And the navigation resolver, `FoliateNavSeek.navigationTarget` (`FoliateNavSeek.swift:34-46`):

```
cfi (non-blank)  →  href (non-blank)  →  nil
```

**Note what is absent: there is no progression leg.** That absence is load-bearing — see §5.2.

### 4.2 Android precedent this builds on

| Precedent | File | What is reused |
| --- | --- | --- |
| The `TocProvider` seam | `nav/TocProvider.kt` (`fun interface`, `suspend fun toc(): List<TocEntry>`) | a third implementation beside `ReadiumTocProvider` / `TxtMdTocProvider` |
| Recursive flatten with depth + skip-but-recurse | `nav/ReadiumTocProvider.kt:60-71` | copied structure, different source tree |
| Testability posture (a pure seam so the flatten logic is JVM-testable without a platform type) | `nav/ReadiumTocProvider.kt:26-38` (`PublicationTocSource`) | our source is already a plain data tree, so no seam is needed — a stronger version of the same property |
| The current-chapter index helper | `ReaderChromeModel.kt:74-99` (`tocIndexFor`), `nav/TxtTocIndex.kt` (`txtTocIndexFor`) | a third: `foliateTocIndexFor(currentTocHref, entryHrefs)` |
| The awaited goTo + sync dismiss decision | `Azw3ReaderActivity.kt:188-210`, `:301-322`; `FoliateBridge.kt:218-303` | **reused unchanged** — WI-3 only teaches `FoliateGoToTarget` a third shape |
| Render-death carry-across for an in-flight jump | `Azw3Document.kt:75-105`, `:160-173` | unchanged; a TOC jump inherits it for free |
| The lazy Contents sheet | `TocContentsSheet.kt:161-199` (#139 WI-6) | unchanged; an AZW3 TOC is far smaller than a 1,859-row TXT one |
| Host wiring / doc-sync / Gate-5 shape | feature #139 WI-7/WI-8 | the template for WI-6 / WI-8 |

### 4.3 Rejected alternatives

| Alternative | Why rejected |
| --- | --- |
| **Add a new `readerAPI.getTOC()` call and a new bridge round-trip** | Unnecessary: `book-ready` already carries the tree (W6). A second round-trip adds a failure mode (a race against render-death, a second timeout to design) for zero information. |
| **Patch `foliate-bundle.js`** (e.g. to emit a pre-flattened TOC, or to make `view.goTo` reject on an unresolvable target) | The bundle is SHA-pinned (W10) and re-deriving the pin is a documented multi-step patch chain (`FoliateBundleProvenanceTest.kt:21-24`). Everything #140 needs is already emitted; the only JS edit required is in **our own** `reader.html` shim (W9), which is not pinned. Making `goTo` reject would be a genuine improvement (§9 R1) but it is a bundle change and a separate, riskier piece of work — named follow-up **F2**. |
| **Reuse `FoliateGoToTarget.Cfi` to carry an href** (it works, because `readerAPI.goTo` takes both) | Semantically dishonest: the type would lie about its content, the injected JS would say `{cfi: "kindle:pos:…"}`, and the next reader of `FoliateGoToTarget.from` would mis-reason about precedence. A third case costs ~6 lines. |
| **Derive the current chapter from `fraction` + section fractions** instead of `relocate.tocHref` | foliate already computes the answer with its own `TOCProgress` over the *same* toc objects (`foliate-bundle.js:6666-6672`, `:7047-7048`) and posts it. Re-deriving it from fractions would be a second, worse implementation of a thing the engine hands us — and would drift from what the engine believes. |
| **Persist the TOC to Room** | It is derived at book-open from data already in flight; there is nothing to save. (Contrast #139, where the TOC cost a whole-document regex scan and persistence was a live question.) |
| **Give TOC rows a `pageLabel`** | AZW3 has no page model in this host (`Azw3ReaderActivity.kt:141-143` passes `pageCount = null` to Book Details). `TocSheetRows.kt:114-122` renders `p. N` only when non-null, so `null` is both correct and free. |
| **Also surface `relocate.tocLabel` as a chapter name in the AZW3 chrome** (iOS does this at `FoliateReaderContainerView.swift:218`) | Out of scope: the Android AZW3 bottom chrome has no chapter-label surface today, and adding one is undesigned UI (rule 51). Named follow-up **F3**. |
| **Bookmark-from-TOC** (`TocEntry.kt:4-5` anticipates it) | Out of scope; #135 territory. Named follow-up **F4**. |

---

## 5. Design

### 5.1 Pipeline

```
foliate-js bundle (UNCHANGED, SHA-pinned)
   │  book-ready { title, sections, toc:[{label,href,subitems:[…]}] }        ← already emitted today
   │  relocate   { cfi, fraction, sectionIndex, sectionTotal, tocHref, … }   ← already emitted today
   ▼
FoliateMessageParser  (WI-1 + WI-4: stop discarding `toc` and `tocHref`)
   │      │  reads detail["toc"] itself, then hands the ELEMENT over:
   │      └─ FoliateTocParser.parse(tocElement: JsonElement?) → List<FoliateTocItem>  [depth/node-capped]
   ▼
FoliateMessage.BookReady(title, sectionTotal, toc)          FoliateMessage.Relocate(…, tocHref)
   │                                                                   │
   ▼                                                                   │
Azw3Document  → Azw3DocState.Loaded(sectionTotal, toc)   (WI-6)        │
   │                                                                   │
   ▼   (hoisted out of Azw3ReaderHost via onToc, like onRelocate/onDocument)
Azw3ReaderActivity
   ├─ FoliateTocProvider(items, book).toc()  (WI-2)  →  List<TocEntry>
   │      title = label.trim()   depth = nesting level   pageLabel = null
   │      canonicalLocator = Locator(sha, bytes, "azw3", href = item.href)   ← progression stays NULL (§5.2)
   │      epubReadiumLocator = null
   ├─ tocEntries      ──► Azw3ReaderChrome ──► ReaderChromeScaffold ──► Contents control + TocBookmarksSheet
   ├─ currentTocIndex ──► foliateTocIndexFor(latestRelocate.tocHref, entryHrefs)   (WI-4)
   └─ onJumpToc(i)    ──► azw3JumpDecision(doc, entries[i].canonicalLocator)   [EXISTING, #135]
                            └─ jumpScope.launch { doc.goTo(entries[i].canonicalLocator) }
                                 └─ FoliateGoToTarget.from → Href   (WI-3)
                                      └─ __vreaderGoTo(id, {href}) → readerAPI.goTo(href)   (WI-3, reader.html)
                                           └─ view.resolveNavigation → book.resolveHref → renderer.goTo
```

Nothing in the bundle, the paginator, the position-save path, the bookmark path, or the annotation
path changes.

### 5.2 The single most dangerous detail: **progression must not win**

iOS's TOC locators carry `progression = 0.0` (§4.1) and that is harmless there, because
`FoliateNavSeek.navigationTarget` has **no progression leg**. Android's resolver **does**:

```kotlin
// FoliateBridge.kt:210-214 — TODAY
fun from(locator: Locator): FoliateGoToTarget? {
    locator.cfi?.takeIf { it.isNotBlank() }?.let { return Cfi(it) }
    locator.progression?.takeIf { it.isFinite() }?.let { return Fraction(it) }
    return null
}
```

If an Android TOC row copied iOS's `progression = 0.0`, **every chapter would resolve to
`Fraction(0.0)` and jump to the start of the book** — while `view.goTo` resolves successfully, the
shim acks `ok: true`, and the sheet dismisses. A test that asserts "the jump succeeded" would be
**green on a completely broken feature**. This is the exact failure shape §8 is built to catch.

**Two independent defenses, both required:**

1. **Precedence becomes `cfi → href → progression`** (WI-3). Even if a TOC row later acquires a
   progression, the href still wins.
2. **TOC rows carry `progression = null`** (WI-2), a deliberate, documented divergence from iOS's
   `0.0` — it is the *same* observable behavior on iOS (which never reads it) and the *safe*
   behavior on Android. Pinned by `FoliateTocProviderTest.entryLocator_hasNoProgression`.

Existing behavior is unaffected: bookmarks/resume locators for AZW3 carry `progression` + `cfi` and
never an `href` (`Azw3LocatorBridge.kt:26-32`), so no existing target resolution changes. Pinned by
re-running `Azw3BookmarkNavTest.jumpDecision_dismissesOnJumpableTarget_staysOpenOnUnjumpable`
(`Azw3BookmarkNavTest.kt:121-141`), whose `unjumpable` fixture has no href and must stay `Failed`.

### 5.3 `TocEntry` field mapping

| Field | AZW3 value | Why |
| --- | --- | --- |
| `title` | `item.label.trim()`; a blank label ⇒ the node emits no row (children still walked) | iOS parity (`FoliateTOCConverter.swift` `trimmedLabel`) |
| `depth` | nesting level, 0-based, depth-first | iOS parity (`level`); rendered by `TocSheetRows.kt:105` |
| `pageLabel` | `null` | no page model on this host (§4.3) |
| `canonicalLocator` | `Locator(book.contentSHA256, book.fileByteCount, BookFormat.azw3.name, href = item.href)` — `.validatedOrNull()` applied, and a null result drops the row | mirrors iOS's href-bearing AZW3 TOC locator; §5.2 for the null progression |
| `epubReadiumLocator` | `null` | non-Readium host (`TocEntry.kt:29`) |

The `format` leg uses `book.originalFormat.name` (the same typed format `MainActivity` routed on,
`MainActivity.kt:90`), matching `TxtMdTocProvider.kt:29-30`'s note — **not** a hardcoded `"azw3"`
string, so `.azw`/`.mobi`/`.prc` books (which import as `BookFormat.azw3` today) key consistently
with their bookmarks.

### 5.4 Hostile / malformed TOC — where each bound lives

**The processing of a book's TOC has TWO stages, and this feature only owns the second one.** Gate-2
round 1 rated the previous version of this section a **High** for blurring them. Stated precisely:

#### Stage 1 — JS, inside the SHA-pinned bundle. **Pre-existing, unchanged by #140, NOT bounded.**

Three *recursive* JS walks over the book's TOC tree run before Kotlin sees anything, all inside
`readerAPI.open()`:

| # | Where | Line | What |
| --- | --- | --- | --- |
| 1 | `assignIDs(toc)` | `foliate-bundle.js:6101-6109` | recursive `assignID` over `item.subitems` |
| 2 | `flatten(items)` | `foliate-bundle.js:6110` | self-recursive `flatten(item.subitems)` |
| 3 | `serializeTOC(toc)` | `foliate-bundle.js:7659-7666` | self-recursive `serializeTOC(item.subitems)` |

(1) and (2) run from `TOCProgress.init({ toc: book.toc ?? [] })` at `foliate-bundle.js:6666-6672`,
reached by `await view.open(url)`; (3) runs when the result is posted at `:7174`. **All three
already execute on every AZW3 open today**, with `book.toc` fully built, whether or not Kotlin reads
the field. A TOC pathological enough to blow the JS stack therefore blows it *today* — the failure
lands in `readerAPI.open`'s `catch`, which posts `error` instead of `book-ready`, and
`Azw3Document.handle` maps a pre-`book-ready` error to `Azw3DocState.Corrupt`
(`Azw3Document.kt:129`): **"This book can't be opened."**

**#140 changes this exposure by exactly nothing.** It adds no JS work, no bundle change, no new
call. But equally: **no Kotlin bound can protect against it**, because the Kotlin bound is
downstream of the crash. Fixing stage 1 means patching a SHA-pinned bundle — out of scope, named
follow-up **F6** (§10).

#### Stage 2 — Kotlin, on the WebView message callback thread. **This is what #140 owns and bounds.**

`FoliateMessageParser.parse` runs on the main thread (`FoliateBridge.kt:128-134` calls
`WebViewCompat.addWebMessageListener` with no handler). Two facts constrain the design:

- **The full JSON payload — TOC included — is ALREADY parsed on that thread today.**
  `FoliateMessageParser.kt:25` does `json.parseToJsonElement(raw).jsonObject` over the entire
  `book-ready` message before reading `title`. So #140 adds only a **walk over an already-built
  `JsonElement` tree**, not a new parse. This is why §9 R5 rates the added main-thread cost low —
  but it is still *measured* (WI-7), because #139's Gate-5 taught that a desktop estimate can be
  100× wrong on device (`dev-docs/verification/feature-139-20260805.md:88-92`).
- **Recursion is the hazard #140 introduces.** The tree walk is new Kotlin code over
  attacker-shaped input; an unbounded recursive descent is a `StackOverflowError` *in the message
  callback*, which — same as stage 1 — would leave the book unopenable. This is the one this
  feature must not get wrong.

Bounds (all `internal const`, each with a boundary test):

```kotlin
/** Deepest nesting level parsed. Beyond this, subitems are DROPPED (the parent row is kept). */
internal const val MAX_TOC_DEPTH = 12

/** Most rows a Foliate TOC may yield. Beyond this the WHOLE TOC is REJECTED, never truncated. */
internal const val MAX_TOC_ENTRIES = 10_000
```

- `MAX_TOC_DEPTH = 12`: `TocSheetRows.kt:105` already clamps *indentation* at 4, so nothing past
  depth 4 is visually distinguishable; 12 is far above any real NCX and keeps the walk shallow.
  **Drop-subitems, keep-parent** (rather than rejecting) because over-deep nesting is a *display*
  problem, not a correctness one — the reachable chapters stay reachable.
- `MAX_TOC_ENTRIES = 10_000`: **reject, never truncate** — the #139 rationale verbatim
  (`TxtMdTocProvider.kt:98-105`): "a Contents list that silently stops at entry N of a larger book
  is worse than none, because the user cannot tell it is incomplete." 10 000 (not #139's 50 000)
  because an NCX is authored, not detected: no real Kindle book has 10 000 TOC rows, and the whole
  tree is being held in memory on the main thread.
- **The parse is iterative or explicitly depth-limited** — an unbounded recursive descent over
  attacker-controlled nesting is a `StackOverflowError` in the WebView callback. Pinned by
  `FoliateTocParserTest.deeplyNestedToc_doesNotOverflow_andDropsBeyondMaxDepth` built from a
  200-deep synthetic payload, **and re-run on-device** by WI-7's `pathologicalTocPayload_…` probe
  (ART's stack budget is not the JVM's, so a JVM-only pass is not evidence for the device).

Every other malformed shape degrades to "absent", matching the parser's existing contract
(`FoliateMessageParser.kt:20-23`): `toc` missing / null / not an array / elements not objects /
`subitems` not an array ⇒ empty or partial list, never a throw.

#### The claim this plan makes — and the one it does NOT

> **CLAIM (stage 2, deliverable):** a `book-ready` message whose `toc` field is malformed, hostile,
> absurdly deep, or absurdly large is parsed **without throwing and without unbounded recursion or
> allocation**, so the Kotlin side degrades to "no TOC / partial TOC" and the book opens exactly as
> it would have before #140. Verified by `FoliateTocParserTest` (JVM) **and** WI-7's on-device
> injection probe, which drives a 200-deep / over-cap payload through the REAL
> `addWebMessageListener` → `FoliateMessageParser` path on the emulator's main thread.
>
> **NOT CLAIMED:** that a pathological book *file* opens. A TOC pathological enough to break the
> bundle's own recursive walks (stage 1) prevents `book-ready` from ever being posted, and no
> Kotlin-side bound can change that. That exposure is **pre-existing and unchanged**; it is
> characterized, not fixed, here. Follow-up **F6**.

This distinction is the reason §11's acceptance criterion 8 is scoped to the payload, not the book.

### 5.5 Current-chapter highlight

```kotlin
/**
 * The index of the TOC row foliate itself considers current, matched by the `tocHref` it
 * reports on every relocate. Returns the LAST matching index (a parent and its first child
 * commonly share an href; the deepest/last row is the more specific answer — the same rule
 * ReaderChromeModel.tocIndexFor uses for an exact-href match).
 * No href / no match, but a TOC exists → 0 (never -1: a missing highlight is worse than a
 * best-effort first row — the tocIndexFor contract, ReaderChromeModel.kt:66-70).
 * Empty entries → -1.
 */
fun foliateTocIndexFor(currentTocHref: String?, entryHrefs: List<String>): Int
```

Matching is on the **exact string** foliate emits. That is sound because `TOCProgress` is
initialized with `book.toc` (`foliate-bundle.js:6666-6672`) — the very object tree `serializeTOC`
walks — so `relocate.tocHref` is, by construction, `===` one of the serialized hrefs. Comparison is
byte-exact with no normalization, deliberately: any normalization we invent could only *break* an
identity the engine already guarantees.

### 5.6 Threading

- **Parse** (`FoliateTocParser`): main thread, bounded (§5.4), over an already-parsed tree.
- **Flatten** (`FoliateTocProvider.toc()`): `withContext(dispatcher)` on an **injected**
  dispatcher, owned by the provider — exactly `TxtMdTocProvider.kt:76` (rule 50 §12.1: never a
  hardcoded dispatcher; the host must not wrap the call).
- **Publish**: a `LaunchedEffect` keyed on the `Azw3DocState.Loaded` toc payload sets a
  `mutableStateOf(emptyList())`. Until it publishes, `tocEntries` is empty ⇒ the control is hidden
  ⇒ **the pre-publish frame is byte-identical to today's behavior**, so there is no loading state
  and therefore no undesigned surface (rule 51).
- **No first-frame gate is needed.** #139 needed one because its scan was CPU work competing with
  the first paint (`…-139-….md:536-604`). Here the TOC *arrives* at `book-ready`, which by
  definition is after the render pipeline has started, and the flatten is O(entries) over a
  ≤10 000-node tree off the main thread.
- **Render-process death**: the host recreates the WebView + `Azw3Document`
  (`Azw3ReaderActivity.kt:377-382`); the replacement re-opens the book and emits a fresh
  `book-ready`, so the TOC re-arrives with no extra machinery. The previous entries are **kept**
  (not cleared) during the gap so the control doesn't blink; a jump attempted in that window hits
  the existing `!bookReady` path (`Azw3Document.kt:161-166`) → `Failed` → the sheet stays open
  (rule 51). Pinned by an explicit test in WI-6.

---

## 6. Surface area

### 6.1 New files

All Kotlin; Gradle picks up new files by source-set glob (no project regeneration — rule 55's
"new files aren't lane-dispatchable" caveat is iOS/xcodegen-specific, as #139 established).

| File | Contents |
| --- | --- |
| `…/reader/foliate/FoliateTocItem.kt` | `data class FoliateTocItem(val label: String, val href: String, val subitems: List<FoliateTocItem> = emptyList())` — the wire shape of `serializeTOC` |
| `…/reader/foliate/FoliateTocParser.kt` | `object FoliateTocParser { internal const val MAX_TOC_DEPTH = 12; internal const val MAX_TOC_ENTRIES = 10_000; fun parse(tocElement: JsonElement?): List<FoliateTocItem> }` — bounded, throw-free. **Takes the `toc` ELEMENT, not the `book-ready` envelope** (Gate-2 R1 Low): reading `detail["toc"]` is `FoliateMessageParser`'s job, so this object stays a reusable TOC parser with no knowledge of which message carried the tree. A `null` element (field absent) is a legal input yielding `emptyList()` |
| `…/reader/nav/FoliateTocProvider.kt` | `class FoliateTocProvider(private val items: List<FoliateTocItem>, private val book: Book, private val dispatcher: CoroutineDispatcher) : TocProvider` — depth-first flatten, skip-but-recurse, entry cap |
| `…/reader/nav/FoliateTocIndex.kt` | `fun foliateTocIndexFor(currentTocHref: String?, entryHrefs: List<String>): Int` |
| `…/reader/Azw3ReaderChrome.kt` | WI-5 — the pure move of `Azw3ReaderChrome`, `Azw3NotesBottomChrome`, `azw3JumpResult`, `azw3JumpDecision` out of `Azw3ReaderActivity.kt` (same package ⇒ no import changes anywhere) |

New test files: `FoliateTocParserTest.kt`, `FoliateTocProviderTest.kt`, `FoliateTocIndexTest.kt`
(JVM); `Azw3TocConnectedTest.kt`, `Azw3TocAcceptanceTest.kt` (connected).

### 6.2 Modified files

| File | Change | WI |
| --- | --- | --- |
| `…/reader/foliate/FoliateMessage.kt` | `BookReady` gains `toc: List<FoliateTocItem> = emptyList()`; `Relocate` gains `tocHref: String? = null` (both defaulted ⇒ every existing construction site compiles) | 1, 4 |
| `…/reader/foliate/FoliateMessageParser.kt` | populate the two new fields; delegate the tree walk to `FoliateTocParser` | 1, 4 |
| `…/reader/foliate/FoliateBridge.kt` | `FoliateGoToTarget.Href`; `from()` precedence cfi → href → progression; `gotoJs` href branch (JSON-escaped through the existing `jsString` seam) | 3 |
| `android/app/src/main/assets/foliate/reader.html` | `__vreaderGoTo`: one `else if (target.href != null) { p = window.readerAPI.goTo(target.href); }` branch. **`foliate-bundle.js` is NOT touched** (W10) | 3 |
| `…/reader/foliate/Azw3Document.kt` | `Azw3DocState.Loaded(sectionTotal, toc)`; carry `message.toc` through `handle` | 6 |
| `…/reader/Azw3ReaderActivity.kt` | hoist the TOC out of `Azw3ReaderHost` (`onToc`, mirroring `onRelocate`/`onDocument`); build the provider; feed `tocEntries` / `currentTocIndex` / `onJumpToc`; **pass the Contents callback into the bottom chrome** (the `_` at `:473`); update the `Purpose:` header (rule 22 — `:11-12` currently *states* the gap) | 5, 6 |
| `…/reader/Azw3ReaderChrome.kt` | `tocEntries` / `currentTocIndex` / `onJumpToc` params (defaulted); `Azw3NotesBottomChrome` → `Azw3BottomChrome(theme, onOpenContents, onOpenNotes)` rendering the designed Contents slot when non-null | 6 |
| `…/reader/chrome/ReaderBottomChrome.kt` | `private fun ToolbarIconButton` → `internal` so the AZW3 bottom chrome reuses the **same** designed treatment instead of duplicating it (no visual drift by construction) | 6 |
| `docs/architecture.md` | `:659-674` — add the `FoliateTocProvider` row (WI-2, same PR as the service, rule 24); WI-6 then corrects `EmptyTocProvider (PDF/AZW3)` → `(PDF)` and removes the now-stale #139 parenthetical *"(Host wiring lands in #139 WI-7; until then…)"* at `:661-663`, which became false when #139 WI-7 merged | 2, 6 |
| `android/app/src/androidTest/.../Azw3ReaderChromeUiTest.kt` | the `withNoContents` case is **kept** as the empty-TOC regression (its `Contents` count-0 assertion still holds with the defaulted empty list); its comment is updated, and new cases are added | 6 |

### 6.3 Files explicitly OUT of scope

- **`android/app/src/main/assets/foliate/foliate-bundle.js`** — SHA-pinned (W10); nothing needed
  from it.
- **`android/app/src/androidTest/assets/foliate-spike/*`** — the legacy spike harness copy, which
  has **already diverged** from `main` (it lacks the #135 goTo shim entirely; diff verified). Not
  updated, not used by any #140 test.
- `reader/nav/EmptyTocProvider.kt` — **stays**; still correct for PDF.
- `reader/nav/TocContentsSheet.kt`, `TocSheetRows.kt`, `TocBookmarksSheet.kt`,
  `chrome/ReaderChromeScaffold.kt` — **no change** (W3, W5, W11). `ReaderChromeScaffold`'s
  `tocEntries.isEmpty()` rule already produces the wanted behavior.
- `reader/nav/ReadiumTocProvider.kt`, `reader/ReaderActivity.kt`, `reader/ReaderChromeModel.kt`,
  `reader/TxtReaderActivity.kt`, `reader/nav/TxtMdTocProvider.kt`, `reader/PdfReaderScreen.kt` —
  EPUB / TXT / MD / PDF TOC paths untouched.
- `reader/foliate/Azw3LocatorBridge.kt` — the persisted-position shape is unchanged.
- Room, `contracts/`, backup — nothing persisted (§10).
- `reader/foliate/FoliateGoToDispatcher` await/supersede/timeout machinery — reused verbatim.

---

## 7. Work-item sequencing

Nine WIs. Tiers per rule 47 Gate 5: **foundational** = pure types/logic, no user-observable
behavior (unit tests + audit suffice); **behavioral** = changes what the app does on screen
(emulator verification through a production path required).

---

### WI-1 — `FoliateTocItem` + `FoliateTocParser` (stop discarding `book-ready.toc`)

```yaml
id: WI-1
tier: foundational
depends: []
writes:
  - android/app/src/main/kotlin/com/vreader/app/reader/foliate/FoliateTocItem.kt
  - android/app/src/main/kotlin/com/vreader/app/reader/foliate/FoliateTocParser.kt
  - android/app/src/main/kotlin/com/vreader/app/reader/foliate/FoliateMessage.kt
  - android/app/src/main/kotlin/com/vreader/app/reader/foliate/FoliateMessageParser.kt
  - android/app/src/test/kotlin/com/vreader/app/reader/foliate/FoliateTocParserTest.kt
  - android/app/src/test/kotlin/com/vreader/app/reader/foliate/FoliateMessageParserTest.kt
tests:
  - FoliateTocParserTest.flatToc_parsesLabelAndHrefInOrder
  - FoliateTocParserTest.nestedToc_preservesSubitemTree
  - FoliateTocParserTest.nullElement_yieldsEmptyList            # parse(null) — the field-absent input
  - FoliateTocParserTest.jsonNullElement_yieldsEmptyList
  - FoliateTocParserTest.tocIsNotAnArray_yieldsEmptyList
  - FoliateTocParserTest.tocElementIsNotAnObject_isSkipped_siblingsSurvive
  - FoliateTocParserTest.subitemsMissingOrNullOrNotAnArray_treatedAsNoChildren
  - FoliateTocParserTest.blankLabelAndBlankHref_arePreservedVerbatim_filteringIsTheProvidersJob
  - FoliateTocParserTest.deeplyNestedToc_doesNotOverflow_andDropsBeyondMaxDepth   # 200-deep payload
  - FoliateTocParserTest.overMaxEntries_rejectsWholeToc_neverTruncates
  - FoliateTocParserTest.exactlyMaxEntries_isKept                                 # boundary
  - FoliateTocParserTest.cjkAndRtlLabels_areByteForBytePreserved
  - FoliateTocParserTest.hrefWithFragmentQueryOrNonAscii_isPreservedByteForByte  # Gate-2 R1 Low
  - FoliateTocParserTest.labelWithEmbeddedNewline_isPreserved_sheetNormalizesAtRender
  - FoliateMessageParserTest.bookReady_populatesTocTree
  - FoliateMessageParserTest.bookReady_withoutToc_stillParsesTitleAndSections    # back-compat
  - FoliateMessageParserTest.hostileTocPayload_isParsedWithoutThrowing           # scoped: the PAYLOAD
acceptance: >
  `book-ready` yields the full nested tree; every malformed shape degrades to empty/partial and
  NEVER throws; MAX_TOC_DEPTH drops deeper subitems while keeping the parent row; MAX_TOC_ENTRIES
  rejects the whole TOC rather than truncating; a 200-deep synthetic payload does not StackOverflow
  on the JVM (WI-7 re-runs it on ART). Existing FoliateMessageParser behavior is unchanged for every
  message that carries no `toc`.
  SCOPE (Gate-2 R1 High): these bounds protect the KOTLIN stage only. They cannot make a
  pathological BOOK open — foliate's own recursive assignIDs/flatten/serializeTOC
  (foliate-bundle.js:6101-6110, :7659) run first, inside the SHA-pinned bundle, and a failure there
  posts `error` instead of `book-ready` → Azw3DocState.Corrupt (Azw3Document.kt:129). That exposure
  is pre-existing and unchanged by this feature; see §5.4 and follow-up F6. No test here may be
  named or worded as though it proves the book opens.
pr_size: ~120 impl + ~230 test
```

---

### WI-2 — `FoliateTocProvider` (tree → `TocEntry`)

```yaml
id: WI-2
tier: foundational
depends: [WI-1]
writes:
  - android/app/src/main/kotlin/com/vreader/app/reader/nav/FoliateTocProvider.kt
  - android/app/src/test/kotlin/com/vreader/app/reader/nav/FoliateTocProviderTest.kt
  - docs/architecture.md
tests:
  - FoliateTocProviderTest.flatTree_yieldsDepthZeroRowsInOrder
  - FoliateTocProviderTest.nestedTree_isDepthFirst_parentBeforeChildren
  - FoliateTocProviderTest.depthIncrementsOncePerNestingLevel
  - FoliateTocProviderTest.blankLabel_isSkipped_butSubitemsAreStillWalked      # iOS bug #262 parity
  - FoliateTocProviderTest.blankHref_isSkipped_butSubitemsAreStillWalked       # iOS bug #262 parity
  - FoliateTocProviderTest.labelIsTrimmed
  - FoliateTocProviderTest.entryLocator_carriesHref_andBookIdentityTriple
  - FoliateTocProviderTest.entryLocator_hasNoProgression                        # §5.2 defense 2
  - FoliateTocProviderTest.entryLocator_formatComesFromBookOriginalFormat_notALiteral
  - FoliateTocProviderTest.pageLabelAndReadiumLocator_areNull
  - FoliateTocProviderTest.emptyTree_yieldsEmptyList_theHideTheControlSignal
  - FoliateTocProviderTest.hrefWithFragmentOrQuery_isPreservedByteForByte      # Gate-2 R1 Low
  - FoliateTocProviderTest.kf8PosUriHref_isPreservedByteForByte                # kindle:pos:fid:…:off:…
  - FoliateTocProviderTest.mobi6FileposHref_isPreservedByteForByte             # filepos:NNNN
  - FoliateTocProviderTest.nonAsciiHref_isPreservedByteForByte                 # decodeURI'd CJK path
  - FoliateTocProviderTest.runsOnTheInjectedDispatcher_notTheCaller
  - FoliateTocProviderTest.cancellation_isCooperative
acceptance: >
  Depth-first order, iOS #38 semantics exactly (trim, skip-blank-but-recurse); every emitted row
  carries an href-bearing canonical locator with the book identity triple and NO progression; an
  empty result is the documented "hide the Contents control" signal, not an error. Hrefs are opaque
  and preserved BYTE-FOR-BYTE — the three real shapes are KF8 `kindle:pos:fid:XXXX:off:YYYYYYYYYY`
  (foliate-bundle.js:3380), MOBI6 `filepos:NNNN` (:3235) and the EPUB-path relative href, which is
  `decodeURI`'d (:1753) so it can carry a `#fragment`, a query, or non-ASCII characters. The
  provider owns its dispatcher hop (rule 50 §12.1). docs/architecture.md gains the FoliateTocProvider
  row in THIS PR (rule 24), with an explicit "(host wiring lands in WI-6)" parenthetical.
pr_size: ~110 impl + ~220 test + ~10 docs
```

> **Dependency note (Gate-2 R1 Medium).** An earlier draft carried
> `FoliateTocProviderTest.everyEmittedRow_hasAJumpableTarget` here with a prose instruction to
> "sequence WI-3 first" — but the machine-readable `depends:` token still said `[WI-1]`, and
> `scripts/deps-check.sh` reads the token, not the prose, so a dispatcher would have started WI-2
> straight into a known-red test. **Resolved by moving the assertion, not by adding a dependency**:
> the target-resolution invariant now lives in **WI-3** (`from_hrefOnlyLocator_yieldsHrefTarget`,
> which builds its own TOC-shaped locator inline and needs nothing from WI-2), and the *end-to-end*
> version — real provider rows resolving to real href targets — lives in **WI-6**, which genuinely
> depends on both. WI-2's `depends: [WI-1]` is therefore correct as written and WI-2 and WI-3 are
> independent and parallelizable. (Same failure shape as the stale Spec block that nearly shipped
> into #155 WI-5: a decision recorded in prose while the machine-readable field said the old thing.)

---

### WI-3 — the href navigation leg (`FoliateGoToTarget.Href` + the shell shim)

```yaml
id: WI-3
tier: foundational
depends: []
writes:
  - android/app/src/main/kotlin/com/vreader/app/reader/foliate/FoliateBridge.kt
  - android/app/src/main/assets/foliate/reader.html
  - android/app/src/test/kotlin/com/vreader/app/reader/foliate/FoliateGoToTest.kt
tests:
  - FoliateGoToTest.from_hrefOnlyLocator_yieldsHrefTarget
  - FoliateGoToTest.from_prefersCfiOverHref
  - FoliateGoToTest.from_prefersHrefOverProgression                 # §5.2 defense 1 — THE regression
  - FoliateGoToTest.from_hrefWithProgressionZero_stillYieldsHref    # the exact iOS-shaped locator
  - FoliateGoToTest.from_blankHref_fallsThroughToProgression
  - FoliateGoToTest.from_noCfiNoHrefNoProgression_yieldsNull        # unchanged contract
  - FoliateGoToTest.from_tocShapedLocator_alwaysResolves            # moved here from WI-2 (R1 Medium)
  - FoliateGoToTest.gotoJs_hrefIsJsonEscaped_quotesBackslashesScriptTagsNeutralized
  - FoliateGoToTest.gotoJs_hrefWithFragmentQueryOrNonAscii_isPassedThroughUNCHANGED  # R1 Low
  - FoliateGoToTest.gotoJs_kf8PosUriHref_survivesEscapingByteForByte  # kindle:pos:fid:…:off:…
  - FoliateGoToTest.gotoJs_hrefTarget_callsReaderApiGoTo_notGoToFraction
  - FoliateGoToTest.hrefGoTo_awaitsAck_andSupersedeStillApplies
acceptance: >
  Precedence is cfi → href → progression, pinned by a test whose fixture is exactly the iOS-shaped
  TOC locator (href + progression 0.0) and which asserts Href, NOT Fraction(0.0) — the defect that
  would otherwise send every chapter tap to the start of the book with a green "jump succeeded".
  The href rides the EXISTING jsString/JSON-escaping seam (FoliateBridge.kt:302) — no new escaping
  code — and is passed to readerAPI.goTo BYTE-FOR-BYTE: no trimming, no normalization, no
  re-encoding, so a `#fragment`, a query suffix, the KF8 `kindle:pos:…` colon form and a decodeURI'd
  non-ASCII path all survive (Gate-2 R1 Low). reader.html gains ONE else-if branch;
  foliate-bundle.js is untouched and its pinned SHA test still passes. The shim branch itself is not
  JVM-testable and is covered by WI-7's connected round-trip.
  `from_tocShapedLocator_alwaysResolves` moved here from WI-2 so no WI is dispatchable while a
  declared test is known-red (Gate-2 R1 Medium); it constructs its own href-only locator inline and
  depends on nothing from WI-2.
pr_size: ~40 impl (incl. ~4 lines JS) + ~150 test
```

---

### WI-4 — `relocate.tocHref` + `foliateTocIndexFor`

```yaml
id: WI-4
tier: foundational
depends: [WI-1]
writes:
  - android/app/src/main/kotlin/com/vreader/app/reader/foliate/FoliateMessage.kt
  - android/app/src/main/kotlin/com/vreader/app/reader/foliate/FoliateMessageParser.kt
  - android/app/src/main/kotlin/com/vreader/app/reader/nav/FoliateTocIndex.kt
  - android/app/src/test/kotlin/com/vreader/app/reader/foliate/FoliateMessageParserTest.kt
  - android/app/src/test/kotlin/com/vreader/app/reader/nav/FoliateTocIndexTest.kt
tests:
  - FoliateMessageParserTest.relocate_populatesTocHref
  - FoliateMessageParserTest.relocate_withoutTocHref_isNull_otherFieldsUnchanged
  - FoliateMessageParserTest.relocate_blankTocHref_isNull
  - FoliateTocIndexTest.exactMatch_returnsThatIndex
  - FoliateTocIndexTest.duplicateHrefs_returnsTheLastMatch          # parent + first child share an href
  - FoliateTocIndexTest.noMatch_butTocExists_returnsZero            # tocIndexFor contract parity
  - FoliateTocIndexTest.nullHref_butTocExists_returnsZero
  - FoliateTocIndexTest.emptyEntries_returnsMinusOne
  - FoliateTocIndexTest.matchIsByteExact_noNormalization_noTrimming
  - FoliateTocIndexTest.cjkHref_matches
  - FoliateTocIndexTest.hrefsDifferingOnlyByFragment_areDistinctRows      # Gate-2 R1 Low
  - FoliateTocIndexTest.hrefWithQuerySuffix_matchesOnlyItself
  - FoliateTocIndexTest.kf8PosUriHrefs_matchOnTheExactOffsetSegment       # kindle:pos:fid:…:off:…
acceptance: >
  The relocate parser gains one nullable field with every existing field's behavior unchanged.
  Matching is byte-exact — two entries whose hrefs differ ONLY in their `#fragment` (or query, or
  the KF8 `:off:` segment) are DISTINCT rows and must not collapse onto one another, which is the
  whole reason no normalization is applied (Gate-2 R1 Low).
  foliateTocIndexFor's contract matches the two existing index helpers at the edges (-1 only when
  there is no TOC; 0 as the best-effort fallback), and resolves a parent/child href tie to the
  LAST (deepest) row.
pr_size: ~60 impl + ~170 test
```

---

### WI-5 — extract `Azw3ReaderChrome` into its own file (pure move)

```yaml
id: WI-5
tier: foundational
depends: []
writes:
  - android/app/src/main/kotlin/com/vreader/app/reader/Azw3ReaderChrome.kt
  - android/app/src/main/kotlin/com/vreader/app/reader/Azw3ReaderActivity.kt
tests:
  - (no new tests — behavior-preserving move; the existing Azw3ReaderChromeUiTest /
     Azw3BookmarkNavTest / Azw3ReaderActivityTest suites are the regression net and must pass
     UNCHANGED, byte-for-byte, including their imports)
acceptance: >
  Azw3ReaderActivity.kt is 569 lines today — already past the ~300-line guideline (rule 00), and
  WI-6 adds to it. This WI moves Azw3ReaderChrome, Azw3NotesBottomChrome, azw3JumpResult and
  azw3JumpDecision into a sibling file in the SAME package, so no import in main or androidTest
  changes (Azw3BookmarkNavTest.kt:107-149 references the two helpers unqualified and must compile
  untouched). Zero behavior change; `git diff` shows moves only. Splitting BEFORE the wiring WI
  keeps WI-6's diff readable and its audit focused on behavior.
pr_size: ~250 lines moved, 0 added
```

---

### WI-6 — host wiring: the AZW3 reader gets a Contents control (BEHAVIORAL)

```yaml
id: WI-6
tier: behavioral
depends: [WI-2, WI-3, WI-4, WI-5]
writes:
  - android/app/src/main/kotlin/com/vreader/app/reader/foliate/Azw3Document.kt
  - android/app/src/main/kotlin/com/vreader/app/reader/Azw3ReaderActivity.kt
  - android/app/src/main/kotlin/com/vreader/app/reader/Azw3ReaderChrome.kt
  - android/app/src/main/kotlin/com/vreader/app/reader/chrome/ReaderBottomChrome.kt
  - android/app/src/main/kotlin/com/vreader/app/reader/nav/EmptyTocProvider.kt   # COMMENT-ONLY (rule 22)
  - android/app/src/main/kotlin/com/vreader/app/reader/nav/TocProvider.kt        # COMMENT-ONLY (rule 22)
  - android/app/src/androidTest/kotlin/com/vreader/app/reader/Azw3ReaderChromeUiTest.kt
  - android/app/src/test/kotlin/com/vreader/app/reader/nav/FoliateTocProviderTest.kt
  - docs/architecture.md
tests:
  - FoliateTocProviderTest.everyEmittedRow_resolvesToAnHrefTarget           # the end-to-end invariant
  - Azw3ReaderChromeUiTest.emptyToc_hidesContents_notesStillPresent          # kept from today
  - Azw3ReaderChromeUiTest.nonEmptyToc_showsContentsControl
  - Azw3ReaderChromeUiTest.tappingContents_opensSheet_listingEveryChapterTitle
  - Azw3ReaderChromeUiTest.nestedEntry_isIndentedPastItsParent               # measured bounds, not depth field
  - Azw3ReaderChromeUiTest.currentChapterRow_carriesTheCurrentMarker_atANonZeroIndex
  - Azw3ReaderChromeUiTest.tappingRow_whenJumpReportsFailure_keepsSheetOpen  # rule 51
  - Azw3ReaderChromeUiTest.tappingRow_whenJumpReportsSuccess_dismissesSheet
  - Azw3ReaderChromeUiTest.contentsAndNotes_bothRenderInTheDesignedOrder
acceptance: >
  The Contents control appears on an AZW3 book with a TOC and is hidden without one — BOTH
  assertions made against the real bottom chrome, i.e. with the `_` at Azw3ReaderActivity.kt:473
  replaced by the real callback (claim W4: without this the control cannot appear no matter what
  tocEntries holds). The Contents slot reuses ReaderBottomChrome's ToolbarIconButton (promoted to
  internal) so the treatment cannot drift from EPUB/TXT. The nesting test measures the on-screen
  left bound of a depth-1 title against a depth-0 title (the #139 acceptance-criterion-7 technique)
  — asserting the depth FIELD would pass on a sheet that ignored it. The current-row test uses a
  non-zero index, because index 0 is the fallback and would pass on a helper that always returns 0.
  Render-death mid-session keeps the TOC visible and degrades a jump to Failed (sheet stays open).
  `everyEmittedRow_resolvesToAnHrefTarget` is the end-to-end form of the invariant WI-3 pins in the
  abstract: FoliateGoToTarget.from(row.canonicalLocator) is an Href — never null, never a Fraction —
  for every row a REAL provider emits (Gate-2 R1 Medium: it lives here, where both dependencies are
  already satisfied, so no WI is ever dispatchable with a known-red test).
  docs/architecture.md: EmptyTocProvider scope corrected to (PDF), the WI-2 parenthetical removed,
  and the stale #139 "host wiring lands in WI-7" sentence at :661-663 fixed.
  COMMENT-ONLY, rule 22 (Gate-2 R1 Low) — two Purpose headers name AZW3 as a no-TOC format and go
  wrong the moment this ships. Both are ALREADY stale for TXT/MD since #139 WI-7, so each loses two
  formats, not one:
    - TocProvider.kt:3 "…[EmptyTocProvider] is the no-TOC provider for TXT/MD/PDF/AZW3 hosts."
    - EmptyTocProvider.kt:1-2 "…for reader hosts without a bridged outline (TXT/MD/PDF/AZW3)"
  Both become "PDF" only, and TocProvider.kt's header names the three real implementations
  (ReadiumTocProvider / TxtMdTocProvider / FoliateTocProvider). No behavior change in either file.
gate5a: >
  Slice verification on the emulator through the PRODUCTION path with the real book staged
  (see §9 R7): Library → tap the AZW3 tile → reader → Contents visible → sheet lists real chapter
  titles. Recorded in the PR body.
pr_size: ~140 impl + ~200 test + ~6 docs
```

---

### WI-7 — real-book connected slice: the jump actually moves the reader (BEHAVIORAL)

```yaml
id: WI-7
tier: behavioral
depends: [WI-6]
writes:
  - android/app/src/androidTest/kotlin/com/vreader/app/reader/foliate/Azw3TocConnectedTest.kt
tests:
  - Azw3TocConnectedTest.realBook_bookReady_carriesANonEmptyToc_withRealLabels
  - Azw3TocConnectedTest.realBook_tocDepthHistogram_isLogged                 # measurement, §9 R3
  - Azw3TocConnectedTest.realBook_goToTocHref_CHANGES_theReportedPosition    # the discriminator
  - Azw3TocConnectedTest.realBook_goToBogusHref_doesNOTChangePosition        # negative control
  - Azw3TocConnectedTest.realBook_goToTocHref_thenRelocateTocHref_matchesThatEntry
  - Azw3TocConnectedTest.realBook_tocParseAndFlatten_areLogged_withElapsedMs # §9 R5
  - Azw3TocConnectedTest.pathologicalTocPayload_200Deep_isParsedOnDeviceWithoutOverflow   # §5.4 stage 2
  - Azw3TocConnectedTest.pathologicalTocPayload_overEntryCap_isRejectedOnDevice
acceptance: >
  Drives a REAL Azw3Document over the real local-only book on the emulator. The load-bearing
  assertion is that the relocate-reported position (cfi/fraction) CHANGES from its pre-jump value
  to the target chapter's neighbourhood — NOT that goTo returned Succeeded. Rationale: foliate's
  view.goTo swallows a failed resolution (foliate-bundle.js:6874-6884 catches and returns
  undefined), so the shim acks ok:true even when nothing moved (§9 R1). The existing
  Azw3GoToSliceTest.kt:90 shows the trap in the codebase already —
  `assertTrue(result is Succeeded || result == Timeout)` passes on total failure. The bogus-href
  negative control proves the positive assertion has teeth. If the fixture is absent the test
  SKIPS (assumeTrue) — so the WI is not done until the run log shows it RAN, not skipped.

  THE PRODUCTION-WEBVIEW HOSTILE-PAYLOAD PROBE (Gate-2 R1 High, §5.4 stage 2). The two
  `pathologicalTocPayload_*` cases need NO pathological book file — authoring a malformed MOBI is
  both hard and beside the point, because the JS stage that a bad FILE would break is out of scope.
  Instead they load the real shell, then `evaluateJavascript` a synthetic message straight down the
  production channel:
      window.__vreaderPost('book-ready', { title:'x', sections:1, toc:<200-deep | over-cap tree> })
  `__vreaderPost` is the shell's own `send()` (reader.html:48), so this rides the REAL
  addWebMessageListener → FoliateBridgePolicy.isTrustedMessage → FoliateMessageParser path on the
  REAL main thread of a REAL WebView. That is the only way to evidence the stage-2 bound on ART,
  whose stack budget is not the JVM's — a green JVM test is not evidence for the device.
  These cases assert ONLY that the parse returns (bounded, no throw, no overflow) and that the
  document does not go Corrupt. They do NOT assert, and must not be worded as asserting, that a
  pathological BOOK opens — see §5.4's CLAIM / NOT CLAIMED block and follow-up F6. They are
  fixture-independent, so they run even when book.azw3 is absent.
pr_size: ~300 test
```

---

### WI-8 — Gate-5b acceptance + evidence file (FINAL, BEHAVIORAL)

```yaml
id: WI-8
tier: behavioral
depends: [WI-7]
writes:
  - android/app/src/androidTest/kotlin/com/vreader/app/reader/Azw3TocAcceptanceTest.kt
  - dev-docs/verification/feature-140-<YYYYMMDD>.md
tests:
  - Azw3TocAcceptanceTest.productionPath_libraryTapToContentsToChapterJump
  - Azw3TocAcceptanceTest.everyAcceptanceCriterionIsAsserted_afterBookReady   # never before
acceptance: >
  Every §11 acceptance criterion exercised end-to-end from app launch through MainActivity (the
  manifest LAUNCHER) — no Activity.intent() shortcut, no debug launcher, no composable invoked
  directly, mirroring feature-139-20260805.md:22-39. Every assertion is made AFTER
  Azw3DocState.Loaded is observed (the #139 lesson: a stuck pipeline must not pass a
  "control is hidden" check). Evidence file per dev-docs/verification/SCHEMA.md, naming the
  user-visible path and recording the real book's entry count + depth histogram + timings.
pr_size: ~250 test + evidence
```

---

### WI-9 — tracker / GH finalization (orchestrator-owned)

```yaml
id: WI-9
tier: n/a (orchestrator)
depends: [WI-8]
writes:
  - docs/features.md            # row 140 → DONE, then VERIFIED after WI-8's evidence lands
  - (gh issue create/comment/close)
acceptance: >
  Row #140 reaches VERIFIED only with the evidence file present and a production path named in it
  (rule 47 Gate 5). Docs-only PR, NO version bump — bumping android/version.properties would make
  it a code path and trip the merge-gate audit hook (the #134 lesson).
```

---

## 8. What could pass while wrong — per acceptance criterion

This section is the plan's answer to "name the green-on-broken test and the assertion that
discriminates". #139's Gate-5 only caught a stuck scan because a test asserted *after* the scan
completed rather than merely that a control appeared
(`dev-docs/verification/feature-139-20260805.md:46`).

| # | Criterion | A test that passes while broken | The discriminating assertion |
| --- | --- | --- | --- |
| 1 | Contents appears for an AZW3 with a TOC | `onNodeWithTag("chrome-contents").assertExists()` with a hand-fed non-empty list — proves nothing about the bundle, the parser, or the host hoist | WI-7/WI-8 assert the row **titles** equal the real book's NCX labels, read out of a real `book-ready`, after `Azw3DocState.Loaded` |
| 2 | Contents stays hidden without a TOC | Asserting "hidden" **before** book-ready — trivially true, and true forever if the pipeline is wedged | Assert only after `Loaded` is observed; additionally assert `chrome-notes` **is** present, proving the chrome rendered at all |
| 3 | Tapping a chapter navigates | `assertTrue(result is Succeeded)`, or `azw3JumpDecision(...) == Succeeded`. **Both are green when nothing moves**: `view.goTo` swallows an unresolvable target (`foliate-bundle.js:6876-6883`) so the shim acks `ok:true`; and `azw3JumpDecision` only inspects target *shape*. The codebase already contains this trap at `Azw3GoToSliceTest.kt:90` | The **reported position must change**: capture `latestRelocate` before the jump, jump, await a new relocate, assert `cfi`/`fraction` differ **and** the new `tocHref` equals the tapped entry's href. Plus a **bogus-href negative control** that must NOT change position |
| 4 | The jump goes to the right chapter, not the book start | Any "position changed" test where the target chapter happens to be chapter 1; and any test where the TOC locator carries `progression = 0.0` and `from()` resolves `Fraction(0.0)` — position "changes" to 0 and the ack is `ok:true` | Jump to a **middle** chapter (index ≥ 2) and assert the post-jump `tocHref` == that entry's href. Plus the JVM guard `FoliateGoToTest.from_hrefWithProgressionZero_stillYieldsHref` |
| 5 | Nested entries render indented | Asserting `entry.depth == 1` on the model — passes on a sheet that ignores depth entirely | Measure the on-screen left bound of the depth-1 title node vs the depth-0 title node (`getUnclippedBoundsInRoot()`, unmerged tree) — #139 criterion 7's technique |
| 6 | Current chapter is highlighted | `onNodeWithTag("toc-current-marker").assertExists()` — passes with `currentTocIndex = 0`, which is both today's hardcoded value (`Azw3ReaderActivity.kt:465`) and the helper's fallback | Navigate to chapter k (k ≥ 2) first, then assert the marker is inside `toc-row-k` |
| 7 | A malformed TOC **payload** is parsed without throwing or overflowing | (a) a parser test over a well-formed payload; (b) **the previous draft's own wording** — "assert the book still opens" — which claims protection the Kotlin bound cannot deliver, since foliate's recursive JS walks run first and a stage-1 failure never posts `book-ready` at all (§5.4) | Feed hostile payloads (`toc: 7`, `toc: [null, 3, {}]`, 200-deep nesting, over-cap entry counts) through the parser (JVM) **and** through the real `addWebMessageListener` path on-device (WI-7), asserting bounded return + no throw + no overflow + document not `Corrupt`. Scope the assertion to the **payload**, never the book file |
| 8 | Nothing regressed | Running only the new suites | Re-run `Azw3ReaderActivityTest`, `Azw3BookmarkNavTest`, `Azw3GoToSliceTest`, `Azw3ReaderChromeUiTest`, `FoliateBundleProvenanceTest` (the SHA pin proves the bundle was not touched) |

---

## 9. Risks + mitigations

| # | Risk | Mitigation |
| --- | --- | --- |
| **R1** | **foliate's `goTo` ack lies.** `view.goTo` catches its own failure and returns `undefined` (`foliate-bundle.js:6874-6884`); `renderer.goTo` no-ops on an unresolved target (`:5488-5492`); the shim's `.then()` therefore acks `ok:true` (`reader.html:66-70`). Every "the jump succeeded" assertion is unreliable. | Verify by **observed position change**, never by the ack (§8 #3). Do not attempt to fix the bundle (it is SHA-pinned) — named follow-up **F2**. |
| **R2** | **`Fraction(0.0)` shadowing the href** → every chapter jumps to the book start, silently and "successfully". | Two independent defenses (§5.2), each with its own JVM test, plus §8 #4's middle-chapter assertion. |
| **R3** | **The only real AZW3 fixture may have a FLAT TOC**, leaving hierarchical depth — the feature's headline difference from #139 — unexercised on real data. Not yet determined at Gate 1 (a calibre probe of `book.azw3` did not complete within the planning budget). | WI-7 **logs the real depth histogram** — that is the measurement. If it is flat: (a) depth logic stays covered by WI-1/WI-2 unit tests over synthetic nested payloads (a legitimate "real books first" exception: a **CI unit test cannot read the gitignored `test-books/`**, AGENTS.md's stated exception), (b) depth *rendering* is already device-verified through #139 criterion 7 on MD (same rows, same sheet, same `depth` field), and (c) the evidence file records the gap explicitly rather than implying coverage. **Do not synthesize an AZW3 just to make a nested TOC**: `mobi`-format fixtures are hard to author correctly and a hand-built one would prove less than the two existing coverages. |
| **R4** | Only **one** real AZW3 exists (`test-books/books/azw3/Bei Tao Yan De Yong Qi - Zi Wo.azw3`, 6.3 MB, CJK) — no English, no `.mobi`, no multi-volume sample. Format-quirk coverage is thin. | Accept + state. AZW3 import/render already ships on this single fixture (#126 VERIFIED). The parser's robustness is carried by the hostile-payload unit matrix, not by fixture breadth. |
| **R5** | **Main-thread cost at `book-ready`**: `FoliateMessageParser.parse` runs on the WebView callback (UI) thread. | The full JSON — TOC included — is **already** parsed there today (`FoliateMessageParser.kt:25`); #140 adds only a bounded walk of an already-built tree, and the flatten runs off-main. Bounds in §5.4. **Measured** in WI-7 and recorded in WI-8's evidence — the #139 lesson (a desktop estimate was ~100× wrong on device) says estimate nothing. |
| **R6** | **A hostile TOC payload could make the book unopenable — via the KOTLIN stage.** A throw or `StackOverflowError` inside the message callback → no `book-ready` consumed → `Azw3DocState.Corrupt` (`Azw3Document.kt:129`), i.e. "This book can't be opened." | Closed for stage 2: the parser is total (never throws) and depth-bounded, pinned by `hostileTocPayload_isParsedWithoutThrowing` on the JVM **and** WI-7's on-device injection probe (ART ≠ JVM stack budget). |
| **R13** | **The SAME failure via the JS stage is NOT closable here.** `assignIDs` (`foliate-bundle.js:6101-6109`), `flatten` (`:6110`) and `serializeTOC` (`:7659-7666`) all recurse over the book's TOC inside `readerAPI.open()`, upstream of every Kotlin bound. A book pathological enough to blow the JS stack fails to open. | **Accept + state, do not pretend to fix.** This is **pre-existing and completely unchanged by #140** — all three walks already run on every AZW3 open today, because `TOCProgress.init` is fed `book.toc` at `view.open` (`:6666-6672`) and `serializeTOC` runs at the `book-ready` post (`:7174`), whether or not Kotlin reads the field. Fixing it means patching a SHA-pinned bundle: follow-up **F6**. §5.4 carries the explicit CLAIM / NOT CLAIMED block, §11 criterion 8 is scoped to the payload, and no test may be named as though it proves a book opens. Gate-2 R1 rated the earlier overclaim **High**. |
| **R7** | **The fixture is invisible to a lane.** `book.azw3` is gitignored (W14) and absent from any fresh worktree; every AZW3 connected test `assumeTrue`-**skips** without it, so an unstaged lane reports a **green run that tested nothing**. | Every connected-lane brief for WI-6/7/8 must stage it first: `cp "/Users/ll/workspace/vreader/android/app/src/androidTest/assets/foliate-spike/book.azw3" "<worktree>/android/app/src/androidTest/assets/foliate-spike/"` (gitignored ⇒ no contamination). WI-7/WI-8 additionally **assert the test RAN** — a skip is a failure, not a pass. |
| **R8** | **Emulator flake / contention.** Compose long-press + gesture tests are timing-flaky on a loaded machine, and driving the emulator during an in-flight `connectedAndroidTest` wedges it (rule 52 Cause D). | These are click/render tests, not long-press (the flaky class), so #125's finding does not apply — but still: one test class per connected run, nothing driving the emulator concurrently, `--rerun-tasks` so Gradle can't report up-to-date on an unchanged task. |
| **R9** | **Duplicate hrefs** (a parent and its first child commonly point at the same anchor) make the current-chapter match ambiguous. | Defined tie-break: **last match wins** (the deepest/most specific row), mirroring `tocIndexFor`'s exact-href rule (`ReaderChromeModel.kt:83-88`). Pinned by `duplicateHrefs_returnsTheLastMatch`. |
| **R10** | **`reader.html` drift**: two copies exist and have already diverged (`androidTest/assets/foliate-spike/reader.html` lacks the #135 shim). Editing the wrong one silently does nothing. | §6.3 names the spike copy explicitly OUT of scope; WI-3's acceptance names the exact path `android/app/src/main/assets/foliate/reader.html`; WI-7's connected round-trip fails if the production shim was not edited. |
| **R11** | **File-size drift**: `Azw3ReaderActivity.kt` is already 569 lines. | WI-5 is a dedicated behavior-preserving split before any wiring lands. |
| **R12** | **Rule-51 ruling on depth indentation** (§3.1) could go the other way at Gate 2. | The plan states the position, the evidence, and the *correct* remedy if rejected (a sheet-level `needs-design` covering #132/#139, WI-6 blocked) — rather than silently assuming reuse or silently shipping flat. |

---

## 10. Backward compatibility

- **No persisted data changes.** The TOC is derived per reader session from a message already in
  flight. No Room entity, no migration, no `contracts/` change, no backup-section change.
- **`Locator` with `href` for an `azw3` format is not a new persisted shape** — TOC-row locators
  are never written to disk in v1 (bookmarks are built from `currentCanonical`, the relocate-derived
  locator, `Azw3ReaderActivity.kt:219-221`). If a future feature *does* persist one (bookmark-from-TOC,
  follow-up F4), the shape already matches what iOS writes for the same rows (§4.1), so cross-platform
  restore is unaffected either way.
- **`FoliateMessage` additions are defaulted**, so every existing construction site (production and
  test) compiles unchanged.
- **`reader.html`'s shim gains a branch**; `{cfi}` and `{fraction}` targets behave exactly as before.
  A stale WebView cache is not a concern (the shell is served from app assets each load).
- **`foliate-bundle.js` is byte-identical**; `FoliateBundleProvenanceTest` keeps passing, which is
  itself the regression proof.
- **Older System WebView**: no new WebView API. A device too old for `addWebMessageListener` still
  lands in `WebViewUnsupported` exactly as today.
- **A book with no NCX** (many `.mobi` files) behaves precisely as today: empty TOC, hidden control.

### Named follow-ups (filed, not implied)

- **F1** — Contents for **PDF**: blocked upstream (`android.graphics.pdf.PdfRenderer` exposes no
  outline API); already tracked by feature **#167** per row #140's own note. `EmptyTocProvider`
  stays alive for it.
- **F2** — make foliate's `goTo` report an unresolvable target instead of swallowing it (bundle
  patch + SHA re-pin + `bundle-patch.md` update). Would turn R1's `ok:true` lie into a real signal
  and let the sheet stay open on a dead chapter link.
- **F3** — surface `relocate.tocLabel` as a chapter name in the AZW3 chrome (iOS does at
  `FoliateReaderContainerView.swift:218`). **Undesigned surface on Android ⇒ a `needs-design` issue
  is the first step, not a code WI.**
- **F4** — bookmark-from-TOC on AZW3 (`TocEntry.kt:4-5` anticipates it).
- **F5** — `bookmarkRowItems(..., tocIndex = null, ...)` at `Azw3ReaderActivity.kt:153`: now that
  AZW3 has a TOC, bookmark rows *could* carry a chapter label like EPUB's. Deliberately out of
  scope (the mirror of #139's F3).
- **F6** — **harden the bundle's own TOC walks** (§5.4 stage 1, §9 R13): make `assignIDs` /
  `flatten` / `serializeTOC` depth-bounded, and make `view.goTo` report an unresolvable target
  instead of swallowing it (F2's other half). Both are edits to the SHA-pinned
  `foliate-bundle.js` and therefore need the patch chain + SHA re-pin +
  `bundle-patch.md` update that `FoliateBundleProvenanceTest.kt:21-24` documents. **Not a
  regression introduced by #140** — it is a pre-existing exposure #140 characterized while
  building on top of it. File as its own row; do not fold it into this feature.

---

## 11. Acceptance criteria (what Gate 5b must exercise)

1. Opening the real AZW3 book shows the **Contents** control in the bottom chrome, reached from
   app launch → Library → tap the tile.
2. The sheet lists the book's real chapters — count and titles match the file's NCX.
3. Nested entries (if the fixture has them; see R3) are indented past their parents, measured on
   screen.
4. Tapping a **middle** chapter navigates: the reader's reported position **changes** and the new
   `tocHref` equals the tapped entry's href.
5. After that jump, reopening Contents highlights **that** row (a non-zero index).
6. A bogus/unresolvable href does **not** move the reader (negative control).
7. An AZW3 with no usable TOC keeps the control hidden — asserted after `book-ready`.
8. A malformed/hostile TOC **payload** — wrong type, null elements, 200-deep nesting, over-cap
   entry count — is parsed without throwing, overflowing, or driving the document to `Corrupt`,
   proven on-device through the real message channel, not only on the JVM. **Scoped deliberately
   to the payload**: a book file whose TOC breaks foliate's own recursive walks fails to open
   today and still would, and #140 neither worsens nor fixes that (§5.4, R13, follow-up F6).
9. Existing AZW3 behavior is intact: page-turn zones, position save/restore, bookmarks (create,
   list, jump), the Notes review sheet, render-death recovery.
10. The TOC parse + flatten cost at `book-ready` is measured and recorded (no open-to-first-page
    regression).

---

## 12. Gate-1 evidence appendix — claims verified against the live codebase

Files read in full while drafting: `Azw3ReaderActivity.kt`, `Azw3Document.kt`, `FoliateBridge.kt`,
`FoliateMessage.kt`, `FoliateMessageParser.kt`, `Azw3LocatorBridge.kt`,
`android/app/src/main/assets/foliate/reader.html`, `TocEntry.kt`, `TocProvider.kt`,
`EmptyTocProvider.kt`, `ReadiumTocProvider.kt`, `TxtMdTocProvider.kt`, `TocContentsSheet.kt`,
`TocSheetRows.kt`, `ReaderChromeScaffold.kt`, `ReaderBottomChrome.kt`, `ReaderChromeModel.kt`,
`Azw3ReaderChromeUiTest.kt`, `Azw3GoToSliceTest.kt`, `Azw3BookmarkNavTest.kt` (relevant sections),
`FoliateBundleProvenanceTest.kt`, `MainActivity.kt` (routing), `AndroidManifest.xml`,
`vreader/Services/Foliate/FoliateTOCConverter.swift`, `vreader/Services/Foliate/FoliateNavSeek.swift`,
`dev-docs/plans/20260804-feature-139-android-txt-md-toc.md`,
`dev-docs/verification/feature-139-20260805.md`,
`dev-docs/designs/vreader-fidelity-v1/project/vreader-panels.jsx` (`TOCSheet`), plus targeted reads
of `android/app/src/main/assets/foliate/foliate-bundle.js` at lines 3480-3510, 3640-3682, 5480-5492,
6650-6690, 6855-6925, 7038-7060, 7159-7210, 7620-7669.

Verified symbol/signature facts (the class Gate 2 checks first):

- `TocEntry(title: String?, depth: Int, pageLabel: String?, canonicalLocator: Locator, epubReadiumLocator: ReadiumLocator?)` — `TocEntry.kt:24-30`. ✔
- `fun interface TocProvider { suspend fun toc(): List<TocEntry> }` — `TocProvider.kt:6-9`. ✔
- `Locator` carries `href`, `progression`, `cfi`, and `fingerprintKey` — `android/identity/src/main/kotlin/vreader/contracts/Locator.kt`. ✔
- `FoliateGoToTarget.from(locator): FoliateGoToTarget?` = cfi → progression — `FoliateBridge.kt:210-214`. ✔
- `Azw3DocState.Loaded(val sectionTotal: Int)` — `Azw3Document.kt:27`. ✔
- `azw3JumpDecision(document: Azw3Document?, canonical: Locator): JumpResult` — `Azw3ReaderActivity.kt:315-322`. ✔
- `ReaderChromeScaffold(… tocEntries: List<TocEntry>, currentTocIndex: Int, onJumpToc: (Int) -> Boolean, bottomChrome: @Composable (onOpenContents: (() -> Unit)?, onOpenNotes: (() -> Unit)?) -> Unit …)` — `ReaderChromeScaffold.kt:93-123`. ✔
- `ReaderBottomChrome(… onOpenContents: (() -> Unit)? = null …)` + `private fun ToolbarIconButton` — `ReaderBottomChrome.kt:61-71`, `:162-182`. ✔
- `BookFormat.azw3` is the routed enum case — `MainActivity.kt:90`. ✔
- `serializeTOC` shape `{label, href, subitems}` and its `?? ""` defaults — `foliate-bundle.js:7659-7666`. ✔

Verified during Gate-2 round 1 (the JS-recursion finding):

- `assignIDs` recurses over `item.subitems` — `foliate-bundle.js:6101-6109`. ✔
- `flatten` is self-recursive — `foliate-bundle.js:6110`. ✔
- `TOCProgress.init` calls both, fed `book.toc ?? []` from `view.open` — `:6112-6114`, `:6666-6672`. ✔
- `serializeTOC` runs at the `book-ready` post, after `bookReady = true` — `:7166-7177`. ✔
- KF8 TOC hrefs are `kindle:pos:fid:XXXX:off:YYYYYYYYYY` — `makePosURI`, `foliate-bundle.js:3380`, used at `:3491`. ✔
- MOBI6 TOC hrefs are `filepos:NNNN` — `foliate-bundle.js:3235`. ✔
- EPUB-path hrefs pass through `decodeURI` — `foliate-bundle.js:1753` — so an href may carry a `#fragment`, a query, or non-ASCII characters. ✔
- `TocProvider.kt:3` and `EmptyTocProvider.kt:1-2` both name AZW3 (and TXT/MD) as no-TOC formats — already stale since #139 WI-7. ✔

---

## 13. Revision history / Gate-2 audit rounds

| Version | Date | Change |
| --- | --- | --- |
| v1 | 2026-08-05 | Gate-1 draft. Not audited. |
| v2 | 2026-08-05 | Gate-2 **round 1** dispositions applied (Codex gpt-5.5/high). Round 1 confirmed the two central claims — the AZW3 host genuinely discards the Contents callback (`Azw3ReaderActivity.kt:473`, so WI-6 aims at the right call site) and the `Fraction(0.0)` progression trap is real, with href-precedence + null-progression the right shape. 1 High, 1 Medium, 3 Low, all closed below. |

### R1 finding dispositions (v1 → v2)

| Sev | Finding | Disposition |
| --- | --- | --- |
| **High** | Hostile-TOC safety was **overclaimed**: the Kotlin depth/entry bounds sit downstream of foliate's own recursive `assignIDs` / `flatten` / `serializeTOC`, so a pathological TOC breaks inside the bundle and the Kotlin bound never runs — yet acceptance criterion 8 promised "never prevents the book from opening". | **Fixed by all three remedies the auditor offered.** (1) §5.4 rewritten into an explicit two-stage model with a `CLAIM` / `NOT CLAIMED` block; the JS stage is named, line-cited, and shown to be **pre-existing and unchanged** by #140 (all three walks already run on every open today). (2) Criterion 8, §8 row 7, WI-1's acceptance and the test name (`hostileTocPayload_neverThrows_bookStillOpens` → `…_isParsedWithoutThrowing`) are all narrowed to the **payload**. (3) New risk **R13** + named follow-up **F6** (bundle patch + SHA re-pin). (4) WI-7 gains **production-WebView coverage** for the half we do own: a 200-deep / over-cap payload injected via the shell's own `__vreaderPost` through the real `addWebMessageListener` → `FoliateMessageParser` path on-device, because ART's stack budget is not the JVM's. |
| **Medium** | The "sequence WI-3 before WI-2" instruction lived only in prose while WI-2's machine-readable `depends: [WI-1]` was unchanged — `scripts/deps-check.sh` reads the token, so a dispatcher could start WI-2 into a known-red test. | **Fixed by moving the test, not by adding a dependency.** `everyEmittedRow_hasAJumpableTarget` is gone from WI-2; the abstract invariant is now `FoliateGoToTest.from_tocShapedLocator_alwaysResolves` in **WI-3** (self-contained), and the end-to-end version is `FoliateTocProviderTest.everyEmittedRow_resolvesToAnHrefTarget` in **WI-6**, which already depends on both. WI-2 and WI-3 are genuinely independent; no WI declares a test that is red at dispatch time. |
| Low | `EmptyTocProvider.kt` / `TocProvider.kt` Purpose headers list AZW3 as a no-TOC format. | Added to WI-6's write-set as **comment-only** edits (rule 22). Both were **already stale for TXT/MD** since #139 WI-7, so each loses two formats. |
| Low | `FoliateTocParser`'s signature was inconsistent (`parse(JsonElement)` vs `parse(detail: JsonObject)`) and the latter leaked the `book-ready` envelope into a would-be reusable parser. | Settled as `parse(tocElement: JsonElement?)`; `FoliateMessageParser` reads `detail["toc"]` and hands over the element. §5.1 and §6.1 now agree; a `null` element is a legal input yielding `emptyList()`, pinned by a renamed test. |
| Low | Href-with-fragment coverage was implicit despite navigation and current-index both depending on byte-exact preservation. | Explicit cases added at all four layers — parser (WI-1), provider (WI-2, incl. the real KF8 `kindle:pos:…` and MOBI6 `filepos:…` shapes), goTo escaping/pass-through (WI-3), and index matching (WI-4, incl. "two hrefs differing only by fragment are distinct rows"). The `decodeURI` at `foliate-bundle.js:1753` is cited as why non-ASCII hrefs are in scope. |

**Coordinator rulings carried forward unchanged**: no `needs-design` for depth indentation (§3.1),
and fixture staging is mandatory in every connected lane brief (§9 R7).
