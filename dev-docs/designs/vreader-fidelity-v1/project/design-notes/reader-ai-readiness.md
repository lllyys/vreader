# In-reader AI-enable + consent readiness affordance (#1394 · Feature #82)

> Source of truth (design): `VReader AI Readiness Canvas.html` → `ai-readiness-artboards.jsx` + `vreader-ai-readiness.jsx` (+ a clickable happy-path `VReader AI Readiness Prototype.html`).
> Chat transcript: `chats/chat17-ai-readiness-1394.md`.
> Resolves needs-design [#1394](https://github.com/lllyys/vreader/issues/1394) (Feature **#82**). Follow-up to Feature #81 (#1380, in-reader provider entry) and Bug #301 (truthful engine strip).
> Status: **design landed — implementation deferred** (recorded, not built; Swift held for a separate go-ahead per the handoff convention).

## The gap

`BilingualAIReadiness` requires **all four gates**: `FeatureFlags.aiAssistant` ON · explicit
consent (`AIConsentManager.hasConsent`) · a provider profile · that profile's API key.
Feature #81 lets a user **add a provider** in-reader — but on a fresh device the **flag and
consent default OFF**, so adding a provider *alone* leaves readiness false and the bilingual
engine strip correctly still shows **"Set up."** Today the only way to flip the flag + grant
consent is a trip to Library → Settings → AI. This closes that loop **inside the reader**.

This is the **capstone of the AI-gating cluster** — the surface every "AI unconfigured"
silent-no-op should route to: Bug #301 (bilingual "Set up" routing), Bug #308 (bottom-bar AI
button no-op), and the gate behind Bug #306 (cache) all resolve to *this* readiness flow.

## Decision (binding) — Variant A: "Set up translation" readiness sheet

Reached from the bilingual engine strip's **"Set up"**. One scoped sheet makes the whole
`BilingualAIReadiness` legible and satisfiable top-to-bottom:

1. **3-step tracker** — *Turn on AI · Allow data · Add provider* — doubles as the explainer
   ("why am I still seeing Set up?") by showing exactly which gates remain. Each clears with a
   check as it's satisfied.
2. **Master AI toggle** (`aiAssistant` flag) — the first gate, satisfied in place.
3. **Explicit full-disclosure consent card** — the two-column **"sent to provider / stays on
   device"** ledger from #1068 (Variant C), tuned to translation. **Consent is NEVER
   auto-granted** — it has its own toggle, and the card only **appears once AI is on** (matches
   the #1068 gating logic).
4. **Provider step** — reuses the canonical `AIProviderEditSheet` (#81/#1363) **unchanged**
   (provider + key); on save it becomes the bilingual engine.
5. **"Ready" payoff** — all four gates cleared → the engine strip flips to **"Claude ·
   configured / Change…"**, ready to turn on bilingual. The user lands back where they started
   with the blocker removed.

Covered across **paper / sepia / dark / oled**, all four gate states, plus the reused editor.

### Rejected alternatives (explored in the canvas)
- **B · guided 1·2·3 stepper** — clear for a first-timer, but **order-forces every visit**: a
  returning user who only lacks consent still walks the whole rail, and step 3 re-presents the
  #81 editor mid-flow.
- **C · pre-flight enable+consent gate** — demands both switches before the provider list is
  reachable. One tidy consent moment, but it **front-loads privacy before the user has
  committed** to anything, and re-gates returning users who already granted it.

## Production wiring (deferred — do NOT build without go-ahead)

- New `ReaderAIReadinessSheet` (or extend the #81 `ReaderAIProvidersView` into a readiness
  container) presented from `BilingualSetupSheet.onOpenSettings` (currently the deferred slice
  of Bug #301). It hosts: the tracker, the `aiAssistant` master toggle (`FeatureFlags`), the
  consent card (`AIConsentManager.grantConsent` on its own toggle, shown only when AI on), and
  the #81 provider list (`AIProviderEditSheet` reused).
- On all-four-cleared: set the saved provider as the bilingual engine and pop back to Bilingual
  with the strip reading "configured / Change…".
- The same readiness sheet is the route target for **Bug #308** (bottom-bar AI button) and the
  bilingual "Set up"/"Change…" (Feature #81). One surface, multiple entry points.
- `aiConfigured`/readiness derives from `BilingualAIReadiness.resolve` (already mirrors the live
  `AIService` gate per the #301 fix). Rule 51 satisfied (this note + canvas are the committed
  design).
