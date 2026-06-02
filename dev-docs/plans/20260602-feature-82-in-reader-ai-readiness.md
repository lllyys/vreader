# Feature #82 — In-reader AI-enable + consent readiness affordance (Gate-1 plan)

Make the full `BilingualAIReadiness` gate satisfiable **inside the reader**: extend
the scoped sheet reached from the bilingual engine strip's "Set up" (Feature #81)
into a **readiness container** — a 3-step tracker + the `aiAssistant` master toggle +
an explicit consent disclosure card + the reused #81 provider list + a "ready"
payoff. The capstone of the AI-gating cluster: one surface that **Feature #82**,
**Bug #308** (bottom-bar AI button no-op), and **Bug #301**'s deferred routing slice
all resolve to.

- **Design (binding, Variant A)**: `dev-docs/designs/vreader-fidelity-v1/project/design-notes/reader-ai-readiness.md`, component `vreader-ai-readiness.jsx` (resolves needs-design #1394).
- **Status target**: `TODO` → `PLANNED` (after Gate-2) → `IN PROGRESS` → `DONE` → `VERIFIED`.

## Revision history / audit rounds

- **v1** (Gate-1 draft).
- **v2** (Gate-2 round 1 — Codex gpt-5.5/high): verdict NEEDS REVISION; 1 Critical, 2
  High, 4 Medium. All addressed — see **Audit fixes applied (Gate-2 round 1)** at the
  bottom.
- **Gate 2 PASSED** (round 2 — Codex gpt-5.5/high): verdict **READY TO BUILD**, zero
  open Critical/High/Medium; all 7 round-1 findings RESOLVED; buildability spot-check
  (generation-token recompute, async-availability-cached-read-sync bridge for #308,
  no @MainActor/Sendable hazard) confirmed sound. 2 rounds.

## Problem

`BilingualAIReadiness.resolve` requires **all four** gates: `aiAssistant` flag ON +
AI consent granted + an active provider profile + that profile's non-empty key. On a
fresh device the flag + consent default **OFF** (Feature #81 scope boundary), so a
user who adds a provider in-reader via #81 STILL sees "Set up." This closes that loop
inside the reader, and gives the same surface to Bug #308 (AI button) and Bug #301.

## Prior art / project precedent / rejected alternatives

- **Reuse `AISettingsViewModel` for the flag + consent.** `var isAIEnabled` (didSet →
  `featureFlags.setOverride(_, for: .aiAssistant)`) + `var hasConsent` (get/set →
  `AIConsentManager.grantConsent()/revokeConsent()`) — both bindable
  (`$viewModel.isAIEnabled`, already bound at `AISettingsSection.swift:87`). No new VM
  API for the toggles.
- **Reuse #81's provider list + editor + flow.** `AIProviderListView`,
  `AIProviderEditSheet`, `ReaderAIProvidersFlow`, `BilingualSetupSheetContainer`.
- **Mirror #301's async-gate-cached-into-state pattern.** `BilingualReadingViewModel.aiConfigured`
  is an async-resolved (`BilingualAIReadiness.resolve`) bool cached into observed state
  + refreshed via `.task`. The readiness model uses the same shape (async resolve →
  cached, generation-guarded).
- **Reuse the #1068 consent ledger vocabulary.** Two-column "Sent to provider / Stays
  on device" (`vreader-ai-toggles.jsx` Variant C).
- **Design rejects** B (guided stepper — order-forces every visit) and C (pre-flight
  gate — front-loads privacy). Variant A (one scoped sheet, gates clear in any order).

### Consent-safety invariant (narrowed — Gate-2 round 1)
Consent is granted elsewhere by other EXPLICIT paths (`AIAssistantView`,
`AISummaryTabView`, and DEBUG `AITestSetup` under `--enable-ai`). The invariant THIS
feature owns is narrow: **this readiness flow must never call `grantConsent()` except
from the consent card's own toggle** — NOT from AI-enable, provider save, row
activation, the readiness `onAppear`/recompute, or the auto-pop. Pinned by tests.
(Verification consequence: do NOT use `--enable-ai` for the consent-safety check — it
auto-grants; reset consent defaults and drive the toggle explicitly.)

## Surface area (file-by-file)

### New
- **`vreader/Views/Reader/Bilingual/ReaderAIReadinessModel.swift`** — `@MainActor
  @Observable` model owning the readiness recompute (Gate-2 fixes #6/#7: staleness +
  async races). Holds the four gate states (`aiEnabled`, `hasConsent`,
  `hasActiveProvider`, `hasKey`) + a cached `isReady`. `recompute()` runs the async
  `BilingualAIReadiness.resolve` (+ the individual gate reads) under a **generation
  token** so a stale async result can't overwrite a newer one; called on appear and
  after every toggle/save/activation. Records `startedReady` (the readiness at first
  recompute) so auto-pop fires ONLY on an in-session not-ready→ready transition —
  NOT when a configured user opens it (the Change flow). Wraps the #81
  `ReaderAIProvidersFlow` (provider activation/pop) or absorbs it.
- **`vreader/Views/Reader/Bilingual/ReadinessTracker.swift`** — the 3-gate progress
  row (`Turn on AI` · `Allow data` · `Add provider`), each `done/active/todo` from the
  model's gate states (the key gate rides inside the provider gate).
- **`vreader/Views/Reader/Bilingual/ReadinessRows.swift`** — `EnableAIRow` (brand tile
  + `PillSwitch` bound to `isAIEnabled`), `ConsentDisclosureCard` (shield tile +
  explicit toggle bound to `hasConsent` + the two-column ledger; rendered only when AI
  on), `ReadyBanner` (all-gates-cleared payoff, "Go back to turn on bilingual mode").
  Reuse `PillSwitch` + the `SettingsToggleRow` tile idiom.
- **`vreader/Views/Reader/Bilingual/ReaderAIReadinessView.swift`** — composes
  `ReadinessTracker` → `EnableAIRow` → `ConsentDisclosureCard` (when AI on) → the
  reused `AIProviderListView` → `ReadyBanner` (when ready), bound to the model +
  `AISettingsViewModel`. Pushed inside the bilingual sheet's NavigationStack.
- **`vreader/Views/Reader/Bilingual/ReaderAIReadinessSheet.swift`** (Gate-2 fix #4) —
  a standalone wrapper for the **Bug #308 AI-button entry**: its OWN `@State` model +
  `NavigationStack` + an explicit `onReady`/dismiss path (so it doesn't depend on the
  bilingual `NavigationStack`'s `showingProviders`). Hosts `ReaderAIReadinessView`.

### Modified
- **`vreader/Views/Reader/Bilingual/BilingualSetupSheetContainer.swift`** — change the
  `.navigationDestination` push target from `ReaderAIProvidersView` to
  `ReaderAIReadinessView`. The #81 `ReaderAIProvidersView` is **removed/absorbed**
  (only this container references it; the readiness view supersedes it, still hosting
  `AIProviderListView` for the list section).
- **`vreader/Views/Reader/Bilingual/ReaderAIProvidersFlow.swift`** — the pop logic
  moves into / is gated by the readiness model (Gate-2 fixes #1-row & #2):
  - Row activation + editor-save: after `setActive`, **recompute readiness** and
    pop ONLY when `isReady` is true (a row may be active but key-less / not-ready —
    `BilingualAIReadiness` correctly false); otherwise stay on the view and surface
    the unmet gate. (#81's unconditional row pop is replaced by ready-gated pop.)
  - Auto-pop on a not-ready→ready transition only when `!startedReady` (Change flow
    never auto-pops on appear).
- **`vreader/Services/AI/AIReaderAvailability.swift`** + **the AI-panel availability
  gate** (Gate-2 **Critical** — Bug #308's real fix). `isAvailable` /
  `hasAPIKey` reads the LEGACY `AIService.apiKeyAccount`, NOT the active provider's
  per-profile key — so a user readied via this flow (per-profile key, no legacy key)
  still fails the gate and the AI button loops back forever. Align the AI-panel
  availability to the **active-provider per-profile** gate (mirror
  `BilingualAIReadiness` / what `AIService.sendRequest` actually uses). Because the
  active-provider lookup is async, resolve it once into a cached observed bool
  (the #301 `aiConfigured` pattern) that the button render + `onAI` read
  synchronously, refreshed on appear / after readiness changes. Keep the legacy key
  as a fallback (older single-key installs) so existing configured users don't
  regress.
- **`vreader/Views/Reader/ReaderContainerView.swift`** (Bug #308) — `onAI` currently
  no-ops when `!isAIAvailable`. Add a `@State showAIReadiness` + `.sheet` presenting
  `ReaderAIReadinessSheet`; route the unavailable branch there. When the readiness
  sheet reaches ready, dismiss it (and optionally open the AI panel) — the
  now-aligned availability gate makes the next AI-button tap open the panel.
- **`docs/bugs.md`** — Bug #308 (BLOCKED → fixed-by-#82) + Bug #301 rows updated when
  the routing + availability fix land.

### Files OUT of scope
- Library `SettingsView → AI` section; `AIProviderEditSheet` internals; the bilingual
  pipeline + `BilingualAIReadiness.resolve` logic (reused). Variants B + C.

## Work-item sequencing

- **WI-1 (behavioral) — the readiness container + model.**
  `ReaderAIReadinessModel` (generation-guarded recompute, `startedReady`),
  `ReadinessTracker`, `ReadinessRows`, `ReaderAIReadinessView`; rewire
  `BilingualSetupSheetContainer` to push it; the ready-gated + initial-ready-aware
  pop. The bilingual "Set up"/"Change…" entry (wired in #81) now lands on the full
  readiness flow — **independently valuable + mergeable** before WI-2.
- **WI-2 (behavioral, final) — Bug #308 entry + the availability-gate alignment +
  device verification.** Align `AIReaderAvailability`/AI-panel gate to the
  active-provider per-profile key (the Critical — without it #308 isn't fixed); the
  standalone `ReaderAIReadinessSheet`; route `ReaderContainerView.onAI` unavailable →
  it. Device-verify the full enable→consent→add→ready flow (bilingual entry) + the
  AI-button entry + the readied-user AI-button-opens-panel regression.

## Test catalogue

- `ReadinessTrackerTests` — gate states → step states (todo/active/done); first-not-
  done is active; all-done → done.
- `ReaderAIReadinessModelTests` — (a) toggling AI on surfaces the consent card; (b)
  **consent is false until its own toggle** — AI-on / provider-save / row-activation /
  `recompute` / auto-pop NEVER call `grantConsent()`; (c) all-four-gates → `isReady`;
  (d) **Change flow (startedReady) does NOT auto-pop on appear**; an in-session
  not-ready→ready transition DOES; (e) row tap on a key-less active provider does NOT
  pop (not ready); (f) **async-race/staleness**: rapid AI off after ready, consent
  revoke after provider save, empty-key save, concurrent profile deletion while
  resolving — generation token discards stale results.
- `AIReaderAvailabilityTests` (Critical regression) — per-profile key present + no
  legacy key + flag + consent → `isAvailable` true (AI button opens panel); legacy-key
  fallback still works; none → false.
- Bug #308 route test — `onAI` presents the readiness sheet when unavailable (not a
  no-op).
- Reuse `ReaderAIProvidersFlowTests`, `BilingualAIReadiness` tests,
  `AISettingsViewModelTests`.

## Risks + mitigations

- **Bug #308 not actually fixed (Critical).** Mitigation: WI-2 aligns the AI-panel
  availability gate to the active-provider per-profile key; regression test pins
  readied-user → panel opens.
- **Change-flow auto-pop.** Mitigation: `startedReady` — no auto-pop on initial ready;
  pop only on in-session transition or explicit ready-gated row-tap/save.
- **Async readiness races / consent staleness.** Mitigation: generation-token-guarded
  `recompute()` in the model; recompute on appear + after every write; tests for the
  race set.
- **Consent auto-grant.** Mitigation: narrowed invariant + tests; consent only via its
  toggle; don't verify with `--enable-ai`.
- **#81 `ReaderAIProvidersView` churn.** Only `BilingualSetupSheetContainer`
  references it; absorbing it into the readiness view is mechanical.
- **Standalone #308 entry @State lifecycle.** Mitigation: `ReaderAIReadinessSheet`
  owns its `@State` model + NavigationStack (not the bilingual one); device-verify.
- **File size** — split tracker/rows/view/model/sheet into separate files (<300 each).

## Backward compat

- No schema change (reuses `ProviderProfileStore`, `AIConsentManager`, `FeatureFlags`,
  keychain). No migration. The Library AI path is untouched; the in-reader sheet
  writes the same global flag + consent + provider store, so state is consistent.
  Existing single-legacy-key installs keep working via the availability-gate fallback.
  Configured users see all gates green + the provider list (Change flow), no auto-pop.

## Audit fixes applied (Gate-2 round 1)

| Finding | Severity | Resolution |
|---|---|---|
| `AIReaderAvailability` reads legacy key → #308 not fixed | Critical | WI-2 aligns the AI-panel availability gate to the active-provider per-profile key (async-resolved + cached, #301 pattern); legacy fallback kept; regression test. |
| All-gates auto-pop breaks #81 Change flow | High | `ReaderAIReadinessModel.startedReady` — auto-pop only on in-session not-ready→ready; no pop on initial-ready appear. |
| Row activation pops unconditionally | High | Pop is ready-gated — recompute `BilingualAIReadiness` after activation/save, pop only when `isReady`. |
| Standalone #308 entry needs own flow | Medium | New `ReaderAIReadinessSheet` wrapper with own `@State` model + NavigationStack + onReady. |
| "Consent is the ONLY writer" overstated | Medium | Narrowed to "this flow never grants except via its toggle"; verification note (don't use `--enable-ai`). |
| `hasConsent` is a UserDefaults pass-through (staleness) | Medium | Model owns the readiness snapshot + recomputes on appear/after writes. |
| Async stale-result hazards | Medium | Generation-token-guarded `recompute()`; race tests. |
