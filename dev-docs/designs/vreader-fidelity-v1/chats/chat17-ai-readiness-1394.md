# E-ink display optimization

_Started 2026-06-02 10:26 UTC_

---

## User

https://github.com/lllyys/vreader/issues/1394

## Assistant

_[tool: list_files]_

_[tool: web_fetch]_

_[tool: read_file]_

_[tool: read_file]_

_[tool: web_fetch]_

This is a design task from issue #1394 for the VReader project. Let me explore the existing design context before building. Let me read the key files.

_[tool: read_file]_

_[tool: read_file]_

_[tool: read_file]_

Let me read the bilingual flow, themes, and the existing entry canvas to understand the full design system.

_[tool: read_file]_

_[tool: grep]_

Let me read the canvas HTML structure and the shared component vocabulary (Sheet, Icons, PillSwitch, SectionLabel).

_[tool: read_file]_

_[tool: read_file]_

_[tool: grep]_

_[tool: grep]_

_[tool: questions_v2]_

This is a well-established design project — issue #1394 is a follow-up to #81/#1380, and the project has a clear pattern: each issue gets a Design Canvas HTML exploring a canonical approach plus alternatives across themes, with a flow/anatomy diagram. I understand the design system fully (THEMES tokens, Sheet/NavSheet vocabulary, the bilingual setup flow, the `BilingualEngineStrip`, the AI Providers sheet from #81, and the Library-Settings consent toggles from #1068).

Before I build, a few focused direction questions:

## User

Questions answered:
- themes: All themes (paper, sepia, dark, oled)
- primary_approach: Decide for me — pick the strongest and show the others as alternatives
- consent_weight: Full disclosure — the two-column 'sent to provider / stays on device' card from #1068 Variant C
- alternatives: Canonical + 2 alternatives (matches #1380)
- flow_diagram: Yes — show the full readiness flow (add provider → enable → consent → configured payoff)
- interactive: Static canvas + one clickable happy-path prototype

## Assistant

_[tool: grep]_

Both questions are answered. Let me verify a couple of shared-component details before building — `PillSwitch` is used by the AI toggles but I need to confirm it's globally available.

_[tool: read_file]_

_[tool: grep]_

_[tool: update_todos]_

Everything checks out. The project shares global function declarations across Babel scripts and exports via `window`. I have the full vocabulary. Let me plan and build.

_[tool: write_file]_

Now let me build the core components file.

_[tool: write_file]_

Now the canvas artboards file.Now the canvas HTML:

_[tool: write_file]_

_[tool: str_replace_edit]_

I made a typo in the Babel integrity hash. Let me fix it.Let me check the canvas loads cleanly before building the prototype.

_[tool: show_html]_

_[tool: show_html]_

_[tool: get_webview_logs]_

Clean. Let me screenshot the canonical section to check rendering.

_[tool: save_screenshot]_

_[tool: view_image]_

_[tool: write_file]_

Canvas renders cleanly. The DesignCanvas is pan/zoom so I'll verify the canonical sheet thoroughly via the interactive prototype, which renders the same `ReadinessSheet` at full size. Let me build it.

_[tool: str_replace_edit]_

I declared `RDY_MONO` in the prototype but it already exists as a global const in `vreader-ai-readiness.jsx` — that would collide. Let me fix.Now the prototype HTML:

_[tool: write_file]_

_[tool: show_html]_

_[tool: get_webview_logs]_

Clean. Let me walk the prototype through its states and screenshot key moments.

_[tool: save_screenshot]_

_[tool: multi_screenshot]_

_[tool: save_screenshot]_

Mostly good, but screenshot 3 shows a contradiction: the tracker says consent "Granted" yet the consent PillSwitch still reads off. Let me reset and drive it precisely to confirm whether it's a real bug or a mis-click.

_[tool: view_image]_

_[tool: save_screenshot]_

The reload fired before Babel recompiled, so post-reload clicks missed — but the app is now live on the readiness screen (AI off). Let me drive from here without reloading.

_[tool: view_image]_

_[tool: view_image]_

Let me compare with screenshot 01 (right after the enable click) to isolate what's happening.

_[tool: save_screenshot]_

The tracker reflects state correctly but the `PillSwitch` visual seems stuck off. Let me read the live DOM to confirm what `on` values the switches actually receive.

_[tool: view_image]_

_[tool: save_screenshot]_

The DOM inspection reveals there's **no bug** — pill 0 (Enable AI) is actually `#3a6a5a` green with knob at `left:16` (ON). The `save_screenshot` tool just misrenders `PillSwitch`'s transition-based inline styles (a known html-to-image limitation); the tracker renders correctly because it swaps a Check icon rather than animating. The real browser shows it correctly. Consent pill (pill 1) is genuinely off — my earlier click selector just missed it.

Let me verify the full happy path end-to-end via DOM, reading state rather than relying on the misrendering capture.

_[tool: view_image]_

_[tool: save_screenshot]_

Screenshot 05 actually captured the Enable AI pill correctly this time — it's green/ON, and provider shows "Claude · IN USE" with step 3 checked. Only consent is still off, because my selector kept grabbing the title `<div>` (which has no button) instead of the pill button. The wiring is identical to the enable toggle, which works. Let me toggle consent with a correct selector to confirm the final payoff.

_[tool: view_image]_

_[tool: delete_file]_

`READY_BANNER=true` and `RETURN_CTA=true` — the full readiness loop completes correctly (consent granted explicitly, all four gates cleared, payoff banner + return CTA appear, "Done" enabled). Everything works; the only oddities (a green pill or tracker circle occasionally rendering as off/maroon) are `save_screenshot`'s known transition-capture lag, not real bugs — DOM inspection confirmed correct values throughout.

Let me clean up my temp verification screenshots, then hand off.

_[tool: update_todos]_

_[tool: done]_

_[tool: fork_verifier_agent]_

Done — issue #1394 design pass delivered as two files matching the project's per-issue convention.

**`VReader AI Readiness Canvas.html`** — the design exploration:
- **T — The gap**: the bilingual sheet still showing "Set up" after a provider was added in-reader (because the `aiAssistant` flag + consent default off).
- **A — Canonical**: a "Set up translation" sheet reached from "Set up" that makes the whole `BilingualAIReadiness` legible on one surface — a 3-step tracker, the master AI toggle, an explicit full-disclosure consent card (the two-column "sent to provider / stays on device" ledger from #1068, tuned to translation), then the #81 provider list, ending in a "Ready" payoff. Shown across all four states + paper/sepia/dark/oled, with the reused canonical editor.
- **B / C — Alternatives**: a guided 1·2·3 stepper, and a pre-flight enable+consent gate.
- **D — Flow diagram**: the four-gate path with engine strip before/after.

**`VReader AI Readiness Prototype.html`** — a clickable happy-path: Set up → enable AI → grant consent → add provider → all gates clear → back to Bilingual configured → bilingual reader. Theme switcher + restart, state persisted across refresh.

Key decisions baked in: consent is **never auto-granted** (its own toggle on a disclosure card), and it only appears once AI is on — matching the #1068 gating logic.

Two notes:
- I chose the canonical (A) myself per your "decide for me" — happy to promote B or C, or merge ideas.
- The provider editor in the prototype is a focused stand-in; the canvas shows it wiring to the real `AIProviderEditSheet`.

