# Android feature checklist — the finite definition of "parity" (feature #110)

**Why this file exists.** Feature #110 ("Android Phase-3 capability parity") was an *unbounded*
driver — "bring Android to parity, decomposed per-capability" with no checkable terminal state. That
let every session reach "zero open issues" and read it as done while parity wasn't reached. **This
checklist is the fix: a finite, checkable list.** Android parity = every box below checked. When the
last unchecked box reaches `VERIFIED`, #110 is complete (modulo the explicit DEFERRED row).

> **STATUS 2026-08-04 — boxes A–F are all complete; #110 is DONE.** But A–F were the
> *capability-block* definition of parity ("does Android have a reader / library / backup / AI / TTS
> at all"), not feature-for-feature parity: iOS shipped ~90 VERIFIED features and Android implements
> roughly a third of them. A code-level sweep on 2026-08-04 found **31 concrete remaining gaps**,
> filed as rows **#139–#171** and organised into boxes **G0–G8** in the
> [Phase 4](#phase-4--the-remaining-iosandroid-gap-filed-2026-08-04) section below. **Phase 4 is the
> live build queue; A–F below are history — do not re-open them.**

Each unchecked item is built as its own feature through the rule-47 6-gate workflow (`/feature-workflow`),
gets its own `docs/features.md` row + GH issue when started, and is checked off here when VERIFIED.

Source of truth for capability status: `docs/parity/README.md` (the iOS↔Android ledger). This file is
the **build queue** distilled from it.

**Legend:** `[x]` VERIFIED on Android · `[~]` in progress · `[ ]` not started · `[-]` deferred (explicit
go/no-go). "Design" = the committed `dev-docs/designs/vreader-fidelity-v1/project/<file>` the build
implements (rule 51). Per feature #106, iOS design bundles reuse cleanly for Android, so the
iOS-authored bundles below are valid Android design sources.

---

## ✅ Shipped (VERIFIED on Android)

These are done — listed so progress is visible and parity isn't re-litigated.

- [x] **Foundation bar** — DI container, Library list + SAF import + content-hash dedup, identity/locator/backup contracts (`:identity`) — #106 (`android/v0.1.0`–`v0.3.0`)
- [x] **EPUB reader** — Readium open/parse/render (scroll) + precise-first resume — #106 WI-9
- [x] **TXT reader** — encoding-detected decode + resume — #111 (`android/v0.4.0`)
- [x] **Markdown (.md) reader** — `MarkdownRenderer` over the TXT host — #112 (`android/v0.5.0`)
- [x] **PDF reader** — `PdfRenderer` continuous scroll + page resume — #115 (`android/v0.7.0`)
- [x] **Backup format model** — `@Serializable` DTOs, golden-vector conformance — #113 (`android/v0.6.1`)
- [x] **WebDAV backup/restore backend** — client + blob store + collector/importer (live rclone round-trip) — #116 (`android/v0.7.7`)
- [~] **Backup & WebDAV restore UI** — the 5 designed Compose surfaces — #114 (`android/v0.6.0`).
  **UNCHECKED 2026-08-04 — UNREACHABLE**: zero production call sites; only launcher is
  `src/debug/BackupDebugActivity`, excluded from the release APK. Blocked on #171 / needs-design #2018.
- [x] **OPDS catalog backend** — feed parse + HTTP + acquisition→import — #117
- [~] **OPDS catalog UI** — source list + add/edit + browse + download → in-library — #120 (`android/v0.8.1`–`v0.8.4`).
  **UNCHECKED 2026-08-04 — UNREACHABLE**: `OpdsSourceListScreen`/`OpdsBrowseScreen`/`OpdsAddSheet`
  have zero production call sites. Blocked on #171 / needs-design #2018.
- [~] **AI provider + chat/summary** — provider list/editor + OpenAI-compat & Anthropic SSE + chat panel — #118 (`android/v0.8.0`).
  **UNCHECKED 2026-08-04 — PARTLY UNREACHABLE**: `AiChatPanel` + `AiProviderListScreen` have zero
  production call sites (provider *config* was later reachable via #131's bilingual Set-up flow, but
  chat/summarize never was). Blocked on #171 / needs-design #2018.
- [x] **TTS read-aloud** — `TextToSpeech` engine + control bar + voice/speed sheets + TXT highlight — #121 (`android/v0.8.5`–`v0.9.0`)

---

## 🔨 Remaining to reach parity (the build queue)

The finite list. Each is autonomously buildable (its design is committed; none is design-blocked).
Build order is roughly reuse-leverage / dependency order.

- [~] **A. Reading stats** — in-reader session pill + time-detail card + dashboard (window bar · hero ·
  14-day chart · per-book table) over a Room reading-time tracker.
  **UNCHECKED 2026-08-04 — DASHBOARD UNREACHABLE**: `StatsDashboard` has zero production call sites.
  The tracker backend is live and the in-reader pill IS reachable, so time is recorded but the
  dashboard can never be opened. Blocked on #171 / needs-design #2018.
  Design: `vreader-stats-android.jsx`. Status: **VERIFIED 2026-06-28** — #122, all 4 WIs merged
  (`android/v0.9.1`→`v0.10.0`); Gate-5b `dev-docs/verification/feature-122-20260628.md` (`result: pass`).
  GH #1828 closed.

- [x] **B. Highlights & annotations** — in-reader text-selection popover (5 colors · highlight · note ·
  copy · translate · share) + the annotations review sheet (highlights / notes / bookmarks filter).
  Design: `vreader-android-annotations.jsx` (+ `vreader-annotations.jsx`).
  Needs: a highlights/notes/bookmarks Room schema (migration) + reader text-selection integration
  (Readium decorations for EPUB; TXT/MD selection). iOS parity: #62.
  Status: **VERIFIED 2026-07-12** — decomposed into 3 highlight features (#123/#124/#125) + the annotations
  review sheet (#132) + bookmark creation/list (#135); all VERIFIED. Box B COMPLETE.
  **#123 EPUB highlighting VERIFIED 2026-06-28** (`android/v0.11.0`, GH #1835 closed: schema +
  domain + Readium selection/decoration + edit/remove, on-device-verified incl. live-navigator render).
  **#124 TXT highlighting VERIFIED 2026-06-28** (`android/v0.12.0`, GH #1841 closed: custom Compose
  long-press-drag selection + wash render + tap-edit/remove; the gesture is automatable via the Compose
  harness).
  **#125 MD highlighting VERIFIED 2026-06-29** (`android/v0.13.0`, GH #1847 closed: `MarkdownRenderer.renderWithMap`
  per-char source spans + `MarkdownOffsetMap`/`ChunkTextMapper` rendered↔source conversions threaded
  through the selection controller + wash + `TxtReaderActivity` — the `BookFormat.txt` gate is gone, so
  MD select→highlight/note/copy/share→persist→wash→tap-edit/remove works on the same engine TXT uses;
  evidence `dev-docs/verification/feature-125-20260629.md`).
  **Box B complete**: the annotations review sheet landed with **#132 VERIFIED 2026-07-11** (`android/v0.15.3`,
  GH #1924) and bookmark creation/toggle/list/jump with **#135 VERIFIED 2026-07-12** (`android/v0.17.2`,
  GH #1927 closed; evidence `dev-docs/verification/feature-135-20260712.md` — live-WebDAV bookmark
  round-trip UUID-preserving + toggle/list/jump across all 5 formats).

