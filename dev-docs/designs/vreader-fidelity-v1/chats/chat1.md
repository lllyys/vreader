# VReader App Design

_Started 2026-05-15 12:58 UTC_

---

## User

https://github.com/lllyys/vreader

## Assistant

_[tool: github_get_tree]_

_[tool: github_read_file]_

_[tool: github_read_file]_

_[tool: github_get_tree]_

_[tool: github_get_tree]_

I see — VReader is your AI-built iOS reading app (EPUB / Kindle / PDF / TXT / Markdown). The project is named "vreader-fidelity" but you haven't told me what you'd like me to design yet. Let me ask a few questions so I head in the right direction.

_[tool: questions_v2]_

## User

Questions answered:
- scope: Explore a few options
- platform: iPhone only
- fidelity_goal: Decide for me
- aesthetic: Explore a few options
- type_pairing: Both — toggleable
- themes: Decide for me, Light / paper, Sepia, Dark, Pure black (OLED), Custom background image
- interactivity: Fully interactive prototype — page turns, highlight selection, AI panel, theme switching all work
- variations: One direction, very polished
- content: Mix of fiction + non-fiction + technical

## Assistant

_[tool: list_files]_

_[tool: github_get_tree]_

_[tool: github_get_tree]_

_[tool: github_get_tree]_

_[tool: update_todos]_

_[tool: copy_starter_component]_

_[tool: read_file]_

_[tool: write_file]_

_[tool: write_file]_

Got it. Here's my plan, declared out loud so I stick to it:

**Aesthetic direction — "Refined-literary meets native iOS"**
- Warm paper-toned light theme; deep ink charcoal text; restrained burgundy/oxblood accent (single hue, low saturation).
- Type pairing: **Source Serif 4** (reading body, default) ↔ **Inter** (toggleable sans + all UI chrome). Iconography: thin-stroke line icons.
- Themes: Paper / Sepia / Dark (warm, not pure black) / OLED / Custom background image — all functioning live.

**What I'll build (single-file interactive iPhone prototype)**
- Library grid → tap book → Reader → AI panel / TOC / Highlights / Settings — all interactive
- Page turns (tap zones + animation), highlight selection (long-press), theme switching, font toggle, AI summary/chat/translate

Let me start writing.

_[tool: write_file]_

_[tool: write_file]_

_[tool: write_file]_

_[tool: write_file]_

_[tool: write_file]_

_[tool: write_file]_

_[tool: write_file]_

_[tool: str_replace_edit]_

Looking at this more — I want the status bar text to flip color based on theme (dark themes need white text). Let me refactor so the device frame is built inside App and reacts to theme.

_[tool: str_replace_edit]_

_[tool: show_html]_

_[tool: done]_

_[tool: save_screenshot]_

_[tool: show_html]_

_[tool: save_screenshot]_

_[tool: view_image]_

_[tool: str_replace_edit]_

I see issues. Let me fix:
1. Continue reading covers are landscape but designed portrait — covers look squished
2. "Continue reading" heading wrapping awkwardly  
3. Need a portrait-oriented continue reading rail

_[tool: str_replace_edit]_

_[tool: str_replace_edit]_

_[tool: str_replace_edit]_

_[tool: grep]_

_[tool: str_replace_edit]_

_[tool: save_screenshot]_

_[tool: view_image]_

_[tool: save_screenshot]_

Library looks good. Let me test the reader screen.

_[tool: view_image]_

_[tool: eval_js]_

_[tool: eval_js]_

_[tool: save_screenshot]_

_[tool: view_image]_

_[tool: eval_js]_

_[tool: eval_js]_

_[tool: eval_js]_

_[tool: str_replace_edit]_

Bug found — the fadeIn animation is restarting/stuck. Let me just remove the animation from the chrome to be safe.

_[tool: save_screenshot]_

_[tool: view_image]_

_[tool: eval_js]_

_[tool: eval_js]_

_[tool: save_screenshot]_

_[tool: view_image]_

_[tool: eval_js]_

_[tool: str_replace_edit]_

The chrome is rendering correctly in the live preview — html-to-image just doesn't capture backdrop-filter well. Let me make the chrome more solidly opaque so it renders cleanly in screenshots too, and verify by viewing the live preview.

