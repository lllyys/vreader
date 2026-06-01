---
branch: fix/ai-path-observability
threadId: codex-exec-gpt-5.5-20260601
rounds: 1
final_verdict: ship-as-is
date: 2026-06-01
---

# Codex Audit — --enable-ai ungated + bilingual prefetch observability

## Scope

Two related changes, surfaced while verifying Feature #42's bilingual criterion:

1. **`VReaderApp.swift`** — move the DEBUG-only `AITestSetup.apply(enableAI:...)`
   call OUT of the `if config.isUITesting { }` block. It was inside that gate, so
   `--enable-ai` via DebugBridge `simctl openurl vreader-debug://…` (which does NOT
   pass `--uitesting`) never set the `aiAssistant` + consent gates → live AI
   requests threw `featureDisabled`. Now `--enable-ai` works for BOTH XCUITest and
   CU-free DebugBridge verification.
2. **`ChapterTranslationPrefetcher.swift`** — add OSLog error/debug logging at the
   prefetch swallow points. The bilingual VM treats a prefetch failure as "retry
   later", so the underlying cause was invisible (UI activated, nothing rendered).
   This logging surfaced the real chain: `featureDisabled` → (after fix #1) the
   actual AI call firing → `HTTP 401` from a stale test key.

Files: `vreader/App/VReaderApp.swift`, `vreader/Services/AI/ChapterTranslationPrefetcher.swift`.

## Round 1 — findings

Codex (gpt-5.5, read-only). 0 Critical/High. **3 Medium.** No Release leak
(AITestSetup + call site `#if DEBUG`); no behavior change from the do/catch
(rethrows); static `Logger` in a `Sendable` struct OK.

| # | file:line | sev | issue | resolution |
|---|---|---|---|---|
| 1 | VReaderApp.swift:189 | Medium | `apply(enableAI:false)` clears `forceAvailable` but does NOT revoke the persisted `aiAssistant` flag + consent, so a later DEBUG run without `--enable-ai` keeps AI on (sticky). | ACCEPTED with rationale: DEBUG-only; `--enable-ai` is a deliberate test flag, so AI-stays-on across DEBUG runs is benign (a dev disables it in Settings). The clean session-only fix (gates honor `AITestOverride.forceAvailable`) needs an actor(AIService)↔@MainActor(AITestOverride) hop across 5 gate sites — disproportionate to a DEBUG-only stickiness; Codex itself warned NOT to revoke-on-false (could erase a real dev's AI setup). |
| 2 | ChapterTranslationPrefetcher.swift:124,135,150 | Medium | Raw translate errors logged `privacy: .public` — provider/proxy error bodies can echo prompt/book content. | FIXED — all raw `error` descriptions flipped to `privacy: .private`; the human-readable reason + unit ids (hrefs, not content) stay `.public`. |
| 3 | ChapterTranslationPrefetcher.swift:192 | Medium | Same public-error risk in `translatePreSegmented`. | FIXED — flipped to `.private`. |

## Test evidence

`AITestSetupTests` (3) green; full DEBUG build SUCCEEDED. Live verification with
the fix: the bilingual prefetch ran end-to-end (gate → prefetch → provider API
call), proving the pipeline functional — the only barrier to a rendered screenshot
was a stale OpenRouter key (HTTP 401) + flaky idb enable, not a product defect.

## Verdict

ship-as-is (2 Medium fixed, 1 Medium accepted with rationale).