- [x] **C. Library management — collections + search** — a collections shelf-bar over the grid +
  manage/assign sheets + search (metadata hits split from in-text hits).
  Design: `vreader-library-android.jsx` (+ `vreader-search.jsx`).
  Needs: a collections Room schema (+ book↔collection join) + a search index. iOS parity: #60.
  **IN PROGRESS — split into two features (Gate-2 decision): #127 collections (GH #1869, **VERIFIED
  2026-06-29** `android/v0.13.7` — shelf-bar + assign/manage sheets + collections.json backup/restore
  proven end-to-end over live WebDAV; delete UI deferred to needs-design #1875) + #128 search (Android
  `Book` has no author field + no cross-format FTS → search design/data gap, filed separately — NOT yet
  done). Box C checks when BOTH #127 and #128 are VERIFIED — #127 ✓, #128 remains.**
  **COMPLETE 2026-07-14: #128 search VERIFIED (GH #1901) — the "NOT yet done" note above is stale; both #127 and #128 VERIFIED, box C COMPLETE.**

- [x] **D. Bilingual interlinear reading** — interlinear original+translation rendering + the bilingual
  setup sheet (languages · provider · model · style), building on the #118 AI provider.
  Design: `vreader-ai-android.jsx` (BilingualReader/BilingualSetupSheet) + `vreader-bilingual.jsx`.
  Note: the pipeline + UI are buildable autonomously; LIVE translation verification is
  AI-credential-gated (a mock/integration path verifies the pipeline). iOS parity: #56/#100.
  **VERIFIED 2026-07-14 — #131 (GH #1923 closed, `android/v0.19.0`); box D COMPLETE.**

