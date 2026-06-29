# Android feature checklist — the finite definition of "parity" (feature #110)

**Why this file exists.** Feature #110 ("Android Phase-3 capability parity") was an *unbounded*
driver — "bring Android to parity, decomposed per-capability" with no checkable terminal state. That
let every session reach "zero open issues" and read it as done while parity wasn't reached. **This
checklist is the fix: a finite, checkable list.** Android parity = every box below checked. When the
last unchecked box reaches `VERIFIED`, #110 is complete (modulo the explicit DEFERRED row).

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
- [x] **Backup & WebDAV restore UI** — the 5 designed Compose surfaces — #114 (`android/v0.6.0`)
- [x] **OPDS catalog backend** — feed parse + HTTP + acquisition→import — #117
- [x] **OPDS catalog UI** — source list + add/edit + browse + download → in-library — #120 (`android/v0.8.1`–`v0.8.4`)
- [x] **AI provider + chat/summary** — provider list/editor + OpenAI-compat & Anthropic SSE + chat panel — #118 (`android/v0.8.0`)
- [x] **TTS read-aloud** — `TextToSpeech` engine + control bar + voice/speed sheets + TXT highlight — #121 (`android/v0.8.5`–`v0.9.0`)

---

## 🔨 Remaining to reach parity (the build queue)

The finite list. Each is autonomously buildable (its design is committed; none is design-blocked).
Build order is roughly reuse-leverage / dependency order.

- [x] **A. Reading stats** — in-reader session pill + time-detail card + dashboard (window bar · hero ·
  14-day chart · per-book table) over a Room reading-time tracker.
  Design: `vreader-stats-android.jsx`. Status: **VERIFIED 2026-06-28** — #122, all 4 WIs merged
  (`android/v0.9.1`→`v0.10.0`); Gate-5b `dev-docs/verification/feature-122-20260628.md` (`result: pass`).
  GH #1828 closed.

- [~] **B. Highlights & annotations** — in-reader text-selection popover (5 colors · highlight · note ·
  copy · translate · share) + the annotations review sheet (highlights / notes / bookmarks filter).
  Design: `vreader-android-annotations.jsx` (+ `vreader-annotations.jsx`).
  Needs: a highlights/notes/bookmarks Room schema (migration) + reader text-selection integration
  (Readium decorations for EPUB; TXT/MD selection). iOS parity: #62.
  Status: **IN PROGRESS** — decomposed into 3 features (Gate-2 entry-point decision).
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
  **Remaining for box B: the annotations review sheet + bookmark creation** (ride with item **F**, which
  owns the chrome entry). Box checks when those land with F.

- [~] **C. Library management — collections + search** — a collections shelf-bar over the grid +
  manage/assign sheets + search (metadata hits split from in-text hits).
  Design: `vreader-library-android.jsx` (+ `vreader-search.jsx`).
  Needs: a collections Room schema (+ book↔collection join) + a search index. iOS parity: #60.
  **IN PROGRESS — split into two features (Gate-2 decision): #127 collections (GH #1869, PLANNED — Gate-2
  clean, 2 Codex rounds; collections are backup-contract-bound so #127 wires backup/restore) + #128 search
  (Android `Book` has no author field + no cross-format FTS → search design/data gap, filed separately).
  Box C checks when BOTH #127 and #128 are VERIFIED.**

- [ ] **D. Bilingual interlinear reading** — interlinear original+translation rendering + the bilingual
  setup sheet (languages · provider · model · style), building on the #118 AI provider.
  Design: `vreader-ai-android.jsx` (BilingualReader/BilingualSetupSheet) + `vreader-bilingual.jsx`.
  Note: the pipeline + UI are buildable autonomously; LIVE translation verification is
  AI-credential-gated (a mock/integration path verifies the pipeline). iOS parity: #56/#100.

- [ ] **E. Reader display settings** — the Aa sheet: theme (the 5 reader themes), font family/size,
  line spacing, layout (scroll/paged) — applied across the EPUB/TXT/MD/PDF readers.
  Design: `vreader-themes.jsx` + `vreader-panels.jsx` (+ `vreader-reader.jsx` chrome).
  Needs: an Android `ReaderSettingsStore` (DataStore) + per-host application. iOS parity: #60 WI-10.

- [ ] **F. Reader navigation chrome** — the designed top/bottom reader bars hosting: Contents (TOC) +
  bookmarks, find-in-book (in-reader text search), and the More menu (book details · share · export).
  Design: `vreader-reader.jsx` + `vreader-panels.jsx` + `vreader-more.jsx` + `vreader-book-details.jsx`
  + `vreader-search.jsx`. (The TTS Read-aloud entry from #121 already added the bottom-bar slot.)
  Likely splits into ≥2 features (TOC/bookmarks; find-in-book; more-menu/details/share). iOS parity:
  #60 WI-6 (chrome), #61 (details), #62 (TOC/bookmarks).

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

## Definition of done

- **Autonomous parity reached** when A–F are all `[x] VERIFIED`.
- **Full parity** additionally requires the AZW3 go/no-go decision (the one DEFERRED row).
- Each item, when started: file a `docs/features.md` row (status → `PLANNED` after its Gate-2 plan
  audit) + a GH issue, run the 6 gates, then check its box here on VERIFIED.

> Maintenance: update this checklist's boxes in lock-step with `docs/features.md` status flips, and keep
> `docs/parity/README.md`'s capability rows current (it drifted — OPDS/TTS were marked unbuilt after
> they shipped). A box here is the single visible signal of remaining Android-parity work.
