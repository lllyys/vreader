# Feature #60 — follow-up surfaces

> Resolves [#789](https://github.com/lllyys/vreader/issues/789), [#790](https://github.com/lllyys/vreader/issues/790), [#793](https://github.com/lllyys/vreader/issues/793).
> To be filed under `dev-docs/designs/vreader-fidelity-v1/` alongside `reader-search-and-more-menu.md`.

Three loose ends from the WI-6c / WI-10 design landing. Each gets a committed decision below; component implementations live in `vreader-book-details.jsx`, `vreader-bilingual.jsx`, and the refined sheets in `vreader-annotations.jsx`.

---

## 1. Book Details sheet (#789)

**Decision: half-sheet, cover-on-top canonical layout.** Title and author live directly under the cover in serif; metadata is a single key/value list below. One alternate (cover-left/dense) ships as a Tweak for review but is not the canonical surface.

### Anatomy

```
─────── grabber ───────
[ ✕ ]   Book details   [ ⇪ Share ]
──────────────────────────────────
              ┌──────┐
              │      │   ← 116×174 cover, accent-tinted edit
              │      │     pencil overlay (bottom-right)
              │      │
              └──────┘
       Pride and Prejudice            ← serif italic, 22pt
       Jane Austen · 1813             ← inter, sub
       [Fiction] [Classics]           ← tag chips

       ── METADATA ────────────────
       Format         EPUB
       Size           432 KB
       Pages          432
       Fingerprint    epub:8a4f…2c1b      [⎘]
       Location       Documents/Books/…   [↗]

       ── ACTIONS ─────────────────
       Replace cover…
       Share book…
       Export annotations…
```

### Why cover-on-top

The reader's whole visual language is portrait-first and serif-led. Placing a real book object at the top of the sheet matches the way users already think about the book (the cover IS the book) and gives the typography room to breathe. The cover-left/right layout (Apple Files-style) is denser, but it visually demotes the cover to a thumbnail and crowds the metadata list against the screen edge on a 402px width.

### States — exhaustively

| State | Treatment |
|---|---|
| **Default** | All rows populated. Fingerprint truncated mid-string with `[⎘]` copy button. Location truncated with `[↗]` reveal button. |
| **Long title** | Title wraps to up to 3 lines (still serif italic, line-height 1.05). Author truncates with ellipsis. Sheet height grows; metadata list stays anchored below. |
| **Missing cover** | Cover slot renders as a placeholder card — same dimensions, accent-tinted dashed border, large `V` monogram + "Tap to add cover" caption. The "Replace cover" action row becomes "Add cover…" for symmetry. |
| **Remote-only** | Header gets a small `⬇ Remote` chip next to title block. Size shows `—`. Location row reads `Not downloaded` with a primary-tinted `Download` button replacing the `[↗]`. Fingerprint is still present (we have it from the catalog). |

### Cover-swap affordance

**Inline overlay pencil** in the bottom-right of the cover. It's the most direct mapping ("touch the thing you want to change") and matches how iOS's profile-photo editor works. The "Replace cover…" action row stays as a discoverable backup for users who don't notice the overlay (and for keyboard/VoiceOver paths).

---

## 2. Bilingual mode (#790)

This issue is really two issues. We resolve them together so the popover row can ship cleanly:

### 2.1 — Backing feature: interlinear bilingual reading

**Decision: paragraph-interlinear rendering.** When bilingual mode is on, every source paragraph is followed by its translation in a smaller, muted, italic style. No per-selection AI call — the reader pre-fetches translations a page ahead and caches by paragraph fingerprint.

```
   It is a truth universally acknowledged, that a single man
   in possession of a good fortune, must be in want of a wife.
       凡是有钱的单身汉，总想娶位太太，这已经成了一条举世公认的真理。

   However little known the feelings or views of such a man …
       不论这样的单身汉，刚搬进一个地方时性情如何…
```

- Translation block is `~0.88× source font-size`, line-height `1.5`, color `sub`, italic off (target script reads better upright).
- Indent slightly (1× font-size) so the eye can see the alternation rhythm.
- Chapter headings are NOT translated (proper noun, breaks the flow).
- Drop-cap stays on source paragraph only.
- Reader top-chrome shows a small `EN ↔ 中` pill next to the title when bilingual is active — this is the one persistent affordance that signals state outside the More menu.

**Rejected: side-by-side columns.** At 402px, two columns of 17pt serif type leave each column at ~145px of usable text — under ten characters per line. Unreadable.

**Rejected: per-tap inline overlay.** That's what the existing AI Translate tab already does. The whole point of bilingual mode is that the user doesn't have to ask, paragraph by paragraph.

### 2.2 — Setup sheet

First time the toggle flips on, a half-sheet appears:

- Target language (Chinese / Spanish / French / Japanese / German · 9 languages, matches Settings → Translation languages)
- Granularity: Paragraph / Sentence (default Paragraph)
- AI provider chip (read-only, links to Settings if not configured)

On subsequent toggles, no sheet — just flip. The setup sheet is reachable from the row's sub-detail (`Tap to change`).

### 2.3 — More-menu row states

The row stays in place (3rd row), but ships with three rendered states instead of two:

| State | Icon | Sub-detail | Control | Trigger |
|---|---|---|---|---|
| **Off** | Translate, ink | `Translate inline` | Toggle (off) | AI configured |
| **On** | Translate, accent-tinted bg | `English ↔ Chinese` (or current target) | Toggle (on, green) | AI configured + bilingual active |
| **Unavailable** | Translate, 40% opacity | `Configure AI provider first` + chevron | (no toggle) | AI provider missing |

The unavailable state is **not hidden**, because invisibility hurts discoverability — users wonder why a feature they've heard about isn't there. Showing it as disabled with a one-tap path to fix it is the iOS-standard pattern (Settings → Cellular when no SIM, etc.).

---

## 3. Annotations sheet split (#793)

**Decision: split.** The committed design bundle (`vreader-panels.jsx`) is now canon — two separate sheets, `TOCSheet` and `HighlightsSheet`. The unified 4-tab `AnnotationsPanelView` in the production app is an IA debt item to follow up.

### Why split

- **Contents and bookmarks are about *navigating*** the book. The user opens this sheet to **leave the current page**.
- **Highlights and notes are about *reviewing*** what they've collected from the book. The user opens this sheet to **revisit reading**.
- These are different jobs. Bundling them into one sheet means every visit to TOC bumps the user past three tabs they don't care about right now. Splitting also keeps each sheet's title bar honest: `TOCSheet` titles with the *book name* (you're navigating *this* book); `HighlightsSheet` titles with `Annotations` (a cross-book concept that will eventually grow a "All books" affordance).
- The 4-tab production sheet was a defensive choice from before highlights were a first-class thing in the app. With the WI-10 chrome re-skin landed, the surfaces have room to spread out.

### Reader bottom-chrome routing

| Button | Opens |
|---|---|
| Contents | `TOCSheet` (Contents tab default) |
| Notes | `HighlightsSheet` (All filter default) |

Same buttons, two destinations instead of one — production code change is a one-liner in `ReaderChromeBar.onContents` / `.onNotes`.

### TOCSheet states

- **Contents · filled** — chapter list, current chapter row gets accent tint + bold title.
- **Contents · empty** — only happens with EPUBs that ship no TOC. Render a friendly hint: "This book has no table of contents. Use the scrubber or Search to navigate." + a button to open Search.
- **Bookmarks · filled** — bookmark cards with chapter / page / date / 1-line preview.
- **Bookmarks · empty** — illustrated empty state, copy: "No bookmarks yet. Tap the bookmark icon in the top bar to save your place."

### HighlightsSheet states

- **All · filled** — the existing card list, oldest-newest reverse chronological.
- **All · empty** — copy: "Long-press any passage to highlight or add a note." + a small illustration of a highlighted line.
- **Highlights · empty** / **Notes · empty** / **Bookmarks · empty** — filter-specific copy ("No notes yet.", etc.) but the same illustration. Stops the sheet from feeling like a dead end when the user is just filtering.

---

## Cross-references

- Live wiring: `VReader Prototype.html` (Tweaks panel exposes all three).
- Canvas of every state across the 5 themes: `VReader Followups Canvas.html`.
- Touches: `vreader-more.jsx` (bilingual unavailable state), `vreader-reader.jsx` (`EN ↔ 中` pill, interlinear renderer), `vreader-panels.jsx` (refined TOC / Highlights empty states).
