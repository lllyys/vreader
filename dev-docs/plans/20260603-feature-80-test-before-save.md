# Feature #80 — Test Connection before Save (add-mode, in-memory key)

Implements the #80 half of the landed design. Lets a user test a provider WITHOUT
a Save-and-reopen round-trip. **Committed design source (Rule 51)**: the canvas
`dev-docs/designs/vreader-fidelity-v1/project/vreader-ai-provider-fields.jsx:429`
+ `dev-docs/designs/vreader-fidelity-v1/project/ai-provider-editor-artboards.jsx:65`
(the footnote, the disabled-no-key hint, and the disabled/idle/testing/connected/
failed states), summarized in
`dev-docs/designs/vreader-fidelity-v1/project/design-notes/ai-provider-editor-fields.md`
(§ "Scope expansion — Feature #80"). Same surface as #79.

## Problem

`testConnection(profile:)` reads the API key from the **keychain**
(`AISettingsViewModel+Editor.swift:135`), so it requires a SAVED profile. The
Test Connection button is therefore **edit-mode-only**
(`AIProviderEditSheet+Sections.swift:215`); add-mode shows "Save the profile
first, then return here to test." Users must save (writing a key to the keychain)
before they can validate it — a clumsy round-trip.

## Decision (landed design)

- **Test Connection is available in add-mode**, gated on **input completeness**
  (an API key entered), not on a saved profile. It runs against the **live form
  state + the typed in-memory key**.
- **No key yet** → button shown DISABLED with the hint *"Enter an API key above to
  test — no need to save first."*
- States: **disabled · idle · Testing… (spinner) · Connected (green) · Failed (red).**
- API-key footnote → *"Saved to the keychain when you tap Save — but you can test
  it below first."*

## Surface area

- `vreader/Views/Settings/AISettingsViewModel+Editor.swift`
  - `testConnection(profile:)` → add an **in-memory-key path**:
    `func testConnection(profile:apiKeyOverride: String? = nil)`. When
    `apiKeyOverride` is non-nil + non-empty, use it; else the existing keychain
    read (so edit-mode with a saved key is unchanged). Empty override + no keychain
    key → `.failure(.apiKeyMissing)`. The provider-build switch is unchanged.
- `vreader/Views/Settings/AIProviderEditSheet.swift`
  - `runTest()`: pass the typed `apiKey` (`@State`) as `apiKeyOverride` (trimmed;
    nil when empty so edit-mode falls back to the saved keychain key).
  - **Stale-result invalidation (Gate-2 round-1 Medium)**: `testResultText` is
    persistent and nothing clears it today, so after a successful "Connected" the
    user can change the API key / Base URL / Model / kind / Max Tokens and the
    stale green result lingers — contradicting the "live form state" promise. Add
    a `resetTestResult()` (`testResultText = nil`) and call it from the `onChange`
    of EVERY request-shaping input: `apiKey`, `baseURLText`, `model`, `kind`,
    `maxTokens`. (A pure helper isn't needed — it's a one-line state reset — but
    the set of inputs that must reset it is part of the contract + tested.)
  - **Saved-key presence transitions (Gate-2 round-2 Medium)**: `saveKey()` and
    `deleteKey()` mutate `isAPIKeySaved` (and clear `apiKey`) — which changes what a
    subsequent test does — WITHOUT firing any of the five `onChange` hooks. So
    after a "Connected", a `Delete Key` (or `Save Key`) would leave a stale green
    result. Also call `resetTestResult()` at the end of `saveKey()` / `deleteKey()`
    (the `isAPIKeySaved` change is the trigger).
- `vreader/Views/Settings/AIProviderEditSheet+Sections.swift`
  - `testConnectionSection`: show the Test button in **both** modes. Enabled when
    `!testInFlight && hasTestableKey`, where `hasTestableKey` =
    `!apiKey.trimmed.isEmpty || isAPIKeySaved`. When NOT testable → button disabled
    + the "Enter an API key above to test — no need to save first." hint (replaces
    the add-mode "Save first" note). Keep the spinner (Testing…) + the
    green/red result (Connected/Failed) — already present, just un-gated from
    edit-mode.
  - `apiKeySection` footnote → "Saved to the keychain when you tap Save — but you
    can test it below first." (add-mode; edit-mode keeps its existing copy).

### Out of scope
- #79 (field placeholders — shipped). The effective-value helpers from #79 are
  REUSED so a blank add-mode URL/model tests the kind default.
- The visual re-skin beyond the design's stated states.

