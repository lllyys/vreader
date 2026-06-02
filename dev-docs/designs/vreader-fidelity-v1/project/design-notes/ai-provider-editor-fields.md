# AI provider editor — field pre-fill / placeholder + test-before-save (#1363 · Feature #79/#80)

> Source of truth (design): `VReader AI Provider Editor Canvas.html` → `ai-provider-editor-artboards.jsx` + `vreader-ai-provider-fields.jsx`.
> Chat transcript: `chats/chat16.md`.
> Resolves needs-design [#1363](https://github.com/lllyys/vreader/issues/1363) (Feature **#79** — field pre-fill). The design also expands into a sibling capability, **Feature #80** (test-before-save).
> Surface: `vreader/Views/Settings/AIProviderEditSheet.swift` (+ `+Sections.swift`), `AISettingsViewModel+Editor.swift`, `ProviderKind.swift`, `KindResetPolicy.swift`.
> Status: **design landed — implementation deferred** (recorded, not built; Swift held for a separate go-ahead per the handoff convention).

## The gap

In **add-mode** the editor seeds Base URL + Model with the kind's real default text
(`https://api.openai.com/v1`, `gpt-4o-mini`) as `@State` initial values
(`AIProviderEditSheet.swift:111-112`). The declared placeholders
(`+Sections.swift:68,89`) are **shadowed** because the binding is non-empty, SwiftUI
never clears on focus, and the user must backspace the defaults. The fix can't just
bind empty — an empty Base URL fails the `canSave` validation today, which would break
the zero-config "add a key and Save" flow.

## Decision (binding) — Variant A: placeholder + save-time fallback

1. **Bind the Base URL + Model fields empty** in add-mode. Show the kind default as a
   **muted placeholder** with a small **"Default" tag**. Nothing to delete on focus —
   the caret lands at the start; the user types, or leaves it blank.
2. **Save-time fallback** — a blank field **stores the kind default at Save**. `canSave`
   changes from "baseURL must be non-empty & valid" to validating the **effective** URL
   (typed value, else the kind default). So *blank + a key* still Saves. This is the one
   small VM change that makes the literal "placeholder" ask work without losing zero-config.
3. **Typed** → ink value, the "Default" tag disappears.
4. **Edit-mode** (existing provider) → show the **committed saved value** (ink), no
   placeholder, no "Default" tag, no "leave blank" hint. (`existing != nil` is the mode
   discriminator at `AIProviderEditSheet.swift:92`.)
5. **Kind picker drives the default** shown in the placeholder — OpenAI-compatible →
   `gpt-4o-mini` · `api.openai.com/v1`; Anthropic → `claude-sonnet-4-6` · `api.anthropic.com`
   (`ProviderKind`). `KindResetPolicy` already resets only untouched fields.

### Rejected alternatives (explored in the canvas)
- **B · prefilled + select-all on focus** — keeps the real default as an ink value, selects
  all on focus so one keystroke replaces it. Zero `canSave` change, but default vs. user-typed
  look identical and select-all is a quieter signal than a real placeholder. Safest to ship,
  **weakest affordance.**
- **C · empty field + tap-to-fill "Use defaults" chip** — most discoverable about what the
  default is, but the **most chrome** + an extra control to localize. Still needs the same
  blank→default save fallback as A.

## Scope expansion — Feature #80: Test Connection before Save

The design chat surfaced a second, bigger improvement the user asked for: **testing should
not require a Save-and-reopen round-trip.** Today the Test Connection button lives in the
**Connection** section and is shown only in edit-mode (add-mode shows a note "Save the
profile first, then return here to test"). The design reworks it:

- **Test Connection is available in add-mode**, gated on **input completeness** (a key
  entered), not on a saved profile. It runs against the **live form state + the typed
  in-memory key** — the VM's `testConnection(profile:)` already builds a candidate from the
  form fields; it just needs the typed key instead of a keychain read.
- **No key yet** → button shown disabled with the hint *"Enter an API key above to test — no
  need to save first."*
- States: **disabled · idle · Testing… (spinner) · Connected (green) · Failed (red).**
- API-key footnote → *"Saved to the keychain when you tap Save — but you can test it below first."*

## Visual system

Re-skinned to VReader's own design vocabulary (NOT generic iOS chrome): the warm
**paper / dark** theme, a bottom **Sheet** with a Source Serif title + Cancel / **Save**
(accent `#8c2f2f` light / `#d6885a` dark), rounded-14 cream cards, `SectionLabel` rows,
Inter body, and the segmented pill Provider-Type picker — matching the other canvases.

## Implementation pointers (deferred — do NOT build without go-ahead)

- **#79 (fields)**: in `AIProviderEditSheet` add-mode, bind Base URL/Model empty; render the
  kind default as the placeholder (already declared, just stop seeding the binding); add the
  "Default" tag; in `addProfile`/`canSave` (`AIProviderEditSheet.swift:167-190`), compute the
  **effective** URL/model (typed value else `defaultKind.defaultBaseURL`/`defaultModel`) and
  validate/persist that. Edit-mode unchanged (sticky saved values).
- **#80 (test-before-save)**: show the Test button in add-mode gated on `keyEntered`; pass the
  in-memory typed key into `testConnection` instead of reading the keychain; render the
  disabled/idle/testing/connected/failed states.
- Both are on the same surface — likely one implementation pass. Rule 51 satisfied (this note +
  canvas are the committed design).
