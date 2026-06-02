# Feature #79 — AI provider editor: Base URL / Model as placeholders (Variant A)

Implements the landed design `design-notes/ai-provider-editor-fields.md`
(Variant A), resolving the now-closed needs-design #1363. **Scope: #79 only**
(the sibling #80 "test-before-save" shares the surface but is a separate issue).

## Problem

In **add-mode** the editor seeds Base URL + Model with the kind's real default
TEXT (`AIProviderEditSheet.swift:125-126`) as `@State` initial values, so the
declared placeholders are shadowed (the binding is non-empty), SwiftUI never
clears on focus, and the user must backspace the defaults. Binding empty naively
would break `canSave` (empty URL fails validation → breaks the zero-config "add a
key and Save" flow).

## Decision (from the landed design — Variant A, NOT invented here)

1. Bind Base URL + Model **empty** in add-mode; show the **kind default as a muted
   placeholder** + a small **"Default" tag**.
2. **Save-time fallback**: a blank field stores the kind default at Save. `canSave`
   validates the **effective** URL (typed value else kind default) — so blank + a
   key still Saves.
3. Typed → ink value, the "Default" tag disappears.
4. **Edit-mode** (existing provider) → committed saved value, no placeholder / tag.
5. Kind picker drives the placeholder default (`ProviderKind.defaultBaseURL/
   defaultModel`); `KindResetPolicy` already leaves empty/untouched fields.

## Surface area (file-by-file)

- `vreader/Views/Settings/AIProviderEditSheet.swift`
  - **init add-mode** (`:125-126`): `_baseURLText = State(initialValue: "")`,
    `_model = State(initialValue: "")`. (Edit-mode init unchanged — committed values.)
  - `private var isAddMode: Bool { existing == nil }`.
  - **Effective values are ADD-MODE-ONLY** (Gate-2 round-1 High — a global fallback
    would make an edit-mode user who *clears* Base URL/Model silently persist the
    kind defaults instead of their literal intent):
    - `effectiveBaseURLText` = let `t = baseURLText.trimmed`; `isAddMode && t.isEmpty
      ? kind.defaultBaseURL.absoluteString : t`. (Edit-mode → raw `t`, so clearing
      still fails validation exactly as today.)
    - `effectiveModel` = `isAddMode && model.trimmed.isEmpty ? kind.defaultModel :
      model.trimmed`. (Edit-mode → raw, unchanged.)
  - `canSave` (`:181-184`): validate `effectiveBaseURLText`.
  - `save()` (`:186-201`): build the `ProviderProfile` from the effective URL/model.
  - `runTest()` (`:249-261`): use the effective URL/model **only in add-mode** —
    edit-mode `runTest` keeps raw semantics (Gate-2 round-1 High). (#80, not #79,
    owns the broader add-mode Test rework; this only makes a blank add-mode field
    test the default.)
  - **Live error path** (Gate-2 round-1 Medium): `baseURLError` is computed in
    `+Sections` `onChange` (`:74-76`) and in `save()` (`:189`) from raw
    `validateBaseURL(baseURLText)`. Switch both to validate the **effective**
    value, so an add-mode blank/whitespace field shows NO "URL cannot be empty"
    error (the default is valid), while a non-empty INVALID typed URL still errors.
- `vreader/Views/Settings/AIProviderEditSheet+Sections.swift`
  - Base URL + Model `TextField` placeholders (`:68,89`): **add-mode-aware**
    (Gate-2 round-2 Medium — an existing edit-mode profile can already have
    `model == ""`; an unconditional `kind.defaultModel` placeholder would render a
    misleading default in edit-mode). Branch on `existing == nil`: **add-mode** →
    placeholder = `kind.defaultBaseURL.absoluteString` / `kind.defaultModel` (the
    real default); **edit-mode** → no default placeholder (empty/neutral — the
    committed value is the binding; an empty edit-mode model shows a plain empty
    field, never the default hint).
  - Add a muted **"Default" tag** beside each field, shown only in add-mode when
    the field is empty (committed design `ai-provider-editor-artboards.jsx:45-79` /
    `vreader-ai-provider-fields.jsx:227-231`); hidden once typed or in edit-mode.
  - The `onChange` validation uses the effective value (add-mode-aware, above).

### Out of scope
- **Feature #80** (Test Connection in add-mode) — same surface, separate issue/PR;
  `runTest`'s effective-value change here is compatible with it but does NOT add
  the add-mode Test button / gating.
- The kind picker / `KindResetPolicy` logic (already leaves empty fields alone).
- Edit-mode behavior (unchanged).
- The API-key `SecureField` / keychain flow.

## Prior art / precedent / rejected alternatives
- **Precedent**: the placeholders are already DECLARED (`+Sections:68,89`) — the
  design's insight is they're merely shadowed by the non-empty binding. The
  "effective value at save" mirrors how other forms fall back to a default.
- **Rejected (in the design canvas)**: Variant B (prefilled + select-all-on-focus —
  weakest affordance, default vs typed look identical); Variant C (empty + "Use
  defaults" chip — most chrome). Variant A is the binding decision.

## Work-item sequencing
Single behavioral WI (one surface, one PR). ~small. Final WI.

## Test catalogue
- `AISettingsViewModelEditorTests` (or a focused sheet test): the **effective**
  URL/model logic — blank baseURL → kind default persisted; blank model → kind
  default; typed values pass through verbatim; `canSave` true for blank+valid-key
  (effective URL valid), false for an explicitly INVALID typed URL.
- Add-mode init binds empty (`baseURLText == ""`, `model == ""`); edit-mode binds
  the committed values.
- Kind switch updates the effective default (OpenAI → `gpt-4o-mini` /
  `api.openai.com/v1`; Anthropic → `claude-sonnet-4-6` / `api.anthropic.com`).
- **Edit-mode is unchanged** (Gate-2 round-1 High): an edit-mode profile with a
  CLEARED Base URL → `canSave` false (raw empty fails, as today, NOT defaulted);
  a cleared Model in edit-mode stores raw "" (pre-existing behavior, out of scope).
- Edge cases: whitespace-only add-mode field → treated as blank (uses default);
  a non-empty typed URL that fails validation → `canSave` false (not silently
  defaulted). **Blank model is NOT provider-tolerated** (Gate-2 round-1 Medium —
  both `AIProvider`/`AnthropicProvider` serialize `model` verbatim, no `""`
  fallback), so the add-mode blank→`kind.defaultModel` resolution before save is a
  REQUIRED local fix, not "current behavior"; test that add-mode blank model
  persists the kind default (never "").

## Risks + mitigations
- *Risk*: `canSave` change could let an invalid typed URL slip through if "effective"
  masks it. *Mitigation*: effective = typed-if-non-empty, so a non-empty INVALID
  typed URL is still validated (and fails); only a BLANK field uses the default.
- *Risk*: the "Default" tag is new UI. *Mitigation*: it's in the committed design
  canvas (Rule 51 satisfied) — render to the design's muted-tag spec, not invented.
- *Risk*: edit-mode regressions. *Mitigation*: `existing != nil` gates all the
  add-mode changes; edit-mode keeps committed values + no placeholder/tag.

## Backward compat
Pure UI/validation behavior change in add-mode; no schema, persistence, or
migration. Existing saved providers (edit-mode) render unchanged. A user who
previously relied on the pre-filled default still gets it (now via the blank→default
save fallback).

## Acceptance criteria
1. Add-mode: Base URL + Model start **empty** with the kind default shown as a muted
   placeholder + a "Default" tag (no text to delete).
2. Saving with a blank Base URL (+ a key) stores the kind default URL; blank Model
   stores the kind default model.
3. A typed value is used verbatim; the "Default" tag disappears once typed.
4. `canSave` accepts blank fields (effective URL valid) but still rejects a non-empty
   INVALID typed URL.
5. Edit-mode shows the committed values with no placeholder/tag; clearing a field
   in edit-mode does NOT silently default (raw semantics, unchanged).
6. The placeholder/default follows the selected provider kind.

## Revision history
- **v1** (2026-06-03) — initial plan.
- **v2** (2026-06-03) — Gate-2 Codex audit round 1 (`/tmp/feat79-planaudit.txt`,
  SUCCEEDED): **1 High + 2 Medium, all addressed.**
  - High (global effective-value would break edit-mode clear→default) → scoped the
    effective fallback + `runTest` change to **add-mode only** (`existing == nil`);
    edit-mode keeps raw validate/persist/test semantics.
  - Medium (live `baseURLError` path still raw) → `onChange` + `save()` validation
    switched to the effective value (add-mode blank clears the error; non-empty
    invalid still errors).
  - Medium (false "empty model allowed; provider defaults") → corrected: providers
    serialize `model` verbatim, so add-mode blank→`kind.defaultModel` is a required
    local fix; tests assert the default is persisted, never "".
  - Audit confirmed all model assumptions exist (`ProviderKind.defaultBaseURL/
    defaultModel`, `validateBaseURL` nonisolated static, `KindResetPolicy`
    empty-field-safe) + Rule-51 (the "Default" tag is in the committed canvas).
- **v3 / Gate-2 CLOSED** (2026-06-03) — round 2 (`/tmp/feat79-planaudit-r2.txt`):
  all 3 round-1 findings confirmed resolved; **1 new Medium** — an unconditional
  `kind.defaultModel` placeholder would mislead in edit-mode (existing profiles can
  have `model == ""`). v3 gates the **placeholder itself** to add-mode (edit-mode →
  no default hint). Converged 3→1, all resolved. Added an edit-mode-empty-model
  placeholder test. **Gate 2 passes: 0 Critical / 0 High / 0 open Medium.**
