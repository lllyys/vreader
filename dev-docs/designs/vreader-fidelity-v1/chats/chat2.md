# GitHub Issue Fixes

_Started 2026-05-16 13:05 UTC_

---

## User

https://github.com/lllyys/vreader/issues/789 https://github.com/lllyys/vreader/issues/790 https://github.com/lllyys/vreader/issues/793

## Assistant

_[tool: list_files]_

_[tool: github_read_file]_

_[tool: list_files]_

_[tool: read_file]_

_[tool: web_fetch]_

_[tool: web_fetch]_

_[tool: web_fetch]_

_[tool: read_file]_

_[tool: read_file]_

_[tool: read_file]_

_[tool: read_file]_

_[tool: read_file]_

_[tool: read_file]_

_[tool: read_file]_

_[tool: grep]_

_[tool: grep]_

_[tool: web_search]_

_[tool: snip]_

_[tool: web_search]_

_[tool: questions_v2]_

I have full context for issues #789 (Book Details sheet) and #793 (unified annotations sheet decision), and I've explored the existing prototype, design notes, and component layer. I couldn't fetch issue #790 (the GitHub page errored on retrieval). A few quick questions before I open up the canvas:

## User

Questions answered:
- issue_790_body: Surface needed
The Bilingual mode row in the reader's More-menu popover (feature #60 WI-6c).

dev-docs/designs/vreader-fidelity-v1/project/vreader-more.jsx depicts Bilingual mode as the 3rd row of the popover with an inline toggle switch — design-notes/reader-search-and-more-menu.md §2 specifies:

Bilingual mode · "Translate inline" → "English ↔ Chinese" when on · Toggle switch (inline)

— i.e. an on/off control with an active state and an active sub-detail.

Why WI-6c could not ship this row
WI-6c ships the More-menu popover. Five of the six designed rows have real backing surfaces (Read aloud → TTS, Auto-turn → ReaderSettingsStore.autoPageTurn, Book details → settings interim, Share → ShareSheet, Export → annotations panel). Bilingual mode does not. There is no persistent "bilingual mode" on/off state in the app — bilingual translation lives entirely inside the AI assistant's translate tab (AITranslationViewModel + BilingualView), invoked per selection.

Rendering the row as a toggle with no backing state would be a fake control; routing it as a tap row to the AI panel diverges from the design's depicted toggle. Both are rule-51 violations (self-designed UI). Per rule 51, WI-6c omits this one row and files this issue; the other 5 designed rows ship.

What this issue must resolve
Two things, before the Bilingual row can be (re-)added to the popover:

Backing feature — a persistent "bilingual mode" the reader can turn on so content renders inline-bilingual (English ↔ target language) without per-selection AI calls. This is a new capability (likely its own feature row in docs/features.md), not just UI.
Design confirmation — confirm the Bilingual row's final placement, control (toggle vs tap), states (off / on / unavailable when AI not configured), and sub-detail text in a committed design bundle, so the popover row can be implemented faithfully.
Parent
Refs #718 (feature #60 — visual identity v2). WI-6c ships the popover with 5 rows; this row is deferred.

States the design must cover
Off (default)
On (active tint + "English ↔ " sub-detail)
AI not configured (the bilingual feature depends on an AI provider) — disabled / hidden?
Source of truth
docs/features.md feature #60 row + dev-docs/plans/20260515-feature-60-visual-identity-v2.md.
- presentation: Both — canvas for review, prototype for interaction
- variation_breadth: Decide for me
- book_details_layout: Decide for me
- book_details_cover_swap: Decide for me
- annotations_decision: Split — design the two separate TOCSheet + HighlightsSheet as the canonical surfaces
- states_per_surface: Yes — render every state in #789, plus filled + empty for #793
- tweaks: Theme switcher (paper/sepia/dark/OLED/photo), File-state simulator (local / remote-only / missing cover / long title), Annotations active tab (Contents / Bookmarks / Highlights / Notes), Layout variant for each surface, Book selected from the library data
- theme_for_canvas: Paper + Sepia + Dark + OLED + Photo (full matrix per surface)

## Assistant

_[tool: update_todos]_

Got it. Locking in:
- **#789 Book Details:** Big-cover-top canonical + cover-left compact alternate; pencil overlay for cover swap; all 4 states rendered.
- **#790 Bilingual:** Design the backing feature (paragraph-interlinear reader mode + setup sheet) AND the popover row in 3 states (off / on / AI-not-configured).
- **#793 Annotations:** Split into canonical `TOCSheet` and `HighlightsSheet` — both with filled + empty states.

Output: canvas with full theme matrix for review, **and** wire everything live into the existing prototype with Tweaks. Let me lay out the plan and start writing.

_[tool: read_file]_

Let me peek at the cover component before I extend it for the missing-cover state.

_[tool: write_file]_

_[tool: copy_starter_component]_

_[tool: copy_starter_component]_

Now I'll build the design notes and new components.

_[tool: write_file]_

_[tool: write_file]_

_[tool: write_file]_

_[tool: str_replace_edit]_

_[tool: write_file]_

_[tool: write_file]_

Now I'll build the canvas with all artboards.

_[tool: grep]_

_[tool: read_file]_

_[tool: grep]_

_[tool: str_replace_edit]_

_[tool: read_file]_

_[tool: show_html]_

_[tool: show_html]_

_[tool: get_webview_logs]_

_[tool: save_screenshot]_

_[tool: str_replace_edit]_

Now I'll wire everything into the live prototype with Tweaks. Editing the app shell and reader, then updating the HTML.

_[tool: str_replace_edit]_

_[tool: str_replace_edit]_

_[tool: write_file]_

_[tool: grep]_

_[tool: write_file]_

_[tool: str_replace_edit]_

_[tool: show_html]_

_[tool: get_webview_logs]_

_[tool: show_html]_

_[tool: get_webview_logs]_

_[tool: update_todos]_

_[tool: done]_

_[tool: snip]_

_[tool: fork_verifier_agent]_

Designs landed for all three follow-ups. Two files:

- **`VReader Followups Canvas.html`** — review canvas, ~30 artboards organized in 10 sections: Book Details across themes + states + alternate layout, Bilingual reader across 5 themes/languages + setup sheet + 4 popover-row states, TOCSheet + HighlightsSheet split with filled/empty across all themes.
- **`VReader Prototype.html`** — live prototype with the new surfaces wired in; Tweaks panel (toolbar toggle) exposes theme override, book selection, file-state simulator, layout variant, bilingual language, and AI-unavailable simulation.

Committed decisions live in `design-notes/feature-60-followups.md`:
- **#789** — cover-on-top stacked sheet is canon; cover-left compact is alternate-only; pencil overlay for cover swap.
- **#790** — paragraph-interlinear reader mode + setup sheet are the backing feature; popover row ships in 3 states (off / on / unavailable-with-fix-path) rather than hiding when AI unconfigured.
- **#793** — **split**: `TOCSheet` (navigation, book-titled) and `HighlightsSheet` (review, "Annotations"-titled), each with proper empty states.

Open the Tweaks panel from the toolbar to flip through everything live.

