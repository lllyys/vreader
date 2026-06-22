# Six Android Phase-3 needs-design issues — design notes (batch 2)

> Resolves the design gaps blocking [#1797](https://github.com/lllyys/vreader/issues/1797), [#1798](https://github.com/lllyys/vreader/issues/1798), [#1799](https://github.com/lllyys/vreader/issues/1799), [#1800](https://github.com/lllyys/vreader/issues/1800), [#1801](https://github.com/lllyys/vreader/issues/1801), [#1802](https://github.com/lllyys/vreader/issues/1802) — all children of the [#110](https://github.com/lllyys/vreader/issues/110) Android Phase-3 capability-parity driver. Follows the batch-1 note (`android-phase3-issues.md`, #1766/#1767).

All six are blocked by Rule 51 (UI from the committed design bundle only). iOS gets these surfaces from system components or already-shipped subsystems; Android has the data/runtime layer (Room, `android.speech.tts.TextToSpeech`, the OPDS client, the AI provider client) but no UI, so each user-facing surface had to be designed. Every design is rendered in VReader's existing vocabulary — the reader `THEMES`, Source-Serif titles, `#8c2f2f` / `#d6885a` accent, rounded-14 cards, and the AI-provider/backup form primitives (`UI`, `Card`, `Row`, `GroupHeader/Footer`, `Tag`, `PhoneFrame`, `AppSheet`) — so Android reads as the same product, **not a Material re-skin**. Each canvas shows every state across the paper and dark themes.

| Issue | Canvas | Component file | Artboards |
|---|---|---|---|
| #1797 TTS read-aloud | `VReader TTS Read-Aloud Canvas.html` | `vreader-tts.jsx` | `tts-artboards.jsx` |
| #1801 Highlights + annotations | `VReader Highlights & Annotations Canvas.html` | `vreader-android-annotations.jsx` | `android-annotations-artboards.jsx` |
| #1802 Library management | `VReader Library Management Canvas.html` | `vreader-library-android.jsx` | `library-android-artboards.jsx` |
| #1800 Reading-stats | `VReader Reading Stats Canvas.html` | `vreader-stats-android.jsx` | `stats-android-artboards.jsx` |
| #1799 OPDS catalog | `VReader OPDS Catalog Canvas.html` | `vreader-opds.jsx` | `opds-artboards.jsx` |
| #1798 AI provider + bilingual + chat | `VReader AI Provider & Chat Canvas.html` | `vreader-ai-android.jsx` | `ai-android-artboards.jsx` |

`vreader-tts.jsx` also exports the reader frame chrome (`TtsFrame`, `StatusStrip`, `ReaderChrome`, `ReaderProse`) reused by the annotations, library, stats, bilingual and chat canvases, so every in-reader surface shares one device frame and top bar.

---

## #1797 · TTS read-aloud control bar

**Decision: a glassy transport docked at the foot of the reader — not a system media-notification surrogate.** Component: `vreader-tts.jsx` (`TtsBar`, `TtsScreen`, `VoiceSheet`, `SpeedSheet`, `TtsEntry`).

iOS reads aloud through `AVSpeechSynthesizer`; Android has on-device `android.speech.tts.TextToSpeech` (no credentials, multiple engines). The control bar owns play/pause, sentence prev/next, speed, and a voice/engine chip; a chunk-progress line rides the bar's top edge. The page behind highlights the **spoken sentence** with an accent wash + a left keyline — sentences already read dim to the secondary ink, upcoming text stays full-strength — and an auto-scroll keepline holds the spoken line in view.

- **Entry** is the reader's own bottom toolbar (the Volume item, beside Contents / Aa / AI) — no new navigation.
- **States:** idle (ready, not started), speaking, paused (highlight retained), and **error/unavailable** — no installed voice for the book's language → one primary CTA ("Install voice data") + a secondary jump to System TTS.
- **Voice & engine** is the genuinely-Android surface: pick the on-device engine (Google / Samsung), then a per-language voice; uninstalled voices show a sized **Download**, one is mid-install. iOS's AVSpeech surface has none of this.
- **Speed** is a slider + preset pills (0.5×–2.0×) with the current rate set large for at-a-glance legibility while listening.

---

## #1801 · Highlights + annotations

**Decision: one popover does double duty (fresh selection + tap-on-existing-highlight); the review list renders all three record kinds with a filter whose *Notes* merges by intent, not anchor.** Component: `vreader-android-annotations.jsx`.

- **In-reader (A):** press-and-hold selects a passage (blue handles); a popover with a downward notch floats above it carrying 5 highlight colors + Highlight / Note / Copy / Translate / Share. Picking a color highlights in place; **Note** swaps the action row for an inline compose (no jump to a separate editor for a one-liner). Tapping a saved highlight re-opens the same popover scoped to edit/recolor/remove.
- **Review (B):** a filter chip row (All · Highlights · Notes · Bookmarks). `HighlightCard` carries a color rule + optional note; `StandaloneNoteCard` (a note with no passage behind it) uses a **dashed** accent rule + a `STANDALONE` pill; bookmarks are a compact locator row. The **Notes filter merges highlight-notes and standalone notes** — notes are notes regardless of anchor (mirrors the iOS #860 decision). Per-book and library-wide (grouped under book headers); empty and edit states.

---

## #1802 · Library management (collections + search)

**Decision: collections are a horizontal shelf-bar over the grid (not a separate tab); two collections are derived from progress and locked; search splits metadata hits from in-text hits.** Component: `vreader-library-android.jsx`. Covers are typographic (a tonal card + serif title), never illustrated art.

- **Library (A):** the 2-up cover grid with the collection chip-bar pinned under the title; covers carry a reading-progress hairline. Tapping a chip scopes the grid and swaps the header to the collection name + count + edit affordance.
- **Manage & assign (B):** the collections manager (rename / reorder / delete, create-new inline) and the per-book **Assign** sheet (a checklist, so one book can sit on several shelves). *Currently Reading* and *Finished* update from progress automatically and can't be deleted.
- **Search (C):** empty (recent searches + browse-by-collection), results, no-results. Results split **metadata hits** (title/author, matched span washed) from **in-text hits** (a serif snippet with the matched word) so a half-remembered phrase still surfaces its book. Every state names what search actually covers.

---

## #1800 · Reading-stats surfaces

**Decision: the in-reader surface stays out of the way (auto-fading pill → expandable detail card); the dashboard is window-bar-driven.** Component: `vreader-stats-android.jsx`.

- **In-reader (A):** a glassy **session pill** rides the top-right and fades after a few seconds; the progress area expands the full **time detail card** — session · book total · time-left estimates · current pace.
- **Dashboard (B):** a time-window chip bar (Today · 7d · 30d · 90d · Year · All) drives everything below — an hour hero (with streak / daily-avg / finished), a 14-day daily-reading column chart (today tinted), and a per-book table sortable by Time / Highlights / Notes. The **Time column drives a per-row hairline bar** so relative magnitude reads even after re-sorting. **No-data** isn't a blank screen: the hero becomes a one-line nudge and every module keeps its frame.

---

## #1799 · OPDS catalog browse/add/download

**Decision: honor both OPDS feed kinds explicitly; reuse the backup/AI form vocabulary so catalogs feel like one system with Settings; every error names its HTTP cause + one CTA.** Component: `vreader-opds.jsx`. The backend (feed parser, HTTP client, acquisition→import) ships separately and isn't design-gated.

- **Source list (A):** saved catalogs with a live status dot + exact host (or failure reason); empty onboards by naming compatible catalogs (Standard Ebooks, Project Gutenberg, a self-hosted Calibre server).
- **Add/edit (B):** Name · URL · optional sign-in (the toggle reveals username/password). Test Connection runs against the live form and reports inline; edit adds Remove Catalog.
- **Browse (C):** **navigation** feeds render as folder rows (with entry counts, drill in); **acquisition** feeds as book entries (cover · title · author · EPUB · download). Every per-entry state lives on the row — get / downloading (radial) / in-library. Loading shimmers the rows; empty names the cause.
- **Errors (D):** offline (retry), 401 auth (edit sign-in), 404 not-found (edit URL) — three visually distinct outcomes, never a generic failure.

---

## #1798 · AI provider + bilingual + chat

**Decision: one credential drives all three features, so the spine is the four states the issue names — unconfigured → configured → in-flight → error. The provider editor is the already-committed `EditorSheet`; this batch adds the list, the interlinear reader, and the chat/summary panel.** Component: `vreader-ai-android.jsx`.

- **Provider (A):** the provider **list** is the gate. Unconfigured onboards to a single Add action; configured shows the active provider + per-provider status (model, or the rejection reason). Add / edit / test reuse the committed `EditorSheet` (`vreader-ai-provider-fields.jsx`) verbatim — in-flight and error are its existing `test="testing"` / `test="fail"` states.
- **Bilingual (B):** interlinear — the original line keeps full weight, the translation sits beneath behind an accent keyline so the eye can drop to it or skip it. A docked toggle carries the mode + language/provider/style summary. In-flight translates progressively (later paragraphs dimmed); **error keeps the original** and names the HTTP cause (429). A setup sheet sets languages · provider · model · style (Literal / Natural / Literary) + a cost estimate.
- **Chat & summary (C):** a panel docked over a dimmed reader. **Unconfigured** routes to AI settings (the same gate); idle offers suggested prompts; in-flight shows a typing indicator; the **answer streams in the reading serif** (the AI's prose shares the book's voice, not a chat-app sans); the chapter **summary** renders cached key-points with an explicit regenerate. Summaries are cached per chapter so re-opening is instant and free.

---

## Cross-references

| File | Role |
|---|---|
| `vreader-tts.jsx` | TTS bar, voice/speed sheets, reader entry **+ shared reader frame chrome** (`TtsFrame` / `StatusStrip` / `ReaderChrome` / `ReaderProse`) — #1797 |
| `vreader-android-annotations.jsx` | `SelectionReader`, `SelectionPopover`, `AnnotationsSheet`, the three card kinds — #1801 |
| `vreader-library-android.jsx` | `LibraryScreen`, `SearchScreen`, `CollectionsManageSheet`, `AssignSheet`, `Cover` — #1802 |
| `vreader-stats-android.jsx` | `InReaderTime`, `StatsDashboard`, `TimeWindowBar`, `DailyChart`, `PerBookTable` — #1800 |
| `vreader-opds.jsx` | `OpdsSourceList`, `OpdsAddSheet`, `OpdsBrowse`, `OpdsError`, `AcquisitionEntry` — #1799 |
| `vreader-ai-android.jsx` | `AiProviderList`, `BilingualReader`, `BilingualSetupSheet`, `AiChatPanel` — #1798 |
