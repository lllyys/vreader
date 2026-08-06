# Feature #142 — Android AZW3 text selection + highlights/notes (Gate-1 plan)

- **Tracker row**: `docs/features.md` #142 (parity phase 4, box **G2**), status `TODO`, priority High.
- **Unblocks**: #150 (Android AZW3 text-to-speech) — both need a foliate-js → native content bridge
  beyond `relocate`/`book-ready`.
- **iOS parity**: #11 / #64 on the Foliate path (`FoliateSpikeView+Selection.swift`,
  `FoliateHighlightJSBridge.swift`, `FoliateHighlightRenderer.swift`,
  `FoliateHighlightTapResolver.swift`, `FoliateSpikeView+Restore.swift`).
- **Author**: Gate-1 plan only. Nothing implemented.

---

## 0. Row corrections (verified against HEAD `24451540`)

The row's framing is directionally right but three of its concrete claims are stale. Gate 2 should
audit against this section, not the row.

| Row claim | Verified state |
| --- | --- |
| "`Azw3ReaderActivity.kt:404` — text selection … deferred from the AZW3 MVP" | **The comment is real but at line 481**, inside `Azw3ReaderHost`'s tap-zone block. Verbatim: *"WebView-native interactions (link/footnote taps, and text selection once the Foliate annotation adapter lands — deferred from the AZW3 MVP) are reachable in the CENTRE third; the side thirds are page-turn only."* The line number drifted with #140 WI-5/#165 WI-7. |
| "its Notes sheet is hard-wired to an EMPTY snapshot (`AnnotationsSnapshot(emptyList(), emptyList())`)" | **FALSE at HEAD.** `Azw3ReaderActivity.kt:146-151` runs `produceState(AnnotationsSnapshot(emptyList(), emptyList()), bookKey, annotationsRefresh) { value = runCatching { container.annotationsRepository.annotationsForBook(bookKey) }.getOrDefault(...) }` — the empty snapshot is only the *initial value / error fallback*. The AZW3 Notes sheet already reads real rows (and #165 WI-7 already wires annotation **import** into it). The sheet is empty today only because **nothing can create an AZW3 highlight or note**. |
| "AZW3/MOBI is the ONLY reader with no annotation capability" | Half true. AZW3 already has **bookmarks** (#135 WI-7: toggle, Bookmarks tab, jump), a **real Notes review sheet** (#132 WI-7-hosts), **annotation import** (#165 WI-7) and **annotation share** (`shareAnnotations`). What is missing is exactly: (a) highlight/note **creation** from a selection, (b) **decoration rendering** in the WebView, (c) tap-to-edit/remove, and (d) `onJumpToAnnotation`, which `Azw3ReaderChrome.kt:171` passes as **`null`** — an explicit "review-only capability gate". |

Two further verified facts that change the shape of the work versus the row's scope sentence:

1. **The vendored foliate-js bundle already has the entire annotation API.** No bundle change is
   needed (§3, §5).
2. **`reader.html` needs no change either.** Its shim installs a `Proxy` over
   `window.webkit.messageHandlers` whose `get` trap forwards *any* handler name as
   `{name, detail}` JSON to `vreaderHost` (`reader.html:42-46`). The bundle's `post('selection', …)`
   therefore already reaches Kotlin today — `FoliateMessageParserTest.kt:68` asserts it currently
   parses to `FoliateMessage.Other("selection")`.

---

## 1. Problem

The AZW3/MOBI/KF8 reader (`Azw3ReaderActivity` → `Azw3Document` → `FoliateBridge` → foliate-js in a
WebView) cannot create annotations. A user can select text (in the centre third — §7 R1), gets the
bare Android system selection bar, and has no way to highlight it, attach a note, or see an existing
highlight. Every other Android reader can: EPUB via Readium decorations (#123), TXT/MD via the
Compose text engine (#124/#125), and all of them share one storage + review + backup pipeline that
AZW3 rows are already welcome in.

The missing piece is **one adapter**: foliate-js `selection` / `annotation-show` events → the
existing `AnnotationsRepository`, and stored highlights → foliate's `readerAPI.addAnnotation`. This
is a fourth adapter onto an existing system, not a new system.

---

## 2. Rule 51 — design coverage

**Gap: none.** Every surface and state this feature needs is depicted in a committed bundle, and the
composables that render them are already shipped.

| Needed state | Depicted at | Already implemented as |
| --- | --- | --- |
| In-reader floating popover over a live selection, anchored under it, downward notch | `dev-docs/designs/vreader-fidelity-v1/project/vreader-android-annotations.jsx:32-146` (`SelectionReader` + `SelectionPopover`) | `annotations/SelectionPopover.kt` |
| SELECT mode: 5-colour dot row + `+`, actions Highlight · Note · Copy · Share | ibid. `mode='select'` (`:131-139`) | `SelectionPopover.ActionRow(editMode=false)` |
| NOTE mode: "ADD NOTE" label, inline field, Cancel/Save | ibid. `mode='note'` (`:108-121`) | `SelectionPopover.NoteCompose` |
| EDIT mode (tapped an existing highlight): Note · Copy · Share · **Remove** (danger red) | ibid. `mode='editHL'` (`:124-130`) | `SelectionPopover.ActionRow(editMode=true)` |
| Active-colour ring on the selected dot | ibid. `:97` | `ColorRow` |
| An existing highlight rendered as a colour **wash** on the text | ibid. `:51-52` (`existing` branch) | foliate `Overlayer.highlight` → `fill: <colour>` at `--overlayer-highlight-opacity: .3` |
| Notes-sheet rows for the created rows | ibid. `HighlightCard` `:167`, `StandaloneNoteCard` `:205` | `annotations/AnnotationCards.kt` via `AnnotationsReviewSheet` |
| Highlight popover geometry / artboards | `vreader-highlight-popover.jsx`, `highlight-popover-canvas-artboards.jsx` | same composable |

Two recorded non-gaps (pre-existing decisions this feature does **not** change):

- The design's SELECT row includes a **Translate** action; the shipped `SelectionPopover` omits it
  (`SelectionPopover.kt:127-128` — "routes to #119 … omitted here rather than shipped as a dead
  no-op"). AZW3 inherits that omission verbatim.
- The design's existing-highlight treatment shows a wash **plus a left rule** (`inset 2px 0 0`).
  foliate's `Overlayer.highlight` paints the wash only, exactly as Readium's `Decoration.Style.
  Highlight` does on EPUB. No new element is introduced; this is engine treatment, not a surface.

No `needs-design` issue is required. (Nothing in this plan invents a dialog, toast, error surface, or
placeholder — every failure path degrades to "nothing happens", the rule-51 posture #135/#140 already
established for this host.)

### 2.1 Adjudicated: the tapped-highlight surface (Gate-2 round 1, finding 4)

`highlight-popover-canvas-artboards.jsx:666-669` specifies a *separate* highlight-action card, with
**"Trigger: Single tap on an existing highlight. Long-press route stays on the selection popover."**
Routing a tapped highlight into `SelectionPopover`'s EDIT mode therefore does contradict that bundle.
Verified — the design text is real.

**#142 nonetheless keeps `SelectionPopover` EDIT mode, by adjudication.** The divergence is
**pre-existing and app-wide**, not introduced here: `SelectionPopoverViewModel` ships
`PopoverMode.SELECT/NOTE/EDIT`, and both `ReaderActivity` (EPUB, `:599-608` `onHighlightTapped` →
`popoverVm.showForExisting(...)`) and `TxtReaderActivity` already route a tapped highlight into EDIT
mode today. iOS shipped the unified card as #64; Android never adopted it. Building it inside #142
would make **AZW3 the only Android format on the designed surface** — a worse inconsistency than the
one it fixes, and a scope expansion for a parity WI.

Cross-format adoption is tracked as **feature #175** (`docs/features.md:227`, "Android unified
highlight-action popover — tap-on-highlight uses the SELECTION popover's EDIT mode on every format,
which the committed design says is the long-press route"). #142 inherits the current behaviour and
converts with every other format when #175 lands. This is a deliberate, recorded acceptance — not an
oversight, and not a rule-51 violation (no new or invented surface is introduced).

---

## 3. What already exists (verified) — the interfaces the adapter plugs into

### 3.1 The vendored bundle — annotation API present, unmodified

`android/app/src/main/assets/foliate/foliate-bundle.js`, SHA-256
`c9b0e101435b1b1757eade7d06633bf7ba382980327574067ae449273e8cf3fa` (pinned by
`FoliateBundleProvenanceTest`). Verified by reading the bundle, not the docs:

| Bundle site | Emits / accepts |
| --- | --- |
| `:7079-7120` | `post("selection", { collapsed:false, text, cfi, index, rect:{x,y,width,height} })` after a **300 ms** `setTimeout` debounce on `selectionchange`; `post("selection", { collapsed:true })` when the selection collapses. |
| `:7069-7074` | `post("annotation-show", { value, index })` when the user taps an existing overlay (fired from `view.js:404-428`'s capture-phase hit test, exact then a 44 px tolerance pass). |
| `:7058-7062` | `post("create-overlay", { index })` each time a section mounts its overlayer. |
| `:7063-7068` | `draw-annotation` handler: `draw(Overlayer.highlight, { color: annotation.color \|\| "yellow" })`. |
| `readerAPI` (`:7161+`, `:7212-7220`) | `addAnnotation(a)`, `deleteAnnotation(a)`, `showAnnotation(a)`, `deselect()`. |
| `view.js:366-395` | `addAnnotation({value})` resolves `value` as a CFI → per-section overlayer → `overlayer.remove(value)` then re-add. **Silently no-ops when that section's overlayer does not exist yet** (`if (obj)`), which is why re-applying on `create-overlay` is required (§4.4). |
| `overlayer.js:164-168` | `Overlayer.highlight` sets `fill: <color>` — any CSS colour, so Android's hex palette works directly. |

**Conclusion: the design requires NO modification to the vendored bundle.** The bundle SHA pin, the
`allow-scripts`-stripping patch, and `bundle-patch.md` are untouched, so the rule-54 / #126
supply-chain posture is unchanged and `FoliateBundleProvenanceTest` keeps passing as-is.

### 3.2 The secure channel — unchanged

`FoliateBridge.attach()` (`:132-142`):
`WebViewCompat.addWebMessageListener(webView, "vreaderHost", setOf(FoliateAssetServer.SHELL_ORIGIN))`,
gated by `FoliateBridgePolicy.isTrustedMessage(sourceOrigin, isMainFrame)`, feeding
`FoliateMessageParser.parse`. **`addJavascriptInterface` is never used and is not introduced.**
Outbound is `webView.evaluateJavascript(js, null)` with every book-derived string JSON-encoded via
`Json.encodeToString(String.serializer(), s)` (the `jsString` / `foliateSetStylesJs` seam).

### 3.3 The annotation domain — reused verbatim, zero changes

| Interface | Signature at HEAD | Use here |
| --- | --- | --- |
| `AnnotationsRepository.addHighlight` | `suspend (bookKey: String, color: AnnotationColor, selectedText: String, locator: Locator, anchor: AnnotationAnchor?, note: String? = null): HighlightRecord` | create |
| `.updateHighlight` / `.removeHighlight` / `.findHighlight` | `suspend (id, color, note)` / `suspend (id)` / `suspend (id): HighlightRecord?` | edit / remove / tap-resolve |
| `.addNote` | `suspend (bookKey, content, locator, anchor): NoteRecord` | standalone note |
| `.highlights(bookKey)` | `Flow<List<HighlightRecord>>` | re-decoration source |
| `.annotationsForBook(bookKey)` | `suspend (bookKey): AnnotationsSnapshot` | already wired in the AZW3 host |
| `AnnotationAnchor.Epub` | `data class Epub(href: String, cfi: String, serializedRange: EpubSerializedRange? = null, readiumLocatorJSON: String? = null)` | the AZW3 anchor (§4.2) |
| `AnnotationColor` | enum `yellow/green/blue/pink/red`, `key`, `dotHex`, `washHex`, `ruleHex`, `palette`, `DEFAULT` | popover + `Overlayer.highlight` colour |
| `SelectionPopoverViewModel` | `showForSelection(x,y)`, `showForExisting(color, note, x, y)`, `selectColor`, `beginNote`, `updateNoteDraft`, `dismiss`; `state: StateFlow<SelectionPopoverState>` | popover state |
| `SelectionPopover(state, actions, modifier)` + `SelectionPopoverActions` | 9 callbacks | popover UI |
| `ReaderChromeScaffold` / `Azw3ReaderChrome` | `annotations: AnnotationsSnapshot`, `onJumpToAnnotation: ((AnnotationItem) -> Unit)?` | the Notes sheet; the null becomes non-null in WI-6 |
| `azw3JumpDecision(doc, locator)` / `Azw3Document.goTo(locator)` | `#135 WI-7` | jump-to-annotation, reused unchanged |
| Room `HighlightEntity` / `AnnotationNoteEntity` + `(profileKey, anchorKey)` unique index | — | **no schema change, no migration** |

### 3.4 The two precedents, and how AZW3 differs

| | EPUB (#123) | TXT / MD (#124/#125) | **AZW3 (this feature)** |
| --- | --- | --- | --- |
| Selection source | `EpubNavigatorFragment.currentSelection()` (suspend, pull) | `TxtSelectionController` — Compose pointer geometry → source UTF-16 range | **push**: a debounced `selection` message over the existing web-message channel |
| Anchor | `AnnotationAnchor.Epub(href, cfi, readiumLocatorJSON = locator.toJSON())` | `AnnotationAnchor.Text(sourceUnitId, startUTF16, endUTF16)` | `AnnotationAnchor.Epub(href = "", cfi = foliateCfi)` — **iOS parity** (`FoliateSpikeView+Selection.swift:118-128`) |
| Render | `DecorableNavigator.applyDecorations(list, "highlights")` — whole-set, idempotent | Compose `TxtHighlightWash` recompute | `readerAPI.addAnnotation({value, color})` **per record**, re-applied per section on `create-overlay` |
| Tap-to-edit | `DecorableNavigator.Listener.onDecorationActivated` → id + rect | `TxtHighlightHitTester` on a source offset | `annotation-show` → CFI → resolve to id (**iOS `FoliateHighlightTapResolver` analog**) |
| System selection bar | suppressed via Readium's `selectionActionModeCallback` | n/a (custom selection) | must be suppressed at the **Activity** level (§7 R2) |

The AZW3 adapter differs from both in three ways that drive the WI split: it is **push not pull**
(so a debounce exists and `waitForIdle` cannot be used to wait for it), its render surface is
**per-section and lazily created** (so a single apply is not enough), and its selection geometry
arrives in the **section iframe's** coordinate space (§7 R3, the bug #108 class).

---

## 4. Surface area

### 4.1 `reader/foliate/FoliateMessage.kt` + `FoliateMessageParser.kt` — MODIFY (WI-1)

Three new typed cases; everything else untouched. All three currently land in `Other`.

```kotlin
/** A finished text selection in the rendered book (bundle `post("selection", …)`).
 *  [cfi] is foliate's CFI for the range; for MOBI/KF8 it is
 *  `CFI.joinIndir(CFI.fake.fromIndex(index), CFI.fromRange(range))`. [rect] is in the SECTION
 *  document's coordinate space (see Azw3SelectionAnchor). */
data class Selection(
    val text: String,
    val cfi: String,
    val sectionIndex: Int,
    val rect: SelectionRect?,
) : FoliateMessage

/** The selection collapsed (user tapped away). */
data object SelectionCleared : FoliateMessage

/** The user tapped an existing overlay (bundle `post("annotation-show", …)`); [value] is the CFI
 *  the annotation was added under. */
data class AnnotationShow(val value: String, val sectionIndex: Int) : FoliateMessage

/** A section mounted its overlayer — stored annotations for it must be (re)applied. */
data class OverlayCreated(val sectionIndex: Int) : FoliateMessage

data class SelectionRect(val x: Double, val y: Double, val width: Double, val height: Double)
```

Parser branches, following the file's existing strictness conventions (`str` rejects blank / JSON
`null` / non-string; `dbl` rejects quoted and non-finite; `bool` accepts only the literals):

```
"selection" ->
    if (detail.bool("collapsed") == true) SelectionCleared
    else Selection(
        text  = detail.str("text") ?.takeIf { it.length <= MAX_SELECTION_CHARS } ?: return null,
        cfi   = detail.str("cfi")  ?.takeIf { it.length <= MAX_CFI_CHARS }       ?: return null,
        sectionIndex = detail.int("index") ?: 0,
        rect  = detail.rect("rect"),        // null when absent/partial/non-finite
    )
"annotation-show" -> AnnotationShow(detail.str("value")?.takeIf { it.length <= MAX_CFI_CHARS } ?: return null,
                                    detail.int("index") ?: 0)
"create-overlay"  -> OverlayCreated(detail.int("index") ?: 0)
```

`MAX_SELECTION_CHARS = 8_000`, `MAX_CFI_CHARS = 4_000` (rationale in §8). These are **field** caps;
the **raw-message** cap that must precede `parse` lives at the bridge — see §4.3 and §8.

### 4.2 `annotations/Azw3AnnotationMapper.kt` — NEW, pure, JVM-tested (WI-2)

```kotlin
/** The persistable inputs derived from a foliate selection (the EpubAnnotationMapper analog). */
data class Azw3SelectionInputs(
    val selectedText: String,
    val locator: Locator,
    val anchor: AnnotationAnchor.Epub,
)

object Azw3AnnotationMapper {
    /** Selection message + book → persistable inputs, or null when unusable (blank text/cfi). */
    fun selectionToInputs(selection: FoliateMessage.Selection, book: Book): Azw3SelectionInputs?

    /**
     * The CFI to hand `readerAPI.addAnnotation`/`deleteAnnotation` for a stored record.
     * Precedence: `(anchor as? Epub)?.cfi` → `record.locator.cfi` → null.
     * The LOCATOR fallback is load-bearing: the backup wire carries NO anchor, so
     * `AnnotationsRepository.restoreAnnotations` inserts every restored row with `anchor = null`
     * (`AnnotationsRepository.kt:177,191`). Without the fallback, every AZW3 highlight restored
     * from a backup would be invisible forever.
     */
    fun cfiFor(record: HighlightRecord): String?

    /** A tapped CFI → the matching highlight id, or null (iOS FoliateHighlightTapResolver analog:
     *  walk in order, first exact match wins, blank cfi is a no-match). */
    fun highlightIdForCfi(cfi: String, records: List<HighlightRecord>): String?
}
```

The locator built by `selectionToInputs`, matching iOS `FoliateSpikeView+Selection.swift:129-142`
field for field:

```kotlin
Locator(
    contentSHA256 = book.contentSHA256,
    fileByteCount = book.fileByteCount,
    format        = BookFormat.azw3.name,
    href          = null,          // foliate exposes no stable per-section href in a selection
    progression   = null,          // the selection event carries none
    cfi           = selection.cfi,
    textQuote     = selection.text,
)
AnnotationAnchor.Epub(href = "", cfi = selection.cfi)   // serializedRange/readiumLocatorJSON stay null
```

**What round-trips, precisely.**

- *Durable*: `cfi` (stored twice — `Locator.cfi` and `anchor.cfi`) and `selectedText`. The CFI is
  what re-creates the visual: it is handed straight back to `readerAPI.addAnnotation`, the same
  string the bundle minted, so the re-render is the inverse of the creation by construction.
- *Derived, not stored*: `sectionIndex` — for MOBI/KF8 the CFI's first step **is** the spine index
  (`epubcfi.js:333-336`, `fake.fromIndex(i) = /6/((i+1)*2)`), and `view.addAnnotation` recovers it
  via `resolveNavigation`. Storing it would be a second, drift-prone source.
- *Not stored*: the selection `rect` (view-only, valid for one layout) and any DOM range — foliate
  exposes none on this path, which is exactly why iOS uses a placeholder `EPUBSerializedRange` and
  Android leaves `serializedRange = null`.
- *Dedupe*: `profileKey = "$bookKey:${sha256(locator.canonicalJson())}"` and `canonicalJson()`
  includes `cfi` (`Locator.kt:94-109`), so two different selections never collide and re-highlighting
  the identical range upserts through the `(profileKey, anchorKey)` unique index.
- **Cross-platform note (verified, not assumed)**: an AZW3 CFI is portable to iOS *for the same
  file* because both platforms run the same `mobi.js`/`epubcfi.js` and neither has a package
  document, so both synthesize the same `fake` CFI. It is **not** carried by the anchor across a
  backup (§9) — it survives in `Locator.cfi`.

### 4.3 `reader/foliate/FoliateBridge.kt` — MODIFY (WI-1 gate, WI-3 methods)

**WI-1 — the raw-message gate, before `parse` (Gate-2 round 1, finding 1).** Verified: `:137` calls
`FoliateMessageParser.parse(message.data ?: "")`, and `parse` (`:26`) immediately runs
`json.parseToJsonElement(raw).jsonObject`. Field-level caps cannot help there — they run after the
whole document has been built into a `JsonElement` tree. So the listener gains a length gate first:

**The v2 GLOBAL cap is withdrawn (Gate-2 round 2, H1).** Round 2's arithmetic is right and the
conclusion goes further than "raise the number": **no finite global ceiling can do both jobs.**

*Why.* The bundle serialises each TOC row as `{"label":"…","href":"…","subitems":[…]}`
(`foliate-host.js:846-851` → `foliate-bundle.js:7659`), i.e. **36 chars of fixed structure + 1
separator** per row. With `FoliateTocParser.MAX_TOC_ENTRIES = 10_000`:

```
raw(book-ready) ≈ 37·N + 2·B·E·N + envelope        N = 10_000 rows
  B = 200, E = 1  →   370_000 + 4_000_000  =  4_370_000 chars   ← ABOVE the v2 cap of 4_194_304
  B = 200, E = 6  →   370_000 + 24_000_000 = 24_370_000 chars   (worst-case \uXXXX escaping)
```

(`B` = per-row label/href length, `E` = JSON escape expansion.) Round 2's ~4,370,112 figure
reproduces exactly at `B = 200, E = 1`. **But `B` has no upper bound anywhere in the codebase or the
contract** — a single 1 MB TOC label is legal today. And round 2 is also right that the auditor's
other fix is closed: `FoliateTocParser.kt:96-100` preserves labels and hrefs *"byte-for-byte"*
deliberately, because `relocate.tocHref` matching is byte-exact (#140), so capping those strings
would silently break current-chapter highlighting.

So any global number is a **guess about what counts as legitimate**, and guessing low means a
`book-ready` is dropped and the reader never reaches `Loaded` — a worse outcome than the threat the
cap addresses.

**The cap is therefore PER MESSAGE NAME, and it applies only to the names #142 introduces.**

| Message | Ceiling | Basis |
| --- | --- | --- |
| `selection` | **131_072** | derived below |
| `annotation-show` | **65_536** | derived below |
| `create-overlay` | **1_024** | derived below |
| `book-ready`, `relocate`, `goto-ack`, `error`, `bridge-ready`, `tap`, everything else | **uncapped** | today's behaviour, unchanged |

The dividing line is principled, not arbitrary: **a message may be tightly capped only if this
feature already bounds every variable-length field it carries.** `book-ready` (TOC labels/hrefs) and
`relocate` (`tocHref`) carry byte-exact, unbounded, book-derived identifiers that #140 depends on;
they stay uncapped, exactly as they are today — #142 does not touch them, so it introduces no new
exposure there. The three names above carry only fields §4.1 already caps.

```kotlin
// FoliateBridgePolicy — pure, JVM-testable, beside the other boundaries.
const val NAME_SNIFF_WINDOW = 256

/** The raw ceiling for [raw]'s message name, or null = uncapped. Reads at most
 *  [NAME_SNIFF_WINDOW] chars and NEVER parses: it locates the `"name"` key and reads the following
 *  JSON string literal. An unrecognised, absent or unsniffable name yields null (uncapped), so a
 *  shim change or a future message type can never break the reader — only the three names this
 *  feature introduces are bounded. */
fun rawCeilingFor(raw: String): Int?

// FoliateBridge.attach()
) { _, message, sourceOrigin, isMainFrame, _ ->
    if (FoliateBridgePolicy.isTrustedMessage(sourceOrigin?.toString(), isMainFrame)) {
        val raw = message.data ?: ""
        val ceiling = FoliateBridgePolicy.rawCeilingFor(raw)
        if (ceiling == null || raw.length <= ceiling) {
            FoliateMessageParser.parse(raw)?.let { _messages.tryEmit(it) }
        }   // else: dropped silently, exactly like an unparseable message
    }
}
```

**Deriving the three ceilings** (each must admit everything §4.1's field caps admit, or the raw cap
would silently shrink them; `E = 6` is worst-case `\uXXXX` escaping of every character):

```
selection        skeleton 222 chars (counted: envelope 30 + collapsed 18 + text/cfi keys 19
                   + index 20 + rect{4 doubles ≤24 each} 133 + close 2), round to 256
                 + text 8_000 × 6 = 48_000
                 + cfi  4_000 × 6 = 24_000        → worst case 72_256 → ceiling 131_072 (≈1.8×)
annotation-show  skeleton ~70, round to 128
                 + value 4_000 × 6 = 24_000       → worst case 24_128 → ceiling  65_536 (≈2.7×)
create-overlay   skeleton 56 (no variable field)  → worst case     56 → ceiling   1_024 (≈18×)
```

**Honest scoping of what this buys — two limits, stated rather than buried.**

1. `WebMessageCompat.data` is *already* a materialised `String` when the listener runs — the WebView
   built it. No host-side cap can prevent **receipt**. What the gate prevents is the JSON-tree
   amplification in `parseToJsonElement` (a `JsonElement` tree is several times the source string)
   and everything downstream of it.
2. The name sniff is a **best-effort classifier for well-formed messages from our own shim, not an
   adversarial parser.** A payload that hides its `"name"` past the sniff window falls through to
   *uncapped* — i.e. today's behaviour. That is acceptable because the load-bearing defense is not
   this cap: it is the bundle patch (book sections run no script, so they cannot post at all) plus
   the origin/main-frame gate, exactly as `FoliateBridgePolicy`'s own docs state. Anyone able to
   forge a shell-origin message already controls the shell page and has `evaluateJavascript`-
   equivalent power, at which point the cap is moot. The cap's job is to bound the **foreseeable
   pathological** case (a multi-megabyte selection) without regressing the **foreseeable legitimate**
   case (a multi-megabyte TOC).

**WI-3 — three typed methods + two shared pure JS builders**, mirroring the `foliateSetStylesJs` seam
so the escaping a unit test pins is the exact escaping production runs:

```kotlin
/** Paint a stored highlight. [cfi] is book-derived → JSON-escaped; [cssColor] comes from the
 *  AnnotationColor enum (never free text). */
fun addAnnotation(cfi: String, cssColor: String) = eval(foliateAddAnnotationJs(cfi, cssColor))
fun deleteAnnotation(cfi: String)                = eval(foliateDeleteAnnotationJs(cfi))
fun deselect()                                   = eval("try{readerAPI.deselect&&readerAPI.deselect()}catch(e){}")

/** WI-5 §4.5.1 — one-shot JS whose RESULT is returned (the existing eval() discards it).
 *  MAIN-THREAD only; [onResult] is posted on the main thread and is dropped after teardown (§4.5.2). */
fun evalForResult(js: String, onResult: (String?) -> Unit)

// file-level, pure, unit-pinned:
fun foliateAddAnnotationJs(cfi: String, cssColor: String): String
fun foliateDeleteAnnotationJs(cfi: String): String
```

### 4.4 `reader/foliate/Azw3Document.kt` — MODIFY (WI-4)

```kotlin
/** Fired on a finished selection (main thread). Null payload = the selection collapsed. */
var onSelection: ((FoliateMessage.Selection?) -> Unit)? = null
/** Fired when the user taps an existing overlay; carries the annotation's CFI. */
var onAnnotationShow: ((String) -> Unit)? = null

/** The full set of highlights to paint, as (cfi → cssColor). Replaces the previous set: newly
 *  absent cfis are deleted, present ones (re)added. Recorded so a section that mounts LATER, a
 *  fresh book-ready, or a render-death recreate re-paints — mirroring how pendingStylesCss works
 *  for #129 and how iOS refires on every create-overlay (FoliateSpikeView+Restore.swift:22-27). */
fun setAnnotations(decorations: Map<String, String>)
fun deselect()
```

`handle(message)` gains:

- `is Selection` → `onSelection?.invoke(message)`; `SelectionCleared` → `onSelection?.invoke(null)`
- `is AnnotationShow` → `onAnnotationShow?.invoke(message.value)`
- `is OverlayCreated` → re-apply the recorded decoration set (the newly mounted section's overlayer
  now exists, so its CFIs resolve)
- `BookReady` → after `restoreOrInit()` + `pendingStylesCss`, apply the recorded decoration set

### 4.5 `reader/Azw3ReaderAnnotations.kt` — NEW (WI-5, WI-6)

`Azw3ReaderActivity.kt` is already 541 lines and `Azw3ReaderChrome.kt` 246; the #140 WI-5 split
precedent applies. Same package `com.vreader.app.reader`, so no call-site or test import changes.

```kotlin
/** Host-owned annotation state + side effects for the AZW3 reader. The Activity supplies the
 *  repository, the live Azw3Document and the book; this owns the popover VM, the pending
 *  create/edit context and the persist→decorate loop. Scope discipline: §4.5.2. */
@Stable
internal class Azw3AnnotationHost(
    private val annotations: AnnotationsRepository,
    /** Repository WRITES only. App-scoped so a persist survives the reader being finished/rotated.
     *  Nothing Activity-, WebView- or Composition-bound may be captured by work launched here. */
    private val writeScope: CoroutineScope,
    /** Reads that feed the UI + every WebView call. Lifecycle/composition-bound; cancelled on dispose. */
    private val uiScope: CoroutineScope,
) {
    val popoverVm = SelectionPopoverViewModel()
    fun onSelection(selection: FoliateMessage.Selection?, anchor: Offset?)
    fun onAnnotationTapped(cfi: String, records: List<HighlightRecord>, anchor: Offset?)
    fun createHighlight(book: Book, color: AnnotationColor, note: String?)
    fun editHighlightColor(color: AnnotationColor); fun saveNote(note: String?)
    fun removeCurrentHighlight(); fun selectedTextForAction(): String?
    fun dismiss()
    /** Called from the host's onDispose: drops pending context and refuses all later callbacks. */
    fun teardown()
}

/** The floating popover overlay for the AZW3 body — the EPUB PopoverOverlay's clamp + above/below
 *  flip, reused verbatim (design vreader-fidelity-v1/project/vreader-android-annotations.jsx). */
@Composable
internal fun Azw3PopoverOverlay(host: Azw3AnnotationHost, actions: SelectionPopoverActions)
```

#### 4.5.1 Selection anchoring — the full-rect mapping, with NO bundle change (finding 5)

Round 1 was right that a `frameLeft`-only probe is inadequate: it ignores the frame's vertical
offset, writing mode, RTL, scrolled-vs-paginated layout, and multi-rect selections. The v1 design is
withdrawn. It was also right that the *bundle-side* fix would require touching the bundle. **It does
not follow that a host-side fix is impossible — and the repo already contains proof that it is not.**

Two verified facts settle this:

1. **Injected shell JS has full DOM access into the mounted section document.**
   `Azw3DomProbe.evalJs` (`androidTest/.../Azw3DomProbe.kt:156-174`) calls
   `webView.evaluateJavascript(js)` on the **shell** WebView, and `PROBE_JS` (`:58-120`) reaches
   `document.getElementById('view').renderer.getContents()[0].doc`, calls `d.createRange()`,
   `selectNodeContents`, and `getClientRects()` inside it. Section documents are `blob:` URLs, which
   inherit the shell origin, and the sandbox keeps `allow-same-origin` — this is a shipped, passing
   connected test (#156 WI-3), not a hypothesis.
2. **The frame-to-host mapping is reachable from that same context.** The bundle's own
   `mapTapToHostViewport(doc, clientX)` is **module-scope in the shell page** (`foliate-bundle.js:7141-7158`
   / `foliate-host.js:241-268`) and does exactly `doc.defaultView.frameElement.getBoundingClientRect()`
   plus `frameElement.ownerDocument.defaultView.innerWidth`. Whatever the bundle can read from the
   shell, injected shell JS can read too.

So the host computes the anchor itself, from the **live** layout, in JS we own:

```
(function(){ try{
  var cs = document.getElementById('view')?.renderer?.getContents?.();
  if(!cs || !cs.length) return null;
  // the section that owns a live, non-collapsed selection
  var owner = cs.find(c => { var s = c?.doc?.getSelection?.();
                             return s && !s.isCollapsed && s.rangeCount; });
  if(!owner) return null;
  var doc = owner.doc, sel = doc.getSelection(), r = sel.getRangeAt(0);

  // Round-2 M1(2): reject DEGENERATE rects. A real range does produce zero-area rects (a range
  // ending at a line break, a not-yet-laid-out element). Mirrors the existing probe's
  // `if(!(rs[i].width>0.5)) continue;` (Azw3DomProbe.kt:91), widened to both axes.
  var rects = [], all = r.getClientRects();     // per-LINE, not the bounding box
  for (var i = 0; i < all.length; i++) {
    if (all[i].width > 0.5 && all[i].height > 0.5) rects.push(all[i]);
  }
  if (!rects.length) return null;

  // Round-2 M1(1): the FOCUS edge is not always the range END — the Selection API defines
  // backward selections (drag right-to-left / bottom-to-top), where focus is the range START.
  // Prefer the standard `direction`; fall back to the bundle's own idiom
  // (`selectionIsBackward`, foliate-bundle.js:4280-4285 — module-scoped, so replicated, not called).
  var backward;
  if (typeof sel.direction === 'string' && sel.direction !== 'none') {
    backward = sel.direction === 'backward';
  } else if (sel.anchorNode && sel.focusNode) {
    var probe = doc.createRange();
    probe.setStart(sel.anchorNode, sel.anchorOffset);
    probe.setEnd(sel.focusNode, sel.focusOffset);
    backward = probe.collapsed;
  } else { backward = false; }
  var edge = backward ? rects[0] : rects[rects.length - 1];

  var win = doc.defaultView, fe = win && win.frameElement;
  var dx = 0, dy = 0;
  if (fe) { var fr = fe.getBoundingClientRect(); dx = fr.left; dy = fr.top; }
  var host = fe ? fe.ownerDocument.defaultView : win;
  if (!host || !isFinite(host.innerWidth) || host.innerWidth <= 0) return null;
  return JSON.stringify({ x: edge.left + edge.width/2 + dx, y: edge.bottom + dy,
                          w: host.innerWidth, h: host.innerHeight });
} catch(e){ return null; } })()
```

What this covers, and — separately — what it only argues:

**Covered, and exercised by the WI-5 connected test:**

- **Frame top** — `fr.top` is added, not just `fr.left`.
- **Multi-rect selections** — `getClientRects()` gives one rect per line/fragment; the degenerate
  ones are filtered and the **focus-edge** rect is chosen by direction. `Azw3ProbeSupport.kt:30-45`
  documents why document order must not be re-sorted here: in multi-column layout every column
  restarts at the same `top`, so a positional sort interleaves columns. The whole-bounding-box
  approach is explicitly rejected.
- **Backward (right-to-left drag) selections** — anchored at the range start, per above.
- **Paginated multi-column** — no transform is *reasoned about*; the rects come from the engine's
  actual layout. Gated on a **non-first column** (§10).
- **No `frameElement`** (non-iframe renderer) — `dx = dy = 0` and the rects are already host-relative,
  the same fallback the bundle documents.
- **Coordinate space** — `reader.html:5` pins `initial-scale=1, maximum-scale=1, user-scalable=no`, so
  1 CSS px = 1 dp. `SelectionPopoverState.anchorX/anchorY` are dp (the EPUB host divides Android px by
  `density` to get there), so the returned values are used **directly** with no density conversion,
  and the overlay is drawn in the same body `Box` that hosts the WebView, so both are body-local.

**Residual limits — argued but NOT tested, and listed as limits rather than claimed as coverage
(round-2 M1, third point):**

- **RTL text.** The "rects come from the engine's layout" argument applies, and the focus-edge choice
  is direction-based rather than position-based, so it should hold. But **no RTL book exists in
  `test-books/`**, so this is untested. Listed as a residual limit.
- **Vertical writing modes (`writing-mode: vertical-rl`, plausible for a CJK Kindle title).** This one
  is weaker than an untested-but-sound case, and the layout argument does **not** rescue it: the code
  anchors at `edge.bottom`, i.e. "below the selection", which is a *horizontal-writing* assumption.
  In a vertical mode the block direction is horizontal, so the correct anchor edge would be the
  inline-start/end side, not the bottom. The rects would still be correct; the *edge choice* would
  not. No vertical fixture exists (the one real AZW3 is modern horizontal Chinese), so this is
  **explicitly out of scope** and recorded as a named follow-up rather than silently covered.
  Degradation is benign — the popover is misplaced but clamped on-screen, never lost.

**Consequence: the bundle's posted `rect` is advisory only** and this feature does not depend on it.
It is still parsed (`SelectionRect`) for diagnostics and as a last-ditch fallback, but the anchor
comes from the probe. `FoliateMessage.Selection.rect` therefore stays nullable and no assertion is
built on it.

**Residual limitations, stated rather than hidden.** `evaluateJavascript` is asynchronous, so the
anchor lands a frame or two after the `selection` message: the popover is shown only once the probe
resolves, or — if it returns `null`/does not resolve within a short budget — at the clamped default
position (visible and usable, merely not anchored). WI-5's connected slice must **measure** the
mapping against a known element's on-screen position in **paginated** mode on a non-first column
before the mapping is claimed correct; a green test that only ever ran on column 0 would prove
nothing.

#### 4.5.2 Coroutine scopes (finding 6)

The #165 WI-7 precedent is in this very file: `Azw3ReaderActivity.kt:104-109` uses the **application**
`ContentResolver` rather than the Activity's, because "a bounded provider call can outlive the reader,
so an Activity-bound resolver would keep a finished Activity alive" (Gate-4 round 2, Medium), and
`AnnotationImportEntry` takes `applyScope = container.appScope` for the same reason.

| Work | Scope | Rule |
| --- | --- | --- |
| `addHighlight` / `updateHighlight` / `removeHighlight` | `container.appScope` (`writeScope`) | Must survive the reader being finished/rotated mid-write. The launched block captures **only** value types (ids, `AnnotationColor`, `String`, `Locator`) — never `this@Azw3ReaderActivity`, the `WebView`, the `Azw3Document`, or a composable lambda. |
| `annotations.highlights(bookKey)` collection → `setAnnotations` | composition scope (`rememberCoroutineScope`) / `repeatOnLifecycle` | Touches the WebView, so it must stop when the reader stops. |
| `findHighlight` for a tapped CFI → popover EDIT | `uiScope` | Result mutates popover state; dropped if the host is gone. |
| `evalForResult` anchor probe + every `FoliateBridge` call | main thread, `uiScope` | `@MainThread` contract of `FoliateBridge`/`Azw3Document`. |

Teardown: the existing `DisposableEffect(holder)` `onDispose` already runs `onDocument(null)` and
`doc.destroy()`; it additionally clears `doc.onSelection` / `doc.onAnnotationShow` to `null` and calls
`host.teardown()`. After `teardown()`, a late `evalForResult` callback or a late `selection` message is
**ignored** rather than mutating popover state — the read-then-drop pattern
`FoliateGoToDispatcher.goTo`'s `finally` block already uses. A WI-5 test asserts that a callback
delivered after `teardown()` mutates nothing.

**Binding instruction for the WI-5 brief — do NOT copy the local EPUB precedent here.** The table
above is not merely advisory, because an implementer reading the nearest example will reproduce a
leak. `ReaderActivity.kt:682` is that example:

```kotlin
container.appScope.launch { annotations.updateHighlight(id, popoverVm.state.value.activeColor, note) }
```

`popoverVm` is an **Activity property** (`ReaderActivity.kt:205`), read *inside* the `appScope` lambda
— so the coroutine captures `this@ReaderActivity` and pins a finished Activity for the life of the
write. (Its siblings at `:665` and `:674` are correct: they snapshot into locals first.) The AZW3 host
**must snapshot every value into a local before `writeScope.launch`**, and a `writeScope` lambda may
reference only value types — never `popoverVm`, the Activity, the `WebView`, the `Azw3Document`, or a
composable lambda. Gate-4 should read the WI-5 diff against this rule specifically.

*(Observation for the tracker, outside this feature's write-set: the `ReaderActivity.kt:682`
occurrence looks like a live instance of the same leak class #165 WI-7 fixed. Worth a bug row; #142
does not touch that file.)*

#### 4.5.3 Standalone notes are OUT of scope (finding 3)

Verified: `AnnotationsRepository.addNote` has **zero production call sites** in
`android/app/src/main/kotlin/` — the only occurrence is its own declaration
(`AnnotationsRepository.kt:70`). **No Android format ships a standalone-note creation entry point**;
EPUB's and TXT's popover `NOTE` mode calls `saveNote`, which routes to `updateHighlight(id, color, note)`
or `createHighlight(color, note)` — i.e. a note **attached to a highlight**, which is what the
design's `HighlightCard` renders. `StandaloneNoteCard` exists for rows that arrive via backup restore
and annotation import (#165).

So #142 ships **highlight-attached notes only**, matching EPUB/TXT exactly. Standalone-note creation
is dropped from the scope and the acceptance criteria: it is not AZW3-specific, has no designed
control on any format, and inventing one would be a rule-51 violation. (`AnnotationsRepository.addNote`
is therefore *not* called by this feature; the AZW3 Notes sheet still **renders** standalone notes that
arrive by restore/import, which is already true today.)

Gate-2 round 2 independently reproduced this result and confirmed the attach-to-highlight flow at
`ReaderActivity.kt:678` and `TxtReaderActivity.kt:1171`. The cross-format gap — a standalone-note
creation entry that no Android format has, and `addNote`'s consequently dead production path — is
tracked as **feature #176**, the sibling of #175 (§2.1). Both are cross-format adoptions that #142
inherits rather than diverges from.

### 4.6 `reader/Azw3ReaderActivity.kt` — MODIFY (WI-5, WI-6)

- Build `Azw3AnnotationHost`; collect `container.annotationsRepository.highlights(bookKey)`; map
  through `Azw3AnnotationMapper.cfiFor` + `AnnotationColor.dotHex` → `liveDocument?.setAnnotations(...)`.
- Wire `doc.onSelection` / `doc.onAnnotationShow` in the existing `DisposableEffect(holder)`.
- Render `Azw3PopoverOverlay` inside the body `Box` (above the tap zones).
- `override fun onActionModeStarted(mode: ActionMode)` → suppress the system selection bar (§7 R2).
- Tap-zone long-press pass-through (§7 R1).
- Replace `onJumpToAnnotation = null` in `Azw3ReaderChrome.kt:171` with a passed-in nullable
  callback defaulting to `null`, and pass the host's jump (WI-6), reusing `azw3JumpDecision` +
  `Azw3Document.goTo` unchanged.

### 4.7 Files explicitly OUT of scope

- **`android/app/src/main/assets/foliate/foliate-bundle.js`** — the vendored bundle. Not touched.
  Nor `bundle-patch.md`, nor `FoliateBundleProvenanceTest.kt`'s SHA pin.
- **`android/app/src/main/assets/foliate/reader.html`** — the shim's `Proxy` already forwards
  `selection` / `annotation-show` / `create-overlay`; outbound calls go through
  `evaluateJavascript` → `readerAPI.*` directly. Not touched.
- `annotations/AnnotationsRepository.kt`, `data/AnnotationDao.kt`, `data/Entities.kt`,
  `VReaderDatabase` — **no schema change, no Room migration**. `AnnotationsRepository.addNote` is
  **not called** by this feature (§4.5.3 — standalone-note creation exists on no Android format).
- `annotations/SelectionPopover.kt`, `SelectionPopoverViewModel.kt`, `AnnotationCards.kt`,
  `AnnotationsReviewSheet.kt`, `AnnotationColor.kt`, `AnnotationAnchor.kt`, `Annotation.kt`.
- `backup/AnnotationBackupMapper.kt`, `contracts/**`, `android/identity/**` — the wire format is
  unchanged; an AZW3 highlight serializes exactly like an EPUB one.
- `reader/ReaderActivity.kt`, `TxtReaderActivity.kt`, `PdfReaderActivity.kt`,
  `ReaderHighlightController.kt`, `TxtSelectionController.kt` — other formats untouched.
- The entire iOS tree (`vreader/`, `vreaderTests/`, `project.yml`, `*.xcodeproj`) — rule 48
  cross-platform write isolation.

---

## 5. Prior art / precedent / rejected alternatives

**Built on.** iOS's Foliate annotation path is the direct template and it is small on purpose:
`FoliateSpikeView+Selection.swift` (selection → anchor + locator → persist → repaint),
`FoliateHighlightRenderer.swift` (`readerAPI.addAnnotation({value, color})` with escaped CFI),
`FoliateHighlightTapResolver.swift` (tapped CFI → record UUID),
`FoliateSpikeView+Restore.swift` (re-fire on **every** `create-overlay`, not just the first — its
header states the reason: a highlight whose CFI lives in section 3 cannot paint while section 0 is
mounting). Android's #123 supplies the UI/state half (popover VM, three modes, persist side effects,
clamped overlay) which this feature reuses composable-for-composable.

**Rejected alternatives.**

| Rejected | Why |
| --- | --- |
| A new `AnnotationAnchor.Foliate` sealed case | Diverges from iOS (which reuses `.epub` for AZW3 and documents why in `FoliateHighlightTapResolver.swift`), changes the `anchorHash` basis for a format that has no extra fields to carry, and adds a decode variant iOS cannot read. `Epub(href = "", cfi = …)` is the parity shape. |
| Patching the bundle to post a richer selection payload (host-viewport rect, href) | The bundle already posts everything durable; the only missing datum is a coordinate transform we can compute host-side (§7 R3). A third patch would move the SHA pin, re-open the rule-54 supply-chain review, and desync from iOS's bundle for no persisted benefit. |
| Adding a new shim function to `reader.html` for selection | Unnecessary — the `Proxy`'s `get` trap forwards every handler name through the one `send` path (`reader.html:42-46`, which serialises `{name, detail}` at `:37`). Established by reading that code, and independently confirmed at Gate-2 round 3. (The existing `Other("selection")` parser test shows only that the Kotlin side already receives the name — it is a JVM test over a synthetic string, so it is corroboration, not end-to-end proof.) |
| Storing the section index in the anchor | Redundant: the MOBI CFI's first step *is* `(index+1)*2`, and `view.addAnnotation` re-derives it. A second copy can drift. |
| Driving the render through a single "apply all decorations" call à la Readium | foliate's overlayer is **per section and lazily created**; `view.addAnnotation` silently no-ops for an unmounted section (`view.js:384-393`). Only a recorded set re-applied on `create-overlay` is correct. |
| Reusing `TxtSelectionController` | It resolves Compose text geometry; there is no Compose text in a WebView. |
| A synthetic AZW3 fixture for the tests | A real AZW3 exists (§6). Rule "real books first". |

---

## 6. Work-item sequencing

Real book for every AZW3 test that needs one: **`test-books/books/azw3/Bei Tao Yan De Yong Qi - Zi Wo.azw3`** (6.29 MB, CJK). It is already staged for connected tests as the gitignored asset
`android/app/src/androidTest/assets/foliate-spike/book.azw3` — **verified byte-identical**
(SHA-256 `39826bfd…c01c95`), reached with the existing `copyBookOrSkip("book.azw3")` helper. It is the
**only** Kindle-format book in `test-books/`, so **CJK selection is the primary real-book case, not an
afterthought.**

| WI | Tier | Scope | Est. |
| --- | --- | --- | --- |
| **WI-1** | foundational | `FoliateMessage` cases (`Selection`, `SelectionCleared`, `AnnotationShow`, `OverlayCreated`, `SelectionRect`) + strict parser branches + field caps, **plus the PER-MESSAGE-NAME `FoliateBridgePolicy.rawCeilingFor` gate at the bridge before `parse` (§4.3), with the adversarial long-label TOC non-regression test**, and the `FoliateBundleProvenanceTest` extension pinning the message + `readerAPI` names this feature depends on (§10). Existing `Other("selection")` test updated. | S |
| **WI-2** | foundational | `Azw3AnnotationMapper` — `selectionToInputs`, `cfiFor` (anchor → **locator fallback**), `highlightIdForCfi`. | S |
| **WI-3** | foundational | `foliateAddAnnotationJs` / `foliateDeleteAnnotationJs` builders + `FoliateBridge.addAnnotation/deleteAnnotation/deselect/evalForResult`. | S |
| **WI-4** | behavioral | `Azw3Document` annotation surface: `onSelection`, `onAnnotationShow`, `setAnnotations`, re-apply on `book-ready` + every `create-overlay`, `deselect`. Connected slice on the real book: a JS-driven DOM selection produces a `Selection` with a non-blank CFI; `setAnnotations` paints an SVG overlay that survives a page turn into another section. | M |
| **WI-5** | behavioral | Host wiring in `Azw3ReaderAnnotations.kt` + `Azw3ReaderActivity`: popover overlay, create / highlight-attached note / edit-colour / remove / copy / share, persist→decorate loop, **scope + teardown discipline** (§4.5.2), **selection anchor probe** (§4.5.1), **system ActionMode suppression** (R2), **tap-zone long-press pass-through** (R1). | L |
| **WI-6** | behavioral | Tap an existing highlight → `annotation-show` → EDIT popover (Note/Copy/Share/Remove — see §2.1 for the adjudicated surface); Notes-sheet `onJumpToAnnotation` lit up for AZW3 (reusing `azw3JumpDecision` + `Azw3Document.goTo`). | M |
| **WI-7** | behavioral | Gate-5b acceptance suite on the real CJK book through the production entry point + `dev-docs/verification/feature-142-<YYYYMMDD>.md`. **Test + evidence only — no `src/main` changes.** | M |

Dependencies are strictly linear (WI-1 → WI-2/WI-3 → WI-4 → WI-5 → WI-6 → WI-7); WI-2 and WI-3 are
parallelisable against each other. Every WI adds only Kotlin files, which Gradle source globs pick up
with no project regeneration — the rule-55 "new files are not lane-dispatchable" caveat is
iOS/xcodegen-specific and does not apply.

**Write-set conflict with bug #368 (Gate-2 round 1, finding 7 — confirmed).** Bug #368 ("AZW3 has no
Display (Aa) control", `docs/bugs.md:430`) is in flight and edits `Azw3ReaderActivity.kt` and
`Azw3ReaderChrome.kt` — both of which WI-5 and WI-6 also write (§4.6). Per rule 48 "one writer per
file/area at a time":

- **WI-1 – WI-4 are independent** of #368 (they touch `FoliateMessage.kt`, `FoliateMessageParser.kt`,
  `FoliateBridge.kt`, `FoliateBridgePolicy.kt`, `Azw3Document.kt` and the new
  `Azw3AnnotationMapper.kt` — none of which #368 edits) and may be dispatched immediately.
- **WI-5 and WI-6 must wait for #368 to land**, then rebase onto it. They are not dispatchable
  concurrently with it.
- **WI-7 is safe alongside either**, because it is confined to `androidTest/` plus the
  `dev-docs/verification/` evidence file — it must not acquire an `src/main` write.

Sequencing is the orchestrator's call; this note exists so the constraint is recorded rather than
rediscovered at integration.

---

## 7. Risks + mitigations

**R1 — the side tap zones may swallow the long-press, so selection is only reachable in the centre
third.** `Azw3ReaderActivity.kt:481-484` states this as the *current* contract in its own comment;
`TapZone` uses `pointerInput(holder) { detectTapGestures { … } }`, which awaits and consumes the
first down. *Mitigation*: WI-5 begins with an empirical check on the emulator (long-press in the left
third with the annotation pipeline live — does a `Selection` arrive?). If it does not, change
`TapZone` to consume only a resolved tap and let a long-press fall through to the WebView. This is a
gesture-routing change with no new visible element (rule 51 out-of-scope: "pure code changes with no
visible delta"). Do **not** assert the Compose internals in the plan — settle it by observation.

**R2 — the system selection ActionMode is undesigned chrome.** A WebView long-press raises the OS
"Copy / Select all" bar, which would sit above the designed popover. *Mitigation*: mirror the EPUB
precedent (`ReaderActivity.kt:633-656`) at the Activity level —
`override fun onActionModeStarted(mode: ActionMode) { mode.menu.clear(); super.onActionModeStarted(mode) }`
and `mode.finish()` once the `selection` message has been captured, so the empty bar is transient.
*Fallback if finishing the mode also clears the DOM selection in a way that breaks the flow*: keep
the mode alive with an emptied menu and drop it when the popover dismisses. Settle empirically in
WI-5; record which path was taken.

**R3 — the posted selection rect is in the section iframe's coordinate space (the bug #108 class).**
The bundle posts `serializeRect(range.getBoundingClientRect())` **raw** (`:7106-7112`) — unlike the
`tap` handler, which explicitly maps through `mapTapToHostViewport` because foliate shifts the
paginated section iframe horizontally (`left: -columnWidth`). So on any page but the first column the
popover's x would be wrong. *Mitigation (revised in round 1 — the v1 `frameLeft`-only probe is
withdrawn)*: **the posted rect is not used for anchoring at all.** The host computes the anchor from
the live selection's `getClientRects()` plus the section frame's **full** bounding rect, in injected
shell JS — **§4.5.1**, which also shows why this needs no bundle change.

*Scope of the mitigation — §4.5.1 is authoritative; this summary must not exceed it.* **Covered and
connected-tested**: frame left+top, multi-rect selections, backward (right-to-left) selections,
degenerate/zero-area rects, and paginated multi-column layout. **Argued but untested**: RTL text —
the reasoning holds (the rects come from the engine's own layout, and the focus edge is chosen by
direction rather than position), but no RTL book exists in `test-books/`. **Out of scope**: vertical
writing modes — anchoring at `edge.bottom` is itself a horizontal-writing assumption, so the layout
argument does not rescue that case; it is a named follow-up, not coverage.

*Degradation*: the probe returns `null` → the existing viewport clamp positions the popover —
unanchored, never off-screen or lost. In the out-of-scope vertical case the popover is
**misplaced but still clamped on-screen**, never lost. *Gate*: WI-5's connected slice must measure the
mapping against a known element's on-screen position on a **non-first column in paginated mode**; a
pass that only ever ran on column 0 proves nothing.

**R4 — a backup-restored AZW3 highlight would be invisible.** The backup wire has no anchor field
(§9), so `restoreAnnotations` inserts `anchor = null`. *Mitigation*: `Azw3AnnotationMapper.cfiFor`
falls back to `record.locator.cfi`; WI-2 ships a **mandatory RED test** with `anchor = null`.

**R5 — CFI durability across a bundle upgrade.** The MOBI CFI is synthesized from the spine index; a
future bundle whose `mobi.js` re-orders sections would orphan existing highlights. *Mitigation*: the
existing SHA pin (`FoliateBundleProvenanceTest`) already fails the build on any bundle drift, which
forces a human decision; WI-2 additionally pins the observed CFI *shape* (`epubcfi(/6/<even>!…)`)
against a string captured from the real book.

**R6 — the 300 ms selection debounce.** `waitForIdle` does not await it (the #133 recurrence).
*Mitigation*: every connected assertion on a selection uses `composeRule.waitUntil { … }` or the
`awaitLoaded`-style foreground poll; this is written into the test catalogue, not left to the author.

**R7 — re-applying the whole decoration set on every `create-overlay`.** iOS calls this "trivial"
(`FoliateHighlightRestoreDispatcher.swift:18`) at user-scale highlight counts. *Mitigation*: mirror
iOS, and have WI-4's connected slice record the page-turn latency with ~20 highlights on the real
6 MB book. Only optimise (per-section filtering by the CFI's spine step) if a regression is measured.

**R8 — emulator flakiness on gesture tests** (documented recurrence, #125/#133). *Mitigation*: §8
test policy — one connected class at a time on a cold-booted emulator, deterministic JS-driven
selection for everything except the one acceptance test that must use a real long-press.

---

## 8. Security

The row is emphatic and correct: **`addJavascriptInterface` is never used**, and this feature does
not introduce it. All traffic rides the existing pinned channel.

**Inbound (page → native).** Unchanged transport: `WebViewCompat.addWebMessageListener` bound to
`"vreaderHost"` with an allow-list of exactly `FoliateAssetServer.SHELL_ORIGIN`, plus
`FoliateBridgePolicy.isTrustedMessage(sourceOrigin, isMainFrame)`. The load-bearing boundary behind
that is the bundle patch: book sections are rendered in `sandbox="allow-same-origin"` iframes with
`allow-scripts` **stripped**, so book-embedded JavaScript cannot run and therefore cannot reach
`parent.vreaderHost` at all. Nothing in this feature widens the sandbox, the origin allow-list, or
the CSP in `reader.html`.

**The raw-message gate, ahead of the parser (round-1 finding 1; re-scoped in round 2, H1).** Before
this feature, the only bound on an inbound payload was whatever `Json.parseToJsonElement` would
tolerate. `FoliateBridgePolicy.rawCeilingFor` (§4.3) now rejects an over-length `message.data`
**before** `parse` runs — but **per message name, not globally**, because no finite global ceiling can
both admit an unbounded-by-design `book-ready` TOC and meaningfully bound a `selection` (the H1
arithmetic and the derivation are in §4.3). Only the three names #142 introduces are capped; every
other name keeps today's behaviour unchanged. Two limits are stated rather than buried: the `String`
is already materialised by the WebView when the listener fires, so this bounds parse-time
amplification and everything downstream but not *receipt*; and the name sniff is a best-effort
classifier for our own shim's output, not an adversarial parser — the load-bearing defense remains
the bundle patch plus the origin/main-frame gate. Deep nesting inside a ceiling is covered by a JVM
test that pins the observed degradation (`parse` already returns `null` on anything it cannot read)
rather than by asserting a depth guard kotlinx.serialization does not document.

**Validation of the three new messages** (all in `FoliateMessageParser`, pure and JVM-tested):

- Every field goes through the existing strict readers: `str()` rejects blank / JSON `null` /
  non-string; `int()` and `dbl()` reject *quoted* numerics and non-finite doubles; `bool()` accepts
  only the JSON literals (a quoted `"true"` or a numeric `1` is not a `collapsed`).
- A `selection` with `collapsed != true` but a blank/absent `text` **or** a blank/absent `cfi`
  → `parse` returns `null` → `tryEmit` is never called → the message is dropped. Same for an
  `annotation-show` with no `value`.
- A malformed `rect` (missing/partial/non-finite members) yields `rect = null`, not a throw; the
  popover then falls back to the clamped default position (R3).
- **Size caps**: `text` ≤ 8 000 chars, `cfi`/`value` ≤ 4 000 chars; anything longer is rejected
  wholesale (the message is dropped, not truncated — a truncated CFI would resolve to the wrong
  range, and a truncated quote would corrupt `profileKey`). Rationale: `selectedText` is persisted to
  Room, copied into `Locator.textQuote`, hashed into `profileKey` via `canonicalJson()`, **and
  written into `annotations.json` on every backup** — an unbounded string is a storage-bloat and
  backup-size vector reachable by a very large drag selection even with no book script at all.
- `parse` is already `runCatching`-wrapped for the JSON parse, so a hostile/oversized payload can
  never throw into the WebView callback thread.

**Outbound (native → page).** `addAnnotation` / `deleteAnnotation` interpolate exactly two values:

- the **CFI**, which is book-derived and therefore JSON-encoded through the same
  `Json.encodeToString(String.serializer(), s)` seam that `foliateSetStylesJs` and the #135 goTo
  dispatcher use — quotes, backslashes, newlines and `</script>` are all neutralised, and the unit
  test pins the *production* builder, so test-vs-production escaping cannot drift;
- the **colour**, which is never free text: it is `AnnotationColor.dotHex`, a compile-time constant
  from a 5-value enum. (Note the deliberate divergence from iOS's `FoliateHighlightRenderer`, which
  maps to CSS colour *names* from a 4-name set and coerces anything else to `yellow` — that would
  silently mis-render Android's `red`. `Overlayer.highlight` sets `fill: <color>`, so a hex triplet
  is valid and exact.)

Every injected call keeps the file's existing `try{…}catch(e){}` wrapper so a missing `readerAPI`
(pre-book-ready, or a dead renderer) is a no-op rather than an uncaught page error.

**Not changed**: `FoliateAssetServer`'s single virtual origin, the `shouldInterceptRequest`
fail-closed rule, `shouldOverrideUrlLoading`, `allowFileAccess = false`, the book-path handler's
exact-name gate, or the bundle SHA pin.

---

## 9. Backward compatibility

**Existing data.** No Room schema change and no migration: AZW3 highlights/notes are ordinary rows in
the existing tables, distinguished only by `locator.format == "azw3"`. Existing AZW3 **bookmarks**
(#135) are untouched — different table, different code path. Existing EPUB/TXT/MD/PDF annotations are
untouched.

**Backup / restore (verified against the real decoder, not just the doc).**
`contracts/identity/backup-format.md:42-43` and `BackupSectionDTOs.swift:50-59` /
`vreader.contracts.backup.BackupHighlight` agree: a backed-up highlight is
`{highlightId, bookFingerprintKey, locatorJSON, selectedText, color, note, createdAt, updatedAt}`.
`locatorJSON` is the **plain** `Locator` JSON — `AnnotationBackupMapper.toWire()` emits
`BackupJson.encode(locator)` and `AnnotationsRepository.validate()` decodes `BackupJson.decode<Locator>`
— **never `canonicalJson()`** (the #132 trap; confirmed on both the write and the read side plus the
contract doc). This feature writes no new field and changes no mapper, so an AZW3 highlight is
byte-shaped exactly like an EPUB one and an older restorer reads it fine.

**There is no `anchor` field on the wire, on either platform.** Therefore:

- A restored AZW3 highlight arrives with `anchor = null` and its CFI **only** in `locator.cfi`. This
  is precisely why `Azw3AnnotationMapper.cfiFor` must prefer the anchor and **fall back to the
  locator** (§4.2, R4) — the difference between "restored highlights re-paint" and "restored
  highlights are permanently invisible".
- The anchor JSON never crosses platforms, which also neutralises a latent shape mismatch worth
  recording: iOS's `AnnotationAnchor.epub` has a **non-optional** `serializedRange`, while Android's
  `Epub` makes it nullable. An Android AZW3 anchor (`serializedRange = null`) would not decode on
  iOS — but it is never transported, so nothing breaks.

**What an AZW3 annotation looks like to iOS.** Restored from an Android backup, it becomes a
`Highlight` with `anchorData = nil`, `locator.cfi` = the foliate CFI, `locator.textQuote` = the
quote, `format = "azw3"`, and the colour string. It appears in iOS's annotations list, its text and
note survive, and its position is jumpable. It will **not** re-paint in iOS's Foliate overlay,
because iOS's repaint reads the CFI from `record.anchor`'s `.epub` case only
(`FoliateHighlightJSBridge.cfi(from:)`, `FoliateHighlightTapResolver`). That is a **pre-existing,
symmetric iOS gap** — an iOS highlight restored from an iOS backup behaves identically — not a
regression introduced here. Record it as an observation in the Gate-5 evidence and file it as a
follow-up bug against the iOS Foliate repaint path rather than widening this feature's scope.

**Colour.** `red` remains Android-only (already documented at `AnnotationColor.kt:2-5`); on iOS it
round-trips as an unknown colour string and renders as the default. Unchanged by this feature.

---

## 10. Test catalogue

### JVM (`android/app/src/test/kotlin/…`) — fast, deterministic, no emulator

| File | Covers |
| --- | --- |
| `reader/foliate/FoliateMessageParserTest.kt` (extend) | `selection` → `Selection(text, cfi, index, rect)`; `collapsed:true` → `SelectionCleared`; blank/absent `text` → null; blank/absent `cfi` → null; quoted `"collapsed":"true"` is NOT collapsed; malformed/partial/non-finite `rect` → `rect == null`; text > `MAX_SELECTION_CHARS` → dropped; cfi > `MAX_CFI_CHARS` → dropped; `annotation-show` with/without `value`; `create-overlay` index incl. 0; non-JSON and non-object payloads → null. **Update the existing `Other("selection")` assertion.** Plus (round-1 finding 1): a **raw `selection` over its per-name ceiling** and a **deeply-nested JSON payload within the ceiling** both degrade to "ignored" without throwing — the nesting case pins the *observed* behaviour rather than asserting a documented depth guard. |
| `reader/foliate/FoliateBridgePolicyTest.kt` (extend) | `rawCeilingFor`: each of the three capped names resolves to its derived ceiling; boundary at / one under / one over each; **an uncapped name (`book-ready`, `relocate`, `goto-ack`, unknown) returns `null`**; a `"name"` key beyond `NAME_SNIFF_WINDOW` returns `null` (documented degradation, §4.3 limit 2); non-JSON input returns `null` without throwing. Plus: a `selection` at BOTH field caps with worst-case `\uXXXX` escaping is **under** its ceiling — i.e. the raw cap never silently shrinks the field caps. |
| `reader/foliate/FoliateTocParserTest.kt` (extend — the **adversarial** H1 non-regression) | Not "a max-size TOC with empty labels". A **`MAX_TOC_ENTRIES` = 10,000-entry TOC with 200-char labels AND 200-char hrefs** — ≈4,370,000 chars, i.e. *above* the withdrawn v2 global cap — still parses, still yields 10,000 entries, and preserves labels/hrefs **byte-for-byte** (`FoliateTocParser.kt:96-100`). Companion: a `relocate` carrying a 4,000-char `tocHref` round-trips byte-exact, so `foliateTocIndexFor`'s exact-string matching is untouched. This test fails on the v2 design and passes on v3 — it is the regression pin for H1. |
| `reader/foliate/FoliateBundleProvenanceTest.kt` (extend — finding 9) | Beyond the SHA pin, assert the bundle still contains the exact bridge message names and `readerAPI` members this feature binds to: `"selection"`, `"annotation-show"`, `"create-overlay"`, `addAnnotation`, `deleteAnnotation`, `deselect`. A future bundle re-vendor that renames or drops any of them then fails **visibly at build time** instead of silently breaking selection at runtime. |
| `annotations/Azw3AnnotationMapperTest.kt` (new) | `selectionToInputs`: locator field-for-field (format `azw3`, `cfi`, `textQuote`, `href`/`progression` null); anchor `Epub(href="", cfi=…, serializedRange=null)`; blank text/cfi → null. **CJK**: a selection whose text is Chinese round-trips byte-exactly through `Locator.textQuote`, `canonicalJson()` and `profileKey` (NFC handling is the canonical layer's, asserted not assumed). **Surrogate pairs / emoji** in the quote. `cfiFor`: anchor wins; **`anchor == null` → `locator.cfi`** (the restore case); both null → null. `highlightIdForCfi`: exact match, first-match-wins ordering, blank cfi → null, no match → null. CFI **shape** pinned against a string captured from the real book (`epubcfi(/6/<even>!…)`). |
| `reader/foliate/FoliateAnnotationJsTest.kt` (new) | `foliateAddAnnotationJs` / `foliateDeleteAnnotationJs` escaping: a CFI containing `'`, `"`, `\`, a newline, `</script>` and CJK produces a valid JS string literal that cannot break out; the colour is the enum's `dotHex`; both are wrapped in `try{…}catch{}`. Pins the **production** builders (the `foliateSetStylesJs` pattern). |
| `annotations/SelectionPopoverViewModelTest.kt` (extend, if needed) | SELECT → NOTE → dismiss transitions used by the AZW3 host. |
| `reader/Azw3SelectionAnchorTest.kt` (new, WI-5) | The Kotlin side of §4.5.1: the probe's JSON (`x`,`y`,`w`,`h`) → a `SelectionPopoverState` anchor in dp; a `null`/unparseable/timed-out probe → `null` (the documented clamped-default degradation); non-finite members → `null`. The JS itself is exercised on-device (below), not here. |
| `reader/Azw3AnnotationScopeTest.kt` (new, WI-5 — finding 6) | After `Azw3AnnotationHost.teardown()`, a late `onSelection` / `onAnnotationShow` / anchor-probe callback mutates **nothing** (popover stays dismissed, no repository call). A repository write launched on `writeScope` completes after teardown and captures no Activity/WebView reference (asserted by construction — the lambda takes only value types). |

Room-backed JVM/Robolectric parity with `MdHighlightConnectedTest`'s shape is **not** duplicated —
the persistence seam is `AnnotationsRepository`, already covered by `AnnotationsRepositoryTest`.

### Connected (`android/app/src/androidTest/kotlin/…`) — real WebView, real book

Binding policy for every connected class below (all four documented hazards):

1. **`setContent` / `ActivityScenario` exactly once per test method** — never loop over themes,
   books or modes inside one method (`IllegalStateException`; compile and JVM do not catch it).
2. **Never `waitForIdle` to await a selection** — the bundle debounces 300 ms and the persist path is
   async. Use `composeRule.waitUntil(timeoutMillis = …) { … }` or an `awaitLoaded`-style foreground
   poll (`Azw3BookmarkNavTest.kt:247-254`).
3. **Gesture/long-press classes run ONE AT A TIME on a cold-booted emulator**, never with anything
   else driving the device; sweep stale `adb shell getprop` processes and restart adb first.
4. **`Azw3Document` built outside the Activity must be given a viewport** — reuse
   `forceViewport(wv)` (bug #357: a WRAP_CONTENT WebView measures to 0 height → 1-page paginator).
5. **Fixture policy — the acceptance suite FAILS HARD; only the slice tests may skip (finding 2).**
   Round 1 is right that a blanket `Assume` policy reproduces bug #369's exact shape: *"a skip exits 0
   exactly like a pass"* (`docs/bugs.md:431`; the same sentence is written into
   `Azw3TocAcceptanceTest.kt:123` and `:510-511`). The repo already has both patterns, so this plan
   picks per tier rather than uniformly:
   - **WI-7 acceptance (`Azw3AnnotationsAcceptanceTest`)** copies `Azw3TocAcceptanceTest.importRealBook()`
     (`:513-532`) verbatim in spirit: `assertTrue` on the asset's presence with the staging command in
     the message, then **content-digest proof** that the imported artifact really is that book
     (`assertEquals(REAL_BOOK_SHA256, book.contentSHA256)` and the byte count) — never `assumeTrue`.
   - **WI-4/WI-5/WI-6 slices** may keep `copyBookOrSkip` so a fresh worktree without the gitignored
     asset still builds and runs the rest of the class.
   - **Gate-5 evidence is only valid from a run with a non-zero executed count and ZERO skips for the
     acceptance class.** The evidence file records the runner's executed/failed/skipped counts, not
     just "green". A run reporting `tests=0` or any skip in that class does not satisfy Gate 5.

| File | Tier | Covers |
| --- | --- | --- |
| `reader/Azw3SelectionBridgeTest.kt` (new, WI-4) | slice | On the real book, after `Azw3DocState.Loaded`: inject a DOM `Range` over a CJK run in the mounted section (`getElementById('view').renderer.getContents()[0].doc`, the **existing `Azw3DomProbe` seam**) and `addRange` it — this fires the same `selectionchange` a finger does, so the whole production path from the bundle's handler onward runs, deterministically. Assert (via `waitUntil`) a `Selection` arrives with non-blank CJK `text` and a `epubcfi(/6/…!…)` `cfi`. Then `setAnnotations(mapOf(cfi to "#e6b800"))` and assert an SVG overlay rect exists in that section's document; page into another section and assert the overlay for a CFI in **that** section paints after its `create-overlay` (the iOS-parity requirement). |
| `reader/Azw3SelectionAnchorConnectedTest.kt` (new, WI-5 — §4.5.1 gate) | slice | The anchor probe against the real layout: select a known element, run the §4.5.1 JS, and assert the returned `(x, y)` lands inside that element's on-screen bounds **on a non-first column in paginated mode** (page forward first — a pass on column 0 proves nothing, since `frameElement.left` is 0 there). This is the test that would have caught the withdrawn v1 `frameLeft`-only design. Round-2 M1 additions: (a) a **backward** selection (build it with `sel.setBaseAndExtent(focusNode, focusOffset, anchorNode, anchorOffset)` reversed) anchors at the range **start**, not the end — this fails on the v2 JS; (b) a range whose client-rect list contains a **zero-area** rect (end at a line break) still yields a usable anchor, and an all-degenerate range yields `null`; (c) no live selection → `null`; (d) `w`/`h` match the host viewport. |
| `reader/Azw3AnnotationHostTest.kt` (new, WI-5) | slice | Real Room (in-memory) + real `Azw3Document`: a `Selection` → popover visible in SELECT mode → colour tap → a `HighlightRecord` exists with `format == "azw3"`, the CFI in **both** `locator.cfi` and the anchor, and the CJK quote intact; a **highlight-attached** note saves via NOTE mode (§4.5.3 — no standalone-note path); a second identical selection dedupes to one row via `(profileKey, anchorKey)`. Seed the parent `BookEntity` first (in-memory Room enforces the FK — the #135 lesson). |
| `reader/Azw3HighlightTapTest.kt` (new, WI-6) | slice | An `annotation-show` for a stored CFI opens the popover in **EDIT** mode with the record's colour and note; Remove deletes the row **and** the overlay disappears from the section document; an `annotation-show` for an unknown CFI is a no-op. |
| `reader/Azw3AnnotationsAcceptanceTest.kt` (new, WI-7) | acceptance | §11, end to end through the production entry point on the real CJK book, incl. **one real UiAutomator long-press** (run alone, cold-booted). |

---

## 11. Gate-5 production reachability

**The user-visible path, all files in `android/app/src/main/`:**

> app launch → **`MainActivity`** (the manifest `LAUNCHER` activity) → **Library** grid → tap the tile
> for *Bei Tao Yan De Yong Qi - Zi Wo* (`.azw3`) → **`Azw3ReaderActivity`** → **long-press a Chinese
> phrase in the page body** → the designed **selection popover** appears under the selection → tap a
> colour dot → the phrase paints with that colour wash in the WebView → bottom chrome **"Notes"** →
> the highlight's card is listed → tap the card → the reader jumps to it (the sheet dismisses) →
> back in the page, **tap the painted highlight** → the popover opens in EDIT mode → **Remove** → the
> wash disappears and the card is gone from the Notes sheet.

No `Azw3ReaderActivity.intent(...)`, no `src/debug/` launcher, no composable invoked directly, no
`vreader-debug://` equivalent — mirroring `Azw3TocAcceptanceTest`'s wording and
`dev-docs/verification/feature-139-20260805.md`. The reader the tap opens must additionally be
confirmed to carry this book's fingerprint in the **production** intent extra.

Acceptance criteria exercised in WI-7, each asserted only after `Azw3DocState.Loaded` is observed:

1. Long-press in the page body raises the designed popover — **the real gesture**, run alone on a
   cold-booted emulator. The system selection bar must not present *populated* (no Copy / Select-all
   chrome competing with the popover); whether an emptied bar flashes transiently depends on which
   R2 path WI-5 settled on empirically, so the evidence records the observed behaviour rather than
   asserting one path in advance.
2. Highlight creation persists a row with the CJK quote intact and paints immediately.
3. The wash survives a page turn away and back, and survives closing + reopening the reader
   (the `book-ready` re-apply path).
4. A note attached to a highlight appears on that highlight's card in the Notes sheet. (**Standalone
   notes are NOT an acceptance criterion — §4.5.3**: no Android format ships a creation entry for
   them, so requiring one here would demand an undesigned control.)
5. Tap-to-edit opens EDIT mode (§2.1); recolour and Remove both take effect in the WebView and in Room.
6. Notes-sheet card tap jumps (sheet dismisses on a jumpable target; stays open otherwise — no
   invented error surface).
7. Copy puts the CJK text on the clipboard; Share opens the chooser.
8. **Cross-format non-regression**: EPUB (Readium) and TXT highlights still create and render.
9. A live-WebDAV backup → wipe → restore round-trip re-lists the AZW3 highlight **and re-paints it**
   (the R4 / §9 anchor-less path, which is the single most likely silent failure).

Evidence file: `dev-docs/verification/feature-142-<YYYYMMDD>.md` per
`dev-docs/verification/SCHEMA.md`, naming the user-visible path above and recording the R1/R2/R3
empirical outcomes **and the runner's executed / failed / skipped counts**. The row may not reach
`VERIFIED` until that file exists, criterion 1 was exercised with a real long-press, and the
acceptance class reports a **non-zero executed count with zero skips** (§10 fixture policy — a
skipped acceptance run exits 0 exactly like a passing one; bug #369).

**What the evidence file must NOT claim.** The acceptance pass exercises one real book, which is
horizontal CJK. The evidence must therefore state explicitly that **RTL text and vertical writing
modes were not exercised** (§4.5.1: RTL is argued-but-untested, vertical is out of scope), so a later
reader cannot infer anchor coverage the run did not establish. Passing criteria 1-9 demonstrates the
AZW3 annotation path on this fixture; it does not demonstrate writing-mode generality.

---

## 12. Docs sync + version

- `docs/architecture.md` — the Android reader/annotations section gains the AZW3 adapter row
  (`Azw3AnnotationMapper`, the `selection`/`annotation-show`/`create-overlay` bridge messages, the
  per-section decoration re-apply). No new service, entity, schema or notification.
- `README.md` — the Android features list: AZW3 gains highlights/notes alongside EPUB/TXT/MD.
- Version: Android PRs bump `android/version.properties` (`versionName` + `versionCode`) and tag
  `android/vX.Y.Z` — **minor** for the feature-completing WI, patch for foundational ones (rule 40;
  the orchestrator allocates at the merge slot). The `VERIFIED` finalizer PR is **docs-only with no
  version bump** (`android/version.properties` is a code path and would trip the merge-gate audit
  hook — the #134 lesson).

## 13. Revision history

- **v1 — 2026-08-06** — Gate-1 draft.
- **v2 — 2026-08-06** — Gate-2 **round 1: block-recommended** (4 High, 3 Medium, 2 Low). All nine
  findings addressed or adjudicated. Caveat recorded for the auditor: several findings cited paths
  that do not exist in this repo — `android/app/src/main/kotlin/me/lllyys/vreader/azw3/…` (there is
  no `me/` package; the root is `com/vreader/app/…`) and `dev-docs/designs/vreader-android-annotations.jsx`
  (missing the `vreader-fidelity-v1/project/` segment). Each finding was re-verified at the real path
  before acting; none was dismissed on the citation error alone, and none turned out to rest on a
  file that does not exist.

  | # | Sev | Disposition |
  | --- | --- | --- |
  | 1 | High | **Fixed.** Confirmed at `FoliateBridge.kt:137` → `FoliateMessageParser.kt:26`. Added `FoliateBridgePolicy.MAX_RAW_MESSAGE_CHARS`, gated **before** `parse` (§4.3), sized above the legal `MAX_TOC_ENTRIES` `book-ready` ceiling so #140 does not regress; §8 states honestly that the `String` is already materialised by the WebView, so the cap bounds parse-time amplification, not receipt. Tests added for oversized raw payloads, deep nesting, and the TOC non-regression (§10). **→ SUPERSEDED in v3 (round-2 H1): the global cap was withdrawn for a per-message-name one; the sizing claim in this row was wrong.** |
  | 2 | High | **Fixed.** Confirmed bug #369's shape at `docs/bugs.md:431` and the fail-hard pattern at `Azw3TocAcceptanceTest.kt:510-532`. §10 now splits by tier: the WI-7 acceptance class fails hard with a content-digest identity proof and never `assumeTrue`s; slices may still skip; Gate-5 evidence requires a non-zero executed count and zero skips (§11). |
  | 3 | High | **Fixed by removal.** Verified `AnnotationsRepository.addNote` has **zero production call sites** — no Android format has a standalone-note creation entry. §4.5.3 drops it from scope; §11 criterion 4 narrowed to highlight-attached notes; §4.7 records that `addNote` is not called. No control invented. |
  | 4 | High | **Adjudicated, approach unchanged** (§2.1). The design text at `highlight-popover-canvas-artboards.jsx:666-669` is real, but EPUB and TXT/MD already route tapped highlights into `SelectionPopover` EDIT mode today — the divergence is pre-existing and app-wide. Cross-format adoption is feature **#175** (`docs/features.md:227`). |
  | 5 | Medium | **Fixed; answer is NO bundle change** (§4.5.1, §7 R3). The v1 `frameLeft`-only probe is withdrawn. The host now computes the anchor from the live selection's `getClientRects()` plus the section frame's full rect, in injected shell JS — proven reachable by `Azw3DomProbe.kt:156-174`+`:58-120` (shipped connected test) and by the bundle's own shell-scope `mapTapToHostViewport` (`:7141-7158`). New connected test gates it on a **non-first column**. **→ Its coverage claim ("covers frame top, RTL/vertical modes, scrolled-vs-paginated and multi-rect") was SUPERSEDED in v3 (round-2 M1) and was an overclaim: RTL is argued-but-untested and vertical writing modes are out of scope. §4.5.1 is authoritative; see the M1 row below.** |
  | 6 | Medium | **Fixed** (§4.5.2). Two named scopes: `writeScope` = `container.appScope` for repository writes capturing only value types; `uiScope` = composition/lifecycle for all reads, WebView calls and the anchor probe. Callbacks nulled and `teardown()` called in the existing `onDispose`; late callbacks ignored. Cites the #165 WI-7 leak fix at `Azw3ReaderActivity.kt:104-109`. New `Azw3AnnotationScopeTest`. |
  | 7 | Medium | **Recorded** (§6). Bug #368 (`docs/bugs.md:430`) edits `Azw3ReaderActivity.kt`/`Azw3ReaderChrome.kt`. WI-1–WI-4 independent; WI-5/WI-6 wait for #368; WI-7 stays test/evidence-only. |
  | 8, 9 | Low | **Confirmations + one improvement taken.** `FoliateBundleProvenanceTest` is extended to pin the bridge message names (`selection`, `annotation-show`, `create-overlay`) and `readerAPI` members (`addAnnotation`, `deleteAnnotation`, `deselect`) this feature binds to, so a future re-vendor fails at build time instead of silently breaking selection (§10). The anchor/restore fallback and its RED test are unchanged. |

- **v3 — 2026-08-06** — Gate-2 **round 2**: 7 of 9 round-1 findings verified resolved; 2 new
  (H1, M1). Round-2 citations were accurate and were spot-checked at source before acting.
  **The finding-5 premise was independently verified by the auditor** (`Azw3DomProbe.kt:58,:156`;
  `foliate-bundle.js:7141`; `reader.html:5`), so the **"no bundle change" conclusion is closed on
  evidence** — the SHA pin, `bundle-patch.md` and the rule-54 posture stay untouched.

  | # | Sev | Disposition |
  | --- | --- | --- |
  | H1 | High | **Design withdrawn and replaced, not renumbered** (§4.3). Round 2's arithmetic reproduces exactly (37 chars/row structure from `foliate-host.js:846-851`; 10,000 × 200-char labels+hrefs ≈ 4,370,000 > the v2 cap of 4,194,304), and the auditor's parser-side fix is indeed closed by `FoliateTocParser.kt:96-100`'s deliberate byte-for-byte preservation. The plan goes further than "raise the number": **`B` (per-row label/href length) has no upper bound anywhere**, so no finite global ceiling provably admits every legitimate `book-ready`. Taking round 2's explicit invitation, the cap is now **per message name** — `selection` 131_072, `annotation-show` 65_536, `create-overlay` 1_024, everything else **uncapped** (today's behaviour). Ceilings are derived from §4.1's field caps plus a counted skeleton at worst-case `\uXXXX` escaping, shown as arithmetic. The dividing line is principled: a message may be tightly capped only if this feature already bounds every variable-length field it carries — which excludes `book-ready` (TOC) and `relocate` (`tocHref`), the two that #140 needs byte-exact. The non-regression test is now adversarial (10,000 rows × 200-char labels **and** hrefs, ≈4.37 M chars — it fails on v2, passes on v3). Two honest limits recorded: the cap cannot prevent receipt (the WebView already built the `String`), and the name sniff is best-effort for our own shim, not an adversarial parser — the load-bearing defense remains the bundle patch + origin gate. |
  | M1 | Medium | **Both defects fixed; the writing-mode claim narrowed** (§4.5.1). (1) Backward selections: the JS no longer assumes focus == range end. It prefers `Selection.direction` and falls back to the bundle's own `selectionIsBackward` idiom (`foliate-bundle.js:4280-4285`, module-scoped so replicated rather than called), then takes `rects[0]` for backward and `rects[n-1]` for forward. (2) Degenerate rects: filtered at `width > 0.5 && height > 0.5`, following the existing probe's precedent (`Azw3DomProbe.kt:91`) widened to both axes; an all-degenerate range returns `null` → clamped default. (3) Writing modes: paginated multi-column stays *covered* (and connected-tested on a non-first column); **RTL is downgraded to "argued, untested"** (no RTL fixture exists) and **vertical writing modes are explicitly OUT of scope** — the layout argument does not rescue them, because anchoring at `edge.bottom` is itself a horizontal-writing assumption. Named as a follow-up rather than silently claimed. New connected assertions cover the backward and degenerate-rect cases; both fail on the v2 JS. |
  | — | note | Round 2's implementation caution on finding 6 folded in as a **binding WI-5 brief instruction** (§4.5.2), naming the exact local anti-pattern: `ReaderActivity.kt:682` reads the Activity property `popoverVm` *inside* an `appScope.launch`, capturing `this@ReaderActivity` (its siblings at `:665`/`:674` snapshot correctly). The AZW3 host must snapshot into locals before `launch`. Also recorded as a tracker observation — that EPUB occurrence looks like a live instance of the leak class #165 WI-7 fixed, and is outside this feature's write-set. |
  | — | note | Standalone-note exclusion (§4.5.3) now cites **#176** alongside **#175**, per the coordinator's filing. |

- **v4 — 2026-08-06** — Gate-2 **round 3**: H1 resolved, verdict moved to `follow-up-recommended`.
  The per-message-name cap design was verified non-circular (`rawCeilingFor` never parses; the shim
  emits `name` first at `reader.html:37` and the proxy forwards arbitrary names at `:42`), and the
  M1 fixes were verified at source. One **Low** remained: a stale coverage claim, fixed here — plus
  a second instance of the same claim that the requested sweep turned up.

  | # | Disposition |
  | --- | --- |
  | Low (stale coverage line) | **Fixed in §7 R3.** It said §4.5.1 "covers … RTL/vertical writing modes", contradicting §4.5.1's own out-of-scope finding. R3 now carries an explicit three-way split — **covered and connected-tested** (frame left+top, multi-rect, backward selections, degenerate rects, paginated multi-column) / **argued but untested** (RTL, no fixture) / **out of scope** (vertical writing modes, because `edge.bottom` is itself a horizontal-writing assumption) — with §4.5.1 named as authoritative and the summary explicitly forbidden from exceeding it. The vertical degradation is stated as *misplaced but clamped on-screen*, never lost. |
  | Sweep finding 1 (same class, **second instance**) | **Fixed.** The round-1 finding-5 row in this very revision history still read "Covers frame top, RTL/vertical modes, scrolled-vs-paginated and multi-rect" — the identical overclaim, in the section Gate 4/5 read first. Marked **SUPERSEDED** with the reason named, pointing at the M1 row and §4.5.1. (Two independent instances of one stale claim is the argument for sweeping rather than patching the cited line.) |
  | Sweep finding 2 (weaker overclaim) | **Fixed** in §5's rejected-alternatives table. "The `Proxy` already forwards every handler name, **proven** by the existing `Other("selection")` parser test" over-attributed: that test is a JVM assertion over a synthetic string, so it shows the Kotlin side accepts the name — it is corroboration, not end-to-end proof. The claim now rests on reading `reader.html:37,:42` and on the round-3 independent confirmation, with the test's weaker role stated. |
  | Sweep finding 3 (acceptance criterion) | **Tightened.** Criterion 1 said the long-press must raise the popover "not the bare system bar", which pre-judged an R2 path that §7 R2 explicitly leaves to empirical settlement in WI-5. It now requires only that the system bar not present *populated*, and records the observed behaviour instead of asserting a path in advance. |
  | Sweep finding 4 (evidence-file scope) | **Added** to §11. The acceptance pass runs on one horizontal-CJK book, so the evidence file must state explicitly that RTL and vertical writing modes were **not** exercised — otherwise a Gate-5 reader could infer anchor generality the run never established. This is the #141 "copied verbatim from iOS" failure shape closed at the point where it would otherwise enter the record. |

  Remainder of the plan re-swept for coverage language; no other instance found. §2 "design coverage",
  §10's "Covers" table headers, and §8's "covered by a JVM test" are scoped statements about specific
  artifacts, not generality claims.