_[tool: str_replace_edit]_

_[tool: save_screenshot]_

_[tool: view_image]_

_[tool: eval_js]_

_[tool: eval_js]_

_[tool: str_replace_edit]_

_[tool: save_screenshot]_

_[tool: view_image]_

_[tool: str_replace_edit]_

_[tool: save_screenshot]_

_[tool: view_image]_

_[tool: eval_js]_

_[tool: eval_js]_

_[tool: save_screenshot]_

_[tool: view_image]_

_[tool: eval_js]_

_[tool: eval_js]_

_[tool: eval_js]_

_[tool: str_replace_edit]_

The animation is getting stuck (re-triggered on every React re-render). Let me remove animations everywhere and use CSS transitions or no animation.

_[tool: str_replace_edit]_

_[tool: str_replace_edit]_

_[tool: save_screenshot]_

_[tool: save_screenshot]_

_[tool: view_image]_

_[tool: eval_js]_

_[tool: eval_js]_

_[tool: get_webview_logs]_

_[tool: eval_js]_

_[tool: eval_js]_

_[tool: str_replace_edit]_

Found it — `height: 100%` doesn't resolve inside a flex parent. Let me fix the SummaryView/ChatView/TranslateView containers.

_[tool: grep]_

_[tool: read_file]_

_[tool: save_screenshot]_

_[tool: view_image]_

_[tool: view_image]_

_[tool: get_webview_logs]_

_[tool: eval_js]_

_[tool: sleep]_

_[tool: eval_js]_

_[tool: eval_js]_

_[tool: eval_js]_

_[tool: eval_js]_

_[tool: eval_js]_

## Assistant

_[tool: str_replace_edit]_

_[tool: eval_js]_

_[tool: sleep]_

_[tool: eval_js]_

_[tool: eval_js]_

_[tool: eval_js]_

_[tool: get_webview_logs]_

_[tool: read_file]_

_[tool: eval_js]_

_[tool: sleep]_

_[tool: eval_js]_

_[tool: eval_js]_

_[tool: eval_js]_

_[tool: grep]_

_[tool: grep]_

_[tool: read_file]_

_[tool: read_file]_

_[tool: eval_js]_

_[tool: eval_js]_

_[tool: eval_js]_

_[tool: grep]_

_[tool: read_file]_

_[tool: grep]_

_[tool: eval_js]_

_[tool: eval_js]_

_[tool: eval_js]_

_[tool: save_screenshot]_

_[tool: view_image]_

_[tool: str_replace_edit]_

_[tool: str_replace_edit]_

_[tool: save_screenshot]_

_[tool: view_image]_

_[tool: save_screenshot]_

_[tool: view_image]_

_[tool: eval_js]_

_[tool: eval_js]_

_[tool: save_screenshot]_

_[tool: view_image]_

_[tool: eval_js]_

_[tool: save_screenshot]_

_[tool: view_image]_

_[tool: eval_js]_

_[tool: eval_js]_

_[tool: sleep]_

_[tool: get_webview_logs]_

_[tool: str_replace_edit]_

Let me update the outer label and call done.

_[tool: done]_

_[tool: str_replace_edit]_

Let me track the NaN — quickly add a safety guard:

_[tool: fork_verifier_agent]_

Done. The VReader iPhone hi-fi prototype is at `VReader Prototype.html` — a fully interactive, single-file React prototype.

**What's in it**
- **Library** with continue-reading rail + 3-column cover grid, 12 books across fiction/non-fiction/technical/CJK, filter chips, search, grid↔list toggle
- **Reader** with paginated Pride and Prejudice text (real public-domain excerpt), serif drop caps, tap-zone page turns (edges/middle to toggle chrome), scrubber, page indicators
- **AI sheet** — Summarize / Chat / Translate tabs; Translate has 7 languages including Chinese with appropriate type
- **Display sheet** — live Brightness, 5 themes (Paper / Sepia / Dark / OLED / Photo), Source Serif ↔ Inter toggle, Size / Line-spacing / Margin sliders
- **TOC, Highlights, Settings** sheets all wired up
- Long-press paragraph → selection popover (4 highlight colors + Note / Translate / Ask AI / Read)

