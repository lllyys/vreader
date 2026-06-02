# Feature #81 — In-reader AI Providers entry (Gate-1 plan)

Wire the bilingual setup sheet's "Set up" / "Change…" button (truthful since Bug
#301) to a SCOPED in-reader AI Providers sheet, reusing the canonical
`AIProviderEditSheet`, returning to the bilingual sheet with the saved provider
selected as the active engine. Resolves the **routing slice** of Bug #301 (#1356 /
#1380).

- **Design (binding, Variant A)**: `dev-docs/designs/vreader-fidelity-v1/project/design-notes/reader-ai-provider-entry.md`, canvas `VReader AI Provider Entry Canvas.html`, component `vreader-ai-provider-entry.jsx`.
- **Status target**: `TODO` → `PLANNED` (after Gate-2) → `IN PROGRESS` → `DONE` → `VERIFIED`.

## Revision history / audit rounds

- **v1** (Gate-1 draft).
- **v2** (Gate-2 round 1 — Codex gpt-5.5/high): verdict NEEDS REVISION; 1 Critical,
  4 High, 4 Medium, 1 Low. All addressed — see **Audit fixes applied** at the bottom.
- **v3** (Gate-2 round 2 — Codex gpt-5.5/high): 8/10 resolved; 1 High + 1 Medium +
  1 Low reopened because v2 wrongly said "no callback added to `AIProviderListView`"
  while the editor sheet is constructed PRIVATELY inside it (so the reader container
  couldn't receive the saved id), and the `activeID` observation could pop under the
  still-present editor. v3 replaces `activeID` observation with explicit callbacks
  forwarded through `AIProviderListView`.
- **Gate 2 PASSED** (round 3 — Codex gpt-5.5/high): verdict **READY TO BUILD**, zero
  open Critical/High/Medium. All three round-2 findings RESOLVED; buildability
  spot-check on the `.sheet(item:onDismiss:)` re-emission + optional-closure
  forwarding + `Task { await … }` wrapper from `onDismiss` confirmed sound. 3 rounds
  total (rule-47 cap).

## Problem

Bug #301 made the bilingual setup sheet truthful — when bilingual translation
isn't ready the engine strip shows a **"Set up"** button — but
`BilingualSetupSheet.onOpenSettings` currently just **dismisses the sheet**
(`cancelBilingualSetup()` in every host, the documented "WI-15 hook"). The in-reader
→ AI Providers path doesn't exist: the reader's `showSettings` presents only
`ReaderSettingsPanel`; the full `SettingsView` (with the provider list) is
Library-only. This feature builds the missing scoped entry so "Set up" routes to a
provider list inside the bilingual sheet.

## Readiness gates — explicit scope boundary (Gate-2 fix)

`BilingualAIReadiness.resolve` (the gate the strip's `configured` reflects since
#301) requires **all four**: `aiAssistant` feature flag ON + AI consent granted +
an ACTIVE provider profile + that profile's non-empty per-profile API key. In the
current build `aiAssistant` defaults **false** (ships dark) and consent defaults
**false**; the bilingual More-menu row is **never gated** (design §2.3), so a user
can reach "Set up" with the flag/consent gates unsatisfied.

**This feature owns only the provider gates (active profile + key) via the designed
provider list + editor.** The `aiAssistant` flag and consent are NOT in scope:

- They are **not** in the committed Variant A design (which is explicitly "only the
  `AISettingsSection` provider list — nothing else from `SettingsView`"). Adding an
  in-reader AI-enable toggle or consent affordance would be **inventing UI** →
  prohibited by rule 51.
- They already have **designed affordances** in the Library `AISettingsSection`
  (the "Enable AI Assistant" master toggle + "Allow AI data sharing" consent
  toggle). Enabling AI + granting consent is the existing Library responsibility.

**Resulting behavior (truthful, per #301):**

| User state on entering "Set up" | After add provider + key + activate |
|---|---|
| AI on + consent granted (provider missing) | strip → **configured** → pop back → "Change…", ready to turn on bilingual. **The designed payoff.** |
| AI on + consent, provider saved WITHOUT a key | strip stays "Set up" (no key) — correct |
| AI off OR no consent | strip stays "Set up" — correct & truthful; the saved provider persists and becomes usable once the user enables AI + consents in Library |

This is a **net improvement regardless of state** — today "Set up" routes nowhere;
after this it always reaches the provider list. The fresh-user "provider saved but
strip still Set up because AI-off/no-consent" wrinkle is filed as **Feature #82
(`TODO`, BLOCKED: needs-design, GH #1394)** — an in-reader AI-enable + consent
affordance requiring its own `claude.ai/design` pass; it is **not** invented here.

## Prior art / project precedent / rejected alternatives

- **Reuse, don't rebuild.** `AIProviderListView` (Settings) ALREADY provides the
  "AI Providers" `navigationTitle` + `.inline`, an empty state, a `+` toolbar →
  `AIProviderEditSheet` (add), and row-tap `setActive`, over an injectable
  `AISettingsViewModel(profileStore: .shared, keychainService:)`.
  `AIProviderEditSheet(viewModel:existing:)` is the canonical editor. This feature
  REUSES both — no second "add provider" form.
- **Design rejects** B (deep-link the whole `SettingsView`) and C (inline strip
  form). Variant A (scoped push + canonical-editor reuse + pop-back-configured
  payoff) is canonical.
- **"Engine" == active provider.** The design's "Production wiring" names
  `BilingualConfig.engineProviderID`, but the bilingual runtime
  (`BilingualAIReadiness.resolve`, `ChapterTranslationPrefetcher`) reads the
  **active** `ProviderProfile`, not a bilingual-specific id. A separate
  `engineProviderID` would be dead state the pipeline never reads. This plan
  implements "becomes the engine" as "becomes the **active profile**" — identical
  user-visible behavior, no dead state, no rule-51 deviation (no visible surface
  change).
- **VERIFIED — add-save auto-activates only the FIRST provider** (Gate-2 Critical
  fix). `AISettingsViewModel+Editor.addProfile` sets the new profile active only
  when `snapshot.activeID == nil`. Relying on that alone would break the payoff for
  a SECOND provider added during the "Change…" flow. **Therefore the reader flow
  explicitly activates the just-saved provider** (`setActive(savedID)` on
  save-success), not relying on `addProfile`'s first-only auto-activation. Library
  behavior is unchanged (the explicit activation is reader-flow-only, driven by the
  editor's new `onSaveSuccess` callback).

## Surface area (file-by-file)

### New
- **`vreader/Views/Reader/Bilingual/ReaderAIProvidersView.swift`** — the scoped
  reader AI-Providers view. Hosts `AIProviderListView(viewModel:emptyState:)`
  (reused) configured with the design's bilingual-context empty state (sparkle tile
  + "Bilingual mode needs a provider to translate" + single "Add provider" CTA via
  the data-only config below). It forwards two explicit callbacks straight into the
  reused `AIProviderListView` (it does NOT observe `viewModel.activeID` — Gate-2
  round-2 fix): `onEditorSaveSuccess: (UUID, _ wasAdd: Bool) -> Void` and
  `onRowActivated: (UUID) -> Void`. `ReaderAIProvidersView` is the list-presentation
  + nav-title surface (`.toolbar(.visible, for: .navigationBar)` so the pushed level
  shows the system nav bar with `‹ Bilingual` back + "AI Providers" title).
- **`vreader/Views/Reader/Bilingual/BilingualSetupSheetContainer.swift`** — a shared
  wrapper presented by all 6 sites. Owns: a `NavigationStack`, an
  `@State AISettingsViewModel` (default-constructed: `ProviderProfileStore.shared` +
  `KeychainService()`), and the nav path. Root = `BilingualSetupSheet` (system nav
  bar hidden via `.toolbar(.hidden, for: .navigationBar)` — the root keeps its own
  `ReaderSheetChrome`). `onOpenSettings` (consumed internally) pushes
  `ReaderAIProvidersView`. **Activation is driven by explicit callbacks, NOT
  `activeID` observation** (Gate-2 round-2 fix — raw observation could pop underneath
  the still-present editor because first-add mutates `activeID` before the editor
  dismisses):
  - `onEditorSaveSuccess(id, wasAdd)` — `AIProviderListView` fires this from its OWN
    `.sheet(item:onDismiss:)`, AFTER the editor sheet fully dismisses (the editor's
    `onSaveSuccess` only records a pending id; the list re-emits it in `onDismiss`).
    The container then `await viewModel.setActive(id)` (the Critical fix — explicit
    activation works for non-first adds too), `await onConfigured()` (host →
    `bilingualViewModel?.refreshAIConfigured()`, explicit refresh — NOT relying on
    the root sheet's `.task` re-running), then pops to root. No pop-under-editor —
    it all runs post-dismiss.
  - `onRowActivated(id)` — `AIProviderListView` fires this after a row tap's
    `setActive` completes (no modal in flight). The container `await onConfigured()`
    + pops. Tapping the already-active row in the Change flow still pops (confirms
    the current engine).
  - The initial `loadProfiles()` hydration fires NEITHER callback (not a user
    action), so the Change-flow active-row selection never auto-pops.
- **Empty-state seam — builder, not data-config** (implementation refinement, still
  within the auditor's endorsed options). The design's empty state is too rich for a
  string config: a gradient **sparkle tile** (54pt circle), a serif "No providers
  yet", a keychain-privacy line ("…stored in the device keychain — never synced"),
  and a pill "Add provider" button — plus a persistent **context banner**
  ("Choose the provider **bilingual mode** will use to translate this book."). So
  `AIProviderListView` takes `emptyState: ((@escaping () -> Void) -> AnyView)? = nil`
  (round-1 finding #5's first recommended form — a builder that RECEIVES the list's
  internal add action, so its CTA drives `editorContext = .add()`). Default nil →
  the current globe state, Library byte-identical. `ReaderAIProvidersView` renders
  the design's empty body via this builder and the context banner above the list. The
  design notes explicitly sanction reusing `AIProviderListView` cells, so the
  populated list keeps AIProviderListView's existing rows (the active radio = the
  design's "In use" check) + its toolbar "+".

### Modified
- **`vreader/Views/Settings/AIProviderListView.swift`** — add THREE optional params,
  all default nil/`.default` → Library path byte-identical (Gate-2 round-2: the
  editor sheet is constructed PRIVATELY here, so the reader callbacks MUST be
  forwarded through this view, not just added to the editor):
  1. `emptyState: ((@escaping () -> Void) -> AnyView)? = nil` — when nil, the current
     globe empty state; when supplied, render `emptyState(addAction)` with
     `addAction = { editorContext = .add() }` so the builder's CTA drives the
     internal editor. Library path byte-identical (nil default).
  2. `onEditorSaveSuccess: ((UUID, _ wasAdd: Bool) -> Void)? = nil` — this view
     records the editor's `onSaveSuccess(id, wasAdd)` into a private
     `@State pendingSaved` and re-emits it to `onEditorSaveSuccess` from its
     `.sheet(item: $editorContext, onDismiss:)` handler, AFTER the editor dismisses.
     It passes its own internal recorder as the editor's `onSaveSuccess`.
  3. `onRowActivated: ((UUID) -> Void)? = nil` — fired in the row-tap button after
     `await viewModel.setActive(profile.id)` completes.
- **`vreader/Views/Settings/AIProviderEditSheet.swift`** — add a default-nil
  `onSaveSuccess: ((UUID, _ wasAdd: Bool) -> Void)? = nil`. Fire it inside `save()`
  AFTER a successful add/update, just before `dismiss()`. Default nil → Library path
  unchanged. `AIProviderListView` (not the reader) supplies this closure to record
  the pending id; the container performs `setActive(id)` + refresh + pop from the
  list's `onDismiss` re-emission (post-dismiss) — NOT before `dismiss()` settles,
  avoiding the sheet-over-sheet pop-timing race the audit flagged.
- **`vreader/Views/Settings/AISettingsViewModel.swift`** (NO change expected) — the
  reader activation reuses the existing `setActive(_:)`. Listed only to confirm no
  new VM API is needed.
- **The six bilingual presentation sites** — swap `BilingualSetupSheet(...)` for
  `BilingualSetupSheetContainer(...)` with the same host bindings (`state`,
  `engineDescriptor`, `onConfirm`, `onCancel`) + an `onConfigured` that refreshes the
  host's `bilingualViewModel?.aiConfigured`. `onOpenSettings` is dropped from the
  call site (the container owns routing). Five present via a `bilingualSetupSheetView`
  builder var (TXT/MD/PDF/EPUB/Readium `*+Bilingual.swift`); **Foliate presents
  `BilingualSetupSheet` INLINE inside `.sheet` in `FoliateBilingualContainerView.swift`
  (~L306)** — its swap is the same view-type change, just inline rather than in a
  builder (Gate-2 Low fix — Foliate has no builder var).

### Files OUT of scope
- The Library `SettingsView → AI provider` row (unchanged — second scoped entry).
- `aiAssistant` flag + AI consent affordances (existing Library `AISettingsSection`;
  see "Readiness gates" above — not invented in-reader).
- The `.unavailable` More-menu-row → AI-settings dispatch in `handleMoreMenuAction`
  (a separate, pre-existing entry; #81 is the setup-sheet "Set up" button per its
  design).
- `AIProviderEditSheet` internals (reused; only the additive `onSaveSuccess`).
- The bilingual translation pipeline. Variants B + C (rejected by the design).

## Work-item sequencing — single WI

**WI-1 (behavioral, final, 1 PR)** — the whole feature in one PR. v1 split this into
WI-1 (view + seams) + WI-2 (wiring); the Gate-2 audit noted WI-1 is dead code until
WI-2 wires it, so they merge. Order within the PR: (1) `AIProviderEmptyStateConfiguration`
+ `AIProviderListView` empty-state param; (2) `AIProviderEditSheet.onSaveSuccess`;
(3) `ReaderAIProvidersView`; (4) `BilingualSetupSheetContainer` (nav + activation +
pop); (5) swap the 6 sites. Each step is TDD-gated. **Device verification (Gate-5,
final WI)**: with AI enabled + consent granted (the designed happy path) — fresh
provider state → open a book → Bilingual ON → "Set up" → AI Providers (empty,
bilingual-context note) → Add provider + key → Save → pops back to Bilingual, engine
strip now "Change…"/configured → Turn on bilingual.

## Test catalogue

- `ReaderAIProvidersViewTests` — bilingual-context empty state renders the design
  copy (sparkle tile + the why-line + single CTA); the list renders providers.
- `AIProviderListView` reuse: default config keeps the globe copy (Library
  byte-identical); a supplied config renders the bilingual copy; the Add CTA still
  drives `editorContext = .add()`.
- `AIProviderEditSheet` — `onSaveSuccess` fires with `(savedID, wasAdd:true/false)`
  after a successful add/update and NOT on validation failure / cancel; default nil
  is a no-op (Library unchanged).
- `BilingualSetupSheetContainer` nav-state: "Set up" pushes the providers view;
  initial `loadProfiles()` hydration does NOT pop (Change flow); a user-driven
  activation (add-save→setActive, or row tap) pops to root and fires `onConfigured`.
- Activation correctness: a SECOND provider added during the Change flow is made
  active by the reader flow's explicit `setActive(savedID)` (regression for the
  Gate-2 Critical), distinct from `addProfile`'s first-only auto-activation.
- Engine-strip truthfulness across the gate matrix (reuse `BilingualAIReadiness` +
  `BilingualSetupSheetTests` label assertions): configured only when all 4 gates
  pass; "Set up" when AI-off / no-consent / no-key even with a saved provider.

## Risks + mitigations

- **NavigationStack inside `.sheet` + a nested modal editor + pop-to-root.**
  Mitigation: editor save-success records pending activation; the container does
  `setActive` + refresh + pop in the editor's `onDismiss` (after dismissal settles),
  not inside `save()` before `dismiss()`. Device-verify root → push → editor modal →
  save → pop.
- **Double chrome.** Root keeps `ReaderSheetChrome`; hide the system nav bar on the
  root via `.toolbar(.hidden, for: .navigationBar)` and force
  `.toolbar(.visible, for: .navigationBar)` on `ReaderAIProvidersView` (avoid the
  stickier `navigationBarHidden(true)`). Device-verify no double bar on either
  screen.
- **Strip refresh after pop.** Do NOT rely on the root sheet's `.task` re-running
  (a backgrounded NavigationStack root may not). The container calls
  `await onConfigured()` → host `refreshAIConfigured()` explicitly on activation.
- **Six-site duplication.** The shared `BilingualSetupSheetContainer` owns the
  nav/VM/activation, so each site's change is a mechanical view-type swap (5 builder
  vars + 1 inline Foliate site).
- **`AISettingsViewModel` lifecycle.** Held as `@State` in the container so it
  survives sheet re-renders; `.task { loadProfiles() }` (already in
  `AIProviderListView`) hydrates on push; `.shared` store keeps it consistent with
  the Library path.
- **Active-profile side effect.** Activating the provider also affects the AI chat
  assistant (one shared active provider) — correct, matches Library, documented.

## Backward compat

- `AIProviderListView`'s new `emptyState` param defaults to the current copy;
  `AIProviderEditSheet.onSaveSuccess` defaults nil → both Library paths
  byte-identical. No schema change (reuses `ProviderProfileStore` + keychain). No
  migration. Configured users: "Change…" lands on the same scoped list, active
  provider checked.

## Audit fixes applied (Gate-2 round 1)

| Finding | Severity | Resolution |
|---|---|---|
| `addProfile` activates only the first provider | Critical | Reader flow explicitly `setActive(savedID)` on save-success (not relying on first-only auto-activation); Library unchanged. |
| Editor has no save-success callback | High | Added default-nil `onSaveSuccess(id, wasAdd)` to `AIProviderEditSheet`; reader flow consumes it, Library passes nil. |
| Readiness needs flag + consent + key, not just provider | High | Explicit **scope boundary** section: #81 owns provider gates only; flag/consent stay the existing Library affordances (rule-51 — not invented in-reader); strip stays truthful; fresh-user wrinkle logged as a follow-up IDEA. |
| Scoped list omits AI-enable + consent that a fresh user needs | High | Same scope-boundary resolution (audit's "constrain" option): document the constraint, verify the AI-on+consented happy path, file follow-up IDEA for in-reader enable+consent. |
| `emptyStateOverride: AnyView?` wrong seam | High | Replaced with data-only `AIProviderEmptyStateConfiguration`; the list owns the Add action — no AnyView, no leaked private state. |
| Pop-to-root timing under-specified | Medium | Activation + pop run in the editor's `onDismiss`, after dismissal settles. |
| `navigationBarHidden(true)` risky | Medium | `.toolbar(.hidden, for: .navigationBar)` on root + `.toolbar(.visible,…)` on the pushed view. |
| Root `.task` may not re-run on pop | Medium | Container calls `refreshAIConfigured()` explicitly via `onConfigured`. |
| Foliate has no `bilingualSetupSheetView` builder | Low | Foliate's swap is the inline `.sheet` `BilingualSetupSheet(...)` → `BilingualSetupSheetContainer(...)` change; documented as inline, not a builder swap. |
| WI-1 dead code until WI-2 | Medium | Collapsed to a single WI / one PR. |

### Audit fixes applied (Gate-2 round 2)

| Finding | Severity | Resolution |
|---|---|---|
| `setActive(savedID)` can't reach the reader — editor sheet is constructed privately inside `AIProviderListView` | High | `AIProviderListView` gains `onEditorSaveSuccess` + `onRowActivated` params (default nil) and forwards the editor's `onSaveSuccess` through itself. The reader callbacks now actually receive the saved id. |
| Raw `activeID` observation can pop under the still-present editor | Medium | Dropped `activeID` observation entirely. Editor-save activation+pop runs from `AIProviderListView`'s `.sheet(onDismiss:)` (post-dismiss); row-tap pop runs after `setActive` completes. |
| "logged as follow-up IDEA" claim has no tracker row | Low | Reworded — the IDEA row is filed WITH the implementation PR, not pre-claimed as already-logged. |