## Prior art / precedent / rejected alternatives
- **Precedent**: `runTest()` already builds a candidate `ProviderProfile` from live
  form state (audit-round-1 finding [1]); #80 only swaps the KEY source from
  keychain to the typed in-memory value. The states (spinner/green/red) already
  exist in `testConnectionSection`.
- **Rejected**: writing the key to the keychain before test (the current
  round-trip) — the whole point of #80 is to avoid it; an unsaved test must not
  persist a key the user hasn't committed.

## Work-item sequencing
Single behavioral WI (VM overload + section gating + footnote). ~small. Final WI.

## Test catalogue
- `AISettingsViewModelEditorTests` (HTTP suite): `testConnection(profile:apiKeyOverride:)`
  uses the OVERRIDE key (assert the outgoing request's Authorization/x-api-key
  header = the override, NOT a keychain value) when provided; falls back to the
  keychain when override is nil; empty override + no keychain → `.apiKeyMissing`.
- A `hasTestableKey` pure helper (extract like #79's statics): true when typed key
  non-empty OR saved; false otherwise — for the button gating + hint.
- **Stale-result invalidation** (Gate-2 round-1 + round-2 Medium): after a result
  is set, changing any of `apiKey`/`baseURLText`/`model`/`kind`/`maxTokens` resets
  it to idle (`testResultText == nil`); AND `saveKey()`/`deleteKey()` (saved-key
  presence transitions) reset it too — so a stale "Connected" can't linger over
  edited form state or a removed key. (Test the reset contract for each trigger.)
- Edge cases: whitespace-only typed key → treated as no key (disabled + hint);
  add-mode blank URL/model + a key → tests the kind default (reuses #79 effective
  values); edit-mode with a saved key + no typed key → still tests the saved key
  (no regression).

## Risks + mitigations
- *Risk*: leaking/persisting the typed key during test. *Mitigation*: the override
  is passed by value to `testConnection` and used only to build the transient
  provider; nothing writes it to the keychain (only `saveAPIKey`/Save does).
- *Risk*: edit-mode regression (a saved-key profile must still test via keychain).
  *Mitigation*: override is nil when the typed field is empty → keychain fallback;
  HTTP test asserts both paths.
- *Risk*: the "no key" disabled+hint must not block the existing edit-mode
  saved-key flow. *Mitigation*: `hasTestableKey` ORs the saved flag.

## Backward compat
Additive VM param (defaulted nil) + a UI gating change. No schema/persistence.
Edit-mode saved-key testing is unchanged (override nil → keychain read).

## Acceptance criteria
1. Add-mode with an API key typed → the Test Connection button is enabled and
   tests against the live form + typed key (no Save first).
2. Add-mode with NO key → button disabled + "Enter an API key above to test — no
   need to save first."
3. States render: idle → Testing… (spinner) → Connected (green) / Failed (red).
4. Edit-mode with a saved key (no typed key) still tests via the keychain
   (no regression).
5. The test never persists the typed key (only Save does).
6. API-key footnote reflects "test below first."
7. A prior result is cleared (back to idle) when any request-shaping input
   (key / Base URL / Model / kind / Max Tokens) changes OR the saved key is
   added/removed (`saveKey`/`deleteKey`) — no stale "Connected".

## Revision history
- **v1** (2026-06-03) — initial plan.
- **v2** (2026-06-03) — Gate-2 Codex audit round 1 (`/tmp/feat80-planaudit.txt`,
  SUCCEEDED): 0 Critical/High, **2 Medium, both addressed.**
  - Medium (wrong design-source path) → cited the actual committed canvas
    `vreader-ai-provider-fields.jsx:429` / `ai-provider-editor-artboards.jsx:65`
    (+ the design-note full path).
  - Medium (stale `testResultText` not invalidated on input change) → added
    `resetTestResult()` wired to the `onChange` of every request-shaping input +
    a test + acceptance criterion 7.
  - Audit confirmed all model assumptions (`testConnection` + `apiKeyOverride`
    clean; `runTest` builds live state w/ #79 effective values; `hasTestableKey`
    gating correct + edit-mode-safe; no key logging / keychain write on test).
- **v3 / Gate-2 CLOSED** (2026-06-03) — round 2 (`/tmp/feat80-planaudit-r2.txt`):
  (a) design path resolved; (b) 1 new Medium — the stale-result reset missed
  saved-key presence transitions (`saveKey`/`deleteKey` change what a test does
  but fire none of the 5 input hooks). v3 also resets `testResultText` in
  `saveKey()`/`deleteKey()` + extends criterion 7 + the test. Converged 2→1→0.
  **Gate 2 passes: 0 Critical / 0 High / 0 open Medium.**