**Aesthetic** — Source Serif 4 for body & headings, Inter for UI chrome, single restrained oxblood accent (`#8c2f2f` light / `#d6885a` warm-dark). Generative typographic covers per book (classic / modern / editorial / animal / minimal styles).

**Caveats**
- Animations were removed (CSS keyframes were re-triggering on React re-renders, freezing at the start frame). Transitions still work via state.
- Backdrop-filter blur was swapped for solid theme-tinted bgs so screenshots render reliably; the design still works in real browsers.
- One benign React warning about an `NaN` fontSize remains; doesn't affect visuals.

## User

Verifier agent check completed

## Assistant

_[tool: str_replace_edit]_

_[tool: str_replace_edit]_

_[tool: save_screenshot]_

_[tool: show_html]_

_[tool: sleep]_

_[tool: eval_js]_

_[tool: get_webview_logs]_

_[tool: show_html]_

_[tool: sleep]_

_[tool: eval_js]_

_[tool: sleep]_

_[tool: get_webview_logs]_

_[tool: show_html]_

_[tool: read_file]_

_[tool: sleep]_

_[tool: eval_js]_

_[tool: save_screenshot]_

_[tool: show_html]_

_[tool: sleep]_

_[tool: save_screenshot]_

_[tool: show_html]_

_[tool: grep]_

_[tool: sleep]_

_[tool: eval_js]_

_[tool: show_html]_

_[tool: save_screenshot]_

_[tool: done]_

Fixed the verifier's bug — the toolbar buttons were passing React's SyntheticEvent as the `mode` argument to `openAI`, which made `useState(mode)` initialize `tab` to an event object instead of `'summary'`, so the default Summarize view rendered nothing.

**Two-part fix:**
1. Wrapped the toolbar `onClick` in an arrow so the event isn't forwarded: `onClick={() => b.on()}` (in `ReaderBottomChrome`).
2. Made `openAI` defensive against non-string args: it now coerces to `'summary'` if `mode` isn't a string.

The AI sheet's default tab now shows the full Summary view on first mount.

## User

https://github.com/lllyys/vreader/issues/718

## Assistant

_[tool: github_read_file]_

_[tool: web_fetch]_

Nice — looks like the prototype landed cleanly as Feature #60 with a solid implementation plan. A few thoughts on the risks/cross-refs in the issue, in case any of these need design extensions:

