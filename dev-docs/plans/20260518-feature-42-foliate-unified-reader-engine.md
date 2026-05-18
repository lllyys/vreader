# Feature #42 — Foliate-js unified reader engine (EPUB + AZW3/MOBI)

- **Feature row**: `docs/features.md` #42 — `Reader/*`, High, `PLANNED`, `GH: #113`
- **Plan author**: claude (feature-cron, Gate 1)
- **Plan status**: v4 — **Gate 2 PASSED** (Codex, 3 rounds); awaiting §9 G1 human ratification before Gate 3
- **Source of truth**: `docs/features.md` #42 row + this plan

> **Read this first.** This is a high-risk plan to replace a **VERIFIED**,
> heavily-bug-fixed rendering engine. It is deliberately written to *not*
> commit the project to a big-bang rewrite. It proposes a flag-gated,
> parity-verified, incremental migration with **three explicit
> human-ratification gates** (§9). Gate 1 produces a proposal; it does not
> authorise the swap. The autonomous feature-cron must stop at the human
> gates — see §9.

---

## 1. Problem

The feature row reads: *"Replace EPUB bridge with Foliate-js `<foliate-view>`.
EPUB+AZW3/MOBI via one engine. PDF/TXT unchanged."*

Today VReader runs **two independent reflowable-document engines**:

| Format | Engine | Path |
|---|---|---|
| EPUB | Custom `EPUBWebViewBridge` (WKWebView + hand-written JS) | `EPUBReaderHost` → `EPUBReaderContainerView` → `EPUBWebViewBridge` |
| AZW3/MOBI | Foliate-js (`<foliate-view>`, vendored JS) | dispatch → `FoliateSpikeView` directly |

This split has real costs:

- **Duplicated maintenance** — selection, CFI math, highlight overlays,
  pagination, theming, TTS marks all exist twice.