- [x] **E. Reader display settings** — the Aa sheet: theme (the 5 reader themes), font family/size,
  line spacing, layout (scroll/paged) — applied across the EPUB/TXT/MD/PDF readers.
  Design: `vreader-themes.jsx` + `vreader-panels.jsx` (+ `vreader-reader.jsx` chrome).
  Needs: an Android `ReaderSettingsStore` (DataStore) + per-host application. iOS parity: #60 WI-10.
  **IN PROGRESS — split (Gate-2 decision): #129 (GH #1879, PLANNED — Gate-2 clean 3 Codex rounds) is the
  TYPOGRAPHY slice (5 themes + font family/size + line spacing + margin + the designed `ReaderBottomChrome`
  Display slot); the LAYOUT (scroll/paged) toggle is a separate tracked follow-up (TXT/MD are scroll-only
  Compose hosts → needs a paged renderer first; a layout toggle there would be a non-functional control).
  Box E checks when BOTH #129 AND the layout follow-up are VERIFIED.**
  **RECONCILED 2026-07-14: #129 typography VERIFIED (GH #1879); the LAYOUT (scroll/paged) toggle is now filed as **feature #137** (PLANNED — Gate-1 v4 + Gate-2 passed 3 Codex rounds, GH #1990; 12 WIs, incl. a new Compose paged text renderer for TXT/MD). Box E checks when #137 VERIFIED.**
  **COMPLETE 2026-07-15: #137 VERIFIED (android/v0.20.6, GH #1990 closed; evidence `dev-docs/verification/feature-137-20260715.md`) — the layout toggle + Compose paged renderer (TXT/MD) + EPUB Readium pagination shipped with every paged feature (selection/highlight/bookmark/find/TTS/bilingual-gate) verified on emulator-5554. Box E COMPLETE. This was the LAST unchecked capability box → #110 DONE. One non-blocking perf follow-up (#138: opt-in large-doc paged phase-1 latency, ~96s on a real 14MB CJK book measured in WI-11).**