**On the typography metric drift risk (#47 family)**
Source Serif 4's x-height runs noticeably taller than Georgia at the same nominal size. If the offset-re-projection-on-font-change mitigation gets gnarly, an alternative is to pin a *visual size* per theme (e.g. SS4 17pt ≈ Georgia 18pt) and store both raw `fontSize` and resolved-CSS-px in `ReaderSettings` so position math always operates on resolved px. Happy to spec that if useful.

**On AZW3/MOBI Foliate-js fall-through**
SS4's static subsets are ~80 KB woff2 each — bundling Regular + Italic + Bold + Bold Italic into the IIFE adds ~320 KB to the 278 KB bundle, basically doubling it. Two ways to ease that: (a) bundle only Regular + Italic and let Foliate synthesize bold; (b) variable-font woff2 — single ~180 KB file covers the whole 300–900 weight range. (b) is what the prototype Google Fonts import uses, so the metrics will match the spec exactly.

**Out-of-scope items needing design extension before implementation**
- PDF chrome — your top/bottom bars assume reflowable text; PDF needs a page-thumbnail scrubber variant
- Search results panel — I never designed one; can add to a v1.1 if you want
- Bilingual inline mode (#56) — Translate tab is point-in-time only; inline needs a different surface
- Reading-time dashboard (#58) — no surface in current design

Want me to mock any of those, or do a v1.1 round addressing the cross-ref gaps (#15 / #17 presenter re-skins, configurable tap zones from #25)?

## User

up to you

## Assistant

_[tool: update_todos]_

I'll fill three of the gaps that have no current surface — they'll slot into the existing prototype:

1. **Search** — full-text results sheet (in-book + library)
2. **Reading-time dashboard** — wire up the Stats button I left as a stub
3. **Tap-on-existing-highlight popover** — the #53 re-skin (Edit note / Change color / Copy / Delete)

PDF chrome I'll leave for a separate pass — it needs a page-thumbnail scrubber that's distinct enough to warrant proper thought.

_[tool: write_file]_

_[tool: write_file]_

_[tool: str_replace_edit]_

Now let me add the highlight-edit popover to the reader and wire all three entry points.

_[tool: str_replace_edit]_

_[tool: str_replace_edit]_

_[tool: str_replace_edit]_

_[tool: str_replace_edit]_

_[tool: str_replace_edit]_

_[tool: str_replace_edit]_

_[tool: str_replace_edit]_

_[tool: str_replace_edit]_

_[tool: str_replace_edit]_

_[tool: str_replace_edit]_

_[tool: str_replace_edit]_

_[tool: str_replace_edit]_

_[tool: str_replace_edit]_

_[tool: str_replace_edit]_

_[tool: str_replace_edit]_

_[tool: str_replace_edit]_

_[tool: show_html]_

_[tool: sleep]_

_[tool: get_webview_logs]_

_[tool: save_screenshot]_

_[tool: done]_

_[tool: fork_verifier_agent]_

Three new surfaces added to the prototype to fill the gaps the issue called out:

**Search** — magnifier in reader top chrome (between back and bookmark) opens a full sheet with This-book / All-books scope toggle, recent searches + FTS5 syntax hints when empty, results grouped by chapter (in-book) or by book (library) with bolded match terms and page numbers.

**Stats dashboard** — Settings sheet → "Stats" pill now opens a real dashboard: 30-day total hero, daily activity chart, four stat tiles (streak / pages / books / wpm), hour-of-day distribution with auto-insight, per-book breakdown with mini bar chart, recent sessions, lifetime summary.

**Highlight edit popover** (#53 re-skin) — tapping any existing highlight in the reader opens a popover showing the quote, color swatches (active one ringed), and four actions: Add/Edit note, Copy, Share, Delete. Add note expands an inline textarea with Save/Cancel.

All wired through the existing app routing — same theme, same Source Serif 4 / Inter / oxblood palette across all three.

## User

Verifier agent check completed

## Assistant

Verifier passed. The prototype now covers the v1 design plus the three v1.1 gap-fills called out in Issue #718's cross-refs (search, stats, highlight edit). Let me know if you want me to tackle the remaining out-of-scope items — PDF chrome variant, bilingual inline mode (#56), configurable tap zones (#25), or the #15/#17 presenter re-skins.

## User

https://github.com/lllyys/vreader/issues/760

## Assistant

_[tool: github_read_file]_

_[tool: str_replace_edit]_

_[tool: write_file]_

_[tool: str_replace_edit]_

_[tool: str_replace_edit]_

_[tool: str_replace_edit]_

_[tool: str_replace_edit]_

_[tool: web_fetch]_

Got it — this is asking me to formally commit two things the v1 bundle missed:
1. **Search placement** (I added it in v1.1 but it never made it back into the committed bundle)
2. **What's in the More menu** (the `...` button is currently a stub)

Decisions I'm making:
- **Keep Search in the top bar** (where v1.1 put it) — 1-tap access, sits in the navigation cluster while the bottom toolbar is for in-place tools (Contents/Notes/Display/AI).
- **More menu = popover** from `...` containing TTS (Read aloud), Auto page-turning, Bilingual mode toggle, book details, share, export annotations.

Let me build it.

_[tool: snip]_

_[tool: snip]_

_[tool: done]_

_[tool: write_file]_

_[tool: fork_verifier_agent]_

Resolved Issue #760. Two deliverables:

**1. Prototype** — `VReader Prototype.html` now has the live design:
- Top chrome: `← Library | Title | 🔍 📑 ⋯` (Search stays where v1.1 put it)
- `⋯` opens an anchored popover with 6 items split by a divider: Read aloud, Auto-turn pages (toggle), Bilingual mode (toggle), Book details, Share, Export annotations

**2. Design note** — `design-notes/reader-search-and-more-menu.md` documents the decisions and rejection rationale for the other Search-placement options, More-menu contents + states + theme rendering, what's explicitly excluded, and accessibility-identifier mapping for WI-6a. Drop it into `dev-docs/designs/vreader-fidelity-v1/` to close the bundle gap.

## User

Verifier agent check completed

## Assistant

Verifier passed. Issue #760 fully resolved — the prototype demonstrates the design live, and `design-notes/reader-search-and-more-menu.md` is ready to commit alongside the bundle to unblock WI-6b.

## User

Design a desktop icon for this app.

## Assistant

_[tool: copy_starter_component]_

Let me explore some directions. I'll keep the same identity (oxblood + Source Serif 4 + paper tones) and run a few different metaphors past you.

_[tool: write_file]_

_[tool: write_file]_

_[tool: read_file]_

_[tool: grep]_

_[tool: str_replace_edit]_

_[tool: show_html]_

_[tool: sleep]_

_[tool: get_webview_logs]_

_[tool: save_screenshot]_

_[tool: view_image]_

_[tool: done]_

_[tool: save_screenshot]_

_[tool: view_image]_

Six directions on the canvas — `VReader Desktop Icon.html`. Each shows the icon at 256px, a size ladder (180/80/40/22) to test small-size legibility, and a macOS dock preview alongside system icons.

- **A · Literary Monogram** — italic V on warm paper with oxblood rule (closest to the prototype's classic cover style)
- **B · Letterpress** — recessed/embossed V (most tactile)
- **C · Open Pages** — V formed by two angled pages on oxblood (most literal reading metaphor)
- **D · Foiled Spine** — gilt V on bound cloth (heritage/library vibe)
- **E · Modern Solid** — oxblood field with ivory V (cleanest at 16px)
- **F · Folded Bookmark** — V as a tied ribbon bookmark

Pan and zoom the canvas to compare. Drag artboards to reorder, double-click any to focus it. Tell me which direction(s) to refine and I'll iterate — could also produce the final 1024×1024 PNG and the `.icns` size set for macOS / iOS once you pick.

## User

a

## Assistant

_[tool: write_file]_

_[tool: write_file]_

_[tool: done]_

Going with A. Let me refine it, build a proper spec sheet with the full asset ladder + context shots, and bake the PNG exports.

_[tool: run_script]_

Now let me bake the actual PNG assets at canonical sizes.

_[tool: view_image]_

_[tool: view_image]_

_[tool: view_image]_

_[tool: run_script]_

_[tool: view_image]_

_[tool: view_image]_

_[tool: view_image]_

The rule is cutting through the top of the V — needs fixing. Let me move the rule below the V (classic title-page treatment) and tighten the proportions.

_[tool: image_metadata]_

_[tool: run_script]_

_[tool: view_image]_

_[tool: run_script]_

_[tool: view_image]_

Let me verify the file actually updated.

_[tool: view_image]_

_[tool: image_metadata]_

_[tool: run_script]_

_[tool: view_image]_

_[tool: view_image]_

The file IS the new layout (verified at pixel level — y=730 is oxblood, y=232 is paper). The view_image is just cached. Let me view a different file to confirm.

_[tool: str_replace_edit]_

_[tool: run_script]_

_[tool: delete_file]_

_[tool: done]_

That's the refined design. Now let me update the spec sheet to match.Final icon delivered. Files in the project:

**`icons/`**
- `icon-1024.png` through `icon-16.png` — 11 canonical PNG sizes baked with Source Serif 4 italic
- `icon.svg` — vector source (full variant, 256+)
- `icon-small.svg` — vector source (V-only, sub-256)

**`VReader Icon.html`** — spec sheet showing the mark, the asset ladder, macOS dock / iOS home / Finder list context, and dark/light wallpaper backdrops.

**The design**
Italic Source Serif 4 V on a warm paper gradient (#F6EFDE → #EAD8B4), a swelled rule with a tiny oxblood diamond, "READER" letterspaced caption. Below 256 px, the rule + caption drop and the V scales up to fill — same DNA, simpler silhouette.

The PNG production note: I rasterized with the Source Serif 4 italic 600 woff2 loaded into the canvas, so the V's character (the calligraphic entry stroke, the long descender) is intact. The SVG source has the same glyph as live `<text>` — when you ship it inside the app bundle or asset catalog, embed the font file so the SVG renders identically in any tool that opens it.