- **AZW3/MOBI is the weaker twin** — the Foliate `FoliateSelectionEvent`
  exposes only `cfi`/`text`/`rect`/`sectionIndex`, so highlight *create*
  persists a CFI plus a *placeholder* `AnnotationAnchor.epub(href: "",
  serializedRange: empty)` (`FoliateSpikeView+Selection.swift`), highlight
  *restore* is a no-op, and AZW3 has no TTS (`FormatCapabilities` gates
  `.tts` off, bug #176).
- **The Foliate path itself is bifurcated** — `FoliateSpikeView` (562 LOC,
  the *live* AZW3 path) and `FoliateReaderHost` / `FoliateReaderContainerView`
  / `FoliateViewBridge` (the host-pattern path, fully written but **not
  wired into dispatch**, and missing the spike's coordinator plumbing) are
  two parallel implementations. `FoliateURLSchemeHandler` (254 LOC) is
  written but unwired.

The end-state #42 asks for: **one Foliate-js engine renders EPUB *and*
AZW3/MOBI**, the legacy `EPUBWebViewBridge` stack is retired, and the
unmaintained second Foliate path is collapsed into one.

**Why this is not free.** EPUB is VReader's most-exercised reflowable
format — `VERIFIED` across features #3, #11, #21, #33, #38, #49, and the
absorber of dozens of bug fixes (#163, #211, #212, footnotes, …).
Swapping its engine risks regressing every one. The migration's value is
**engineering** (less code, one engine, AZW3 inherits EPUB's maturity) —
there is **no direct user-facing feature** in it. That asymmetry is why
this plan is conservative.

---

## 2. Surface area

### 2a. Files to ADD

| File | Purpose | Tier |
|---|---|---|
| `vreaderTests/Services/Foliate/FoliateURLSchemeHandlerTests.swift` | Allowed-root contract + path-traversal rejection | foundational |
| `vreaderTests/ViewModels/FoliateReaderViewModel+EPUBTests.swift` | EPUB open / CFI position / legacy-locator back-compat | behavioral |
| `vreaderTests/Views/Reader/FoliateHighlightRendererTests.swift` | Promoted `HighlightRenderer` adapter | behavioral |
| `vreaderTests/Views/Reader/FoliateEPUBHighlightAnchorTests.swift` | Real `AnnotationAnchor.epub` create/restore + legacy re-anchor | behavioral |
| `vreaderTests/Services/Foliate/FoliateTOCConverter+EPUBTests.swift` | EPUB TOC parity | behavioral |
| `vreaderUITests/Verification/Feature42FoliateEPUBVerificationTests.swift` | End-to-end EPUB-on-Foliate acceptance (Gate 5 final) | behavioral |

### 2b. Files to MODIFY

| File | Change | Tier |
|---|---|---|
| `vreader/Views/Reader/ReaderContainerView.swift` | Dispatch switch (`:603`): `case "azw3"` → `FoliateReaderHost` (was `FoliateSpikeView`); `case "epub"` → `FoliateReaderHost` when `FeatureFlags.shared.isEnabled(.foliateUnifiedEPUBEngine)` **and** the book is not fixed-layout (§6 Risk 6), else legacy `EPUBReaderHost`. Thread `readerToken` to `FoliateReaderHost`. DebugBridge eval branch (`:430` `.epub`) → Foliate registry path. | behavioral |
| `vreader/Views/Reader/ReaderFormatHosts.swift` | `FoliateReaderHost` gains `readerToken: UUID?` and accepts EPUB; `EPUBReaderHost` retired in WI-17. | behavioral |
| `vreader/Views/Reader/FoliateReaderContainerView.swift` (292) + `+Navigation` (53) + `+Highlights` (85) | Stop hardcoding `readerToken: nil`; accept the threaded token; wire EPUB highlight persistence, search-nav, footnotes, selection routing; **add a host-path JS command channel** (today `+Navigation` posts `.foliateEvaluateJS` but nothing listens). | behavioral |
| `vreader/Views/Reader/FoliateViewBridge.swift` (264), `FoliateViewCoordinator.swift` (304) | Register the threaded `readerToken` for eval/settle; observe the JS command channel; port the spike's coordinator-side observers (create/delete-highlight JS, overlay-ready restore); accept `.epub`; switch the live load path to `FoliateURLSchemeHandler`. | behavioral |
| `vreader/ViewModels/FoliateReaderViewModel.swift` | Accept `.epub`; map EPUB CFI ↔ `Locator`; resolve legacy `Locator(href:progression:cfi:nil)`; consume the `layout` field from `handleBookReady` as a *secondary* fixed-layout consistency check (§6 Risk 6). | behavioral |
| `vreader/Services/Foliate/FoliateTypes.swift` | `FoliateRelocateEvent` today carries `cfi`/`fraction`/`tocLabel`/`tocHref`; add real section `href` + per-section `progression` (insufficient today for the legacy-locator fallback). `FoliateSelectionEvent` today carries `cfi`/`text`/`rect`/`sectionIndex`; add section `href` + serialized DOM-range (insufficient today to build a real `AnnotationAnchor`). | foundational |
| `vreader/Services/Foliate/FoliateMessageParser.swift` | Parse the new relocate **and** selection fields. | foundational |
| `vreader/Services/Foliate/JS/foliate-host.js` | Emit section `href` + `progression` in the `relocate` message, and section `href` + serialized range in the `selection` message. | behavioral |
| `vreader/Services/Foliate/FoliateURLSchemeHandler.swift` (254) | Wire into the live bridge; enforce the §5 allowed-root model. | behavioral |
| `vreader/Services/Foliate/FoliateTOCConverter.swift` (65) | EPUB spine → hierarchical `[TOCEntry]` with non-zero nesting (feature #38). | behavioral |
| `vreader/Services/Foliate/FoliateStyleMapper.swift` (90) | EPUB theme/typography/layout (paged↔scroll), chapter padding (#49), safe-area inset (#163). | behavioral |
| `vreader/Services/Foliate/FoliateTTSAdapter.swift` (96), `FoliateSearchAdapter.swift` (80) | EPUB TTS + search-result navigation wiring. | behavioral |
| `vreader/Views/Reader/FoliateHighlightRenderer.swift` (56) | Promote from a plain JS-string helper to a wired `HighlightRenderer` adapter — real contract is `apply(record:)`, `remove(id:)`, `restore(records:forHref:using:)` (+ convenience `restore(records:)`). | behavioral |
| `vreader/Services/FeatureFlags.swift` | Add a `FeatureFlagKey` enum case `foliateUnifiedEPUBEngine` + a `defaultValue` branch (default `false`); read via `FeatureFlags.shared.isEnabled(_:)`. DEBUG-overridable only, no persisted user override (§8). | foundational |
| `vreader/Services/EPUB/EPUBParser.swift` (read-only consult) | Expose / surface the OPF `rendition:layout` so dispatch can detect fixed-layout pre-open (§6 Risk 6). No retirement — see §2d. | foundational |
| `vreader/Models/FormatCapabilities.swift` | Regression-guard only: EPUB capability set must stay byte-identical post-migration. | foundational |
| `docs/architecture.md`, `README.md` | Doc-sync: collapse the dual-engine diagram; update Highlight-System + Format-Hosts tables. | n/a |

### 2c. Files to RETIRE (WI-17 only — after parity is proven *and* human-ratified)

`EPUBWebViewBridge.swift` (391), `EPUBWebViewBridgeCoordinator.swift`
(384), `EPUBWebViewBridgeJS.swift` (231), `EPUBHighlightBridge.swift`
(309), `EPUBHighlightJS.swift` (514), `EPUBHighlightRenderer.swift` (97),
`EPUBHighlightActions.swift` (57), `EPUBSelectionTokenCache.swift` (70),
`EPUBPaginationHelper.swift` (201), `EPUBProgressCalculator.swift` (110),
`EPUBReaderContainerView.swift` (481) + `+Navigation` (84) + `+Highlights`
(190), `EPUBReaderHost` (in `ReaderFormatHosts.swift`), and the EPUB JS
bundle `vreader/Services/EPUB/FoliateJS/` (epubcfi/foliate-bridge/
overlayer/tts/text-walker/footnotes). **≈ 4 000 LOC removed.**

> If §6 Risk 6's fixed-layout fallback is in effect, `EPUBReaderHost` and
> the legacy stack are **not** fully retired — they remain as the
> fixed-layout-EPUB renderer. WI-17 retires only the parts the Foliate
> engine fully replaces; the fixed-layout policy is settled in WI-15.

### 2d. Files explicitly OUT of scope

- `vreader/Services/EPUB/EPUBParser*.swift` — **stays.** Used by feature
  #43 (cover extraction), book-import metadata, and (newly, §6 Risk 6) the
  pre-dispatch fixed-layout check. Only the `rendition:layout` surfacing
  in §2b touches it.
- `TXTReaderHost` / `MDReaderHost` / `PDFReaderHost` and their bridges —
  untouched.
- `vreader/Services/Search/` FTS5 index — unchanged; only navigate-to-
  result wiring is touched.
- Feature #60 reader chrome — format-agnostic, untouched. No new UI (§8).
- The unified-reflow path (`UnifiedTextRenderer`, `ReaderUnified
  Coordinator`) — feature #54's concern. But the live `ReaderContainerView`
  has an unresolved `isComplexEPUB` unified/native dispatch branch; #42
  must *preserve* current complex-EPUB fallback behaviour (WI-15
  acceptance criterion), not silently regress it.

---

## 3. Prior art / project precedent / rejected alternatives

**Project precedent.** The Foliate-js engine, its bundle, the
`FoliateViewBridge`/`FoliateViewCoordinator`/`FoliateMessageParser`/
`FoliateJSEscaper` stack, and the host pattern (`FoliateReaderHost`
mirrors the other formats' hosts) **already exist** — the AZW3 spike
built them. `epub.js` and `mobi.js` are both already inside
`foliate-bundle.js`. This plan finishes wiring an engine the codebase
already ships and extends it to a second format.

**The referenced historical plans are gone.** GH #113 cites
`.claude/plans/snug-painting-barto.md` and `docs/2026-03-24-azw3-support-
plan.md`; both files no longer exist. GH #113's *body* carries a 13-WI
sketch — used here only as a structural reference, not a binding spec.

**Rejected alternative A — keep two engines (status quo).** Pros: zero
EPUB regression risk; zero effort. Cons: permanent maintenance
duplication; AZW3 stays the weaker twin. *Rejected* as the end-state —
but it is the honest fallback if §9's Gate G1 concludes the swap's risk
outweighs its benefit.

**Rejected alternative B — big-bang swap (one PR).** *Rejected outright* —
puts 6 VERIFIED features and ~40 bug fixes on one un-de-riskable PR with
no parity evidence.

**Rejected alternative C — make `FoliateSpikeView` canonical, retire the
host abstraction.** *Rejected* — the host pattern is the documented
architecture for every format, EPUB needs a host path anyway, and
`FoliateViewBridge` is the `UIViewRepresentable`+`Coordinator` convention
(rule 50 §3). The spike's mature AZW3 logic is *ported* into the host
path (WI-1) before the spike is retired (WI-5), not discarded.

**Chosen approach — flag-gated, parity-verified, phased, human-gated
migration.** Both engines coexist until parity is *evidenced*, the
off-switch (`FeatureFlags`) exists before any EPUB engine code lands, and
three human-ratification gates (§9) bound the autonomous pipeline.

---

## 4. Work-item sequencing

17 WIs, 4 phases. Each WI = one PR. Tier per rule 47 (Gate 5).

### Phase A — Consolidate the single Foliate path (no EPUB risk)

- **WI-1** *(behavioral, L)* — Port the spike's coordinator-side plumbing
  into the host path: selection / create-highlight-JS / delete-highlight-JS
  observers, `overlay-ready` restore (`handleCreateOverlay` is a no-op
  today), the **JS command channel** (`+Navigation` posts `.foliate
  EvaluateJS` but nothing listens), and thread `readerToken` through
  `ReaderContainerView` → `FoliateReaderHost` → `FoliateReaderContainerView`
  → `FoliateViewBridge` for DebugBridge eval/settle registration. No
  dispatch change. New observers mirror the spike's keyed `fingerprintKey`
  filtering + coalescing (§6 Risk 11).
- **WI-2** *(behavioral, M)* — **Selection-payload extension.** Extend the
  `selection` message in `foliate-host.js`, `FoliateMessageParser`, and
  `FoliateSelectionEvent` to carry section `href` + serialized DOM-range —
  the data needed to build a *real* `AnnotationAnchor` instead of today's
  placeholder. Wire the (still-live) spike + the host creation paths to
  persist the real anchor. **Prerequisite for WI-4 and WI-9.**
- **WI-3** *(behavioral, M)* — Flip AZW3/MOBI dispatch from `FoliateSpikeView`
  to `FoliateReaderHost`. Gate 5: AZW3 slice verify — `mini-azw3`, confirm
  render / position / selection / eval / settle parity with the spike.
- **WI-4** *(behavioral, M)* — Promote `FoliateHighlightRenderer` to a wired
  `HighlightRenderer` adapter (`apply(record:)`/`remove(id:)`/`restore
  (records:forHref:using:)`); implement AZW3 highlight create + restore
  using WI-2's real anchor. Closes a standing AZW3 defect.
- **WI-5** *(behavioral, S)* — Retire `FoliateSpikeView` + `+Selection`/
  `+HighlightTap`/`+Restore` (≈ 1 036 LOC). One Foliate path remains.

> Phase A is EPUB-risk-free, fixes the dual-path debt + the AZW3 highlight
> gap, and unblocks feature #57. **§10 recommends lifting Phase A into its
> own feature** — that decision belongs to Gate 2 / the human (§9 G1).

### Phase B — Bring the Foliate engine to EPUB parity (flag-gated; EPUB stays default-on-legacy)

- **WI-6** *(foundational, S)* — **The off-switch, first.** Add the
  `FeatureFlagKey.foliateUnifiedEPUBEngine` case + `defaultValue: false`
  branch; dispatch routes `.epub` → `FoliateReaderHost` only when
  `FeatureFlags.shared.isEnabled(.foliateUnifiedEPUBEngine)`. No
  user-facing toggle (rule 51, §8); DEBUG-overridable for verification.
- **WI-7** *(behavioral, L)* — EPUB open via Foliate-js: `FoliateReader
  ViewModel` accepts `.epub`; wire `FoliateURLSchemeHandler` into the live
  bridge with the §5 allowed-root model.
- **WI-8** *(behavioral, M)* — EPUB position/CFI: add the relocate-payload
  fields (section `href` + per-section `progression` to
  `FoliateRelocateEvent` / `FoliateMessageParser` / `foliate-host.js` —
  the EPUB-only counterpart to WI-2's selection-payload work; AZW3 needs
  no relocate `href`/`progression` since it positions by CFI); map EPUB
  CFI ↔ `Locator`; resolve legacy `Locator(href:progression:cfi:nil)`
  rows (§7).
- **WI-9** *(behavioral, M)* — EPUB highlight full-anchor: create a real
  `AnnotationAnchor.epub(href:serializedRange:)` (building on WI-2's
  selection payload); restore; **re-anchor pre-migration EPUB highlights**
  created by the legacy bridge. Pre-migration re-anchoring is a **hard
  no-go criterion** for the WI-16 default flip (§6 Risk 3).
- **WI-10** *(behavioral, M)* — EPUB TOC via `FoliateTOCConverter`,
  hierarchical nesting (feature #38).
- **WI-11** *(behavioral, S)* — EPUB search-result navigation: FTS5 index
  unchanged; `.readerNavigateToLocator` → host-path JS command channel →
  Foliate `goto`.
- **WI-12** *(behavioral, M)* — EPUB theme/typography/layout via
  `FoliateStyleMapper`: paged↔scroll, chapter padding (#49), Dynamic
  Island safe-area inset (#163), per-book settings. **Owns the
  pre-dispatch fixed-layout determination** (§6 Risk 6): surface OPF
  `rendition:layout` from `EPUBParser` so `ReaderContainerView` /
  `EPUBReaderHost` route fixed-layout `.epub` to the chosen engine
  *before* open — the post-`book-ready` `layout` field is a secondary
  consistency check only.
- **WI-13** *(behavioral, M)* — EPUB selection parity: dictionary /
  translate-on-select (#33), footnote detection (`.epubFootnoteDetected`),
  selection-popover routing (`.readerSelectionPopoverRequested`).
- **WI-14** *(behavioral, L)* — EPUB TTS on the Foliate path. **Must land
  before the WI-16 default-ON flip** or EPUB TTS regresses (§6 Risk 2).
  Overlaps feature #57 — see §8.

### Phase C — Parity verification (no default change)

- **WI-15** *(behavioral, L)* — Slice-verify EPUB-on-Foliate (flag forced
  ON in DEBUG) against **every** EPUB acceptance criterion: features
  #3/#11/#21/#33/#38/#49; bug regressions #163/#211/#212/footnotes;
  **pre-migration highlight re-anchoring (hard no-go)**; **fixed-layout
  EPUB slice** (settles the §6 Risk 6 policy); **complex-EPUB
  (`isComplexEPUB`) fallback preserved**; large-EPUB performance. Evidence
  file `dev-docs/verification/feature-42-<date>.md`. **Verification only —
  does NOT flip the default.**

### Phase D — Default flip + legacy retirement (each human-gated)

- **WI-16** *(behavioral, S)* — Flip `foliateUnifiedEPUBEngine`
  `defaultValue` → `true`. **HUMAN GATE G2 (§9): the feature-cron must NOT
  execute this WI autonomously.** Gated on WI-15 passing every criterion
  with zero no-go failures.
- **WI-17** *(behavioral, M)* — Delete the §2c legacy EPUB stack (modulo
  the fixed-layout carve-out, §2c note); retire `EPUBReaderHost`;
  doc-sync. **HUMAN GATE G3 (§9): separate explicit ratification, not
  implied by G2.** Final WI → row `DONE`; Gate 5b final acceptance →
  `VERIFIED`.

**PR-size estimate:** 4×S, 9×M, 4×L → 17 PRs. **Large** feature (rule 47)
— see §10.

---

## 5. `FoliateURLSchemeHandler` allowed-root model (concrete)

The live scheme handler must serve exactly two roots and reject all else:

1. **Bundle resources** — the app-bundle directory containing the Foliate
   JS/HTML/CSS (`vreader/Services/Foliate/JS/` as built into the bundle).
   Read-only, fixed at build time.
2. **One injected book-extraction root** — the single per-book extracted
   document directory (the unzipped EPUB / decoded MOBI), passed in at
   bridge construction.

Reject: any request whose canonicalised path is not a descendant of one
of those two roots; any `..` traversal; absolute paths; symlinks that
escape the root. `FoliateJSEscaper` is used for every interpolated value.
`FoliateURLSchemeHandlerTests` asserts this exact contract (allowed
descendants pass; `../`, absolute, symlink-escape all rejected).

---

## 6. Risks + mitigations

| # | Risk | Severity | Mitigation |
|---|---|---|---|
| 1 | EPUB regression across 6 VERIFIED features | **Critical** | Flag-gated; default OFF until WI-16; both engines coexist; per-criterion WI-15 verification |
| 2 | EPUB TTS regresses (EPUB has working TTS; Foliate TTS unwired) | **High** | WI-14 lands EPUB TTS *before* WI-16's default-ON flip; sequence is binding |
| 3 | Pre-migration EPUB highlights fail to re-anchor — legacy restore needs real `href` + serialized range; the Foliate path stores a placeholder anchor today | **High** | WI-2 adds the selection-payload data; WI-9 builds real `AnnotationAnchor.epub` create/restore; `FoliateEPUBHighlightAnchorTests` + the WI-15 legacy-highlight fixture; **hard no-go** for WI-16 |
| 4 | `readerToken` not threaded — host path hardcodes `readerToken: nil`, breaking DebugBridge eval/settle that Gate 5 depends on | **High** | WI-1 threads `readerToken` end-to-end *before* the WI-3 dispatch flip |
| 5 | Relocate model lacks section `href`+`progression` for the legacy-locator fallback | **High** | WI-8 adds the relocate `href`+`progression` fields (`FoliateTypes`/`FoliateMessageParser`/`foliate-host.js`) and tests legacy-row resolution |
| 6 | Fixed-layout EPUB — `layout` is known only at `book-ready`, **after** dispatch has already chosen the engine, so a post-open policy is unenforceable | **High** | WI-12 adds a **pre-dispatch** fixed-layout determination from OPF `rendition:layout` via `EPUBParser` (alongside the existing `isComplexEPUB` determination); `ReaderContainerView`/`EPUBReaderHost` route fixed-layout `.epub` to the chosen engine before open. WI-15's fixed-layout slice decides the final policy: Foliate renders fixed-layout adequately → it migrates too; inadequate → fixed-layout EPUB stays a permanent legacy-engine capability branch and the §2c retirement is partial |
| 7 | `FoliateURLSchemeHandler` path-traversal (custom scheme serving sandbox files) | **High** (security) | §5 concrete allowed-root model + explicit rejection tests |
| 8 | Host path has no JS command channel (`.foliateEvaluateJS` posted, unobserved) — TOC/search nav impossible | **High** | WI-1 adds the command channel before WI-10/WI-11 depend on it |
| 9 | Complex-EPUB (`isComplexEPUB`) unified/native fallback regresses indirectly | Medium | WI-15 acceptance criterion: complex-EPUB fallback behaviour preserved, or complex EPUBs explicitly gated out |
| 10 | Autonomous cron self-approves the default flip / legacy deletion | **High (process)** | §9 G2 + G3 human gates; WI-16/WI-17 marked "cron must not execute autonomously" |
| 11 | New host-path observers race / duplicate without the spike's keyed filtering | Medium | WI-1 mirrors the spike's `fingerprintKey`-keyed filtering + coalescing; `@MainActor` + `nonisolated` hop pattern reused from `FoliateViewCoordinator` |
| 12 | Large-EPUB performance/memory vs. the tuned legacy bridge | Medium | WI-15 large-EPUB performance slice |
| 13 | GH #113 is **CLOSED** — no open issue for `Refs #N` | Medium | §9 G1: re-open #113 or file fresh before Gate 3 |
| 14 | epubcfi.js bundle drift — two copies (`Services/EPUB/FoliateJS/` + `Services/Foliate/JS/`) | Low | Byte-identical *today* (audit-confirmed); WI-17 retires the EPUB copy, eliminating the drift surface |
| 15 | 17 WIs — Large feature, long-lived divergence | Medium | Phased; each WI one mergeable PR; Phase A splittable (§10) |
| 16 | Net value is engineering-only; no user feature offsets the risk | **High (project)** | §9 G1 explicit go/no-go; Gate-2 audit + human ratification before Gate 3 |

---

## 7. Backward compatibility

- **EPUB reading positions.** `ReadingPosition` stores a `Locator`
  (`href`+`progression`, and/or `cfi`). WI-8 adds the relocate `href`+
  `progression` fields so the Foliate engine can both *emit* and *resolve*
  the legacy shape. Positions with a `cfi` map directly; positions with
  only `href`+`progression` resolve via Foliate `goto` by href + fraction.
  WI-8 tests both shapes. No data migration.
- **EPUB highlights / bookmarks.** Stored via `AnnotationAnchor`. The
  legacy EPUB restore needs a real `href` + serialized range; the current
  Foliate selection path only persists a placeholder. WI-2 adds the
  selection-payload data; WI-9 builds the real anchor; pre-migration
  highlight re-anchoring is a **hard no-go criterion** (Risk 3). If legacy
  highlights cannot re-anchor, WI-16 is blocked until a migration path
  exists.
- **WebDAV backups.** Backup ZIPs store `Locator`/`AnnotationAnchor`
  values, not engine state — engine-agnostic. WI-15 includes a
  backup→restore→open-EPUB smoke check.
- **`PerBookSettings`.** Per-book EPUB overrides honoured by WI-12.
- **Older app versions / older backups.** Forward-only migration. N/A.

---

## 8. Rule-51 (no self-designed UI) compliance

The engine swap is **rendering-only**. Feature #60's reader chrome is
format-agnostic and untouched — EPUB-on-Foliate shows the *same designed
chrome*. **No new UI is introduced.** The `foliateUnifiedEPUBEngine` flag
is an internal `FeatureFlagKey` with **no Settings surface** — DEBUG-
overridable only, no persisted user override. A user-facing engine toggle
would be a new surface requiring `needs-design`; this plan does not add
one.

**Feature #57 overlap.** WI-14 (EPUB TTS on Foliate) delivers the Foliate
TTS wiring feature #57 ("AZW3/MOBI TTS") also needs. This plan does not
re-scope #57; WI-14 is planned from #42's own row. Whichever lands first
should coordinate (a cross-feature note, not a scope change).

---

## 9. Human-ratification gates (three)

This plan is a **Gate-1 proposal**. The autonomous feature-cron must stop
at each gate below — it cannot self-approve any of them.

- **G1 — before Gate 3 starts.** *(a)* Project go/no-go: proceed with the
  full phased plan / do **Phase A only** and keep two engines (rejected-
  alt A) / abandon. *(b)* Re-open GH #113 or file a fresh tracking issue
  and update the #42 Notes column. Until both are settled the row stays
  `PLANNED` and Gate 3 does not start.
- **G2 — before WI-16 (default flip).** A human reviews the WI-15
  verification evidence file and explicitly approves flipping the default
  to ON. The cron, on reaching WI-16, logs the blocked-on-human state and
  stops; it must not flip the default itself.
- **G3 — before WI-17 (legacy deletion).** A *separate* explicit human
  approval to delete the ≈ 4 000-LOC legacy stack — not implied by G2.

These gates exist because the migration has real regression risk and no
user-facing feature; an autonomous pipeline must not barrel through them.

---

## 10. Recommended feature split (for Gate-2 / human)

Rule 47: *"If a feature is genuinely 10+ WIs, consider whether the plan
should split."* This is **17 WIs** — a strong split signal.
**Recommendation:** lift **Phase A (WI-1…5)** into its own feature —
"Consolidate the Foliate reader path + AZW3 highlight parity". Rationale:
Phase A is independently valuable, carries zero EPUB risk, fixes a
standing AZW3 defect, and unblocks feature #57 — it should not be hostage
to the contentious EPUB-swap decision (§9 G1). Phases B–D remain feature
#42 (12 WIs). This is a triage decision (re-filing rows), so this plan
only *recommends* it.

---

## 11. Revision history / audit trail

| Version | Date | Change |
|---|---|---|
| v1 | 2026-05-18 | Initial draft (feature-cron, Gate 1). |
| v2 | 2026-05-18 | Gate-2 round-1 (Codex `019e38ff`): flag moved ahead of EPUB engine work; WI-1 expanded; new EPUB-highlight-anchor WI; fixed-layout policy; verification split from default flip + deletion; §9 → three human gates; §5 URL-scheme model; signatures corrected. 13 → 16 WIs. |
| v3 | 2026-05-18 | Gate-2 round-2 (Codex `019e38ff`): new **WI-2** (selection-payload extension — `FoliateSelectionEvent` lacked the `href`+range data the real anchor needs); fixed-layout routing moved **pre-dispatch** (OPF `rendition:layout` via `EPUBParser`; the `book-ready` `layout` field is post-dispatch and cannot enforce a capability branch); §2b `FoliateTypes` field list corrected (`fraction`, not `totalProgression`); §2c retirement made partial under the fixed-layout carve-out. 16 → 17 WIs. |
| v4 | 2026-05-18 | Gate-2 round-3 (Codex `019e38ff`): WI-ownership wording fix — the relocate-payload extension is attributed to **WI-8 only** (WI-2 is selection-payload only); Risk 5, §7, and the test-catalogue references corrected. **Gate 2 PASSED.** |

### Gate 2 — Independent plan audit

**Round 1** — Codex MCP, thread `019e38ff`, 2026-05-18. 6 High + 4 Medium
+ 2 Low — all legitimate, all applied in v2 (readerToken threading;
relocate `href`/`progression`; EPUB highlight-anchor WI; flag-first
ordering; three human gates; fixed-layout policy; host JS command
channel; Phase-A re-split; concrete URL-scheme model; complex-EPUB
criterion; TTS wording; `FeatureFlags` shape). Audit confirmed all named
files/types exist; legacy §2c files exist; `HighlightRenderer` contract
is `apply(record:)`/`remove(id:)`/`restore(records:forHref:using:)`; both
`epubcfi.js` copies byte-identical today.

**Round 2** — Codex MCP, thread `019e38ff`, 2026-05-18. v2 "materially
better"; 2 High + 1 Medium remaining, all applied in v3:

| Finding | Severity | Resolution in v3 |
|---|---|---|
| Highlight-anchor only partially resolved — `FoliateSelectionEvent` lacks the `href`+serialized-range data WI-9 needs to build a real anchor | High | New **WI-2** extends the selection payload (`foliate-host.js`/`FoliateMessageParser`/`FoliateSelectionEvent`) before WI-4/WI-9 |
| Fixed-layout fallback not implementable from `handleBookReady` — `layout` is known only post-dispatch | High | WI-12 moves the determination **pre-dispatch** (OPF `rendition:layout` via `EPUBParser`); `book-ready` `layout` is a secondary check; §6 Risk 6 + §2c carve-out |
| `FoliateTypes` model-assumption slip — relocate event has `fraction`, not `totalProgression` | Medium | §2b corrected to `cfi`/`fraction`/`tocLabel`/`tocHref` |

_Round-2 confirmed: no WI renumber/cross-reference break; the §9 G2/G3
stop mechanism is sufficient given the cron treats `dev-docs/plans` as
binding._

**Round 3** — Codex MCP, thread `019e38ff`, 2026-05-18. v3 resolved all
three round-2 findings (selection-payload prerequisite, pre-dispatch
fixed-layout determination, `FoliateTypes` field list). One Medium
remained: a WI-ownership wording inconsistency — the relocate-payload
work was attributed to WI-2 in Risk 5 / §7 / the test catalogue though
WI-2 is defined as selection-payload only. Auditor verdict:
*accept-with-rationale — "does not genuinely block Gate 2; it is a
planning consistency cleanup, not a missing safety/control mechanism."*
Fixed in v4 (relocate-payload work attributed to WI-8 only).

**Gate 2 verdict: PASSED.** Zero open Critical/High/Medium findings;
rule-47 3-round ceiling respected (12 findings round 1, 3 round 2, 1
round 3 — each resolved). The plan is audited and ready; **Gate 3 does
not start until §9 G1 human ratification.**

### Test catalogue

| Test file | Covers | WI |
|---|---|---|
| `FoliateMessageParserTests` (extend) | selection `href`+range fields (WI-2); relocate `href`+`progression` fields (WI-8) | WI-2, WI-8 |
| `FoliateURLSchemeHandlerTests` | §5 allowed-root contract; `../`/absolute/symlink-escape rejection; ES-module MIME | WI-7 |
| `FoliateReaderViewModel+EPUBTests` | EPUB open; CFI ↔ `Locator`; legacy `href+progression` resolution; malformed/missing-spine CFI | WI-7/8 |
| `FoliateHighlightRendererTests` | `apply`/`remove`/`restore(records:forHref:using:)`; restore idempotency; overlapping ranges; CJK/RTL anchors | WI-4 |
| `FoliateEPUBHighlightAnchorTests` | real `AnnotationAnchor.epub` create/restore; **legacy-bridge highlight re-anchoring** | WI-9 |
| `FoliateTOCConverter+EPUBTests` | EPUB spine → hierarchical `[TOCEntry]`; nesting; empty TOC; nav-doc vs NCX | WI-10 |
| `FormatCapabilitiesTests` (extend) | EPUB capability set byte-identical pre/post-migration | WI-6 |
| `Feature42FoliateEPUBVerificationTests` (XCUITest) | end-to-end: open / highlight / paginate / TOC nav / dictionary / search-jump / TTS / footnote; fixed-layout slice; complex-EPUB slice | WI-15 |

**Audit-driven additions:** malformed CFI; EPUB with a missing/corrupt
spine item; highlight-restore idempotency on repeated section loads; a
fixture book carrying **legacy-bridge-created** highlights opened under
Foliate (the single most important back-compat test — fixture gap below).

> **Fixture gap.** DebugBridge ships `mini-epub3`. The legacy-highlight
> re-anchoring test needs a fixture *with persisted legacy highlights* —
> WI-15 must add a launch-arg seed (`--seed-epub-legacy-highlights`) or
> script highlight creation on the legacy engine first.
