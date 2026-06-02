# In-reader AI Providers entry — from the bilingual "Set up" button

> Resolves [#1380](https://github.com/lllyys/vreader/issues/1380). Splits off the
> routing slice of Bug [#301](https://github.com/lllyys/vreader/pull/301) (GH [#1356](https://github.com/lllyys/vreader/issues/1356)).
> Source of truth: `VReader AI Provider Entry Canvas.html` (every state across themes).
> Component file: `vreader-ai-provider-entry.jsx`. Editor reused from `vreader-ai-provider-fields.jsx`.

**Decision: a scoped, in-reader "AI Providers" sheet pushed inside the bilingual
flow, reusing the canonical `AIProviderEditSheet` for the actual add/edit, and
returning to the bilingual sheet with the new provider already selected as the
engine.** Components: `AIProvidersSheet` (list, empty + populated), `BilingualEngineStrip`
(before/after), plus the inline-expansion alternative `EngineStripInline`.

---

## The gap this fills

Bug #301 made the bilingual setup sheet *truthful*: when no AI provider is
configured, the engine strip stops claiming "configured" and shows a **"Set up"**
button. But `BilingualSetupSheet.onOpenSettings` currently just **dismisses the
sheet** — it routes nowhere.

Wiring it is not a one-liner, because the in-reader → AI Providers path does not
exist:

- The reader's `showSettings` sheet presents **only** `ReaderSettingsPanel`
  (display / fonts / theme).
- The full `SettingsView` — the one that contains `AISettingsSection` — is
  presented **only from the Library**.

So "Set up" has nothing to call. This is a new in-reader navigation surface →
`needs-design` per rule 51. The question the issue poses: **where does "Set up"
land, and how is it presented?**

---

## Three approaches

### A — Scoped AI Providers sheet, pushed in the bilingual flow  ·  CANONICAL

"Set up" pushes a **navigation level inside the same bottom sheet** — same frame,
same height, slide-left push. Nav bar: `‹ Bilingual` leading, **AI Providers**
title. The body is *only* the `AISettingsSection` provider list — nothing else
from `SettingsView`.

- **Zero providers** → the list shows an empty state (sparkle tile, one line of
  copy naming *why* the user is here — "Bilingual mode needs a provider to
  translate") and a single **Add provider** CTA.
- **Add provider** presents the canonical `AIProviderEditSheet`
  (`vreader-ai-provider-fields.jsx`) as its own modal sheet — full height,
  unchanged from the Library path. Kind / Name / Endpoint / Sampling / API Key /
  Test Connection all intact.
- **On the first Save**, the new provider becomes the bilingual engine default
  and the stack **pops all the way back to Bilingual**. The engine strip now reads
  *"Claude · configured" / "Change…"*, ready for **Turn on bilingual mode**. That
  return is the payoff — the user lands exactly where they started, with the one
  thing they were missing now filled in.
- Tapping `‹ Bilingual` *without* adding returns to Bilingual still unconfigured —
  no state mutated, no penalty for backing out.

**Why A wins**

- **Reuses the canonical editor.** No second, diverging "add a provider" form to
  maintain. Test Connection, keychain storage, endpoint hints — all the work
  already shipped in `AIProviderEditSheet` comes for free.
- **Keeps the reader context.** A scoped sheet, not the whole app-settings tree.
  The user never sees Cloud & Sync, OPDS catalogs, Book sources, TTS, replacement
  rules — none of which they came for.
- **Closes the loop.** The user's actual goal is "turn on bilingual"; A returns
  them to that goal with the blocker removed. B and C both leak that thread.
- **One surface for both entry points.** "Change…" (when already configured) lands
  on the *same* list, current provider checked — so add-first and change-later
  share a destination.

The extra navigation level (list → editor) looks like a cost when there are zero
providers, but it isn't: the empty state is a one-tap shortcut into the editor.
When the user *does* already have providers (added from Library, or for the AI
chat assistant), the list is the correct landing — "Set up" should let them pick,
not silently create a duplicate.

### B — Deep-link into the full `SettingsView`, scrolled to the AI section

Present the entire app `SettingsView` modally over the reader, auto-scrolled and
briefly highlighting the AI section.

- **Pro:** one surface, verbatim reuse of the Library path, no new navigation
  container.
- **Why not canonical:** it dumps a reader-context user into the *whole* app
  configuration — Cloud, OPDS, sources, TTS, Chinese conversion, About — to do one
  narrow thing. And the return is ambiguous: closing `SettingsView` drops the user
  back to the reader with the bilingual sheet already gone, so the "I was turning
  on bilingual" thread is lost. They have to re-open More → toggle bilingual again.

### C — Inline expansion inside the bilingual sheet

"Set up" expands the engine strip *in place* into a minimal provider-+-key form;
no navigation at all.

- **Pro:** the tightest possible loop — the user never leaves the bilingual sheet.
- **Why not canonical:** the real provider model is not "provider + key". It's
  kind, name, base URL (with append-path hints), model, sampling, keychain-stored
  key, and a live connection test. A bilingual half-sheet can't host that without
  either cramping it or shipping a stripped-down form that **diverges from
  `AIProviderEditSheet`** — at which point a key saved here wouldn't be testable,
  and two "add provider" surfaces would drift. Held in reserve for a future
  "express setup" only if we ever ship a genuinely one-field provider kind.

---

## Navigation model (precise)

```
   More ▸ Bilingual mode (first toggle on)
        └─ BilingualSetupSheet        [bottom sheet · height 620]
             engine strip: "No AI provider configured"  [ Set up ]
                                   │  onOpenSettings
                                   ▼   (push, slide-left, same sheet frame)
           AIProvidersSheet           [nav bar: ‹ Bilingual · "AI Providers"]
             ├─ empty  → [ Add provider ] ─┐
             └─ list   → tap a row sets it │  (present modal, full height)
                                   ▼        ▼
                          AIProviderEditSheet   [vreader-ai-provider-fields.jsx]
                                   │  Save
                                   ▼   (provider becomes bilingual engine,
                                        pop the whole stack)
           BilingualSetupSheet  ← engine strip now "Claude · configured" / Change…
```

- The AI Providers view is a **push within the bilingual sheet**, NOT a modal over
  the reader and NOT the full `SettingsView`.
- The editor is a **modal on top** (tall form deserves full height).
- "Change…" on an already-configured strip opens the **same** `AIProvidersSheet`,
  populated, current provider checked.

---

## States — covered exhaustively in the canvas

**Trigger**
- The bilingual sheet, engine unconfigured, "Set up" highlighted (start point) —
  paper + dark.

**A · canonical**
- AI Providers — empty (no providers) + bilingual-context note + Add CTA.
- Add Provider — the canonical `AIProviderEditSheet`, pushed.
- AI Providers — populated, new provider "In use" checked, Done.
- Return to Bilingual — engine configured, "Change…", ready to turn on (payoff).
- Empty + populated in dark.
- Reached via "Change…" — multiple providers, switching the selected one.

**B · alternative** — full `SettingsView` deep-link, AI section highlighted —
paper + dark.

**C · alternative** — inline expansion in the bilingual strip — paper + dark.

**D · anatomy** — the nav-stack diagram + engine-strip before/after, true size.

---

## Production wiring

- New reader-scoped presentation: a lightweight nav container hosting **only**
  `AISettingsSection`'s provider list — call it `ReaderAIProvidersView`. It is NOT
  `SettingsView`; it reuses the same `AIProviderListView` + `AIProviderEditSheet`
  cells.
- `BilingualSetupSheet.onOpenSettings` → presents `ReaderAIProvidersView` as a
  push inside the bilingual sheet's own `NavigationStack` (so `‹ Bilingual` is a
  real back, not a dismiss).
- On `AIProviderEditSheet` Save when launched from this flow: set the saved
  provider as the bilingual mode engine (`BilingualConfig.engineProviderID`) and
  dismiss back to the bilingual sheet (pop to root).
- `aiConfigured` on the engine strip is derived from
  `AISettingsViewModel.providers.isEmpty == false`; the strip's CTA label is
  `Set up` when empty, `Change…` otherwise (already shipped by #301).
- The Library `SettingsView → AI provider` row is unchanged; it still opens the
  full list. This adds a *second*, scoped entry — it does not move the first.

## Cross-references

| File | Role |
|---|---|
| `VReader AI Provider Entry Canvas.html` | Canvas of every state across themes. Source of truth. |
| `vreader-ai-provider-entry.jsx` | `AIProvidersSheet`, `BilingualEngineStrip`, `EngineStripInline`, `NavFlowDiagram` — #1380 |
| `vreader-ai-provider-fields.jsx` | `EditorSheet` (`AIProviderEditSheet`) — reused unchanged for the add/edit step (#1363) |
| `vreader-bilingual.jsx` | `BilingualSetupSheet` — the surface whose "Set up" button this wires (#790) |
| `design-notes/feature-60-followups.md` | Parent bilingual feature notes (#60 / #56) |
