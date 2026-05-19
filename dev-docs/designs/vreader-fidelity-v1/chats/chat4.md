# I don't have access to external links or the ability to browse GitHub. Could you please share the content of the issue or describe what you're designing so I

_Started 2026-05-19 04:50 UTC_

---

## User

https://github.com/lllyys/vreader/issues/914

## Assistant

_[tool: list_files]_

_[tool: read_file]_

_[tool: web_fetch]_

_[tool: read_file]_

_[tool: read_file]_

_[tool: read_file]_

_[tool: read_file]_

_[tool: read_file]_

Now I have strong context. Let me look at the Followups Canvas to see how it presents new design issues, then create the design for the highlight-note edit surface.

_[tool: grep]_

I have enough context. Let me design the **highlight-note edit surface** for issue #914.

**My approach:** Commit to a canonical form (a keyboard-anchored half-sheet — the standard iOS pattern, gives the note room without losing context), plus two alternatives (inline-expanded callout and full-page) for variation. Cover all required states.

Let me check what icons exist:

_[tool: grep]_

_[tool: grep]_

_[tool: grep]_

_[tool: update_todos]_

Now I have everything I need. Let me design.

**My approach for issue #914 — Highlight-Note Edit Surface:**

- **Canonical:** `HighlightNoteEditSheet` — a keyboard-anchored half-sheet, the standard iOS editor pattern. Anchored above the keyboard (not behind it), excerpt strip for context, generous Source Serif textarea, header [Cancel · Note · Save]. Save is destructive-coloured when it would clear a note.
- **Alternative:** `FullScreenNoteEditor` — for VoiceOver / long-form / accessibility path.
- **CJK is explicitly first-class** — proper CJK font stack (`"Source Han Serif", "Songti SC", "Noto Serif SC"`), looser CJK line-height (1.8 vs 1.55 for Latin), one dedicated artboard for Chinese, one for Japanese, IME compose-state visual indicator.
- Cover every required state: editing existing, empty/add, clearing, discard-confirm, save-in-flight, save error, long content, CJK (zh + ja), RTL (Arabic), dark/sepia.

_[tool: write_file]_

_[tool: write_file]_

_[tool: write_file]_

_[tool: show_html]_

_[tool: done]_

_[tool: update_todos]_

_[tool: fork_verifier_agent]_

Designed the highlight-note edit surface for issue #914 — `VReader Note Editor Canvas.html`.

**Canonical form:** `HighlightNoteEditSheet` — keyboard-anchored half-sheet (sits *above* the iOS keyboard, not behind it). Header is `[Cancel] · Note · [Save]`; excerpt strip keeps the highlighted passage visible while editing; Save flips to destructive "Clear" when the user empties an existing note. The inline `editing` stub in `vreader-note-preview.jsx` is replaced by a real, buildable surface.

**CJK is first-class** — body font cascades through Source Han Serif → Songti SC → Noto Serif SC (zh) / Noto Serif JP / Yu Mincho (ja); CJK content uses 1.85 line-height vs 1.55 for Latin so dense glyphs breathe. IME compose state has a visible "Composing · …" pill so users mid-pinyin always know where they are. `dir="auto"` flips for Arabic.

**States covered:** editing existing · adding to color-only · clearing-to-empty · saving · save error · discard-confirm · long content · zh CJK filled · zh CJK mid-IME · ja CJK · ar RTL · dark · sepia. Plus an alternative `FullScreenNoteEditor` for VoiceOver and long-form. Final section is a binding-contract spec card naming the persistence call site (`HighlightPersisting.updateHighlightNote`) and the theme tokens used.

## User

done？

## Assistant

Yes — done. The canvas is live at **VReader Note Editor Canvas.html** with 5 sections covering 22 artboards:

1. **Intent** — canonical editor + empty/add entry
2. **Save flow & edge states** — dirty, will-clear, saving, saved toast, error, discard alerts
3. **CJK & RTL** — zh filled, zh mid-IME, ja, ar (first-class)
4. **Themes** — dark, sepia, dark+CJK, dark error
5. **Alternative form** — full-screen editor for VoiceOver / long-form
6. **Spec card** — binding contract for the `HighlightPersisting.updateHighlightNote` handoff

Let me know if you want any state tweaked, more variants, or a specific artboard pulled out for closer review.