- [x] **F. Reader navigation chrome** — the designed top/bottom reader bars hosting: Contents (TOC) +
  bookmarks, find-in-book (in-reader text search), and the More menu (book details · share · export).
  Design: `vreader-reader.jsx` + `vreader-panels.jsx` + `vreader-more.jsx` + `vreader-book-details.jsx`
  + `vreader-search.jsx`. (The TTS Read-aloud entry from #121 already added the bottom-bar slot.)
  Likely splits into ≥2 features (TOC/bookmarks; find-in-book; more-menu/details/share). iOS parity:
  #60 WI-6 (chrome), #61 (details), #62 (TOC/bookmarks).
  Status: **IN PROGRESS** — the chrome shell + Contents/TOC (**#132 VERIFIED 2026-07-11**, `android/v0.15.3`,
  GH #1924), the More menu + Book Details + Share (**#134 VERIFIED 2026-07-11**, `android/v0.16.1`, GH #1926),
  and Contents+**bookmarks** (**#135 VERIFIED 2026-07-12**, `android/v0.17.2`, GH #1927) are all VERIFIED.
  **Box F COMPLETE 2026-07-14: find-in-book #133 VERIFIED** (`android/v0.18.2`, GH #1925 closed). All box-F
  sub-features — TOC/bookmarks (#132/#135), More/Details/Share (#134), find-in-book (#133) — are VERIFIED.

### Deferred (explicit go/no-go — not autonomously startable)

- [x] **AZW3 / MOBI / KF8 reader** → **feature #126 VERIFIED 2026-06-29** (`android/v0.12.9`, GH #1851
  closed; evidence `dev-docs/verification/feature-126-20260629.md`). WebView + pinned security-patched
  foliate-js bundle (NO NDK); render/resume/page-turn/secure-bridge/backup all pass on the real 6 MB CJK
  AZW3 (API-35). The final blocker (bug #357 — page-turn stuck on screen 1 = a 0-height Compose WebView
  viewport) is fixed (MATCH_PARENT LayoutParams + `100dvh`). **Go/no-go = GO**
  (user, 2026-06-29: "the azw3 is needed"). **Framing corrected**: iOS does NOT read these via libmobi —
  it renders them with **foliate-js (`mobi.js`) in a WKWebView** (`FoliateSpikeView`); libmobi is auxiliary
  (metadata/cover/convert). So Android's path is a **`WebView` + pinned foliate-js host** (mirror
  `FoliateSpikeView`), NOT a "large HIGH-risk NDK port". Prior art: Anx-Reader, Readest. **Gated on a
  go/no-go Spike #1** (WebView↔native **bridge security** is the #1 risk: `WebViewCompat.addWebMessageListener`
  + `WebViewAssetLoader`, never `addJavascriptInterface`) before any WIs — run via `/feature-workflow #126`.
  iOS parity: Foliate path.

---

---

# Phase 4 — the remaining iOS↔Android gap (filed 2026-08-04)

**Why there is a phase 4.** Boxes A–F were the *capability-block* definition of parity: does Android
have a reader, a library, backup, AI, TTS, annotations at all. They are all `[x]`. But iOS shipped
~90 VERIFIED features and Android implements roughly a third of them, so "every box checked" ≠ "the
two apps do the same things". A 2026-08-04 code-level sweep (iOS `docs/features.md` VERIFIED rows ×
the actual `android/app/src/main/kotlin` surface) found **31 concrete gaps**, now filed as
`docs/features.md` rows **#139–#171**.

These are deliberately *small* features (2–6 WIs each) so they can be run in batches, several lanes
at a time, through `/dispatch` (rule 55) or `/feature-workflow` individually.

