# Five needs-design issues — design notes

> Resolves design gaps blocking [#55](https://github.com/lllyys/vreader/issues/55), [#56](https://github.com/lllyys/vreader/issues/56), [#62](https://github.com/lllyys/vreader/issues/62), [#67](https://github.com/lllyys/vreader/issues/67), [#58](https://github.com/lllyys/vreader/issues/58).
> Source of truth: `VReader Issues Canvas.html` (every state across themes).

Five committed decisions, one per `needs-design` issue. Each section here is the README for the corresponding `.jsx` file and the prose justification for the canvas artboards.

---

## #865 · Tap-on-annotated-text note-preview presenter (feature [#55](https://github.com/lllyys/vreader/issues/55))

**Decision: anchored note callout, with a bottom-sheet fallback for long notes / VoiceOver.** Component: `NoteCallout` (canonical), `NotePreviewSheet` (fallback). Component file: `vreader-note-preview.jsx`.

### Why a new surface (not `HighlightActionPopover`)

The existing tap-on-highlight popover (feature #53) is an *action menu* — color swatches, edit, share, delete, with the note rendered as a small annotation block under the quote. Reusing it for tap-on-annotated-text muddles two intents:

- **Tap-on-highlight** (no note attached, or a note as secondary metadata): *I want to do something to this.*
- **Tap-on-annotated-text** (a note IS attached): *I want to read what I wrote.*

The note-preview presenter makes the note the hero — large serif body, no action grid stealing focus — and the dismiss is a single tap anywhere outside. Destructive actions live elsewhere; a casual "what did I write?" tap can't accidentally mutate state.

### Anatomy

```
   ──────────────────────────────────────────────────
   ●  NOTE   · Apr 18                              ✕
       ┊  "Such amiable qualities must speak…"      ← color-rule + 1-line excerpt
       
       Bingley's charm is presented through         ← note body, serif 15pt, 1.55
       external impression — "speak for             ← textWrap: pretty
       themselves" — which the rest of the
       chapter then undermines. Compare with
       how Darcy is introduced.

       ────────────────────────────────────────
         Edit       Share      Open in panel       ← lightweight handoff row
   ──────────────────────────────────────────────────
              ◢  pointer notch (above OR below)
```

### States — exhaustively

| State | Treatment |
|---|---|
| **Reading** | Default. Color swatch + "Note" + date in the meta row, 1-line passage excerpt, note body, handoff row. |
| **Editing** | Inline textarea replaces the body, Cancel / Save in place of the handoff row. (Production path: most users hit "Edit" and bounce to the full highlight-action popover; we render an in-callout edit too so the presenter is self-sufficient.) |
| **Empty / no-note** | The case the issue spec calls out. Meta row reads "Highlight" (not "Note"), body reads *"No note attached. Add one…"* with a tap target. |
| **Long note** | Body block is `max-height: 180px` with internal scroll. The sheet fallback is the better path here — the chrome-on-content design lets the user keep paging. |

### Placement / pointer logic

The callout positions itself relative to the tapped passage's bounding rect:

- Below the passage if there's room (default).
- Above if the passage is in the bottom third of the page.
- Notch tracks the passage's horizontal center, clamped to the card's left/right margins so it never points to the edge.
- Card max-width 304 px; horizontal position clamped to a `margin: 18` gutter.

### Sheet fallback

A short half-sheet (height 420), title "Note", body in serif 17pt, only two CTAs at bottom (Done / Edit note). Triggered when:

- VoiceOver is active (the anchored callout's positioning is meaningless to a screen reader).
- The note exceeds ~6 lines of body text at the current font size.
- The passage spans more than 60% of the page width (no good notch placement).

---

## #864 · Per-chapter re-translate menu + provider-override picker (feature [#56](https://github.com/lllyys/vreader/issues/56))

**Decision: a new row in the More popover (canonical) + a TOC swipe action (secondary), opening a provider-override half-sheet.** Component file: `vreader-retranslate.jsx`.

### Why the More popover (not AA, not chapter-list-only)

The issue offers three options for the affordance location:

1. The reader **AA (Display) panel** — mixes a translation action into a panel about *typography*. Conceptually wrong.
2. A **long-press menu** on the current chapter — hides the action behind a discovery problem (users have to know to long-press text *outside* a paragraph).
3. A **chapter-list context menu** — discoverable but requires opening TOC, which is two taps away from the read view.

The More popover already houses the bilingual mode toggle (the action that produced the translation in the first place); re-translate belongs in the same neighbourhood. The row is conditional on `bilingualOn === true` — when bilingual is off there's nothing to re-translate, so the row is absent rather than disabled.

The TOC swipe action covers the cross-chapter case: re-translating chapters other than the current one. Same provider picker opens; the chapter shown in the picker header changes.

### Row states

| `state` | Sub-detail | Icon |
|---|---|---|
| `idle` | *"Translated by Claude · Sonnet 4.5"* | `Translate` glyph |
| `running` | *"Re-translating… 38%"* | inline spinner replaces icon |
| `complete` | *"Re-translated · 14m ago"* | `Translate` glyph (transient ~6s, then collapses to `idle`) |
| `error` | *"Last attempt failed — tap to retry"* | `Translate` glyph, both label and chevron in `#c44` |

### Provider-override picker

A half-sheet. Pre-populates the provider + model + style that the bilingual mode setup sheet set as the book default. Changes inside the picker are scoped to this re-translation — they do NOT modify the default.

- **Context strip** — chapter title + token estimate up top.
- **Provider list** — Claude, OpenAI, Gemini, DeepL, Local. Each carries a one-line strength tag (*"Best for nuance"*, *"Cheapest"*, *"No AI tone — faithful"*, *"On-device, no cost"*).
- **Model picker** — pill row, hidden if the selected provider has only one model.
- **Style** — Literal / Natural / Literary, segmented control.
- **Glossary toggle** — *"Keep term overrides"* — reuses any per-book term overrides from the previous run. On by default.
- **CTA** — a single primary "Re-translate" pill on the right of the footer; the left of the footer carries the cost estimate (e.g. *"~\$0.012 · 2,380 tokens. Existing translation is kept until the new one is ready."*).

### Running / error sub-states

The picker swaps into a compact "Re-translating" sheet on submit — chapter strip, progress bar, ETA, and a Cancel button. Errors render inline above the provider list with a tinted error chip so the user can pick a different provider without losing form state.

---

## #863 · Translate-entire-book entry, confirmation, progress, cancel (feature [#56](https://github.com/lllyys/vreader/issues/56))

**Decision: a row in Book Details > Actions (canonical) and a library long-press menu item (secondary). Confirmation alert with cost. Progress in three places of increasing detail. Cancel surfaced with a "nothing is lost" alert.** Component file: `vreader-translate-book.jsx`.

### Entry point

We deliberately do **NOT** add this to the More popover.

- Whole-book translation is heavy, slow, and costs the user real money.
- It shouldn't sit next to lightweight reader actions like *"Read aloud"* and *"Auto-turn pages"*.
- Per-chapter re-translate (#864) belongs in More; whole-book belongs in Book Details, where the user is already thinking about the book as an object.

Long-press on a library card is the secondary path — matches the iOS contextMenu pattern and surfaces the action without crowding the card chrome.

### Confirmation alert

iOS-style alert with four parts:

1. **Title** — *"Translate the whole book?"*
2. **Body** — book title (serif italic) + chapter count + estimated tokens + estimated cost + estimated time, with the variable values bolded.
3. **Provider strip** — current provider with a "Change…" link. Tapping opens the provider picker (same component as #864's, scoped to this run).
4. **Two-button footer** — *"Not now"* / *"Translate"* (accent-tinted).

### In-progress — three places

1. **Library card badge** — clipped to the bottom of the cover. Glassy backdrop, spinner + `12 / 61` + a thin progress bar. Translated books (status `done`) get a small filled translate glyph in the top-right of the cover instead.
2. **Reader top banner** — when the book is open. Spinner + label + thin progress + a small × button that opens the cancel alert.
3. **Status sheet** — opens from either of the above. Hero progress row (large `12 / 61`, progress bar, throughput, provider chip) + a per-chapter list (`queued` / `running` / `done` / `failed`, with a tiny per-chapter progress bar on the running one) + a destructive `Cancel translation` CTA in the footer.

### Cancel — the part most apps get wrong

The cancel alert exists to *disabuse* the user of the assumption that they're throwing work away.

```
   Cancel translation?

   12 of 61 chapters are already translated and will
   stay cached — you can resume from where you stopped
   any time. We won't be charged for the rest.

   [ Keep translating ]      [ Cancel translation ]
                                 (in #c44)
```

The destructive button is in red, but the body copy explicitly says *what stays*. We named the action "Cancel translation" (not "Stop", not "Abort") because that's what the user said in their head when they tapped the ×; the alert just confirms it isn't catastrophic.

---

## #862 · Settings profile-header card identity + reading-stats dashboard (features [#67](https://github.com/lllyys/vreader/issues/67) / [#58](https://github.com/lllyys/vreader/issues/58))

**Decision: card represents the LIBRARY, not a person. Reading-stats dashboard gains a time-window bar and a sortable per-book table.** Component file: `vreader-profile-stats.jsx`.

### Identity model — three options, one canonical

The committed design shows *"lllyys"* + a gradient avatar with an initial. The production app has no user account and no user-name concept. We had to pick something else.

**A. Library-as-identity (CANONICAL).** The card represents the LIBRARY, not a person. Header reads *"Your library"* in serif italic; the avatar slot becomes a three-book-spine glyph. Stats below unchanged.

Why this wins:

- **Honest.** We don't have a user; generating an initial or a synthetic handle is uncanny.
- **Matches reality.** One library per device, no cross-device identity. The library IS the user-facing aggregation.
- **Lossless if we ever add accounts.** Avatar slot becomes the user-photo slot; *"Your library"* becomes a display name. Nothing about the layout has to change.

**B. User-set display name (alternate; falls back to A if empty).** Adds a single *"Your name"* field to Settings → About. If empty, the card renders as A. If set, the card shows the name + a coloured initial badge whose hue is derived from the name. iCloud profile photos are explicitly NOT used — they'd require a sign-in we don't otherwise need.

Why we might ship this: power users like the app to feel personal. Why we wouldn't: it's a whole new settings flow + migration for users with nothing set, and the value is purely cosmetic. Defer to a feature ask.

**C. Stats-as-hero (alternate).** Replace the identity card with a stats hero — *"41h this month"* in big serif + a 14-day sparkline + a Stats chevron at the right.

Why we might: makes Settings feel less iOS-generic. Why we wouldn't: pushes the actual settings list down, and a fresh-install user has 0h, which is a sad hero.

### Reading-stats dashboard additions

The committed `StatsSheet` (`vreader-stats.jsx`) is missing two things feature #58 explicitly calls for. We add them as drop-in components.

**`StatsTimeWindowBar`** — a chip row pinned under the sheet title: `Today · 7d · 30d · 90d · Year · All · Custom`. Active chip is the inverted `t.ink` pill (matches the existing filter-chip language from `HighlightsSheetV2`). All downstream content reflects the selection.

**`SortablePerBookTable`** — replaces the existing per-book block. Four columns:

| Book | Time | Hl | Nt |
|---|---:|---:|---:|
| *Pride and Prejudice* | 12h 18m | 47 | 18 |
| *The Beginning of Infinity* | 9h 47m | 22 | 11 |
| *Designing Data-Intensive Apps* | 7h 11m | 31 | 4 |

Tap any header to sort by that column; tap again to reverse. The Time column also drives a per-row progress bar so the relative magnitude reads even when the user has sorted by Hl or Nt.

---

## #860 · HighlightsSheet filter content with standalone notes (feature [#62](https://github.com/lllyys/vreader/issues/62))

**Decision: extend the design — option (2) from the issue. Render BOTH `HighlightRecord` and standalone `AnnotationRecord` cards. Notes filter merges both kinds.** Component file: `vreader-notes-unified.jsx`.

### Why option 2 and not 1 or 3

The committed `HighlightsSheetV2` models filters on `h.note`. Production has TWO record types:

- `HighlightRecord` — a highlighted passage, optionally annotated.
- `AnnotationRecord` — a standalone note at a locator (no quoted passage).

Shipping the committed design literally drops the standalone surface entirely — a regression.

- **Option 1 (fold into highlight-notes)** is a data-model change with a migration. Out of design scope; the model is already wired.
- **Option 3 (deprecate the feature)** deletes a working production surface (own `@Model`, `PersistenceActor+Annotations` CRUD, reader creation path, `AnnotationListView`, export / import / backup / CloudKit support) and breaks export shape.
- **Option 2 (extend the design)** is local — only this sheet changes.

### Changes vs `HighlightsSheetV2`

1. **Filter chip set** stays the same — `All · Highlights · Notes · Bookmarks` — but the **semantics change**:
   - `Highlights` → `HighlightRecord` rows (the passage; note optional).
   - `Notes` → BOTH `AnnotationRecord` rows AND `HighlightRecord` rows with a note. *Notes are notes, regardless of anchor.* This is the key choice — it means the user doesn't have to learn which "kind" of note they made.
   - `All` → union, chronological.
   - `Bookmarks` → unchanged.

2. **Two card components**:
   - `HighlightCardV3` — visually identical to v2.
   - `StandaloneNoteCard` — new. Note body is the hero (no quoted passage). Meta row carries the locator + a small "STANDALONE" pill so the user can scan the list and tell the kinds apart at a glance. The note body lives behind a *dashed* accent rule instead of v2's solid colour rule (no colour to show — no highlight backed it).

3. **"All" filter renders both card types in one chronological stream.** Card visuals are different enough that the stream reads cleanly without grouping headers.

4. **Empty states** unchanged from v2, with one copy tweak: the *"All"* empty state now mentions both ways to leave a note (long-press a passage, or tap the note icon on a chapter).

---

## Cross-references

| File | Role |
|---|---|
| `VReader Issues Canvas.html` | Canvas of every state across themes for all five issues. Source of truth. |
| `vreader-note-preview.jsx` | `NoteCallout`, `NotePreviewSheet` — #865 |
| `vreader-retranslate.jsx` | `ReTranslateMoreRow`, `ChapterSwipeAction`, `ReTranslatePickerSheet`, `ReTranslateProgress` — #864 |
| `vreader-translate-book.jsx` | `TranslateBookActionRow`, `TranslateBookConfirmAlert`, `LibraryCardTranslateBadge`, `ReaderTranslateBanner`, `TranslateStatusSheet`, `TranslateCancelAlert` — #863 |
| `vreader-profile-stats.jsx` | `ProfileCardLibrary`, `ProfileCardNamed`, `ProfileCardStatsHero`, `StatsTimeWindowBar`, `SortablePerBookTable`, `FullStatsDashboard` — #862 |
| `vreader-notes-unified.jsx` | `HighlightsSheetV3`, `HighlightCardV3`, `StandaloneNoteCard` — #860 |
