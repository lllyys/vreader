# GitHub Issue Fixes

*Started 2026-05-16 13:05 UTC*

---

## User

[https\://github.com/lllyys/vreader/issues/789](https://github.com/lllyys/vreader/issues/789) [https\://github.com/lllyys/vreader/issues/790](https://github.com/lllyys/vreader/issues/790) [https\://github.com/lllyys/vreader/issues/793](https://github.com/lllyys/vreader/issues/793)

## Assistant

*[tool: list_files]*

*[tool: github_read_file]*

*[tool: list_files]*

*[tool: read_file]*

*[tool: web_fetch]*

*[tool: web_fetch]*

*[tool: web_fetch]*

*[tool: read_file]*

*[tool: read_file]*

*[tool: read_file]*

*[tool: read_file]*

*[tool: read_file]*

*[tool: read_file]*

*[tool: read_file]*

*[tool: grep]*

*[tool: grep]*

*[tool: web_search]*

*[tool: snip]*

*[tool: web_search]*

*[tool: questions_v2]*

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

*[tool: update_todos]*

Got it. Locking in:

- **#789 Book Details:** Big-cover-top canonical + cover-left compact alternate; pencil overlay for cover swap; all 4 states rendered.
- **#790 Bilingual:** Design the backing feature (paragraph-interlinear reader mode + setup sheet) AND the popover row in 3 states (off / on / AI-not-configured).
- **#793 Annotations:** Split into canonical `TOCSheet` and `HighlightsSheet` — both with filled + empty states.

Output: canvas with full theme matrix for review, **and** wire everything live into the existing prototype with Tweaks. Let me lay out the plan and start writing.

*[tool: read_file]*

Let me peek at the cover component before I extend it for the missing-cover state.

*[tool: write_file]*

*[tool: copy_starter_component]*

*[tool: copy_starter_component]*

Now I'll build the design notes and new components.

*[tool: write_file]*

*[tool: write_file]*

*[tool: write_file]*

*[tool: str_replace_edit]*

*[tool: write_file]*

*[tool: write_file]*

Now I'll build the canvas with all artboards.

*[tool: grep]*

*[tool: read_file]*

*[tool: grep]*

*[tool: str_replace_edit]*

*[tool: read_file]*

*[tool: show_html]*

*[tool: show_html]*

*[tool: get_webview_logs]*

*[tool: save_screenshot]*

*[tool: str_replace_edit]*

Now I'll wire everything into the live prototype with Tweaks. Editing the app shell and reader, then updating the HTML.

*[tool: str_replace_edit]*

*[tool: str_replace_edit]*

*[tool: write_file]*

*[tool: grep]*

*[tool: write_file]*

*[tool: str_replace_edit]*

*[tool: show_html]*

*[tool: get_webview_logs]*

*[tool: show_html]*

*[tool: get_webview_logs]*

*[tool: update_todos]*

*[tool: done]*

*[tool: snip]*

*[tool: fork_verifier_agent]*

Designs landed for all three follow-ups. Two files:

- **`VReader Followups Canvas.html`** — review canvas, \~30 artboards organized in 10 sections: Book Details across themes + states + alternate layout, Bilingual reader across 5 themes/languages + setup sheet + 4 popover-row states, TOCSheet + HighlightsSheet split with filled/empty across all themes.
- **`VReader Prototype.html`** — live prototype with the new surfaces wired in; Tweaks panel (toolbar toggle) exposes theme override, book selection, file-state simulator, layout variant, bilingual language, and AI-unavailable simulation.

Committed decisions live in `design-notes/feature-60-followups.md`:

- **#789** — cover-on-top stacked sheet is canon; cover-left compact is alternate-only; pencil overlay for cover swap.
- **#790** — paragraph-interlinear reader mode + setup sheet are the backing feature; popover row ships in 3 states (off / on / unavailable-with-fix-path) rather than hiding when AI unconfigured.
- **#793** — **split**: `TOCSheet` (navigation, book-titled) and `HighlightsSheet` (review, "Annotations"-titled), each with proper empty states.

Open the Tweaks panel from the toolbar to flip through everything live.

## User

[https\://github.com/lllyys/vreader/issues/842](https://github.com/lllyys/vreader/issues/842) [https\://github.com/lllyys/vreader/issues/812](https://github.com/lllyys/vreader/issues/812)

## Assistant

*[tool: github_read_file]*

*[tool: web_fetch]*

*[tool: web_fetch]*

*[tool: questions_v2]*

Read both. Two more "needs-design" issues against the same vreader fidelity bundle:

- **#842 MD reader paged-mode** — need to decide (a) how paged content + "Page X of Y" indicator inset against `ReaderBottomChrome`, and (b) the tap-zone overlay (left/center/right → prev/toggle/next). States: chrome visible/hidden, auto-page-turn.
- **#812 EPUB chapter navigation** — pick the interaction model: side-tap nav, continuous cross-chapter scroll, or defined hybrid. Plus states for chapter start/end, first/last chapter, mid-render loading.

The existing prototype already has reader tap zones (30/40/30 split), so #812 has a partial answer baked into our committed design. Quick questions before I lay out the canvas and wire into the prototype:

## User

Questions timed out; go with defaults

## Assistant

*[tool: update_todos]*

*[tool: read_file]*

Going with sensible defaults across the board: canvas + prototype wiring, hybrid model for #812 (side-tap paged · continuous scroll), one-time first-open hint, content insets above chrome with the chrome's own page counter as canonical, chapter heading + thin divider in scroll mode, sweeping ribbon for auto-page-turn. Let me lay it out.

*[tool: write_file]*

*[tool: write_file]*

*[tool: write_file]*

*[tool: write_file]*

*[tool: read_file]*

*[tool: str_replace_edit]*

*[tool: str_replace_edit]*

*[tool: str_replace_edit]*

*[tool: str_replace_edit]*

*[tool: str_replace_edit]*

*[tool: write_file]*

*[tool: write_file]*

*[tool: show_html]*

*[tool: get_webview_logs]*

*[tool: show_html]*

*[tool: sleep]*

*[tool: get_webview_logs]*

*[tool: show_html]*

*[tool: sleep]*

*[tool: get_webview_logs]*

*[tool: save_screenshot]*

*[tool: update_todos]*

*[tool: done]*

*[tool: fork_verifier_agent]*

Designs for both new issues shipped.

**`design-notes/reader-navigation.md`** — committed decisions:

- **#812 EPUB chapter nav: hybrid.** Side-tap zones extend across chapter boundaries in paged mode (last-page Next → Ch+1; first-page Prev → Ch-1; end-of-book bounces). Continuous scroll in scroll mode with hairline divider + uppercase chapter heading.
- **#842 MD chrome inset:** content insets above chrome (no overlap); page indicator de-duplicated — chrome's scrubber shows it when visible, content-bottom shows it when hidden.
- **#842 Auto-page-turn:** 1.5px accent ribbon sweeping along the bottom edge over the interval.
- **Tap-zone discoverability:** subtle one-time first-open hint (left/right chevron + caption columns, fades after 2.5s, localStorage-gated).

**`VReader Navigation Canvas.html`** — 6 sections / \~20 artboards: paged hybrid (mid-chapter, at boundary with advance hint, end-of-book bounce), continuous scroll (default, boundary visible, mid-render skeleton), MD chrome inset before/after, ribbon at 0% / 50% / 95%, tap-zone hint across paper/dark/photo + designer debug overlay, and the cross-theme matrix.

**`VReader Prototype.html`** — live: Tweaks panel now has a "Reader navigation" section with Paged/Scroll mode toggle, Debug tap zones, and Replay first-open hint. Auto-turn lives in the More menu (⋯) as before; flip it and the ribbon sweeps. Switch to Scroll mode and Ch1+Ch2 stream with the divider between them.

## User

there should be a button to switch paged and scroll. and the Scrolling page turns can seamlessly connect two chapters.

## Assistant

*[tool: str_replace_edit]*

*[tool: str_replace_edit]*

*[tool: str_replace_edit]*

*[tool: str_replace_edit]*

*[tool: str_replace_edit]*

Good calls — I'll move the mode toggle into the Display (Aa) sheet as a first-class button, and tighten the scroll mode so chapters flow together more visibly.

*[tool: show_html]*

*[tool: sleep]*

*[tool: get_webview_logs]*

*[tool: save_screenshot]*

*[tool: view_image]*

*[tool: save_screenshot]*

*[tool: view_image]*

Both changes landed:

- **Layout switcher** is now a first-class control in the Display (Aa) sheet — segmented Paged | Scroll with little pictogram glyphs, sitting alongside Theme / Font / Size / Line spacing / Margin. Mode is owned by `readerSettings.mode`; the Tweaks panel keeps a "Display / Paged / Scroll" override knob for review.
- **Scroll-mode chapter flow** is already seamless — Ch1 streams into a hairline divider + uppercase "Chapter 2" heading, then Ch2 continues. Try it: open the prototype → tap a book → Display → Scroll, then scroll down to see the transition.

