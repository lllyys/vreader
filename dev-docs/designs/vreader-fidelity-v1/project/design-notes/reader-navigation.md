# Reader navigation — MD paged-mode layout + EPUB chapter interaction

> Resolves [#842](https://github.com/lllyys/vreader/issues/842), [#812](https://github.com/lllyys/vreader/issues/812).
> Filed under `dev-docs/designs/vreader-fidelity-v1/` alongside `reader-search-and-more-menu.md` and `feature-60-followups.md`.

Two reader-fidelity issues that overlap on tap-zone geometry. Committed together so the gesture grammar is consistent across renderers.

---

## 1. Decisions at a glance

| | Decision |
|---|---|
| **EPUB chapter nav (#812)** | **Hybrid.** Side-tap in paged mode (extends our existing 30 / 40 / 30 zones, wraps across chapters at boundaries). Continuous cross-chapter scroll in scroll mode. |
| **MD chrome inset (#842 §1)** | Content insets **above** chrome — `bottom: chromeHeight + 8px` when chrome visible, `bottom: 56px` when chrome hidden. No overlap. |
| **Page indicator (#842 §1)** | The chrome already shows "Page X · N pages left" in its scrubber row. When chrome visible, **hide** the content-bottom indicator (de-duplicate). When chrome hidden, **show** the content-bottom indicator at the page edge. |
| **Tap-zone affordance** | Subtle one-time hint on first open of any paged reader — left + right zones flash a chevron + "Tap edges to turn" caption for ~2.5s, then fade. After the user taps once, the hint never returns. Persistent affordance rejected (visually noisy in a reading app). |
| **Chapter boundary (scroll mode)** | Small horizontal divider + uppercase chapter heading. No full-bleed transition page. |
| **Auto-page-turn indicator (#842 §states)** | Thin sweeping ribbon at the very bottom of the page (1px-tall accent-tinted bar filling left→right over the interval). Invisible when not on. |

---

## 2. #812 — EPUB chapter navigation (hybrid model)

### 2.1 — Why hybrid

Both Apple Books and Kindle ship a hybrid. The choice between paged and scroll modes is itself a real reader preference (typography-first vs. firehose-first), and each mode has its own grammar for *what should happen next*:

- **Paged mode** wants discrete page units. The grammar is *tap = next page*. Chapter boundaries are nothing special — the next tap just goes to chapter N+1's page 1. No new gesture.
- **Scroll mode** wants continuous flow. The grammar is *flick = pull more content*. Pretending there's a chapter wall when there isn't is fighting the medium. Content scrolls in; a divider + heading shows you've crossed a chapter.

This is mutually-exclusive at the *mode* level (#812 framing), not mutually-exclusive at the *app* level.

### 2.2 — Side-tap in paged mode, extended

Our existing 30 / 40 / 30 split (`vreader-reader.jsx::handleTap`) already handles tap-to-turn. The change for #812 is:

| Position | Tap | Behavior at boundary |
|---|---|---|
| Last page of chapter N | Right zone | → page 1 of chapter N+1 (no nav button, no confirmation) |
| First page of chapter N | Left zone | → last page of chapter N-1 |
| Last page of last chapter | Right zone | Bounce (subtle horizontal nudge animation, no nav) |
| First page of first chapter | Left zone | Same bounce |

Production code path: `Reader.advance()` already knows about chapters; the side-tap handler just needs to call `advance()` / `retreat()` instead of `nextPage` / `prevPage` at boundaries.

### 2.3 — Continuous scroll mode

When the user picks Scroll in Display sheet:

- Chapters render one after the other in a single scrollable column.
- A chapter boundary is rendered as:
  ```
  ─────────────  ────────────
                CHAPTER 2          ← uppercase, letter-spaced, t.sub
  ─────────────  ────────────
  ```
  Two short hairline rules flanking a centered chapter label. Vertical space ≈ 2 line-heights above + below. No buttons.
- The reader's bottom-chrome scrubber still shows current page / progress across the whole book — production app already computes this; just keep it.
- Lazy load: render current chapter + ±1 chapter eagerly; skeleton-pulse for further chapters until scrolled near.
- Scroll-position is saved on every settle; resuming a scroll-mode book scrolls to the exact pixel.

### 2.4 — Loading / mid-render

A 4-line skeleton (animated shimmer over `t.rule` color) appears at the bottom while the next chapter materializes. Only shown when the user has scrolled within 800px of the boundary; never on first load.

---

## 3. #842 — MD reader paged-mode layout

### 3.1 — Chrome inset (the root problem)

`PageContent`'s container is currently `top: 76, bottom: 56`. The bottom chrome is ~120px tall when visible, so content extends *under* the chrome — invisible but rendered.

**Fix:** content `bottom` becomes a function of chrome state.

```jsx
bottom: chromeVisible ? CHROME_HEIGHT + 8 : 56
```

Where `CHROME_HEIGHT` is a single source-of-truth constant derived from the chrome's actual layout (≈128px on iPhone 15-class). The 8px breath above the chrome edge keeps body text from kissing the chrome's hairline rule.

When chrome animates in/out (~180ms), the content's bottom inset animates the same curve. Justified text won't reflow mid-page because we're animating a clip region, not a width.

### 3.2 — Page indicator placement

There is only one canonical place for the page indicator at a time:

- **Chrome visible:** The chrome's scrubber row already shows `Page 147 · 285 pages left in book`. The content-bottom indicator hides (it would duplicate).
- **Chrome hidden:** Content-bottom indicator visible at `bottom: 18px`, centered, low-contrast (`t.sub` at 0.6 opacity). Format: `147 / 432`. No percentage — the chrome handles that.

Rejected alternatives:
- Top-right corner — competes visually with chapter heading, looks like a notification badge.
- Inside the chrome's progress bar — already there. Don't duplicate.
- Top + scrubber redundant — fine for accessibility, but adds visual noise. Single source of truth is cleaner.

### 3.3 — Tap-zone overlay (#842 §2)

The 30 / 40 / 30 zones already exist in MD paged mode (they live in `ReaderScreen::handleTap`, not in the renderer). The fix is **discoverability** — the issue's stated problem is that taps and swipes don't appear to do anything.

**First-open hint** — on first entry into the reader after install (and after a Reset Tips action in Settings):

- A non-interactive overlay layer fades in over 220ms after the page renders.
- Left zone: chevron-left icon + "Tap to go back" caption.
- Right zone: chevron-right icon + "Tap to advance" caption.
- Center zone: dot + "Tap to toggle controls".
- After 2.5s, the overlay fades out over 400ms.
- A `localStorage` flag (`vreader.tap-hint-seen`) prevents re-showing.

The hint sits *above* the page content but *below* the chrome, so the chrome's buttons remain primary. It is purely visual — pointer-events: none — so the first tap still does what it claims.

A "Show me again" tweak in the prototype re-triggers the hint without clearing the flag.

### 3.4 — Auto-page-turn indicator (state)

When Auto-turn is on (via the More menu), the page turns automatically at the configured interval. The user needs a way to see it's running and roughly when the next turn will fire.

**Indicator:** a 1px-tall accent-tinted ribbon at the very bottom of the page (`bottom: 0`), full width. Width animates from 0 to 100% across the interval; resets on each turn. Color is `t.accent` at 0.85 opacity in dark themes, 0.7 in light themes.

Why not a progress ring around the page counter? It would compete with the chrome scrubber's existing accent-bar. Why not a pulsing edge? Too easy to misread as "tap me." Why not invisible? The user has no idea whether they accidentally left it on.

The ribbon does not interfere with tap zones (it's at the very bottom and pointer-events: none). Tapping anywhere pauses auto-turn until the user dismisses the chrome and re-enters the reader, matching Kindle's behavior.

---

## 4. State coverage

The canvas (`VReader Navigation Canvas.html`) renders each of these states explicitly:

### EPUB chapter nav (#812)
- Paged · mid-chapter (default)
- Paged · at chapter boundary (text shows page N's content ending mid-paragraph, next tap will advance to chapter N+1)
- Paged · at last page of last chapter (next tap = bounce, shown as a sub-frame)
- Scroll · default (1 chapter visible)
- Scroll · crossing a chapter boundary (divider + heading visible in the middle of viewport)
- Scroll · mid-render (skeleton at bottom)

### MD paged-mode (#842)
- Default (chrome visible, content inset above, no indicator duplication)
- Chrome hidden (content extends to bottom, page indicator visible)
- Long content (3+ paragraphs, verifies that content respects inset)
- Auto-page-turn active (ribbon visible)
- First-open with tap-zone hint

### Cross-cutting
- Tap-zone hint — paper, dark, photo
- Auto-turn ribbon — paper, dark
- Debug overlay (tweak only) — 30/40/30 zones tinted for designer review

---

## 5. Cross-references

- Prototype wiring: `VReader Prototype.html` exposes Display → mode (Paged/Scroll), Auto-turn toggle/interval (existing), Reset tap-hint, Debug tap zones.
- Components: `vreader-tap-zones.jsx` (hint + debug overlays), `vreader-scroll-mode.jsx` (continuous renderer), `vreader-autoturn.jsx` (ribbon).
- Touches `vreader-reader.jsx::ReaderScreen` for the chrome-aware inset, the cross-chapter wrap in `handleTap`, and the renderer switch.
- Production: `MDReaderViewModel.bottomInset` becomes a published property derived from chrome visibility; `PaginatedReader.tap(at:)` calls `advance()` instead of `nextPage()` at boundaries.

---

## 6. What this does NOT cover

- The Scroll-mode font and layout settings — same Display sheet; no new controls.
- PDF reader chapter nav — PDFs don't have semantic chapters; out of scope.
- Touch-and-hold sliding (drag-to-flip with rubber band) — separate animation issue, future.