**Legend:** same as above. Each box lists its feature row; dependency edges are the machine-readable
`Deps:[…]` tokens in the tracker (`scripts/deps-check.sh feature <id>` is the gate — nothing
dispatches that isn't READY).

## G0. Reachability — the Settings hub (BLOCKS the value of four shipped features)

> **Found 2026-08-04.** Boxes A–F certified *"the code exists and its tests pass"*, not *"a user can
> open it"*. Four features shipped `VERIFIED` with UI that has **zero call sites** in
> `android/app/src/main/kotlin`. This box exists so parity can never again be declared on
> unreachable code.

- [ ] **#171 Settings hub + production entry-point wiring** — `MainActivity` hosts only Library +
      Search; no `SettingsScreen` has ever existed on Android. Wiring it makes #114 (backup/WebDAV
      UI), #118 (AI chat + provider list), #120 (OPDS UI) and #122 (stats dashboard) reachable, and
      is the acceptance criterion for those four re-earning `VERIFIED`.
      **BLOCKED: needs-design (#2018)** — the hub's *content* is designed for iOS
      (`vreader-panels.jsx:810-901` + `diagnostics-artboards.jsx:28-83`) and reuses per #106, but the
      Android **entry point** is not: `vreader-library-android.jsx:99-132` shows only Search + More
      with no Settings icon and no depicted destination, which *contradicts* the iOS default rather
      than merely omitting it — so the #106 reuse policy does not cover it.

**Highest-value item in phase 4**: it ships no new capability and makes four existing ones usable.

## G1. Reader navigation — Contents (TOC) on every format

- [ ] **#139 TXT/MD auto-generated TOC** — TXT/MD hide Contents entirely today. iOS: #23 + #12.
- [ ] **#140 AZW3 Contents (TOC)** — foliate exposes a real TOC; Android hides it. iOS: #38.
- [ ] **#141 Filterable TOC** — designed filter field (`toc-filter-artboards.jsx`). iOS: #94.
      `Deps:[feat:#139, feat:#140]`.
- *Out of scope*: PDF outline — `android.graphics.pdf.PdfRenderer` has no outline API (see #167).

## G2. Reader text interaction

- [ ] **#142 AZW3 text selection + highlights/notes** — the only reader with zero annotation
      capability. Bridge-security-sensitive (rule 54). iOS: #11/#64.
- [ ] **#143 Selection-popover actions — translate · define · Ask AI** — Android offers only
      Highlight/Note/Copy/Share/Remove. iOS: #33 + #78.

## G3. AI parity (all build on #118's `AiClient`)

> These five share the `ai/` write-set — run them **sequentially within a batch** (rule 48,
> one writer per area), not fanned out concurrently.

- [ ] **#144 AI stop/cancel control** — no Stop affordance exists. iOS: #87.
- [ ] **#145 AI conversation sessions + WebDAV backup** — one implicit thread, no history.
      iOS: #88 + #89. `Deps:[feat:#144]`.
- [ ] **#146 Summarize scope selector + bilingual summary** — summary is chapter-fixed and
      monolingual. iOS: #69 + #90.
- [ ] **#147 Expanded AI reading scope & sources** — narrow context window. iOS: #86.
      `Deps:[feat:#145]`.
- [ ] **#148 Agentic tool-calling + library tool** — no tool-use at all. iOS: #91 + #97.
      `Deps:[feat:#144]`.

## G4. Text-to-speech beyond TXT

- [ ] **#149 EPUB TTS + sentence highlight + auto-advance** — TTS is wired ONLY into
      `TxtReaderActivity`. iOS: #26/#40/#41. *Highest-visibility TTS gap.*
- [ ] **#150 AZW3 TTS** — iOS: #57. `Deps:[feat:#142]` (shares the foliate bridge work).
- [ ] **#151 HTTP cloud TTS provider** — on-device engine only. iOS: #72. `Deps:[feat:#149]`.

## G5. Library

- [ ] **#152 Generative typographic covers** — every book renders a flat 5-tint `FallbackCover`;
      iOS ships the design's 5 style families × 12 `COVER_PALETTES`, assigned deterministically from
      `fingerprintKey`. iOS: **#60 WI-10**. **Highest user-visible gap in phase 4.**
      *Re-scoped during Gate 1*: iOS #43 (extract embedded art) was superseded by #60 WI-10 — iOS
      feeds its cover image slot from `CustomCoverStore` only and never displays publisher artwork,
      so an extraction pipeline would be non-parity work. Determinism must use FNV-1a (not
      `hashCode()`) so a book gets the same cover on both platforms.
- [ ] **#153 Custom book covers** — iOS: #30. `Deps:[feat:#152]`.
- [ ] **#154 Library sort order** — no sort exists. iOS: #20. `Deps:[feat:#152]`.
- [ ] **#155 Open-with / system document handler** — manifest declares LAUNCHER only, so vreader
      never appears as a share/open target. iOS: #59. *Disjoint — good concurrent-lane partner.*

## G6. Reader settings & typography

- [ ] **#156 Justified text (TXT/MD + EPUB)** — all text is ragged-right. iOS: #92 + #95.
- [ ] **#157 Configurable tap zones** — zones are hard-coded. iOS: #25.
- [ ] **#158 Auto page turning** — iOS: #31. `Deps:[feat:#157]`.
- [ ] **#159 Per-book reading settings** — settings are global-only. iOS: #37. `Deps:[feat:#156]`.
- [ ] **#160 Reading theme backgrounds** — 5 flat themes only. iOS: #32. `Deps:[feat:#156]`.

## G7. Bilingual completion (over #131)

- [ ] **#161 Chapter-heading translation** — body blocks only today. iOS: #100.
- [ ] **#162 Change target language / granularity after setup** — iOS: #99. `Deps:[feat:#161]`.
- [ ] **#163 Whole-book translation job + background resilience** — per-chapter on-demand only.
      iOS: #56 + #98. `Deps:[feat:#162]`.

## G8. Diagnostics & data portability

- [ ] **#164 Diagnostics — log capture + viewer/export** — nothing exists; this is what makes
      user-reported Android issues diagnosable without a cable. iOS: #96. *Fully disjoint.*
- [ ] **#165 Export / import annotations** — share-as-text only. iOS: #35.
- [ ] **#166 Content replacement rules + S/T Chinese conversion** — iOS: #27 + #28.
      *Offset-safety is the hard part* (annotations anchor on source offsets).

### Deferred (tracked, not queued — each needs a go/no-go or a fixture)

- [-] **#167 PDF text-layer highlights** — `PdfRenderer` exposes no text API; needs a third-party
      PDF text engine (size/license/security review). Same posture #126 had pre-GO. iOS: #17.
- [-] **#168 Book source scraping (web novels)** — largest single remaining item, least load-bearing
      for core reading, and rule-54-sensitive (untrusted remote content). iOS: #24.
- [-] **#169 RTL / vertical-writing rendering** — no real RTL or tategaki book exists in
      `test-books/books/`, so Gate-5 could not verify it against a real book. iOS: #75 + #76.

## Suggested batch order (dependency- and write-set-aware)

| Batch | Rows | Why grouped |
| --- | --- | --- |
| 1 | #152, #155, #164 | Three fully disjoint write-sets (library covers · manifest · new diagnostics module) — safe true fan-out, and #152 is the biggest visible win. |
| 2 | #139, #140, #142 | Reader nav + AZW3 bridge; disjoint from each other. #141 follows once both TOC providers land. |
| 3 | #144 → #145 → #148, then #146, #147 | The AI block. Shared `ai/` write-set ⇒ sequential within the batch. |
| 4 | #149, #143, #154, #153 | EPUB TTS (big, disjoint) alongside the selection-popover actions and the library follow-ons. |
| 5 | #156, #157, #161, #165 | Typography + tap zones + bilingual headings + annotation export — disjoint areas. |
| 6 | #158, #159, #160, #162, #163, #150, #151, #166, #141 | The dependent tail, unblocked by batches 2–5. |

## Definition of done (phase 4)

- **Reachability is part of done.** A box may only be checked when the capability is exercised
  through a **production entry point in a release-configured build** — the path a real user takes.
  A DEBUG-source-set launcher, a `vreader-debug://` command, or a test invoking a composable
  directly does **not** count (rule 47 Gate 5, "Production reachability"). This clause exists
  because A–F were all checked while four features were unreachable.
- **Phase-4 parity reached** when G0–G8 are all `[x] VERIFIED` (the three DEFERRED rows excepted,
  pending their go/no-go). **G0 is the gating item** — until it lands, four already-shipped features
  remain unusable.
- Each row follows the standard rule-47 6 gates: it gets its GH issue at the Gate-2 → `PLANNED`
  flip, and its box is checked here on `VERIFIED`.
- **Do not re-open the A–F boxes** — they are the capability-block definition and are complete.

---

## Definition of done (phases 0–3 — historical)

- **Autonomous parity reached** when A–F are all `[x] VERIFIED`.
- **STATUS 2026-07-14:** A/B/C/D/F ✅ VERIFIED; AZW3 ✅ (GO, #126). **The ONLY remaining box is E's layout (scroll/paged) toggle → feature #137** (PLANNED, GH #1990; Gate-2 passed 3 Codex rounds; 12 WIs incl. a new Compose paged text renderer for TXT/MD). When #137 reaches VERIFIED, box E checks and **all boxes complete → driver #110 → DONE.**
- **Full parity** additionally requires the AZW3 go/no-go decision (the one DEFERRED row).
- Each item, when started: file a `docs/features.md` row (status → `PLANNED` after its Gate-2 plan
  audit) + a GH issue, run the 6 gates, then check its box here on VERIFIED.

> Maintenance: update this checklist's boxes in lock-step with `docs/features.md` status flips, and keep
> `docs/parity/README.md`'s capability rows current (it drifted — OPDS/TTS were marked unbuilt after
> they shipped). A box here is the single visible signal of remaining Android-parity work.
